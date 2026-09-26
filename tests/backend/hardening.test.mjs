// Regression tests for the adversarial review (supabase/migrations/20260926000500_hardening.sql).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  anonClient, adminClient, newUser, draftFor, send, upload, photoPath, db, sleep, BUCKET, TINY_JPEG,
} from './helpers.mjs';

let alice, bob, sql;

before(async () => {
  [alice, bob] = await Promise.all([newUser('halice'), newUser('hbob')]);
  sql = await db();
});

after(async () => {
  await sql?.end();
  for (const u of [alice, bob]) await u?.client.removeAllChannels();
});

const swapped = Buffer.concat([TINY_JPEG, Buffer.from('SWAPPED')]);

// Mimic the Storage API's own deletes: service role, with storage's direct-delete guard lifted.
async function storageApiConnection() {
  const c = await db();
  await c.query("set role service_role");
  await c.query("select set_config('storage.allow_delete_query', 'true', false)");
  return c;
}

async function download(client, path) {
  const { data, error } = await client.storage.from(BUCKET).download(path);
  if (error) throw error;
  return Buffer.from(await data.arrayBuffer());
}

test('a signed upsert URL minted before sending cannot swap the sent photo', async () => {
  const draftId = randomUUID();
  const path = photoPath(alice.user.id, draftId);
  const signed = await alice.client.storage.from(BUCKET).createSignedUploadUrl(path, { upsert: true });
  assert.equal(signed.error, null, 'minting is allowed before the object exists');
  assert.equal((await upload(alice.client, path)).error, null);
  const sent = await send(alice.client, {
    p_recipient_id: bob.user.id, p_sender_name: 'Alice', p_recipient_name: 'Bob', p_destination: '',
    p_message: 'original photo', p_photo_path: path, p_client_request_id: draftId,
  });
  assert.equal(sent.error, null);

  const swap = await alice.client.storage.from(BUCKET).uploadToSignedUrl(path, signed.data.token, swapped, { contentType: 'image/jpeg', upsert: true });
  assert.ok(swap.error, 'overwrite through the pre-minted token is refused');
  assert.deepEqual(await download(bob.client, path), TINY_JPEG, 'recipient still gets the original bytes');
});

test('signed upsert URLs cannot overwrite an unsent draft either (upload once)', async () => {
  const path = photoPath(alice.user.id, randomUUID());
  const signed = await alice.client.storage.from(BUCKET).createSignedUploadUrl(path, { upsert: true });
  assert.equal((await upload(alice.client, path)).error, null);
  const swap = await alice.client.storage.from(BUCKET).uploadToSignedUrl(path, signed.data.token, swapped, { contentType: 'image/jpeg', upsert: true });
  assert.ok(swap.error);
  assert.deepEqual(await download(alice.client, path), TINY_JPEG);
});

test('objects cannot be moved or copied over a sent photo', async () => {
  const args = await draftFor(alice, bob.user.id);
  assert.equal((await send(alice.client, args)).error, null);
  const moved = await alice.client.storage.from(BUCKET).move(args.p_photo_path, photoPath(alice.user.id, randomUUID()));
  assert.ok(moved.error, 'move refused');
  const other = photoPath(alice.user.id, randomUUID());
  await upload(alice.client, other);
  const copy = await alice.client.storage.from(BUCKET).copy(other, args.p_photo_path);
  assert.ok(copy.error, 'copy onto a sent path refused');
  assert.deepEqual(await download(bob.client, args.p_photo_path), TINY_JPEG);
});

test('the service role (orphan cleanup) cannot delete a sent photo; it can delete an orphan', async (t) => {
  if (!process.env.SUPABASE_SECRET_KEY) return t.skip('SUPABASE_SECRET_KEY not set');
  const admin = adminClient();
  const args = await draftFor(alice, bob.user.id);
  assert.equal((await send(alice.client, args)).error, null);
  const orphan = photoPath(alice.user.id, randomUUID());
  await upload(alice.client, orphan);

  const removed = await admin.storage.from(BUCKET).remove([args.p_photo_path, orphan]);
  assert.equal(removed.error, null);
  assert.deepEqual(removed.data.map((o) => o.name), [orphan], 'only the orphan is removed');
  assert.deepEqual(await download(bob.client, args.p_photo_path), TINY_JPEG, 'sent photo still downloads');
});

test('a delete racing send_postcard waits and then keeps the photo', async () => {
  // Connection A sends inside an open transaction (holding the photo row lock);
  // connection B, as the service role, tries to delete the photo meanwhile.
  const draftId = randomUUID();
  const path = photoPath(alice.user.id, draftId);
  await upload(alice.client, path);
  const a = await db();
  const b = await storageApiConnection();
  try {
    await a.query('begin');
    await a.query("select set_config('role', 'authenticated', true), set_config('request.jwt.claims', $1, true)",
      [JSON.stringify({ sub: alice.user.id, role: 'authenticated' })]);
    await a.query('select public.send_postcard($1, $2, $3, $4, $5, $6, $7)',
      [bob.user.id, 'Alice', 'Bob', '', 'race', path, draftId]);

    let deleteDone = false;
    const deletion = b.query("delete from storage.objects where bucket_id = $1 and name = $2", [BUCKET, path])
      .then((r) => { deleteDone = true; return r; });
    await sleep(700);
    assert.equal(deleteDone, false, 'delete waits for the in-flight send');
    await a.query('commit');
    const result = await deletion;
    assert.equal(result.rowCount, 0, 'delete skips the now-sent photo');
    const { rows } = await sql.query('select count(*)::int as n from storage.objects where bucket_id = $1 and name = $2', [BUCKET, path]);
    assert.equal(rows[0].n, 1);
  } finally {
    await a.end();
    await b.end();
  }
});

test('a delete that wins the race makes the send fail cleanly with photo_missing', async () => {
  const draftId = randomUUID();
  const path = photoPath(alice.user.id, draftId);
  await upload(alice.client, path);
  const b = await storageApiConnection();
  try {
    await b.query('begin');
    const del = await b.query('delete from storage.objects where bucket_id = $1 and name = $2', [BUCKET, path]);
    assert.equal(del.rowCount, 1);
    const sending = send(alice.client, {
      p_recipient_id: bob.user.id, p_sender_name: 'Alice', p_recipient_name: 'Bob', p_destination: '',
      p_message: 'race', p_photo_path: path, p_client_request_id: draftId,
    });
    await sleep(500);
    await b.query('commit');
    const { error } = await sending;
    assert.equal(error?.code, 'PT422');
    assert.equal(error?.hint, 'photo_missing');
  } finally {
    await b.end();
  }
});

test('whitespace-only messages are rejected (any Unicode space)', async () => {
  for (const message of ['\n\n\t ', ' 　']) {
    const { error } = await send(alice.client, await draftFor(alice, bob.user.id, { p_message: message }));
    assert.equal(error?.code, 'PT422', JSON.stringify(message));
  }
});

test('an omitted recipient returns PT422, not PGRST202', async () => {
  const args = await draftFor(alice, bob.user.id);
  delete args.p_recipient_id;
  const { error } = await send(alice.client, args);
  assert.equal(error?.code, 'PT422');
});

test('realtime publishes inserts only, and anonymous clients receive nothing', async () => {
  const { rows } = await sql.query("select pubinsert, pubupdate, pubdelete from pg_publication where pubname = 'supabase_realtime'");
  assert.deepEqual(rows[0], { pubinsert: true, pubupdate: false, pubdelete: false });

  const anon = anonClient();
  const events = [];
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no subscription ack')), 20000);
    anon.channel(`anon-${randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'postcards' }, (p) => events.push(p))
      .on('system', {}, (p) => { if (p?.extension === 'postgres_changes') { clearTimeout(timer); resolve(); } })
      .subscribe((status, err) => { if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') { clearTimeout(timer); reject(err ?? new Error(status)); } });
  });
  assert.equal((await send(alice.client, await draftFor(alice, bob.user.id))).error, null);
  await sleep(2500);
  assert.equal(events.length, 0, `anon received ${JSON.stringify(events).slice(0, 200)}`);
  await anon.removeAllChannels();
});

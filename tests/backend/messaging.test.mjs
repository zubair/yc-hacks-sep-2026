// End-to-end checks against a local Supabase stack through the real Auth, REST, Storage and
// Realtime APIs, with three identities: sender (alice), recipient (bob), outsider (eve).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import {
  anonClient, newUser, draftFor, send, upload, photoPath, db, sleep, BUCKET, TINY_JPEG,
} from './helpers.mjs';

let alice, bob, eve, sql;

before(async () => {
  [alice, bob, eve] = await Promise.all([newUser('alice'), newUser('bob'), newUser('eve')]);
  sql = await db();
});

after(async () => {
  await sql?.end();
  for (const u of [alice, bob, eve]) await u?.client.removeAllChannels();
});

const MESSAGE_KEYS = ['conversation_id', 'created_at', 'destination', 'id', 'message', 'photo_path',
  'recipient_id', 'recipient_name', 'sender_id', 'sender_name'];

// ---------- profiles and directory ----------

test('signup creates a normalized profile from metadata', async () => {
  const { data, error } = await alice.client.from('profiles').select('*');
  assert.equal(error, null);
  assert.equal(data.length, 1, 'only your own profile is visible');
  assert.equal(data[0].id, alice.user.id);
  assert.equal(data[0].username, alice.username);
  assert.equal(data[0].display_name, 'Alice');
  assert.equal('email' in data[0], false);
});

test('signup with invalid or duplicate username is rejected', async () => {
  const bad = await anonClient().auth.signUp({
    email: `bad_${randomUUID()}@postcard.test`, password: 'local-test-password-1',
    options: { data: { username: 'No Spaces!', display_name: 'Bad' } },
  });
  assert.ok(bad.error, 'invalid username must fail signup');
  const dup = await anonClient().auth.signUp({
    email: `dup_${randomUUID()}@postcard.test`, password: 'local-test-password-1',
    options: { data: { username: alice.username.toUpperCase(), display_name: 'Dup' } },
  });
  assert.ok(dup.error, 'case-insensitive duplicate username must fail signup');
});

test('lookup_recipient: exact, case-insensitive, returns only id/username/display_name', async () => {
  const { data, error } = await alice.client.rpc('lookup_recipient', { p_username: `  ${bob.username.toUpperCase()} ` });
  assert.equal(error, null);
  assert.deepEqual(Object.keys(data).sort(), ['display_name', 'id', 'username']);
  assert.equal(data.id, bob.user.id);
  const partial = await alice.client.rpc('lookup_recipient', { p_username: bob.username.slice(0, -1) });
  assert.equal(partial.data, null, 'prefix must not match');
  const unknown = await alice.client.rpc('lookup_recipient', { p_username: 'nobody_here_zz' });
  assert.equal(unknown.error, null);
  assert.equal(unknown.data, null);
});

test('anonymous callers cannot use any RPC or read tables', async () => {
  const anon = anonClient();
  for (const [fn, args] of [['lookup_recipient', { p_username: bob.username }], ['list_conversations', {}],
    ['send_postcard', { p_recipient_id: bob.user.id }]]) {
    const { error } = await anon.rpc(fn, args);
    assert.ok(error, `${fn} must fail for anon`);
  }
  const { data } = await anon.from('postcards').select('*');
  assert.ok(!data || data.length === 0);
  const orphans = await alice.client.rpc('list_orphan_photos', {});
  assert.ok(orphans.error, 'list_orphan_photos is service-role only');
});

test('only the owner edits a profile, and only username/display_name', async () => {
  const own = await eve.client.from('profiles').update({ display_name: 'Eve Updated' }).eq('id', eve.user.id).select();
  assert.equal(own.error, null);
  assert.equal(own.data[0].display_name, 'Eve Updated');
  const other = await eve.client.from('profiles').update({ display_name: 'hacked' }).eq('id', bob.user.id).select();
  assert.equal(other.error, null);
  assert.equal(other.data.length, 0, 'RLS hides and blocks other profiles');
  const idChange = await eve.client.from('profiles').update({ id: randomUUID() }).eq('id', eve.user.id);
  assert.ok(idChange.error, 'id is not updatable');
  const badName = await eve.client.from('profiles').update({ username: 'x' }).eq('id', eve.user.id);
  assert.ok(badName.error, 'username format enforced on update');
});

// ---------- storage ----------

test('uploads only into your own folder with the canonical name; no overwrite', async () => {
  const draft = randomUUID();
  assert.equal((await upload(alice.client, photoPath(alice.user.id, draft))).error, null);
  const again = await alice.client.storage.from(BUCKET).upload(photoPath(alice.user.id, draft), TINY_JPEG, { contentType: 'image/jpeg', upsert: true });
  assert.ok(again.error, 'overwrite/upsert must be refused');
  assert.ok((await upload(alice.client, photoPath(bob.user.id, randomUUID()))).error, 'other user folder refused');
  assert.ok((await upload(alice.client, `${alice.user.id}/${randomUUID()}/other.jpg`)).error, 'non-canonical name refused');
  const png = await alice.client.storage.from(BUCKET).upload(photoPath(alice.user.id, randomUUID()), TINY_JPEG, { contentType: 'image/png' });
  assert.ok(png.error, 'bucket allows image/jpeg only');
  const big = await alice.client.storage.from(BUCKET).upload(photoPath(alice.user.id, randomUUID()), Buffer.alloc(10 * 1024 * 1024 + 1), { contentType: 'image/jpeg' });
  assert.ok(big.error, 'bucket rejects files over 10 MB');
});

test('unsent draft photo: owner can read, outsider and recipient cannot', async () => {
  const path = photoPath(alice.user.id, randomUUID());
  await upload(alice.client, path);
  assert.equal((await alice.client.storage.from(BUCKET).createSignedUrl(path, 300)).error, null);
  assert.ok((await bob.client.storage.from(BUCKET).createSignedUrl(path, 300)).error);
  assert.ok((await eve.client.storage.from(BUCKET).download(path)).error);
});

// ---------- sending ----------

let firstMessage;

test('send_postcard returns one message object and creates the conversation', async () => {
  const args = await draftFor(alice, bob.user.id);
  const { data, error } = await send(alice.client, args);
  assert.equal(error, null);
  assert.equal(Array.isArray(data), false, 'single object, not an array');
  assert.deepEqual(Object.keys(data).sort(), MESSAGE_KEYS);
  assert.equal(data.sender_id, alice.user.id);
  assert.equal(data.recipient_id, bob.user.id);
  assert.equal(data.photo_path, args.p_photo_path);
  assert.match(data.created_at, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/);
  firstMessage = data;

  const convos = await bob.client.rpc('list_conversations');
  assert.equal(convos.error, null);
  const convo = convos.data.find((c) => c.id === data.conversation_id);
  assert.ok(convo, 'recipient sees the conversation');
  assert.deepEqual(Object.keys(convo).sort(), ['id', 'latest_message', 'peer', 'updated_at']);
  assert.deepEqual(convo.peer, { id: alice.user.id, username: alice.username, display_name: 'Alice' });
  assert.equal(convo.latest_message.id, data.id);
});

test('recipient reads the message and its photo; outsider cannot', async () => {
  const msgs = await bob.client.rpc('list_messages', { p_conversation_id: firstMessage.conversation_id, p_before: null, p_limit: 20 });
  assert.equal(msgs.error, null);
  assert.equal(msgs.data[0].id, firstMessage.id);
  const signed = await bob.client.storage.from(BUCKET).createSignedUrl(firstMessage.photo_path, 300);
  assert.equal(signed.error, null);
  const res = await fetch(signed.data.signedUrl);
  assert.equal(res.status, 200, 'signed URL downloads for recipient');

  const outsider = await eve.client.rpc('list_messages', { p_conversation_id: firstMessage.conversation_id, p_before: null, p_limit: 20 });
  assert.equal(outsider.error?.code, 'PT404');
  assert.equal((await eve.client.from('postcards').select('*').eq('id', firstMessage.id)).data.length, 0);
  assert.equal((await eve.client.from('conversations').select('*')).data.length, 0);
  assert.ok((await eve.client.storage.from(BUCKET).createSignedUrl(firstMessage.photo_path, 300)).error);
  const eveConvos = await eve.client.rpc('list_conversations');
  assert.deepEqual(eveConvos.data, []);
});

test('clients cannot write tables directly or join conversations', async () => {
  const ins = await eve.client.from('postcards').insert({
    conversation_id: firstMessage.conversation_id, sender_id: alice.user.id, recipient_id: bob.user.id,
    message: 'forged', photo_path: 'x', client_request_id: randomUUID(),
  });
  assert.ok(ins.error, 'direct postcard insert refused');
  const join = await eve.client.from('conversation_members').insert({ conversation_id: firstMessage.conversation_id, user_id: eve.user.id });
  assert.ok(join.error, 'self-join refused');
  const convo = await eve.client.from('conversations').insert({ user_low: alice.user.id, user_high: bob.user.id });
  assert.ok(convo.error, 'direct conversation insert refused');
  const edit = await alice.client.from('postcards').update({ message: 'edited' }).eq('id', firstMessage.id);
  assert.ok(edit.error, 'messages are immutable for the sender too');
  const del = await alice.client.from('postcards').delete().eq('id', firstMessage.id);
  assert.ok(del.error || (await alice.client.from('postcards').select('id').eq('id', firstMessage.id)).data.length === 1);
});

test('sender identity cannot be spoofed through the photo path', async () => {
  // Eve uploads her own photo but claims Alice's path, or reuses Alice's sent photo.
  const draft = randomUUID();
  await upload(eve.client, photoPath(eve.user.id, draft));
  const spoof = await send(eve.client, {
    p_recipient_id: bob.user.id, p_sender_name: 'Alice', p_recipient_name: 'Bob', p_destination: '',
    p_message: 'hi', p_photo_path: firstMessage.photo_path, p_client_request_id: draft,
  });
  assert.equal(spoof.error?.code, 'PT403');
  const wrongDraft = await send(eve.client, {
    p_recipient_id: bob.user.id, p_sender_name: 'Eve', p_recipient_name: 'Bob', p_destination: '',
    p_message: 'hi', p_photo_path: photoPath(eve.user.id, draft), p_client_request_id: randomUUID(),
  });
  assert.equal(wrongDraft.error?.code, 'PT403', 'path must match the draft id');
});

test('validation errors use PT codes and create nothing', async () => {
  const cases = [
    [{ p_recipient_id: alice.user.id }, 'PT422', 'self'],
    [{ p_recipient_id: randomUUID() }, 'PT404', 'unknown recipient'],
    [{ p_message: '   ' }, 'PT422', 'blank message'],
    [{ p_message: 'x'.repeat(5001) }, 'PT422', 'long message'],
    [{ p_sender_name: 'x'.repeat(101) }, 'PT422', 'long sender name'],
    [{ p_recipient_name: 'x'.repeat(101) }, 'PT422', 'long recipient name'],
    [{ p_destination: 'x'.repeat(201) }, 'PT422', 'long destination'],
  ];
  for (const [override, code, label] of cases) {
    const args = await draftFor(alice, bob.user.id, override);
    const { error } = await send(alice.client, args);
    assert.equal(error?.code, code, label);
  }
  const ok5000 = await send(alice.client, await draftFor(alice, bob.user.id, { p_message: 'x'.repeat(5000) }));
  assert.equal(ok5000.error, null, '5,000 characters is allowed');

  const noUpload = randomUUID();
  const missing = await send(alice.client, {
    p_recipient_id: bob.user.id, p_sender_name: '', p_recipient_name: '', p_destination: '',
    p_message: 'hi', p_photo_path: photoPath(alice.user.id, noUpload), p_client_request_id: noUpload,
  });
  assert.equal(missing.error?.code, 'PT422');
  assert.equal(missing.error?.hint, 'photo_missing');
});

test('retry with the same draft id returns the original; conflicting reuse is rejected', async () => {
  const args = await draftFor(alice, bob.user.id);
  const first = await send(alice.client, args);
  const second = await send(alice.client, args);
  assert.equal(second.error, null);
  assert.deepEqual(second.data, first.data);
  const conflict = await send(alice.client, { ...args, p_message: 'different words' });
  assert.equal(conflict.error?.code, 'PT409');
  const { rows } = await sql.query('select count(*)::int as n from public.postcards where client_request_id = $1', [args.p_client_request_id]);
  assert.equal(rows[0].n, 1);
});

test('concurrent duplicate sends create exactly one message', async () => {
  const args = await draftFor(alice, bob.user.id);
  const results = await Promise.all(Array.from({ length: 20 }, () => send(alice.client, args)));
  for (const r of results) assert.equal(r.error, null);
  assert.equal(new Set(results.map((r) => r.data.id)).size, 1);
  const { rows } = await sql.query('select count(*)::int as n from public.postcards where client_request_id = $1', [args.p_client_request_id]);
  assert.equal(rows[0].n, 1);
});

test('concurrent first messages between a new pair create one conversation', async () => {
  const [carol, dave] = await Promise.all([newUser('carol'), newUser('dave')]);
  const a = await draftFor(carol, dave.user.id);
  const b = await draftFor(dave, carol.user.id);
  const [ra, rb] = await Promise.all([send(carol.client, a), send(dave.client, b)]);
  assert.equal(ra.error, null);
  assert.equal(rb.error, null);
  assert.equal(ra.data.conversation_id, rb.data.conversation_id);
  const { rows } = await sql.query(
    'select count(*)::int as n from public.conversations where user_low = least($1::uuid,$2::uuid) and user_high = greatest($1::uuid,$2::uuid)',
    [carol.user.id, dave.user.id]);
  assert.equal(rows[0].n, 1);
  const members = await sql.query('select count(*)::int as n from public.conversation_members where conversation_id = $1', [ra.data.conversation_id]);
  assert.equal(members.rows[0].n, 2);
});

test('list_messages pages newest first and clamps the limit', async () => {
  const conv = firstMessage.conversation_id;
  const page1 = await alice.client.rpc('list_messages', { p_conversation_id: conv, p_before: null, p_limit: 2 });
  assert.equal(page1.data.length, 2);
  assert.ok(page1.data[0].created_at >= page1.data[1].created_at);
  const page2 = await alice.client.rpc('list_messages', { p_conversation_id: conv, p_before: page1.data[1].created_at, p_limit: 2 });
  assert.ok(page2.data.every((m) => m.created_at < page1.data[1].created_at));
  const zero = await alice.client.rpc('list_messages', { p_conversation_id: conv, p_before: null, p_limit: 0 });
  assert.equal(zero.data.length, 1, 'limit clamps up to 1');
  const huge = await alice.client.rpc('list_messages', { p_conversation_id: conv, p_before: null, p_limit: 1000 });
  assert.ok(huge.data.length <= 100);
});

// ---------- storage lifecycle ----------

test('sent photos cannot be deleted; unsent orphans can, and cleanup never lists sent photos', async () => {
  const del = await alice.client.storage.from(BUCKET).remove([firstMessage.photo_path]);
  const still = await sql.query('select count(*)::int as n from storage.objects where bucket_id = $1 and name = $2', [BUCKET, firstMessage.photo_path]);
  assert.equal(still.rows[0].n, 1, `sent photo survives delete attempt (${JSON.stringify(del.error ?? del.data)})`);

  const orphan = photoPath(alice.user.id, randomUUID());
  await upload(alice.client, orphan);
  await sql.query("update storage.objects set created_at = now() - interval '2 days' where bucket_id = $1 and name in ($2, $3)",
    [BUCKET, orphan, firstMessage.photo_path]);
  const { rows } = await sql.query('select name from public.list_orphan_photos(24)');
  const names = rows.map((r) => r.name);
  assert.ok(names.includes(orphan), 'old unsent upload is an orphan');
  assert.ok(!names.includes(firstMessage.photo_path), 'sent photo is never an orphan');

  const removed = await alice.client.storage.from(BUCKET).remove([orphan]);
  assert.equal(removed.error, null);
  assert.equal(removed.data.length, 1, 'owner can delete an unsent upload');
});

test('a sent photo cannot be swapped through an upsert signed upload URL issued before sending', async () => {
  // The token is signed while the object doesn't exist (only the INSERT policy is checked), stays
  // valid for 2 h, and its uploads run on Storage's privileged connection, so RLS cannot stop a reuse.
  const bytes = (tag) => Buffer.concat([TINY_JPEG, Buffer.from(tag)]);
  const [draftBytes, sentBytes, swapBytes] = [bytes('draft'), bytes('sent'), bytes('swapped')];
  const draftId = randomUUID();
  const path = photoPath(alice.user.id, draftId);
  const storage = alice.client.storage.from(BUCKET);
  const signed = await storage.createSignedUploadUrl(path, { upsert: true });
  assert.equal(signed.error, null);
  const put = (body) => storage.uploadToSignedUrl(path, signed.data.token, body, { contentType: 'image/jpeg' });
  assert.equal((await put(draftBytes)).error, null, 'first upload through the signed URL');
  assert.equal((await put(sentBytes)).error, null, 'an unsent draft photo may still be replaced by its owner');

  const sent = await send(alice.client, {
    p_recipient_id: bob.user.id, p_sender_name: 'Alice', p_recipient_name: 'Bob', p_destination: '',
    p_message: 'look at this', p_photo_path: path, p_client_request_id: draftId,
  });
  assert.equal(sent.error, null);
  const recipientBytes = async () => {
    const { data, error } = await bob.client.storage.from(BUCKET).download(path);
    assert.equal(error, null);
    return Buffer.from(await data.arrayBuffer());
  };
  assert.deepEqual(await recipientBytes(), sentBytes, 'recipient sees the photo as sent');

  const swap = await put(swapBytes);
  assert.ok(swap.error, 'reusing the signed upload URL after sending must be refused');
  const upsert = await storage.upload(path, swapBytes, { contentType: 'image/jpeg', upsert: true });
  assert.ok(upsert.error, 'a direct upsert of a sent photo must be refused');
  assert.deepEqual(await recipientBytes(), sentBytes, 'recipient still downloads the original bytes');

  // Below the API too: privileged roles cannot rewrite or delete a sent photo, only move timestamps.
  const tryDb = async (statement) => {
    await sql.query('begin');
    try {
      await sql.query("set local storage.allow_delete_query = 'true'");
      await sql.query(statement, [BUCKET, path]);
      return null;
    } catch (e) {
      return e;
    } finally {
      await sql.query('rollback');
    }
  };
  const rewrite = await tryDb("update storage.objects set version = gen_random_uuid()::text where bucket_id = $1 and name = $2");
  assert.equal(rewrite?.code, 'PT403', 'version swap refused in the database');
  const rename = await tryDb("update storage.objects set name = name || '.old' where bucket_id = $1 and name = $2");
  assert.equal(rename?.code, 'PT403', 'moving a sent photo refused');
  const remove = await tryDb('delete from storage.objects where bucket_id = $1 and name = $2');
  assert.equal(remove?.code, 'PT403', 'deleting a sent photo refused even for privileged roles');
  assert.equal(await tryDb("update storage.objects set last_accessed_at = now() where bucket_id = $1 and name = $2"), null,
    'timestamp-only updates are allowed');
});

// ---------- realtime ----------

test('realtime delivers postcard inserts to participants only', async () => {
  const seen = { bob: [], eve: [] };
  // Resolve only when Realtime confirms the postgres_changes listener ("Subscribed to PostgreSQL"),
  // not merely the channel join, so the insert below can't race the subscription.
  const subscribe = (who, client) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${who}: no postgres_changes ack`)), 20000);
    client.channel(`pc-${who}-${randomUUID()}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'postcards' }, (p) => seen[who].push(p.new))
      .on('system', {}, (payload) => {
        if (payload?.extension === 'postgres_changes' && payload?.status === 'ok') { clearTimeout(timer); resolve(); }
        else if (payload?.extension === 'postgres_changes' && payload?.status === 'error') { clearTimeout(timer); reject(new Error(payload.message)); }
      })
      .subscribe((status, err) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') { clearTimeout(timer); reject(err ?? new Error(status)); }
      });
  });
  await Promise.all([subscribe('bob', bob.client), subscribe('eve', eve.client)]);

  const sent = await send(alice.client, await draftFor(alice, bob.user.id, { p_message: 'realtime hello' }));
  assert.equal(sent.error, null);
  for (let i = 0; i < 40 && seen.bob.length === 0; i++) await sleep(250);
  await sleep(1000);
  assert.ok(seen.bob.some((m) => m.id === sent.data.id), 'recipient receives the insert event');
  assert.equal(seen.eve.length, 0, 'outsider receives nothing');
});

// Records real request/response pairs from the LOCAL stack into backend/fixtures/.
// Requires `supabase db reset` (seeded alice/bob/eve). Tokens are redacted in the output.
import { writeFileSync, mkdirSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { API_URL, PUBLISHABLE_KEY, TINY_JPEG } from './helpers.mjs';

const OUT = new URL('../../backend/fixtures/', import.meta.url);
mkdirSync(OUT, { recursive: true });

async function signIn(email) {
  const res = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'postcard-local-1' }),
  });
  const body = await res.json();
  return { token: body.access_token, id: body.user.id };
}

async function rpc(name, args, token) {
  const headers = { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${API_URL}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(args) });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

function record(file, name, args, response, authed = true) {
  const fixture = {
    request: {
      method: 'POST',
      path: `/rest/v1/rpc/${name}`,
      headers: {
        apikey: '<SUPABASE_PUBLISHABLE_KEY>',
        ...(authed ? { Authorization: 'Bearer <user access token>' } : {}),
        'Content-Type': 'application/json',
      },
      body: args,
    },
    response,
  };
  writeFileSync(new URL(`${file}.json`, OUT), JSON.stringify(fixture, null, 2) + '\n');
  console.log(`${file}: ${response.status}`);
}

const alice = await signIn('alice@postcard.test');
const bob = await signIn('bob@postcard.test');

const draftId = randomUUID();
const path = `${alice.id}/${draftId}/photo.jpg`;
const up = await fetch(`${API_URL}/storage/v1/object/postcard-photos/${path}`, {
  method: 'POST',
  headers: { apikey: PUBLISHABLE_KEY, Authorization: `Bearer ${alice.token}`, 'Content-Type': 'image/jpeg', 'x-upsert': 'false' },
  body: TINY_JPEG,
});
writeFileSync(new URL('upload_photo.json', OUT), JSON.stringify({
  request: {
    method: 'POST',
    path: `/storage/v1/object/postcard-photos/${path}`,
    headers: { apikey: '<SUPABASE_PUBLISHABLE_KEY>', Authorization: 'Bearer <user access token>', 'Content-Type': 'image/jpeg', 'x-upsert': 'false' },
    body: '<JPEG bytes, max 10 MB>',
  },
  response: { status: up.status, body: await up.json() },
}, null, 2) + '\n');
console.log(`upload_photo: ${up.status}`);

let args = { p_username: 'BOB' };
record('lookup_recipient', 'lookup_recipient', args, await rpc('lookup_recipient', args, alice.token));
args = { p_username: 'nobody' };
record('lookup_recipient_not_found', 'lookup_recipient', args, await rpc('lookup_recipient', args, alice.token));

const send = {
  p_recipient_id: bob.id, p_sender_name: 'Alice', p_recipient_name: 'Grandma', p_destination: 'Cinque Terre',
  p_message: 'Somewhere between the sea and the sky, I thought of you.', p_photo_path: path, p_client_request_id: draftId,
};
const sent = await rpc('send_postcard', send, alice.token);
record('send_postcard', 'send_postcard', send, sent);
record('send_postcard_retry_same_key', 'send_postcard', send, await rpc('send_postcard', send, alice.token));
args = { ...send, p_message: 'different words' };
record('error_idempotency_conflict', 'send_postcard', args, await rpc('send_postcard', args, alice.token));

record('list_conversations', 'list_conversations', {}, await rpc('list_conversations', {}, bob.token));
args = { p_conversation_id: sent.body.conversation_id, p_before: null, p_limit: 50 };
record('list_messages', 'list_messages', args, await rpc('list_messages', args, bob.token));

// Errors
record('error_unauthenticated', 'list_conversations', {}, await rpc('list_conversations', {}, null), false);
args = { ...send, p_client_request_id: randomUUID(), p_message: '' };
record('error_validation', 'send_postcard', args, await rpc('send_postcard', args, alice.token));
args = { ...send, p_client_request_id: randomUUID(), p_recipient_id: randomUUID() };
record('error_recipient_not_found', 'send_postcard', args, await rpc('send_postcard', args, alice.token));
const other = randomUUID();
args = { ...send, p_client_request_id: other };
record('error_forbidden_photo_path', 'send_postcard', args, await rpc('send_postcard', args, alice.token));
args = { ...send, p_client_request_id: other, p_photo_path: `${alice.id}/${other}/photo.jpg` };
record('error_photo_missing', 'send_postcard', args, await rpc('send_postcard', args, alice.token));
const eve = await signIn('eve@postcard.test');
args = { p_conversation_id: sent.body.conversation_id, p_before: null, p_limit: 50 };
record('error_conversation_not_found', 'list_messages', args, await rpc('list_messages', args, eve.token));

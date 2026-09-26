// Test helpers for a LOCAL Supabase stack (`supabase start`). Never point these at a hosted project:
// they create users and send postcards.
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';
import { randomUUID } from 'node:crypto';

export const API_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
export const PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;
export const DB_URL = process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';

if (!PUBLISHABLE_KEY) {
  throw new Error('Set SUPABASE_PUBLISHABLE_KEY (from `supabase status`). See backend/README.md.');
}
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(API_URL)) {
  throw new Error(`Refusing to run destructive tests against non-local ${API_URL}`);
}

export const BUCKET = 'postcard-photos';
// Smallest valid JPEG (1x1). Real clients upload a converted JPEG from the photo picker.
export const TINY_JPEG = Buffer.from(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AN//Z',
  'base64',
);

export const SECRET_KEY = process.env.SUPABASE_SECRET_KEY;

/** Service-role client for server-side checks (local only). */
export function adminClient() {
  if (!SECRET_KEY) throw new Error('Set SUPABASE_SECRET_KEY (from `supabase status`) for service-role tests.');
  return createClient(API_URL, SECRET_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function anonClient() {
  return createClient(API_URL, PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}

const runId = Math.random().toString(36).slice(2, 8);

/** Signs up a fresh local user and returns { client, user, profile }. */
export async function newUser(label) {
  const client = anonClient();
  const username = `${label}_${runId}`.toLowerCase();
  const email = `${username}@postcard.test`;
  const { data, error } = await client.auth.signUp({
    email,
    password: 'local-test-password-1',
    options: { data: { username, display_name: label[0].toUpperCase() + label.slice(1) } },
  });
  if (error) throw error;
  if (!data.session) throw new Error('Local stack should not require email confirmation');
  return { client, user: data.user, username, email };
}

export function photoPath(userId, draftId) {
  return `${userId}/${draftId}/photo.jpg`;
}

export async function upload(client, path, body = TINY_JPEG) {
  return client.storage.from(BUCKET).upload(path, body, { contentType: 'image/jpeg', upsert: false });
}

/** Uploads a photo for a new draft and returns send_postcard args. */
export async function draftFor(sender, recipientId, overrides = {}) {
  const draftId = randomUUID();
  const path = photoPath(sender.user.id, draftId);
  const { error } = await upload(sender.client, path);
  if (error) throw error;
  return {
    p_recipient_id: recipientId,
    p_sender_name: 'Alice',
    p_recipient_name: 'Grandma',
    p_destination: 'Cinque Terre',
    p_message: 'Wish you were here.',
    p_photo_path: path,
    p_client_request_id: draftId,
    ...overrides,
  };
}

export async function send(client, args) {
  return client.rpc('send_postcard', args);
}

export async function db() {
  const c = new pg.Client({ connectionString: DB_URL });
  await c.connect();
  return c;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

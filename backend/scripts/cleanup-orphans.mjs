// Removes unsent photo uploads older than N hours. SERVER-SIDE ONLY: uses the service-role key,
// which must never ship in the iOS app. Dry run by default; pass --apply to delete.
//   SUPABASE_URL=... SUPABASE_SECRET_KEY=... node backend/scripts/cleanup-orphans.mjs [--hours 24] [--apply]
// Sent photos are never listed: list_orphan_photos excludes any object a postcard references,
// and the Storage delete policy refuses sent photos for clients as a second guard.
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SECRET_KEY;
if (!url || !key) {
  console.error('Set SUPABASE_URL and SUPABASE_SECRET_KEY (service role; server-side only).');
  process.exit(1);
}
const args = process.argv.slice(2);
const apply = args.includes('--apply');
const hoursArg = args.indexOf('--hours');
const hours = Math.max(1, Number(hoursArg >= 0 ? args[hoursArg + 1] : 24) || 24);

const admin = createClient(url, key, { auth: { persistSession: false } });
const { data, error } = await admin.rpc('list_orphan_photos', { p_older_than_hours: hours });
if (error) throw error;
const names = data.map((row) => row.name);
console.log(`${names.length} orphan upload(s) older than ${hours}h${apply ? '' : ' (dry run)'}`);
for (let i = 0; apply && i < names.length; i += 100) {
  const batch = names.slice(i, i + 100);
  const { error: removeError } = await admin.storage.from('postcard-photos').remove(batch);
  if (removeError) throw removeError;
}
if (apply) console.log('Removed.');

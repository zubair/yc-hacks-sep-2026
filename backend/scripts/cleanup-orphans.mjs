// Removes unsent photo uploads older than N hours. SERVER-SIDE ONLY: uses the service-role key,
// which must never ship in the iOS app. Dry run by default; pass --apply to delete.
//   SUPABASE_URL=... SUPABASE_SECRET_KEY=... node backend/scripts/cleanup-orphans.mjs [--hours 24] [--apply]
// Sent photos are never listed: list_orphan_photos excludes any object a postcard references.
// The protect_sent_postcard_photos trigger refuses deleting a sent photo for every role, including
// this job, so a draft sent between listing and removal is kept and reported, not deleted.
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
const bucket = admin.storage.from('postcard-photos');
let removed = 0;
const kept = [];
const failed = [];
for (let i = 0; apply && i < names.length; i += 100) {
  const batch = names.slice(i, i + 100);
  const { data: gone, error: removeError } = await bucket.remove(batch);
  if (!removeError) {
    removed += gone.length;
    continue;
  }
  // One refused object fails the whole batch, so retry this batch one object at a time.
  for (const name of batch) {
    const { data: one, error } = await bucket.remove([name]);
    // PT403 comes from the trigger: the draft was sent after listing, so it is no orphan.
    if (error) (/PT403/.test(error.message) ? kept : failed).push(`${name} (${error.message})`);
    else removed += one.length;
  }
}
if (apply) console.log(`Removed ${removed}.`);
if (kept.length) console.log(`Kept ${kept.length} sent after listing:\n  ${kept.join('\n  ')}`);
if (failed.length) {
  console.error(`Failed to remove ${failed.length}:\n  ${failed.join('\n  ')}`);
  process.exitCode = 1;
}

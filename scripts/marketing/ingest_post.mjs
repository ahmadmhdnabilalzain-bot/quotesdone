// INGEST A POST TO THE MARKETING SEAT (marketing, 22 Sep 2026).
//
// Founder, 22 Sep 2026: he and Claude create posts together and ingest them to the marketing seat, which
// schedules them. This is the one way in for a post written outside the estate: it sends the post and its
// media to supabase/functions/marketing_channels (action 'ingest'), which stores the media in the PRIVATE
// marketing-media bucket and the post in public.marketing_post through fn_marketing_post_ingest.
//
//   node scripts/marketing/ingest_post.mjs post.json [media1.png media2.jpg ...]
//
// post.json (UTF-8 -- Node reads it as UTF-8, which is why this is a script and not a curl line: a
// Windows-shell curl once sent Arabic as question marks, and fn_marketing_post_ingest refuses that shape):
//   { "ingest_key": "2026-09-25-three-quotes", "ingested_by": "founder",
//     "text_en": "...", "text_ar": "...", "channels": ["facebook", "instagram", "linkedin"],
//     "scheduled_at": "2026-09-25T09:00:00+04:00" }            // omit scheduled_at to keep it a draft
//
// Re-running with the same ingest_key edits the post while it is still a draft or scheduled. Nothing is
// published by ingesting: the seat publishes at scheduled_at, and only while app_secrets.marketing_golive
// is 'true'. The script prints the result row; it never prints a key.
import { readFileSync } from 'node:fs';
import { basename, extname } from 'node:path';

const REF = 'htdblwldjkcgjvmqkbeh';
const TYPES = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.mp4': 'video/mp4' };

const [postFile, ...mediaFiles] = process.argv.slice(2);
if (!postFile) { console.error('usage: node scripts/marketing/ingest_post.mjs post.json [media ...]'); process.exit(2); }
const post = JSON.parse(readFileSync(postFile, 'utf8'));
const media = mediaFiles.map((f) => {
  const type = TYPES[extname(f).toLowerCase()];
  if (!type) { console.error('unsupported media type: ' + f); process.exit(2); }
  return { name: basename(f), type, base64: readFileSync(f).toString('base64') };
});

const mgmt = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + mgmt } })).json();
const service = keys.find?.((k) => k.name === 'service_role')?.api_key;
const credRows = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
  method: 'POST', headers: { Authorization: 'Bearer ' + mgmt, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: "select value from public.app_secrets where key = 'cred_fn_marketing_channels'" }),
})).json();
const cred = Array.isArray(credRows) ? credRows[0]?.value : null;
if (!service || !cred) { console.error('could not read the service key or cred_fn_marketing_channels'); process.exit(1); }

const r = await fetch(`https://${REF}.supabase.co/functions/v1/marketing_channels`, {
  method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8', Authorization: 'Bearer ' + service },
  body: JSON.stringify({ __secret: cred, action: 'ingest', post, media }),
});
const out = await r.json().catch(() => ({ status: r.status }));
console.log(JSON.stringify(out, null, 2));
process.exit(out?.ok ? 0 : 1);

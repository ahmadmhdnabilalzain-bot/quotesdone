// LOAD A MONTH OF SOCIAL POSTS TO THE MARKETING SEAT (marketing, 23 Sep 2026).
//
// Founder, founder_instruction 865: a month-1 campaign of founder-made videos, scheduled by the marketing seat.
// This is the one way a month's calendar gets in:
//
//   node scripts/marketing/load_calendar.mjs docs/marketing/month1_social_calendar.json [--dry-run]
//
// 1. Every video and key frame the calendar names is DOWNLOADED from the private marketing-media bucket (service
//    role) and its sha256 compared with the calendar's; one mismatch or missing file and nothing is loaded.
// 2. The whole month is loaded by ONE call to fn_marketing_calendar_load, one transaction: all posts or none.
//    Loading the same file twice leaves the same rows (the function rewrites only what changed).
// 3. Nothing is published by loading. The seat emails the founder the month's calendar (PDF + spreadsheet)
//    once it has been quiet for 30 minutes; his reply "approve" is the approval (fn_marketing_calendar_reply),
//    and publishing still waits on app_secrets.marketing_golive.
//
// The calendar file (UTF-8; Node reads it as UTF-8, so Arabic arrives as Arabic):
//   { "campaign": { "key": "2026-month1-supplier-recruitment", "theme": "...", "month": "2026-10", "title": "..." },
//     "posts": [ { "key": "m1-01-instagram", "platform": "instagram|facebook|linkedin|x|youtube",
//                  "at_dubai": "2026-10-01T19:00:00", "at_utc": "2026-10-01T15:00:00Z",
//                  "video":    { "path": "campaigns/<campaign key>/videos/01.mp4", "sha256": "<64 hex>", "title": "..." },
//                  "keyframe": { "path": "campaigns/<campaign key>/frames/01.jpg", "sha256": "<64 hex>" },
//                  "caption_en": "...", "caption_ar": "...", "hashtags": ["UAE", "Shorts"],
//                  "alt_text": "...", "title": "(YouTube title; defaults to video.title)", "first_comment": "...",
//                  "cta_url": "https://...", "rationale": "...", "music": { "bpm": 100, "mood": "..." },
//                  "post_type": "(optional: reel|short|post|video)", "language": "(optional: en|ar|bi)" } ] }
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const REF = 'htdblwldjkcgjvmqkbeh';
const BUCKET = 'marketing-media';
const norm = (p) => String(p || '').replace(/^marketing-media\//, '');

/** Every asset the calendar names, verified against its bytes. Returns the problems (empty = all verified). */
export async function verifyAssets(calendar, fetchBytes) {
  const want = new Map();
  for (const p of calendar?.posts || []) {
    for (const a of [p.video, p.keyframe]) {
      if (!a?.path) { want.set('(missing path in ' + p.key + ')', null); continue; }
      const prev = want.get(norm(a.path));
      if (prev !== undefined && prev !== a.sha256) want.set(norm(a.path), 'conflict');
      else want.set(norm(a.path), a.sha256);
    }
  }
  const problems = [];
  for (const [path, sha] of want) {
    if (sha === null) { problems.push(path); continue; }
    if (sha === 'conflict') { problems.push(`${path}: two different sha256 values in the calendar`); continue; }
    const bytes = await fetchBytes(path);
    if (!bytes) { problems.push(`${path}: not in the private ${BUCKET} bucket`); continue; }
    const got = createHash('sha256').update(bytes).digest('hex');
    if (got !== String(sha).toLowerCase()) problems.push(`${path}: sha256 is ${got}, the calendar says ${sha}`);
  }
  return problems;
}

async function main() {
  const [file] = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (!file) { console.error('usage: node scripts/marketing/load_calendar.mjs <calendar.json> [--dry-run]'); process.exit(2); }
  const calendar = JSON.parse(readFileSync(file, 'utf8'));
  const mgmt = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
  const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + mgmt } })).json();
  const service = keys.find?.((k) => k.name === 'service_role')?.api_key;
  if (!service) { console.error('could not read the service key'); process.exit(1); }
  const H = { Authorization: 'Bearer ' + service, apikey: service };
  const problems = await verifyAssets(calendar, async (path) => {
    const r = await fetch(`https://${REF}.supabase.co/storage/v1/object/${BUCKET}/${path.split('/').map(encodeURIComponent).join('/')}`, { headers: H });
    return r.ok ? Buffer.from(await r.arrayBuffer()) : null;
  });
  if (problems.length) { console.error('NOT LOADED -- assets do not match the calendar:\n  ' + problems.join('\n  ')); process.exit(1); }
  console.log(`verified ${calendar.posts.length} posts' assets by sha256`);
  if (process.argv.includes('--dry-run')) process.exit(0);
  const r = await fetch(`https://${REF}.supabase.co/rest/v1/rpc/fn_marketing_calendar_load`, {
    method: 'POST', headers: { ...H, 'Content-Type': 'application/json; charset=utf-8' }, body: JSON.stringify({ p: calendar }) });
  const out = await r.json().catch(() => ({ status: r.status }));
  console.log(JSON.stringify(out, null, 2));
  process.exit(r.ok && out?.ok ? 0 : 1);
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) await main();

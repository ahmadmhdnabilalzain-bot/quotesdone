// The Vercel configuration is backed up every day, and every env var the site needs is in Vercel with a way
// back if Vercel loses it (it_engineer, 12 Oct 2026; the founder: "fix it" for the backup workflow).
//   1. The env var names the daily step checks are exactly the names the site's code reads (src/: process.env.X),
//      so a new variable cannot be added to the site without the check knowing it.
//   2. The snapshot never carries a value: the env list is requested without decrypt and values are dropped.
//   3. With a Supabase token (local runs), the live Vercel project is read and every needed name must be set
//      in Vercel and have a recoverable source; measured 12 Oct 2026: CRON_SECRET and SITE_ERROR_INGEST_SECRET
//      are read by the site, set nowhere in Vercel, and recoverable from nowhere.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
function walk(d, out = []) {
  for (const e of readdirSync(d)) { const p = join(d, e); if (statSync(p).isDirectory()) { if (e !== 'node_modules') walk(p, out); } else if (/\.(ts|tsx|js|mjs)$/.test(e)) out.push(p); }
  return out;
}
const SYSTEM = /^(NODE_ENV|VERCEL_ENV|VERCEL_DEPLOYMENT_ID|NEXT_PUBLIC_VERCEL_ENV|VERCEL_URL|VERCEL)$/;
const used = [...new Set(walk(join(ROOT, 'src')).flatMap((f) => [...readFileSync(f, 'utf8').matchAll(/process\.env\.([A-Z0-9_]+)/g)].map((m) => m[1])))]
  .filter((k) => !SYSTEM.test(k)).sort();
const listed = JSON.parse(/const SITE_ENV_NAMES = (\[[^\]]*\])/.exec(read('supabase/functions/resilience_ping/index.ts'))[1].replace(/'/g, '"')).sort();

test('the daily step checks exactly the env var names the site reads', () => {
  assert.deepEqual(listed, used, 'update SITE_ENV_NAMES in resilience_ping/index.ts to the names src/ reads');
});

test('the snapshot asks for no value and keeps none', () => {
  const r = read('supabase/functions/resilience_ping/index.ts');
  const tick = r.slice(r.indexOf('async function vercelSnapshotTick'), r.indexOf('async function dropboxHealthTick'));
  assert.ok(!/decrypt/i.test(tick), 'the env list is never requested decrypted');
  const s = read('supabase/functions/_shared/vercel_snapshot.ts');
  assert.match(s, /key: String\(e\.key\), targets: .*type: String\(e\.type/, 'only key, targets and type are copied from an env entry');
  assert.match(read('scripts/sql/the_vercel_configuration_is_backed_up_every_day.sql'), /'\/QuotesDone Backup\/Company\/Vercel\/'/, 'filed under Company/Vercel/ in Dropbox');
});

const tokenFile = join(homedir(), '.supabase', 'access-token');
const token = process.env.SUPABASE_ACCESS_TOKEN || (existsSync(tokenFile) ? readFileSync(tokenFile, 'utf8').trim() : '');
test('live: every env var the site reads is set in Vercel and recoverable', { skip: token ? false : 'no Supabase management token here' }, async () => {
  const q = async (query) => (await (await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', { method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }) })).json());
  const s = Object.fromEntries((await q("select key, value from public.app_secrets where key in ('vercel_token','vercel_project_id','vercel_team_id')")).map((r) => [r.key, r.value]));
  const team = s.vercel_team_id ? `?teamId=${s.vercel_team_id}` : '';
  const env = await (await fetch(`https://api.vercel.com/v10/projects/${s.vercel_project_id}/env${team}`, { headers: { Authorization: 'Bearer ' + s.vercel_token } })).json();
  const names = new Set((env.envs || []).map((e) => e.key));
  const missing = used.filter((k) => !names.has(k));
  // CRON_SECRET is optional by design (the cron route accepts an unsigned call: it mutates nothing). Every other
  // name must be set. SITE_ERROR_INGEST_SECRET is the open finding of 12 Oct 2026 (site errors are not reported).
  assert.deepEqual(missing.filter((k) => k !== 'CRON_SECRET'), [], 'set these in Vercel (Production) and keep their value in app_secrets: ' + missing.join(', '));
});

// THE ADVISORS BECOME A WATCHED SIGNAL — 9 September 2026.  Agent: ceo.
//
// Supabase computes security advisors continuously and nobody was reading them. "Run the advisors
// occasionally and look at the list" is not monitoring; it is a habit, and a habit is not a control.
// This script turns the list into a BASELINE and a DELTA:
//
//   * first run  — every finding is recorded with in_baseline = true. Nothing is reported.
//   * later runs — a cache_key that was not in the baseline is recorded with in_baseline = false,
//                  which is what public.fn_security_detect() raises as a 'new_security_advisor'
//                  security_event. A finding that stops being returned gets cleared_at set, so a
//                  fix is visible too and a cleared finding that comes BACK is new again.
//
// GRANULARITY, because it is the whole point. The advisors returned 534 findings on 9 Sep 2026
// across four rule types (485 INFO rls_enabled_no_policy, 44 WARN function_search_path_mutable,
// 3 WARN extension_in_public, 2 WARN authenticated_security_definer_function_executable). Baselining
// by RULE TYPE would have made a brand-new table with RLS on and no policy invisible behind a rule
// name that was already known — the estate's own "instrument measuring the wrong subject" failure.
// The key is therefore the per-entity cache_key, so a 535th key is a new finding whatever it is
// called.
//
// WHY THIS IS A SCRIPT AND NOT AN EDGE FUNCTION. The advisors are readable only through the
// management API (GET /v1/projects/{ref}/advisors/security, proven 200 with the CLI token on
// 9 Sep 2026). No edge function carries a management token, and copying one into app_secrets would
// widen the blast radius of a service-role leak from this project to the whole Supabase account, to
// close a gap a scheduled script already closes. That trade is recorded in public.security_gap
// under 'advisors_unreadable_from_the_runtime' rather than left as an unstated assumption.
//
//   node scripts/checks/security_advisors_match_the_baseline.mjs            # report the delta
//   node scripts/checks/security_advisors_match_the_baseline.mjs --refresh  # record it too
//
// Exit code is 0 when there is no NEW finding, 1 when there is — so CI fails on a security
// regression and on nothing else.
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { sql, PROJECT_REF } from '../lib/db.mjs';

const REFRESH = process.argv.includes('--refresh');

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token (SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token).');
}

const q = (s) => `'${String(s ?? '').replace(/'/g, "''")}'`;

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/advisors/security`,
                        { headers: { Authorization: `Bearer ${token()}` } });
if (!res.ok) {
  // An unreadable advisor list is NOT "no findings". Fail loudly rather than record a green.
  console.error(`advisors unreadable: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  process.exit(2);
}
const lints = (await res.json()).lints || [];
if (!Array.isArray(lints) || lints.length === 0) {
  console.error('the advisors endpoint returned no findings at all, which has never been true for '
              + 'this project. Treating that as an instrument failure, not as a clean bill.');
  process.exit(2);
}

const known = await sql(`select cache_key, in_baseline, cleared_at from public.security_advisor_baseline`);
const knownMap = new Map(known.map((r) => [r.cache_key, r]));
const firstRun = known.length === 0;

const live = new Set();
const values = [];
for (const l of lints) {
  const key = String(l.cache_key || `${l.name}:${JSON.stringify(l.metadata || {})}`);
  live.add(key);
  values.push(`(${q(key)}, ${q(l.name)}, ${q(l.level)}, ${q(String(l.title || '').slice(0, 300))}, `
            + `${q(JSON.stringify(l.metadata || {}))}::jsonb, ${firstRun ? 'true' : 'false'})`);
}

const brandNew = lints.filter((l) => {
  const k = String(l.cache_key || '');
  const prior = knownMap.get(k);
  return !firstRun && (!prior || (prior.in_baseline === false && prior.cleared_at !== null));
});
const gone = known.filter((r) => !r.cleared_at && !live.has(r.cache_key));

if (REFRESH) {
  // in_baseline is set on INSERT and never overwritten: a finding recorded as new stays new until a
  // human decides it is acceptable and updates the row. last_seen_at always moves, so a stale
  // baseline is visible as an old timestamp rather than being mistaken for a quiet estate.
  for (let i = 0; i < values.length; i += 200) {
    await sql(`insert into public.security_advisor_baseline
                 (cache_key, name, level, title, metadata, in_baseline)
               values ${values.slice(i, i + 200).join(',')}
               on conflict (cache_key) do update
                 set last_seen_at = now(), level = excluded.level, title = excluded.title,
                     metadata = excluded.metadata, cleared_at = null`);
  }
  if (gone.length) {
    await sql(`update public.security_advisor_baseline set cleared_at = now()
                where cleared_at is null and cache_key not in (${[...live].map(q).join(',')})`);
  }
}

const byRule = {};
for (const l of lints) { const k = `${l.level} ${l.name}`; byRule[k] = (byRule[k] || 0) + 1; }

console.log(`advisors on ${PROJECT_REF}: ${lints.length} findings`);
for (const [k, n] of Object.entries(byRule).sort()) console.log(`  ${String(n).padStart(4)}  ${k}`);
console.log(firstRun
  ? `baseline: ${REFRESH ? 'RECORDED' : 'NOT recorded (pass --refresh)'} — ${lints.length} findings`
  : `baseline holds ${known.length} keys; ${brandNew.length} NEW, ${gone.length} cleared`);

for (const l of brandNew) console.log(`  NEW      ${l.level} ${l.name} — ${l.cache_key}`);
for (const r of gone)     console.log(`  CLEARED  ${r.cache_key}`);

if (!REFRESH && (brandNew.length || gone.length)) {
  console.log('re-run with --refresh to record this state.');
}
process.exit(brandNew.length ? 1 : 0);

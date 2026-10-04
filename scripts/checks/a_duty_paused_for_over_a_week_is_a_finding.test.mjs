// ITEM 21 (it_engineer, 4 Oct 2026): a pause expires into a finding, and three probes assert the real thing.
//   1. a_duty_paused_for_over_a_week_is_a_finding.sql: a duty_pause row older than 7 days is a finding, money/security
//      duties raise a higher blast, the check runs as a daily seat duty, and its probe drives a REAL tick on a ZZ DEMO
//      paused duty (not a regex over the routine body);
//   2. the export registry probe asserts the EXACT 312 rows its file seeds, and that number is the file's own count;
//   3. the model matrix probe asserts tier and max_tokens per route, the tiers equal the change file's, no price literal.
// Offline: reads source only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, 'missing: ' + a); const j = s.indexOf(b, i + a.length); return s.slice(i, j < 0 ? undefined : j); };

test('a pause older than 7 days is a finding, more severe for money and security duties, run daily', () => {
  const s = read('scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql');
  const fn = between(s, 'create or replace function public.fn_it_engineer_duty_pause_expiry', '$fn$;');
  assert.match(fn, /paused_at < now\(\) - interval '7 days'/, 'the 7-day limit moved');
  assert.match(fn, /fn_it_engineer_finding_upsert\(\s*'duty_pause_expired:' \|\| p\.duty/, 'not raised through the estate finding path');
  assert.match(fn, /case when v_stakes in \('money', 'security'\) then 'security' else 'agent_facing' end/, 'money/security no longer raise the higher blast');
  assert.match(fn, /closed_at = now\(\)[\s\S]*not exists \(select 1 from public\.duty_pause/, 'a lifted pause no longer closes its finding');
  const stakes = between(s, 'create or replace function public.fn_duty_pause_stakes', '$fn$;');
  assert.match(stakes, /= 'accountant'/, 'the accountant seat is no longer money');
  assert.match(stakes, /'resilience_ping\.rotate_by_api'/, 'key rotation is no longer a security duty');
  for (const f of ['fn_duty_pause_stakes\\(text\\)', 'fn_it_engineer_duty_pause_expiry\\(\\)']) {
    assert.match(s, new RegExp(`revoke execute on function public\\.${f} from public, anon, authenticated`), f + ' is not revoked');
  }
  assert.match(s, /\('it_engineer\.duty_pause_expiry', 'it_engineer', interval '1 day', 'fn_it_engineer_duty_pause_expiry'/, 'not wired as a daily it_engineer duty');
});

test('the pause probes run a real tick, not a regex over the routine', () => {
  const p = between(read('scripts/sql/a_duty_paused_for_over_a_week_is_a_finding.sql'), '-- PROBE', 'drop table zz_duty_pause_probe;');
  assert.match(p, /r := public\.fn_seat_duties_tick\(/, 'the probe does not run the tick');
  assert.match(p, /'it_engineer\.zz_demo_paused', 'ZZ DEMO probe', 'it_engineer', now\(\) - interval '8 days'/, 'no aged ZZ DEMO pause');
  assert.match(p, /'it_engineer\.zz_demo_control'/, 'no unpaused control: a skip would prove nothing');
  assert.match(p, /raise exception using message = 'zz_duty_pause_probe_rollback'/, 'the probe no longer rolls its tick back');
  assert.doesNotMatch(p, /pg_get_functiondef/, 'the probe reads routine text again');
  const old = read('scripts/sql/every_duty_runner_honours_one_pause_switch.sql');
  assert.doesNotMatch(between(old, '-- PROBE', '\u0000'), /pg_get_functiondef[^\n]*duty_pause/, 'the regex-only pause probe is back');
});

test('the export registry probe asserts the exact count its file seeds', () => {
  const s = read('scripts/sql/the_daily_export_reads_a_registry_every_pull_request_adds_rows_to.sql');
  const rows = s.split(/\r?\n/).filter((l) => /^\s*\('[a-z0-9_]+', true, /.test(l));
  const tagged = rows.filter((l) => /'(exported before the registry \(the 174-row list of 29 Sep 2026\)|backlog decided 29 Sep 2026, exported:)/.test(l));
  const self = rows.filter((l) => /^\s*\('table_export_registry', true,/.test(l));
  assert.equal(tagged.length + self.length, 312, 'the seed changed: update the probe\'s exact count');
  const v = between(s, '-- VERDICT', 'end as verdict;');
  assert.match(v, /\) <> 312\b/, 'the probe is not the exact seeded count');
  assert.doesNotMatch(v, /< 174/, 'the floor is back');
});

test('the matrix probe asserts tier and max_tokens per route, as the change file writes them, with no price literal', () => {
  const probe = read('scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql');
  const sec4 = between(probe, '── 4. EVERY CLASS HAS A SEAT', 'if jsonb_array_length(bad) = 0');
  const want = {};
  for (const m of sec4.matchAll(/\('([a-z_]+)', c_\w+, (?:c_\w+|null), '(\w+)', (\d+)\)/g)) want[m[1]] = { tier: m[2], min: +m[3] };
  const change = read('scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql');
  const have = {};
  for (const m of change.matchAll(/\('([a-z_]+)',\s+'(small|medium|large|xlarge)',\s+'([^']+)',\s+(?:'([^']+)'|null)\)/g)) have[m[1]] = { tier: m[2], p: m[3], f: m[4] };
  assert.ok(Object.keys(have).length >= 8, 'could not read the change file\'s routes');
  for (const [route, h] of Object.entries(have)) {
    assert.ok(want[route], route + ' has no tier in the probe');
    assert.equal(want[route].tier, h.tier, route + ': the probe\'s tier is not the change file\'s');
    const opus = [h.p, h.f].includes('anthropic/claude-opus-5.5');
    assert.ok(want[route].min >= (opus ? 4000 : 1), route + ': the max_tokens floor is below the change file\'s');
  }
  assert.match(sec4, /r\.tier is distinct from r\.want_t/, 'tier is not asserted');
  assert.match(sec4, /coalesce\(r\.max_tokens, 0\) < r\.min_tok/, 'max_tokens is not asserted');
  assert.match(sec4, /drawing_and_boq_analysis'\) < 8000/, 'drawing_and_boq_analysis lost its 8000');
  assert.doesNotMatch(probe.replace(/--[^\n]*/g, ''), /per_mtok|\b0\.0\d+\b|\b\d+\.\d+\s*\/\s*\d/, 'a price literal is back in the matrix probe');
});

// THE IT ENGINEER TURNS EVERY FAILING RUN LABEL INTO AN OWNED FINDING (it_engineer, 27 Oct 2026; ledger 1003, IT-C14).
//
// MEASURED 27 Oct 2026: labels that ALWAYS fail have no rise against their own baseline, so the IT watch never raised
// them (llm_gateway_auth 413/413 errors in 30 days, no finding; watch:run_failure:compliance_archive closed 30 Sep while
// the label kept failing). And without a fixture filter, the loudest 7-day "cluster" was login_otp refusing rehearsal
// traffic exactly as designed.
//
// WHAT FAILS IF THE CAUSE RETURNS (offline): the rule (more than 5 runs, more than half not ok, 7 days) changes; fixture
// runs stop being counted apart; the owner stops coming from function_owner or the seat's duty; an unowned label stops
// saying so; a cleared label's finding stops closing; the duty or the revoke disappears.
//
//   node --test scripts/checks/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { definitions } from '../lib/canonical_sql.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const s = readFileSync(join(REPO, 'scripts/sql/the_it_engineer_turns_every_failing_run_label_into_an_owned_finding.sql'), 'utf8');
// The routine's canonical body moved on 27 Oct 2026: a warned or skipped run is not a failed run. The duty row still
// comes from the first file; the rule, the fixture split, the owner and the close loop are read from the new one.
const w = readFileSync(join(REPO, 'scripts/sql/a_warned_or_skipped_run_is_not_a_failed_run.sql'), 'utf8');
const fn = definitions(w).find((d) => d.name === 'fn_it_engineer_run_clusters')?.stmt ?? '';
const FAILED = String.raw`(?:coalesce\(status, 'none'\)|status) not in \('ok', 'warn', 'skipped'\)`;

test('the rule is the standard\'s: more than 5 runs and more than half FAILED in 7 days', () => {
  assert.ok(fn, 'fn_it_engineer_run_clusters is not defined');
  assert.match(fn, /ar\.started_at > now\(\) - interval '7 days'/);
  assert.match(fn, new RegExp(String.raw`having count\(\*\) > 5 and count\(\*\) filter \(where ${FAILED}\) \* 2 > count\(\*\)`));
});

// MEASURED 27 Oct 2026: the 17:05 UTC run opened duty:run_cluster:fn:unsubscribe (warn 18 of 18, HTTP 400 for a bad
// link) and duty:run_cluster:fn:quote_compare (warn 17 of 17, HTTP 409 need_two) on a healthy day, because every status
// but 'ok' counted as a failure. A warn is a 4xx answered correctly and a skip is a guard refusing correctly.
test('a warned or skipped run is not counted as failed, and a run with no status still is', () => {
  const counted = fn.match(/count\(\*\) filter \(where .{0,70}/g) ?? [];
  assert.ok(counted.length >= 3, 'the failure count, the cluster rule and the order are all filtered counts');
  for (const c of counted) assert.match(c, new RegExp(FAILED), 'a count that is not the failure predicate: ' + c);
  assert.doesNotMatch(fn, /status <> 'ok'/, 'every status but ok counts as a failure again');
  assert.match(fn, /coalesce\(ar\.status, 'none'\) as status/, 'a missing status must be counted, as \'none\'');
  assert.match(fn, /where r3\.label = runs\.label and r3\.status not in \('ok', 'warn', 'skipped'\)/, 'the sample notes must be failed runs');
  assert.match(fn, /coalesce\(status, 'none'\) not in \('ok', 'warn', 'skipped'\)\) from public\.agent_runs where agent = f\.label/, 'the close reading counts the same failures');
  assert.ok(w.includes('revoke execute on function public.fn_it_engineer_run_clusters() from public, anon, authenticated;'));
});

test('fixture runs are counted apart, under their own key, as demo', () => {
  for (const marker of [/counts->>'fixture'/, /counts->>'caller', ''\) = 'fixture'/, /ilike '%example\.invalid%'/, /like '%ZZ DEMO%'/]) assert.match(fn, marker);
  assert.match(fn, /\) = v_fx\)/, 'the fixture test is not compared with the run mode');
  assert.match(fn, /'duty:run_cluster:fixture:'/);
  assert.match(fn, /'demo', v_fx/);
});

test('every finding names its owner, and an unowned label says so', () => {
  assert.match(fn, /from public\.function_owner o join public\.org_role s on s\.role_id = o\.owner and s\.status = 'active'/);
  assert.match(fn, /from public\.seat_duty d join public\.org_role s on s\.role_id = d\.owner_seat/);
  assert.match(fn, /'owner_seat', v_owner, 'unowned', v_owner is null/);
  assert.match(fn, /no seat owns this run label/);
  assert.match(fn, /public\.fn_it_engineer_finding_upsert\(/);
});

test('a cleared label\'s finding is closed with its reading, and real findings are untouched by a fixture run', () => {
  assert.match(fn, /continue when f\.label = any \(v_labels\);\s+perform public\.fn_it_engineer_finding_close\(f\.issue_key, format\('cleared: /);
  assert.match(fn, /\(v_fx or e\.issue_key not like 'duty:run_cluster:fixture:%'\)/);
});

test('the duty is registered and the definer is closed', () => {
  assert.match(s, /security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.ok(s.includes('revoke execute on function public.fn_it_engineer_run_clusters() from public, anon, authenticated;'));
  assert.match(s, /\('it_engineer\.run_clusters', 'it_engineer', interval '1 day', 'fn_it_engineer_run_clusters'/);
});

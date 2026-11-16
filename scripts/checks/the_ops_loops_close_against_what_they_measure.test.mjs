// THE OPS LOOPS CLOSE AGAINST WHAT THEY MEASURE (ceo + it_engineer, OPS_LOOPS, 16 Nov 2026; holes H3-H7, H9, H10 of the COO
// hunt of 16 Nov 2026, founder ledgers 1711-1713).
//
// Static, no token, no database: it reads the six SQL files and fails if a cause of the hunt's holes comes back:
//   * a routine one of them creates is callable by anon or has no pinned search_path;
//   * a file has no probe, or no pending note while it is unapplied, or a probe that is not a pure rolled-back probe;
//   * the backup settle stops judging against the measurement, or stops keeping one live alert per live condition (H9);
//   * the incident impact is decided by code instead of the it_engineer's model, or an occurrence can carry the impact (H3);
//   * a calendar owner is accepted without being a live seat, or Big 5 Global loses its seats (H7);
//   * the backlog review resolves a person-facing question, or allows a second retry (H4);
//   * the weekly verdict counts a duty on its clock without reading its result (H5);
//   * a failed compliance fetch stamps the source checked, or the fetch leaves the registered hosts (H6);
//   * the partnership handoff kind or its decision loses its owner (H10).
// The behaviour itself is proved by each file's _probe.sql on a local Postgres 16 (scripts/db/local_pg16.mjs), run twice.
//   node --test scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILES = {
  backup: 'a_backup_alert_closes_against_the_coverage_measured_today',
  incident: 'an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches',
  calendar: 'every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead',
  backlog: 'each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves',
  compliance: 'every_compliance_source_is_fetched_monthly_and_a_change_reaches_the_seat_it_affects',
  partnership: 'a_partnership_email_reaches_the_ceo_with_the_senders_facts',
};
const SQL = Object.fromEntries(Object.entries(FILES).map(([k, n]) => [k, R(`scripts/sql/${n}.sql`)]));
const MANIFEST = R('scripts/sql/MANIFEST.txt');
/** The body of one routine, from its create line to the end of its dollar-quoted body. */
const body = (sql, fn) => {
  const at = sql.indexOf(`create or replace function public.${fn}(`);
  assert.ok(at >= 0, `${fn} is not defined`);
  const open = sql.indexOf('$fn$', at);
  return sql.slice(at, sql.indexOf('$fn$', open + 4) + 4);
};

test('every routine is revoked from anon and authenticated and pins its search_path', () => {
  for (const [k, sql] of Object.entries(SQL)) {
    const made = [...sql.matchAll(/create or replace function public\.(\w+)\(/g)].map((m) => m[1]);
    assert.ok(made.length > 0, `${k}: no routine`);
    for (const fn of made) {
      assert.match(sql, new RegExp(`revoke execute on function public\\.${fn}\\([^)]*\\) from public, anon, authenticated`), `${k}: ${fn} is not revoked`);
      assert.match(body(sql, fn), /set search_path to 'public', 'pg_temp'/, `${k}: ${fn} has no pinned search_path`);
    }
    for (const t of [...sql.matchAll(/create table if not exists public\.(\w+)/g)].map((m) => m[1])) {
      assert.match(sql, new RegExp(`alter table public\\.${t} enable row level security`), `${k}: ${t} has no RLS`);
      assert.match(sql, new RegExp(`create policy \\w+ on public\\.${t}`), `${k}: ${t} has no policy`);
      assert.match(sql, new RegExp(`insert into public\\.table_export_registry[\\s\\S]*'${t}'`), `${k}: ${t} is not in the export registry`);
    }
    assert.doesNotMatch(sql, /do \$\w*\$[\s\S]{0,400}execute format\(/, `${k}: dynamic SQL in a DO block`);
  }
});

test('every file has a pure probe, and a pending note until its MANIFEST line exists', () => {
  for (const n of Object.values(FILES)) {
    const probe = R(`scripts/sql/${n}_probe.sql`);
    assert.match(probe, /raise exception 'CHK<<PROBE OK>>'/, `${n}: the probe does not end by rolling back`);
    assert.doesNotMatch(probe, /create or replace function/, `${n}: the probe defines a routine`);
    const applied = MANIFEST.split(/\r?\n/).includes(`scripts/sql/${n}.sql`);
    assert.equal(existsSync(join(ROOT, `scripts/sql/pending/${n}.txt`)), !applied, `${n}: pending note and MANIFEST line disagree`);
    assert.ok(existsSync(join(ROOT, `scripts/sql/pending/${n}_probe.txt`)), `${n}: the probe has no note`);
  }
});

test('H9: a backup alert is judged against the coverage measured now, one stays open per live condition', () => {
  const b = body(SQL.backup, 'fn_it_backup_alerts_settle');
  assert.match(b, /coalesce\(p_cov, public\.fn_backup_coverage\(\)\)/, 'the settle does not measure the coverage itself');
  assert.match(b, /'superseded_by', v_keep/, 'older copies are not closed as superseded by the kept alert');
  assert.match(b, /'coverage', v_cov/, 'a close does not carry the measurement it was judged on');
});

test('H3: the it_engineer\'s model says who an incident reaches; code routes by the detector\'s flag only', () => {
  const ask = body(SQL.incident, 'fn_it_incident_impact_ask');
  assert.match(ask, /public\.fn_reason_hold\('it_engineer', 'it_engineer\.incident_impact'/, 'the impact is not asked of the it_engineer\'s model');
  assert.match(ask, /finding_evidence'->>'public_surface'/, 'the routing does not read the detector\'s public_surface flag');
  assert.match(ask, /inc\.same_cause_as is null/, 'an occurrence (not a root) can be asked');
  const apply = body(SQL.incident, 'fn_reason_apply_it_engineer__incident_impact');
  assert.match(apply, /v_choice not in \('none', 'customers', 'suppliers', 'everyone'\)/, 'the apply does not check the four options');
  assert.match(apply, /where id = v_inc and same_cause_as is null/, 'an occurrence can carry the impact, so people would be told twice');
  assert.match(body(SQL.incident, 'fn_it_incident_collapse'), /interval '24 hours'/, 'occurrences are no longer folded within 24 hours');
});

test('H7: a calendar owner is a live seat, and Big 5 Global keeps marketing and sales_engineer', () => {
  const apply = body(SQL.calendar, 'fn_reason_apply_ceo__calendar_owner');
  assert.match(apply, /from public\.org_role o where o\.role_id = v_owner and o\.status = 'active'/, 'an owner is accepted without being a live seat');
  assert.match(SQL.calendar, /owner_seat text references public\.org_role \(role_id\)/, 'owner_seat is not bound to org_role');
  assert.match(SQL.calendar, /set owner_seat = 'marketing', also_seats = array\['sales_engineer'\]/, 'Big 5 Global lost its seats');
  assert.match(SQL.calendar, /\(41, 'sales_engineer'|select 41, 'sales_engineer'/, 'Big 5 Global lost the sales_engineer\'s brief');
  assert.match(body(SQL.calendar, 'fn_calendar_seat_facts'), /consent rules/, 'the seat\'s question lost the consent rules');
  assert.doesNotMatch(SQL.calendar, /when 'Growth' then|owner_dept\s*=\s*'Growth'/, 'a department is mapped to a seat by a rule');
});

test('H4: the backlog review never applies a person-facing answer and allows one retry', () => {
  const b = body(SQL.backlog, 'fn_seat_backlog_apply');
  assert.match(b, /not public\.fn_held_question_is_person_facing\(h\.surface\)/, 'a person-facing answer can be applied');
  // the earlier retry is read from the queue's history: a failed try replaces result, so a marker there is lost (review 16 Nov)
  assert.match(b, /y\.evidence->>'verdict' like 'asked again%'\)\) then\s+v_verb := 'raise'/, 'a second retry is allowed');
  assert.doesNotMatch(b, /h\.result \? 'backlog_retried_at'/, 'the retry marker is read from result, which a failed try replaces');
  assert.match(b, /'draft_answer', left\(v_txt, 4000\), 'needs_founder', true/, 'a person-facing answer is closed instead of kept for the founder');
  assert.match(body(SQL.backlog, 'fn_seat_backlog_review'), /public\.fn_reason_hold\(s\.role_id, s\.role_id \|\| '\.backlog_review'/, 'the review is not the seat\'s own model');
});

test('H5: the weekly verdict counts a duty on its clock only while its result is met', () => {
  const v = body(SQL.backlog, 'fn_ceo_seat_senior_verdict');
  assert.equal((v.match(/fn_seat_duty_result_missed\(/g) || []).length >= 3, true, 'the verdict does not read the result in the clock, the contribution and the shortfall');
  assert.match(v, /did not move their result/, 'a missed result is not a shortfall');
  assert.match(body(SQL.backlog, 'fn_seat_duty_result_missed'), /r\.measured_at < p_at - interval '2 days'/, 'a stale measurement counts as met');
  assert.doesNotMatch(body(SQL.backlog, 'fn_seat_duty_results_measure'), /\bexecute\b/i, 'a stored query is executed');
});

test('H6: a failed fetch is never a check, and the fetch stays on the registered hosts', () => {
  const rec = body(SQL.compliance, 'fn_compliance_sources_record');
  const failed = rec.slice(rec.indexOf("is not true or v_sig is null"), rec.indexOf("return jsonb_build_object('outcome', 'failed'"));
  assert.ok(failed.length > 0, 'no failure branch');
  assert.doesNotMatch(failed, /last_checked_at/, 'a failed fetch stamps last_checked_at');
  assert.match(body(SQL.compliance, 'fn_compliance_sources_due'), /'allowed_hosts'/, 'the due list carries no allowlist');
  const ts = R('supabase/functions/_shared/compliance_watch.ts');
  assert.match(ts, /if \(!hostAllowed\(u, allowed\)\) return Promise\.reject/, 'a redirect hop can leave the allowlist');
  assert.match(R('supabase/functions/resilience_ping/ticks/it_engineer/later_duties.ts'), /await runComplianceWatch\(rpc\)/, 'the daily step is not wired');
});

test('H10: a partnership e-mail is the CEO\'s, and its decision closes the loop', () => {
  assert.match(SQL.partnership, /'partnership\.proposed', 'customer_support', 'ceo'/, 'the handoff kind is not registered');
  const apply = body(SQL.partnership, 'fn_reason_apply_ceo__partnership');
  assert.match(apply, /v_choice not in \('pursue', 'decline'\)/, 'the apply does not check the two choices');
  assert.match(apply, /fn_seat_handoff_complete\(a\.id/, 'the decision does not close the handoff');
  assert.match(R('supabase/functions/email_triage/index.ts'), /if \(category === 'partnership'\)[^\n]*handPartnershipToCeo\(admin, m, summary, facts\)/, 'email_triage does not hand a partnership on');
});

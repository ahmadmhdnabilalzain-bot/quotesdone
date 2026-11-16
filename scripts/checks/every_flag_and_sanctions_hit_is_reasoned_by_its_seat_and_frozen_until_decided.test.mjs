// EVERY FRAUD FLAG AND EVERY SANCTIONS HIT IS REASONED BY ITS SEAT, AND THE PARTY IS FROZEN UNTIL IT IS DECIDED
// (16 Nov 2026, ceo + accountant, agent FLAGS_DECIDED; FAILURES items 3, 5, 9, 10 of the real-company hole hunt).
//
// What fails if a cause returns:
//   * a sanctions hit with no decider: the CEO duty, its reasoning surface or its apply routine is gone        -> static
//   * an open hit no longer freezes: the matching freeze trigger, or the reveal door's screening read, is gone -> static + probe
//   * customers are no longer screened at the points suppliers are                                           -> static + probe
//   * a confirmed ban tells no customer, or tells one a reason                                                -> probe
//   * a new fraud flag files no reasoning, or the backlog / overdue pass is gone                              -> static + probe
//   * a supplier-as-customer flag no longer holds that customer's quotes in the supplier's trades              -> static + probe
//   * request velocity is no longer a fact, or a supplier gets every new-job notice at once again              -> probe
//   * any new routine is callable by anon / authenticated, or has no pinned search_path                       -> static
// The probe runs on the LOCAL database only (QD_LOCAL_DB_URL, scripts/db/local_pg16.mjs); without one it is skipped and
// says NOT_VERIFIED. It is never run against production by this check.
//
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=... node --test scripts/checks/every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const sqlCode = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const tsCode = (s) => s.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
const NAME = 'every_flag_and_sanctions_hit_is_reasoned_by_its_seat_and_frozen_until_decided';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const src = sqlCode(R(FILE));

test('every routine the file creates is pinned to a search_path and revoked from anon and authenticated', () => {
  const made = [...src.matchAll(/create or replace function public\.([a-z0-9_]+)\(([^)]*)\)\s*returns[\s\S]*?\$(fn|function)\$;/gi)];
  assert.ok(made.length >= 20, `expected the file's routines, found ${made.length}`);
  for (const m of made) {
    assert.match(m[0], /set search_path to 'public', 'pg_temp'/i, `${m[1]} has no pinned search_path`);
    assert.match(src, new RegExp(`revoke execute on function public\\.${m[1]}\\([^)]*\\) from public, anon, authenticated;`, 'i'), `${m[1]} is not revoked`);
  }
  assert.doesNotMatch(src, /execute\s+format\s*\(/i, 'no dynamic SQL (apply_sql refuses it)');
  assert.doesNotMatch(src, /^\s*(begin|commit)\s*;/im, 'the file carries no transaction lines of its own');
});

test('the new table is sealed, service-role only, and its rows can never be deleted', () => {
  assert.match(src, /alter table public\.customer_screening_hit enable row level security;/);
  assert.match(src, /create policy customer_screening_hit_service_role_only on public\.customer_screening_hit\s+as permissive for all to public using \(false\) with check \(false\);/);
  assert.match(src, /revoke all on public\.customer_screening_hit from anon, authenticated;/);
  assert.match(src, /before delete on public\.customer_screening_hit\s+for each row execute function public\.fn_screening_record_is_never_deleted\(\)/);
});

test('a sanctions hit has a decider with a deadline, customers are screened at the same points, and an open hit freezes', () => {
  assert.match(src, /\('ceo\.sanctions_review', 'ceo', interval '1 hour', 'fn_ceo_sanctions_review_tick'/, 'the CEO duty is not registered');
  assert.match(src, /public\.fn_seat_duty_reason\('ceo', 'ceo\.sanctions_hit'/, "the hit is not filed for the CEO's reasoning");
  assert.match(src, /create or replace function public\.fn_reason_apply_ceo__sanctions_hit\(p_id bigint, p_result jsonb\)/, 'no apply routine for the answer');
  assert.match(src, /public\.fn_supplier_screening_decide\(v_one, v_choice, v_actor\)/, 'the answer is not applied through the decider');
  assert.match(src, /interval '24 hours'/, 'the decision has no deadline');
  const screen = src.slice(src.search(/create or replace function public\.fn_supplier_sanctions_screen\(/i));
  assert.match(screen.slice(0, screen.indexOf('$function$;') + 12), /v_cust := public\.fn_customer_sanctions_screen\(p_run_ids, p_rehearsal_tag\);/, 'the supplier screen no longer screens customers');
  assert.match(src, /after insert or update of status on public\.supplier_screening_hit\s+for each row execute function public\.fn_screening_hit_freezes_the_supplier\(\)/, 'no freeze on an open hit');
  assert.match(src, /matching_block_reason = 'compliance_review'/);
  assert.match(src, /after insert on public\.sanctions_ban\s+for each row execute function public\.fn_sanctions_ban_tells_affected_customers\(\)/, 'a confirmed ban tells nobody');
  assert.match(src, /\('compliance_check', '\*', 'ceo'/, 'compliance_check is not registered with the CEO');
  const guard = tsCode(R('supabase/functions/_shared/reveal_guard.ts'));
  assert.match(guard, /if \(await screeningOpen\(admin, \{ leadId: q\.supplier_id, customerId: opts\.customerId \}\)\) return refuse\('compliance_review'\);/, 'the reveal door does not ask the screening');
  const matching = tsCode(R('supabase/functions/customer_api/lib/matching.ts'));
  const frozenAt = matching.indexOf('if (await customerFrozen(admin, inqId))');
  assert.ok(frozenAt > 0 && frozenAt < matching.indexOf('functions/v1/sales_engineer'), 'a frozen customer is matched before he is checked');
});

test('every new fraud flag is reasoned with a close-by date; the backlog and the overdue ones are worked hourly', () => {
  assert.match(src, /after insert on public\.fraud_flags\s+for each row execute function public\.fn_fraud_flag_goes_to_the_accountants_reasoning\(\)/, 'a new flag files nothing');
  assert.match(src, /public\.fn_seat_duty_reason\('accountant', 'accountant\.fraud_flag'/);
  assert.match(src, /create or replace function public\.fn_reason_apply_accountant__fraud_flag\(p_id bigint, p_result jsonb\)/);
  assert.match(src, /when 'high' then interval '2 days' when 'medium' then interval '5 days' else interval '10 days'/, 'no close-by date by severity');
  assert.match(src, /\('accountant\.flag_review', 'accountant', interval '1 hour', 'fn_accountant_flag_review_tick'/, 'the hourly pass is not registered');
  assert.match(src, /p_idempotency_key => 'fraud_flag_overdue:'/, 'an overdue flag is not reported to the CEO');
});

test('a supplier posing as a customer: the facts, the wider equality test and the held quotes', () => {
  for (const k of ['same_terms_ip', 'same_company_email_domain', 'customer_requests_in_these_trades', 'rival_quotes_the_customer_could_read', 'customer_reveals_in_these_trades'])
    assert.match(src, new RegExp(`'${k}'`), `the facts lack ${k}`);
  assert.match(src, /select 'terms_ip' as what/, 'equal terms IP raises no flag');
  const life = tsCode(R('supabase/functions/customer_api/actions/inquiry_lifecycle.ts'));
  assert.match(life, /const checking = await quotesBeingChecked\(admin, String\(cust\.id\)\);/, 'my_inquiries does not read the hold');
  assert.match(life, /\(paidQuoteIds\.has\(String\(q\.id\)\) \|\| !checking\.has\(String\(q\.inquiry_id\)\)\)/, 'held quotes are still listed');
  assert.match(life, /being_checked: checkingByInq\[String\(i\.id\)\] \|\| 0/, 'the held quotes are not counted');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const LOCAL = process.env.QD_LOCAL_DB_URL || '';
test('local database, rolled back, ZZ DEMO only: the probe passes', { skip: LOCAL ? false : 'NOT_VERIFIED: no QD_LOCAL_DB_URL (scripts/db/local_pg16.mjs start)' }, async () => {
  const { replaySql } = await import('../lib/safe_replay.mjs');
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let out = null;
  try { await replaySql(pre + R(PROBE), { retry: false }); } catch (e) {
    // the local runner keeps the whole stderr on e.body (its message is cut at 2,000 characters, which the NOTICEs fill)
    const m = (String(e.body || '') + '\n' + String(e.message || e)).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message || e).slice(0, 1500));
    try { out = JSON.parse(m[1]); } catch (_e) { out = JSON.parse(m[1].replace(/\\"/g, '"')); }
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log('  ' + JSON.stringify({ ok: out.ok, failures: out.failures, screen: out.screen, flag_tick: out.flag_tick }));
  assert.deepEqual(out.failures, [], JSON.stringify(out.failures));
  assert.equal(out.ok, true);
});

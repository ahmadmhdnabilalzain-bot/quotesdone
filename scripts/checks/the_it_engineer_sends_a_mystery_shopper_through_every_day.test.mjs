// THE IT ENGINEER SENDS A MYSTERY SHOPPER THROUGH EVERY DAY (founder ruling 1209). Assigned: it_engineer.
// Offline. Fails when:
//   1. the comparison stops running on the real model (ruling 1260, 19 Oct 2026: "all tests need to be done with AI.
//      from now on open router stays on"): quote_compare grows a model-skipping switch again (the deterministic_only
//      branch this PR first carried was refused for exactly that), the shopper stops carrying its run tag, or a
//      degraded (deterministic fallback) report passes unnoticed;
//   1b. the intake stops going through the real AI interview (ruling 1260: the review of #1370 found it on the
//      demo_factory makeInquiry SQL fixture): no runIntake on a fact sheet, no ready gate, no create_inquiry as the
//      portal presses it, no tagged model call, or matching asserts equality instead of "both run suppliers among";
//   2. it can reach a real person or be billed: no demo-guard preflight, no rehearsal window, a reveal or Stripe call;
//   3. it stops cleaning up and proving 0 leftovers, or stops reporting each step to the IT engineer;
//   4. the ingest stops filing a broken step (with its error) or starts closing on a skipped one; the workflow loses
//      its daily schedule (commented out under the founder's 26 Oct note while Actions are off, ledger 1279) or the
//      shared runner; a new routine is left open.
//   node --test scripts/checks/the_it_engineer_sends_a_mystery_shopper_through_every_day.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'the_it_engineer_sends_a_mystery_shopper_through_every_day';
const SHOP = R('scripts/e2e/mystery_shopper.mjs');
const QC = R('supabase/functions/quote_compare/index.ts');
const SQL = R(`scripts/sql/${NAME}.sql`);
const PROBE = R(`scripts/sql/${NAME}_probe.sql`);
const WF = R('.github/workflows/mystery-shopper.yml');
const js = (s) => s.split(/\r?\n/).map((l) => l.replace(/^\s*\/\/.*$/, '')).join('\n');

test('the comparison runs on the real model, tagged to the run, and a fallback is the finding', () => {
  const code = js(SHOP);
  assert.match(code, /call\('quote_compare', fx\.cust\.jwt, \{ inquiry_id: fx\.inq\.id, lang: 'en' \}/, 'the comparison is not asked for as the customer asks for it');
  assert.doesNotMatch(code, /deterministic_only|technical_only/, 'the shopper asks quote_compare to skip the model (ruling 1260)');
  assert.match(code, /must\(process\.env\.QD_E2E_RUN_TAG === run\.tag/, 'the model call is not proved to carry the run tag');
  assert.match(code, /must\(r\.json\.degraded !== true/, 'a deterministic fallback would pass as the model\'s report');
  assert.doesNotMatch(QC, /body\.deterministic_only/, 'quote_compare has a model-skipping switch again (ruling 1260)');
});

test('the intake is the real AI interview, sent as the portal sends it, and matching judges the real path', () => {
  const code = js(SHOP);
  assert.doesNotMatch(code, /makeInquiry/, 'the intake is the SQL fixture again, not the interview (ruling 1260)');
  assert.match(code, /const sheet = factSheet\('aluminium', \{ lang: 'en', emirate: 'Dubai' \}\)/, 'no fact sheet answers the interview');
  assert.match(code, /await runIntake\(fx\.cust, \[sheet\.opening\], 14, sheet\)/, 'the interview is not driven turn by turn');
  assert.match(code, /must\(it\.status === 'ready'/, 'an interview that never reached ready would pass');
  assert.match(code, /call\('customer_api', fx\.cust\.jwt, \{ action: 'create_inquiry', intake_id: it\.intakeId/, 'the request is not sent as the portal sends it');
  assert.match(code, /e2e_run_tag = \$\{q\(run\.tag\)\}[\s\S]*must\(cost\[0\]\.n > 0/, 'the interview\'s model calls are not proved to carry the run tag');
  assert.match(code, /mine\.every\(\(id\) => got\.includes\(id\)\)/, 'matching no longer requires both run suppliers among the matches');
  assert.doesNotMatch(code, /insert into public\.inquiry_matches/, 'the shopper writes its own matches instead of reading the matcher\'s');
  assert.match(code, /r\.status === 'suppressed'/, 'a deliverable notification about the demo request would pass');
  // the quotes answer what the real request asks (live run 5b64eda4: both held at ranking), judged by the product's own
  // assessment rather than by the shopper's guess
  assert.match(code, /call\('supplier_api', s\.jwt, \{ action: 'spec_hold', quote_id: qt\.id \}\)/, 'the quotes are not checked against the sales engineer\'s assessment');
  assert.match(code, /still incomplete by the sales engineer's assessment/, 'a quote the assessment still holds would pass the quote step');
});

test('the shopper cannot reach a real person or be billed, and leaves nothing behind', () => {
  const code = js(SHOP);
  assert.match(code, /zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair'/, 'no demo-guard preflight');
  assert.match(code, /must\(g\.length === 3/, 'the preflight no longer refuses');
  assert.match(code, /await openRun\(\)/, 'no rehearsal window / run tag');
  assert.doesNotMatch(code, /makeReveal|stripe_checkout|element_pay|transactions/, 'the shopper reveals or pays');
  assert.match(code, /makeDemoCustomer\(run, \{ label: 'Mystery Shopper'/);
  assert.match(code, /c\.demo === true/, 'the customer is not asserted to be on a demo address');
  assert.match(code, /r\.is_demo\)/, 'matches are not asserted demo-only');
  assert.match(code, /closed = await closeRun\(run\);\s*must\(closed\.leftovers && closed\.leftovers\.total === 0/, 'cleanup is not proved to 0');
  assert.match(code, /\} finally \{[\s\S]*step\('cleanup'[\s\S]*await report\(run\.tag\)/, 'cleanup or the report is not in the finally');
  assert.match(code, /fn_it_engineer_mystery_shopper_ingest/, 'the steps are not reported to the IT engineer');
  for (const s of ['signup', 'suppliers', 'intake', 'matching', 'quote', 'comparison', 'cleanup']) assert.match(code, new RegExp(`step\\('${s}'`), `step ${s} is gone`);
});

test('a broken step becomes a finding naming it; a skipped one is carried, never closed', () => {
  const code = SQL.replace(/--.*$/gm, '');
  assert.match(code, /'title', left\('Mystery shopper: step ' \|\| \(x->>'step'\) \|\| ' broke: ' \|\| coalesce\(nullif\(btrim\(x->>'error'\), ''\)/, 'the finding no longer names the step and the error');
  assert.match(code, /'carried', x->>'status' = 'SKIP'/, 'a skipped step is no longer carried');
  assert.match(code, /fn_it_duty_settle\('mystery_shopper', v_items\)/);
  for (const [fn, sig] of [['fn_it_engineer_mystery_shopper_ingest', 'jsonb'], ['fn_it_engineer_mystery_shopper_heartbeat', '']]) {
    assert.ok(code.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn} is not revoked`);
  }
  assert.equal((code.match(/set search_path to 'public', 'pg_temp'/g) || []).length, 2, 'a routine has no pinned search_path');
  assert.match(code, /interval '26 hours'/, 'the heartbeat window moved');
  assert.match(PROBE, /raise exception 'CHK<<%>>'/);
  assert.ok(PROBE.includes("'duty:mystery_shopper:quote'"), 'the probe no longer proves a skip files nothing');
});

test('the workflow keeps its daily schedule and the shared runner', () => {
  assert.match(WF, /cron: '\d+ \d+ \* \* \*'/, 'the daily schedule is gone (keep it, commented, while Actions are off)');
  assert.match(WF, /workflow_dispatch/, 'the workflow cannot be run by hand');
  assert.match(WF, /runs-on: \$\{\{ vars\.RUNNER \|\| 'ubicloud-standard-2' \}\}/, 'not on the shared runner');
  assert.match(WF, /run: node scripts\/e2e\/mystery_shopper\.mjs\s*$/m, 'the workflow does not run the shopper');
});

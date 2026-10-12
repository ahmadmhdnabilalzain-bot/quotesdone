// THE IT ENGINEER SENDS A MYSTERY SHOPPER THROUGH EVERY DAY (founder ruling 1209). Assigned: it_engineer.
// Offline. Fails when:
//   1. the shopper can buy a model call: it drives the intake interview, a PDF/Arabic comparison, or a quote_compare
//      without deterministic_only, or quote_compare stops answering deterministic_only BEFORE it asks a model;
//   2. it can reach a real person or be billed: no demo-guard preflight, no rehearsal window, a reveal or Stripe call;
//   3. it stops cleaning up and proving 0 leftovers, or stops reporting each step to the IT engineer;
//   4. the ingest stops filing a broken step (with its error) or starts closing on a skipped one; the workflow stops
//      running daily on the shared runner; a new routine is left open.
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

test('the shopper never asks a paid model', () => {
  const code = js(SHOP);
  for (const bad of [/inquiry_intake/, /runIntake/, /compare_pdf|compare_csv/, /makeInquiry\([^)]*mode:\s*'api'/, /makeQuote\([^)]*mode:\s*'api'/, /makeSupplier\([^)]*mode:\s*'api'/]) {
    assert.doesNotMatch(code, bad, `the shopper calls a model path: ${bad}`);
  }
  assert.match(code, /call\('quote_compare', fx\.cust\.jwt, \{ inquiry_id: fx\.inq\.id, lang: 'en', deterministic_only: true \}/, 'the comparison is not asked for deterministically');
  assert.match(code, /r\.json\.deterministic_only === true/, 'a model-written comparison would pass unnoticed');
  const branch = QC.indexOf('if (body.deterministic_only === true) {');
  assert.ok(branch > 0, 'quote_compare no longer serves deterministic_only');
  assert.ok(branch < QC.indexOf("/functions/v1/ai_gateway'"), 'quote_compare asks a model before it reads deterministic_only');
  assert.match(QC.slice(branch, branch + 600), /deterministicCompare\(labelled/, 'deterministic_only is not the deterministic ranking');
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

test('the workflow runs it daily on the shared runner', () => {
  assert.match(WF, /cron: '\d+ \d+ \* \* \*'/, 'not scheduled daily');
  assert.match(WF, /runs-on: \$\{\{ vars\.RUNNER \|\| 'ubicloud-standard-2' \}\}/, 'not on the shared runner');
  assert.match(WF, /run: node scripts\/e2e\/mystery_shopper\.mjs\s*$/m, 'the workflow does not run the shopper');
});

// OUR OWN TEST TRAFFIC NEVER REACHES A PAID MODEL
// (it_engineer, 22 Sep 2026, founder instruction 705). Recurrence check for
// scripts/sql/our_own_test_traffic_never_reaches_a_paid_model.sql, supabase/functions/ai_gateway and the
// consumers that name their subject. The pure rules are tested in _shared/spend_guards.test.ts; the
// repeat-spend shapes in no_paid_call_repeats_itself.test.mjs.
//
// REPOSITORY (always runs) FAILS if:
//   * ai_gateway stops asking fn_ai_subject_is_fixture, or asks it after the provider key is read;
//   * a consumer that the E2E harness drives stops naming its subject.
// PRODUCTION (needs a management token, and the file applied) runs the verdict-row probe.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

// RULING 1260 (19 Oct 2026): "all tests need to be done with AI. from now on open router stays on". The fixture
// check lets a test run through INSIDE its tagged, open window and tags the costed row; untagged or outside its
// window it is still refused before the provider key is read.
test('ruling 1260: inside its window a test run is tagged and costed; outside it, it is refused', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  const fx = gw.indexOf("admin.rpc('fn_ai_subject_is_fixture'");
  const key = gw.indexOf("sec('openrouter_api_key')");
  const dry = gw.indexOf('if (dry) {');
  assert.ok(dry > 0 && dry < fx && fx < key, 'the fixture check must sit after the dry run and before the provider key is read');
  assert.match(gw, /ownWorkByName\(fnName\)/, 'probes, rehearsals, smokes and evals must be recognised by name');
  assert.match(gw, /if \(ownWork && !inWindow\) \{/, 'untagged or out-of-window test traffic must still be refused');
  assert.match(gw, /outcome: 'fixture_no_spend'/);
  assert.match(gw, /if \(inWindow\) route\.why = route\.why \+ ' \| TEST RUN \(ruling 1260\): run tag '/, 'an in-window test call must carry its tag on the costed row');
  assert.match(gw, /if \(runTag\) \{/, 'a named probe/smoke/eval inside its window must be let through too');
});

test('the fixture marker is one only the harness can set, never a name, domain or number a user types', () => {
  const sql = read('scripts/sql/our_own_test_traffic_never_reaches_a_paid_model.sql');
  const body = sql.slice(sql.indexOf('create or replace function public.fn_ai_subject_is_fixture'), sql.indexOf('comment on function'));
  assert.match(body, /public\.rehearsal_window/, 'a harness identity must be proved by its rehearsal_window row');
  for (const typed of ['fn_is_demo_email', 'fn_is_demo_phone', 'is_demo', 'fn_seat_clock_customer_is_fixture', 'fn_seat_clock_lead_is_fixture', 'fn_inquiry_is_demo', 'zz'])
    assert.ok(!body.toLowerCase().includes(typed.toLowerCase()), `fn_ai_subject_is_fixture must not trust ${typed}: a customer can set it at sign-up`);
});

// The consumers the post-merge smoke and the nightly journey drive (scripts/e2e/run.mjs journeys a, b, c).
const NAMES_SUBJECT = {
  'supabase/functions/quote_compare/index.ts': /fn: 'quote_compare', subject: \{ inquiry_id/,
  'supabase/functions/inquiry_intake/index.ts': /fn: 'inquiry_intake', subject,/,
  // 12 Oct 2026 (ruling 1196): the widget's one model call (answerFromBrief) names the signed-in party as its subject
  'supabase/functions/site_assistant/index.ts': /fn: 'site_assistant', agent: seatForSurface,[\s\S]{0,400}subject: who \? \{ email: who\.email[\s\S]{0,120}\{ fixture: true, conv \}/,
  'supabase/functions/quote_extract/index.ts': /fn: 'quote_extract', subject: body\.subject/,
  'supabase/functions/license_extract/index.ts': /fn: 'license_extract', subject: body\.subject/,
};
test('every consumer the E2E harness drives names its subject to the gateway', () => {
  for (const [f, re] of Object.entries(NAMES_SUBJECT)) assert.match(read(f), re, `${f} no longer names its subject`);
  const api = read('supabase/functions/supplier_api/index.ts');
  // Five reader calls: the licence, the profile, the scanned catalogue (sales_engineer, 3 Nov 2026: a scanned
  // catalogue now reaches the model), quote_extract, and extract_quote reading through read_every_attachment (ruling 1177).
  assert.equal((api.match(/subject: \{ supplier_id: \(?sup/g) || []).length, 5, 'supplier_api must name the supplier on all five reader calls (licence, profile, scanned catalogue, quote_extract, read_every_attachment)');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: the fixture check agrees with the estate and never stubs a customer by accident', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [live] = await sql(`select to_regprocedure('public.fn_ai_subject_is_fixture(jsonb)') is not null as applied`);
  if (!live.applied) { t.skip('our_own_test_traffic_never_reaches_a_paid_model.sql is not applied yet'); return; }
  const [row] = await replaySql(read('scripts/sql/our_own_test_traffic_never_reaches_a_paid_model_probe.sql'), { rows: true });
  assert.equal(row.verdict, 'PROBE OK', row.detail);
});

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

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

test('the gateway answers a fixture before it reads the provider key', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  const fx = gw.indexOf("admin.rpc('fn_ai_subject_is_fixture'");
  const key = gw.indexOf("sec('openrouter_api_key')");
  const dry = gw.indexOf('if (dry) {');
  assert.ok(fx > 0, 'ai_gateway no longer asks fn_ai_subject_is_fixture');
  assert.ok(dry > 0 && dry < fx && fx < key, 'the fixture stub must sit after the dry run and before the provider key is read');
  assert.match(gw, /ownWorkByName\(fnName\)/, 'probes, rehearsals, smokes and evals must be recognised by name');
  assert.match(gw, /outcome: 'fixture_no_spend'/);
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
  'supabase/functions/site_assistant/index.ts': /fn: 'site_assistant', agent: seat, \.\.\.\(who \? \{ subject: \{ email: who\.email \} \}/,
  'supabase/functions/quote_extract/index.ts': /fn: 'quote_extract', subject: body\.subject/,
  'supabase/functions/license_extract/index.ts': /fn: 'license_extract', subject: body\.subject/,
};
test('every consumer the E2E harness drives names its subject to the gateway', () => {
  for (const [f, re] of Object.entries(NAMES_SUBJECT)) assert.match(read(f), re, `${f} no longer names its subject`);
  const api = read('supabase/functions/supplier_api/index.ts');
  assert.equal((api.match(/subject: \{ supplier_id: \(?sup/g) || []).length, 3, 'supplier_api must name the supplier on all three reader calls');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: the fixture check agrees with the estate and never stubs a customer by accident', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [live] = await sql(`select to_regprocedure('public.fn_ai_subject_is_fixture(jsonb)') is not null as applied`);
  if (!live.applied) { t.skip('our_own_test_traffic_never_reaches_a_paid_model.sql is not applied yet'); return; }
  const [row] = await sql(read('scripts/sql/our_own_test_traffic_never_reaches_a_paid_model_probe.sql'));
  assert.equal(row.verdict, 'PROBE OK', row.detail);
});

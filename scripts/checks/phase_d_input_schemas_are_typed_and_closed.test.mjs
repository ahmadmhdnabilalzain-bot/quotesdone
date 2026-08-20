// THE NEGATIVE CONTROLS THE ACCEPTANCE AUDIT ASKED FOR, COMMITTED.
//
// Measured 2026-08-20, before E16: all 769 input keys across all 257 input schemas were declared
// `unconstrained`, `additional_properties` was true on 257 of 257, and there were no input enum
// domains at all. Driven against `fn_phase_d_schema_validate`, two payloads that should obviously
// have been refused validated **true**:
//
//   1. integers and booleans supplied where the source text describes documents;
//   2. the required keys plus an invented `refund_amount_aed: 999999` and `__proto__: {admin:true}`.
//
// The second one mattered more than it looked. `fn_phase_d_handler_execute` passes
// `coalesce(p_input->'effect_payload', v_inputs)` as the payload of the business object it writes,
// so an undeclared input key does not sit harmlessly outside the contract — it rides into a business
// record through `fn_phase_d_object_write`.
//
// These are the two payloads, verbatim, kept as negative controls. A schema change that reopens the
// contract or drops a type fails here rather than in an audit six weeks later.
//
// Read-only: every assertion is a `select`. Nothing is written.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// A CHECK THAT CANNOT RUN MUST SAY SO, AND MUST NOT THROW. This file needs the Supabase management
// credential. The tokenless `checks` workflow runs `npm test` with no env block, and reading the
// token file unconditionally made this an ENOENT hard failure there rather than a declared skip.
//
// node:test's own skip, never a top-level process.exit(0) — a file that registers zero tests reads
// as success to a runner, which is how a check goes quiet without anyone noticing.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so a file that skipped inside the one
// CI job holding the credential would read as a pass. Printing this makes the skip visible to the
// gate as well as to a human.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

// qd_guard reads the credential at module load, so importing it eagerly would throw before the
// skip below could take effect. It is loaded on first use instead.
const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const mgmtRead = async (ref, sql) =>
  (await import('../staging/qd_guard.mjs')).mgmtRead(ref, sql);

const q = (sql) => mgmtRead(PROD_REF, sql);
const lit = (o) => `'${JSON.stringify(o).replace(/'/g, "''")}'::jsonb`;

// Three well-formed objects: the declared type of every input key, measured in E16.
const WELL_FORMED = {
  founder_instruction: { command_id: 1, outcome: 'stated' },
  current_approved_founder_policies: { count: 0, policies: [] },
  current_company_objective: { count: 0, objectives: [] },
};

test('no schema declares an unconstrained key, and no contract is open', { skip: SKIP }, async () => {
  const [r] = await q(`
    select
      (select count(*) from public.phase_d_handler_schema s,
              lateral unnest(s.required_keys || coalesce(s.optional_keys,'{}')) k
        where coalesce(s.field_types->>k,'unconstrained') = 'unconstrained') as unconstrained,
      (select count(*) from public.phase_d_handler_schema
        where coalesce(additional_properties, true)) as open_contracts,
      (select count(*) from public.phase_d_handler_schema where schema_kind='input') as inputs,
      (select count(*) from public.phase_d_handler_schema where schema_kind='output') as outputs;`);

  assert.equal(Number(r.inputs), 257, 'the input schema count moved');
  assert.equal(Number(r.outputs), 257, 'the output schema count moved');
  assert.equal(Number(r.unconstrained), 0,
    `${r.unconstrained} declared keys are still 'unconstrained'. An unstated type is not an ` +
    'unconstrained one, and the validator can enforce nothing it was not told.');
  assert.equal(Number(r.open_contracts), 0,
    `${r.open_contracts} schemas still declare additional_properties = true. An undeclared input ` +
    'key reaches the business object payload through fn_phase_d_handler_execute.');
});

test('NEGATIVE CONTROL 1: wrongly-typed values are refused', { skip: SKIP }, async () => {
  const payload = {
    founder_instruction: 12345,
    current_approved_founder_policies: true,
    current_company_objective: 'a string where the resolver produces an object',
  };
  const [r] = await q(
    `select valid, reason from public.fn_phase_d_schema_validate('schema_input_w01_s01', ${lit(payload)});`);
  assert.equal(r.valid, false,
    'an integer, a boolean and a string were accepted for three keys the resolver only ever ' +
    'produces objects for. This is the exact payload the 2026-08-20 acceptance audit validated true.');
  assert.match(String(r.reason), /wrong types/,
    `refused, but not for the type: ${r.reason}`);
});

test('NEGATIVE CONTROL 2: an injected money key and __proto__ are refused', { skip: SKIP }, async () => {
  // JSON.parse and object spread both refuse to give you an OWN '__proto__' key, so the payload is
  // assembled as text. In jsonb '__proto__' is an ordinary key with no special meaning — which is
  // exactly why a closed contract, not a name filter, is the thing that has to refuse it.
  const body = "'" + JSON.stringify(WELL_FORMED).slice(0, -1)
    + ',"refund_amount_aed":999999,"__proto__":{"admin":true}}' + "'::jsonb";

  const [r] = await q(
    `select valid, reason from public.fn_phase_d_schema_validate('schema_input_w01_s01', ${body});`);
  assert.equal(r.valid, false,
    'refund_amount_aed and __proto__ were accepted into an input payload. fn_phase_d_handler_execute ' +
    'passes the input object through as the payload of the business object it writes, so this is a ' +
    'route from an unvalidated key into a business record.');
  assert.match(String(r.reason), /closed contract/,
    `refused, but not for being closed: ${r.reason}`);
  assert.ok(/refund_amount_aed/.test(String(r.reason)) && /__proto__/.test(String(r.reason)),
    `the refusal must name both injected keys so a reader can see what was rejected: ${r.reason}`);
});

test('POSITIVE CONTROL: a well-formed payload still validates', { skip: SKIP }, async () => {
  // A closed, typed contract that refuses everything is not a contract, it is an outage. The pair
  // of controls is what makes the two negatives above mean something.
  const [r] = await q(
    `select valid, reason from public.fn_phase_d_schema_validate('schema_input_w01_s01', ${lit(WELL_FORMED)});`);
  assert.equal(r.valid, true,
    `the correctly-typed payload was refused, so E16 closed more than it should have: ${r.reason}`);
  assert.match(String(r.reason), /closed/, `the reason should record that the contract is closed: ${r.reason}`);
  assert.match(String(r.reason), /3 typed/, `all three keys should report as typed: ${r.reason}`);
});

test('the output contract still refuses a bad status and an invented key', { skip: SKIP }, async () => {
  // The output side was already right before E16/E17 and must stay right. These two were measured
  // as passing by the acceptance audit and are kept so a schema edit cannot quietly undo them.
  const good = {
    status: 'completed', output: 'x',
    acceptance_assertions: [{ criterion: 'c', satisfied_by: 's' }],
    evidence_refs: [{ step_id: 'W01-S01' }],
    source_ref: 'step_run:1', captured_verbatim: { a: 1 },
  };
  const [badEnum] = await q(`select valid, reason from public.fn_phase_d_schema_validate(
    'schema_output_w01_s01', ${lit({ ...good, status: 'NOT_A_STATUS' })});`);
  assert.equal(badEnum.valid, false, 'a status outside the declared domain was accepted');

  const [extra] = await q(`select valid, reason from public.fn_phase_d_schema_validate(
    'schema_output_w01_s01', ${lit({ ...good, refund_amount_aed: 1 })});`);
  assert.equal(extra.valid, false, 'an invented key was accepted into a closed output contract');

  const [ok] = await q(
    `select valid, reason from public.fn_phase_d_schema_validate('schema_output_w01_s01', ${lit(good)});`);
  assert.equal(ok.valid, true,
    `the correctly-typed output was refused, so E17 typed a key wrongly: ${ok.reason}`);
});

// RETIRED 7 SEPTEMBER 2026 — ITS SUBJECT WAS REMOVED, NOT BROKEN.
//
// This asserted that every Phase D handler input schema is typed and closed.
//
// On 7 September 2026 the founder removed, in his own words: the organisation chart ("remove the
// whole organization chart that you made cause its trash"), every pre-programmed workflow ("i dont
// want any pre programmed workflow as things will totally be different"), and finally the kernel
// gates themselves ("i said remove the kernel gates").
//
// What is gone: 30 workflows, 257 steps, 8 handoffs, 347 events, 56 business objects, 54 rules, 32
// gates, every Phase C binding, every Phase D handler schema and fixture, 41 event subscriptions,
// 94 action executors, and the 36 kernel write/trace/parent-delete gate triggers.
//
// So this file is not red because the estate regressed. It is red because every noun in it was
// deliberately deleted. It is RETIRED rather than edited down to something that passes: a check
// rewritten until it goes green against an empty schema asserts nothing while still looking like a
// guard, and that is worse than no check at all.
//
// WHAT REPLACES IT: nothing yet, and that is said plainly rather than hidden. When the new
// structure exists it deserves checks written fresh against THAT structure. Do not recover this
// file; write the new one from what the company then is.
//
// WHAT STILL GUARDS THE ESTATE TODAY, all green: kernel_invariants,
// cancellation_reaches_the_kernel, every_discharge_claim_reaches_its_table,
// anon_cannot_execute_security_definer (security, and it never depended on the org),
// phase_c_components_are_owned, canonical_routine_manifest, export_from_either_source_is_identical
// and receipts_never_wait_on_the_founder.
//
// Removed from .github/workflows/project-parity.yml in the same commit. Do not re-add this file.

/* eslint-disable */
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
  (await import('../../staging/qd_guard.mjs')).mgmtRead(ref, sql);

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

// EVERY CONSEQUENTIAL CLOSED-DOMAIN FIELD, NOT THE ONE THAT HAPPENED TO HAVE A DOMAIN.
//
// Gate 5 of the final independent acceptance audit, 24 Aug 2026:
//
//   "The estate's own guard, phase_d_input_schemas_are_typed_and_closed.test.mjs, passes 5 of 5 —
//    its output assertion is 'the output contract still refuses a bad STATUS and an invented key.'
//    It tests the one field that has a domain. A check scoped to the only constrained key cannot
//    report that the other 140 schemas constrain nothing."
//
// That was exactly right, and it is why the audit's Gate 5 finding survived to a final acceptance
// run. The three tests below are derived from public.phase_d_output_domain_registry, so the
// denominator is the population and not a number typed here: a new schema, a new field or a
// withdrawn domain moves them without anyone remembering to.
test('every field on every schema carries a classified semantic domain', { skip: SKIP }, async () => {
  const [r] = await q(`select
      (select count(*) from public.phase_d_handler_schema hs,
              lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k)::text as pairs,
      (select count(*) from public.phase_d_output_domain_registry)::text as classified,
      (select coalesce(string_agg(hs.schema_id || '.' || k, ', '), '(none)')
         from public.phase_d_handler_schema hs,
              lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k
        where not exists (select 1 from public.phase_d_output_domain_registry r
                           where r.schema_id = hs.schema_id and r.field_name = k)) as unclassified`);
  assert.equal(r.unclassified, '(none)',
    `unclassified (schema, field) pair(s): ${r.unclassified}. fn_phase_d_schema_validate fails `
    + 'closed on these, so a payload for that schema is refused until the registry is rebuilt.');
  assert.equal(r.classified, r.pairs,
    `${r.pairs} (schema, field) pairs exist and the registry classifies ${r.classified}`);
});

test('every registered closed domain is actually declared on its schema', { skip: SKIP }, async () => {
  const [r] = await q(`select
      (select count(*) from public.phase_d_output_domain_registry
        where field_semantic_type = 'CLOSED_ENUM')::text as closed,
      (select coalesce(string_agg(r.schema_id || '.' || r.field_name, ', '), '(none)')
         from public.phase_d_output_domain_registry r
         join public.phase_d_handler_schema hs on hs.schema_id = r.schema_id
        where r.field_semantic_type = 'CLOSED_ENUM'
          and not (hs.enum_domains ? r.field_name)) as undeclared,
      (select count(*) from public.phase_d_output_domain_registry
        where field_semantic_type = 'CLOSED_ENUM_UNDEFINED')::text as undefined_pending`);
  assert.equal(r.undeclared, '(none)',
    `registered CLOSED_ENUM with no enum_domains entry: ${r.undeclared}. The registry is the `
    + 'derivation and enum_domains is what the validator enforces; they may not disagree.');
  assert.ok(Number(r.closed) >= 478,
    `only ${r.closed} CLOSED_ENUM field(s) are registered; 478 were established on 24 Aug 2026 and `
    + 'a domain may be added but not silently withdrawn');
  // Disclosed, not asserted to zero: 33 decision fields have no vocabulary in the frozen estate and
  // are raised as PBCR-002. A CHECK on the registry refuses a CLOSED_ENUM_UNDEFINED row that does
  // not name its change request, so this number can never become a silent hole.
  console.log(`  ${r.closed} CLOSED_ENUM field(s) enforced; ${r.undefined_pending} CLOSED_ENUM_UNDEFINED, each naming its change request`);
});

test('an invalid value is refused on EVERY consequential closed-domain field', { skip: SKIP }, async () => {
  // One accepted control and one refused sentinel per (schema, field), built by the estate's own
  // probe builders FROM the registry — never typed here. 478 fields, so it is sampled per FIELD
  // NAME rather than per schema; the per-schema denominator is the suite in
  // scripts/phase_d/run_step_cases_live.mjs.
  const fields = await q(`select distinct field_name from public.phase_d_output_domain_registry
     where field_semantic_type = 'CLOSED_ENUM' order by field_name`);
  assert.ok(fields.length >= 7, `only ${fields.length} closed-domain field name(s) registered`);
  for (const { field_name: f } of fields) {
    const [r] = await q(`select
        (select valid from public.fn_phase_d_schema_validate(
           public.fn_phase_d_domain_probe_schema('${f}'),
           public.fn_phase_d_domain_probe_payload(
             public.fn_phase_d_domain_probe_schema('${f}'), '${f}', true))) as conforming,
        (select valid from public.fn_phase_d_schema_validate(
           public.fn_phase_d_domain_probe_schema('${f}'),
           public.fn_phase_d_domain_probe_payload(
             public.fn_phase_d_domain_probe_schema('${f}'), '${f}', false))) as sentinel,
        public.fn_phase_d_domain_probe_schema('${f}') as schema_id`);
    assert.equal(r.conforming, true,
      `${r.schema_id}: the registered valid_control_value for ${f} was REFUSED — a guard that fires `
      + 'when the system works is worse than no guard');
    assert.equal(r.sentinel, false,
      `${r.schema_id}: the registered invalid_sentinel_value for ${f} was ACCEPTED — this is the `
      + 'exact shape of the Gate 5 failure (decision = NOT_A_DECISION on schema_output_w17_s06)');
  }
  console.log(`  ${fields.length} closed-domain field name(s): conforming accepted, sentinel refused, on all`);
});

// THE GENERIC OBJECT STORE MUST REFUSE WHAT ITS CONTRACT FORBIDS — DRIVEN, BOTH DIRECTIONS.
//
// `public.phase_d_object_record` holds 56 business objects in one table. Until E18 its `state` was
// unconstrained `text`, no object had a payload contract, and both acceptance audits recorded the
// same five constraints: two keys, two foreign keys and `payload_not_empty`.
//
// A guard that has never fired is not a guard. Zero cannot tell a dead guard from an idle system, so
// this test FORCES each branch to fire, in one aborted transaction, and asserts both directions:
// four writes that must be refused and two that must be accepted. Without the accepted pair, a
// trigger that refused everything would score full marks.
//
// The whole probe runs inside a DO block that always raises, so nothing survives. The probe's own
// business keys begin `zz-phase-d-`, which `fn_phase_d_fixture_residue()` matches by design — the
// test asserts committed residue is 0 AFTER the rollback, which is the assertion that matters.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

const COLS = 'object_id, business_key, version, state, owner_scope, owner_ref, payload, created_by';

const CASES = [
  // name                  object                 state          scope       owner    payload                                     must
  ['well_formed',          'company_objective',   `'open'`,      `'COMPANY'`, `'ceo'`,     `jsonb_build_object('a',1)`,                'accept'],
  ['state_outside_domain', 'company_objective',   `'NOT_A_STATE'`, `'COMPANY'`, `'ceo'`,   `jsonb_build_object('a',1)`,                'refuse'],
  ['money_key',            'company_objective',   `'open'`,      `'COMPANY'`, `'ceo'`,     `jsonb_build_object('refund_amount_aed',999999)`, 'refuse'],
  ['wrong_owner_scope',    'company_objective',   `'open'`,      `'CUSTOMER'`, `'ceo'`,    `jsonb_build_object('a',1)`,                'refuse'],
  ['no_owner_ref',         'company_objective',   `'open'`,      `'COMPANY'`, `''`,        `jsonb_build_object('a',1)`,                'refuse'],
  ['money_on_transaction', 'payment_transaction', `'pending'`,   null,        `'finance'`, `jsonb_build_object('amount_aed',100)`,     'accept'],
  // An IDENTIFIER that merely mentions money is not money. The first version of the E18 rule matched
  // any key containing "refund" and refused this, which would have stopped a case record from naming
  // the refund it is about. The rule is a money-VALUE rule — a money-shaped name AND a numeric
  // value — and this is the control that keeps it one.
  ['refund_id_is_an_identifier', 'company_objective', `'open'`, `'COMPANY'`, `'ceo'`, `jsonb_build_object('refund_id','RF-1')`, 'accept'],
];

const PROBE = `
do $$
declare r jsonb := '[]'::jsonb;
begin
${CASES.map(([name, obj, state, scope, owner, payload], i) => `
  begin
    insert into public.phase_d_object_record (${COLS})
    select '${obj}', 'zz-phase-d-contract-probe-${i}', 1, ${state},
           ${scope ?? `b.ownership_scope`}, ${owner}, ${payload}, 'contract-probe'
      from public.phase_d_business_object_binding b where b.object_id = '${obj}';
    r := r || jsonb_build_array(jsonb_build_object('case','${name}','outcome','accepted'));
  exception when others then
    r := r || jsonb_build_array(jsonb_build_object(
      'case','${name}','outcome','refused','why',left(SQLERRM,200)));
  end;`).join('')}
  raise exception 'OBJ_CONTRACT %', jsonb_build_object(
    'cases', r,
    'contracts', (select count(*) from public.phase_d_object_state_contract),
    'objects',   (select count(*) from public.phase_d_business_object_binding));
end $$;`;

async function run() {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + TOKEN, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: PROBE }),
  });
  const body = await res.text();
  const m = body.match(/OBJ_CONTRACT (\{[\s\S]*?\})\\nCONTEXT/);
  assert.ok(m, `the probe did not reach its report:\n${body.slice(0, 1200)}`);
  return JSON.parse(m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'));
}

test('every bound business object has a state contract', async () => {
  const r = await run();
  assert.equal(Number(r.contracts), Number(r.objects),
    `${r.objects} bound objects but ${r.contracts} state contracts. The trigger fails closed on an ` +
    'object with no contract, so a gap here is an outage, not a permission.');
});

test('the object-record contract refuses what it forbids and accepts what it allows', async () => {
  const r = await run();
  const got = new Map(r.cases.map(c => [c.case, c]));

  for (const [name, , , , , , must] of CASES) {
    const c = got.get(name);
    assert.ok(c, `case ${name} did not run`);
    if (must === 'refuse') {
      assert.equal(c.outcome, 'refused',
        `case "${name}" was ACCEPTED. A guard that cannot refuse this is not enforcing anything.`);
      assert.match(String(c.why), /pd_object_/,
        `case "${name}" was refused, but not by the contract trigger: ${c.why}`);
    } else {
      assert.equal(c.outcome, 'accepted',
        `case "${name}" was REFUSED: ${c.why}. A contract that refuses a well-formed record is an ` +
        'outage wearing a guard, and it is what makes the four refusals above meaningless.');
    }
  }
});

test('the probe committed nothing', async () => {
  const [r] = await mgmtRead(PROD_REF, `select
    (select count(*) from public.fn_phase_d_fixture_residue()) as residue,
    (select count(*) from public.phase_d_object_record) as rows;`);
  assert.equal(Number(r.residue), 0, 'the probe left fixture residue behind');
  assert.equal(Number(r.rows), 0,
    `public.phase_d_object_record holds ${r.rows} committed rows — an aborted probe committed, or a ` +
    'real arrival has written one and a person should read why before this test is changed.');
});

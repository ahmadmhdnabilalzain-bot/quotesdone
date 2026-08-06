// employee_authority's 285 ROWS HAD FIRED AT MOST 3 TIMES EVER.
//
// Not because the limit was never computed — fn_check_spend reads employee_authority, derives
// agent_limit_aed and returns it. Because fn_decision_gate, the only enforcement caller, read one
// field (`affordable`) and threw the limit away, falling back to two hardcoded thresholds. A grant
// that is computed and discarded is decoration.
//
// The decisive check below is the MIDDLE one: an amount that is affordable for the department AND
// under the 1,000 Chief-of-Staff threshold, but over the employee's personal grant. That case
// passed before this change and must refuse now — it is the only case that isolates the personal
// limit from every other rule in the gate.
//
//   node scripts/staging/verify_employee_authority.mjs      # zero spend
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(60)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const AGENT = 'qd_fixture_approver';
const DEPT = 'procurement';        // 1,600 AED available
const LIMIT = 100;

const IMPACT = `impact_business='fixture business impact, long enough to pass the gate',
  impact_financial='fixture financial impact, long enough to pass the gate',
  impact_legal='fixture legal impact',
  impact_customer='fixture customer impact, long enough to pass the gate',
  evidence='[{"ref":"fixture"}]'::jsonb`;

async function cleanup() {
  await mgmtWrite(STAGE, `delete from public.decision_record where problem like 'qd_fixture_auth%'`, 'dr');
  await mgmtWrite(STAGE, `delete from public.employee_authority where agent_key='${AGENT}'`, 'ea');
  await mgmtWrite(STAGE, `delete from public.company_event where entity_id='${DEPT}' and event_type='budget.exceeded' and actor='${AGENT}'`, 'ce');
}

// Insert one decision_record at `amount` and report what the gate did to it.
async function decide(tag, amount) {
  await mgmtWrite(STAGE,
    `insert into public.decision_record
       (decided_by, dept_key, problem, recommendation, status, approved_by, financial_aed,
        impact_business, impact_financial, impact_legal, impact_customer, evidence)
     values ('${AGENT}','${DEPT}','qd_fixture_auth ${tag}','fixture recommendation','approved','${AGENT}',${amount},
        'fixture business impact, long enough to pass the gate',
        'fixture financial impact, long enough to pass the gate',
        'fixture legal impact for the gate',
        'fixture customer impact, long enough to pass the gate',
        '[{"ref":"fixture"}]'::jsonb)`, `dr ${tag}`);
  const r = await mgmtRead(STAGE,
    `select status, gate_verdict, coalesce(gate_reason,'') gate_reason
       from public.decision_record where problem = 'qd_fixture_auth ${tag}'`);
  return r[0] || {};
}

try {
  await cleanup();
  await mgmtWrite(STAGE,
    `insert into public.employee_authority (agent_key, action_class, max_tier, threshold_aed, note)
     values ('${AGENT}','fixture','supervised',${LIMIT},'fixture row for verify_employee_authority')`, 'ea');

  const avail = Number(one(await mgmtRead(STAGE, `select public.fn_budget_available('${DEPT}')`)));
  step('the fixture has a personal limit well under the department budget',
    avail > 500, `${DEPT} has ${avail} AED available, ${AGENT} is limited to ${LIMIT} AED`);

  // 1. Under the personal limit: must pass. If this refuses, the gate is simply broken.
  const under = await decide('under', 50);
  step('a spend inside the personal limit still passes', under.gate_verdict === 'passed',
    `50 AED -> ${under.gate_verdict} (${under.status})`);

  // 2. THE ONE THAT MATTERS. Affordable for the department, below the 1,000 Chief-of-Staff
  //    threshold, ABOVE the employee's personal grant. Nothing else in the gate refuses this.
  const over = await decide('over', 300);
  step('a spend over the personal limit is REFUSED, naming the limit',
    over.gate_verdict === 'refused' && /personal authority limit/i.test(over.gate_reason)
      && over.gate_reason.includes(String(LIMIT)),
    `300 AED -> ${over.gate_verdict}: ${over.gate_reason.slice(0, 110)}`);

  step('the refusal is left on the row, not lost to an aborted transaction',
    over.status === 'blocked_by_gate', `status=${over.status}`);

  step('and it says the amount was affordable, so the cause is not confused with a budget breach',
    /Affordable for the department/i.test(over.gate_reason),
    'the reason distinguishes "not yours to approve" from "no money left"');

  // 3. Unaffordable: refuses AND emits the company_event that had zero writers.
  const broke = await decide('unaffordable', 999999);
  step('an unaffordable spend is refused on affordability', broke.gate_verdict === 'refused',
    `999,999 AED -> ${broke.gate_verdict}: ${broke.gate_reason.slice(0, 80)}`);

  const evt = await mgmtRead(STAGE,
    `select payload from public.company_event
      where event_type='budget.exceeded' and actor='${AGENT}' order by id desc limit 1`);
  step('fn_emit_budget_exceeded has a caller, so a breach reaches company_event',
    evt.length === 1, evt.length ? `payload requested_aed=${evt[0].payload?.requested_aed}` : 'NO EVENT WRITTEN');

  // A breach that is only affordable-blocked must not also claim a personal-limit cause.
  step('each refusal names one cause, not both',
    !/personal authority limit/i.test(broke.gate_reason || ''),
    'the unaffordable case refuses on budget, not on the personal grant');

  await cleanup();
  const left = Number(one(await mgmtRead(STAGE,
    `select count(*) from public.decision_record where problem like 'qd_fixture_auth%'`)));
  step('the fixture cleaned up after itself', left === 0, `${left} row(s) left behind`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 300));
  await cleanup().catch(() => {});
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nEMPLOYEE AUTHORITY ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);

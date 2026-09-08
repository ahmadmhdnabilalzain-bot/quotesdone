// RETIRED 4 SEP 2026 — PHASE E (MASTER_PLAN §5.1 / §6 step 4). NOT RUN BY ANYTHING.
// Renamed from phase_c_command_acceptance.test.mjs so neither npm test nor the CI kernel gate discovers it.
// Why: an acceptance DRIVE of every row of PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv against production; a reproduction of a Phase C deliverable, not a property.
// The reasoning for every retired drive is in docs/agents/RETIRED_PHASE_DRIVES.md. The file is kept
// verbatim below as the record of what was measured while it ran.

// Gate C4 — run every row of PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv against the live
// Founder Command Center, with zero paid inference and zero persistent rows.
//
//   node scripts/checks/phase_c_command_acceptance.test.mjs
//
// Each case runs inside a transaction that ALWAYS rolls back: the command is submitted, the
// result is read, and then an exception is raised carrying the result out.  Nothing survives.
// That is the same aborted-transaction probe the session skill prescribes, applied to a write
// path instead of to a count.
//
// What is asserted is the routing OUTCOME, not merely that a row appeared: the intent, the
// workflows, the primary owner, whether a founder approval was created, and — for the two cases
// that must create no work — that zero tasks exist.
//
// A database-reading test must skip loudly when there is no management token.  CI has none.
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP phase_c_command_acceptance: no Supabase management token in this environment.');
  process.exit(0);
}

const { sql } = await import('../lib/db.mjs');
const { readCSV } = await import('../phase_c/lib/package.mjs');

const cases = readCSV(join(REPO, 'docs', 'phase-c', 'package', 'PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv'));
const lit = s => `'${String(s).replace(/'/g, "''")}'`;
const FOUNDER = 'management@quotesdone.com';

// package spelling -> live canonical role_id, for the expectation side only
const ALIAS = {
  payments_billing_manager: 'payments_and_billing_manager',
  supplier_coverage_liquidity_specialist: 'supplier_coverage',
  trust_safety_manager: 'trust_and_safety_manager',
  qa_release_management_director: 'quality_and_release_director',
  organisation_design_lead: 'organization_designer',
  corporate_performance_director: 'corporate_performance_director',
  rfq_success_specialist: 'rfq_success',
};
// 3 SEP 2026 (PACR-004): a role parked by a re-carve resolves to the seat that inherited its work,
// read from the alias registry the runtime itself resolves through (org_role_alias, kind
// merged_role) so this file never carries a second copy of the org.
const MERGED = Object.fromEntries((await sql(`select alias, role_id from public.org_role_alias where kind = 'merged_role'`)).map(r => [r.alias, r.role_id]));
const live = t => { const a = ALIAS[t] || t; return MERGED[a] || a; };

// ---- the frozen Phase B ownership these cases are judged against ------------------------------
// Loaded once, from the frozen registry, so the assertions below compare the runtime to the
// architecture rather than to a list that happens to be in a CSV column.
const stepRows = await sql(`select workflow_id, step_id, step_no, accountable_role_id
                              from public.phase_b_workflow_step order by workflow_id, step_no`);
const ownRows = await sql(`select workflow_id, accountable_role_id from public.org_workflow_ownership`);
const firstStepOwner = new Map();          // workflow_id -> the owner of step 1
const stepOwners = new Map();              // workflow_id -> Set(every step owner)
for (const s of stepRows) {
  if (!stepOwners.has(s.workflow_id)) stepOwners.set(s.workflow_id, new Set());
  stepOwners.get(s.workflow_id).add(s.accountable_role_id);
  if (!firstStepOwner.has(s.workflow_id)) firstStepOwner.set(s.workflow_id, s.accountable_role_id);
}
const workflowOwner = new Map(ownRows.map(r => [r.workflow_id, r.accountable_role_id]));

/**
 * Submit one command inside a transaction that always aborts, and bring the result back out
 * through the raised message.  `raise exception` with the JSON payload is what makes a write
 * path testable without leaving a write behind.
 */
async function submitAborted(text, idem) {
  const probe = `
do $probe$
declare v jsonb; v_tasks bigint; v_appr bigint; v_owner text; v_wf text; v_cmd_owner text;
begin
  v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(text)}, ${lit(idem)}, '{}'::jsonb);
  select count(*) into v_tasks from public.phase_c_task where command_id = (v->>'command_id')::bigint;
  select count(*) into v_appr from public.founder_approval_request where command_id = (v->>'command_id')::bigint;
  select coalesce(string_agg(workflow_id, ';' order by workflow_id), '') into v_wf
    from public.founder_command_workflow_link where command_id = (v->>'command_id')::bigint;
  select coalesce(string_agg(distinct accountable_role_id, ';'), '') into v_owner
    from public.phase_c_task where command_id = (v->>'command_id')::bigint;
  select command_owner_role_id into v_cmd_owner
    from public.founder_command where command_id = (v->>'command_id')::bigint;
  raise exception 'PROBE %', (v || jsonb_build_object(
    'db_tasks', v_tasks, 'db_approvals', v_appr, 'db_workflows', v_wf, 'db_owners', v_owner,
    'db_command_owner', v_cmd_owner))::text;
end $probe$;`;
  try {
    await sql(probe);
    throw new Error('the probe did not raise; nothing proves it rolled back');
  } catch (e) {
    // The management API escapes the raised message into JSON and appends its own CONTEXT
    // trailer, so neither "everything after PROBE" nor "up to the last brace" is the payload.
    // Scan braces to find the exact object.
    const msg = String(e.message).replace(/\\n/g, ' ').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    const start = msg.indexOf('{', msg.indexOf('PROBE'));
    if (start < 0) throw new Error('could not read the probe payload: ' + msg.slice(0, 500));
    let depth = 0, end = -1, inStr = false, esc = false;
    for (let i = start; i < msg.length; i++) {
      const ch = msg[i];
      if (esc) { esc = false; continue; }
      if (ch === '\\') { esc = true; continue; }
      if (ch === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (ch === '{') depth++;
      else if (ch === '}') { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) throw new Error('unbalanced probe payload: ' + msg.slice(start, start + 400));
    return JSON.parse(msg.slice(start, end + 1));
  }
}

const results = [];
let failed = 0;
let seq = 0;

for (const c of cases) {
  seq += 1;
  const r = await submitAborted(c.founder_text, `acceptance:${c.case_id}:${seq}`);
  const problems = [];

  // 1. intent
  const wantIntent = c.expected_intent;
  if (wantIntent === 'AMBIGUOUS') {
    if (r.intent !== 'AMBIGUOUS') problems.push(`intent ${r.intent} != AMBIGUOUS`);
    if (Number(r.db_tasks) !== 0) problems.push(`ambiguous command created ${r.db_tasks} task(s)`);
    if (!r.clarification) problems.push('no clarification question asked');
  } else if (r.intent !== wantIntent && !(wantIntent === 'CMD-MULTI' && r.intent === 'CMD-MULTI')) {
    problems.push(`intent ${r.intent} != ${wantIntent}`);
  }

  // 2. workflows — every expected workflow must be linked (extras are allowed: a command may
  //    legitimately touch more than the case names, but it may never miss one).
  //
  //    A REFUSED command is the exception, and it is a stricter assertion rather than a laxer
  //    one.  CC-017 lists expected_workflow_ids=W17 alongside expected_behavior=REFUSE: those
  //    two are in tension, and the safe reading is that W17 records what the instruction was
  //    ABOUT, not what got wired up.  "Refund every customer immediately" must link nothing and
  //    create nothing, so that is what is checked below.
  const gotWf = (r.db_workflows || '').split(';').filter(Boolean);
  if (c.expected_behavior === 'REFUSE_UNSCOPED_UNSAFE_COMMAND') {
    if (gotWf.length) problems.push(`refused command linked workflows [${gotWf.join(',')}]`);
  } else {
    const wantWf = (c.expected_workflow_ids || '').split(';').map(s => s.trim()).filter(x => x && x !== 'NONE');
    for (const w of wantWf) if (!gotWf.includes(w)) problems.push(`workflow ${w} not linked (got ${gotWf.join(',') || 'none'})`);
  }

  // 3. founder approval, the invariant that matters most
  const wantApproval = c.expected_founder_approval === 'YES';
  if (wantApproval && Number(r.db_approvals) !== 1) problems.push(`expected 1 founder approval, got ${r.db_approvals}`);
  if (!wantApproval && Number(r.db_approvals) !== 0) problems.push(`NON-REFUND FOUNDER APPROVAL CREATED (${r.db_approvals})`);

  // 4. the primary owner
  //
  // 17 AUG 2026 — WHAT THIS USED TO ASSERT, AND WHY IT WAS WRONG.
  //   It required `expected_primary_role` to appear among the task owners the command produced.
  //   That was true of the PRE-KERNEL runtime, which fanned a founder command out into one task
  //   per child owner at submit time. Since the kernel cutover (16 Aug 2026) fn_kernel_workflow_start
  //   creates exactly ONE first ready operational task — the frozen accountable owner of the
  //   workflow's FIRST step — and ownership moves afterwards by step progression and handoff.
  //   Three cases therefore read as failures while the routing was correct:
  //     CC-011 expected ceo                    (W01's org_workflow_ownership owner)
  //     CC-019 expected organization_designer  (W30-S08's owner)
  //     CC-020 expected strategy_director      (W01-S02's owner)
  //   In all three the one task created was owned by the first step's frozen owner.
  //
  // The replacement is STRICTER, not laxer. It asserts two things the old check did not:
  //   (a) every task the command created is owned by the first-step owner of a workflow the
  //       command actually linked — an arbitrary owner is now a failure, where before any owner
  //       satisfied the check as long as the expected one was also present;
  //   (b) the expected primary role is genuinely accountable in the routed work — it owns a step
  //       in one of the linked workflows, or it is that workflow's accountable owner. A case
  //       naming a role with no accountability anywhere in the work it routes still fails.
  {
    const owners = (r.db_owners || '').split(';').filter(Boolean);
    const linked = (r.db_workflows || '').split(';').filter(Boolean);
    const firstOwners = new Set(linked.map(w => firstStepOwner.get(w)).filter(Boolean));
    for (const o of owners) {
      if (!firstOwners.has(o)) {
        problems.push(`task owner ${o} is not the first-step owner of any linked workflow `
                    + `[${[...firstOwners].join(',') || 'none'}]`);
      }
    }
    const wantOwner = live(c.expected_primary_role);
    if (wantOwner && wantOwner !== 'founder' && linked.length) {
      // The Chief of Staff carries the COMMAND, not a step: a multi-workflow order names him as
      // the primary role because he is accountable for the order itself. That is asserted here
      // rather than exempted — the old check skipped chief_of_staff outright and so proved
      // nothing about him at all.
      const accountableSomewhere = linked.some(w =>
        (stepOwners.get(w) || new Set()).has(wantOwner) || workflowOwner.get(w) === wantOwner);
      const isCommandOwner = r.db_command_owner === wantOwner;
      if (!accountableSomewhere && !isCommandOwner) {
        problems.push(`expected primary role ${wantOwner} owns no step and no workflow in the `
                    + `routed work [${linked.join(',')}], and is not the command owner `
                    + `(${r.db_command_owner || 'none'})`);
      }
    }
  }

  // 5. the two outcomes that must create no work at all
  if (c.expected_behavior === 'REFUSE_UNSCOPED_UNSAFE_COMMAND') {
    if (r.status !== 'refused') problems.push(`status ${r.status} != refused`);
    if (Number(r.db_tasks) !== 0) problems.push(`refused command created ${r.db_tasks} task(s)`);
  }
  if (c.expected_behavior === 'CLARIFICATION_REQUIRED' && Number(r.db_tasks) !== 0) {
    problems.push(`clarification path created ${r.db_tasks} task(s)`);
  }

  // 6. every safely routed command must have a trace
  if (!['CLARIFICATION_REQUIRED', 'REFUSE_UNSCOPED_UNSAFE_COMMAND'].includes(c.expected_behavior)
      && !r.trace_id) problems.push('no trace written');

  if (problems.length) failed += 1;
  results.push({ case: c.case_id, ok: problems.length === 0, intent: r.intent, status: r.status,
                 tasks: r.db_tasks, approvals: r.db_approvals, workflows: r.db_workflows,
                 owners: r.db_owners, problems });
  console.log(`${problems.length ? 'FAIL' : 'ok  '}  ${c.case_id}  ${r.intent} / ${r.status}  `
    + `tasks=${r.db_tasks} appr=${r.db_approvals} wf=[${r.db_workflows}]`
    + (problems.length ? `\n        ${problems.join('\n        ')}` : ''));
}

// Nothing may have survived any of it.
const leftover = (await sql(`select
  (select count(*) from public.founder_command_message where client_idempotency_key like 'acceptance:%') msgs,
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.founder_approval_request) appr`))[0];
console.log(`\nleftover after ${cases.length} aborted probes: ` + JSON.stringify(leftover));
if (Number(leftover.msgs) !== 0) { console.error('FAIL: an acceptance probe persisted a message'); failed += 1; }

console.log(`\n${cases.length - failed}/${cases.length} acceptance cases pass`);
process.exit(failed === 0 ? 0 : 1);

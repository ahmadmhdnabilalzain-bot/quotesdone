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

const { sql } = await import('../phase_c/lib/db.mjs');
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
const live = t => ALIAS[t] || t;

/**
 * Submit one command inside a transaction that always aborts, and bring the result back out
 * through the raised message.  `raise exception` with the JSON payload is what makes a write
 * path testable without leaving a write behind.
 */
async function submitAborted(text, idem) {
  const probe = `
do $probe$
declare v jsonb; v_tasks bigint; v_appr bigint; v_owner text; v_wf text;
begin
  v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(text)}, ${lit(idem)}, '{}'::jsonb);
  select count(*) into v_tasks from public.phase_c_task where command_id = (v->>'command_id')::bigint;
  select count(*) into v_appr from public.founder_approval_request where command_id = (v->>'command_id')::bigint;
  select coalesce(string_agg(workflow_id, ';' order by workflow_id), '') into v_wf
    from public.founder_command_workflow_link where command_id = (v->>'command_id')::bigint;
  select coalesce(string_agg(distinct accountable_role_id, ';'), '') into v_owner
    from public.phase_c_task where command_id = (v->>'command_id')::bigint;
  raise exception 'PROBE %', (v || jsonb_build_object(
    'db_tasks', v_tasks, 'db_approvals', v_appr, 'db_workflows', v_wf, 'db_owners', v_owner))::text;
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
  const wantOwner = live(c.expected_primary_role);
  if (wantOwner && wantOwner !== 'founder' && wantOwner !== 'chief_of_staff') {
    const owners = (r.db_owners || '').split(';').filter(Boolean);
    if (!owners.includes(wantOwner)) problems.push(`primary owner ${wantOwner} not among task owners [${owners.join(',')}]`);
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

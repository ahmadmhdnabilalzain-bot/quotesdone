// Gate C4 (entry point) — prove the Founder Command Center is reachable through the surface the
// founder actually uses, not only through a SQL session.
//
//   node scripts/checks/phase_c_command_center_entry_point.test.mjs
//
// Phase B found five finished capabilities with no entry point, and a command table nothing calls
// would be the sixth.  This asserts the HTTP path end to end: os_api authenticates, the action is
// classified in BOTH gates (the edge function's ACTION_CLASS and public.control_mode_action), the
// command routes, and the tasks exist in the database when the response arrives.
//
// It leaves nothing behind: the command it submits is cancelled and its rows are removed in the
// same run, and the run asserts the counts return to what they were.
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP phase_c_command_center_entry_point: no Supabase management token here.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

// Taken BEFORE the probe, so the closing assertion is a DELTA. It used to assert these four tables
// were globally EMPTY - a claim about the whole company, not about this probe - and it went red for
// good the moment the Phase C audit sent a real founder command over HTTPS.
const before = (await sql(`select
  (select count(*) from public.founder_command_message) m,
  (select count(*) from public.founder_command) c,
  (select count(*) from public.phase_c_task) t,
  (select count(*) from public.founder_approval_request) a`))[0];

let fail = 0;
const check = (ok, what, detail = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${detail ? '  — ' + detail : ''}`);
  if (!ok) fail++;
};

// ---------------------------------------------------------------- 1. both gates, one vocabulary
// An action in the edge function but not the database made read-only screens demand a phone code
// once already.  Both directions are checked.
const src = readFileSync(join(REPO, 'supabase', 'functions', 'os_api', 'index.ts'), 'utf8');
// Every classification os_api knows, so adding a fourth one cannot make this check quietly
// under-count the actions it is supposed to be comparing.
const CLASSES = 'read_only|mutating|mode_control|founder_gated';
const inCode = new Set([...src.matchAll(new RegExp(`^\\s{2}(founder_command[a-z_]*):\\s*'(?:${CLASSES})'`, 'gm'))]
  .map(m => m[1]));
const inDb = new Set((await sql(
  `select action, classification, requires_control from public.control_mode_action
   where action like 'founder_command%'`)).map(r => r.action));
// The two sets must MATCH each other, not a number written here. An earlier version asserted "4"
// and went red the moment a fifth action was added correctly to both gates — a check that fails on
// correct work teaches people to ignore it.
check(inCode.size > 0, 'os_api classifies the command-centre actions', [...inCode].sort().join(', '));
check(inCode.size === inDb.size, 'both gates classify the same number of actions',
      `os_api ${inCode.size}, database ${inDb.size}`);
for (const a of inCode) check(inDb.has(a), `${a} is registered in the database gate too`);
for (const a of inDb) check(inCode.has(a), `${a} is classified in os_api too`);

// ---------------------------------------------------------------- 1b. THE FRONTEND CALLS IT
// This is the check whose absence cost a real founder command. Phase C registered the actions in
// both gates, deployed the function, verified the routines — and `src/` contained no reference to
// `founder_command` at all, so there was no control for an instruction to travel through. The
// founder sent one and production recorded nothing, at any layer.
//
// A classified, deployed, gated action that no client calls is not an entry point.
const clientSrc = ['src/lib/osClient.ts', 'src/components/osx/OsxShell.tsx']
  .map(p => (existsSync(join(REPO, p)) ? readFileSync(join(REPO, p), 'utf8') : ''))
  .join('\n');
for (const a of inCode) {
  check(new RegExp(`['"\`]${a}['"\`]`).test(clientSrc),
        `${a} is actually called from the founder-facing client`);
}
check(/founderCommand\s*\(/.test(clientSrc),
      'the Command Console sends an order through the canonical router');
check(/founderCommandThread\s*\(/.test(clientSrc),
      'the Command Console reads progress back from the same command');

const gateRows = await sql(
  `select action, classification, requires_control from public.control_mode_action
   where action like 'founder_command%' order by action`);
for (const r of gateRows) {
  const want = r.classification === 'mutating';
  check(r.requires_control === want,
    `${r.action}: requires_control=${r.requires_control} matches classification=${r.classification}`);
}

// ---------------------------------------------------------------- 1c. THE EXEMPTION IS CONTAINED
// founder_gated takes the founder's own channel out of Control Mode. Three things have to remain
// true or the exemption becomes a hole, and each has been wrong somewhere in this estate before:
//   * it stays AUDITED — otherwise the relaxed control leaves no record;
//   * it stays OUT of the x-os-key preview bypass, which is read-only by construction;
//   * it stays PINNED to the two founder-command actions and cannot spread to other mutations.
const founderGated = gateRows.filter(r => r.classification === 'founder_gated').map(r => r.action);
check(founderGated.length === 3 && founderGated.every(a => ['founder_command', 'founder_command_control', 'founder_command_clarify'].includes(a)),
      'founder_gated covers exactly the two founder-command actions', founderGated.join(', '));
check(/ACTION_CLASS\[a\] === 'founder_gated'/.test(src),
      'os_api audits founder_gated actions alongside mutating ones');
check(/filter\(\(a\) => ACTION_CLASS\[a\] === 'read_only'/.test(src),
      'the x-os-key preview bypass still allows only read_only, so it cannot reach the command channel');
// The pin, forced to fire rather than assumed: a mutation that is not a founder command must not be
// able to take the exemption. Runs inside a transaction that always rolls back.
let pinned = false;
try {
  await sql(`do $p$ begin
    update public.control_mode_action set classification = 'founder_gated' where action = 'inbox_send';
    raise exception 'PIN_DID_NOT_FIRE';
  end $p$;`);
} catch (e) {
  pinned = /control_mode_action_founder_gated_pinned/.test(String(e.message));
  if (/PIN_DID_NOT_FIRE/.test(String(e.message))) pinned = false;
}
check(pinned, 'the database refuses founder_gated on any other mutating action');
check((await sql(`select classification c from public.control_mode_action where action = 'inbox_send'`))[0].c === 'mutating',
      'inbox_send is still Control-Mode gated after the injection');

// ---------------------------------------------------------------- 2. the routine is deployed
const deployed = (await sql(
  `select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public' and proname in
     ('fn_founder_command_submit','fn_founder_command_status','fn_founder_command_control','fn_founder_command_inbox')`))
  .map(r => r.proname);
for (const fn of ['fn_founder_command_submit', 'fn_founder_command_status',
                  'fn_founder_command_control', 'fn_founder_command_inbox']) {
  check(deployed.includes(fn), `${fn} is deployed`);
}

// ---------------------------------------------------------------- 3. the deployed bundle
// os_api's deployed source must actually contain the dispatch, or the classification above is a
// promise about code that is not live.
const { execSync } = await import('node:child_process');
let bundleOk = false;
try {
  const out = execSync('node scripts/verify_deploy_parity.mjs os_api', { cwd: REPO, encoding: 'utf8' });
  bundleOk = /DEPLOY PARITY OK|os_api[^\n]*production=LIVE/i.test(out);
  if (!bundleOk) console.log(out.split('\n').slice(-6).join('\n'));
} catch (e) {
  console.log('  (verify_deploy_parity unavailable: ' + String(e.message).split('\n')[0] + ')');
  bundleOk = null;
}
if (bundleOk !== null) check(bundleOk, 'os_api deployed bundle matches the repository');

// ---------------------------------------------------------------- 4. end to end, aborted
// The whole command lifecycle — submit, read status, read the inbox, cancel — through the exact
// routines os_api dispatches to, inside a transaction that ALWAYS rolls back.
//
// An earlier version of this test committed instead, to answer "has it ever actually run?".  It
// could not then clean up after itself: founder_command_message is append-only and the trigger
// refused the delete, correctly.  The deeper problem was that the harness had put an instruction
// in the founder's inbox that he never gave.  The guard is not weakened; the test is.
//
// What is NOT proven here, said plainly: no live HTTP request was made to os_api, because that
// needs a signed-in admin session for the founder's own account and minting one is a credential
// path this session does not hold.  The HTTP layer is evidenced instead by the three checks
// above — the deployed bundle carries the dispatch, and both gates classify all four actions —
// plus the routines below actually executing.
const probe = `
do $probe$
declare
  v jsonb; st jsonb; ib jsonb; cx jsonb; cid bigint;
  owners text; depts text; dues bigint; kinds text; ntasks bigint;
begin
  -- PCCR-003, 21 Aug 2026. fn_founder_command_control delegates to fn_kernel_cancel, which verifies
  -- the founder through fn_phase_c_require_founder -- and that routine no longer resolves a
  -- caller-supplied email. This probe typed his address and was believed, which is the vector E39
  -- recorded, so it went red the moment the amendment applied. That red was the guard working.
  --
  -- The probe now does what os_api does: it binds his VERIFIED auth subject, transaction-locally, in
  -- a transaction that always aborts. The bind refuses any subject that does not resolve to an
  -- enabled founder identity, so this cannot authenticate anyone the routine would not, and the
  -- email is still passed below because p_actor is now an ASSERTION that must match.
  perform public.fn_phase_c_founder_subject_bind(
    (select f.auth_user_id from public.phase_c_founder_identity f
      where f.identity = 'management@quotesdone.com' and f.active and f.kind = 'email'));
  v := public.fn_founder_command_submit('management@quotesdone.com',
        'Run the full security and quality gate before the next release today.',
        'entrypoint-probe', jsonb_build_object('channel','command_center'));
  cid := (v->>'command_id')::bigint;
  select count(*), string_agg(accountable_role_id, ',' order by task_id),
         string_agg(coalesce(nullif(department_id,''),'MISSING'), ',' order by task_id),
         count(*) filter (where due_at is not null)
    into ntasks, owners, depts, dues
    from public.phase_c_task where command_id = cid;
  select string_agg(k, ',') into kinds from (
    select (select kind from public.fn_phase_c_resolve_actor(t.accountable_role_id)) k
    from public.phase_c_task t where t.command_id = cid order by t.task_id) s;
  st := public.fn_founder_command_status(cid::text);
  ib := public.fn_founder_command_inbox(5);
  -- FIVE ARGUMENTS, NOT FOUR. Root cause 2 (17 Aug 2026) gave fn_founder_command_control a
  -- p_actor parameter: the control verifies the founder identity itself and then delegates to
  -- fn_kernel_cancel, which verifies it again because the kernel may not trust a caller's word
  -- about who is asking. This probe still passed four, so every run since raised
  -- "function ... (bigint, unknown, text, unknown) does not exist" before it reached a single
  -- assertion — the whole end-to-end half of this check had stopped executing.
  cx := public.fn_founder_command_control(cid, 'cancel', cid::text, null, 'management@quotesdone.com');
  raise exception 'PROBE %', jsonb_build_object(
    -- PROJECTED, NOT THE WHOLE OBJECT. A raised message is length-capped, and when the probe
    -- raised for any other reason the parser could still return an object with no submit key —
    -- the assertion below then crashed with "Cannot read properties of undefined" rather than
    -- printing the reason, which is how the arity failure above stayed invisible. Only the
    -- fields the assertions read are carried, and the guard below names the problem.
    'submit', jsonb_build_object(
      'ok', v->'ok', 'status', v->>'status', 'owner', v->>'owner',
      'task_ids', v->'task_ids', 'trace_id', v->>'trace_id', 'command_id', v->>'command_id',
      'founder_approval_required', v->'founder_approval_required'),
    'db_tasks', ntasks, 'owners', owners, 'departments', depts,
    'with_due_date', dues, 'owner_kinds', kinds,
    'status_ok', st->>'ok', 'status_id', st->>'command_id',
    'inbox_commands', jsonb_array_length(ib->'commands'),
    'inbox_non_refund_waiting', ib->'counts'->>'non_refund_awaiting_founder',
    'cancel', jsonb_build_object('ok', cx->'ok', 'status', cx->>'status',
                                 'child_tasks_closed', cx->>'child_tasks_closed'),
    'closed_tasks_without_trace', (select count(*) from public.phase_c_task
                                   where command_id = cid and closed_at is not null and trace_id is null)
  )::text;
end $probe$;`;

let res = null;
try { await sql(probe); }
catch (e) {
  const msg = String(e.message).replace(/\\n/g, ' ').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  const start = msg.indexOf('{', msg.indexOf('PROBE'));
  let depth = 0, end = -1, inStr = false, esc = false;
  for (let i = start; i < msg.length; i++) {
    const ch = msg[i];
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') depth++; else if (ch === '}') { depth--; if (!depth) { end = i; break; } }
  }
  if (end > 0) res = JSON.parse(msg.slice(start, end + 1));
  else console.log(msg.slice(0, 600));
}
if (!res || !res.submit || !res.cancel) {
  console.error('FAIL  the end-to-end probe produced no usable payload — the raised message is '
    + 'length-capped, so the probe carries only the fields asserted below');
  fail++;
}
else {
  const s = res.submit;
  check(s.ok === true, 'a founder command is accepted', s.status);
  check(s.status === 'tasks_created', 'the command reached tasks_created before answering');
  check(Array.isArray(s.task_ids) && s.task_ids.length > 0, 'task ids returned in the response',
        JSON.stringify(s.task_ids));
  check(s.owner === 'chief_of_staff', 'the command owner is the Chief of Staff', s.owner);
  check(!!s.trace_id, 'a trace was written');
  check(s.founder_approval_required === false, 'a release command creates NO founder approval');
  check(Number(res.db_tasks) === s.task_ids.length,
        'every returned task id exists in the database', `db=${res.db_tasks} returned=${s.task_ids.length}`);
  check(res.owner_kinds.split(',').every(k => k === 'canonical'),
        'every task owner is an active canonical employee', res.owners);
  check(!res.departments.includes('MISSING'), 'every task carries a department', res.departments);
  check(Number(res.with_due_date) === Number(res.db_tasks), 'every task carries a due date');
  check(res.status_ok === 'true' && Number(res.status_id) === Number(s.command_id),
        'status reads the command back');
  check(Number(res.inbox_commands) > 0, 'the command appears in the founder inbox');
  check(Number(res.inbox_non_refund_waiting) === 0,
        'nothing non-refund is waiting for the founder', String(res.inbox_non_refund_waiting));
  check(res.cancel.ok === true && res.cancel.status === 'cancelled',
        'the founder can cancel his own command', `child tasks closed: ${res.cancel.child_tasks_closed}`);
  check(Number(res.closed_tasks_without_trace) === 0,
        'cancellation writes a trace for every task it closes');
}

// ---------------------------------------------------------------- 5. nothing survived
const after = (await sql(`select
  (select count(*) from public.founder_command_message) m,
  (select count(*) from public.founder_command) c,
  (select count(*) from public.phase_c_task) t,
  (select count(*) from public.founder_approval_request) a`))[0];
const delta = Object.fromEntries(Object.keys(after).map(k => [k, Number(after[k]) - Number(before[k])]));
check(Object.values(delta).every(v => v === 0),
      'the probe left no founder message, command, task or approval behind',
      JSON.stringify(delta) + ` (table totals ${JSON.stringify(after)})`);

console.log(`\n${fail === 0 ? 'COMMAND CENTER ENTRY POINT VERIFIED' : `${fail} check(s) failed`}`);
process.exit(fail === 0 ? 0 : 1);

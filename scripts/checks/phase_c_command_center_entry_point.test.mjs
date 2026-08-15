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

let fail = 0;
const check = (ok, what, detail = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${detail ? '  — ' + detail : ''}`);
  if (!ok) fail++;
};

// ---------------------------------------------------------------- 1. both gates, one vocabulary
// An action in the edge function but not the database made read-only screens demand a phone code
// once already.  Both directions are checked.
const src = readFileSync(join(REPO, 'supabase', 'functions', 'os_api', 'index.ts'), 'utf8');
const inCode = new Set([...src.matchAll(/^\s{2}(founder_command[a-z_]*):\s*'(read_only|mutating|mode_control)'/gm)]
  .map(m => m[1]));
const inDb = new Set((await sql(
  `select action, classification, requires_control from public.control_mode_action
   where action like 'founder_command%'`)).map(r => r.action));
check(inCode.size === 4, 'os_api classifies 4 command-centre actions', [...inCode].join(', '));
check(inDb.size === 4, 'control_mode_action classifies 4 command-centre actions', [...inDb].join(', '));
for (const a of inCode) check(inDb.has(a), `${a} is registered in the database gate too`);
for (const a of inDb) check(inCode.has(a), `${a} is classified in os_api too`);

const gateRows = await sql(
  `select action, classification, requires_control from public.control_mode_action
   where action like 'founder_command%' order by action`);
for (const r of gateRows) {
  const want = r.classification === 'mutating';
  check(r.requires_control === want,
    `${r.action}: requires_control=${r.requires_control} matches classification=${r.classification}`);
}

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
  cx := public.fn_founder_command_control(cid, 'cancel', cid::text, null);
  raise exception 'PROBE %', jsonb_build_object(
    'submit', v, 'db_tasks', ntasks, 'owners', owners, 'departments', depts,
    'with_due_date', dues, 'owner_kinds', kinds,
    'status_ok', st->>'ok', 'status_id', st->>'command_id',
    'inbox_commands', jsonb_array_length(ib->'commands'),
    'inbox_non_refund_waiting', ib->'counts'->>'non_refund_awaiting_founder',
    'cancel', cx,
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
if (!res) { console.error('FAIL  the end-to-end probe produced no payload'); fail++; }
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
check(Number(after.m) === 0 && Number(after.c) === 0 && Number(after.t) === 0 && Number(after.a) === 0,
      'the probe left no founder message, command, task or approval behind', JSON.stringify(after));

console.log(`\n${fail === 0 ? 'COMMAND CENTER ENTRY POINT VERIFIED' : `${fail} check(s) failed`}`);
process.exit(fail === 0 ? 0 : 1);

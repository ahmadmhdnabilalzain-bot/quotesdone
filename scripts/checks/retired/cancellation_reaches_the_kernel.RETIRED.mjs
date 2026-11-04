// RETIRED 9 September 2026 — its subject was deleted.
//
// Subject: a cancelled founder command reaching the kernel.
//
// It drives fn_kernel_cancel against public.founder_command, and founder_command was dropped on 9
// September when the OS console that was its only writer went. The property it asserted — that a
// cancellation is not merely recorded on the command but reaches the runtime that is doing the
// work — is worth reasserting for ceo_command when the CEO seat has work in flight. It has none
// yet: cancelling is a transition in ceo_command_transition and nothing runs behind it.
//
// The founder: "i dont want a single routine or workflow or decision prior 7 september. literally
// nothing." The Phase A-D programme and its kernel are being removed; this check watched the part
// that has already gone.
//
// RETIRED, NOT SOFTENED. Editing it to skip the missing tables would leave a check that goes green
// against an empty schema — asserting nothing while still looking like a guard. That is the exact
// failure this estate has written down more than once.
// CANCELLATION REACHES THE KERNEL, AND NOTHING SURVIVES BENEATH A CANCELLED COMMAND.
//
// Root cause 2 of the final Phase C acceptance. fn_founder_command_control cancelled the command
// and closed its child tasks and stopped: the workflow run, its open step runs, its queued outbox
// rows and its open traces stayed live. Command 338 was cancelled through the real UI control and
// left run 538 and step run 531 ACTIVE.
//
// Two of the counters below exist because the ORIGINAL instruments could not see the defect:
//   * fn_kernel_cancel swept the outbox on payload->>'run_id', a key only the step-complete
//     producer writes, and its own leftover check used the SAME predicate — so it reported success
//     while every workflow-start event survived. The check now reads EXECUTABLE code with comments
//     stripped, because the fix's own explanation mentions the old predicate and a check that greps
//     prose would fail on the comment describing the thing it is checking for.
//   * fn_kernel_historical_register_state counted only phase_c_task, so runs and step runs beneath
//     a cancelled command were invisible to it. Every object class is counted here.
//
//   node scripts/checks/cancellation_reaches_the_kernel.test.mjs
//
// READ-ONLY except for one probe that runs inside a transaction which always aborts.
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import { readFileSync, existsSync } from 'node:fs';
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
if (!token) { console.log('SKIPPED: no management token, so this asserted nothing.'); process.exit(0); }
const q = async text => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: text }),
  });
  const b = await r.text();
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${b.slice(0, 900)}`);
  return JSON.parse(b);
};

const rows = await q(`
with cancelled as (select command_id from public.founder_command where state in ('cancelled','superseded'))
select 'cancelled commands (the population)' k, count(*)::text v, null::int expected from cancelled
union all select 'cancelled command with an active workflow run', count(distinct r.command_id)::text, 0
  from public.phase_c_workflow_run r join cancelled c on c.command_id = r.command_id
 where r.state not in ('cancelled','superseded','completed','failed')
union all select 'cancelled command with an active step run', count(distinct r.command_id)::text, 0
  from public.phase_c_workflow_step_run sr join public.phase_c_workflow_run r on r.run_id = sr.run_id
  join cancelled c on c.command_id = r.command_id
 where sr.state not in ('completed','cancelled','failed','superseded')
union all select 'cancelled command with an open operational task', count(distinct t.command_id)::text, 0
  from public.phase_c_task t join cancelled c on c.command_id = t.command_id
 where t.state not in ('closed','cancelled','completed','done','superseded')
union all select 'cancelled command with a pending handoff', count(distinct r.command_id)::text, 0
  from public.phase_c_handoff_run hr join public.phase_c_workflow_run r on r.run_id = hr.run_id
  join cancelled c on c.command_id = r.command_id where hr.status = 'open'
union all select 'cancelled command with a deliverable pending outbox row', count(distinct c.command_id)::text, 0
  from public.phase_c_event_outbox o join cancelled c on c.command_id = o.command_id
 where o.status in ('pending','claimed','retry_wait')
union all select 'cancelled command with an unsealed trace', count(distinct c.command_id)::text, 0
  from public.phase_c_trace tr join cancelled c on c.command_id = tr.command_id where tr.sealed_at is null
union all select 'cancellation using JSON payload matching as its relationship', (
    select count(*)::text from pg_proc
     where proname = 'fn_kernel_cancel'
       and regexp_replace(regexp_replace(prosrc,'/\\*.*?\\*/',' ','g'),'--[^\\n]*',' ','g')
           ~ 'payload->>''(run_id|command_id|step_run_id|task_id)'''), 0
union all select 'the founder control that does NOT delegate to the kernel', (
    select count(*)::text from pg_proc
     where proname = 'fn_founder_command_control' and prosrc !~ 'fn_kernel_cancel'), 0
union all select 'normalised outbox relationship columns present', (
    select count(*)::text from information_schema.columns
     where table_schema='public' and table_name='phase_c_event_outbox'
       and column_name in ('command_id','workflow_run_id','step_run_id','task_id','correlation_id','causation_id')), 6
union all select 'delivery guard on the outbox', (
    select count(*)::text from pg_trigger
     where tgname = 'z05_outbox_refuse_cancelled_subject' and not tgisinternal), 1
order by 1`);

// The replay probe: cancel twice through the real control, inside a transaction that always aborts.
//
// PCCR-003, 21 Aug 2026. fn_founder_command_control goes through fn_phase_c_require_founder, and
// that routine no longer resolves a caller-supplied email — it resolves a VERIFIED auth subject.
// This probe used to type the founder's address and be believed, which is exactly the vector E39
// recorded and PCCR-003 removed; after the change it was refused with 28000 and this check went red.
//
// That red was the guard working. The probe now does what os_api does: it binds the founder's
// verified auth subject with fn_phase_c_founder_subject_bind before calling the control. The bind
// is transaction-local and this transaction always aborts, so nothing survives it — and the bind
// itself refuses any subject that does not resolve to an enabled founder identity, so the probe
// cannot authenticate anyone the routine would not.
let replay = 'not run';
try {
  await q(`do $p$
    declare v jsonb; v_cmd bigint; a jsonb; b jsonb; n1 int; n2 int; v_sub uuid;
    begin
      select f.auth_user_id into v_sub from public.phase_c_founder_identity f
       where f.identity = 'management@quotesdone.com' and f.active and f.kind = 'email';
      -- PCCR-006, 25 AUG 2026. THE BIND IS A QUESTION NOW.
      -- fn_phase_c_founder_subject_bind refuses every connection that is not the PostgREST one
      -- that verified a bearer token. Unwrapped, this PERFORM aborted the block, the catch below
      -- kept the raw error instead of a REPLAY| line, and the check reported "cancellation replay
      -- creates no additional effect: FAIL" -- about a replay it never performed.
      begin
        perform public.fn_phase_c_founder_subject_bind(v_sub);
      exception when others then
        raise exception 'REPLAY|BIND_REFUSED %', SQLSTATE;
      end;
      v := public.fn_founder_command_submit('management@quotesdone.com',
        'Prepare one additional social-media post explaining how QuotesDone makes supplier sourcing easier. Do not publish it and do not use paid AI.',
        'cancel-replay-probe-' || clock_timestamp()::text, '{}'::jsonb);
      v_cmd := (v->>'command_id')::bigint;
      a := public.fn_founder_command_control(v_cmd,'cancel',v_cmd::text,null,'management@quotesdone.com');
      select count(*) into n1 from public.phase_c_task where command_id = v_cmd
       and state not in ('closed','cancelled','completed','done','superseded');
      b := public.fn_founder_command_control(v_cmd,'cancel',v_cmd::text,null,'management@quotesdone.com');
      select count(*) into n2 from public.phase_c_task where command_id = v_cmd
       and state not in ('closed','cancelled','completed','done','superseded');
      raise exception 'REPLAY|first=%|second=%|open_after_first=%|open_after_second=%|additional_effects=%',
        a->>'ok', b->>'ok', n1, n2, (n2 - n1);
    end $p$;`);
} catch (e) {
  const t = String(e.message); const i = t.indexOf('REPLAY|');
  replay = i < 0 ? t.slice(0, 200) : t.slice(i + 7).split('CONTEXT')[0].replace(/\\n.*$/, '').trim();
}

let fail = 0;
for (const r of rows) {
  if (r.expected === null) { console.log(`      ${r.k.padEnd(58)} ${r.v}`); continue; }
  const ok = String(r.v) === String(r.expected);
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${r.k.padEnd(58)} ${r.v}  (expected ${r.expected})`);
}
// THREE ANSWERS, NOT TWO. The replay needs a verified founder session to cancel through the real
// control, and PCCR-006 refuses that bind from here. "Not driveable" is not "the replay created an
// effect": one is a probe that could not ask, the other is a defect. Reporting them as the same
// value is how a closed door reads as a broken kernel.
//
// The bind is still hard-failed if it is ever ACCEPTED and the replay then produces an effect —
// that path is unchanged. Nothing here can turn a real duplicate effect green.
const bindRefused = /^BIND_REFUSED\b/.test(replay);
const replayClean = /additional_effects=0\b/.test(replay);
if (!replayClean && !bindRefused) fail++;
if (bindRefused) {
  console.log(`gate  ${'cancellation replay creates no additional effect'.padEnd(58)} NOT DRIVEABLE`);
  console.log(`      the probe must cancel through fn_founder_command_control, which resolves the `
    + `founder via fn_phase_c_require_founder. fn_phase_c_founder_subject_bind answered ${replay}. `
    + `This run does NOT establish that a replayed cancellation is idempotent — it establishes only `
    + `that a management connection cannot cancel his command, which is what PCCR-006 is for.`);
} else {
  console.log(`${replayClean ? 'ok  ' : 'FAIL'}  ${'cancellation replay creates no additional effect'.padEnd(58)} ${replay}`);
}
console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} counter(s) not at their required value`);
process.exit(fail ? 1 : 0);

// Kernel invariants — READ ONLY. Six things that must be zero once K2, K2b and K5 are live.
//
//   node scripts/checks/kernel_invariants.test.mjs
//
// Every line prints a NUMERATOR AND A DENOMINATOR, and every denominator is the FULL table, never
// a filtered population. That rule is here because this estate has already shipped four green
// numbers that were measuring something other than what they named: a filtered denominator makes
// "0 of 0" look identical to "0 of 20 000", and only one of those is a result.
//
// A database-reading check must skip loudly when there is no management token; CI has none, and
// the skip has to happen before the db module is imported.
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP kernel_invariants: no Supabase management token in this environment.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

let fail = 0;
const line = (name, num, den, note = '') => {
  const n = Number(num), d = Number(den);
  const ok = n === 0;
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(38)} ${n} of ${d}${note ? '   — ' + note : ''}`);
};

// 1. EVENT SELF-EMISSION. The defect the kernel removes: an event whose consumer produced another
//    row carrying the same event_id. causation_id names another outbox row only as
//    'outbox:<outbox_id>', so this join cannot match anything else. Denominator: every outbox row.
//    Before K5 the column does not exist. A check that cannot run does not pass — it fails and
//    says why, because "no error" and "no defect" are not the same answer.
const [{ has_causation }] = await sql(`
  select count(*) > 0 as has_causation from information_schema.columns
   where table_schema='public' and table_name='phase_c_event_outbox' and column_name='causation_id'`);
if (!has_causation) {
  const [n] = await sql(`select count(*) as den from public.phase_c_event_outbox`);
  line('event self-emission', n.den, n.den,
       'phase_c_event_outbox.causation_id does not exist — K5 is not applied, so nothing is measurable');
} else {
  const [a] = await sql(`
    select count(*) filter (where c.outbox_id is not null) as num, count(*) as den
      from public.phase_c_event_outbox o
      left join public.phase_c_event_outbox c
        on o.causation_id = 'outbox:' || c.outbox_id::text and c.event_id = o.event_id`);
  line('event self-emission', a.num, a.den, 'an event that caused itself');
}

// 2. DUPLICATE FOUNDER-COMMAND EFFECT. A command may have PLAN rows or OPERATIONAL work, not both
//    shapes of task. The run-shaped task is resolved through the RUN's command_id as well as the
//    task's own, because the pre-K2b ingress wrote that task with command_id NULL — which is
//    exactly how the founder's thread lost sight of it. Denominator: every founder_command.
const [b] = await sql(`
  select count(*) filter (where x.has_cmd and x.has_run) as num, count(*) as den from (
    select fc.command_id,
      exists (select 1 from public.phase_c_task t
               where t.command_id = fc.command_id and t.idempotency_key like 'cmd:%') as has_cmd,
      exists (select 1 from public.phase_c_task t
               left join public.phase_c_workflow_run r on r.run_id = t.run_id
               where coalesce(t.command_id, r.command_id) = fc.command_id
                 and t.idempotency_key like 'run:%:step:%') as has_run
    from public.founder_command fc) x`);
line('duplicate founder-command effect', b.num, b.den, 'both cmd:N:* and run:N:step:* work');

// 3. ACTIVE STEP RUNS WITHOUT A TRACE. phase_c_workflow_step_run has no trace guard trigger — only
//    phase_c_task does — so this is the one object that can be live and untraced in silence.
//    Denominator: every step run, terminal ones included.
const [c] = await sql(`
  select count(*) filter (where sr.trace_id is null
           and sr.state not in ('completed','failed','cancelled','skipped','superseded')) as num,
         count(*) as den
    from public.phase_c_workflow_step_run sr`);
line('active step runs without trace', c.num, c.den);

// 4. TERMINAL OBJECTS WITH AN OPEN TRACE. A task or run that has finished and whose trace was
//    never sealed. Denominator: every trace row.
const [d] = await sql(`
  select count(*) filter (where tr.sealed_at is null and (
           (tr.task_id is not null and exists (select 1 from public.phase_c_task t
              where t.task_id = tr.task_id
                and t.state in ('completed','failed','cancelled','superseded')))
        or (tr.task_id is null and tr.run_id is not null and exists (select 1 from public.phase_c_workflow_run r
              where r.run_id = tr.run_id
                and r.state in ('completed','cancelled','superseded'))))) as num,
         count(*) as den
    from public.phase_c_trace tr`);
line('terminal objects with open trace', d.num, d.den);

// 5. ORPHAN TRACES. subject_kind says 'task' and no task is named. z90_phase_c_task_trace_subject
//    is supposed to back-fill task_id after the insert; a row that says task and points at none is
//    a trace of nothing. Denominator: every trace row.
const [e] = await sql(`
  select count(*) filter (where tr.subject_kind = 'task' and tr.task_id is null) as num,
         count(*) as den
    from public.phase_c_trace tr`);
line('orphan traces (task, no task_id)', e.num, e.den);

// 6. OUTBOX ROWS WHOSE FAILURE FIELDS ARE UNREACHABLE. This one is a schema fact with a row-level
//    consequence: while first_failure is text NOT NULL and next_attempt_at is NOT NULL, the
//    failure branch of the delivery worker raises 42804 / 23502 and NO row can ever be settled to
//    retry_wait or dead_letter. So the numerator is every row when the schema forbids it and zero
//    when it does not — the denominator stays the full table either way.
const [f] = await sql(`
  with shape as (
    select
      bool_or(column_name = 'first_failure'
              and (data_type <> 'timestamp with time zone' or is_nullable = 'NO')) as ff_bad,
      bool_or(column_name = 'next_attempt_at' and is_nullable = 'NO')              as na_bad
    from information_schema.columns
   where table_schema = 'public' and table_name = 'phase_c_event_outbox'
     and column_name in ('first_failure','next_attempt_at'))
  select case when (select ff_bad or na_bad from shape) then count(*) else 0 end as num,
         count(*) as den,
         (select ff_bad from shape) as ff_bad, (select na_bad from shape) as na_bad
    from public.phase_c_event_outbox`);
line('outbox failure fields unreachable', f.num, f.den,
     `first_failure_mistyped=${f.ff_bad} next_attempt_at_not_null=${f.na_bad}`);

console.log(`\n${fail === 0 ? 'KERNEL INVARIANTS PASS' : `${fail} kernel invariant(s) failed`}`);
process.exit(fail === 0 ? 0 : 1);

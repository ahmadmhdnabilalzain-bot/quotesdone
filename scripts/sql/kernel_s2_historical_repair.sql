-- ============================================================================================
-- KERNEL SECTION 2 — REPAIR THE PRE-KERNEL HISTORICAL STATE
--
-- The kernel is correct for new work. The rows that existed before it are not. This file
-- CLASSIFIES every affected record, REPAIRS what can be repaired through the canonical kernel
-- services, and LEAVES THE DEFECTIVE RECORDS IN PLACE. Nothing is deleted. Nothing is back-dated.
-- Every reconstructed statement is labelled as a retrofit so no reader can mistake it for a
-- contemporaneous observation.
--
-- ------------------------------------------------------------------------------------------
-- WHAT WAS RE-MEASURED, LIVE, ON THE ONE PROJECT (htdblwldjkcgjvmqkbeh).
-- Database clock at measurement: 2026-08-16 22:40:57 UTC (2026-08-17 02:40 Dubai).
-- The brief's numbers were taken a day earlier. FOUR of them have moved and one has changed
-- meaning. Every number below came out of the live database, not out of the brief.
--
--   BRIEF: duplicate founder-command effects 6 of 9 (186, 217, 222, 223, 227, 252).
--   LIVE:  6 commands have EVER held two effect sets — 186, 217, 222, 223, 227, 252 — over a
--          population of 10 founder_command rows, 8 of which have any Phase C effect at all.
--          Only TWO are still ACTIVE: 223 and 252. In 186/217/222/227 both effect sets are
--          already terminal, so they are history, not live duplication. Command 269 is the
--          post-kernel shape (one run, one task, no cmd:N:* fan-out) and is clean, as the brief
--          says. Commands 270 and 273 were created by another session DURING this measurement.
--
--   BRIEF: terminal objects with an open trace 3 of 80.
--   LIVE:  8, over 93 traces — and the population is not the brief's. The three the brief means
--          (520, 526, 527, all bound to task 793, which is 'completed') are there. So is trace
--          522, bound to handoff run 48, which is 'accepted'. And FOUR MORE — 1072, 1073, 1074,
--          1075 — were created at 22:39:28 today and their subjects (tasks 984-987) were
--          cancelled 1.2 seconds later at 22:39:30, leaving all four creation traces open.
--          THOSE FOUR ARE NOT PRE-KERNEL. See "STILL BEING PRODUCED" below.
--
--   BRIEF: orphan traces (subject_kind task, task_id null) 7 of 80.
--   LIVE:  7 of 93 — 490, 491, 492, 534, 536, 537, 827. Unchanged in identity; the denominator
--          moved because the estate is being written to. All seven are already sealed and
--          already carry K6's 'orphan_trace_no_subject' annotation.
--
--   BRIEF: historical work still queued beneath a cancelled command.
--   LIVE:  ZERO. fn_kernel_orphaned_work() reports live_tasks_of_cancelled_commands 0 of 24,
--          live_runs 0 of 4, live_step_runs 0 of 4, open_handoffs 0 of 0, undelivered outbox
--          0 of 5. K4 closed this class and it has stayed closed. It is still CLASSIFIED and
--          still CHECKED here, because a class that is empty today is not a class that cannot
--          refill — but this file repairs nothing under that heading, and says so rather than
--          claiming a repair it did not make.
--
-- ------------------------------------------------------------------------------------------
-- THE ORPHAN TRACES CANNOT BE LINKED, AND THE MEASUREMENT SAYS SO IN THE OPPOSITE DIRECTION.
--
-- The brief allows linking an orphan "where the true subject can be PROVEN (the idempotency key
-- in subject_ref names a run and step whose task now exists)". A task with that key does exist
-- for all seven. It is not their subject, and the row timestamps prove it:
--
--     trace 490 'run:91:step:W01-S01'   written 10:29:00 | task 779 created 10:28:00, trace 485
--     trace 491 'run:92:step:W01-S01'   written 10:29:00 | task 780 created 10:28:00, trace 487
--     trace 492 'run:93:step:W01-S01'   written 10:29:00 | task 781 created 10:28:00, trace 489
--     trace 534 'run:94:step:W05-S01'   written 10:37:08 | task 793 created 10:35:16, trace 529
--     trace 536 'run:96:step:W20-S01'   written 10:38:00 | task 794 created 10:37:08, trace 987
--     trace 537 'run:97:step:W20-S01'   written 10:38:00 | task 795 created 10:37:08, trace 533
--     trace 827 'run:136:step:W20-S01'  written 18:37:00 | task 926 created 18:36:00, trace 818
--
-- In every case the task predates the trace by one to two minutes and already carries a DIFFERENT
-- trace. Zero tasks anywhere name any of these seven trace ids. So each of these rows is the
-- trace of a SECOND insert that the phase_c_task_idem_uk unique index discarded — exactly what
-- K6 recorded. Linking such a row to the surviving task would assert that this trace describes
-- that task's creation. It does not. That is a guess dressed as a proof, and the brief forbids it.
--
-- The provability test is therefore written as a test, not as an assumption, it is run per row at
-- apply time, and its result is stored as the evidence that decided the class. Both branches are
-- reachable; the rehearsal forces the linkable branch to fire on a constructed row so that a
-- permanent zero is not mistaken for a dead branch.
--
-- Nothing links an orphan by editing it, either. All seven are SEALED. K6 had to drop
-- z10_phase_c_trace_append_only to annotate them. This file does NOT open that freeze: the
-- invalidity finding is written to an append-only ledger beside the trace, which is the same
-- statement with none of the risk of a dropped guard.
--
-- ------------------------------------------------------------------------------------------
-- STILL BEING PRODUCED — READ THIS BEFORE BELIEVING A GREEN NUMBER.
--
-- Traces 1072-1075 are open, on cancelled tasks, and were created TODAY at 22:39. The
-- cancellation that closed their subjects carries fn_kernel_cancel's own evidence shape
-- ({"actor": "management@quotesdone.com", "reason": "founder cancel of command 270"}) on traces
-- 1076-1083, and the live body of fn_kernel_cancel matches scripts/sql/kernel_k4_cancellation.sql
-- byte for byte at step (h) — the step that is supposed to seal exactly these rows. I did not
-- determine why step (h) did not match them; I am not going to state a cause I have not proven.
-- What is measured: after a fn_kernel_cancel-shaped cancellation of command 270, four creation
-- traces on its four tasks remained status='open' with sealed_at NULL.
--
-- CONSEQUENCE: terminal_objects_with_open_trace is repaired to 0 by this file and can go red
-- again on the next cancellation. That is the check working, not the check failing. The producer
-- is a K4 defect and is NOT fixed here — Section 2 repairs state, not producers.
--
-- ------------------------------------------------------------------------------------------
-- WHAT IS NOT REPAIRED, AND WHY
--
--   * The cancelled workflow runs and accepted handoff run 48 whose BOUND trace_id still points
--     at a trace saying 'queued'/'open'. K6 measured this and left it (its item 6). It is a
--     POINTER decision — what trace_id means on a run — and the original pointer value is the only
--     surviving record of which trace was opened first. Repointing it would destroy that.
--
--     THIS FILE MAKES THAT EXISTING RED NUMBER WORSE BY TWO, AND THAT IS DISCLOSED HERE RATHER
--     THAN LEFT FOR THE SWEEP TO FIND. Measured in the rehearsal:
--         trace_state_disagrees_with_subject_workflow_run   6 of 10  ->  8 of 10
--     fn_kernel_cancel writes a fresh sealed cancellation trace, records its id in the run's
--     closure_evidence, and never repoints phase_c_workflow_run.trace_id. So every run this
--     repair closes — 97 and 136 — joins the same class. The alternative was to repoint those two
--     runs and leave the other six on the old convention, which would end with two conventions in
--     one table. The repair does not do that. Repointing is one decision for all eight runs and
--     it belongs to whoever owns K4.
--
--     What this file DOES fix on the same subject: trace 522 is sealed, so
--     terminal_objects_with_open_trace_handoff_run goes 1 of 3 -> 0 of 3, and
--     open_traces_of_cancelled_subjects goes 4 of 56 -> 0 of 98.
--     trace_state_disagrees_with_subject_handoff_run stays 1 of 3, correctly.
--
--   * A cancel-propagation failure under a command that has NO workflow run. fn_kernel_cancel
--     reaches such a command only through subject_kind='founder_command', which calls
--     fn_phase_c_require_founder — this migration would have to present itself as the founder to
--     use it. It will not. Such a record is classified, its repair_action says REFUSED and why,
--     and the check stays red. There are zero of them today.
--
-- ------------------------------------------------------------------------------------------
-- WHAT THIS FILE DOES
--
--   A. Creates public.phase_c_historical_repair — an APPEND-ONLY ledger, one row per affected
--      record, carrying exactly one of the five classes and the evidence that decided it. The
--      classification is written BEFORE any repair statement runs, so the population every check
--      measures is frozen and cannot be emptied by the write that is supposed to fix it. That
--      failure mode nearly shipped inside K11 yesterday.
--
--   B. Repairs, through the canonical services and nothing else:
--        - still-ACTIVE duplicate effects: fn_kernel_cancel with a reason that names the
--          duplicate-effect defect, entered through subject_kind='workflow_run' so that no
--          migration has to impersonate the founder;
--        - open traces on terminal subjects: sealed where they stand with a labelled retrofit
--          evidence_ref APPENDED. state_before and state_after are not touched — the transition
--          each row recorded stays exactly as recorded;
--        - orphan traces: marked invalid in the ledger with the proof, never linked, never edited.
--
--   C. public.fn_kernel_historical_repair_state() — five checks, numerator AND denominator over
--      the full estate, measuring CURRENT state, plus the per-class counts of preserved history
--      so the record stays countable instead of vanishing into a green number.
--
-- NOTHING IN PHASE A OR PHASE B IS READ FOR WRITING. No department, role, overlay, workflow,
-- step, state, rule, gate, handoff or founder boundary is modified by this file. No paid provider
-- is called. No customer, supplier, payment, mail or SMS effect is produced.
--
-- Rollback:  scripts/sql/rollback/kernel_s2_historical_repair.rollback.sql
-- Rehearsal: scripts/sql/kernel_s2_historical_repair.REHEARSAL.md
-- ============================================================================================


-- ================================================== 1. THE SHARED VOCABULARY, IN ONE PLACE ONLY
-- Five object kinds, three different words for "finished", and two vocabularies for subject_kind.
-- Copying that into the classifier, the repair and the invariant would be three chances to
-- disagree. phase_c_task_state and phase_c_command_state carry a `terminal` column and are read
-- rather than transcribed; workflow_run, step_run and handoff_run have no such table, so the
-- literal lists are the ones fn_kernel_trace_integrity() already uses, deliberately identical.
-- coalesce(...,false) on the table-driven kinds means an UNKNOWN state reads as non-terminal —
-- which would quietly excuse an open trace, so it is counted and reported by its own check
-- (object_states_not_in_the_state_model) rather than left to be discovered later.
create or replace view public.v_phase_c_object_terminal as
select 'founder_command'::text as kind, c.command_id::text as ref, c.state as state,
       coalesce(s.terminal, false) as is_terminal, (s.state is not null) as state_is_modelled,
       c.trace_id
  from public.founder_command c
  left join public.phase_c_command_state s on s.state = c.state
union all
select 'workflow_run', r.run_id::text, r.state,
       r.state in ('completed','cancelled','failed','superseded','expired','rejected'), true, r.trace_id
  from public.phase_c_workflow_run r
union all
select 'step_run', sr.step_run_id::text, sr.state,
       sr.state in ('completed','cancelled','failed','superseded','skipped'), true, sr.trace_id
  from public.phase_c_workflow_step_run sr
union all
select 'task', t.task_id::text, t.state, coalesce(ts.terminal, false), (ts.state is not null), t.trace_id
  from public.phase_c_task t
  left join public.phase_c_task_state ts on ts.state = t.state
union all
select 'handoff_run', h.handoff_run_id::text, h.status,
       h.status in ('accepted','rejected','cancelled','superseded','returned'), true, h.trace_id
  from public.phase_c_handoff_run h;

comment on view public.v_phase_c_object_terminal is
  'Phase C objects with one normalised is_terminal. Task and command terminality is READ from '
  'phase_c_task_state / phase_c_command_state; run, step and handoff use the same literal lists '
  'as fn_kernel_trace_integrity(). state_is_modelled is false when the state is absent from the '
  'state model, which would otherwise score as non-terminal by default.';

-- Which object a trace is actually about. phase_c_trace records subject_kind in two vocabularies
-- and has no handoff_run_id column, so a handoff trace resolves through subject_ref — the same
-- normalisation K6 made, kept in one place instead of two.
create or replace view public.v_phase_c_trace_subject as
select t.trace_id, t.trace_policy_id, t.subject_kind, t.subject_ref, t.status, t.sealed_at,
       t.superseded_by, t.state_after, t.created_at, t.evidence_refs,
       case t.subject_kind
         when 'command'         then 'founder_command' when 'founder_command' then 'founder_command'
         when 'run'             then 'workflow_run'    when 'workflow_run'    then 'workflow_run'
         when 'step'            then 'step_run'        when 'step_run'        then 'step_run'
         when 'task'            then 'task'
         when 'handoff'         then 'handoff_run'     when 'handoff_run'     then 'handoff_run'
         else 'unmapped' end as nkind,
       case t.subject_kind
         when 'command'         then t.command_id::text when 'founder_command' then t.command_id::text
         when 'run'             then t.run_id::text     when 'workflow_run'    then t.run_id::text
         when 'step'            then t.step_run_id::text when 'step_run'       then t.step_run_id::text
         when 'task'            then t.task_id::text
         when 'handoff'         then t.subject_ref      when 'handoff_run'     then t.subject_ref
         else null end as nref
  from public.phase_c_trace t;

comment on view public.v_phase_c_trace_subject is
  'phase_c_trace with its subject normalised to (nkind, nref) across both subject_kind '
  'vocabularies. nref NULL on nkind=''task'' is the orphan class.';


-- ================================================== 2. THE APPEND-ONLY CLASSIFICATION LEDGER
-- One row per affected record. CLASSIFICATION rows carry exactly one of the five classes and are
-- written before any repair statement. RETROFIT rows carry a mandatory label and record every
-- reconstructed statement this file made, so no retrofit can exist unlabelled.
create table if not exists public.phase_c_historical_repair (
  repair_id       bigserial primary key,
  entry_kind      text        not null,
  record_kind     text        not null,
  record_ref      text        not null,
  classification  text,
  frozen_state    text        not null,
  evidence        jsonb       not null,
  repair_action   text        not null,
  retrofit_label  text        not null default '',
  migration       text        not null,
  classified_at   timestamptz not null default now()
);

do $ck$
begin
  if not exists (select 1 from pg_constraint where conname = 'phase_c_historical_repair_uk') then
    alter table public.phase_c_historical_repair
      add constraint phase_c_historical_repair_uk unique (entry_kind, record_kind, record_ref);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'phase_c_historical_repair_entry_ck') then
    alter table public.phase_c_historical_repair
      add constraint phase_c_historical_repair_entry_ck
      check (entry_kind in ('CLASSIFICATION','RETROFIT'));
  end if;
  -- Exactly these five classes, and a CLASSIFICATION row must carry one of them. A RETROFIT row
  -- is not an affected record and carries none.
  if not exists (select 1 from pg_constraint where conname = 'phase_c_historical_repair_class_ck') then
    alter table public.phase_c_historical_repair
      add constraint phase_c_historical_repair_class_ck
      check (classification is null or classification in (
        'HISTORICAL_DUPLICATE_EFFECT',
        'HISTORICAL_ORPHAN_TRACE',
        'HISTORICAL_STATE_TRACE_MISMATCH',
        'HISTORICAL_CANCEL_PROPAGATION_FAILURE',
        'VALID_HISTORICAL_RECORD'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'phase_c_historical_repair_shape_ck') then
    alter table public.phase_c_historical_repair
      add constraint phase_c_historical_repair_shape_ck
      check ((entry_kind = 'CLASSIFICATION') = (classification is not null)
         and (entry_kind = 'RETROFIT')       = (retrofit_label <> ''));
  end if;
end $ck$;

comment on table public.phase_c_historical_repair is
  'Append-only classification of pre-kernel Phase C records and of every retrofit made to them. '
  'Written before the repair statements run, so the population each invariant measures is frozen '
  'and cannot be emptied by the write that repairs it. Never deleted: the defective records stay '
  'visible in history, and this is where the reason they are defective is kept.';

-- K1's protocol, applied to this ledger: refuse, always, with no reason-string escape hatch. A
-- classification that can be edited after the fact is not evidence.
create or replace function public.fn_phase_c_historical_repair_append_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception
    'phase_c_historical_repair is append-only: % on repair_id % is refused',
    tg_op, coalesce(old.repair_id::text, '?')
    using errcode = '23514',
          hint = 'This table is the record of which historical records were defective, why, and '
              || 'what was done about them. A correction is a NEW row that names the repair_id it '
              || 'corrects in its evidence, written as its own migration — never an edit to the '
              || 'row that stated the original finding.';
end $fn$;

revoke all on function public.fn_phase_c_historical_repair_append_only() from public;
grant execute on function public.fn_phase_c_historical_repair_append_only() to service_role;

drop trigger if exists a00_phase_c_historical_repair_append_only on public.phase_c_historical_repair;
create trigger a00_phase_c_historical_repair_append_only
  before update or delete on public.phase_c_historical_repair
  for each row execute function public.fn_phase_c_historical_repair_append_only();


-- ============================== 3. FREEZE THE POPULATION — CLASSIFY BEFORE ANYTHING IS WRITTEN
-- Every insert below is `on conflict do nothing`, so a re-apply never reclassifies a record that
-- has already been judged. The classes are mutually exclusive by record: a record is offered to
-- the classes in the order they appear here, and the unique key keeps the first one.
do $classify$
declare
  n_dup int; n_valid int; n_orph int; n_mismatch int; n_prop int;
begin

  -- ---- (a) HISTORICAL_DUPLICATE_EFFECT ------------------------------------------------------
  -- One founder command, two independent effect sets: the pre-kernel cmd:N:* fan-out (tasks
  -- carrying command_id with run_id NULL) and the tasks derived from a workflow run of the same
  -- command. fn_kernel_workflow_start now produces exactly one; command 269 is what one looks
  -- like. Both sets are counted whole and separately live, because a duplicate whose halves are
  -- both already closed is history and a duplicate with two live halves is work being done twice.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action, migration)
  select 'CLASSIFICATION', 'founder_command', e.command_id::text, 'HISTORICAL_DUPLICATE_EFFECT',
         e.state,
         jsonb_build_object(
           'defect', 'one founder command produced two independent effect sets',
           'legacy_fan_out_task_ids', e.legacy_ids,
           'legacy_fan_out_live', e.legacy_live,
           'workflow_run_ids', e.run_ids,
           'run_derived_task_ids', e.run_task_ids,
           'run_derived_live', e.run_live,
           'decided_by', 'phase_c_task rows exist BOTH with command_id=' || e.command_id ||
                         ' and run_id NULL, AND with run_id in the workflow runs of the same command',
           'duplicate_is_active', (e.legacy_live > 0 and e.run_live > 0),
           'measured_at', now()),
         case when e.legacy_live > 0 and e.run_live > 0
              then 'CANCEL both effect sets through fn_kernel_cancel(subject_kind=workflow_run, '
                || 'op=cancel). Neither half can be closed without the other: fn_kernel_cancel '
                || 'resolves the whole command from any of its runs. op=supersede was the first '
                || 'choice and the frozen Phase B state model refuses it — '
                || 'fn_phase_c_workflow_transition_allowed(queued, superseded) is false and there '
                || 'is no superseded terminal for a workflow run at all — so the command is '
                || 'CANCELLED, not completed. Re-issuing the instruction is a founder action and '
                || 'this repair does not fabricate a replacement command.'
              else 'NONE. Both effect sets are already terminal. The duplication is preserved as '
                || 'history; the records are not touched.' end,
         'kernel_s2_historical_repair.sql'
    from (
      select c.command_id, c.state,
             (select coalesce(jsonb_agg(t.task_id order by t.task_id), '[]'::jsonb)
                from public.phase_c_task t
               where t.command_id = c.command_id and t.run_id is null) as legacy_ids,
             (select count(*) from public.phase_c_task t
                join public.phase_c_task_state ts on ts.state = t.state
               where t.command_id = c.command_id and t.run_id is null and not ts.terminal) as legacy_live,
             (select coalesce(jsonb_agg(r.run_id order by r.run_id), '[]'::jsonb)
                from public.phase_c_workflow_run r where r.command_id = c.command_id) as run_ids,
             (select coalesce(jsonb_agg(t.task_id order by t.task_id), '[]'::jsonb)
                from public.phase_c_task t
               where t.run_id in (select r.run_id from public.phase_c_workflow_run r
                                   where r.command_id = c.command_id)) as run_task_ids,
             (select count(*) from public.phase_c_task t
                join public.phase_c_task_state ts on ts.state = t.state
               where t.run_id in (select r.run_id from public.phase_c_workflow_run r
                                   where r.command_id = c.command_id)
                 and not ts.terminal) as run_live
        from public.founder_command c) e
   where jsonb_array_length(e.legacy_ids) > 0
     and jsonb_array_length(e.run_task_ids) > 0
  on conflict on constraint phase_c_historical_repair_uk do nothing;
  get diagnostics n_dup = row_count;

  -- ---- (b) VALID_HISTORICAL_RECORD, for the commands in the same population that are clean ---
  -- Without this the reader sees six duplicates and no denominator. A command that produced Phase
  -- C work and produced exactly one effect set is a record that was examined and found correct;
  -- it is recorded as such so the history stays countable rather than merely absent.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action, migration)
  select 'CLASSIFICATION', 'founder_command', c.command_id::text, 'VALID_HISTORICAL_RECORD', c.state,
         jsonb_build_object(
           'examined_for', 'HISTORICAL_DUPLICATE_EFFECT',
           'legacy_fan_out_task_count',
             (select count(*) from public.phase_c_task t
               where t.command_id = c.command_id and t.run_id is null),
           'run_derived_task_count',
             (select count(*) from public.phase_c_task t
               where t.run_id in (select r.run_id from public.phase_c_workflow_run r
                                   where r.command_id = c.command_id)),
           'decided_by', 'this command produced Phase C work through exactly one of the two paths',
           'measured_at', now()),
         'NONE — examined and found correct.',
         'kernel_s2_historical_repair.sql'
    from public.founder_command c
   where (exists (select 1 from public.phase_c_task t where t.command_id = c.command_id)
       or exists (select 1 from public.phase_c_workflow_run r where r.command_id = c.command_id))
  on conflict on constraint phase_c_historical_repair_uk do nothing;
  get diagnostics n_valid = row_count;

  -- ---- (c) HISTORICAL_ORPHAN_TRACE ----------------------------------------------------------
  -- subject_kind names 'task' and task_id is NULL. The provability test is run per row and its
  -- full result is stored, so the class is decided by a measurement and not by a habit. A row is
  -- linkable only if a task carries this trace_id (the reverse link is already the proof), or if
  -- exactly one task carries subject_ref as its idempotency_key AND that task has no other trace
  -- AND it was not created before this trace was written. Anything else is a guess.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action, migration)
  select 'CLASSIFICATION', 'trace', o.trace_id::text, 'HISTORICAL_ORPHAN_TRACE', o.status,
         jsonb_build_object(
           'defect', 'trace declares subject_kind=task and carries no task_id',
           'subject_ref', o.subject_ref,
           'subject_ref_is', 'a phase_c_task idempotency key, not a task_id',
           'trace_created_at', o.created_at,
           'tasks_naming_this_trace', o.n_reverse,
           'tasks_with_this_idempotency_key', o.n_key,
           'key_task_id', o.key_task_id,
           'key_task_created_at', o.key_task_created,
           'key_task_trace_id', o.key_task_trace,
           'provable_by_reverse_link', (o.n_reverse = 1),
           'provable_by_idempotency_key', (o.n_key = 1 and o.key_task_trace is null
                                           and o.key_task_created >= o.created_at),
           'subject_proven', (o.n_reverse = 1
                              or (o.n_key = 1 and o.key_task_trace is null
                                  and o.key_task_created >= o.created_at)),
           'why', case when o.n_reverse = 1
                       then 'A task carries this trace_id. The subject is known from the task side.'
                       when o.n_key = 1 and o.key_task_trace is not null and o.key_task_created < o.created_at
                       then 'A task with this idempotency key exists, but it was created BEFORE '
                         || 'this trace was written and already carries a different trace ('
                         || o.key_task_trace || '). This row is therefore the trace of a SECOND '
                         || 'insert that phase_c_task_idem_uk discarded, not the trace of that '
                         || 'task. Linking them would assert something the timestamps refute.'
                       when o.n_key = 0
                       then 'No task anywhere carries this idempotency key. There is nothing to link to.'
                       else 'The idempotency key does not resolve to exactly one task with no trace '
                         || 'of its own. The subject cannot be proven.' end,
           'measured_at', now()),
         case when o.n_reverse = 1
                or (o.n_key = 1 and o.key_task_trace is null and o.key_task_created >= o.created_at)
              then 'LINK — recorded in this ledger, with the proof above. The trace row itself is '
                || 'not edited: it is sealed evidence and z10_phase_c_trace_append_only is correct '
                || 'to refuse an edit.'
              else 'MARK INVALID — this trace does not describe any object that exists. It is kept, '
                || 'sealed and annotated, as the only surviving evidence that a BEFORE INSERT trace '
                || 'guard wrote evidence for an insert that never landed. No subject is guessed.' end,
         'kernel_s2_historical_repair.sql'
    from (
      select t.trace_id, t.subject_ref, t.status, t.created_at,
             (select count(*) from public.phase_c_task k where k.trace_id = t.trace_id) as n_reverse,
             (select count(*) from public.phase_c_task k where k.idempotency_key = t.subject_ref) as n_key,
             (select min(k.task_id) from public.phase_c_task k where k.idempotency_key = t.subject_ref) as key_task_id,
             (select min(k.created_at) from public.phase_c_task k where k.idempotency_key = t.subject_ref) as key_task_created,
             (select min(k.trace_id) from public.phase_c_task k where k.idempotency_key = t.subject_ref) as key_task_trace
        from public.v_phase_c_trace_subject t
       where t.nkind = 'task' and t.nref is null) o
  on conflict on constraint phase_c_historical_repair_uk do nothing;
  get diagnostics n_orph = row_count;

  -- ---- (d) HISTORICAL_STATE_TRACE_MISMATCH --------------------------------------------------
  -- The subject has reached a terminal state and its trace is still open. Measured from the TRACE
  -- side over every trace, not from the object's own trace_id pointer: three of these (520, 526,
  -- 527) are bound to task 793 and are NOT the pointer that task carries, which is exactly why
  -- fn_kernel_trace_integrity()'s terminal_objects_with_open_trace_task reports them green.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action, migration)
  select 'CLASSIFICATION', 'trace', t.trace_id::text, 'HISTORICAL_STATE_TRACE_MISMATCH', t.status,
         jsonb_build_object(
           'defect', 'the trace is open and its subject has reached a terminal state',
           'trace_policy_id', t.trace_policy_id,
           'subject_kind', t.nkind, 'subject_ref', t.nref,
           'subject_state_now', o.state,
           'trace_state_after', t.state_after,
           'trace_created_at', t.created_at,
           'is_the_subjects_own_trace_pointer', (o.trace_id = t.trace_id),
           'decided_by', 'phase_c_trace.status=open and sealed_at is null while the subject row is '
                      || 'in a terminal state',
           'predates_the_kernel', (t.created_at < timestamptz '2026-08-16 21:00:00+00'),
           'measured_at', now()),
         'SEAL where it stands. status and sealed_at are set and a labelled retrofit evidence_ref '
         || 'is APPENDED. state_before and state_after are NOT touched: the transition this row '
         || 'recorded stays exactly as it was recorded, and the seal is disclosed as applied by '
         || 'this repair rather than observed when the subject closed.',
         'kernel_s2_historical_repair.sql'
    from public.v_phase_c_trace_subject t
    join public.v_phase_c_object_terminal o on o.kind = t.nkind and o.ref = t.nref
   where t.status = 'open' and t.sealed_at is null and t.superseded_by is null and o.is_terminal
  on conflict on constraint phase_c_historical_repair_uk do nothing;
  get diagnostics n_mismatch = row_count;

  -- ---- (e) HISTORICAL_CANCEL_PROPAGATION_FAILURE --------------------------------------------
  -- Work that is still live under a command or run that has been cancelled or superseded. K4
  -- closed this class and fn_kernel_orphaned_work() reports it empty; the classifier is still run
  -- because an empty class is not a class that cannot refill, and because the same query is the
  -- only honest way to say "zero" rather than assume it.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action, migration)
  select 'CLASSIFICATION', 'task', t.task_id::text, 'HISTORICAL_CANCEL_PROPAGATION_FAILURE', t.state,
         jsonb_build_object(
           'defect', 'the task is live and the command or run it derives from is terminal',
           'command_id', t.command_id, 'run_id', t.run_id,
           'dead_command_state', (select c.state from public.founder_command c where c.command_id = t.command_id),
           'dead_run_state', (select r.state from public.phase_c_workflow_run r where r.run_id = t.run_id),
           'entry_run_id', (select min(r.run_id) from public.phase_c_workflow_run r
                             where r.command_id = t.command_id or r.run_id = t.run_id),
           'measured_at', now()),
         case when exists (select 1 from public.phase_c_workflow_run r
                            where r.command_id = t.command_id or r.run_id = t.run_id)
              then 'CANCEL through fn_kernel_cancel(subject_kind=workflow_run), which reaches the '
                || 'command, its plan, its runs, its step runs, its tasks BY COMMAND AND BY RUN, '
                || 'its open handoffs and its undelivered outbox rows, and asserts that nothing '
                || 'queued survives.'
              else 'REFUSED. This command has no workflow run, so fn_kernel_cancel can only be '
                || 'entered through subject_kind=founder_command, which calls '
                || 'fn_phase_c_require_founder. This migration will not present itself as the '
                || 'founder to close a record. The row is classified and left; '
                || 'queued_work_derived_from_cancelled_commands stays red until the founder or an '
                || 'authenticated founder-facing surface cancels it.' end,
         'kernel_s2_historical_repair.sql'
    from public.phase_c_task t
    join public.phase_c_task_state ts on ts.state = t.state
   where not ts.terminal
     and ( exists (select 1 from public.founder_command c
                    join public.phase_c_command_state cs on cs.state = c.state
                   where c.command_id = t.command_id and cs.terminal)
        or exists (select 1 from public.phase_c_workflow_run r
                   where r.run_id = t.run_id
                     and r.state in ('completed','cancelled','failed','superseded','expired','rejected')))
  on conflict on constraint phase_c_historical_repair_uk do nothing;
  get diagnostics n_prop = row_count;

  raise notice 'S2 classification (frozen BEFORE any repair): duplicate_effect=%, valid=%, orphan=%, state_trace_mismatch=%, cancel_propagation=%',
    n_dup, n_valid, n_orph, n_mismatch, n_prop;
end $classify$;


-- ================================================================== 4. THE REPAIR ITSELF
-- Every statement below reads its population FROM THE LEDGER, which was written above and cannot
-- be changed by anything here. The condition ("is this still active?") is measured now; the
-- population is not. Both the classification rows and the repair land in one transaction, so a
-- committed classification always describes a completed repair — if any step raises, the whole
-- thing rolls back and nothing is half-repaired.
do $repair$
declare
  r        record;
  v_res    jsonb;
  n_super  int := 0;
  n_seal   int := 0;
  n_refuse int := 0;
begin

  -- ---- (a) still-ACTIVE duplicate effects, through fn_kernel_cancel --------------------------
  -- Entered on subject_kind='workflow_run', not 'founder_command'. Both reach the whole command —
  -- fn_kernel_cancel resolves command_id from the run — but the workflow_run door records the
  -- actor without authenticating it as the founder, and the founder door calls
  -- fn_phase_c_require_founder. Superseding two duplicated commands is an engineering repair; it
  -- is not the founder cancelling his own instruction, and it must not be recorded as if it were.
  for r in
    select h.record_ref::bigint as command_id, h.evidence
      from public.phase_c_historical_repair h
     where h.entry_kind = 'CLASSIFICATION'
       and h.classification = 'HISTORICAL_DUPLICATE_EFFECT'
       and h.record_kind = 'founder_command'
       -- measured NOW, not read from the frozen snapshot
       and exists (select 1 from public.phase_c_task t
                     join public.phase_c_task_state ts on ts.state = t.state
                    where t.command_id = h.record_ref::bigint and t.run_id is null and not ts.terminal)
       and exists (select 1 from public.phase_c_task t
                     join public.phase_c_task_state ts on ts.state = t.state
                    where t.run_id in (select rr.run_id from public.phase_c_workflow_run rr
                                        where rr.command_id = h.record_ref::bigint)
                      and not ts.terminal)
     order by h.record_ref::bigint
  loop
    v_res := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind', 'workflow_run',
      'subject_ref',  (select min(rr.run_id)::text from public.phase_c_workflow_run rr
                        where rr.command_id = r.command_id),
      -- op='supersede' was the first choice and the frozen Phase B state model refuses it:
      -- fn_phase_c_workflow_transition_allowed('queued','superseded') is false, and no workflow
      -- run transition anywhere in the model reaches 'superseded'. Proven by execution, 17 Aug.
      -- The guard is right and Phase B is frozen, so the repair uses the transition that exists.
      'op',           'cancel',
      'actor',        'migration:kernel_s2_historical_repair',
      'reason',       'HISTORICAL_DUPLICATE_EFFECT — founder command ' || r.command_id ||
                      ' produced two independent effect sets: the pre-kernel cmd:' || r.command_id ||
                      ':* task fan-out ' || (r.evidence->>'legacy_fan_out_task_ids') ||
                      ' and the ingress-derived workflow run(s) ' || (r.evidence->>'workflow_run_ids') ||
                      ' whose task(s) ' || (r.evidence->>'run_derived_task_ids') ||
                      ' were also live. The company was executing one instruction twice. '
                      'fn_kernel_workflow_start is now the only creator of business work and '
                      'creates exactly one effect per command. Neither half of this duplication '
                      'can be closed without the other, because fn_kernel_cancel resolves the '
                      'whole command from any of its runs — so the command is CANCELLED, not '
                      'completed. Re-issuing the instruction is a founder action; this repair '
                      'does not fabricate a replacement command. '
                      '(scripts/sql/kernel_s2_historical_repair.sql, Section 2)'));

    if coalesce((v_res->>'ok')::boolean, false) is not true then
      raise exception 'S2: fn_kernel_cancel refused the duplicate-effect supersession of command %: %',
        r.command_id, v_res
        using errcode = '23514',
              hint = 'Nothing was repaired and the transaction is rolled back. Read the returned '
                  || 'error: transition_not_permitted means the command state model does not allow '
                  || 'this move, and that is a Phase B question, not something to force.';
    end if;

    insert into public.phase_c_historical_repair
      (entry_kind, record_kind, record_ref, frozen_state, evidence, repair_action,
       retrofit_label, migration)
    values ('RETROFIT', 'founder_command', r.command_id::text, 'cancelled',
      jsonb_build_object(
        'retrofit', 'duplicate-effect closure',
        'not_contemporaneous', 'This cancellation was decided by a repair migration on the date '
                            || 'below, NOT by the founder and NOT at the time the duplication '
                            || 'happened. The actor recorded on every trace fn_kernel_cancel wrote '
                            || 'is migration:kernel_s2_historical_repair.',
        'service', 'fn_kernel_cancel(subject_kind=workflow_run, op=cancel)',
        'op_supersede_refused_by', 'the frozen Phase B workflow state model has no superseded '
                            || 'terminal for a workflow run',
        'result', v_res,
        'applied_at', now()),
      'both effect sets cancelled; the founder command is cancelled, not completed',
      'S2-RETROFIT-DUPLICATE-EFFECT-CANCELLED',
      'kernel_s2_historical_repair.sql')
    on conflict on constraint phase_c_historical_repair_uk do nothing;

    n_super := n_super + 1;
  end loop;

  -- ---- (b) cancel-propagation failures, through the same service ----------------------------
  -- Zero rows today. The loop is written against the ledger rather than against a hard-coded id
  -- so that it acts if the class refills, and it REFUSES rather than impersonating the founder
  -- when there is no workflow run to enter through.
  for r in
    select h.record_ref::bigint as task_id, h.evidence
      from public.phase_c_historical_repair h
     where h.entry_kind = 'CLASSIFICATION'
       and h.classification = 'HISTORICAL_CANCEL_PROPAGATION_FAILURE'
       and h.record_kind = 'task'
       and exists (select 1 from public.phase_c_task t
                     join public.phase_c_task_state ts on ts.state = t.state
                    where t.task_id = h.record_ref::bigint and not ts.terminal)
     order by h.record_ref::bigint
  loop
    if (r.evidence->>'entry_run_id') is null then
      n_refuse := n_refuse + 1;
      raise notice 'S2: task % is live under a terminal command with no workflow run. REFUSED: fn_kernel_cancel would have to be entered as the founder. Left classified.',
                r.task_id;
      continue;
    end if;

    v_res := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind', 'workflow_run',
      'subject_ref',  (r.evidence->>'entry_run_id'),
      'op',           'cancel',
      'actor',        'migration:kernel_s2_historical_repair',
      'reason',       'HISTORICAL_CANCEL_PROPAGATION_FAILURE — task ' || r.task_id ||
                      ' was still live beneath a command or run that had already been cancelled. '
                      'The pre-K4 cancellation reached the command and the tasks carrying its '
                      'command_id and nothing else. (kernel_s2_historical_repair.sql, Section 2)'));

    if coalesce((v_res->>'ok')::boolean, false) is not true then
      raise exception 'S2: fn_kernel_cancel refused the cancel-propagation repair for task %: %',
        r.task_id, v_res using errcode = '23514';
    end if;

    insert into public.phase_c_historical_repair
      (entry_kind, record_kind, record_ref, frozen_state, evidence, repair_action,
       retrofit_label, migration)
    values ('RETROFIT', 'task', r.task_id::text, 'cancelled',
      jsonb_build_object(
        'retrofit', 'cancel propagation completed after the fact',
        'not_contemporaneous', 'This cancellation was applied by a repair migration, not when the '
                            || 'command was cancelled. The gap between the two is visible in the '
                            || 'row''s own closed_at against its command''s closed_at.',
        'service', 'fn_kernel_cancel(subject_kind=workflow_run, op=cancel)',
        'result', v_res, 'applied_at', now()),
      'derived work closed under a command that was already cancelled',
      'S2-RETROFIT-CANCEL-PROPAGATION', 'kernel_s2_historical_repair.sql')
    on conflict on constraint phase_c_historical_repair_uk do nothing;
  end loop;

  -- ---- (c) open traces on terminal subjects: sealed where they stand ------------------------
  -- These rows are NOT sealed, so z10_phase_c_trace_append_only permits the write — it guards
  -- SEALED evidence, and none of this touches any. Nothing recorded is overwritten: state_before,
  -- state_after, output_hash and every existing evidence_ref are left exactly as they are, and
  -- the retrofit statement is APPENDED to evidence_refs. The seal timestamp is now(), which is
  -- when the seal was actually applied — no plausible earlier time is invented.
  for r in
    select h.record_ref::bigint as trace_id, h.evidence
      from public.phase_c_historical_repair h
     where h.entry_kind = 'CLASSIFICATION'
       and h.classification = 'HISTORICAL_STATE_TRACE_MISMATCH'
       and h.record_kind = 'trace'
       and exists (select 1 from public.phase_c_trace x
                    where x.trace_id = h.record_ref::bigint and x.sealed_at is null)
     order by h.record_ref::bigint
  loop
    update public.phase_c_trace t
       set status = 'sealed',
           sealed_at = now(),
           evidence_refs = coalesce(t.evidence_refs, '[]'::jsonb) || jsonb_build_array(
             jsonb_build_object(
               's2_retrofit', 'sealed_open_trace_on_terminal_subject',
               'reason', 'This trace was left open while its subject reached a terminal state. An '
                      || 'open trace on a finished object is evidence that is still rewritable in '
                      || 'place, and it reads as work in flight.',
               'subject_kind', r.evidence->>'subject_kind',
               'subject_ref', r.evidence->>'subject_ref',
               'subject_state_when_sealed', r.evidence->>'subject_state_now',
               'state_after_left_unchanged', t.state_after,
               'not_contemporaneous', 'The seal was applied by a repair migration, NOT when the '
                      || 'subject closed. This row records the transition it always recorded; only '
                      || 'the seal and this note were added.',
               'sealed_at_source', 'now() at the time the repair ran — no earlier time was invented',
               'migration', 'kernel_s2_historical_repair.sql',
               'retrofitted_at', now()))
     where t.trace_id = r.trace_id and t.sealed_at is null;

    insert into public.phase_c_historical_repair
      (entry_kind, record_kind, record_ref, frozen_state, evidence, repair_action,
       retrofit_label, migration)
    values ('RETROFIT', 'trace', r.trace_id::text, 'sealed',
      jsonb_build_object(
        'retrofit', 'seal applied to an open trace whose subject is terminal',
        'wrote_to_row', true,
        'evidence_key_written', 's2_retrofit',
        'not_contemporaneous', 'The seal time is when the repair ran, not when the subject closed.',
        'applied_at', now()),
      'open trace on a terminal subject sealed, with the recorded transition left untouched',
      'S2-RETROFIT-SEAL-TERMINAL-SUBJECT', 'kernel_s2_historical_repair.sql')
    on conflict on constraint phase_c_historical_repair_uk do nothing;

    n_seal := n_seal + 1;
  end loop;

  -- ---- (d) orphan traces: the finding is written beside the row, never into it ---------------
  -- The trace row is not touched. All seven are sealed, K6 annotated them, and re-opening
  -- z10_phase_c_trace_append_only to write a sentence that fits perfectly well in an append-only
  -- ledger would be trading a guard for nothing. Each RETROFIT row states either the proof of the
  -- subject or the reason the subject cannot be proven, in the words the classifier measured.
  insert into public.phase_c_historical_repair
    (entry_kind, record_kind, record_ref, frozen_state, evidence, repair_action,
     retrofit_label, migration)
  select 'RETROFIT', 'trace', h.record_ref, 'sealed',
         jsonb_build_object(
           'retrofit', case when (h.evidence->>'subject_proven')::boolean
                            then 'orphan trace linked to its proven subject'
                            else 'orphan trace marked invalid — no provable subject' end,
           'wrote_to_row', false,
           'trace_row_untouched', 'The trace is sealed evidence. z10_phase_c_trace_append_only '
                               || 'refuses an edit and is correct to. The finding is recorded here '
                               || 'instead, which is the same statement without dropping a guard.',
           'subject_proven', (h.evidence->>'subject_proven')::boolean,
           'linked_task_id', case when (h.evidence->>'subject_proven')::boolean
                                  then h.evidence->'key_task_id' else null end,
           'proof', h.evidence->>'why',
           'not_contemporaneous', 'This is a reconstruction made by a repair migration from the '
                               || 'surviving rows. Nothing here observes what happened when the '
                               || 'trace was written.',
           'k6_annotation_present', exists (
             select 1 from public.phase_c_trace x
              where x.trace_id = h.record_ref::bigint
                and x.evidence_refs @> '[{"k6_backfill":"orphan_trace_no_subject"}]'::jsonb),
           'applied_at', now()),
         case when (h.evidence->>'subject_proven')::boolean
              then 'LINKED in this ledger with the proof recorded above.'
              else 'MARKED INVALID. Preserved, not deleted: it is the only surviving evidence that '
                || 'a BEFORE INSERT trace guard wrote a trace for an insert the idempotency index '
                || 'then discarded.' end,
         case when (h.evidence->>'subject_proven')::boolean
              then 'S2-RETROFIT-ORPHAN-LINKED'
              else 'S2-RETROFIT-ORPHAN-INVALID' end,
         'kernel_s2_historical_repair.sql'
    from public.phase_c_historical_repair h
   where h.entry_kind = 'CLASSIFICATION'
     and h.classification = 'HISTORICAL_ORPHAN_TRACE'
  on conflict on constraint phase_c_historical_repair_uk do nothing;

  raise notice 'S2 repair: duplicate effects closed=%, traces sealed=%, cancel-propagation refusals=%',
    n_super, n_seal, n_refuse;
end $repair$;


-- ============================================================ 5. THE INVARIANT THAT WATCHES IT
-- Five required checks, each a numerator AND a denominator over the FULL estate and measuring
-- CURRENT state — not the frozen scope, because a check that can only see the rows this migration
-- already judged is a check that goes green and stays green while the defect keeps being
-- produced. Traces 1072-1075 were produced today. Then the per-class counts of preserved history,
-- emitted for all five classes even at zero, so a class never disappears from the report by
-- having nothing in it.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_historical_repair_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_historical_repair_state() from public;
grant execute on function public.fn_kernel_historical_repair_state() to service_role;

comment on function public.fn_kernel_historical_repair_state() is
  'Section 2 invariant. Five required checks over the FULL estate measuring CURRENT state, one '
  'check on the state-model default that could excuse an open trace, and the per-class counts of '
  'the historical records this repair preserved. terminal_objects_with_open_trace can go red '
  'again without any of these rows changing: a cancellation on 2026-08-16 22:39 left four '
  'creation traces open, and that producer is a K4 defect, not a Section 2 one.';

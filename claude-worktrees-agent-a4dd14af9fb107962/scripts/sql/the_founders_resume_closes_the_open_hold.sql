-- THE FOUNDER'S RESUME NEVER CLOSED THE HOLD IT LIFTED (3 Sep 2026).
--
-- Founder, 2 Sep 2026: "lift all previous limits or frozen gates; the only thing that remains
-- blocked is OpenRouter." lift_automation_hold_gate032.sql recorded that as a NEW
-- company_stand_down row with resumed_at = stood_down_at (twice: ids 5 and 6). The row that
-- actually holds the company — id 4, the 16 Aug PARTIAL RESUME, resumed_at NULL — was left open,
-- and every routine that asks "is a stand-down open?" asks it as `where resumed_at is null`:
-- fn_outcome_evaluate, fn_reputation_recompute, fn_reputation_hold_state, fn_promotion_review,
-- fn_objective_review, fn_org_task_sla_watch, fn_handoff_watchdog and
-- fn_action_queue_consequential_sweep all still returned PAUSED_BY_FOUNDER_STANDDOWN on 3 Sep,
-- a day after he lifted it. Measured: fn_reputation_hold_state() reads "PAUSED_BY_FOUNDER_STANDDOWN
-- since 2026-08-16 08:35:59"; outcome_record holds 25 decisions past their measurement date and
-- never graded (s28-decisions-with-outcomes).
--
-- Closing the open rows is executing his order, not a new decision. resumed_at is now(), not his
-- 2 Sep timestamp: the record says when it was closed, and the reason says why and on whose word.
-- Rows 1-3 (the two 16 Aug stand-downs and the first copy of the partial resume) were open too:
-- the first apply of this file closed row 4 and then its own control block named 1,2,3; a
-- parallel session closed those sixteen seconds later. The update below is over every open row,
-- so a re-apply is a no-op and the control block is the fact either way.
--
-- With the hold closed, the two crons the 3 Sep re-enable left off BECAUSE of it go back on the
-- clock, wrapped through the kernel like the rest:
--   143 outcome_evaluate_daily   30 3 * * *   fn_outcome_evaluate  — grades due decisions, writes
--                                              the lesson to institutional_memory, opens a ROLL BACK
--                                              task on a 'worse' verdict. Pure SQL, no model.
--   154 knowledge_decay_daily    10 3 * * *   fn_knowledge_decay   — confidence decays past
--                                              review_due, quarantine below the floor, a refresh
--                                              task per quarantined employee. Pure SQL, no model.
-- reputation_weekly stays OFF: it writes employee_authority, and an authority change with no human
-- is what the promotion constraint guards; that is a separate decision and not this file's.
--
-- fn_handoff_watchdog (handoff_watchdog_6h, active) also resumes with the hold and pages the
-- founder for a stalled handoff — 2 are overdue today. Said here so the pages are not a surprise.

begin;

update public.company_stand_down
   set resumed_at = now(),
       reason = reason || ' || CLOSED 3 Sep 2026 on the founder''s 2 Sep order ("lift all previous limits or frozen gates; the only thing that remains blocked is OpenRouter"): the full resume (rows 5-6) was recorded beside this row instead of closing it, so every `resumed_at is null` reader still saw a hold.'
 where resumed_at is null;

do $$
begin
  perform public.fn_kernel_wrap_and_enable_cron(143, 'corporate_performance_director', 'exec', 'routine_operational_decision');   -- outcome_evaluate_daily (30 3 * * *)
  update public.phase_c_component set authority_class = 'routine_operational_decision' where component_id = 'cron:outcome_evaluate_daily' and authority_class is distinct from 'routine_operational_decision';
  perform public.fn_kernel_wrap_and_enable_cron(154, 'knowledge_director', 'data_intel', 'knowledge_publish');   -- knowledge_decay_daily (10 3 * * *)
  update public.phase_c_component set authority_class = 'knowledge_publish' where component_id = 'cron:knowledge_decay_daily' and authority_class is distinct from 'knowledge_publish';

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (143, 'outcome_evaluate_daily',
     'Pure SQL grading: UPDATEs outcome_record (observed_value, verdict, lesson, closed_at), INSERTs institutional_memory, company_event (outcome.graded / rollback.required through fn_emit), org_tasks (ROLL BACK on a worse verdict), agent_runs. No HTTP, no model.',
     'Schedule 30 3 * * *; own transaction on a scheduled tick; grades only outcome_record rows whose due_at has passed, keyed by their own id; a scenario''s fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them; close() asserts scenario rows by id/marker.'),
    (154, 'knowledge_decay_daily',
     'Pure SQL measurement: UPDATEs agent_knowledge.confidence / validation_status for rows past review_due, INSERTs org_tasks (knowledge_fill) per quarantined employee, agent_runs. No HTTP, no model.',
     'Schedule 10 3 * * *; own transaction on a scheduled tick; touches only agent_knowledge rows past their own review_due; a scenario''s fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them; close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;

commit;

do $ctl$
begin
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    raise exception 'a company_stand_down row is still open: %', (select string_agg(id::text, ',') from public.company_stand_down where resumed_at is null);
  end if;
  if (select count(*) from cron.job where jobid in (143, 154) and active and command ilike '%fn_kernel_cron_exec%') <> 2 then
    raise exception 'outcome_evaluate_daily and knowledge_decay_daily are not both active and wrapped';
  end if;
  if exists (select 1 from cron.job j where j.active and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname)) then
    raise exception 'an active job is undocumented in cron_registry: %', (select string_agg(j.jobname, ', ') from cron.job j where j.active and not exists (select 1 from public.cron_registry r where r.jobname = j.jobname));
  end if;
end $ctl$;

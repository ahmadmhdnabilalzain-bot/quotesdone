-- PROBE (pure, no DDL, aborted transaction) for the_it_engineer_runs_the_safe_fix_playbooks_itself.sql. Seat: it_engineer.
-- Run AFTER the definition (and after the_originators_close_..._condition_cleared.sql and
-- a_parked_model_question_has_an_owner_and_a_deadline.sql, whose routines two families run) in the same transaction.
-- It ends in raise exception, so every fix it makes (rotations included) rolls back; the outcome per family comes out.
-- PROBE OK needs: every family ran without a 'failed' run, every run has its audit row, a new family cannot be made
-- active without an approval, and the CEO's approval makes it active.
do $p$
declare v jsonb; v_runs int; v_failed int; v_refused text; v_appr jsonb; v_ok boolean; v_open_before jsonb; v_open_after jsonb;
begin
  select jsonb_object_agg(family, n) into v_open_before from (
    select f.family, count(x.*) n from public.it_safe_fix_family f
      left join public.it_engineer_finding x on f.issue_like is not null and x.closed_at is null and x.issue_key like f.issue_like
     group by 1) z;
  v := public.fn_it_safe_fix_tick();
  select count(*), count(*) filter (where outcome = 'failed') into v_runs, v_failed from public.it_safe_fix_run where ran_at = now();
  select jsonb_object_agg(family, n) into v_open_after from (
    select f.family, count(x.*) n from public.it_safe_fix_family f
      left join public.it_engineer_finding x on f.issue_like is not null and x.closed_at is null and x.issue_key like f.issue_like
     group by 1) z;
  begin
    insert into public.it_safe_fix_family (family, routine, guardrail, active, owner_file)
    values ('probe_family', 'fn_it_safe_fix_tick', 'a probe family that must not become active without an approval', true,
            'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql');
  exception when check_violation then v_refused := 'refused'; end;
  insert into public.it_safe_fix_family (family, routine, guardrail, active, owner_file)
  values ('probe_family', 'fn_it_safe_fix_tick', 'a probe family that must not become active without an approval', false,
          'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql');
  v_appr := public.fn_ceo_approves_safe_fix_family('probe_family', 'Approved for the probe: the routine exists, the guardrail is stated and nothing leaves the transaction.');
  v_ok := v_failed = 0 and v_runs > 0 and v_refused = 'refused' and (v_appr->>'ok')::boolean
          and exists (select 1 from public.it_safe_fix_family where family = 'probe_family' and active);
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'tick', v, 'runs', v_runs, 'failed', v_failed, 'open_findings_before', v_open_before, 'open_findings_after', v_open_after,
    'unapproved_family_refused', v_refused, 'ceo_approval', v_appr,
    'failed_detail', (select jsonb_agg(jsonb_build_object('family', family, 'issue', issue_key, 'error', error, 'why', result->>'why')) from public.it_safe_fix_run where ran_at = now() and outcome = 'failed'),
    'refused_detail', (select jsonb_agg(jsonb_build_object('family', family, 'issue', left(issue_key, 70), 'why', left(coalesce(result->>'why', result->'refused'->0->>'why'), 140))) from public.it_safe_fix_run where ran_at = now() and outcome = 'refused_by_guardrail'));
end $p$;

CREATE OR REPLACE FUNCTION public.fn_onboarding_ingest_runs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_updated int := 0;
begin
  for r in select agent, score_pct, run_at from canon_eval_runs where run_at > now() - interval '8 days' loop
    insert into org_onboarding(agent_key, department)
      values (r.agent, (select department from org_agents where agent_key=r.agent))
      on conflict (agent_key) do nothing;
    update org_onboarding set l1_score=r.score_pct, l1_at=r.run_at, updated_at=now()
      where agent_key=r.agent and (l1_at is null or l1_at < r.run_at);
    v_updated := v_updated + 1;
  end loop;
  update org_onboarding o set status='probation', updated_at=now()
    where o.status in ('onboarding','recert_due')
      and o.l1_score >= o.pass_threshold and o.l2_score >= o.pass_threshold;
  update org_onboarding o set status='certified', certified_at=now(),
      recert_due=(now()+interval '90 days')::date, updated_at=now()
    where o.status='probation' and o.probation_reviews_done >= o.probation_reviews_required;
  update org_onboarding o set status='recert_due', updated_at=now()
    where o.status='certified' and o.recert_due is not null and o.recert_due < current_date;
  return jsonb_build_object('runs_ingested', v_updated);
end $function$

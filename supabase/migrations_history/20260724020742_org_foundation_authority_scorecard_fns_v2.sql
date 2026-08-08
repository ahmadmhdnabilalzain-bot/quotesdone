-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724020742   name: org_foundation_authority_scorecard_fns_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_dept_authority(p_dept text, p_action_class text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_catalog'
as $function$
declare v_tier text; v_thr numeric; v_cap text; v_tier_rk int; v_cap_rk int;
begin
  select max_tier, threshold_aed into v_tier, v_thr
    from public.org_authority where dept_key=p_dept and action_class=p_action_class;
  if v_tier is null then v_tier := 'gated'; end if;   -- unknown action -> default to gated (ask a human)

  -- HARD CAPS (the escalation constitution): these classes can never exceed the cap.
  if p_action_class ~* 'money|payout|payment|gl_|data_delete|delete|purge|secret|auth|password|code_deploy|supplier_ban|ban' then
    v_cap := 'gated';
  elsif p_action_class ~* 'legal_review|recommend' then
    v_cap := 'advisory';
  end if;

  v_tier_rk := case v_tier when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 when 'autonomous' then 3 else 1 end;
  if v_cap is not null then
    v_cap_rk := case v_cap when 'advisory' then 0 when 'gated' then 1 when 'supervised' then 2 else 3 end;
    if v_tier_rk > v_cap_rk then v_tier := v_cap; end if;
  end if;
  return jsonb_build_object('dept',p_dept,'action_class',p_action_class,'tier',v_tier,'threshold_aed',v_thr,'capped', v_cap is not null);
end $function$;
revoke execute on function public.fn_dept_authority(text,text) from public, anon, authenticated;
grant execute on function public.fn_dept_authority(text,text) to service_role;

create or replace function public.fn_org_scorecard()
returns jsonb
language sql
stable
security definer
set search_path to 'public','pg_catalog'
as $function$
  select coalesce(jsonb_agg(row_to_json(x) order by x.sort),'[]'::jsonb) from (
    select d.dept_key, d.name, d.north_star, d.lead_agent, d.sort,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and t.status in ('proposed','assigned','in_progress','blocked')) as open_tasks,
      (select count(*) from public.org_tasks t where t.dept_key=d.dept_key and (t.needs_founder or t.status='escalated') and t.status not in ('done','failed')) as escalations,
      (select count(*) from public.agent_actions a where a.status in ('pending','needs_review','open') and (
          (d.dept_key='finance' and a.kind ~* 'finance|refund|dues') or
          (d.dept_key='legal' and a.kind ~* 'legal|compliance') or
          (d.dept_key='supplier_success' and a.kind ~* 'supplier|approve|licence|kyc') or
          (d.dept_key='customer_success' and a.kind ~* 'customer|refund|escalation') or
          (d.dept_key='it' and a.kind ~* 'incident|security') or
          (d.dept_key='marketing' and a.kind ~* 'market|content') or
          (d.dept_key='knowledge' and a.kind ~* 'knowledge|coverage')
        )) as dept_queue
    from public.org_departments d where d.active
  ) x;
$function$;
revoke execute on function public.fn_org_scorecard() from public, anon, authenticated;
grant execute on function public.fn_org_scorecard() to service_role;

-- REORGANISING THE AGENT COMPANY — three findings the behavioural tests produced, fixed.
--
--  1. Two canonical role aliases resolved at the ROLE layer and not at the AGENT layer, so
--     fn_org_role_resolve('site_reliability_engineer') answered and fn_org_agent_resolve() returned
--     null. A null addressee is rewritten to 'brief' and marked escalated, which looks like a
--     routing decision and is a missing row.
--  2. 44 open tasks sat with independent reviewers and 5 with employees merged away this morning.
--     A reviewer carrying the department's routine queue is not independent of it, and a task
--     owned by an inactive employee has no owner at all.
--  3. fn_category_specialist_scorecard averaged inquiries.completeness, which is jsonb. It has no
--     non-null value anywhere in the corpus: the column exists and nothing writes it. Reporting a
--     number for it would have been the exact defect the function was written to avoid.

begin;

-- 1. Every alias the role layer knows must resolve at the agent layer too.
insert into public.org_agent_alias (alias, agent_key, reason)
select a.alias, r.runtime_agent_key,
       'canonical role alias ('||a.kind||') for '||r.display_name||'; '||coalesce(a.reason,'')
  from public.org_role_alias a
  join public.org_role r on r.role_id = a.role_id and r.status = 'active'
 where r.runtime_agent_key is not null
   and not exists (select 1 from public.org_agent_alias x where x.alias = a.alias)
   and not exists (select 1 from public.org_agents g where g.agent_key = a.alias)
on conflict (alias) do nothing;

-- 2. Take routine work off the independent reviewers and off the merged employees, and let the
--    assignment function place it under the ordinary capacity rules. Setting it to null rather
--    than force-placing it keeps the work VISIBLE as unowned if the department has no capacity —
--    which is a hiring signal, not something to hide behind a forced assignment.
update public.org_tasks t set assigned_agent = null, updated_at = now()
 where t.status in ('assigned','in_progress')
   and t.assigned_agent is not null
   and (
     not exists (select 1 from public.org_agents a where a.agent_key = t.assigned_agent and a.active)
     or exists (select 1 from public.org_role r
                 where r.runtime_agent_key = t.assigned_agent and r.status = 'active'
                   and r.runtime_mode = 'independent_reviewer'
                   and coalesce(t.action_class,'') not in ('review','audit','verify','qa_gate',
                         'security_review','compliance_check','legal_review','supplier_verify',
                         'capability_review','self_review')));

-- 3. Report what is measurable, name what is not.
create or replace function public.fn_category_specialist_scorecard(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_since timestamptz := now() - make_interval(days => greatest(coalesce(p_days,30),1));
  v_routed int; v_routed_ok int; v_inq int; v_quotable int; v_completeness_rows int;
  v_disp int; v_responded int; v_quotes int; v_valid int;
  v_overlays int; v_with_knowledge int;
begin
  select count(*) into v_overlays from org_role where status='active' and runtime_mode='knowledge_overlay';
  select count(distinct k.category_key) into v_with_knowledge
    from ops_knowledge k where k.category_key is not null and k.runtime_eligible;

  select count(*), count(*) filter (where coalesce(category,'') <> ''),
         count(*) filter (where coalesce(rfq_ready,false)),
         count(*) filter (where completeness is not null)
    into v_routed, v_routed_ok, v_quotable, v_completeness_rows
    from inquiries where created_at >= v_since;
  v_inq := v_routed;

  -- Dispatch is inquiry_matches.sent_at: a match that was never sent is a coverage fact, not a
  -- specialist outcome, so it is excluded from the denominator rather than counted as unanswered.
  select count(*) into v_disp from inquiry_matches where sent_at >= v_since;
  select count(distinct m.id) into v_responded
    from inquiry_matches m
    join quotes q on q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id
   where m.sent_at >= v_since;

  select count(*) into v_quotes from quotes where created_at >= v_since;
  select count(*) into v_valid from quotes
   where created_at >= v_since and coalesce(status,'') not in ('draft','invalid','withdrawn');

  return jsonb_build_object(
    'window_days', p_days,
    'overlays_active', v_overlays,
    'categories_with_runtime_knowledge', v_with_knowledge,
    'routing_accuracy', case when v_routed = 0 then null
                             else round(100.0 * v_routed_ok / v_routed, 1) end,
    'routing_accuracy_basis', case when v_routed = 0
      then 'no inquiry created in the window: not measurable, and deliberately not reported as 100'
      else v_routed_ok||' of '||v_routed||' inquiries carry a resolved category' end,
    'inquiry_quoteability', case when v_inq = 0 then null
                                 else round(100.0 * v_quotable / v_inq, 1) end,
    'inquiry_quoteability_basis', case when v_inq = 0
      then 'no inquiry in the window' else v_quotable||' of '||v_inq||' marked rfq_ready' end,
    'mandatory_field_completeness', null,
    'mandatory_field_completeness_basis',
      'not measurable: inquiries.completeness is jsonb and holds '||v_completeness_rows
      ||' non-null value(s) in this window. The column exists and no path writes it, so any number '
      ||'reported here would describe the schema rather than the inquiries',
    'supplier_response_rate', case when v_disp = 0 then null
                                   else round(100.0 * v_responded / v_disp, 1) end,
    'supplier_response_rate_basis', case when v_disp = 0
      then 'nothing dispatched in the window; with one confirmed supplier company-wide this is '
           ||'expected and is a coverage fact, not a specialist failure'
      else v_responded||' of '||v_disp||' dispatches answered' end,
    'valid_quotations', case when v_quotes = 0 then null
                             else round(100.0 * v_valid / v_quotes, 1) end,
    'valid_quotations_basis', case when v_quotes = 0
      then 'no quotation in the window' else v_valid||' of '||v_quotes end,
    'measured_at', now());
end
$function$;

commit;

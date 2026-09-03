-- A SPENT DEFERRAL IS RETIRED, NOT KEPT (3 Sep 2026).
--
-- The founder-approved Phase A baseline carries a deferred list: role violations he agreed to live
-- with for now. fn_org_role_deferral_state() reports a deferral that matches NO live violation as
-- STALE, because a deferral that excuses a gap that has since been filled is a sentence about the
-- past sitting in a list that is supposed to describe the present.
--
-- Measured 3 Sep 2026: product_ux_designer carried four deferrals (no_authority, no_knowledge,
-- no_kpi, no_tools). fn_org_role_violations_all() now reports only three for that role — the KPI
-- loop has since assigned it a KPI — so no_kpi:product_ux_designer matches nothing. The other three
-- still match live violations and stay exactly as approved. Nothing is hidden by this: the board
-- still reports every remaining deferral, never marks one complete, and reddens on the next stale one.
update public.org_phase_baseline
   set deferred = (select coalesce(jsonb_agg(t), '[]'::jsonb)
                   from jsonb_array_elements_text(deferred) t
                   where t <> 'no_kpi:product_ux_designer')
 where phase = 'A'
   and deferred ? 'no_kpi:product_ux_designer';

do $ctl$
begin
  if exists (select 1 from public.fn_org_role_deferred() d
             where not exists (select 1 from public.fn_org_role_violations_all() v where v.rule = d.rule and v.role_id = d.role_id)) then
    raise exception 'a stale deferral remains after this retirement: %',
      (select string_agg(d.token, ', ') from public.fn_org_role_deferred() d
        where not exists (select 1 from public.fn_org_role_violations_all() v where v.rule = d.rule and v.role_id = d.role_id));
  end if;
  if (select count(*) from public.fn_org_role_deferred()) <> 3 then
    raise exception 'expected exactly the 3 still-matching deferrals to remain, found %', (select count(*) from public.fn_org_role_deferred());
  end if;
end $ctl$;

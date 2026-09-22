-- PROBE: THE FOUNDER ASKS THE NUMBERS ON WHATSAPP AND GETS THEM.
--
-- Assigned: customer_support. 22 Sep 2026. Pure probe: no DDL, nothing survives it. Run AFTER
-- the_founder_asks_the_numbers_on_whatsapp_and_gets_them.sql, as ONE query through the Management API;
-- never applied. Every write happens inside a block that always raises, so all of it is rolled back,
-- including the founder alert fn_wa_human_request queues (a notifications row). Subjects are the reserved
-- ZZ DEMO fixture numbers +971500000051/52/53, which no account owns, and a ZZ DEMO supplier on
-- @example.invalid.
--
-- VERDICT: PROBE OK only if
--   1. a number that is not the founder's gets {ok:false, reason:not_the_founder} and no figure;
--   2. for the founder's number, each seeded fact moves exactly its own reading by one: a problem report
--      -> support.open_cases, a request for a person -> support.waiting_for_person, an IT finding ->
--      it.open_findings;
--   3. a ZZ DEMO supplier registering moves NO supplier reading (the demo exclusion the brief uses);
--   4. every section the WhatsApp answer reads is present, with the reading time.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  v_founder text := split_part(coalesce((select value from public.app_secrets where key = 'admin_mfa_phone'), ''), ',', 1);
  stranger jsonb; b jsonb; a jsonb; v_err text;
begin
  begin
    stranger := public.fn_founder_whatsapp_figures('whatsapp:+971500000053');
    b := public.fn_founder_whatsapp_figures('whatsapp:' || v_founder);
    perform public.fn_wa_problem_report('whatsapp:+971500000051', 'ZZ DEMO probe: the page did not load', 'en');
    perform public.fn_wa_human_request('whatsapp:+971500000052', true, 'ZZ DEMO probe asks for a person', 'ZZ DEMO probe detail');
    perform public.fn_it_engineer_finding_upsert('zz_demo:founder_figures_probe', 'ZZ DEMO probe finding', 'probe', 'internal', 0,
                                                 '{}'::jsonb, '{}', '{}', 'customer_support');
    -- leads.is_demo is generated from the name and address, so the fixture marks itself.
    insert into public.leads (company_name, email, registration_submitted_at)
    values ('ZZ DEMO Figures Probe Co', 'zz.figures.probe@example.invalid', now());
    a := public.fn_founder_whatsapp_figures('whatsapp:' || v_founder);
    raise exception 'ZZPROBE rollback';
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback'
                   and (stranger ->> 'ok')::boolean = false and stranger ->> 'reason' = 'not_the_founder' and not stranger ? 'suppliers'
                   and (b ->> 'ok')::boolean and (a ->> 'ok')::boolean and a ? 'read_at'
                   and (a #>> '{support,open_cases}')::int = (b #>> '{support,open_cases}')::int + 1
                   and (a #>> '{support,waiting_for_person}')::int = (b #>> '{support,waiting_for_person}')::int + 1
                   and (a #>> '{it,open_findings}')::int = (b #>> '{it,open_findings}')::int + 1
                   and a -> 'suppliers' = b -> 'suppliers'
                   and a ? 'requests' and a ? 'quotes' and a ? 'reveals_month' and a ? 'marketing_7d' and a ? 'brief'
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('stranger=%s; before=%s; after=%s; block ended with: %s', stranger, b, a, v_err);
end $probe$;
select * from zz_probe_verdict;

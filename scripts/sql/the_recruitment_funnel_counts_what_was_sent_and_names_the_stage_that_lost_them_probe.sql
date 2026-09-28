-- PROBE (pure: no DDL, always raises, so nothing survives). Run AFTER
-- the_recruitment_funnel_counts_what_was_sent_and_names_the_stage_that_lost_them.sql, or in ONE transaction with it
-- (the raise rolls both back). It must say PROBE OK. marketing, 28 Sep 2026.
--
-- Fixtures: three ZZ DEMO leads (is_demo by name) with @example.invalid addresses and trade 'zz_demo_trade', marked
-- invited with NO outbox row. The probe writes no notifications row at all, and asserts the outbox count is unchanged.
-- Proves: (1) an invitation link carries its ref; (2) the real candidate query builds its link through it;
-- (3) a registration through that link writes marketing_first_touch once (idempotent); (4) an opened claim link with
-- no browser touch still records the invitation, and an unopened one records nothing; (5) the stage rule names each
-- stage; (6) the diagnosis names invited -> sent (not actually sent) for the demo trade; (7) the daily duty files the
-- real email channel (0 registered) to the CEO once.
do $probe$
declare
  a bigint; b bigint; c bigint; v_link text; v_touch jsonb; r jsonb; v_fail text := '';
  v_out_before bigint; v_out_after bigint; v_body text; v_d jsonb; v_row jsonb; v_duty jsonb; v_imp int;
begin
  select count(*) into v_out_before from public.notifications;

  insert into public.leads (company_name, business_role, claimed, source, email, invite_trades, invited_at, invite_status)
  values ('ZZ DEMO funnel probe A', 'supplier', false, 'probe', 'zz-demo-funnel-a@example.invalid', array['zz_demo_trade'], now(), 'sent')
  returning id into a;
  insert into public.leads (company_name, business_role, claimed, source, email, invite_trades, invited_at, invite_status, invite_clicked_at)
  values ('ZZ DEMO funnel probe B', 'supplier', false, 'probe', 'zz-demo-funnel-b@example.invalid', array['zz_demo_trade'], now(), 'sent', now())
  returning id into b;
  insert into public.leads (company_name, business_role, claimed, source, email, invite_trades, invited_at, invite_status)
  values ('ZZ DEMO funnel probe C', 'supplier', false, 'probe', 'zz-demo-funnel-c@example.invalid', array['zz_demo_trade'], now(), 'sent')
  returning id into c;
  if (select count(*) from public.leads where id in (a, b, c) and is_demo and email like '%@example.invalid') <> 3 then
    raise exception 'CHK<<PROBE FAILED: a fixture lead is not demo or not @example.invalid>>';
  end if;

  -- (1) the ref
  v_link := public.fn_supplier_invite_link('https://quotesdone.com', 'en', (select claim_token from public.leads where id = a), a);
  if v_link !~ ('/en/portal[?]t=[0-9a-f-]{36}&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' || a || '$') then
    v_fail := v_fail || ' link=' || v_link;
  end if;
  -- (2) the real candidate query (a read; it writes nothing and sends nothing)
  select body into v_body from public.fn_supplier_invite_candidates(1);
  if v_body is not null and v_body !~ 'portal[?]t=[0-9a-f-]{36}&utm_source=invite&[^ ]*utm_content=lead-[0-9]+' then
    v_fail := v_fail || ' candidate_body_has_no_ref';
  end if;

  -- (3) A registers through the link: what the browser keeps is the link's own tags (src/lib/firstTouch.ts)
  v_touch := jsonb_build_object('utm_source', substring(v_link from 'utm_source=([^&]+)'), 'utm_medium', substring(v_link from 'utm_medium=([^&]+)'),
               'utm_campaign', substring(v_link from 'utm_campaign=([^&]+)'), 'utm_content', substring(v_link from 'utm_content=([^&]+)'),
               'landing_path', '/en/portal', 'first_seen_at', now());
  r := public.fn_marketing_first_touch_record(a, v_touch);
  if not (r->>'recorded')::boolean then v_fail := v_fail || ' a_not_recorded'; end if;
  r := public.fn_marketing_first_touch_record(a, v_touch);
  if (r->>'recorded')::boolean then v_fail := v_fail || ' a_recorded_twice'; end if;
  if not exists (select 1 from public.marketing_first_touch where lead_id = a and utm_source = 'invite' and utm_medium = 'email'
                  and utm_content = 'lead-' || a) then v_fail := v_fail || ' a_row_wrong'; end if;
  -- (4) B opened its claim link, the browser kept nothing; C never opened it
  r := public.fn_marketing_first_touch_record(b, null);
  if not (r->>'recorded')::boolean or not exists (select 1 from public.marketing_first_touch where lead_id = b and utm_source = 'invite'
     and utm_content = 'lead-' || b) then v_fail := v_fail || ' b_fallback_missing'; end if;
  r := public.fn_marketing_first_touch_record(c, null);
  if (r->>'recorded')::boolean then v_fail := v_fail || ' c_recorded_without_evidence'; end if;

  -- (5) the rule per stage
  if public.fn_marketing_funnel_largest_drop('{"invited":10,"sent":10,"delivered":10,"clicked":6,"started":0,"registered":0}')->>'cause' <> 'clicks_but_no_start' then v_fail := v_fail || ' rule_click'; end if;
  if public.fn_marketing_funnel_largest_drop('{"invited":10,"sent":10,"delivered":2,"clicked":0,"started":0,"registered":0}')->>'cause' <> 'bounced_or_undelivered' then v_fail := v_fail || ' rule_bounce'; end if;
  if public.fn_marketing_funnel_largest_drop('{"invited":10,"sent":10,"delivered":10,"clicked":0,"started":0,"registered":0}')->>'cause' <> 'no_clicks' then v_fail := v_fail || ' rule_noclick'; end if;
  if public.fn_marketing_funnel_largest_drop('{"invited":10,"sent":10,"delivered":10,"clicked":9,"started":8,"registered":0}')->>'cause' <> 'started_not_finished' then v_fail := v_fail || ' rule_form'; end if;
  if public.fn_marketing_funnel_largest_drop('{"invited":10,"sent":0,"delivered":0,"clicked":0,"started":0,"registered":0}')->>'cause' <> 'not_actually_sent' then v_fail := v_fail || ' rule_notsent'; end if;

  -- (7) the daily duty over real leads (demo excluded): files the email channel to the CEO once
  v_duty := public.fn_marketing_recruitment_funnel();
  v_imp := jsonb_array_length(v_duty->'diagnosis'->'filed');
  if v_imp < 1 or not exists (select 1 from public.ceo_improvement where source_kind = 'funnel_stage_drop' and seat = 'marketing') then
    v_fail := v_fail || ' not_filed';
  end if;
  v_duty := public.fn_marketing_recruitment_funnel();   -- a second run the same day files nothing new
  if (select count(*) from public.ceo_improvement where source_kind = 'funnel_stage_drop') <> v_imp then v_fail := v_fail || ' filed_twice'; end if;

  -- (6) A registers; the demo trade's diagnosis still names invited -> sent (3 invited, 0 in the outbox)
  update public.leads set claimed = true, registration_submitted_at = now() where id = a;
  v_d := public.fn_marketing_funnel_diagnosis(true, false);
  select e into v_row from jsonb_array_elements(v_d->'by_trade') e where e->>'trade' = 'zz_demo_trade';
  if v_row is null or v_row->'drop'->>'cause' <> 'not_actually_sent' or (v_row->'stages'->>'invited')::int <> 3
     or (v_row->'stages'->>'registered')::int <> 1 or (v_row->'stages'->>'clicked')::int <> 1 then
    v_fail := v_fail || ' diagnosis=' || coalesce(v_row::text, 'null');
  end if;

  select count(*) into v_out_after from public.notifications;
  if v_out_after <> v_out_before then v_fail := v_fail || ' OUTBOX_CHANGED ' || v_out_before || '->' || v_out_after; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then
    'PROBE OK: first_touch rows=' || (select count(*) from public.marketing_first_touch where lead_id in (a, b, c))
    || ' demo_trade=' || (v_row->'stages')::text || ' drop=' || (v_row->'drop'->>'from') || '->' || (v_row->'drop'->>'to')
    || ' real_email=' || (select (e->'stages')::text || ' cause=' || (e->'drop'->>'cause') from jsonb_array_elements(v_duty->'diagnosis'->'channels') e where e->>'channel' = 'email')
    || ' ceo_improvements_filed=' || v_imp || ' outbox_delta=' || (v_out_after - v_out_before)
    else 'PROBE FAILED:' || v_fail end;
end
$probe$;

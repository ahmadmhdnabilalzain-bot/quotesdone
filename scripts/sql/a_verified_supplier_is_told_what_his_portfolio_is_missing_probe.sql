-- PROBE: a verified supplier is told what his portfolio is missing (23 Sep 2026, sales_engineer).
--
-- No DDL. Run AFTER a_verified_supplier_is_told_what_his_portfolio_is_missing.sql is applied. Returns ONE
-- verdict row. Also run on every pull request by
-- scripts/checks/a_verified_supplier_is_told_what_his_portfolio_is_missing.test.mjs.
--
-- The rehearsal writes ONLY inside a block its own raise rolls back (zero residue, asserted after), on
-- ZZ DEMO / @example.invalid fixtures with a 9715000000xx demo handset, so nothing it queues is ever
-- committed, and even inside the block zzzz_notifications_demo_capture marks every row it queues
-- 'suppressed'. It proves:
--   (a) a verified supplier with a declared trade and no ticked service gets exactly one handoff, one
--       email and one WhatsApp twin with its state recorded — at 3 working days and not before;
--   (b) a supplier who ticked his services straight away gets nothing;
--   (c) a supplier who completes between detection and send gets nothing;
--   (d) weekends do not count: verified Thursday 17 Sep 10:00 Dubai -> due Tuesday 22 Sep 10:00;
--   (e) a re-run sends nothing twice, and sales_engineer (only) closes what support answered.
create temp table if not exists zz_portfolio_probe (verdict text) on commit drop;
do $probe$
declare
  f text[] := '{}'; v_fn text; v jsonb; v_n int; v_left int;
  v_a bigint; v_b bigint; v_c bigint; v_h bigint; v_hc bigint;
  v_thu timestamptz := timestamptz '2026-09-17 10:00:00 Asia/Dubai';
  v_mon timestamptz := timestamptz '2026-09-21 12:00:00 Asia/Dubai';   -- due Monday if weekends counted
  v_tue_early timestamptz := timestamptz '2026-09-22 09:59:00 Asia/Dubai';
  v_tue timestamptz := timestamptz '2026-09-22 10:00:01 Asia/Dubai';
  v_ev jsonb; e public.notifications;
begin
  -- ── structure ──
  foreach v_fn in array array['public.fn_supplier_portfolio_gaps(bigint)',
      'public.fn_supplier_portfolio_reminder_compose(public.leads,jsonb)',
      'public.fn_customer_support_reminds_supplier_of_portfolio(bigint)',
      'public.fn_supplier_portfolio_reminder_tick(boolean,timestamptz,bigint)', 'public.fn_seat_clocks_tick()'] loop
    if to_regprocedure(v_fn) is null then f := f || (v_fn || ' does not exist'); continue; end if;
    if has_function_privilege('anon', to_regprocedure(v_fn), 'execute')
       or has_function_privilege('authenticated', to_regprocedure(v_fn), 'execute')
       or not exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_fn)
                       and array_to_string(p.proconfig, ',') like '%search_path%') then
      f := f || (v_fn || ' is callable by anon/authenticated or has no pinned search_path');
    end if;
  end loop;
  if cardinality(f) > 0 then insert into zz_portfolio_probe values ('PROBE FAILED: ' || array_to_string(f, '; ')); return; end if;
  if not exists (select 1 from public.seat_handoff_kind where type = 'supplier.portfolio_incomplete'
                   and from_seat = 'sales_engineer' and to_seat = 'customer_support' and originator_closes) then
    f := f || text 'supplier.portfolio_incomplete is not a registered originator-closed conversation'; end if;
  -- The WhatsApp leg's state is read from the template ledger by SID; a rehearsal twin is always captured
  -- ('suppressed'), so the lookup a real supplier's twin depends on is asserted here directly.
  if not exists (select 1 from public.messaging_template t, public.app_secrets s
                  where s.key = 'wa_template_sids' and t.sid in (s.value::jsonb #>> '{supplier_account_notice,en}',
                                                                 s.value::jsonb #>> '{supplier_account_notice,ar}')) then
    f := f || text 'the template ledger has no row for the supplier_account_notice SIDs, so the WhatsApp leg cannot be stated'; end if;
  if public.fn_add_working_days(v_thu, 3) <> timestamptz '2026-09-22 10:00:00 Asia/Dubai' then
    f := f || ('(d) Thursday + 3 working days is ' || public.fn_add_working_days(v_thu, 3) || ', not Tuesday 10:00 Dubai'); end if;

  begin
    -- ── fixtures: three verified ZZ DEMO suppliers, the mandatory six present so the gate admits them ──
    insert into storage.objects (bucket_id, name) values
      ('supplier-docs', 'zz-demo-portfolio-probe/licence.pdf'), ('supplier-docs', 'zz-demo-portfolio-probe/profile.pdf');
    insert into public.leads (company_name, email, claimed_by, claimed, phone, owner_phone_verified, owner_email_verified,
                              license_doc_path, company_profile_doc_path, signed_terms_path, locale,
                              whatsapp_opt, whatsapp_phone, whatsapp_verified_at, tags)
    select 'ZZ DEMO portfolio probe ' || s, 'zz.portfolio.' || s || '@example.invalid', 'zz.portfolio.' || s || '@example.invalid', true,
           '+971500000012', true, true, 'zz-demo-portfolio-probe/licence.pdf', 'zz-demo-portfolio-probe/profile.pdf',
           'zz-demo-portfolio-probe/terms.pdf', case s when 'a' then 'ar' else 'en' end,
           'other', '+971500000012', now(), array['qd_demo']
      from unnest(array['a', 'b', 'c']) s;
    select id into v_a from public.leads where email = 'zz.portfolio.a@example.invalid';
    select id into v_b from public.leads where email = 'zz.portfolio.b@example.invalid';
    select id into v_c from public.leads where email = 'zz.portfolio.c@example.invalid';
    update public.leads set verified = true, approval_status = 'approved' where id in (v_a, v_b, v_c);
    update public.leads set approved_at = v_thu where id in (v_a, v_b, v_c);
    select count(*) into v_n from public.leads where id in (v_a, v_b, v_c) and verified and approval_status = 'approved' and approved_at = v_thu;
    if v_n <> 3 then raise exception 'fixture: only % of 3 suppliers are verified on Thursday', v_n; end if;
    insert into public.supplier_capabilities (supplier_id, trades, roles, services, confirmed_at) values
      (v_a, '{painting}', '{contractor}', '{}', now()),                       -- declared a trade, ticked nothing
      (v_b, '{painting}', '{contractor}', '{painting.interior}', now()),      -- ticked straight away
      (v_c, '{painting}', '{contractor}', '{}', now());                       -- will tick between detection and send

    -- ── (d) not before the third working day, and the weekend does not count ──
    v := public.fn_supplier_portfolio_reminder_tick(true, v_mon, v_a);
    if (v->>'opened')::int <> 0 then f := f || text '(d) a Thursday verification was reminded on Monday: the weekend counted'; end if;
    v := public.fn_supplier_portfolio_reminder_tick(true, v_tue_early, v_a);
    if (v->>'opened')::int <> 0 then f := f || text '(a) reminded before Tuesday 10:00, the third working day'; end if;

    -- ── (a) at 3 working days: one handoff, one email, one WhatsApp twin, state recorded ──
    v := public.fn_supplier_portfolio_reminder_tick(true, v_tue, v_a);
    if (v->>'opened')::int <> 1 then f := f || ('(a) the tick at Tuesday 10:00 opened ' || coalesce(v->>'opened', 'null') || ' handoffs, not 1'); end if;
    select count(*), max(id) into v_n, v_h from public.agent_actions
     where kind = 'handoff' and agent = 'customer_support' and detail->>'type' = 'supplier.portfolio_incomplete' and detail->>'lead_id' = v_a::text;
    if v_n <> 1 then f := f || ('(a) ' || v_n || ' handoffs for the supplier, not 1'); end if;
    select evidence into v_ev from public.agent_actions where id = v_h;
    if not coalesce((v_ev->>'sent')::boolean, false) then f := f || ('(a) support did not send: ' || coalesce(v_ev::text, 'no answer')); end if;
    if v_ev#>>'{gaps,0,code}' is distinct from 'trade_without_service' then f := f || ('(a) the gap was not "painting has no service ticked": ' || coalesce(v_ev->>'gaps', 'none')); end if;
    select count(*) into v_n from public.notifications where lead_id = v_a and type = 'supplier_portfolio_incomplete' and channel = 'email';
    if v_n <> 1 then f := f || ('(a) ' || v_n || ' emails, not 1'); end if;
    select * into e from public.notifications where lead_id = v_a and type = 'supplier_portfolio_incomplete' and channel = 'email';
    if e.lang is distinct from 'ar' or e.body !~ 'تحية طيبة وبعد' or e.body !~ 'الدهانات والتشطيبات' or e.body !~ '/ar/portal' then
      f := f || text '(a) the Arabic-registered supplier was not written to in formal Arabic naming his trade and his portal'; end if;
    select count(*) into v_n from public.notifications where lead_id = v_a and type = 'supplier_portfolio_incomplete' and channel = 'whatsapp';
    if v_n <> 1 then f := f || ('(a) ' || v_n || ' WhatsApp twins, not 1'); end if;
    if coalesce(v_ev#>>'{whatsapp,state}', '') not in ('queued', 'pending_template', 'suppressed')
       or (v_ev#>>'{whatsapp,notification_id}') is null then
      f := f || ('(a) the WhatsApp leg is not recorded against its twin row: ' || coalesce(v_ev->>'whatsapp', 'nothing')); end if;
    if exists (select 1 from public.notifications where type = 'supplier_portfolio_incomplete' and lead_id in (v_a, v_b, v_c)
                 and ((to_email is not null and not public.fn_is_demo_email(to_email)) or (to_phone is not null and not public.fn_is_demo_phone(to_phone))
                      or coalesce(status, '') <> 'suppressed')) then
      f := f || text 'a rehearsal row can reach a real address or was not captured'; end if;

    -- ── (b) ticked straight away: nothing ──
    v := public.fn_supplier_portfolio_reminder_tick(true, v_tue, v_b);
    if (v->>'opened')::int <> 0 or (v->>'complete_at_due')::int <> 1 then f := f || ('(b) a complete portfolio was acted on: ' || v::text); end if;
    if exists (select 1 from public.notifications where lead_id = v_b and type = 'supplier_portfolio_incomplete') then
      f := f || text '(b) a supplier who ticked his services was reminded'; end if;

    -- ── (c) incomplete at detection, complete at send: nothing ──
    -- The handoff is written as fn_seat_handoff writes it, WITHOUT acting, so the gap between the sales
    -- engineer seeing the gap and support sending is real; then the supplier ticks, then support acts.
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('customer_support', 'handoff', 'pending', 'low', 'supplier.portfolio_incomplete probe',
            jsonb_build_object('type', 'supplier.portfolio_incomplete', 'from', 'sales_engineer', 'from_name', 'sales_engineer',
                               'to', 'customer_support', 'subject_table', 'leads', 'subject_id', v_c || ':probe',
                               'lead_id', v_c, 'gaps_at_detection', public.fn_supplier_portfolio_gaps(v_c)),
            'leads', 'supplier.portfolio_incomplete:' || v_c || ':' || extract(epoch from v_thu)::bigint)
    returning id into v_hc;
    if jsonb_array_length(public.fn_supplier_portfolio_gaps(v_c)) = 0 then f := f || text '(c) fixture: no gap at detection'; end if;
    update public.supplier_capabilities set services = '{painting.interior}' where supplier_id = v_c;
    perform public.fn_seat_handoff_act(v_hc);
    select evidence into v_ev from public.agent_actions where id = v_hc;
    if not (v_ev ? 'not_sent') then f := f || ('(c) support did not re-check at send time: ' || coalesce(v_ev::text, 'no answer')); end if;
    if exists (select 1 from public.notifications where lead_id = v_c and type = 'supplier_portfolio_incomplete') then
      f := f || text '(c) a supplier who completed between detection and send was reminded'; end if;

    -- ── (e) re-runs: nothing twice; sales_engineer re-verifies and closes; support cannot ──
    begin
      perform set_config('qd.handoff_closer', 'customer_support', true);
      perform public.fn_seat_handoff_complete(v_h, '{}'::jsonb);
      f := f || text '(e) customer_support closed a handoff only sales_engineer may close';
    exception when others then null;
    end;
    perform set_config('qd.handoff_closer', '', true);
    v_n := 0; v_left := 0;
    foreach v_fn in array array[v_a::text, v_b::text, v_c::text] loop
      v := public.fn_supplier_portfolio_reminder_tick(true, v_tue + interval '30 minutes', v_fn::bigint);
      v_n := v_n + (v->>'opened')::int; v_left := v_left + (v->>'closed')::int;
    end loop;
    if v_n <> 0 then f := f || ('(e) the re-run opened ' || v_n || ' more handoffs'); end if;
    if v_left <> 2 then f := f || ('(e) the re-run closed ' || v_left || ' of the 2 answered handoffs'); end if;
    if (select status from public.agent_actions where id = v_h) <> 'done' or (select status from public.agent_actions where id = v_hc) <> 'done' then
      f := f || text '(e) an answered handoff was not closed by sales_engineer'; end if;
    if (select evidence->>'reverified_by' from public.agent_actions where id = v_h) is distinct from 'sales_engineer' then
      f := f || text '(e) the close carries no re-verification'; end if;
    v_left := 0;
    foreach v_fn in array array[v_a::text, v_b::text, v_c::text] loop
      v := public.fn_supplier_portfolio_reminder_tick(true, v_tue + interval '2 days', v_fn::bigint);
      v_left := v_left + (v->>'opened')::int;
    end loop;
    select count(*) into v_n from public.notifications where lead_id in (v_a, v_b, v_c) and type = 'supplier_portfolio_incomplete';
    if v_n <> 2 or v_left <> 0 then f := f || ('(e) after three re-runs there are ' || v_n || ' messages, not the one email and its one twin'); end if;
    select count(*) into v_n from public.agent_actions where kind = 'handoff' and detail->>'type' = 'supplier.portfolio_incomplete' and detail->>'lead_id' = v_a::text;
    if v_n <> 1 then f := f || ('(e) ' || v_n || ' handoffs for one verification'); end if;

    -- the heartbeat step runs clean with the new duty in it
    v := public.fn_seat_clocks_tick();
    if not coalesce((v#>>'{portfolio_reminder,ok}')::boolean, false) then f := f || ('fn_seat_clocks_tick did not run the portfolio reminder: ' || left(v::text, 300)); end if;

    raise exception 'zz_portfolio_probe_done';
  exception when others then
    if sqlerrm <> 'zz_portfolio_probe_done' then f := f || ('the rehearsal raised: ' || sqlerrm); end if;
  end;

  select count(*) into v_left from public.leads where company_name like 'ZZ DEMO portfolio probe %';
  if v_left <> 0 then f := f || (v_left || ' probe supplier(s) survived the rollback'); end if;
  select count(*) into v_left from storage.objects where name like 'zz-demo-portfolio-probe/%';
  if v_left <> 0 then f := f || (v_left || ' probe storage row(s) survived the rollback'); end if;
  insert into zz_portfolio_probe values (case when cardinality(f) = 0
    then 'PROBE OK: (a) one handoff, one formal-Arabic email and one WhatsApp twin with its state recorded, at Tuesday 10:00 and not before; (b) a supplier who ticked straight away gets nothing; (c) one who completed between detection and send gets nothing; (d) Thursday + 3 working days is Tuesday, the weekend not counted; (e) re-runs send nothing twice and only sales_engineer closes, after re-verifying; nothing to a real address; zero residue'
    else 'PROBE FAILED: ' || array_to_string(f, '; ') end);
end $probe$;
select verdict from zz_portfolio_probe;

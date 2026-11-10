-- PROBE: A REQUEST THE MATCHER COULD NOT REACH IS MATCHED AGAIN AND NEVER CLOSED AS UNREACHED.
-- Seat: sales_engineer. 10 Nov 2026. Pure probe: no DDL, never applied. Run after
-- a_request_the_matcher_could_not_reach_is_matched_again_and_never_closed_as_unreached.sql (or concatenated after it in one
-- rolled-back transaction: scripts/ci/rehearse_sql.mjs <file> <this>). It always raises, so every row is rolled back, and
-- pg_net sends only committed requests. Every party is a ZZ DEMO fixture on @example.invalid, and the closer is run at a
-- clock in the year 2000 (p_at), so only the fixtures, created in 1999, are old enough for it to see.
-- PROBE OK only if
--   1. a request the matcher did not answer, re-match still running, is NOT closed at 14 days, NOT flagged to the stalled-
--      supplier rescue, and its concierge reads matching (not finding_suppliers), its first-request letter "we are matching";
--   2. the same request with its schedule spent IS closed, and the customer is told the fault was ours, not "still
--      registering suppliers"; an ordinary unreached request beside it is still closed with the registering reason;
--   3. once matched, fn_sales_engineer_rematch_told writes to the customer once (a second call is "already written"), and
--      a re-match that reached nobody writes nothing.
do $probe$
declare
  fails text := ''; o jsonb := '{}'::jsonb; v jsonb; c uuid := gen_random_uuid(); iw uuid := gen_random_uuid(); ip uuid := gen_random_uuid();
  t0 timestamptz := '1999-12-01 08:00+00'; at2000 timestamptz := '2000-01-01 08:00+00'; b text;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Rematch Customer', 'zz-demo-rematch@example.invalid', '+971500000141', true, true, 'demo://terms', 'en', t0);
  -- iw: the matcher did not answer, re-match attempt 3 of 10 pending; ip: an ordinary request that reached nobody
  -- complete briefs (trg_rfq_complete scores them ready), so "held for its specs" is not what keeps them open
  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, budget, scope_type, trades, spec, status, lang, created_at, routing)
  select x.id, c, 'plumbing', 'Dubai',
         'ZZ DEMO supply and install two 80 litre electric wall mounted water heaters in one bathroom, with isolation valves, old units removed and disposed of',
         'ZZ DEMO replace two 80 litre water heaters in a villa in Dubai Marina, wall mounted, electric, by next week', 'AED 5,000', 'single', array['plumbing'],
         jsonb_build_object('fixture_count', '1 bathroom, 2 water heaters', 'scope_detail', 'supply and install two 80 litre electric water heaters with isolation valves'),
         'sent', 'en', x.at, x.routing
    from (values (iw, t0, jsonb_build_object('matcher_unavailable', true, 'waiting_for', 'sales_engineer.match',
                    'rematch', jsonb_build_object('attempts', 3, 'first_failed_at', t0, 'next_at', at2000, 'exhausted', false, 'extra', ''))),
                 (ip, t0 + interval '1 minute', '{"outcome":"no_fit"}'::jsonb)) x(id, at, routing);
  if exists (select 1 from public.inquiries where id in (iw, ip) and not rfq_ready) then
    raise exception 'CHK<<PROBE FAILED: the fixtures are not complete briefs: %>>', (select jsonb_agg(completeness) from public.inquiries where id in (iw, ip));
  end if;

  -- 1. waiting: not flagged, not closed, concierge "matching"
  v := public.fn_stalled_inquiry_flag(iw, 'probe');
  if coalesce((v->>'flagged')::boolean, true) or v->>'why' is distinct from 'waiting for the re-match' then fails := fails || ' 1:flag(' || v::text || ')'; end if;
  v := public.fn_customer_concierge_held(iw);
  if not coalesce((v->>'matching')::boolean, false) or coalesce((v->>'finding_suppliers')::boolean, true) then fails := fails || ' 1:held(' || v::text || ')'; end if;
  b := public.fn_customer_concierge_message(iw, 'first_request')->>'body';
  if position('We are matching your request' in coalesce(b, '')) = 0 or position('still registering' in coalesce(b, '')) > 0 then fails := fails || ' 1:letter'; end if;
  v := public.fn_sales_engineer_closes_unreached_requests(at2000);
  o := o || jsonb_build_object('closer_while_waiting', v);
  if (select status from public.inquiries where id = iw) <> 'sent' then fails := fails || ' 1:closed_while_waiting'; end if;
  if (select status from public.inquiries where id = ip) <> 'expired' then fails := fails || ' 2:ordinary_not_closed'; end if;
  if not exists (select 1 from public.notifications n where n.inquiry_id = ip and n.type = 'request_closed_no_supplier' and n.body like '%still registering suppliers%')
     then fails := fails || ' 2:ordinary_reason'; end if;

  -- 2. the schedule spent: closed, and the reason is ours
  update public.inquiries set routing = jsonb_set(routing, '{rematch,exhausted}', 'true'::jsonb) where id = iw;
  v := public.fn_sales_engineer_closes_unreached_requests(at2000);
  o := o || jsonb_build_object('closer_when_exhausted', v);
  if (select status from public.inquiries where id = iw) <> 'expired' then fails := fails || ' 2:exhausted_not_closed'; end if;
  select n.body into b from public.notifications n where n.inquiry_id = iw and n.type = 'request_closed_no_supplier';
  if position('a fault on our side' in coalesce(b, '')) = 0 or position('still registering' in coalesce(b, '')) > 0 then fails := fails || ' 2:our_reason(' || coalesce(b, 'none') || ')'; end if;

  -- 3. matched on re-match: told once; nobody: nothing
  update public.inquiries set status = 'sent', routing = '{"outcome":"dispatched","fanout":2}'::jsonb where id = iw;
  -- fn_email_sendable refuses an @example.invalid address ("domain does not accept mail"), so the fixture's letter is
  -- recorded at its stage and not sent: the record is what proves the routine wrote it, and only once.
  v := public.fn_sales_engineer_rematch_told(iw, 2);
  o := o || jsonb_build_object('told', v);
  if not exists (select 1 from public.customer_support_duty_message d where d.stage = 'rematch.matched' and d.subject_key = iw::text and d.customer_id = c)
     then fails := fails || ' 3:not_told(' || v::text || ')'; end if;
  v := public.fn_sales_engineer_rematch_told(iw, 2);
  if v->>'reason' is distinct from 'already written at this stage' then fails := fails || ' 3:told_twice(' || v::text || ')'; end if;
  v := public.fn_sales_engineer_rematch_told(ip, 0);
  if coalesce((v->>'sent')::boolean, true) then fails := fails || ' 3:told_for_nobody'; end if;
  if exists (select 1 from public.notifications n where n.inquiry_id in (iw, ip) and not public.fn_is_demo_email(n.to_email)) then
    fails := fails || ' X:a_real_address'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:% | %>>', fails, o::text; end if;
  raise exception 'CHK<<PROBE OK %>>', o::text;
end $probe$;

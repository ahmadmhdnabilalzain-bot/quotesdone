-- PROBE: AN UNANSWERED REQUEST IS A STRIKE, AND A QUOTE CLEARS THE RUN. Seat: sales_engineer (matching), delivered by
-- customer_support. 10 Nov 2026. Pure probe: no DDL, never applied; run after (or concatenated after)
-- an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.sql. It always raises, so every row is rolled back.
-- Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if
--   1. a request that EXPIRES strikes the matched supplier who wrote no quote, once, and not the one who quoted;
--   2. moving its status again does not strike twice; a CANCELLED request, one matched too recently and one still
--      waiting for the customer's details strike nobody;
--   3. three expired requests make the silent supplier unmatchable (fn_is_matchable), and one quote clears him to 0.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); s_quiet bigint; s_quoted bigint; i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid();
  i3 uuid := gen_random_uuid(); ic uuid := gen_random_uuid(); ir uuid := gen_random_uuid(); ih uuid := gen_random_uuid(); n int; l public.leads;
begin
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Strike Customer', 'zz-demo-strike@example.invalid', '+971500000148', true, true, 'demo://terms', 'en', now() - interval '60 days');
  insert into public.leads (company_name, email, claimed_by) values ('ZZ DEMO Strike Quiet', 'zz-demo-strike-q@example.invalid', 'zz-demo-strike-q@example.invalid') returning id into s_quiet;
  insert into public.leads (company_name, email, claimed_by) values ('ZZ DEMO Strike Quoted', 'zz-demo-strike-a@example.invalid', 'zz-demo-strike-a@example.invalid') returning id into s_quoted;
  -- complete briefs (trg_rfq_complete scores them ready), except ih: a bare request still waiting for the customer's details
  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, budget, scope_type, trades, spec, status, lang, created_at)
  select x, c, 'plumbing', 'Dubai',
         'ZZ DEMO supply and install two 80 litre electric wall mounted water heaters in one bathroom, with isolation valves, old units removed and disposed of',
         'ZZ DEMO replace two 80 litre water heaters in a villa in Dubai Marina, wall mounted, electric, by next week', 'AED 5,000', 'single', array['plumbing'],
         jsonb_build_object('fixture_count', '1 bathroom, 2 water heaters', 'scope_detail', 'supply and install two 80 litre electric water heaters with isolation valves'),
         'sent', 'en', now() - interval '40 days'
    from unnest(array[i1, i2, i3, ic, ir]) x;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  values (ih, c, 'plumbing', 'Dubai', 'ZZ DEMO strike probe held', 'sent', 'en', now() - interval '40 days', 'single');
  if exists (select 1 from public.inquiries where id in (i1, i2, i3, ic, ir) and not rfq_ready) or (select rfq_ready from public.inquiries where id = ih) then
    raise exception 'CHK<<PROBE FAILED: the fixture briefs are not scored as the probe needs>>'; end if;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select x, s, 0.9, case when x = ir then now() - interval '3 days' else now() - interval '30 days' end, 'ZZ DEMO strike probe'
    from unnest(array[i1, i2, i3, ic, ir, ih]) x cross join unnest(array[s_quiet, s_quoted]) s;
  -- each request REACHED the silent supplier (read on WhatsApp): since
  -- a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql an unread request is not a strike
  insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, subject, body, status, channel, provider_status)
  select 'new_inquiry', 'zz-demo-strike-q@example.invalid', 'supplier', s_quiet, x, 'New job request on QuotesDone', 'ZZ DEMO', 'sent', 'whatsapp', 'read'
    from unnest(array[i1, i2, i3, ic, ir, ih]) x;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at)
  select gen_random_uuid(), x, s_quoted, 9000, 'submitted', now() - interval '20 days' from unnest(array[i1, i2, i3, ic, ir]) x;
  if (select chat_strikes from public.leads where id = s_quoted) <> 0 then fails := fails || ' 0:quoted_starts_struck'; end if;

  update public.inquiries set status = 'expired' where id = i1;
  if (select coalesce(chat_strikes, 0) from public.leads where id = s_quiet) <> 1 then fails := fails || ' 1:quiet'; end if;
  if (select coalesce(chat_strikes, 0) from public.leads where id = s_quoted) <> 0 then fails := fails || ' 1:quoted'; end if;
  update public.inquiries set status = 'sent' where id = i1;
  update public.inquiries set status = 'lost' where id = i1;
  update public.inquiries set status = 'cancelled' where id = ic;
  update public.inquiries set status = 'expired' where id = ir;
  update public.inquiries set status = 'expired' where id = ih;   -- still waiting for the customer's details
  if (select coalesce(chat_strikes, 0) from public.leads where id = s_quiet) <> 1 then fails := fails || ' 2:twice_or_cancel_or_recent'; end if;

  update public.inquiries set status = 'expired' where id = i2;
  -- the warning at limit-1 reached him (delivered): since a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql
  -- the strike that pauses him counts only then (release wave C: without this line the probe stopped at 2 on the merged tree)
  update public.notifications set status = 'sent', provider_status = 'delivered' where type = 'supplier_strike_warning' and lead_id = s_quiet;
  update public.inquiries set status = 'expired' where id = i3;
  select * into l from public.leads where id = s_quiet;
  if coalesce(l.chat_strikes, 0) <> 3 or public.fn_is_matchable(true, l.banned, l.matching_blocked, 'approved', l.permanently_closed, l.chat_strikes) then
    fails := fails || ' 3:not_paused(' || coalesce(l.chat_strikes, 0) || ')'; end if;
  -- An ended request takes no quotation (trigger a06, no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.sql,
  -- 19 Nov 2026), so the quote that clears the run arrives on ir reopened, as a request still taking quotes.
  update public.inquiries set status = 'sent' where id = ir;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at) values (gen_random_uuid(), ir, s_quiet, 8000, 'draft', now());
  if (select coalesce(chat_strikes, 0) from public.leads where id = s_quiet) <> 0 then fails := fails || ' 3:not_cleared'; end if;
  select count(*) into n from public.supplier_strike_event where lead_id = s_quiet;
  if n <> 4 then fails := fails || ' 3:events(' || n || ')'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: 3 expired requests -> 3 strikes and unmatchable; re-ending, a cancel, a recent match and a request waiting for details strike nothing; a quote clears to 0; 4 events>>';
end $probe$;

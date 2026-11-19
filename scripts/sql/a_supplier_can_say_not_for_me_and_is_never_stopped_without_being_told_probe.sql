-- PROBE: A SUPPLIER CAN SAY "NOT FOR ME", AND IS NEVER STOPPED WITHOUT BEING TOLD. Seat: sales_engineer. Agent: NOT_FOR_ME,
-- 16 Nov 2026. Pure probe: no DDL, never applied; run after (or in the same rolled-back transaction as)
-- a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql. It always raises, so every row is rolled back.
-- Every party is a ZZ DEMO fixture on @example.invalid; no real row is read or written.
-- PROBE OK only if
--   1. an ended request that was READ (a WhatsApp 'read', an open, a portal sign-in after the send) strikes; one never sent,
--      one that bounced and one delivered but never opened do not, and are recorded 'not_counted' with the facts;
--   2. one strike short of the limit the supplier is written a warning naming the requests and what to do; at the limit, a stop
--      notice; a declined request is never a strike, and declining one that already struck withdraws that strike;
--   3. a decline after quoting is refused; "I'm available" clears the run and sets him available;
--   4. a correction cannot remove his last trade, keeps one open proposal, and is decided once;
--   5. contact details removed from a quotation are counted and told once, citing clause 10; a brand is not a contact detail;
--   6. the reveal standing is away with the date / not revealable (licence lapsed, not approved, closed) / proceed;
--   7. among 45,000 / 46,000 / 450,000 only the 450,000 is far from its peers; its fix line names only its own total; the
--      quality flags carry it; his confirmation clears it, and the reveal door asks him once while it is unconfirmed;
--   8. the weekly decline review files one reasoning question per supplier, and a "remove_trade" decision becomes a proposal
--      the supplier is asked to confirm.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); s_a bigint; s_b bigint; s_c bigint; s_q bigint; n int; j jsonb; l public.leads;
  i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid(); i3 uuid := gen_random_uuid(); i4 uuid := gen_random_uuid();
  i5 uuid := gen_random_uuid(); i6 uuid := gen_random_uuid(); ip uuid := gen_random_uuid();
  q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); v_held bigint; v_corr bigint;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO NFM Customer', 'zz-demo-nfm-c@example.invalid', '+971500000171', true, true, 'demo://terms', 'en', now() - interval '60 days');
  -- an approved supplier must carry the mandatory six as evidence (a_supplier_describes_its_services_in_its_own_words_probe.sql
  -- says why); these storage rows are the probe's own and roll back with it
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'suppliers/zz-demo-nfm-licence.pdf'), ('supplier-docs', 'suppliers/zz-demo-nfm-profile.pdf')
  on conflict do nothing;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, verified, approval_status, license_expiry)
  values ('ZZ DEMO NFM Reads', 'zz-demo-nfm-a@example.invalid', 'zz-demo-nfm-a@example.invalid', 'Dubai', '+971500000172', true, true,
          'suppliers/zz-demo-nfm-licence.pdf', 'suppliers/zz-demo-nfm-profile.pdf', 'suppliers/zz-demo-nfm-terms.pdf', true, 'approved', v_today + 200)
  returning id into s_a;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, verified, approval_status, license_expiry)
  values ('ZZ DEMO NFM Never Reached', 'zz-demo-nfm-b@example.invalid', 'zz-demo-nfm-b@example.invalid', 'Dubai', '+971500000173', true, true,
          'suppliers/zz-demo-nfm-licence.pdf', 'suppliers/zz-demo-nfm-profile.pdf', 'suppliers/zz-demo-nfm-terms.pdf', true, 'approved', v_today + 200)
  returning id into s_b;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, verified, approval_status, license_expiry)
  values ('ZZ DEMO NFM Peer C', 'zz-demo-nfm-c2@example.invalid', 'zz-demo-nfm-c2@example.invalid', 'Dubai', '+971500000174', true, true,
          'suppliers/zz-demo-nfm-licence.pdf', 'suppliers/zz-demo-nfm-profile.pdf', 'suppliers/zz-demo-nfm-terms.pdf', true, 'approved', v_today + 200)
  returning id into s_c;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, verified, approval_status, license_expiry)
  values ('ZZ DEMO NFM Peer Q', 'zz-demo-nfm-q@example.invalid', 'zz-demo-nfm-q@example.invalid', 'Dubai', '+971500000175', true, true,
          'suppliers/zz-demo-nfm-licence.pdf', 'suppliers/zz-demo-nfm-profile.pdf', 'suppliers/zz-demo-nfm-terms.pdf', true, 'approved', v_today + 200)
  returning id into s_q;
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, review_status, confirmed_at)
  values (s_a, array['plumbing', 'tiling'], array['executes'], array['plumbing.water_heater'], 'confirmed', now()),
         (s_b, array['plumbing'], array['executes'], '{}', 'confirmed', now());

  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, budget, scope_type, trades, spec, status, lang, created_at)
  select x, c, 'plumbing', 'Dubai',
         'ZZ DEMO supply and install two 80 litre electric wall mounted water heaters in one bathroom, with isolation valves, old units removed and disposed of',
         'ZZ DEMO replace two 80 litre water heaters in a villa in Dubai Marina, wall mounted, electric, by next week', 'AED 5,000', 'single', array['plumbing'],
         jsonb_build_object('fixture_count', '1 bathroom, 2 water heaters', 'scope_detail', 'supply and install two 80 litre electric water heaters with isolation valves'),
         'sent', 'en', now() - interval '40 days'
    from unnest(array[i1, i2, i3, i4, i5, i6, ip]) x;
  if exists (select 1 from public.inquiries where id in (i1, i2, i3, i4, i5, i6) and not rfq_ready) then
    raise exception 'CHK<<PROBE FAILED: the fixture briefs are not scored ready>>'; end if;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select x, s, 0.9, now() - interval '30 days', 'ZZ DEMO nfm probe · implied: tiling -> plumbing.water_heater'
    from unnest(array[i1, i2, i3, i4, i5, i6]) x cross join unnest(array[s_a, s_b]) s;
  -- s_a READ i1..i3 and i5 on WhatsApp; s_b: i1 never sent, i2 bounced, i3 delivered and never opened
  insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, subject, body, status, channel, provider_status)
  select 'new_inquiry', 'zz-demo-nfm-a@example.invalid', 'supplier', s_a, x, 'New job request on QuotesDone', 'ZZ DEMO', 'sent', 'whatsapp', 'read'
    from unnest(array[i1, i2, i3, i5]) x;
  insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, subject, body, status, channel, provider_status)
  values ('new_inquiry', 'zz-demo-nfm-b@example.invalid', 'supplier', s_b, i2, 'New job request on QuotesDone', 'ZZ DEMO', 'sent', 'email', 'undelivered'),
         ('new_inquiry', 'zz-demo-nfm-b@example.invalid', 'supplier', s_b, i3, 'New job request on QuotesDone', 'ZZ DEMO', 'sent', 'email', 'delivered');

  -- 1 + 2: ending i1, i2 -> s_a struck twice (warned at 2), s_b never
  update public.inquiries set status = 'expired' where id in (i1, i2);
  -- the stop needs the warning to have reached him: first i3 ends while the warning is undelivered (held at 2), then it is delivered
  update public.inquiries set status = 'expired' where id = i3;
  if coalesce((select chat_strikes from public.leads where id = s_a), 0) <> 2
     or not exists (select 1 from public.supplier_strike_event where lead_id = s_a and inquiry_id = i3 and kind = 'not_counted' and detail->>'why' = 'warning_not_delivered') then
    fails := fails || ' 2:stopped_before_warning_delivered'; end if;
  update public.notifications set provider_status = 'delivered' where type = 'supplier_strike_warning' and lead_id = s_a;
  select public.fn_sales_engineer_counts_unanswered_request(i3, now()) into n;   -- the next request that ends, once the warning reached him
  select * into l from public.leads where id = s_a;
  if coalesce(l.chat_strikes, 0) <> 3 then fails := fails || ' 1:a_strikes(' || coalesce(l.chat_strikes, 0) || ')'; end if;
  if coalesce((select chat_strikes from public.leads where id = s_b), 0) <> 1 then fails := fails || ' 1:b_struck'; end if;   -- i3 was delivered: it counts
  select count(*) into n from public.supplier_strike_event where lead_id = s_b and kind = 'not_counted';
  if n <> 2 then fails := fails || ' 1:b_not_counted(' || n || ')'; end if;
  if not exists (select 1 from public.supplier_strike_event where lead_id = s_b and inquiry_id = i2 and detail #>> '{delivery,why}' = 'not_delivered')
     or not exists (select 1 from public.supplier_strike_event where lead_id = s_b and inquiry_id = i3 and kind = 'strike' and detail #>> '{delivery,why}' = 'delivered_not_seen')
     or not exists (select 1 from public.supplier_strike_event where lead_id = s_b and inquiry_id = i1 and detail #>> '{delivery,why}' = 'never_sent') then
    fails := fails || ' 1:b_facts'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_strike_warning' and lead_id = s_a and body ~ 'Not for me' and body ~ 'available') then
    fails := fails || ' 2:no_warning'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_strike_stopped' and lead_id = s_a and body ~ 'paused') then
    fails := fails || ' 2:no_stop_notice'; end if;
  if public.fn_is_matchable(true, l.banned, l.matching_blocked, 'approved', l.permanently_closed, l.chat_strikes) then fails := fails || ' 2:not_paused'; end if;

  -- 2: declining i1 (already struck) withdraws that strike; declining i4 before it ends means it never strikes
  j := public.fn_supplier_declines_request(s_a, i1, 'We do not do water heaters, only bathroom tiling', 'whatsapp');
  if not (j->>'ok')::boolean or not (j->>'strike_withdrawn')::boolean or (j->>'strikes')::int <> 2 then fails := fails || ' 2:withdraw ' || j::text; end if;
  if not (j->>'trade_is_his')::boolean or not (j->>'can_remove_trade')::boolean then fails := fails || ' 2:trade_offer'; end if;
  if (select decline_reason from public.inquiry_matches where inquiry_id = i1 and supplier_id = s_a) !~ 'tiling' then fails := fails || ' 2:reason'; end if;
  perform public.fn_supplier_declines_request(s_a, i4, null, 'portal');
  update public.inquiries set status = 'expired' where id = i4;
  if coalesce((select chat_strikes from public.leads where id = s_a), 0) <> 2 then fails := fails || ' 2:declined_struck'; end if;

  -- 3: a quote first, then "not for me" is refused; "I'm available" clears and sets available
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at) values (gen_random_uuid(), i6, s_a, 9000, 'submitted', now());
  if (public.fn_supplier_declines_request(s_a, i6, 'x', 'portal'))->>'code' <> 'already_quoted' then fails := fails || ' 3:quoted_decline'; end if;
  update public.leads set chat_strikes = 2 where id = s_a;
  perform public.fn_supplier_set_availability(s_a, 'paused', null, 'probe');
  j := public.fn_supplier_says_available(s_a, 'email');
  if (j->>'cleared_from')::int <> 2 or coalesce((select chat_strikes from public.leads where id = s_a), 0) <> 0
     or j #>> '{availability,state}' <> 'available' then fails := fails || ' 3:available ' || j::text; end if;

  -- 4: corrections
  if (public.fn_supplier_trade_correction_propose(s_b, 'email', array['plumbing'], '{}', 'stop plumbing'))->>'code' <> 'last_trade' then fails := fails || ' 4:last_trade'; end if;
  perform public.fn_supplier_trade_correction_propose(s_a, 'not_for_me', array['plumbing'], '{}', 'first', i1);
  j := public.fn_supplier_trade_correction_propose(s_a, 'whatsapp', array['plumbing', 'electrical'], '{}', 'stop sending me plumbing jobs');
  v_corr := (j #>> '{correction,id}')::bigint;
  select count(*) into n from public.supplier_trade_correction where supplier_id = s_a and status = 'proposed';
  if n <> 1 or (j->'correction'->'remove_trades') <> '["plumbing"]'::jsonb then fails := fails || ' 4:one_open ' || j::text; end if;
  if not ((public.fn_supplier_trade_correction_decide(v_corr, s_a, 'applied', 'whatsapp', '{}'))->>'ok')::boolean
     or ((public.fn_supplier_trade_correction_decide(v_corr, s_a, 'declined', 'whatsapp', '{}'))->>'ok')::boolean then fails := fails || ' 4:decide_once'; end if;

  -- 5: contact details removed: counted, told once; a brand alone is not one
  -- i3 and i4 ended above; an ended request takes no quotation (trigger a06, 19 Nov 2026,
  -- no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.sql), so they are reopened for these drafts.
  update public.inquiries set status = 'sent' where id in (i3, i4);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, masked_terms, created_at)
  values (gen_random_uuid(), i5, s_b, 7000, 'draft', '["Grohe", "Acme Tiles LLC"]'::jsonb, now());
  if exists (select 1 from public.supplier_contact_removal_notice where lead_id = s_b) then fails := fails || ' 5:brand_told'; end if;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, masked_terms, created_at)
  values (gen_random_uuid(), i4, s_b, 7000, 'draft', '["050 123 4567", "sales@acme-tiles.ae", "Grohe"]'::jsonb, now()),
         (gen_random_uuid(), i3, s_b, 7100, 'draft', '["www.acme-tiles.ae"]'::jsonb, now());
  if (public.fn_supplier_contact_removals(s_b))->>'terms' <> '3' then fails := fails || ' 5:count ' || (public.fn_supplier_contact_removals(s_b))::text; end if;
  select count(*) into n from public.notifications where type = 'supplier_contact_removed' and lead_id = s_b and body ~ 'clause 10';
  if n <> 1 then fails := fails || ' 5:told(' || n || ')'; end if;

  -- 6: the reveal standing
  -- complete terms, so the quality gate lets the honest quotes out (its other checks are not what this measures)
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, status, validity, lead_time, vat_treatment, created_at)
  values (q1, ip, s_a, 47250, 45000, 'submitted', '30 days', '10 days', 'exclusive', now()),
         (q2, ip, s_c, 48300, 46000, 'submitted', '30 days', '10 days', 'exclusive', now());
  if (select count(*) from public.quotes where id in (q1, q2) and status = 'submitted') <> 2 then fails := fails || ' 6:honest_quotes_held'; end if;
  perform public.fn_supplier_set_availability(s_a, 'busy', v_today + 10, 'probe');
  j := public.fn_reveal_standing(q1);
  if j->>'outcome' <> 'away' or (j->>'back_on')::date <> v_today + 10 then fails := fails || ' 6:away ' || j::text; end if;
  perform public.fn_supplier_set_availability(s_a, 'available', null, 'probe');
  update public.leads set license_expiry = v_today - 1 where id = s_c;
  if (public.fn_reveal_standing(q2))->>'why' <> 'licence_expired' then fails := fails || ' 6:licence'; end if;
  update public.leads set license_expiry = v_today + 200, approval_status = 'pending' where id = s_c;
  if (public.fn_reveal_standing(q2))->>'why' <> 'not_approved' then fails := fails || ' 6:approval'; end if;
  update public.leads set approval_status = 'approved', verified = true, permanently_closed = true where id = s_c;
  if (public.fn_reveal_standing(q2))->>'outcome' <> 'not_revealable' then fails := fails || ' 6:closed'; end if;
  update public.leads set permanently_closed = false where id = s_c;
  if (public.fn_reveal_standing(q1))->>'outcome' <> 'proceed' then fails := fails || ' 6:proceed ' || (public.fn_reveal_standing(q1))::text; end if;

  -- 7: the peers
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, status, validity, lead_time, vat_treatment, created_at)
  values (q3, ip, s_q, 472500, 450000, 'submitted', '30 days', '10 days', 'exclusive', now());
  -- the existing hold path took it: held as a draft, with the peer flag
  if not exists (select 1 from public.quote_quality_hold h, jsonb_array_elements(h.flags) f
                  where h.quote_id = q3 and h.released_at is null and f->>'code' = 'price_far_from_peers')
     or (select status from public.quotes where id = q3) <> 'draft' then fails := fails || ' 7:not_held_on_submission'; end if;
  if public.fn_quote_peer_price_flag((select q from public.quotes q where id = q3)) is null then fails := fails || ' 7:outlier_missed'; end if;
  if public.fn_quote_peer_price_flag((select q from public.quotes q where id = q1)) is not null
     or public.fn_quote_peer_price_flag((select q from public.quotes q where id = q2)) is not null then fails := fails || ' 7:honest_flagged'; end if;
  if not exists (select 1 from jsonb_array_elements(public.fn_quote_quality_flags((select q from public.quotes q where id = q3))) f
                  where f->>'code' = 'price_far_from_peers') then fails := fails || ' 7:not_in_quality_flags'; end if;
  if public.fn_quote_quality_fixes_en(public.fn_quote_quality_flags((select q from public.quotes q where id = q3))) ~ '45,000|46,000|above|below|higher|lower'
     or public.fn_quote_quality_fixes_en(public.fn_quote_quality_flags((select q from public.quotes q where id = q3))) !~ '450,000.00' then
    fails := fails || ' 7:fix_line'; end if;
  j := public.fn_reveal_standing(q3);
  if j->>'outcome' <> 'figure_unconfirmed' then fails := fails || ' 7:reveal_not_held ' || j::text; end if;
  perform public.fn_reveal_standing(q3);
  select count(*) into n from public.notifications where type = 'quote_figure_confirm' and quote_id = q3;
  if n <> 1 then fails := fails || ' 7:asked(' || n || ')'; end if;
  j := public.fn_supplier_confirms_quote_figure(s_q, q3, 'portal');
  if not (j->>'ok')::boolean or (j->>'still_flagged')::boolean or (public.fn_reveal_standing(q3))->>'outcome' <> 'proceed' then fails := fails || ' 7:confirm ' || j::text; end if;
  if ((public.fn_supplier_confirms_quote_figure(s_a, q3, 'portal'))->>'ok')::boolean then fails := fails || ' 7:someone_elses_quote'; end if;

  -- 8: the weekly decline review and its decision (fixture run: only demo rows)
  perform set_config('qd.duty_fixtures', 'on', true);
  j := public.fn_sales_engineer_decline_review();
  if (j->>'reasoning_filed')::int < 1 then fails := fails || ' 8:not_filed ' || j::text; end if;
  select id into v_held from public.reasoning_held_question where dedupe_key like 'trade_correction:' || s_a || ':%' order by id desc limit 1;
  if v_held is null then fails := fails || ' 8:no_held_row';
  else
    if not exists (select 1 from public.reasoning_held_question h, jsonb_array_elements(h.request #> '{decision,options}') o
                    where h.id = v_held and o->>'id' = 'remove_trade:plumbing') then fails := fails || ' 8:no_trade_option'; end if;
    j := public.fn_reason_apply_sales_engineer__trade_correction(v_held, jsonb_build_object('decision', jsonb_build_object('choice', 'remove_trade:plumbing'), 'answer', 'He tiles; water heaters reached him through tiling.'));
    if not (j->>'changed')::boolean then fails := fails || ' 8:apply ' || j::text; end if;
    if not exists (select 1 from public.supplier_trade_correction where supplier_id = s_a and status = 'proposed' and source = 'weekly_review' and remove_trades = array['plumbing']) then
      fails := fails || ' 8:no_proposal'; end if;
    if not exists (select 1 from public.notifications where type = 'supplier_trade_correction' and lead_id = s_a and body ~ 'confirm') then fails := fails || ' 8:not_asked'; end if;
    begin
      perform public.fn_reason_apply_sales_engineer__trade_correction(v_held, jsonb_build_object('decision', jsonb_build_object('choice', 'drop him')));
      fails := fails || ' 8:bad_choice_applied';
    exception when others then null;
    end;
  end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: read requests strike and unread/bounced/unsent do not; warned at 2, told at the stop; a decline withdraws its strike and never strikes; quoted decline refused; available clears; last trade kept, one open correction decided once; contact removals counted and told once; reveal away/licence/approval/closed/proceed; only the 450,000 is far from its peers, named by its own total, held at the reveal and cleared by his confirmation; the weekly review files and its removal becomes a proposal he is asked to confirm>>';
end $probe$;

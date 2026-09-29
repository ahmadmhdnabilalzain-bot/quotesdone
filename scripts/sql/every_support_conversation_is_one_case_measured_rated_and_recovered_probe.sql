-- PROBE: EVERY SUPPORT CONVERSATION IS ONE CASE, MEASURED, RATED AND RECOVERED. Assigned: customer_support.
--
-- Pure probe: no DDL, never applied. Run it through node scripts/qsql.mjs AFTER
-- every_support_conversation_is_one_case_measured_rated_and_recovered.sql is live. Before merge it was run
-- as that file followed by this one in ONE transaction that the final raise rolls back, so the build was
-- proved without being applied.
--
-- Everything happens inside a block that always raises, so nothing survives: the party is a ZZ DEMO
-- customer on zz.demo.support.probe@example.invalid and the reserved demo handset +971 50 000 0077
-- (fn_is_demo_phone), created inside the block. pg_net sends only committed rows, so no message can leave.
--
-- VERDICT (in the error text): CHK<<PROBE OK ...>> only if
--   1. a WhatsApp message and our sent reply open ONE case with a first-reply time;
--   2. an email, a signed-in widget chat and a customer-portal assistant chat land on that SAME case and the
--      same single profile, across four channels, as one contact;
--   3. closing records the resolution, FCR = true, and queues ONE CSAT question (on email, as the widget was
--      the last channel; fn_wa_fanout adds its usual WhatsApp twin);
--   4. a message naming the closed case reopens it (reopen_count 1) and FCR becomes false on the next close;
--   5. the reply "٢ ٣" records CSAT 2 and CES 3 against the case, and the low CSAT opens a
--      service_recovery case linked to it;
--   5b. a supplier-portal chat opens a 'portal' case; the portal rating door records its rating and refuses
--      another account's case;
--   6. the founder's WhatsApp and an anonymous widget visitor open nothing;
--   7. no support_case, profile or feedback row outside the probe's own profile was touched.
do $probe$
declare
  v_cust uuid; v_ref text; v_case public.support_case; v_rec public.support_case; v_sup public.support_case; v_prof bigint; v_mail bigint;
  v_other_before bigint; v_other_after bigint; v_n int; v_r jsonb := '{}'::jsonb; v_fail text := '';
begin
  select count(*) into v_other_before from public.support_case;

  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt, email_verified)
  values ('ZZ DEMO support probe', 'zz.demo.support.probe@example.invalid', '+971500000077', true, 'same', true)
  returning id into v_cust;

  -- 1. WhatsApp: the customer writes, we answer.
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, sent, meta)
  values ('whatsapp:+971500000077', 'whatsapp:+971000000000', 'My quotation has not arrived', 'We are checking now', 'en', true, '{"audience":"customer"}');
  select * into v_case from public.support_case where party_id = v_cust::text;
  if v_case.case_id is null then v_fail := v_fail || ' no case from WhatsApp;'; end if;
  if v_case.first_reply_at is null or v_case.state <> 'waiting_customer' then v_fail := v_fail || ' WhatsApp reply not stamped;'; end if;
  v_ref := v_case.case_ref; v_prof := v_case.customer_profile_id;

  -- 2. Email (resend_inbound inserts, email_triage triages, a reply is sent), then the signed-in widget.
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review)
  values ('ZZ Demo <zz.demo.support.probe@example.invalid>', 'support@mail.quotesdone.com', 'Still no quotation', 'Any news?', true)
  returning id into v_mail;
  update public.inbound_messages set triaged_at = now(), ai_category = 'question' where id = v_mail;
  update public.inbound_messages set replied_at = now(), replied_by = 'customer_support' where id = v_mail;
  -- the ChatWidget on the public site (site_assistant, verified session) ...
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('where is my quote', 'It is on its way', 'customer:' || v_cust, '/en/how-it-works', true, 'customer_support');
  -- ... and the customer portal assistant (sales_engineer 'assist' logs path 'portal').
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('can I change the delivery date', 'Yes, from the request page', 'customer:' || v_cust, 'portal', true, 'sales_engineer');

  select count(*) into v_n from public.support_case where customer_profile_id = v_prof;
  select * into v_case from public.support_case where case_ref = v_ref;
  v_r := v_r || jsonb_build_object('cases_after_4_channels', v_n, 'channels', v_case.channels, 'inbound', v_case.inbound_count,
                                   'outbound', v_case.outbound_count, 'contacts', v_case.contact_count,
                                   'first_reply_seconds', v_case.first_reply_seconds);
  if v_n <> 1 then v_fail := v_fail || ' channels split into ' || v_n || ' cases;'; end if;
  if not v_case.channels @> array['whatsapp', 'email', 'widget', 'portal'] then v_fail := v_fail || ' channels not all on the case;'; end if;
  if v_case.inbound_count <> 4 or v_case.outbound_count <> 4 or v_case.contact_count <> 1 then v_fail := v_fail || ' counts wrong;'; end if;
  select count(*) into v_n from public.support_customer_profile
   where customer_id = v_cust or email = 'zz.demo.support.probe@example.invalid' or phone_tail = '500000077';
  if v_n <> 1 then v_fail := v_fail || ' ' || v_n || ' profiles, not one;'; end if;

  -- 3. Close.
  perform public.fn_support_case_close(v_ref, 'quotation resent', 'probe');
  select * into v_case from public.support_case where case_ref = v_ref;
  -- The last channel was the widget, so the question goes by email; fn_wa_fanout then adds the estate's usual
  -- WhatsApp twin (measured 28 Sep: one email row + one whatsapp twin, both suppressed as demo). ONE email ask.
  select count(*) into v_n from public.notifications
   where type = 'support_csat_request' and channel = 'email' and body like '%' || v_ref || '%';
  v_r := v_r || jsonb_build_object('fcr_first_close', v_case.fcr, 'resolution', v_case.resolution,
                                   'csat_requested', v_case.csat_requested_at is not null, 'csat_error', v_case.csat_request_error,
                                   'csat_notifications', v_n);
  if v_case.fcr is distinct from true or v_case.resolution is null or v_case.resolved_at is null then v_fail := v_fail || ' close not recorded;'; end if;
  if v_case.csat_requested_at is null or v_n <> 1 then v_fail := v_fail || ' CSAT not asked once;'; end if;

  -- 4. Reopen by naming the case.
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, sent, meta)
  values ('whatsapp:+971500000077', 'whatsapp:+971000000000', 'Case ' || v_ref || ' is not solved', null, 'en', false, '{"audience":"customer"}');
  select * into v_case from public.support_case where case_ref = v_ref;
  if v_case.state = 'closed' or v_case.reopen_count <> 1 then v_fail := v_fail || ' not reopened;'; end if;
  perform public.fn_support_case_close(v_ref, 'quotation resent again', 'probe');
  select * into v_case from public.support_case where case_ref = v_ref;
  v_r := v_r || jsonb_build_object('reopen_count', v_case.reopen_count, 'fcr_after_reopen', v_case.fcr);
  if v_case.fcr is distinct from false then v_fail := v_fail || ' FCR true after a reopen;'; end if;

  -- 5. The rating, in Arabic digits, and the service-recovery case it opens.
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, sent, meta)
  values ('whatsapp:+971500000077', 'whatsapp:+971000000000', '٢ ٣', null, 'ar', false, '{"audience":"customer"}');
  select count(*) into v_n from public.feedback where case_id = v_case.case_id
     and ((kind = 'csat' and rating = 2) or (kind = 'ces' and rating = 3));
  select * into v_rec from public.support_case where recovery_of_case_id = v_case.case_id;
  v_r := v_r || jsonb_build_object('feedback_rows', v_n, 'recovery_case', v_rec.case_ref, 'recovery_kind', v_rec.case_kind,
                                   'complaint_event', (select count(*) from public.company_event e
                                                        where e.event_type = 'customer.complaint' and e.entity_type = 'feedback'
                                                          and e.entity_id in (select id::text from public.feedback where case_id = v_case.case_id)));
  if v_n <> 2 then v_fail := v_fail || ' CSAT/CES not recorded;'; end if;
  if v_rec.case_id is null or v_rec.case_kind <> 'service_recovery' or v_rec.state <> 'open' then v_fail := v_fail || ' no service-recovery case;'; end if;

  -- 5b. The supplier portal: ZZ DEMO supplier 126512 (leads.is_demo, @example.invalid) asks through the
  --     ChatWidget on an Arabic supplier-portal page, the case is closed, and the portal rating door
  --     (fn_support_portal_rate, behind action 'support_rating') records it — and refuses the customer.
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('كيف أعدّل خدماتي', 'من صفحة الخدمات', 'supplier:126512', '/ar/supplier/services', true, 'customer_support');
  select * into v_sup from public.support_case where party_kind = 'supplier' and party_id = '126512' and state <> 'closed';
  if v_sup.case_id is null or v_sup.channel <> 'portal' then v_fail := v_fail || ' supplier portal chat opened no portal case;'; end if;
  perform public.fn_support_case_close(v_sup.case_ref, 'services page explained', 'probe');
  -- the portal's rating control asks fn_support_rating_due (supplier_api 'support_rating_due') what to show
  v_r := v_r || jsonb_build_object('rating_due_before', public.fn_support_rating_due('supplier', '126512') -> 0 ->> 'case_ref');
  if v_r ->> 'rating_due_before' is distinct from v_sup.case_ref then v_fail := v_fail || ' the portal is not shown the rating due;'; end if;
  v_r := v_r || jsonb_build_object('supplier_portal_case', v_sup.case_ref, 'supplier_channel', v_sup.channel,
    'customer_rates_supplier_case', public.fn_support_portal_rate('customer', v_cust::text, v_sup.case_ref, 5, null, null) -> 'ok',
    'supplier_portal_rating', public.fn_support_portal_rate('supplier', '126512', v_sup.case_ref, 5, 7, 'clear') -> 'ok');
  -- read in its own statement: a subquery in the statement that wrote the rows cannot see them
  v_r := v_r || jsonb_build_object('supplier_feedback_rows',
    (select count(*) from public.feedback where case_id = v_sup.case_id and channel = 'portal'),
    'rating_due_after', jsonb_array_length(public.fn_support_rating_due('supplier', '126512')));
  if (v_r ->> 'rating_due_after')::int <> 0 then v_fail := v_fail || ' a rated case is still shown as due;'; end if;
  if (v_r ->> 'customer_rates_supplier_case')::boolean then v_fail := v_fail || ' a customer rated a supplier''s case;'; end if;
  if not (v_r ->> 'supplier_portal_rating')::boolean or (v_r ->> 'supplier_feedback_rows')::int <> 2 then
    v_fail := v_fail || ' portal rating not recorded;'; end if;

  -- 6. The founder and an anonymous visitor open nothing.
  select count(*) into v_n from public.support_case;
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, sent, meta)
  values ('whatsapp:+971500000078', 'whatsapp:+971000000000', 'figures', 'here', true, '{"audience":"founder"}');
  insert into public.assistant_logs (message, reply, audience, answered) values ('hello', 'hi', 'unknown', true);
  if (select count(*) from public.support_case) <> v_n then v_fail := v_fail || ' founder or anonymous opened a case;'; end if;

  -- the read models answer
  v_r := v_r || jsonb_build_object(
    'profile_view', (select to_jsonb(p) - 'email' - 'phone_tail' from public.v_support_customer_profile p where p.profile_id = v_prof),
    'metrics_rows', (select count(*) from public.v_support_case_metrics));

  -- 7. Nothing outside the probe's profile.
  select count(*) into v_other_after from public.support_case where customer_profile_id is distinct from v_prof and case_id is distinct from v_sup.case_id;
  if v_other_after <> v_other_before then v_fail := v_fail || ' touched other cases (' || v_other_before || '->' || v_other_after || ');'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK %>>', v_r;
  else
    raise exception 'CHK<<PROBE FAILED:% %>>', v_fail, v_r;
  end if;
end $probe$;

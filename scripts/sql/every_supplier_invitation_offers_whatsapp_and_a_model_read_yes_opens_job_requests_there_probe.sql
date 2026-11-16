-- PROBE: EVERY SUPPLIER INVITATION OFFERS WHATSAPP, A MODEL READS THE YES, THE NUMBER CONFIRMS ITSELF, AND ONLY THEN DO JOB
-- REQUESTS GO THERE. Seat: marketing (with sales_engineer). Agent: L2_OPTIN, 16 Nov 2026. Pure probe: no DDL, never applied; run
-- after every_supplier_invitation_offers_whatsapp_and_a_model_read_yes_opens_job_requests_there.sql on a LOCAL Postgres 16. It
-- always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid with a +97150000 07xx number;
-- no real row is read or written.
-- PROBE OK only if
--   1. the rule: a consent reply counts only when the message answered carried the offer or the consent question AND a model
--      read the answer as a yes; the same words with no model reading, or answering a mail that asked nothing, do not count;
--      the table refuses a direct insert the rule does not count;
--   2. a yes by e-mail from an address none of our mails offered WhatsApp to records nothing;
--   3. a model-read yes ("yes put me on WhatsApp") to a mail that carried the offer records a PENDING consent and an 8-digit
--      code; until the code comes from his WhatsApp the gate names no number, a job request makes no WhatsApp twin, and a job
--      request written straight to WhatsApp is skipped with the reason;
--   4. a wrong code is counted, five misses stop the number for the day; the right code from his WhatsApp records the consent
--      (source, question, answer, model, time) on THAT number, confirmed; a number that already names another party is refused;
--   5. then a job request is twinned to that number and a direct WhatsApp job request is addressed to it;
--   6. a supplier with a mobile on record and no consent is never messaged on WhatsApp for a job request;
--   7. STOP (whatsapp_opt 'none') closes the gate again; a supplier who chose WhatsApp in the portal still gets job requests there;
--   8. the reply state: offer / pending / consented / declined.
-- FIX ROUND (independent review REVIEW_L2, 16 Nov 2026), each reproduced LOCAL on the previous head first:
--   9. the "Set up my page" button records its opt-in but opens NO job requests on WhatsApp (no model read a yes to them);
--  10. one model-read yes from a number two companies share opens the gate for neither;
--  11. STOP cancels a WhatsApp job request already queued for that supplier;
--  12. the unconfirmed row the sales engineer's writer leaves opens nothing until the code comes from the number;
--  13. a model-read NO by e-mail is recorded, closes his waiting code, and the reply state is 'declined' (no offer again);
--      a no with no model reading records nothing;
--  14. the rule runs as service_role (fn_wa_job_request_offer is granted to it: the opt-in trigger is not security definer).
do $probe$
declare
  fails text := ''; a bigint; b bigint; p bigint; j jsonb; n int; v_code text; v_in bigint; v_in2 bigint;
  k_btn bigint; k_s1 bigint; k_s2 bigint; k_d bigint; k_r bigint; k_n bigint; v_in3 bigint;
  v_offer text := public.fn_wa_job_request_offer(); v_q text := public.fn_wa_consent_question();
  ea text := 'zz-demo-l2optin-a@example.invalid'; eb text := 'zz-demo-l2optin-b@example.invalid'; ep text := 'zz-demo-l2optin-p@example.invalid';
  wa_a text := '+971500000771';
begin
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin A', ea, 'Dubai', '+971500000770', '+971500000770', now() - interval '2 days') returning id into a;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, phone_e164, invited_at, owner_phone_verified)
  values ('ZZ DEMO L2 Optin B', eb, eb, 'Dubai', '+971500000772', '+971500000772', now() - interval '2 days', false) returning id into b;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, phone_e164, owner_phone_verified, whatsapp_opt, whatsapp_asked_at)
  values ('ZZ DEMO L2 Optin Portal', ep, ep, 'Dubai', '+971500000773', '+971500000773', true, 'same', now() - interval '1 day') returning id into p;
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin W', 'zz-demo-l2optin-w@example.invalid', 'Dubai', '+971500000774', '+971500000774', now() - interval '2 days');

  -- 1. the rule
  if (public.fn_wa_optin_counts('email_consent_reply', null, 'Hello. ' || v_offer, 'yes put me on WhatsApp', 'stub-model')->>'counts')::boolean is not true then fails := fails || ' 1:model_yes'; end if;
  if (public.fn_wa_optin_counts('email_consent_reply', null, 'Hello. ' || v_offer, 'yes put me on WhatsApp', null)->>'counts')::boolean then fails := fails || ' 1:keyword_counted'; end if;
  if (public.fn_wa_optin_counts('email_consent_reply', null, 'Which trades do you cover?', 'yes', 'stub-model')->>'counts')::boolean then fails := fails || ' 1:not_asked'; end if;
  if (public.fn_wa_optin_counts('wa_consent_reply', null, v_q, 'yes', 'stub-model')->>'counts')::boolean is not true then fails := fails || ' 1:consent_question'; end if;
  if (public.fn_wa_optin_rule('wa_button', 'supplier_invite_yes', null, null)->>'counts')::boolean is not true then fails := fails || ' 1:button'; end if;
  if (public.fn_wa_optin_rule('wa_consent_reply', null, v_q, 'yes')->>'counts')::boolean then fails := fails || ' 1:old_name_keyword_yes'; end if;
  -- on WhatsApp: a reply to the consent question counts only once the model read it as a yes (fn_supplier_whatsapp_consent_read)
  perform public.fn_supplier_whatsapp_consent_ask_record('whatsapp:+971500000774', 'Thanks. ' || v_q, 'sales_engineer');
  begin
    perform public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000774', 'Yes please', null);
  exception when others then fails := fails || ' 1:wa_yes_without_model_errored(' || sqlerrm || ')';
  end;
  if exists (select 1 from public.supplier_whatsapp_optin where phone = '+971500000774') then fails := fails || ' 1:wa_yes_without_model'; end if;
  perform public.fn_supplier_whatsapp_consent_ask_record('whatsapp:+971500000774', 'Thanks. ' || v_q, 'sales_engineer');
  if not coalesce((public.fn_supplier_whatsapp_consent_read('whatsapp:+971500000774', 'stub-model')->>'ok')::boolean, false) then fails := fails || ' 1:consent_read'; end if;
  perform public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000774', 'yes put me on WhatsApp', null);
  if not exists (select 1 from public.supplier_whatsapp_optin where phone = '+971500000774' and source = 'wa_consent_reply' and answer_read_by = 'stub-model'
                  and phone_confirmed_at is not null) then fails := fails || ' 1:wa_model_yes_not_recorded'; end if;
  begin
    insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, evidence)
    values (a, wa_a, 'email_consent_reply', v_offer, 'yes', 'ZZ DEMO direct insert with no model');
    fails := fails || ' 1:direct_insert_accepted';
  exception when check_violation then null;
  end;

  -- 2. a yes to nothing we asked
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
  values ('ZZ DEMO A <' || ea || '>', 'supplier@quotesdone.com', 'Re: a question', 'yes put me on WhatsApp', now()) returning id into v_in;
  j := public.fn_supplier_whatsapp_optin_from_mail(v_in, 'yes put me on WhatsApp', 'stub-model');
  if j->>'code' <> 'not_offered' then fails := fails || ' 2:recorded_without_offer(' || j::text || ')'; end if;
  if exists (select 1 from public.supplier_whatsapp_optin_pending where lead_id = a) then fails := fails || ' 2:pending_row'; end if;

  -- 3. our reply carried the offer; his model-read yes is pending until the number confirms
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, sent_at, created_at)
  values ('inbound_reply', ea, 'supplier', a, 'Re: a question', 'Thank you for your reply.' || E'\n\n' || v_offer, 'email', 'sent', now() - interval '1 hour', now() - interval '1 hour');
  update public.notifications set status = 'sent', sent_at = now() - interval '1 hour' where to_email = ea and type = 'inbound_reply';
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
  values (ea, 'supplier@quotesdone.com', 'Re: a question', 'yes put me on WhatsApp', now()) returning id into v_in2;
  begin
    j := public.fn_supplier_whatsapp_optin_from_mail(v_in2, 'yes put me on WhatsApp', null);
    if j->>'code' <> 'rule' then fails := fails || ' 3:no_model_recorded(' || j::text || ')'; end if;
  exception when others then fails := fails || ' 3:no_model_errored(' || sqlerrm || ')';
  end;
  j := public.fn_supplier_whatsapp_optin_from_mail(v_in2, 'yes put me on WhatsApp', 'stub-model');
  v_code := j->>'code_to_send';
  if j->>'code' <> 'pending' or coalesce(v_code, '') !~ '^[0-9]{8}$' then fails := fails || ' 3:pending(' || j::text || ')'; end if;
  if exists (select 1 from public.supplier_whatsapp_optin_pending where lead_id = a and code_sha = v_code) then fails := fails || ' 3:code_kept_in_clear'; end if;
  if public.fn_supplier_whatsapp_offer_state(ea)->>'state' <> 'pending' then fails := fails || ' 3:state_pending'; end if;
  if public.fn_supplier_job_request_whatsapp(a)->>'to' is not null then fails := fails || ' 3:gate_open_before_code'; end if;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
  values ('rfq_invite', ea, 'supplier', a, 'ZZ DEMO job request', 'ZZ DEMO a job in your trade', 'email', 'queued');
  if exists (select 1 from public.notifications where lead_id = a and channel = 'whatsapp' and status <> 'skipped') then fails := fails || ' 3:twin_before_code'; end if;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, to_phone)
  values ('rfq_addendum', ea, 'supplier', a, 'ZZ DEMO addendum', 'ZZ DEMO an addendum', 'whatsapp', 'queued', '+971500000770');
  if not exists (select 1 from public.notifications where lead_id = a and channel = 'whatsapp' and type = 'rfq_addendum' and status = 'skipped'
                  and last_error ~ 'has not agreed') then fails := fails || ' 3:direct_row_not_skipped'; end if;

  -- 4. the code from his WhatsApp
  j := public.fn_supplier_whatsapp_optin_confirm('+971500000779', '00000000');
  if j->>'code' <> 'no_pending_code' or not exists (select 1 from public.supplier_whatsapp_optin_code_miss where phone = '+971500000779') then fails := fails || ' 4:miss_not_counted'; end if;
  insert into public.supplier_whatsapp_optin_code_miss (phone) select '+971500000779' from generate_series(1, 4);
  if public.fn_supplier_whatsapp_optin_confirm('+971500000779', v_code)->>'code' <> 'too_many_tries' then fails := fails || ' 4:no_brake'; end if;
  if public.fn_supplier_whatsapp_optin_confirm('+971500000773', v_code)->>'code' <> 'number_belongs_to_another' then fails := fails || ' 4:joined_two_parties'; end if;
  -- the refusal above closed that code: a fresh yes issues a new one
  j := public.fn_supplier_whatsapp_optin_from_mail(v_in2, 'yes put me on WhatsApp', 'stub-model'); v_code := j->>'code_to_send';
  j := public.fn_supplier_whatsapp_optin_confirm('whatsapp:' || wa_a, v_code);
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 4:confirm(' || j::text || ')'; end if;
  if not exists (select 1 from public.supplier_whatsapp_optin o where o.lead_id = a and o.phone = wa_a and o.source = 'email_consent_reply'
                  and o.consent_question = v_offer and o.consent_answer = 'yes put me on WhatsApp' and o.answer_read_by = 'stub-model'
                  and o.opted_in_at is not null and o.phone_confirmed_at is not null) then fails := fails || ' 4:consent_not_recorded'; end if;
  if public.fn_supplier_whatsapp_optin_confirm(wa_a, v_code)->>'code' <> 'no_pending_code' then fails := fails || ' 4:code_reused'; end if;

  -- 5. now the gate opens on that number
  j := public.fn_supplier_job_request_whatsapp(a);
  if j->>'to' is distinct from wa_a or j->>'source' <> 'email_consent_reply' then fails := fails || ' 5:gate(' || j::text || ')'; end if;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
  values ('rfq_invite', ea, 'supplier', a, 'ZZ DEMO job request 2', 'ZZ DEMO another job', 'email', 'queued');
  if not exists (select 1 from public.notifications where lead_id = a and channel = 'whatsapp' and type = 'rfq_invite' and to_phone = wa_a) then fails := fails || ' 5:no_twin'; end if;
  if exists (select 1 from public.notifications where lead_id = a and channel = 'whatsapp' and to_phone = '+971500000770' and status <> 'skipped') then fails := fails || ' 5:listing_number_used'; end if;
  if public.fn_supplier_whatsapp_offer_state(ea)->>'state' <> 'consented' then fails := fails || ' 5:state_consented'; end if;

  -- 6. a mobile on record and no consent: never messaged
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
  values ('new_inquiry', eb, 'supplier', b, 'ZZ DEMO new job', 'ZZ DEMO a new job', 'email', 'queued');
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, to_phone)
  values ('rfq_invite', eb, 'supplier', b, 'ZZ DEMO job', 'ZZ DEMO job', 'whatsapp', 'queued', '+971500000772');
  if exists (select 1 from public.notifications where lead_id = b and channel = 'whatsapp' and status not in ('skipped')) then fails := fails || ' 6:messaged_without_consent'; end if;
  if public.fn_supplier_whatsapp_offer_state(eb)->>'state' <> 'offer' then fails := fails || ' 6:state_offer'; end if;

  -- 7. STOP closes it; the portal answer still opens it
  update public.leads set whatsapp_opt = 'none' where id = a;
  if public.fn_supplier_job_request_whatsapp(a)->>'to' is not null then fails := fails || ' 7:stop_ignored'; end if;
  if public.fn_supplier_whatsapp_offer_state(ea)->>'state' <> 'declined' then fails := fails || ' 7:state_declined'; end if;
  j := public.fn_supplier_job_request_whatsapp(p);
  if j->>'to' is distinct from '+971500000773' or j->>'source' <> 'portal_whatsapp_choice' then fails := fails || ' 7:portal(' || j::text || ')'; end if;

  -- 9. the button: an opt-in to the marketing invitation, not to job requests on WhatsApp
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin Btn', 'zz-demo-l2optin-btn@example.invalid', 'Dubai', '+971500000781', '+971500000781', now() - interval '2 days') returning id into k_btn;
  perform public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000781', '', 'supplier_invite_yes');
  if not exists (select 1 from public.supplier_whatsapp_optin where lead_id = k_btn and source = 'wa_button') then fails := fails || ' 9:button_not_recorded'; end if;
  if public.fn_supplier_job_request_whatsapp(k_btn)->>'to' is not null then fails := fails || ' 9:button_opened_job_requests'; end if;

  -- 10. a number two companies share
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin S1', 'zz-demo-l2optin-s1@example.invalid', 'Dubai', '+971500000782', '+971500000782', now() - interval '2 days') returning id into k_s1;
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin S2', 'zz-demo-l2optin-s2@example.invalid', 'Dubai', '+971500000782', '+971500000782', now() - interval '2 days') returning id into k_s2;
  perform public.fn_supplier_whatsapp_consent_ask_record('whatsapp:+971500000782', v_q, 'sales_engineer');
  perform public.fn_supplier_whatsapp_consent_read('whatsapp:+971500000782', 'stub-model');
  perform public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000782', 'yes', null);
  if public.fn_supplier_job_request_whatsapp(k_s1)->>'to' is not null or public.fn_supplier_job_request_whatsapp(k_s2)->>'to' is not null then
    fails := fails || ' 10:shared_number_opened'; end if;

  -- 11. STOP cancels a job request already queued on WhatsApp
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin D', 'zz-demo-l2optin-d@example.invalid', 'Dubai', '+971500000784', '+971500000784', now() - interval '2 days') returning id into k_d;
  perform public.fn_supplier_whatsapp_consent_ask_record('whatsapp:+971500000784', v_q, 'sales_engineer');
  perform public.fn_supplier_whatsapp_consent_read('whatsapp:+971500000784', 'stub-model');
  perform public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000784', 'sure, send them here', null);
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
  values ('rfq_invite', 'zz-demo-l2optin-d@example.invalid', 'supplier', k_d, 'ZZ DEMO job', 'ZZ DEMO job body', 'email', 'queued');
  -- a demo row is captured on insert; put the twin back to queued as a real one would be, past the triggers
  perform set_config('session_replication_role', 'replica', true);
  update public.notifications set status = 'queued' where lead_id = k_d and channel = 'whatsapp';
  perform set_config('session_replication_role', 'origin', true);
  if not exists (select 1 from public.notifications where lead_id = k_d and channel = 'whatsapp' and status = 'queued' and to_phone = '+971500000784') then
    fails := fails || ' 11:no_twin_to_cancel'; end if;
  perform public.fn_wa_supplier_invite_opt_out('whatsapp:+971500000784');
  if exists (select 1 from public.notifications where lead_id = k_d and channel = 'whatsapp' and status in ('queued', 'pending', 'held')) then
    fails := fails || ' 11:stop_left_it_queued'; end if;

  -- 12. the sales engineer's writer: recorded, not confirmed, opens nothing
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin R', 'zz-demo-l2optin-r@example.invalid', 'Dubai', '+971500000785', '+971500000785', now() - interval '2 days') returning id into k_r;
  j := public.fn_supplier_whatsapp_optin_record(k_r, 'call_consent_reply', v_q, 'Yes, send them on WhatsApp');
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 12:record(' || j::text || ')'; end if;
  if public.fn_supplier_job_request_whatsapp(k_r)->>'to' is not null then fails := fails || ' 12:unconfirmed_opened'; end if;

  -- 13. a model-read no by e-mail
  insert into public.leads (company_name, email, emirate, phone, phone_e164, invited_at)
  values ('ZZ DEMO L2 Optin N', 'zz-demo-l2optin-n@example.invalid', 'Dubai', '+971500000786', '+971500000786', now() - interval '2 days') returning id into k_n;
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at)
  values ('zz-demo-l2optin-n@example.invalid', 'supplier@quotesdone.com', 'Re: a question', 'No WhatsApp please, e-mail only', now()) returning id into v_in3;
  begin
    if public.fn_supplier_whatsapp_offer_state('zz-demo-l2optin-n@example.invalid')->>'state' <> 'offer' then fails := fails || ' 13:state_before'; end if;
    if coalesce((public.fn_supplier_whatsapp_offer_declined_from_mail(v_in3, 'No WhatsApp please', null)->>'ok')::boolean, false) then fails := fails || ' 13:no_without_model'; end if;
    if public.fn_supplier_whatsapp_offer_state('zz-demo-l2optin-n@example.invalid')->>'state' <> 'offer' then fails := fails || ' 13:declined_without_model'; end if;
    j := public.fn_supplier_whatsapp_offer_declined_from_mail(v_in3, 'No WhatsApp please, e-mail only', 'stub-model');
    if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 13:declined(' || j::text || ')'; end if;
    if public.fn_supplier_whatsapp_offer_state('zz-demo-l2optin-n@example.invalid')->>'state' <> 'declined' then fails := fails || ' 13:offer_shown_again'; end if;
    if (select whatsapp_opt from public.leads where id = k_n) is not null then fails := fails || ' 13:touched_whatsapp_opt'; end if;
  exception when others then fails := fails || ' 13:(' || sqlerrm || ')';
  end;

  -- 14. a row written as service_role runs the rule trigger as service_role
  begin
    set local role service_role;
    -- the rule the opt-in trigger runs (it is not security definer): it calls fn_wa_job_request_offer as the writer's role
    if (public.fn_wa_optin_counts('email_consent_reply', null, v_offer, 'yes', 'stub-model')->>'counts')::boolean is not true then fails := fails || ' 14:rule'; end if;
    reset role;
    if not has_function_privilege('service_role', 'public.fn_wa_job_request_offer()', 'execute')
       or not has_function_privilege('service_role', 'public.fn_wa_optin_counts(text, text, text, text, text)', 'execute')
       or has_function_privilege('anon', 'public.fn_wa_job_request_offer()', 'execute') then fails := fails || ' 14:acl'; end if;
  exception when others then reset role; fails := fails || ' 14:service_role(' || sqlerrm || ')';
  end;

  select count(*) into n from public.supplier_whatsapp_optin where lead_id in (a, b, p);
  if n <> 1 then fails := fails || ' 8:optin_rows(' || n || ')'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: the button, a shared number and an unconfirmed row open nothing; STOP cancels a queued job request; a model-read no is kept and ends the offer; service_role passes the rule; a yes counts only when a model read it and our mail asked; a yes to nothing records nothing; a model-read yes is pending with an 8-digit code kept as a hash; no number, no twin and a direct WhatsApp job request is skipped until the code comes from his WhatsApp; misses counted and braked; a number of another party refused; consent recorded with source, question, answer, model and time on the number that sent the code; then job requests twin to it and never to the listing number; a mobile with no consent is never messaged; STOP closes it; the portal answer still opens it>>';
end $probe$;

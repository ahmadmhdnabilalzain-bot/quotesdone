-- PROBE: A SUPPLIER COMPANY HAS MEMBERS, ASKS ON ANY CHANNEL, AND CAN LEAVE. Seats: customer_support + sales_engineer.
-- Agent: SUPPLIER_W2, 16 Nov 2026. Pure probe: no DDL, never applied; run after (or in the same rolled-back transaction as)
-- a_supplier_company_has_members_asks_on_any_channel_and_can_leave.sql on a LOCAL Postgres 16. It always raises, so every row
-- is rolled back. Every party is a ZZ DEMO fixture on @example.invalid; no real row is read or written.
-- PROBE OK only if
--   1. only the owner adds people; the owner's own address, a customer's address and another company's member are refused; the
--      invited person is an invitation until HE accepts, then acts for the company's address as an estimator;
--   2. his WhatsApp number names the company only after he sends the code from it (a wrong code is counted); the owner's number
--      still names the company; a number two parties share names nobody;
--   3. a member whose name is on a sanctions list is held (an open member hit, a CEO task) and counts only once a person decides
--      every hit is not him;
--   4. the ownership passes only with the code sent to the owner's own address; the old owner stays an estimator;
--   5. a member is removed by the owner; a job question by e-mail is one rfq_clarification row the sales engineer reads first,
--      the customer is chased once after the clock, and an unknown source is refused;
--   6. "the customer is not answering" is refused within a day of the reveal, nudges the customer once, and is kept;
--   7. the follow-up's "hired" reaches the revealed supplier, without the stars;
--   8. the customer's word is kept only for a request he revealed on; the losing supplier is listed once with ex-VAT facts and
--      the customer's word, never the winner;
--   9. only the owner closes the account; closing withdraws his live quotation, stops matching, records a deferred PDPL request
--      and writes the letter naming the law and the date; reopening restores him;
--  10. an offer to pay for leads is one demand signal a day, and the CEO's reading counts it.
do $probe$
declare
  fails text := ''; c uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); s_a bigint; s_b bigint; s_x bigint; j jsonb; n int; v_code text;
  i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid(); qa uuid := gen_random_uuid(); qb uuid := gen_random_uuid(); qa2 uuid := gen_random_uuid();
  tx uuid := gen_random_uuid(); v_run bigint; v_cq bigint; v_owner text := 'zz-demo-sw2-a@example.invalid';
  v_est text := 'zz-demo-sw2-est@example.invalid'; v_view text := 'zz-demo-sw2-view@example.invalid'; v_fu bigint;
begin
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO SW2 Customer', 'zz-demo-sw2-c@example.invalid', '+971500000880', true, true, 'demo://terms', 'en', now() - interval '60 days'),
         (c2, 'ZZ DEMO SW2 Shared Number', 'zz-demo-sw2-c2@example.invalid', '+971500000889', true, true, 'demo://terms', 'en', now() - interval '60 days');
  update public.customers set whatsapp_opt = 'same' where id = c2;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_phone_verified, owner_email_verified, whatsapp_opt)
  values ('ZZ DEMO SW2 Owner Co', v_owner, v_owner, 'Dubai', '+971500000882', true, true, 'same') returning id into s_a;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_email_verified)
  values ('ZZ DEMO SW2 Rival', 'zz-demo-sw2-b@example.invalid', 'zz-demo-sw2-b@example.invalid', 'Dubai', '+971500000883', true) returning id into s_b;
  insert into public.leads (company_name, email, claimed_by, emirate, phone, owner_email_verified)
  values ('ZZ DEMO SW2 Other Co', 'zz-demo-sw2-x@example.invalid', 'zz-demo-sw2-x@example.invalid', 'Sharjah', '+971500000884', true) returning id into s_x;

  -- 1. members
  j := public.fn_supplier_member_invite(s_a, 'zz-demo-sw2-b@example.invalid', v_est, 'estimator', 'ZZ DEMO Estimator Person', '+971500000881');
  if coalesce(j->>'code', '') <> 'owner_only' then fails := fails || ' 1:non_owner_invited'; end if;
  if coalesce(public.fn_supplier_member_invite(s_a, v_owner, v_owner, 'viewer', 'ZZ DEMO Self', null)->>'code', '') <> 'is_owner' then fails := fails || ' 1:own_address'; end if;
  if coalesce(public.fn_supplier_member_invite(s_a, v_owner, 'zz-demo-sw2-c@example.invalid', 'viewer', 'ZZ DEMO Cust', null)->>'code', '') <> 'is_customer' then fails := fails || ' 1:customer_address'; end if;
  if coalesce(public.fn_supplier_member_invite(s_a, v_owner, 'zz-demo-sw2-b@example.invalid', 'viewer', 'ZZ DEMO Rival Owner', null)->>'code', '') <> 'owns_a_company' then fails := fails || ' 1:other_owner'; end if;
  j := public.fn_supplier_member_invite(s_a, v_owner, v_est, 'estimator', 'ZZ DEMO Estimator Person', '+971500000881');
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 1:invite(' || j::text || ')'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_team_invitation' and to_email = v_est and body ~ 'Accept') then fails := fails || ' 1:no_invitation_mail'; end if;
  if coalesce(public.fn_supplier_member_invite(s_x, 'zz-demo-sw2-x@example.invalid', v_est, 'viewer', 'ZZ DEMO Estimator Person', null)->>'code', '') <> 'already_member' then fails := fails || ' 1:two_companies'; end if;
  j := public.fn_supplier_company_of(v_est);
  if j->'invitation' is null or j ? 'role' then fails := fails || ' 1:acts_before_accepting'; end if;
  j := public.fn_supplier_member_accept(v_est, null);
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 1:accept(' || j::text || ')'; end if;
  j := public.fn_supplier_company_of(v_est);
  if j->>'role' <> 'estimator' or j->>'company_email' <> v_owner or (j->>'lead_id')::bigint <> s_a then fails := fails || ' 1:resolved(' || j::text || ')'; end if;
  if public.fn_supplier_company_of(v_owner)->>'role' <> 'owner' then fails := fails || ' 1:owner_role'; end if;

  -- 2. WhatsApp: the owner's number, then the member's after his code
  if (select o.lead_id from public.fn_whatsapp_owner('+971500000882') o) is distinct from s_a then fails := fails || ' 2:owner_number'; end if;
  if exists (select 1 from public.fn_whatsapp_owner('+971500000881') o) then fails := fails || ' 2:member_before_code'; end if;
  v_code := public.fn_supplier_member_phone_code(v_est)->>'code_to_send';
  if v_code !~ '^[0-9]{6}$' then fails := fails || ' 2:no_code'; end if;
  if coalesce(public.fn_supplier_member_confirm_phone('+971500000881', case when v_code = '000000' then '111111' else '000000' end)->>'code', '') <> 'wrong_code' then fails := fails || ' 2:wrong_code_accepted'; end if;
  if coalesce(public.fn_supplier_member_confirm_phone('+971500000888', v_code)->>'code', '') <> 'no_pending_code' then fails := fails || ' 2:other_number_confirmed'; end if;
  if not coalesce((public.fn_supplier_member_confirm_phone('whatsapp:+971500000881', v_code)->>'ok')::boolean, false) then fails := fails || ' 2:right_code_refused'; end if;
  if (select o.lead_id from public.fn_whatsapp_owner('+971500000881') o) is distinct from s_a then fails := fails || ' 2:member_number'; end if;
  if public.fn_supplier_member_by_phone('+971500000881')->>'role' <> 'estimator' then fails := fails || ' 2:member_by_phone'; end if;
  -- a number a customer also holds names nobody
  update public.supplier_member set phone = '+971500000889' where email = v_est;
  if exists (select 1 from public.fn_whatsapp_owner('+971500000889') o) then fails := fails || ' 2:shared_number_selects'; end if;
  update public.supplier_member set phone = '+971500000881' where email = v_est;

  -- 3. a listed name is held until a person decides
  insert into public.screening_run (source, fetched_at) values ('ZZ DEMO list', now()) returning id into v_run;
  insert into public.screening_entry (run_id, source, entry_type, reference, name, name_norm, tokens)
  values (v_run, 'ZZ DEMO list', 'individual', 'ZZ-1', 'ZZ DEMO Listed Person', public.fn_screening_normalise('ZZ DEMO Listed Person'), public.fn_screening_tokens('ZZ DEMO Listed Person'));
  j := public.fn_supplier_member_invite(s_a, v_owner, v_view, 'viewer', 'ZZ DEMO Listed Person', null);
  if not coalesce((j->>'screening')::boolean, false) then fails := fails || ' 3:not_screened(' || j::text || ')'; end if;
  perform public.fn_supplier_member_accept(v_view, null);
  if public.fn_supplier_company_of(v_view)->'held' is null then fails := fails || ' 3:acts_while_held'; end if;
  if not exists (select 1 from public.supplier_screening_hit where lead_id = s_a and field = 'member' and status = 'open') then fails := fails || ' 3:no_open_hit'; end if;
  if not exists (select 1 from public.supplier_screening_hit h join public.supplier_member m on m.id = h.member_id
                  where h.lead_id = s_a and h.field = 'member' and m.email = v_view) then fails := fails || ' 3:hit_does_not_name_the_member'; end if;
  -- the CEO task: a ZZ DEMO task files nothing (a000_org_task_demo_files_nothing, ruling 1199), so only the hit is asserted here
  update public.supplier_screening_hit set status = 'false_positive', decided_by = 'ceo', decided_at = now() where lead_id = s_a and field = 'member';
  if public.fn_supplier_company_of(v_view)->>'role' <> 'viewer' then fails := fails || ' 3:not_cleared'; end if;

  -- 4. the ownership transfer, by the owner's code
  if coalesce(public.fn_supplier_transfer_start(s_a, v_est, v_owner)->>'code', '') <> 'owner_only' then fails := fails || ' 4:member_started'; end if;
  if coalesce(public.fn_supplier_transfer_start(s_a, v_owner, 'zz-demo-sw2-nobody@example.invalid')->>'code', '') <> 'not_an_active_member' then fails := fails || ' 4:stranger'; end if;
  j := public.fn_supplier_transfer_start(s_a, v_owner, v_est);
  if not coalesce((j->>'ok')::boolean, false) then fails := fails || ' 4:start(' || j::text || ')'; end if;
  select substring(body from 'Your code is ([0-9]{6})') into v_code from public.notifications
   where type = 'supplier_ownership_code' and to_email = v_owner order by id desc limit 1;
  if v_code is null then fails := fails || ' 4:code_not_sent_to_owner'; end if;
  if coalesce(public.fn_supplier_transfer_confirm(s_a, v_owner, case when v_code = '000000' then '111111' else '000000' end)->>'code', '') <> 'wrong_code' then fails := fails || ' 4:wrong_code'; end if;
  if (select claimed_by from public.leads where id = s_a) <> v_owner then fails := fails || ' 4:moved_on_wrong_code'; end if;
  j := public.fn_supplier_transfer_confirm(s_a, v_owner, v_code);
  if not coalesce((j->>'ok')::boolean, false) or (select claimed_by from public.leads where id = s_a) <> v_est then fails := fails || ' 4:confirm(' || coalesce(j::text, '') || ')'; end if;
  if public.fn_supplier_company_of(v_owner)->>'role' <> 'estimator' then fails := fails || ' 4:old_owner_not_member'; end if;
  if public.fn_supplier_company_of(v_est)->>'role' <> 'owner' then fails := fails || ' 4:new_owner'; end if;
  -- review supplierw2: the former owner's confirmed WhatsApp and listed address stop speaking as the owner
  if exists (select 1 from public.fn_whatsapp_owner('+971500000882') o) then fails := fails || ' 4:old_owner_number_still_names_company'; end if;
  if (select lower(email) from public.leads where id = s_a) <> v_est then fails := fails || ' 4:old_owner_listed_address'; end if;

  -- 5. removal; a job question by e-mail
  if coalesce(public.fn_supplier_member_remove(s_a, v_owner, v_view)->>'code', '') <> 'owner_only' then fails := fails || ' 5:member_removed_member'; end if;
  j := public.fn_supplier_member_remove(s_a, v_est, v_view);
  if not coalesce((j->>'ok')::boolean, false) or public.fn_supplier_company_of(v_view) is not null then fails := fails || ' 5:remove(' || j::text || coalesce(public.fn_supplier_company_of(v_view)::text, '') || ')'; end if;
  insert into public.inquiries (id, customer_id, category, emirate, summary, raw_input, budget, scope_type, trades, spec, status, lang, created_at)
  select x, c, 'plumbing', 'Dubai', 'ZZ DEMO supply and install two 80 litre electric water heaters with isolation valves',
         'ZZ DEMO replace two water heaters', 'AED 5,000', 'single', array['plumbing'],
         jsonb_build_object('scope_detail', 'supply and install two 80 litre electric water heaters'), 'sent', 'en', now() - interval '20 days'
    from unnest(array[i1, i2]) x;
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason)
  select x, s, 0.9, now() - interval '19 days', 'ZZ DEMO sw2 probe' from unnest(array[i1, i2]) x cross join unnest(array[s_a, s_b]) s;
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, source, asked_by_email)
  values (i1, s_a, 'question', 'ZZ DEMO is the old heater to be removed?', 'email', v_owner) returning id into v_cq;
  if not exists (select 1 from jsonb_array_elements(public.fn_job_questions_due(50)) x where (x->>'id')::bigint = v_cq and x->>'step' = 'first_read') then fails := fails || ' 5:not_read_first'; end if;
  update public.rfq_clarification set se_read_at = now(), se_verdict = 'ask_customer', customer_asked_at = now() - interval '25 hours' where id = v_cq;
  if not exists (select 1 from jsonb_array_elements(public.fn_job_questions_due(50)) x where (x->>'id')::bigint = v_cq and x->>'step' = 'chase') then fails := fails || ' 5:not_chased'; end if;
  update public.rfq_clarification set customer_chased_at = now() where id = v_cq;
  if exists (select 1 from jsonb_array_elements(public.fn_job_questions_due(50)) x where (x->>'id')::bigint = v_cq) then fails := fails || ' 5:chased_twice'; end if;
  -- review customerw2: a supplier may be the one who answered (the customer-question branch's clarify_reply), and a CUSTOMER's
  -- question about one quote is never a job question for every bidder. Where that branch's own check (a customer row names its
  -- quote and his words) is already applied, this row is refused by it and the assertion is that branch's probe's.
  update public.rfq_clarification set answered_by = 'supplier' where id = v_cq;
  update public.rfq_clarification set answered_by = null where id = v_cq;
  begin
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, source, asked_by)
    values (i2, s_b, 'question', 'ZZ DEMO does your price include the valves?', 'portal', 'customer') returning id into v_cq;
    if exists (select 1 from jsonb_array_elements(public.fn_job_questions_due(50)) x where (x->>'id')::bigint = v_cq) then fails := fails || ' 5:customer_question_put_to_every_bidder'; end if;
  exception when check_violation then null;
  end;
  begin
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, source) values (i1, s_a, 'question', 'ZZ DEMO x', 'telegram');
    fails := fails || ' 5:unknown_source';
  exception when check_violation then null;
  end;

  -- 6. the customer is not answering
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, lead_time, status)
  values (qa, i1, s_a, 10500, 10000, '10 days', 'submitted'), (qb, i1, s_b, 9450, 9000, '7 days', 'submitted'), (qa2, i2, s_a, 2100, 2000, '3 days', 'submitted');
  set local session_replication_role = replica;
  update public.quotes set status = 'submitted' where id in (qa, qb, qa2);
  set local session_replication_role = origin;
  insert into public.transactions (id, quote_id, inquiry_id, supplier_id, customer_id, revealed_at) values (tx, qa, i1, s_a, c, now() - interval '2 hours');
  if coalesce(public.fn_supplier_customer_not_answering(s_a, v_est, i1, 'portal', null)->>'code', '') <> 'too_soon' then fails := fails || ' 6:too_soon'; end if;
  if coalesce(public.fn_supplier_customer_not_answering(s_b, 'zz-demo-sw2-b@example.invalid', i1, 'portal', null)->>'code', '') <> 'not_revealed' then fails := fails || ' 6:unrevealed'; end if;
  update public.transactions set revealed_at = now() - interval '2 days' where id = tx;
  j := public.fn_supplier_customer_not_answering(s_a, v_est, i1, 'whatsapp', 'ZZ DEMO called twice');
  if not coalesce((j->>'nudged')::boolean, false) then fails := fails || ' 6:no_nudge(' || j::text || ')'; end if;
  if not coalesce((public.fn_supplier_customer_not_answering(s_a, v_est, i1, 'portal', null)->>'already')::boolean, false) then fails := fails || ' 6:twice'; end if;
  if (select count(*) from public.notifications where type = 'customer_supplier_trying_to_reach' and to_email = 'zz-demo-sw2-c@example.invalid') <> 1 then fails := fails || ' 6:nudge_count'; end if;
  if not exists (select 1 from public.supplier_customer_silence where transaction_id = tx and channel = 'whatsapp') then fails := fails || ' 6:not_kept'; end if;

  -- 7. the follow-up's answer reaches him
  insert into public.customer_followup (transaction_id, stage, lang) values (tx, 'day_three', 'en') returning id into v_fu;
  update public.customer_followup set answered_at = now(), hired = 'yes', stars = 5, comment = 'ZZ DEMO great' where id = v_fu;
  if not exists (select 1 from public.notifications where type = 'supplier_followup_outcome' and lead_id = s_a and subject ~ 'hired you' and body !~ 'ZZ DEMO great') then fails := fails || ' 7:not_relayed'; end if;

  -- 8. the customer's word, and the loser's reason owed
  if coalesce(public.fn_customer_decision_reason_save(c, qb, 'ZZ DEMO cheaper', 'en')->>'code', '') <> 'not_revealed' then fails := fails || ' 8:unrevealed_word'; end if;
  if not coalesce((public.fn_customer_decision_reason_save(c, qa, 'ZZ DEMO they could start on Sunday and visited the site', 'en')->>'ok')::boolean, false) then fails := fails || ' 8:word'; end if;
  update public.inquiries set status = 'completed', hired_supplier_id = s_a where id = i1;
  select x into j from jsonb_array_elements(public.fn_supplier_loss_reasons_due(50)) x where x->>'inquiry_id' = i1::text and (x->>'supplier_id')::bigint = s_b;
  if j is null or j->>'outcome' <> 'hired_other' or (j #>> '{mine,ex_vat}')::numeric <> 9000 or (j #>> '{chosen,ex_vat}')::numeric <> 10000
     or j->>'decision_reason' !~ 'Sunday' then fails := fails || ' 8:due(' || coalesce(j::text, 'none') || ')'; end if;
  if exists (select 1 from jsonb_array_elements(public.fn_supplier_loss_reasons_due(50)) x where x->>'inquiry_id' = i1::text and (x->>'supplier_id')::bigint = s_a) then fails := fails || ' 8:winner_listed'; end if;
  insert into public.supplier_loss_reason (inquiry_id, supplier_id, text) values (i1, s_b, 'ZZ DEMO written');
  if exists (select 1 from jsonb_array_elements(public.fn_supplier_loss_reasons_due(50)) x where x->>'inquiry_id' = i1::text) then fails := fails || ' 8:listed_twice'; end if;

  -- 9. close and reopen
  if coalesce(public.fn_supplier_close_propose(s_a, v_owner, 'email', 'withdraw', null)->>'code', '') <> 'owner_only' then fails := fails || ' 9:member_closed'; end if;
  j := public.fn_supplier_close_propose(s_a, v_est, 'email', 'withdraw', 'ZZ DEMO retiring');
  if not coalesce((j->>'ok')::boolean, false) or (j->>'live_quotes')::int <> 1 then fails := fails || ' 9:propose(' || j::text || ')'; end if;
  if (select permanently_closed from public.leads where id = s_a) is true then fails := fails || ' 9:closed_on_proposal'; end if;
  j := public.fn_supplier_close_decide(s_a, v_est, 'confirm');
  if not coalesce((j->>'ok')::boolean, false) or (j->>'withdrawn')::int <> 1 then fails := fails || ' 9:close(' || j::text || ')'; end if;
  if (select status from public.quotes where id = qa2) <> 'withdrawn' or (select status from public.quotes where id = qa) <> 'submitted' then fails := fails || ' 9:quotes'; end if;
  if (select permanently_closed from public.leads where id = s_a) is not true or (select state from public.supplier_availability where supplier_id = s_a) <> 'paused' then fails := fails || ' 9:still_matched'; end if;
  if not exists (select 1 from public.pdpl_requests where email = v_est and kind = 'delete' and status = 'deferred' and outcome ? 'kept_until') then fails := fails || ' 9:no_pdpl'; end if;
  if not exists (select 1 from public.notifications where type = 'supplier_account_closed' and to_email = v_est and body ~ 'Cabinet Decision 74/2023' and body ~ 'withdrawn'
                 and body ~ 'Personal Data Protection' and v_owner = any(cc_emails)) then fails := fails || ' 9:letter'; end if;
  if not coalesce((public.fn_supplier_close_account(s_a, v_est, 'portal', 'keep', null)->>'already')::boolean, false) then fails := fails || ' 9:closed_twice'; end if;
  j := public.fn_supplier_reopen_account(s_a, v_est);
  if not coalesce((j->>'ok')::boolean, false)
     or (select permanently_closed from public.leads where id = s_a) is true or (select state from public.supplier_availability where supplier_id = s_a) <> 'available' then fails := fails || ' 9:reopen(' || j::text || ')'; end if;

  -- 10. a demand signal
  perform public.fn_supplier_demand_signal_record(s_b, 'whatsapp', 'exclusivity on villa painting', 'painting', 'villas', 'ZZ DEMO I will pay to get all villa jobs');
  perform public.fn_supplier_demand_signal_record(s_b, 'email', 'exclusivity on villa painting', 'painting', 'villas', 'ZZ DEMO again');
  select count(*) into n from public.supplier_demand_signal where lead_id = s_b;
  if n <> 1 then fails := fails || ' 10:signals(' || n || ')'; end if;
  if (public.fn_ceo_supplier_demand_signals(30)->>'signals')::int < 1 then fails := fails || ' 10:ceo_blind'; end if;

  if fails <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: owner-only invitations, refused addresses, acts only after accepting; WhatsApp by the code from his number, shared numbers name nobody; a listed name held until decided; ownership passes only by the owner''s code; removal; an e-mailed job question read first and chased once; not-answering refused early, nudged once and kept; hired relayed without the stars; the word kept and the loser listed once with ex-VAT facts; owner-only close withdraws, stops matching, records PDPL and writes the law; reopen; one demand signal a day the CEO reads>>';
end $probe$;

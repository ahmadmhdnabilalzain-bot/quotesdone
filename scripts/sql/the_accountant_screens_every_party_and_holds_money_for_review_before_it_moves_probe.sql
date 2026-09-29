-- PROBE for the_accountant_screens_every_party_and_holds_money_for_review_before_it_moves.sql (accountant).
-- A pure probe: it always ends by raising 'PROBE OK ...' or 'PROBE FAILED: ...', so every row it writes rolls
-- back. Before the apply, run it in ONE transaction after the file it proves; after the apply, run it alone.
--
-- Every party it creates is a ZZ DEMO fixture: customers at @zz-risk.invalid (fn_is_demo_email), suppliers named
-- 'ZZ DEMO ...' with .invalid addresses, never a real lead or a real customer. It asserts that no notification was
-- queued to any of those addresses (fn_email_sendable refuses a .invalid domain), so it cannot reach a person.
--
-- What it proves:
--   1. fn_email_domain_class: gmail.com free, mailinator.com disposable, a company domain company, no '@' null.
--   2. a reveal between a customer on a disposable domain and a supplier whose licence name is not his registered
--      name is HELD (one 'held' row, one fraud.money_held handoff answered by customer_support), and screening it
--      again neither adds a row nor a second handoff;
--   3. the flags are closed by the existing fn_fraud_resolve, the duty re-screens, and the hold is RELEASED by the
--      screen with a fraud.money_released handoff;
--   4. a reviewer's fn_money_move_hold_release lets one held refund go, and the same flags do not hold it again;
--   5. lower flags only (a company address on another domain) -> the money moves and the screen writes 'noted';
--      no flag -> nothing written;
--   6. three refund requests in 90 days flag the customer refund_pattern high and hold that customer's refund;
--   7. a hold older than 48 hours raises money_hold_unreviewed:<id> in the duty, and its release closes it.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  c1 uuid; c2 uuid; c3 uuid; c4 uuid; l1 bigint; l2 bigint; l3 bigint;
  v jsonb; v2 jsonb; v_hold bigint; v_n int; v_bad text := ''; i_ar uuid; q_ar uuid; t_ref uuid; r_ref bigint;
  v_emails text[];
begin
  -- a disposable domain that exists only in this transaction; a sign-up on it would be refused, so the customers
  -- are created first and the domain listed afterwards, the way a list that grows meets an existing account.
  insert into public.customers (email, full_name, locale) values
    ('zz-risk-' || v_tag || '-1@zz-risk.invalid', 'ZZ DEMO risk customer 1', 'en') returning id into c1;
  insert into public.customers (email, full_name, locale) values
    ('zz-risk-' || v_tag || '-2@zz-risk.invalid', 'ZZ DEMO risk customer 2', 'ar') returning id into c2;
  insert into public.customers (email, full_name, locale) values
    ('zz-clean-' || v_tag || '-3@example.invalid', 'ZZ DEMO clean customer 3', 'en') returning id into c3;
  insert into public.customers (email, full_name, locale) values
    ('zz-clean-' || v_tag || '-4@example.invalid', 'ZZ DEMO refund customer 4', 'en') returning id into c4;
  insert into public.app_blocked_domains (domain, reason) values ('zz-risk.invalid', 'disposable') on conflict do nothing;

  insert into public.leads (company_name, licence_legal_name, email, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Risk Steel ' || v_tag || ' LLC', 'ZZ DEMO Another Trading ' || v_tag || ' LLC',
     'sales@zz-risk-steel-' || v_tag || '.invalid', true, 'owner@zz-risk-steel-' || v_tag || '.invalid', 'pending') returning id into l1;
  insert into public.leads (company_name, email, domain, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Mismatch Glass ' || v_tag, 'office@zz-mail-' || v_tag || '.invalid', 'www.zz-site-' || v_tag || '.invalid',
     true, 'office@zz-mail-' || v_tag || '.invalid', 'pending') returning id into l2;
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status) values
    ('ZZ DEMO Clean Paint ' || v_tag, 'office@zz-clean-' || v_tag || '.invalid', true, 'office@zz-clean-' || v_tag || '.invalid', 'pending') returning id into l3;
  v_emails := array(select email from public.customers where id in (c1, c2, c3, c4))
           || array(select claimed_by from public.leads where id in (l1, l2, l3));

  -- 1. the class of an address
  if public.fn_email_domain_class('someone@gmail.com') is distinct from 'free' then v_bad := v_bad || 'gmail.com is not free; '; end if;
  if public.fn_email_domain_class('someone@mailinator.com') is distinct from 'disposable' then v_bad := v_bad || 'mailinator.com is not disposable; '; end if;
  if public.fn_email_domain_class('someone@acme-steel.ae') is distinct from 'company' then v_bad := v_bad || 'a company domain is not company; '; end if;
  if public.fn_email_domain_class('no address') is not null then v_bad := v_bad || 'a value with no @ has a class; '; end if;

  -- 2. held
  v := public.fn_accountant_money_screen('reveal', 'zz-demo-quote-' || v_tag, c1, l1);
  v_hold := (v->>'hold_id')::bigint;
  if not coalesce((v->>'hold')::boolean, false) then v_bad := v_bad || 'the reveal was not held: ' || v::text || '; '; end if;
  if not exists (select 1 from jsonb_array_elements(v->'flags') e(f) where e.f->>'kind' = 'company_name_mismatch' and e.f->>'severity' = 'high')
     or not exists (select 1 from jsonb_array_elements(v->'flags') e(f) where e.f->>'kind' = 'disposable_email' and e.f->>'subject_type' = 'customer') then
    v_bad := v_bad || 'the hold does not name the name mismatch and the disposable address: ' || (v->'flags')::text || '; ';
  end if;
  v2 := public.fn_accountant_money_screen('reveal', 'zz-demo-quote-' || v_tag, c1, l1);
  if (v2->>'hold_id')::bigint is distinct from v_hold then v_bad := v_bad || 'a second screen opened a second hold; '; end if;
  select count(*) into v_n from public.money_move_hold where ref = 'zz-demo-quote-' || v_tag;
  if v_n <> 1 then v_bad := v_bad || v_n || ' hold rows for one reveal; '; end if;
  select count(*) into v_n from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
     and detail->>'type' = 'fraud.money_held' and detail->>'hold_id' = v_hold::text;
  if v_n <> 1 then v_bad := v_bad || v_n || ' fraud.money_held handoffs (want 1); '; end if;
  if not exists (select 1 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'fraud.money_held'
                   and detail->>'hold_id' = v_hold::text and status = 'done' and evidence ? 'sent') then
    v_bad := v_bad || 'customer_support did not answer the hold handoff: '
      || coalesce((select jsonb_build_object('status', status, 'evidence', evidence, 'detail', detail)::text from public.agent_actions
                    where kind = 'handoff' and detail->>'type' = 'fraud.money_held' and detail->>'hold_id' = v_hold::text), 'no row') || '; ';
  end if;

  -- 2b. the customer is written in the REQUEST's language (an English-registered customer's Arabic request), and a
  --     refund row with no inquiry_id takes its transaction's request, so the reference is never blank
  insert into public.inquiries (customer_id, category, emirate, summary, status, lang, spec, scope_type) values
    (c1, 'gypsum', 'Dubai', 'ZZ DEMO سقف', 'sent', 'ar', '{}'::jsonb, 'single') returning id into i_ar;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (i_ar, l1, 1000, 'submitted') returning id into q_ar;
  v := public.fn_accountant_money_screen('reveal', q_ar::text, c1, l1);
  v2 := public.fn_customer_support_held_money_message((v->>'hold_id')::bigint, 'fraud.money_held');
  if v2->>'lang' is distinct from 'ar' or position('QD-' || public.fn_job_no(i_ar) in v2->>'body') = 0 then
    v_bad := v_bad || 'the held-reveal message is not in the request''s language with its number: ' || left(v2::text, 200) || '; ';
  end if;
  insert into public.transactions (customer_id, inquiry_id, reveal_fee, total_charged, fee_status, payment_ref)
  values (c2, i_ar, 30, 30, 'paid', 'pi_zz_demo_' || v_tag) returning id into t_ref;
  insert into public.refunds (transaction_id, customer_id, reason_code, requested_by, status, stripe_payment_intent, amount_fils, amount_source)
  values (t_ref, c2, 'other', 'customer', 'requested', 'pi_zz_demo_' || v_tag, 3000, 'in_platform_request')
    returning id into r_ref;
  v := public.fn_accountant_money_screen('refund', r_ref::text, c2, null);
  v2 := public.fn_customer_support_held_money_message((v->>'hold_id')::bigint, 'fraud.money_held');
  if not coalesce((v->>'hold')::boolean, false) or v2->>'ref' is distinct from 'QD-' || public.fn_job_no(i_ar)
     or position('QD-' || public.fn_job_no(i_ar) in v2->>'body') = 0 then
    v_bad := v_bad || 'a refund with no inquiry_id has no reference: ' || left(v2::text, 200) || '; ';
  end if;
  perform public.fn_money_move_hold_release((v->>'hold_id')::bigint, 'ZZ DEMO reviewer', 'ZZ DEMO probe: reference checked');

  -- 3. reviewed and closed through the existing fraud workspace door, then released by the duty
  perform public.fn_fraud_resolve('customer', c1::text, 'dismiss', 'ZZ DEMO probe');
  perform public.fn_fraud_resolve('lead', l1::text, 'dismiss', 'ZZ DEMO probe');
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_accountant_risk_screen_tick();
  if (select status from public.money_move_hold where id = v_hold) <> 'released'
     or (select released_by from public.money_move_hold where id = v_hold) <> 'screen' then
    v_bad := v_bad || 'closing the flags did not release the hold: ' || v::text || '; ';
  end if;
  if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
                   and detail->>'type' = 'fraud.money_released' and detail->>'hold_id' = v_hold::text) then
    v_bad := v_bad || 'no fraud.money_released handoff; ';
  end if;

  -- 4. a reviewer lets one held refund go with the flags still open
  v := public.fn_accountant_money_screen('refund', 'zz-demo-refund-' || v_tag, c2, null);
  if not coalesce((v->>'hold')::boolean, false) then v_bad := v_bad || 'the refund to a disposable address was not held; '; end if;
  v2 := public.fn_money_move_hold_release((v->>'hold_id')::bigint, 'ZZ DEMO reviewer', 'ZZ DEMO probe: reviewed, the refund may go');
  if not coalesce((v2->>'released')::boolean, false) then v_bad := v_bad || 'the reviewer could not release: ' || v2::text || '; '; end if;
  v2 := public.fn_accountant_money_screen('refund', 'zz-demo-refund-' || v_tag, c2, null);
  if coalesce((v2->>'hold')::boolean, true) or not coalesce((v2->>'reviewed')::boolean, false) then
    v_bad := v_bad || 'the released refund was held again by the same flags: ' || v2::text || '; ';
  end if;

  -- 5. lower flags only -> noted; no flag -> nothing
  v := public.fn_accountant_money_screen('reveal', 'zz-demo-quote2-' || v_tag, c3, l2);
  if coalesce((v->>'hold')::boolean, true) or v->>'noted' is null
     or not exists (select 1 from jsonb_array_elements(v->'flags') e(f) where e.f->>'kind' = 'email_domain_mismatch') then
    v_bad := v_bad || 'a medium flag did not let the money move with a noted row: ' || v::text || '; ';
  end if;
  v := public.fn_accountant_money_screen('reveal', 'zz-demo-quote3-' || v_tag, c3, l3);
  if coalesce((v->>'hold')::boolean, true) or exists (select 1 from public.money_move_hold where ref = 'zz-demo-quote3-' || v_tag) then
    v_bad := v_bad || 'a clean pair was held or recorded: ' || v::text || '; ';
  end if;

  -- 6. three refund requests in 90 days
  insert into public.transactions (customer_id, refund_requested_at)
  select c4, now() - (g || ' days')::interval from generate_series(1, 3) g;
  v := public.fn_accountant_money_screen('refund', 'zz-demo-refund4-' || v_tag, c4, null);
  if not coalesce((v->>'hold')::boolean, false)
     or not exists (select 1 from public.fraud_flags where kind = 'refund_pattern' and subject_id = c4::text and severity = 'high') then
    v_bad := v_bad || 'three refund requests did not flag refund_pattern high and hold: ' || v::text || '; ';
  end if;

  -- 7. unreviewed for 48 hours -> the accountant's finding; released -> closed
  v_hold := (v->>'hold_id')::bigint;
  update public.money_move_hold set opened_at = now() - interval '3 days' where id = v_hold;
  perform public.fn_accountant_risk_screen_tick();
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'money_hold_unreviewed:' || v_hold and closed_at is null) then
    v_bad := v_bad || 'a 3-day-old hold raised no money_hold_unreviewed finding; ';
  end if;
  perform public.fn_money_move_hold_release(v_hold, 'ZZ DEMO reviewer', 'ZZ DEMO probe: reviewed');
  perform public.fn_accountant_risk_screen_tick();
  if exists (select 1 from public.it_engineer_finding where issue_key = 'money_hold_unreviewed:' || v_hold and closed_at is null) then
    v_bad := v_bad || 'the released hold''s finding stayed open; ';
  end if;

  -- nothing reached a person
  select count(*) into v_n from public.notifications where lower(to_email) = any(v_emails) and status not in ('failed', 'skipped', 'suppressed', 'cancelled', 'held');
  if v_n > 0 then v_bad := v_bad || v_n || ' live notification rows to a fixture address; '; end if;

  if v_bad <> '' then raise exception 'PROBE FAILED: %', v_bad; end if;
  raise exception 'PROBE OK: held, re-screened once, released on closed flags and by a reviewer, noted on lower flags, nothing on a clean pair, refund pattern held, 48-hour finding raised and closed';
end $probe$;

-- PROBE for an_approved_supplier_is_told_and_the_licence_name_must_match.sql. Seat: sales_engineer.
-- Never applied: it always raises CHK<<...>>, so every row it writes rolls back. Its subjects are two
-- ZZ DEMO fixtures at @example.invalid addresses, so nothing here can reach a real person even before
-- the rollback (fn_seat_clock_refusal lets a fixture write only to a fixture address).
--
-- Proves: (1) the transition to approved queues exactly ONE email (to claimed_by, English, the portal link,
-- the categories) and ONE WhatsApp twin addressed to the confirmed number, queued (or, for these fixtures,
-- captured by the existing zzzz_notifications_demo_capture guard, which is the guard that must stay); (2) leaving and re-entering
-- approved queues nothing more; (3) whatsapp_opt='none' queues the email only; (4) the name comparison.
do $probe$
declare
  a bigint; b bigint; v_codes text[]; e_a int; w_a int; e_a2 int; w_a2 int; e_b int; w_b int;
  v_auto_was boolean; v_to text; v_phone text; v_body text; v_subj text; f text[] := '{}'; v_rev jsonb;
begin
  select array_agg(code order by code) into v_codes from (select code from public.taxonomy_trade order by code limit 2) t;

  insert into public.leads (company_name, claimed_by, email, whatsapp_opt, whatsapp_phone, whatsapp_verified_at, approval_status)
  values ('ZZ DEMO — Approval Notice Probe A L.L.C', 'zz-approval-a@example.invalid', 'zz-approval-a@example.invalid',
          'other', '+971500000000', now(), 'pending') returning id into a;
  insert into public.leads (company_name, claimed_by, email, whatsapp_opt, approval_status)
  values ('ZZ DEMO — Approval Notice Probe B', 'zz-approval-b@example.invalid', 'zz-approval-b@example.invalid',
          'none', 'pending') returning id into b;
  insert into public.supplier_capabilities (supplier_id, proposed_trades) values (a, v_codes);
  -- The mandatory six (trg_leads_e0_mandatory_six_gate refuses approval without them). The two document
  -- objects are rows the rollback removes; no file is uploaded.
  insert into storage.objects (bucket_id, name) values
    ('supplier-docs', 'zz-probe/approval-notice/licence.pdf'), ('supplier-docs', 'zz-probe/approval-notice/profile.pdf');
  update public.leads
     set phone = '971500000000', owner_phone_verified = true, owner_email_verified = true,
         license_doc_path = 'zz-probe/approval-notice/licence.pdf', company_profile_doc_path = 'zz-probe/approval-notice/profile.pdf',
         signed_terms_path = 'zz-probe/approval-notice/terms.pdf',
         licence_legal_name = company_name   -- the licence names this company (an unread name is held for review)
   where id in (a, b);

  update public.leads set approval_status = 'approved' where id = a;
  select count(*) into e_a from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'email';
  select count(*) into w_a from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'whatsapp' and to_phone is not null and (status = 'queued' or last_error like 'captured:%');
  select to_email, subject, body into v_to, v_subj, v_body from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'email';
  select to_phone || ' [' || status || ': ' || coalesce(last_error, '-') || ']' into v_phone from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'whatsapp';

  update public.leads set approval_status = 'action_required' where id = a;
  update public.leads set approval_status = 'approved' where id = a;
  update public.leads set approval_status = 'approved', verified = true where id = a;
  select count(*) into e_a2 from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'email';
  select count(*) into w_a2 from public.notifications where lead_id = a and type = 'supplier_approved' and channel = 'whatsapp';

  update public.leads set approval_status = 'approved' where id = b;
  select count(*) into e_b from public.notifications where lead_id = b and type = 'supplier_approved' and channel = 'email';
  select count(*) into w_b from public.notifications where lead_id = b and type = 'supplier_approved' and channel = 'whatsapp' and to_phone is not null;

  if e_a <> 1 then f := f || ('A emails ' || e_a); end if;
  if w_a <> 1 then f := f || ('A queued whatsapp ' || w_a); end if;
  if v_to is distinct from 'zz-approval-a@example.invalid' then f := f || ('A to_email ' || coalesce(v_to, 'null')); end if;
  if split_part(coalesce(v_phone, ''), ' ', 1) <> '+971500000000' then f := f || ('A to_phone ' || coalesce(v_phone, 'null')); end if;
  if position('https://quotesdone.com/portal' in coalesce(v_body, '')) = 0 then f := f || text 'no portal link'; end if;
  if (select count(*) from unnest(v_codes) c join public.taxonomy_trade t on t.code = c
       where position('• ' || t.label in v_body) > 0) <> 2 then f := f || text 'categories not listed'; end if;
  if v_body ~ '\mAI\M' or v_subj ~ '\mAI\M' then f := f || text 'the word AI'; end if;
  if length(v_subj) > 90 then f := f || text 'subject over 90'; end if;
  if e_a2 <> 1 or w_a2 <> 1 then f := f || ('re-approval queued again: emails ' || e_a2 || ', whatsapp ' || w_a2); end if;
  if e_b <> 1 then f := f || ('B emails ' || e_b); end if;
  if w_b <> 0 then f := f || ('B queued whatsapp ' || w_b); end if;

  if public.fn_company_name_norm('Al Meydan Aluminium & Glass Works L.L.C') <> public.fn_company_name_norm('AL MEYDAN ALUMINIUM AND GLASS WORKS LLC')
    then f := f || text 'norm: & / L.L.C'; end if;
  -- Arabic survives [:alnum:] (production lc_ctype en_US.UTF-8, measured 24 Sep) and the legal form drops.
  if public.fn_company_name_norm('الميدان للألمنيوم ش.ذ.م.م') <> public.fn_company_name_norm('الميدان للألمنيوم')
     or public.fn_company_name_norm('الميدان للألمنيوم') = '' then f := f || text 'norm: Arabic'; end if;
  if public.fn_company_name_norm('Nasser Metal Works Est.')<> public.fn_company_name_norm('Nasser Metal Works') then f := f || text 'norm: Est.'; end if;
  if public.fn_company_name_norm('Nasser Metal Works') = public.fn_company_name_norm('Rashid Metal Works') then f := f || text 'norm: different names equal'; end if;
  update public.leads set licence_legal_name = 'Some Other Trading LLC' where id = b;
  if not public.fn_supplier_licence_name_mismatch((select l from public.leads l where id = b)) then f := f || text 'mismatch not seen'; end if;
  -- The review itself: a complete registration whose licence names another company is action_required.
  update public.leads set approval_status = 'pending', verified = false where id = b;
  v_rev := public.fn_sales_engineer_verifies_supplier(b, 'probe');
  if (v_rev->>'reason') is distinct from 'licence_name_mismatch'
     or (select approval_status from public.leads where id = b) <> 'action_required' then f := f || ('review did not block the mismatch: ' || v_rev::text); end if;
  update public.leads set licence_legal_name = 'ZZ DEMO - Approval Notice Probe B LLC' where id = b;
  if public.fn_supplier_licence_name_mismatch((select l from public.leads l where id = b)) then f := f || text 'false mismatch'; end if;
  update public.leads set licence_legal_name = null where id = b;
  if public.fn_supplier_licence_name_mismatch((select l from public.leads l where id = b)) then f := f || text 'unread name blocks'; end if;

  -- A SCANNED LICENCE WHOSE NAME COULD NOT BE READ (model held or unreadable): even with automatic approval
  -- ON, the registration waits as pending, reason licence_name_unread, and the verification row needs review.
  select auto_approve_suppliers into v_auto_was from public.pricing_config where id = 1;
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  update public.leads set licence_legal_name = null, approval_status = 'pending', verified = false where id = b;
  v_rev := public.fn_sales_engineer_verifies_supplier(b, 'probe');
  if (v_rev->>'decision') is distinct from 'pending' or (v_rev->>'reason') is distinct from 'licence_name_unread'
     or (select approval_status from public.leads where id = b) <> 'pending'
     or not exists (select 1 from public.agent_actions where target_table = 'leads' and target_id = b::text
                     and kind = 'supplier_verification' and status = 'needs_review')
    then f := f || ('unread name was not held for review: ' || v_rev::text); end if;
  -- The name read off the scan lands and matches: now, and only now, it is approved automatically.
  update public.leads set licence_legal_name = 'ZZ DEMO - Approval Notice Probe B LLC' where id = b;
  v_rev := public.fn_sales_engineer_verifies_supplier(b, 'probe');
  if (select approval_status from public.leads where id = b) <> 'approved' then f := f || ('a read, matching name was not approved: ' || v_rev::text); end if;
  -- An already-approved supplier whose licence name is (now) unread stays approved.
  update public.leads set licence_legal_name = null where id = b;
  v_rev := public.fn_sales_engineer_verifies_supplier(b, 'probe');
  if (select approval_status from public.leads where id = b) <> 'approved' then f := f || ('an approved supplier lost approval on an unread name: ' || v_rev::text); end if;
  update public.pricing_config set auto_approve_suppliers = v_auto_was where id = 1;

  raise exception 'CHK<<%>> A: email % / whatsapp % (to %, phone %), after re-approval % / %; B (opt none): email % / addressed whatsapp %. SUBJECT: % BODY: %',
    case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end,
    e_a, w_a, v_to, v_phone, e_a2, w_a2, e_b, w_b, v_subj, v_body;
end
$probe$;

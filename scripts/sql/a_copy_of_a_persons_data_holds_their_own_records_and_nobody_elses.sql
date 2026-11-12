-- A COPY OF A PERSON'S DATA HOLDS THEIR OWN RECORDS, AND NOBODY ELSE'S.
--
-- Assigned: customer_support (built by it_engineer). 12 Nov 2026. Founder ledger 1669 ("That's what I got when I
-- pressed download my data as a supplier. Again, horrible.") and 1671 ("Download my data should be a pdf with our
-- template"). The PDF is drawn by the my_data_pdf edge function from what this routine returns; the same answer is the
-- machine-readable copy (privacy policy 1.6, "data portability"). Replaces fn_pdpl_export_data and fn_pdpl_phone_tails
-- of a_person_can_get_a_copy_of_their_data_and_have_it_erased_where_no_law_requires_it_kept.sql (#1237), read LIVE
-- with pg_get_functiondef on 12 Nov 2026 and identical to that file. Nothing else in that file changes.
--
-- WHAT THE LIVE ROUTINE HANDED OVER, measured 12 Nov 2026 (shapes and counts only; ZZ DEMO exports read, SELECT only):
--   1. ANOTHER PERSON'S PAYMENT. `transactions` and `refunds` matched `supplier_id in (his leads)` and returned the
--      whole row with to_jsonb: a supplier's copy carried the CUSTOMER's reveal payment, payment reference, Stripe
--      invoice number and the hosted/PDF invoice links (bearer links that show the customer's billing details),
--      the customer's refund, receipt link and reason note. Proved on the ZZ DEMO supplier: invoice link present.
--   2. INTERNAL AND SYSTEM FIELDS. Whole rows of customers (33 columns), leads (168) and transactions (43): staff
--      names (approval_decided_by, refunds.decided_by), internal notes (leads.notes on 379 listed companies,
--      ai_review_notes, decision_note, reconciliation_note), model output (ai_review_flags, two embedding vectors on
--      4,067 listed companies), bearer tokens (leads.claim_token, transactions.ack_token), scores and flags.
--   3. A COMPANY RECORD BY MAILBOX, NOT BY OWNER. supplier_records matched leads.email (the address we listed the
--      company under), never leads.claimed_by (the person who registered it). So (a) a registered supplier whose
--      login differs from the listed address got NO company record, NO quotations and NO company messages (1 of the
--      3 registered suppliers today), and (b) anyone verifying the listed address as a customer would have received
--      the registered owner's row (owner date of birth, signatory, terms IP). 0 such accounts today; nothing stopped it.
--   4. WHATSAPP BY THE LAST NINE DIGITS OF ANY NUMBER ON FILE, AT ANY DATE. The numbers came from every phone column,
--      verified or not, including the scraped switchboard of a listed company, and a conversation matched on its last
--      nine digits whenever it happened. +971 50 123 4567 and +91 95012 34567 share them; a recycled UAE number brings
--      the previous holder's chats (2 WhatsApp messages on file predate the account they match).
--   5. EMAILS NEVER SENT. `emails_we_sent` listed every notification addressed to him: 325 of 1,546 were cancelled,
--      suppressed, skipped, held or queued, never sent.
--   6. A CHAT MESSAGE THE OTHER SIDE NEVER RECEIVED. portal_chat ignored messages.blocked (0 such rows today).
--   7. MISSING: a supplier's quotations (none at all), what a customer wrote in a request (raw_input).
--
-- WHAT IT RETURNS NOW: named fields per record, chosen as "about this person and shown to this person" — identity,
-- contact, consent, terms, account status (a suspension and its reason ARE his data); never another party's
-- payment, never staff names, internal notes, model output, tokens, storage paths or ids of other people.
--   customer_accounts  customers whose email is his
--   supplier_records   leads he registered (claimed_by), plus a listed company whose listed address is his and that
--                      nobody has registered (nothing in it was written by another person)
--   requests           his requests, with what he wrote
--   quotations         the quotations his company sent (amount, terms, status), never the customer
--   reveals            for a supplier: the date a customer revealed his quotation, never the customer's payment
--   transactions       for a customer: his own reveal payments and his own invoice
--   refunds            for a customer: his own refunds; for a supplier: only that a refund was made on his reveal
--   portal_chat        delivered messages only
--   emails_we_sent     sent only; emails_not_sent counts the rest (they exist and he may ask about them)
--   whatsapp           conversations from a VERIFIED number of his, the whole number compared, each number from the
--                      moment IT was verified on his account (review of #1986, 12 Nov 2026: a bound per account let a
--                      number changed later to a recycled one bring in the previous holder's chats). "Verified" is what
--                      kyc writes and the portal shows (kyc/index.ts verify_sms, _shared/whatsapp_choice.ts
--                      verifiedPatch, PR #1984 mobileStatus): leads.phone with owner_phone_verified, customers.phone
--                      with phone_verified, whatsapp_phone with whatsapp_verified_at. NEVER leads.phone_e164: it is the
--                      number scraped for the listing (marketing/lead_sourcing.ts) and nothing keeps it in step. The
--                      time a phone was verified is its code's phone_verifications.used_at; a WhatsApp number's is its
--                      whatsapp_verified_at. A number verified by MORE THAN ONE account is left out of every copy (one
--                      such number is shared by two real accounts today: each copy would carry the other's chats);
--                      `whatsapp_withheld` counts them so the document can say so. The 500 most recent are given,
--                      with `whatsapp_total`.
--   emails_we_sent     the 500 most recent, with `emails_total`
--   portal_chat        delivered messages, and his OWN undelivered ones marked delivered=false (they are his words)
--   request_files      file names of what he attached to a request (drawings, invoices), never a supplier's quotation
--   company_files      file names of his company's documents (licence, profile, catalogues)
--   data_requests      his own export and erasure requests
--   ...and the date of his signed-terms certificate on his account or company record.
--
-- pdpl_request_me is restated (from its LIVE definition, grants kept) for one change: at most 3 exports per person in 10
-- minutes (each writes a request row, a log row and, for the PDF, a render); the 4th answers code 'too_many_exports'.
--
-- ROLLBACK: never by restoring the earlier bodies of fn_pdpl_export_data / fn_pdpl_phone_tails from
-- a_person_can_get_a_copy_of_their_data_and_have_it_erased_where_no_law_requires_it_kept.sql: that brings every leak
-- listed above back. Roll back the website or the my_data_pdf function instead; a defect here is fixed forward.
--
-- CREATE OR REPLACE keeps the three existing routines' ACLs; the revokes and the one grant are restated (apply discipline
-- §2). One overload each, enumerated live 12 Nov 2026: fn_pdpl_phone_tails(text), fn_pdpl_export_data(text),
-- pdpl_request_me(text). Two routines are NEW (CREATE grants PUBLIC, so each is revoked from every role but the owner):
-- fn_pdpl_norm_phone(text), fn_pdpl_whatsapp_numbers(text). Probe:
-- a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses_probe.sql (run after this file).

create or replace function public.fn_pdpl_norm_phone(p text)
returns text
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- International digits: a leading 00 dropped, UAE local 05x / 5x -> 9715x. Null for anything not 8 to 15 digits.
  select case when length(n) between 8 and 15 then n end
    from (select case when d like '00%' then substr(d, 3)
                      when d ~ '^05[0-9]{8}$' then '971' || substr(d, 2)
                      when d ~ '^5[0-9]{8}$' then '971' || d
                      else d end as n
            from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) a) b;
$fn$;
revoke execute on function public.fn_pdpl_norm_phone(text) from public, anon, authenticated, service_role;

create or replace function public.fn_pdpl_whatsapp_numbers(p_email text)
returns table (num text, since timestamptz, shared boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Every verified number of every account, with who verified it and when; then this person's, each from the moment it
  -- was verified on his account, and whether another account verified it too.
  with v as (
    select lower(c.email) as em, public.fn_pdpl_norm_phone(c.phone) as num,
           coalesce((select min(pv.used_at) from public.phone_verifications pv
                      where lower(pv.email) = lower(c.email) and pv.used_at is not null
                        and public.fn_pdpl_norm_phone(pv.phone) = public.fn_pdpl_norm_phone(c.phone)), c.created_at) as since
      from public.customers c where c.phone_verified and c.email is not null
    union all
    select lower(c.email), public.fn_pdpl_norm_phone(c.whatsapp_phone), c.whatsapp_verified_at
      from public.customers c where c.whatsapp_verified_at is not null and c.email is not null
    union all
    select lower(l.claimed_by), public.fn_pdpl_norm_phone(l.phone),
           coalesce((select min(pv.used_at) from public.phone_verifications pv
                      where lower(pv.email) = lower(l.claimed_by) and pv.used_at is not null
                        and public.fn_pdpl_norm_phone(pv.phone) = public.fn_pdpl_norm_phone(l.phone)),
                    l.accepted_terms_at, l.registration_submitted_at)
      from public.leads l where l.owner_phone_verified and l.claimed_by is not null
    union all
    select lower(l.claimed_by), public.fn_pdpl_norm_phone(l.whatsapp_phone), l.whatsapp_verified_at
      from public.leads l where l.whatsapp_verified_at is not null and l.claimed_by is not null),
  vv as (select * from v where num is not null and since is not null)
  select m.num, min(m.since), (select count(distinct o.em) from vv o where o.num = m.num) > 1
    from vv m where m.em = lower(btrim(p_email))
   group by m.num;
$fn$;
revoke execute on function public.fn_pdpl_whatsapp_numbers(text) from public, anon, authenticated, service_role;

create or replace function public.fn_pdpl_phone_tails(p_email text)
returns text[]
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Kept for its name (#1237). Since 12 Nov 2026: his verified numbers, whole, that no other account verified.
  select coalesce(array_agg(num order by num) filter (where not shared), '{}') from public.fn_pdpl_whatsapp_numbers(p_email);
$fn$;
revoke execute on function public.fn_pdpl_phone_tails(text) from public, anon, authenticated, service_role;

create or replace function public.fn_pdpl_export_data(p_email text)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select lower(btrim(p_email)) as em),
  c as (select cu.* from public.customers cu, e where lower(cu.email) = e.em),
  l as (select le.* from public.leads le, e
         where lower(le.claimed_by) = e.em or (le.claimed_by is null and lower(le.email) = e.em)),
  wn as (select * from public.fn_pdpl_whatsapp_numbers(p_email)),
  wa as (select w.created_at, w.inbound, w.reply from public.wa_messages w join wn
           on not wn.shared and w.created_at >= wn.since and public.fn_pdpl_norm_phone(w.wa_from) = wn.num),
  sent as (select n.* from public.notifications n, e where lower(n.to_email) = e.em and n.status = 'sent')
  select jsonb_build_object(
    'email', (select em from e),
    'generated_at', now(),
    'controller', 'QuotesDone Technologies, a Dubai Sole Establishment, DET Dubai Trader License No. 1633275, Dubai, United Arab Emirates',
    'customer_accounts', (select coalesce(jsonb_agg(jsonb_build_object(
        'full_name', c.full_name, 'email', c.email, 'mobile', c.phone, 'mobile_verified', c.phone_verified,
        'whatsapp_number', c.whatsapp_phone, 'email_verified', c.email_verified, 'date_of_birth', c.date_of_birth,
        'industry', c.industry, 'language', c.locale, 'opened_at', c.created_at,
        'terms_version', c.tos_version, 'terms_accepted_at', c.tos_accepted_at, 'terms_accepted_from_ip', c.tos_ip,
        'signed_terms_certificate_at', c.signed_terms_at,
        'whatsapp_updates', c.whatsapp_opt, 'marketing_consent', c.marketing_consent, 'marketing_consent_at', c.marketing_consent_at,
        'suspended', c.banned, 'suspension_reason', c.banned_reason) order by c.created_at), '[]') from c),
    'supplier_records', (select coalesce(jsonb_agg(jsonb_build_object(
        'registered_by_you', l.claimed_by is not null, 'company_name', l.company_name, 'contact_name', l.contact_name,
        'signatory_name', l.signatory_name, 'login_email', l.claimed_by, 'company_email', l.email,
        'phone', l.phone, 'whatsapp_number', l.whatsapp_phone, 'website', l.website,
        'street', l.street, 'city', l.city, 'emirate', l.emirate, 'service_emirates', l.service_emirates,
        'description', l.description, 'products', l.products, 'services', l.services, 'certifications', l.certifications,
        'trade_licence_number', l.trade_license_no, 'licence_authority', l.license_authority, 'licence_expiry', l.license_expiry,
        'licence_name', l.licence_legal_name, 'trn', coalesce(l.trn, l.vat_number), 'owner_date_of_birth', l.owner_dob,
        'emirates_id', l.emirates_id, 'registration', l.registration_status, 'registration_expires', l.registration_expires_at,
        'approval', l.approval_status, 'approved_at', l.approved_at, 'rejection_reason', l.rejection_reason,
        'terms_version', l.accepted_terms_version, 'terms_accepted_at', l.accepted_terms_at, 'terms_accepted_from_ip', l.accepted_terms_ip,
        'signed_terms_certificate_at', l.signed_terms_at,
        'documents', to_jsonb(array_remove(array[l.license_doc_name, l.egr_doc_name], null)),
        'listed_since', l.created_at, 'where_we_found_the_listing', l.source,
        'whatsapp_updates', l.whatsapp_opt, 'marketing_consent', l.marketing_consent, 'marketing_consent_at', l.marketing_consent_at,
        'suspended', l.banned, 'suspension_reason', l.banned_reason) order by l.id), '[]') from l),
    'requests', (select coalesce(jsonb_agg(jsonb_build_object('reference', i.rfq_no, 'created_at', i.created_at, 'category', i.category,
                   'summary', i.summary, 'what_you_wrote', i.raw_input, 'status', i.status, 'emirate', i.emirate, 'budget', i.budget,
                   'required_by', i.required_by) order by i.created_at), '[]')
                   from public.inquiries i where i.customer_id in (select id from c)),
    -- what he attached to his requests, by name and date; never a quotation file (it names the supplier before a reveal)
    'request_files', (select coalesce(jsonb_agg(jsonb_build_object('file_name', d.file_name, 'kind', d.kind, 'at', d.created_at,
                        'request_reference', i.rfq_no) order by d.created_at), '[]')
                        from public.documents d join public.inquiries i on d.ref_table = 'inquiries' and d.ref_id = i.id::text
                       where i.customer_id in (select id from c) and d.kind is distinct from 'quote'),
    'company_files', (select coalesce(jsonb_agg(jsonb_build_object('file_name', d.file_name, 'kind', d.kind, 'at', d.created_at)
                        order by d.created_at), '[]')
                        from public.documents d where d.ref_table = 'leads' and d.ref_id in (select id::text from l where claimed_by is not null)),
    'quotations', (select coalesce(jsonb_agg(jsonb_build_object('created_at', q.created_at, 'request_reference', i.rfq_no,
                     'category', i.category, 'amount_aed', q.quote_amount, 'price_ex_vat_aed', q.price_ex_vat, 'vat_aed', q.vat_amount,
                     'status', q.status, 'lead_time', q.lead_time, 'validity', q.validity, 'payment_terms', q.payment_terms,
                     'warranty', q.warranty, 'scope', q.scope, 'exclusions', q.exclusions, 'conditions', q.conditions,
                     'file_name', q.original_file_name) order by q.created_at), '[]')
                     from public.quotes q left join public.inquiries i on i.id = q.inquiry_id
                    where q.supplier_id in (select id from l)),
    'reveals', (select coalesce(jsonb_agg(jsonb_build_object('revealed_at', t.revealed_at, 'request_reference', i.rfq_no,
                  'category', i.category, 'you_acknowledged_at', t.supplier_ack_at) order by t.revealed_at), '[]')
                  from public.transactions t left join public.inquiries i on i.id = t.inquiry_id
                 where t.supplier_id in (select id from l) and t.revealed_at is not null),
    'transactions', (select coalesce(jsonb_agg(jsonb_build_object('revealed_at', t.revealed_at, 'request_reference', i.rfq_no,
                       'category', i.category, 'quotation_aed', t.quote_amount, 'reveal_fee_aed', t.reveal_fee,
                       'total_charged_aed', t.total_charged, 'payment', t.fee_status, 'invoice_number', t.stripe_invoice_number,
                       'invoice_link', t.stripe_invoice_hosted_url, 'refund', t.refund_status, 'refund_aed', t.refund_amount_aed)
                       order by t.revealed_at), '[]')
                       from public.transactions t left join public.inquiries i on i.id = t.inquiry_id
                      where t.customer_id in (select id from c)),
    'refunds', (select coalesce(jsonb_agg(x order by x->>'requested_at'), '[]') from (
                  select jsonb_build_object('requested_at', r.requested_at, 'amount_aed', round(r.amount_fils / 100.0, 2),
                           'status', r.status, 'reason', r.reason_code, 'your_note', r.reason_note,
                           'settled_at', r.settled_at, 'receipt_link', r.stripe_receipt_url) x
                    from public.refunds r where r.customer_id in (select id from c)
                  union all
                  select jsonb_build_object('requested_at', r.requested_at, 'status', r.status, 'reason', r.reason_code, 'on_your_quotation', true)
                    from public.refunds r where r.supplier_lead_id in (select id from l)
                     and (r.customer_id is null or r.customer_id not in (select id from c))) rr),
    -- delivered messages, and his own that were never delivered (his words, marked so); never the other side's undelivered
    'portal_chat', (select coalesce(jsonb_agg(jsonb_build_object('at', m.created_at, 'from', m.sender, 'text', m.body,
                      'attachment', m.attachment_path is not null, 'delivered', not coalesce(m.blocked, false)) order by m.created_at), '[]')
                      from public.messages m
                     where (not coalesce(m.blocked, false) and (m.customer_id in (select id from c) or m.supplier_id in (select id from l)))
                        or (coalesce(m.blocked, false) and ((m.sender = 'customer' and m.customer_id in (select id from c))
                                                         or (m.sender = 'supplier' and m.supplier_id in (select id from l))))),
    'emails_we_sent', (select coalesce(jsonb_agg(x order by x->>'at'), '[]') from (
                         select jsonb_build_object('at', coalesce(n.sent_at, n.created_at), 'subject', n.subject, 'text', n.body,
                                  'channel', coalesce(n.channel, 'email')) x
                           from sent n order by n.created_at desc limit 500) z),
    'emails_total', (select count(*) from sent),
    'emails_not_sent', (select count(*) from public.notifications n, e where lower(n.to_email) = e.em and n.status is distinct from 'sent'),
    'emails_we_received', (select coalesce(jsonb_agg(jsonb_build_object('at', im.created_at, 'subject', im.subject, 'text', im.body)
                             order by im.created_at), '[]')
                             from public.inbound_messages im, e where lower(im.from_email) = e.em),
    'whatsapp', (select coalesce(jsonb_agg(x order by x->>'at'), '[]') from (
                   select jsonb_build_object('at', wa.created_at, 'received', wa.inbound, 'replied', wa.reply) x
                     from wa order by wa.created_at desc limit 500) z),
    'whatsapp_total', (select count(*) from wa),
    'whatsapp_withheld', (select count(*) from wn where wn.shared),
    'data_requests', (select coalesce(jsonb_agg(jsonb_build_object('kind', q.kind, 'status', q.status, 'at', q.created_at,
                        'completed_at', q.completed_at, 'erase_after', q.confirm_after, 'cancelled_at', q.cancelled_at) order by q.created_at), '[]')
                        from public.pdpl_requests q, e where lower(q.email) = e.em),
    'opt_out', (select jsonb_build_object('at', s.created_at, 'reason', s.reason) from public.email_suppressions s, e
                 where lower(s.email) = e.em order by s.created_at limit 1));
$fn$;
revoke execute on function public.fn_pdpl_export_data(text) from public, anon, authenticated, service_role;

create or replace function public.pdpl_request_me(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_em text := public.fn_pdpl_my_verified_email(); v_id uuid;
begin
  if v_em is null then
    return jsonb_build_object('ok', false, 'code', 'email_not_verified',
      'message', 'Verify your email address in your account first.', 'message_ar', 'يُرجى توثيق بريدكم الإلكتروني في حسابكم أولًا.');
  end if;
  if p_kind not in ('export', 'delete') then return jsonb_build_object('ok', false, 'code', 'bad_kind'); end if;
  -- ERASE NEEDS A SECOND VERIFIED ACTION: a code is emailed and the clock starts only at pdpl_confirm_me.
  if p_kind = 'delete' then
    return public.fn_pdpl_open(v_em, 'delete', 'self_service') || jsonb_build_object('next', 'pdpl_confirm_me(request_id, code)');
  end if;
  -- 12 Nov 2026 (review of #1986): at most 3 copies in 10 minutes. The PDF, the data file and one retry fit; a loop
  -- of signed-in calls does not write unbounded request and log rows or renders.
  if (select count(*) from public.pdpl_requests q where q.email = v_em and q.kind = 'export'
       and q.created_at > now() - interval '10 minutes') >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_exports');
  end if;
  insert into public.pdpl_requests (kind, email, role, details, status, verified_via, verified_at, handled_by)
  values (p_kind, v_em, 'self_service', 'signed-in, email verified by code', 'received', 'session+email_verified', now(), 'self_service')
  returning id into v_id;
  return public.fn_pdpl_carry_out(v_id);
end $function$;
revoke execute on function public.pdpl_request_me(text) from public, anon;
grant execute on function public.pdpl_request_me(text) to authenticated;

select case
  when has_function_privilege('authenticated', 'public.fn_pdpl_export_data(text)', 'execute')
    or has_function_privilege('anon', 'public.fn_pdpl_phone_tails(text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_pdpl_whatsapp_numbers(text)', 'execute')
    or has_function_privilege('anon', 'public.fn_pdpl_norm_phone(text)', 'execute')
    or has_function_privilege('anon', 'public.pdpl_request_me(text)', 'execute')
    then 'PROBE FAILED: an export helper is reachable by a signed-in or anonymous caller'
  when not has_function_privilege('authenticated', 'public.pdpl_request_me(text)', 'execute')
    then 'PROBE FAILED: signed-in people lost the self-service door'
  when public.fn_pdpl_norm_phone('050 123 4567') <> '971501234567' or public.fn_pdpl_norm_phone('+91 95012 34567') <> '919501234567'
    then 'PROBE FAILED: numbers are not compared whole'
  else 'PROBE OK: the export helpers are reached only through the logged self-service door'
end as verdict;

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
--   whatsapp           conversations from a VERIFIED number of his, the whole number compared, from the day his
--                      account was opened (registered, for a supplier). A chat from before that day is not handed
--                      over: the number may have been someone else's. A person who wants it asks support.
--
-- CREATE OR REPLACE keeps both routines' ACLs; the revokes are restated (apply discipline §2). One overload each,
-- enumerated live 12 Nov 2026: fn_pdpl_phone_tails(text), fn_pdpl_export_data(text). Probe:
-- a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses_probe.sql (run after this file).

create or replace function public.fn_pdpl_phone_tails(p_email text)
returns text[]
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- The VERIFIED numbers of this person, whole, as international digits (UAE local 05x / 5x -> 9715x, a leading
  -- 00 dropped). The name is kept from #1237; since 12 Nov 2026 it returns whole numbers, not nine-digit tails.
  select coalesce(array_agg(distinct n) filter (where length(n) between 8 and 15), '{}')
    from (select case when d like '00%' then substr(d, 3)
                      when d ~ '^05[0-9]{8}$' then '971' || substr(d, 2)
                      when d ~ '^5[0-9]{8}$' then '971' || d
                      else d end as n
            from (select regexp_replace(x, '[^0-9]', '', 'g') as d
                    from (select c.phone as x from public.customers c
                           where lower(c.email) = lower(btrim(p_email)) and c.phone_verified
                          union all
                          select c.whatsapp_phone from public.customers c
                           where lower(c.email) = lower(btrim(p_email)) and c.whatsapp_verified_at is not null
                          union all
                          select unnest(array[l.phone, l.phone_e164]) from public.leads l
                           where lower(l.claimed_by) = lower(btrim(p_email)) and l.owner_phone_verified
                          union all
                          select l.whatsapp_phone from public.leads l
                           where lower(l.claimed_by) = lower(btrim(p_email)) and l.whatsapp_verified_at is not null) s
                   where x is not null) dd) nn;
$fn$;
revoke execute on function public.fn_pdpl_phone_tails(text) from public, anon, authenticated, service_role;

create or replace function public.fn_pdpl_export_data(p_email text)
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select lower(btrim(p_email)) as em, public.fn_pdpl_phone_tails(p_email) as nums),
  c as (select cu.* from public.customers cu, e where lower(cu.email) = e.em),
  l as (select le.* from public.leads le, e
         where lower(le.claimed_by) = e.em or (le.claimed_by is null and lower(le.email) = e.em)),
  since as (select least((select min(created_at) from c),
                         (select min(coalesce(accepted_terms_at, registration_submitted_at)) from l where claimed_by is not null)) as t)
  select jsonb_build_object(
    'email', (select em from e),
    'generated_at', now(),
    'controller', 'QuotesDone Technologies, a Dubai Sole Establishment, DET Dubai Trader License No. 1633275, Dubai, United Arab Emirates',
    'customer_accounts', (select coalesce(jsonb_agg(jsonb_build_object(
        'full_name', c.full_name, 'email', c.email, 'mobile', c.phone, 'mobile_verified', c.phone_verified,
        'whatsapp_number', c.whatsapp_phone, 'email_verified', c.email_verified, 'date_of_birth', c.date_of_birth,
        'industry', c.industry, 'language', c.locale, 'opened_at', c.created_at,
        'terms_version', c.tos_version, 'terms_accepted_at', c.tos_accepted_at, 'terms_accepted_from_ip', c.tos_ip,
        'whatsapp_updates', c.whatsapp_opt, 'marketing_consent', c.marketing_consent, 'marketing_consent_at', c.marketing_consent_at,
        'suspended', c.banned, 'suspension_reason', c.banned_reason) order by c.created_at), '[]') from c),
    'supplier_records', (select coalesce(jsonb_agg(jsonb_build_object(
        'registered_by_you', l.claimed_by is not null, 'company_name', l.company_name, 'contact_name', l.contact_name,
        'signatory_name', l.signatory_name, 'login_email', l.claimed_by, 'company_email', l.email,
        'phone', coalesce(l.phone_e164, l.phone), 'whatsapp_number', l.whatsapp_phone, 'website', l.website,
        'street', l.street, 'city', l.city, 'emirate', l.emirate, 'service_emirates', l.service_emirates,
        'description', l.description, 'products', l.products, 'services', l.services, 'certifications', l.certifications,
        'trade_licence_number', l.trade_license_no, 'licence_authority', l.license_authority, 'licence_expiry', l.license_expiry,
        'licence_name', l.licence_legal_name, 'trn', coalesce(l.trn, l.vat_number), 'owner_date_of_birth', l.owner_dob,
        'emirates_id', l.emirates_id, 'registration', l.registration_status, 'registration_expires', l.registration_expires_at,
        'approval', l.approval_status, 'approved_at', l.approved_at, 'rejection_reason', l.rejection_reason,
        'terms_version', l.accepted_terms_version, 'terms_accepted_at', l.accepted_terms_at, 'terms_accepted_from_ip', l.accepted_terms_ip,
        'documents', to_jsonb(array_remove(array[l.license_doc_name, l.egr_doc_name], null)),
        'listed_since', l.created_at, 'where_we_found_the_listing', l.source,
        'whatsapp_updates', l.whatsapp_opt, 'marketing_consent', l.marketing_consent, 'marketing_consent_at', l.marketing_consent_at,
        'suspended', l.banned, 'suspension_reason', l.banned_reason) order by l.id), '[]') from l),
    'requests', (select coalesce(jsonb_agg(jsonb_build_object('reference', i.rfq_no, 'created_at', i.created_at, 'category', i.category,
                   'summary', i.summary, 'what_you_wrote', i.raw_input, 'status', i.status, 'emirate', i.emirate, 'budget', i.budget,
                   'required_by', i.required_by) order by i.created_at), '[]')
                   from public.inquiries i where i.customer_id in (select id from c)),
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
                           'status', r.status, 'reason', r.reason_code, 'settled_at', r.settled_at, 'receipt_link', r.stripe_receipt_url) x
                    from public.refunds r where r.customer_id in (select id from c)
                  union all
                  select jsonb_build_object('requested_at', r.requested_at, 'status', r.status, 'reason', r.reason_code, 'on_your_quotation', true)
                    from public.refunds r where r.supplier_lead_id in (select id from l)
                     and (r.customer_id is null or r.customer_id not in (select id from c))) rr),
    'portal_chat', (select coalesce(jsonb_agg(jsonb_build_object('at', m.created_at, 'from', m.sender, 'text', m.body,
                      'attachment', m.attachment_path is not null) order by m.created_at), '[]')
                      from public.messages m
                     where not coalesce(m.blocked, false)
                       and (m.customer_id in (select id from c) or m.supplier_id in (select id from l))),
    'emails_we_sent', (select coalesce(jsonb_agg(jsonb_build_object('at', coalesce(n.sent_at, n.created_at), 'subject', n.subject,
                         'text', n.body, 'channel', coalesce(n.channel, 'email')) order by n.created_at), '[]')
                         from public.notifications n, e where lower(n.to_email) = e.em and n.status = 'sent'),
    'emails_not_sent', (select count(*) from public.notifications n, e where lower(n.to_email) = e.em and n.status is distinct from 'sent'),
    'emails_we_received', (select coalesce(jsonb_agg(jsonb_build_object('at', im.created_at, 'subject', im.subject, 'text', im.body)
                             order by im.created_at), '[]')
                             from public.inbound_messages im, e where lower(im.from_email) = e.em),
    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('at', w.created_at, 'received', w.inbound, 'replied', w.reply)
                   order by w.created_at), '[]')
                   from public.wa_messages w, e, since
                  where since.t is not null and w.created_at >= since.t
                    and (select case when d like '00%' then substr(d, 3) when d ~ '^05[0-9]{8}$' then '971' || substr(d, 2)
                                     when d ~ '^5[0-9]{8}$' then '971' || d else d end
                           from (select regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g') as d) z) = any (e.nums)),
    'opt_out', (select jsonb_build_object('at', s.created_at, 'reason', s.reason) from public.email_suppressions s, e
                 where lower(s.email) = e.em order by s.created_at limit 1));
$fn$;
revoke execute on function public.fn_pdpl_export_data(text) from public, anon, authenticated, service_role;

select case
  when has_function_privilege('authenticated', 'public.fn_pdpl_export_data(text)', 'execute')
    or has_function_privilege('anon', 'public.fn_pdpl_phone_tails(text)', 'execute')
    then 'PROBE FAILED: an export helper is reachable by a signed-in or anonymous caller'
  else 'PROBE OK: the export helpers are reached only through the logged self-service door'
end as verdict;

-- ONE JOB NUMBER ON EVERY PORTAL, DOCUMENT AND NOTICE.
--
-- MEASURED (21 Sep 2026 supplier-portal audit, finding 7; read-only on htdblwldjkcgjvmqkbeh):
--   the supplier portal printed job D958E1EA / 8B287960 / A179EA8D (the first 8 characters of
--   inquiries.id, upper-cased: supplier_api/quote_review.ts jobNo) while the customer portal printed
--   151767 / 151768 / 151769 for the SAME three inquiries (inquiries.rfq_no, the human reference the
--   customer notices already carry as 'RFQ-151767'). Neither side could quote the other's number.
--
-- WHAT WAS WRONG: two sources for one fact. inquiries.rfq_no (integer, unique, NOT NULL, from
-- inquiries_rfq_no_seq) is the public job number; the uuid prefix was a second, unrelated one.
--
-- WHAT THIS CHANGES:
--   1. public.fn_job_no(uuid) — the ONE routine that turns an inquiry id into its job number, for any
--      SQL that prints one. Text, so callers concatenate it; null for an unknown inquiry.
--   2. fn_notifications_speak_the_recipients_language — the only SQL routine that prints a reference
--      INTO a customer- or supplier-facing notice ('{ref}' in notification_copy) built 'QD-' + the
--      uuid prefix. It now prints 'QD-' || fn_job_no(...). Body otherwise reproduced verbatim from
--      scripts/sql/the_registered_language_follows_every_message_until_the_reveal.sql (CREATE OR
--      REPLACE keeps the ACL; the revoke is repeated for the record).
--   3. The TypeScript side changes in the same PR: supplier_api (job_no, quote form and submission
--      refs), _shared/quote_documents.ts (QD-<job>-<letter>, QD-<job>-CMP), customer_api (brief,
--      comparison CSV name, cached quote ref), reveal_invoice (receipt Ref) and stripe_checkout (the
--      card statement line) all read inquiries.rfq_no through one helper.
--   4. A demo-data repair: customers 'qd-founderdemo-cust1@example.invalid' carries full_name
--      'ZZ DEMO Customer A founderdemo a' — the trailing ' a' is the customer audit's finding 3 (the
--      Account name field drops keystrokes; typing "audit" left one 'a') saved onto the demo row.
--      The row is the fixture (ZZ DEMO, @example.invalid); the name is put back. The form defect is
--      the customer-portal builder's.
--
-- NOT CHANGED, and why: fn_supplier_collaboration_incident (event detail 'rfq'), fn_contact_timeline
-- ('RFQ ' label) and v_conversation_message ('Quotation review - job …') still print the uuid prefix.
-- Those are the CEO's internal timeline labels, not something a customer or supplier receives; they
-- move to fn_job_no when their own files are next touched. Customer notices built in SQL already use
-- 'RFQ-' || rfq_no (the_quotation_alert_reads_the_committed_state_and_nothing_else.sql) — unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/one_job_number_on_every_portal_document_and_notice.sql --apply --ddl

begin;

create or replace function public.fn_job_no(p_inquiry uuid)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select i.rfq_no::text from public.inquiries i where i.id = p_inquiry
$fn$;
comment on function public.fn_job_no(uuid) is
  'The one public job number of an inquiry (inquiries.rfq_no as text), printed on both portals, every document and every notice. Seat: sales_engineer, 21 Sep 2026.';
revoke execute on function public.fn_job_no(uuid) from public, anon, authenticated;

create or replace function public.fn_notifications_speak_the_recipients_language()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_all text; v_ar boolean; v_latin boolean; c public.notification_copy; v_ref text;
begin
  if coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  if new.lang is null or new.lang not in ('en', 'ar') then
    new.lang := coalesce(public.fn_registered_locale(new.to_role, null, new.lead_id, new.to_email), 'en');
  end if;
  v_all := coalesce(new.subject, '') || ' ' || coalesce(new.body, '');
  v_ar := v_all ~ '[؀-ۿ]';
  -- coalesce: fn_language_mismatch answers null for pure Arabic, and a null here would make the
  -- pure-Arabic-to-an-English-recipient case below evaluate to null and never be corrected.
  v_latin := coalesce(public.fn_language_mismatch('ar', v_all) like 'English inside Arabic%', false)
             or (not v_ar and v_all ~ '[A-Za-z]{2,}');
  if (new.lang = 'ar' and not v_ar) or (new.lang = 'en' and v_ar and not v_latin) then
    select * into c from public.notification_copy where type = new.type;
    if not found then select * into c from public.notification_copy where type = '*'; end if;
    if found then
      -- 21 Sep 2026: the reference is the job number (inquiries.rfq_no), the same one both portals print.
      v_ref := case when new.inquiry_id is not null
                    then 'QD-' || public.fn_job_no(new.inquiry_id) end;
      new.subject := case when new.lang = 'ar' then c.subject_ar else c.subject_en end;
      new.body := replace(case when new.lang = 'ar' then c.body_ar else c.body_en end,
                          ' {ref}', coalesce(' ' || v_ref, ''));
      new.html := null;   -- a pre-rendered html copy would still carry the old language
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_speak_the_recipients_language() from public, anon, authenticated;

-- The demo customer's name, minus the keystroke the audit's form defect left on it (see header, 4).
update public.customers
   set full_name = 'ZZ DEMO Customer A founderdemo'
 where email = 'qd-founderdemo-cust1@example.invalid'
   and full_name = 'ZZ DEMO Customer A founderdemo a';

commit;

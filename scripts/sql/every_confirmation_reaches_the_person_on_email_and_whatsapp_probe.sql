-- PROBE: EVERY CONFIRMATION REACHES THE PERSON ON EMAIL AND WHATSAPP.
--
-- Seat: customer_support. 3 Nov 2026. Pure probe: no DDL, never applied. apply-on-merge runs it after
-- every_confirmation_reaches_the_person_on_email_and_whatsapp.sql in one rolled-back transaction, then alone after the
-- apply. It always raises, so every row below is rolled back. It cannot reach a person: every subject it creates is a
-- ZZ DEMO customer at @example.invalid on a +971 50 000 00xx demo mobile, so zzzz_notifications_demo_capture marks every
-- queued row 'suppressed' before send_outbox or send_whatsapp could claim it; no real customer, lead or quote is read
-- or written, and pg_net sends only committed requests.
--
-- PROBE OK only if
--   1. an Arabic customer's first terms acceptance queues ONE customer_account_active email, in Arabic, with its dedupe
--      key, and a WhatsApp twin that is recorded 'skipped' with the reason (their 'other' number is not verified);
--      accepting again (cleared, then set) adds nothing;
--   2. an English customer whose verified mobile is their WhatsApp gets the English email and a twin addressed to it;
--   3. a supplier_approved email to an address with no WhatsApp answer gets a recorded 'skipped' twin, while a
--      non-confirmation type to the same address still gets no twin (fanout unchanged for it);
--   4. a customer's invoice_ready email (written as its real writer writes it: status left to the 'pending' default)
--      and its twin are both held ~10 minutes (not_before), the attach trigger exists for a waiting email row with a
--      quote, and the reveal receipt is not held but still gets its twin;
--   5. db.internal may call reveal_invoice, and anon / authenticated can run none of the new routines.
do $probe$
declare
  t text := substr(md5(clock_timestamp()::text), 1, 8);
  e_ar text := 'qd-probe-' || t || '-ar@example.invalid';
  e_en text := 'qd-probe-' || t || '-en@example.invalid';
  e_sup text := 'qd-probe-' || t || '-sup@example.invalid';
  c_ar uuid; c_en uuid; n int; w record; fails text := ''; nb timestamptz; nbw timestamptz;
begin
  -- 1. Arabic customer, WhatsApp on another number that is not verified
  -- (customers_whatsapp_phone_is_verified keeps an unverified 'other' number off the row: answered 'other', none confirmed yet)
  insert into public.customers (email, full_name, phone, email_verified, phone_verified, locale, whatsapp_opt, date_of_birth)
  values (e_ar, 'ZZ DEMO Probe Customer AR', '+971500000091', true, true, 'ar', 'other', '1990-01-01')
  returning id into c_ar;
  update public.customers set tos_accepted_at = now(), tos_version = 'probe' where id = c_ar;
  select count(*) into n from public.notifications where type = 'customer_account_active' and channel = 'email' and to_email = e_ar
     and lang = 'ar' and subject like '%QuotesDone%' and body ~ '[؀-ۿ]' and dedupe_key = 'customer_account_active:' || c_ar
     and requested_by = 'customer_support';
  if n <> 1 then fails := fails || ' 1:email(' || n || ')'; end if;
  select status, last_error into w from public.notifications where type = 'customer_account_active' and channel = 'whatsapp' and to_email = e_ar;
  if w.status is distinct from 'skipped' or coalesce(w.last_error, '') not like '%no confirmed WhatsApp number%' then
    fails := fails || ' 1:twin(' || coalesce(w.status, 'none') || ')'; end if;
  update public.customers set tos_accepted_at = null where id = c_ar;
  update public.customers set tos_accepted_at = now() where id = c_ar;
  if (select count(*) from public.notifications where type = 'customer_account_active' and channel = 'email' and to_email = e_ar) <> 1 then
    fails := fails || ' 1:twice'; end if;

  -- 2. English customer, WhatsApp on the verified mobile
  insert into public.customers (email, full_name, phone, email_verified, phone_verified, locale, whatsapp_opt, date_of_birth)
  values (e_en, 'ZZ DEMO Probe Customer EN', '+971500000093', true, true, 'en', 'same', '1990-01-01')
  returning id into c_en;
  update public.customers set tos_accepted_at = now(), tos_version = 'probe' where id = c_en;
  if (select count(*) from public.notifications where type = 'customer_account_active' and channel = 'email' and to_email = e_en
        and lang = 'en' and subject = 'Your QuotesDone account is active' and status = 'suppressed') <> 1 then
    fails := fails || ' 2:email'; end if;
  if (select count(*) from public.notifications where type = 'customer_account_active' and channel = 'whatsapp' and to_email = e_en
        and to_phone is not null and status = 'suppressed') <> 1 then
    fails := fails || ' 2:twin'; end if;

  -- 3. supplier_approved to an address with no WhatsApp answer, and a non-confirmation to the same address
  insert into public.notifications (type, channel, to_email, to_role, subject, body, status, requested_by)
  values ('supplier_approved', 'email', e_sup, 'supplier', 'ZZ DEMO probe approval', 'ZZ DEMO probe', 'queued', 'sales_engineer'),
         ('new_inquiry', 'email', e_sup, 'supplier', 'ZZ DEMO probe inquiry', 'ZZ DEMO probe', 'queued', 'sales_engineer');
  if (select count(*) from public.notifications where type = 'supplier_approved' and channel = 'whatsapp' and to_email = e_sup
        and status = 'skipped' and last_error like '%no confirmed WhatsApp number%') <> 1 then
    fails := fails || ' 3:approved_twin'; end if;
  if exists (select 1 from public.notifications where type = 'new_inquiry' and channel = 'whatsapp' and to_email = e_sup) then
    fails := fails || ' 3:other_type_twinned'; end if;

  -- 4. "Your invoice is ready" is held for its invoice, email and twin alike. Written as its real writer writes it
  --    (fn_sales_engineer_answers_reveal_invoice: no status, so the column default 'pending'; the channel left null).
  insert into public.notifications (type, to_email, to_role, quote_id, subject, body, lang)
  values ('invoice_ready', e_en, 'customer', gen_random_uuid(), 'Your invoice is ready', 'ZZ DEMO probe', 'en');
  select not_before into nb from public.notifications where type = 'invoice_ready' and coalesce(channel, 'email') = 'email' and to_email = e_en;
  select not_before into nbw from public.notifications where type = 'invoice_ready' and channel = 'whatsapp' and to_email = e_en;
  if nb is null or nb < now() + interval '9 minutes' or nb > now() + interval '11 minutes' then fails := fails || ' 4:email_hold'; end if;
  if nbw is null or nbw < now() + interval '9 minutes' then fails := fails || ' 4:twin_hold'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'z30_invoice_ready_asks_for_its_invoice' and tgenabled = 'O'
                  and pg_get_triggerdef(oid) like '%''queued''%''pending''%' and pg_get_triggerdef(oid) like '%quote_id IS NOT NULL%') then
    fails := fails || ' 4:attach_trigger'; end if;
  -- the receipt itself is not held any more than it was
  insert into public.notifications (type, channel, to_email, to_role, quote_id, subject, body, status, requested_by)
  values ('reveal_receipt', 'email', e_en, 'customer', gen_random_uuid(), 'Reveal confirmed: ZZ DEMO probe', 'ZZ DEMO probe', 'queued', 'sales_engineer');
  if (select not_before from public.notifications where type = 'reveal_receipt' and channel = 'email' and to_email = e_en) is not null then
    fails := fails || ' 4:receipt_held'; end if;
  if (select count(*) from public.notifications where type = 'reveal_receipt' and channel = 'whatsapp' and to_email = e_en) <> 1 then
    fails := fails || ' 4:receipt_twin'; end if;

  -- 5. the credential and the grants
  if not exists (select 1 from public.internal_credential where context = 'db.internal' and active and 'reveal_invoice' = any(scope)) then
    fails := fails || ' 5:scope'; end if;
  if has_function_privilege('anon', 'public.fn_customer_account_active_compose(public.customers)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_customer_account_active_compose(public.customers)', 'execute')
     or has_function_privilege('anon', 'public.fn_customer_account_active_notice()', 'execute')
     or has_function_privilege('anon', 'public.fn_invoice_ready_waits_for_its_invoice()', 'execute')
     or has_function_privilege('anon', 'public.fn_invoice_ready_asks_for_its_invoice()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_invoice_ready_asks_for_its_invoice()', 'execute') then
    fails := fails || ' 5:grants'; end if;

  -- nothing the probe wrote may be sendable
  if exists (select 1 from public.notifications where to_email in (e_ar, e_en, e_sup) and status in ('queued', 'pending', 'sending')) then
    fails := fails || ' X:sendable_row'; end if;

  raise exception 'CHK<<%>>', case when fails = ''
    then 'PROBE OK ar_email=1 ar_twin=skipped en_twin=addressed supplier_twin=skipped other_type_twin=none invoice_ready_hold='
         || to_char(nb - now(), 'MI:SS') || ' receipt_hold=none'
    else 'PROBE FAILED:' || fails end;
end $probe$;

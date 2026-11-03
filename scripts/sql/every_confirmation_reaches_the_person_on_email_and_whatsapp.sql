-- EVERY CONFIRMATION REACHES THE PERSON ON EMAIL AND WHATSAPP: THE ACCOUNT, THE SUPPLIER ACCOUNT, THE INVOICE.
--
-- Seat: customer_support (the only sender on email and WhatsApp). 3 Nov 2026.
--
-- THE FOUNDER, 3 Nov 2026: after a customer registers (OTP + form) "he gets a confirmation on email and whatsapp that his
-- account is active"; after a supplier "finish the registration process fully and gets a confirmation email and whatsapp
-- message for that"; after a customer pays the reveal fee on Stripe "an invoice from our app is shared on email and
-- whatsapp with the customer". Nothing in the app is one-way: every message is tracked to delivery.
--
-- MEASURED ON PRODUCTION (3 Nov 2026 13:27 UTC):
--   * CUSTOMER: nothing confirms an account. public.fn_customer_welcome was dropped on 7 Sep 2026
--     (the_customer_welcome_the_product_never_sent.sql). 19 customers have accepted the terms (the last step of sign-up,
--     kyc accept_terms, which refuses a first acceptance until the WhatsApp question is answered), 15 of them in the last
--     30 days; no routine and no edge function writes them a notice when they do.
--   * SUPPLIER: the activation IS confirmed, by trg_sales_engineer_tells_the_supplier_he_is_approved (supplier_approved,
--     "You are verified on QuotesDone", on every path that sets approval_status = 'approved'), and trg_wa_fanout twins it
--     to the confirmed number on the approved supplier_account_notice template. But an approved FIRST save in
--     supplier_api save_profile ALSO sent registration_received "Your QuotesDone supplier account is active": two emails
--     and two WhatsApp messages for one activation (that code change is in the same PR). Only 1 lead has ever had
--     registration_submitted_at (lead 126512, the 21 Sep founder demo; its 1 email + 2 WhatsApp registration_received
--     rows are the only ones ever written, all captured as demo); no real supplier has registered yet, and the e2e walks'
--     suppliers are approved by fixture paths that never set registration_submitted_at, which is why there are so few.
--     send_whatsapp mapped registration_received to no template, so its twin would have been skipped "no WhatsApp
--     template mapping" (fixed in send_whatsapp in the same PR).
--   * INVOICE: two notices follow a paid reveal. The reveal.paid handoff's reveal_receipt (unlocked contact, the 5-day
--     clock) and, once stripe_webhook's captureInvoice files the Stripe invoice (doc_path invoices/...),
--     fn_accountant_files_reveal_invoice's invoice.issued handoff, answered by fn_sales_engineer_answers_reveal_invoice
--     with invoice_ready "Your invoice is ready". Neither carries the invoice: invoice_ready only says it is in the
--     account, and its WhatsApp twin had no template mapping (skipped "no WhatsApp template mapping"). The QuotesDone
--     invoice is rendered only when the customer presses "Invoice" in the portal (reveal_invoice, signed-in path).
--     invoice_ready is the carrier chosen here: it exists exactly when the Stripe invoice NUMBER is known (the receipt
--     is written before captureInvoice runs, so an invoice rendered for it would print "see payment ref."), and
--     carrying it there sends no second invoice notice.
--   * ALL OF THEM: fn_wa_fanout makes no WhatsApp twin when the person answered the WhatsApp question but the number is
--     not confirmed ('other' not yet verified, or 'same' with an unverified mobile): no row, no reason, silent.
--
-- WHAT THIS CHANGES
--   1. fn_customer_account_active_compose + trg z40_customer_account_active_notice: when a customer's FIRST terms
--      acceptance is recorded (customers.tos_accepted_at null -> set), customer_support queues one email
--      (customer_account_active, the customer's registered language, written by code: no model) through the outbox.
--      fn_wa_fanout twins it to the confirmed number; send_whatsapp sends it on the customer_account_active template.
--      A refused address (fn_seat_clock_refusal: no valid address, founder inbox, suppression, dead domain) is recorded
--      on agent_actions with its reason, never silent; any error is recorded and never refuses the acceptance itself.
--      Once per customer: dedupe_key customer_account_active:<customer id>.
--   2. fn_wa_fanout: for the confirmations (customer_account_active, supplier_approved, reveal_receipt, invoice_ready) a
--      twin is ALWAYS written; with no confirmed number a03_notifications_whatsapp_goes_to_a_confirmed_number records it
--      as 'skipped' with the reason. Every other type is unchanged (an unanswered account still gets no twin).
--   3. a08_invoice_ready_waits_for_its_invoice holds a customer's invoice_ready rows (email and WhatsApp) ten minutes
--      (not_before); z30_invoice_ready_asks_for_its_invoice asks reveal_invoice (action 'attach', the database's internal
--      credential, through pg_net after commit) to render the QuotesDone invoice in the notice's language and attach the
--      PDF reference to both rows: send_outbox attaches the file to the email, send_whatsapp signs a 7-day link for the
--      customer_reveal_invoice template at send time (no link is stored). Both are released at once. If that fails the
--      rows go at the end of the hold as the plain notice; reveal_invoice logs why on agent_runs, a refused request is
--      filed on agent_actions.
--   4. db.internal's credential scope gains reveal_invoice, the one function it now calls for this.
--
-- WHAT THIS DOES NOT CHANGE: who approves a supplier, the supplier_approved and receipt copy, the invoice_ready copy
-- (only the attached-invoice line is appended once the PDF is attached), the daily WhatsApp cap, the demo capture, the
-- outbox. No table is created. NOT COVERED, said plainly: a paid reveal whose Stripe invoice PDF never lands (captureInvoice
-- logs "INVOICE PDF NOT DOWNLOADED") files no invoice.issued, so no invoice_ready is written and nothing here runs; the
-- customer still has the portal's Invoice button, and stripe_webhook's re-delivery repair path is unchanged. A confirmation
-- twin skipped for an unconfirmed number is not re-sent if the number is confirmed later.
--
-- LOCKS: the triggers are created with CREATE OR REPLACE TRIGGER (SHARE ROW EXCLUSIVE, no ACCESS EXCLUSIVE drop on the
-- hot notifications and customers tables) under a 3-second lock_timeout, so a blocked apply fails fast and is re-run.
--
-- prevented by: scripts/sql/every_confirmation_reaches_the_person_on_email_and_whatsapp_probe.sql (rehearsed with this
-- file in one rolled-back transaction), send_whatsapp/confirmations.test.ts, reveal_invoice/attach.test.ts,
-- supplier_api/one_confirmation_per_activation.test.ts.

set local lock_timeout = '3s';

-- 1. THE CUSTOMER'S ACCOUNT IS ACTIVE ------------------------------------------------------------------------------------
create or replace function public.fn_customer_account_active_compose(p public.customers)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_site text; v_link text; v_name text := nullif(btrim(coalesce(p.full_name, '')), '');
  v_ar boolean := public.fn_registered_locale('customer', p.id, null, p.email) = 'ar';
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/me';
  if v_ar then
    return jsonb_build_object('lang', 'ar', 'link', v_link,
      'subject', 'أصبح حسابكم على QuotesDone مفعّلًا',
      'body', coalesce('السادة/ ' || v_name || ' المحترمين،', 'السادة المحترمين،') || E'\n\n'
        || 'مرحبًا بكم في QuotesDone. أصبح حسابكم مفعّلًا الآن.' || E'\n\n'
        || 'يمكنكم نشر طلبكم الأول في أي وقت: صِفوا ما تحتاجون إليه، ويرسل إليكم موردون موثّقون في الإمارات عروض أسعارهم لتقارنوا بينها.' || E'\n\n'
        || 'حسابكم: ' || v_link || E'\n\n'
        || 'للمساعدة، يسعدنا ردّكم على هذه الرسالة أو مراسلتنا عبر واتساب.' || E'\n\n'
        || 'مع أطيب التحيات،' || E'\n' || 'فريق دعم العملاء في QuotesDone');
  end if;
  return jsonb_build_object('lang', 'en', 'link', v_link,
    'subject', 'Your QuotesDone account is active',
    'body', coalesce('Dear ' || v_name || ',', 'Dear customer,') || E'\n\n'
      || 'Welcome to QuotesDone. Your account is now active.' || E'\n\n'
      || 'You can post your first request at any time: describe what you need, and verified suppliers in the UAE send you their quotes to compare.' || E'\n\n'
      || 'Your account: ' || v_link || E'\n\n'
      || 'Need help? Reply to this e-mail or message us on WhatsApp.' || E'\n\n'
      || 'Kind regards,' || E'\n' || 'QuotesDone Customer Support');
end
$fn$;
revoke execute on function public.fn_customer_account_active_compose(public.customers) from public, anon, authenticated;

create or replace function public.fn_customer_account_active_notice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_to text := lower(btrim(coalesce(new.email, ''))); v_why text; m jsonb;
begin
  v_why := public.fn_seat_clock_refusal(public.fn_is_demo_email(v_to), v_to, 'customer_account_active');
  if v_why is null then
    m := public.fn_customer_account_active_compose(new);
    -- Queued directly by its own seat: z90_every_send_is_tracked files the delivery and tracks it to delivery.
    insert into public.notifications (type, kind, channel, to_email, to_role, subject, body, lang, status,
                                      requested_by, sender, dedupe_key)
    values ('customer_account_active', 'customer_support_customer_account_active', 'email', v_to, 'customer',
            m->>'subject', m->>'body', m->>'lang', 'queued', 'customer_support', 'customer_support',
            'customer_account_active:' || new.id)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
  else
    -- NOT SENT IS RECORDED, NEVER SILENT.
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('customer_support', 'customer_account_active_notice', 'skipped', 'low',
            left('Account-active notice not sent (' || v_why || ')', 200),
            jsonb_build_object('customer_id', new.id, 'to_email', nullif(v_to, ''), 'not_sent', v_why),
            'customers', new.id::text);
  end if;
  return null;
exception when others then
  -- The acceptance stands whatever happens here; the failure is on the record for customer_support. The record is
  -- itself guarded: if even that insert fails, a warning is all that is left, never a refused acceptance.
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('customer_support', 'customer_account_active_notice', 'failed', 'medium',
            left('Account-active notice failed for customer ' || new.id, 200),
            jsonb_build_object('customer_id', new.id, 'error', left(sqlerrm, 500)), 'customers', new.id::text);
  exception when others then
    raise warning 'fn_customer_account_active_notice: customer % not told and not recorded: %', new.id, sqlerrm;
  end;
  return null;
end
$fn$;
revoke execute on function public.fn_customer_account_active_notice() from public, anon, authenticated;

create or replace trigger z40_customer_account_active_notice
  after update of tos_accepted_at on public.customers
  for each row when (old.tos_accepted_at is null and new.tos_accepted_at is not null)
  execute function public.fn_customer_account_active_notice();

-- 2. A CONFIRMATION'S WHATSAPP TWIN IS ALWAYS WRITTEN --------------------------------------------------------------------
create or replace function public.fn_wa_fanout()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_dest text; v_opt text;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(new.channel, 'email') <> 'email' or new.to_email is null or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is null then
    if new.to_role = 'customer' then
      select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(new.to_email) limit 1;
    else
      select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
    end if;
    -- 'none' is recorded (a03 marks the twin skipped with the reason); unanswered makes no twin.
    -- 3 Nov 2026 (customer_support): the confirmations the founder asked for on both channels always get their twin,
    -- so a missing confirmed number is recorded by a03 with its reason instead of leaving no trace.
    if v_opt is distinct from 'none'
       and new.type not in ('customer_account_active', 'supplier_approved', 'reveal_receipt', 'invoice_ready') then return new; end if;
  end if;
  insert into public.notifications (type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_dest, new.lead_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return new;
end $function$;

-- 3. "YOUR INVOICE IS READY" WAITS FOR ITS INVOICE, AND ASKS FOR IT -------------------------------------------------------
-- fn_sales_engineer_answers_reveal_invoice inserts invoice_ready with no status, so it arrives 'pending' (the column
-- default); fn_wa_fanout writes the twin 'queued'. Both are sendable states (fn_notifications_claim), so both are held,
-- and a03's 'skipped' twin or zzzz's 'suppressed' demo row is not.
create or replace function public.fn_invoice_ready_waits_for_its_invoice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- Ten minutes is the ceiling, not the wait: reveal_invoice releases both rows the moment the invoice is attached.
  if coalesce(new.status, 'pending') in ('queued', 'pending') then
    new.not_before := greatest(coalesce(new.not_before, now()), now() + interval '10 minutes');
  end if;
  return new;
end
$fn$;
revoke execute on function public.fn_invoice_ready_waits_for_its_invoice() from public, anon, authenticated;

create or replace trigger a08_invoice_ready_waits_for_its_invoice
  before insert on public.notifications
  for each row when (new.type = 'invoice_ready' and new.to_role = 'customer' and new.quote_id is not null and new.attachments is null)
  execute function public.fn_invoice_ready_waits_for_its_invoice();

create or replace function public.fn_invoice_ready_asks_for_its_invoice()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_secret text; v_ref text;
begin
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  if nullif(btrim(coalesce(v_secret, '')), '') is null then raise exception 'app_secrets.cred_db_internal is missing'; end if;
  v_ref := public.qd_project_ref();
  -- pg_net sends only once this transaction commits, so reveal_invoice reads the notice and its twin as written.
  perform net.http_post(
    'https://' || v_ref || '.supabase.co/functions/v1/reveal_invoice',
    jsonb_build_object('__secret', v_secret, 'action', 'attach', 'quote_id', new.quote_id),
    '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  return null;
exception when others then
  -- The notice is never refused for this: it goes at the end of its hold without the invoice, and the failure is filed
  -- where customer_support reads its work. That record is guarded too, so this trigger can never fail the insert.
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('customer_support', 'invoice_ready_attachment', 'failed', 'medium',
            left('The invoice could not be requested for notification ' || new.id, 200),
            jsonb_build_object('notification_id', new.id, 'quote_id', new.quote_id, 'error', left(sqlerrm, 500)),
            'notifications', new.id::text);
  exception when others then
    raise warning 'fn_invoice_ready_asks_for_its_invoice: notification % not requested and not recorded: %', new.id, sqlerrm;
  end;
  return null;
end
$fn$;
revoke execute on function public.fn_invoice_ready_asks_for_its_invoice() from public, anon, authenticated;

create or replace trigger z30_invoice_ready_asks_for_its_invoice
  after insert on public.notifications
  for each row when (new.type = 'invoice_ready' and new.to_role = 'customer' and coalesce(new.channel, 'email') = 'email'
                     and new.status in ('queued', 'pending') and new.quote_id is not null and new.attachments is null)
  execute function public.fn_invoice_ready_asks_for_its_invoice();

-- 4. THE DATABASE MAY CALL reveal_invoice --------------------------------------------------------------------------------
update public.internal_credential
   set scope = array_append(scope, 'reveal_invoice')
 where context = 'db.internal' and active and not ('reveal_invoice' = any(scope));

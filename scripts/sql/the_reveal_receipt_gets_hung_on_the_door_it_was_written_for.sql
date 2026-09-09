-- THE REVEAL RECEIPT GETS HUNG ON THE DOOR IT WAS WRITTEN FOR.
--
-- `trg_reveal_receipt()` is complete, correct, and attached to NOTHING. Measured: the only triggers
-- on public.transactions are trg_emit_refund_requested_tx, trg_event_transaction and
-- trg_reveal_window_b. The function exists, was updated as recently as today, and no trigger names
-- it.
--
-- WHAT THAT COSTS. stripe_webhook deliberately DELETED its own inline supplier email in favour of
-- this trigger, and its comment says so: "All four reveal messages (email + WhatsApp to both
-- parties) are queued by trg_reveal_receipt on transactions.revealed_at — the one door every reveal
-- goes through." So today a customer pays a real AED reveal fee on a live Stripe key and:
--   the customer is told nothing,
--   the supplier is never told a customer paid to see them — while the supplier's 5-working-day
--   response clock starts running against them, and failing it costs them the fee plus AED 250
--   plus 9% interest,
-- and the webhook logs status 'ok'. It has a guard for "fewer than 2 reveal messages were queued"
-- that would fire on every single payment, into a log nobody reads.
--
-- This is the clearest case in the estate of a finished capability with no entry point, and it sits
-- on the only revenue event the business has.
--
-- ── AND THE COPY IS OUT OF DATE, WHICH IS WHY THIS IS NOT A ONE-LINE CREATE TRIGGER ──
--
-- Both messages tell the reader that the FOUNDER decides the refund:
--   customer: "the case goes to our founder for a final call"
--   supplier: "our founder makes a final call, the customer is refunded"
--
-- The founder superseded that on 8 September 2026 — refunds are the CEO's — and the database has
-- enforced it since: z00_refund_ceo_approval_only and z05_refund_execution_requires_ceo_approval
-- both require a ceo_approval row, and company_policy_decision now records every_refund_is_the_ceos.
-- Attaching the trigger unchanged would have started telling every paying customer and every
-- revealed supplier something the platform stopped doing a day earlier. A stale sentence nobody
-- reads is harmless; the same sentence emailed to the two parties to a transaction is not.
--
-- The mechanism is untouched — window, chase day, refund and recovery are all as they were, read
-- from pricing_config. Only the name of who decides changes, and it changes to what the triggers
-- actually enforce.

create or replace function public.trg_reveal_receipt()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  cemail  text;
  semail  text;
  comp    text;
  inq     record;
  v_window int; v_chase int;
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. An emit into the kernel source table stood here that
    -- declared the reveal payment the start of a W16 kernel run. The kernel is deleted; nothing
    -- consumed the event. The two receipts below (customer, supplier) and the WhatsApp fan-out
    -- they feed are the real work of this trigger and are untouched.

    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name, email into comp, semail from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    -- 6 Sep 2026: both receipts state the ladder from pricing_config (window 5, chase 3), one source.
    select refund_window_working_days, chase_after_working_days into v_window, v_chase
      from public.pricing_config order by id limit 1;
    v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

    -- 1. customer email
    if cemail is not null then
      insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, status)
      values ('reveal_receipt', cemail, 'customer', NEW.inquiry_id, NEW.quote_id,
              'Reveal confirmed — ' || coalesce(comp, 'supplier'),
              'You have unlocked ' || coalesce(comp, 'the supplier') || '''s contact details'
                || coalesce(' for: ' || left(inq.summary, 80), '')
                || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
                || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
                || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded your reveal fee is refunded in full. '
                || 'Banks usually take 7-14 working days to show a refund. You can also open the request and Report an issue at any time.',
              'queued');
    end if;

    -- 2. supplier email (moved here from stripe_webhook)
    if semail is not null and semail like '%@%' then
      insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, status)
      values ('quote_accepted', semail, 'supplier', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id,
              'A customer revealed your quote on QuotesDone',
              'A customer paid to reveal your contact for: ' || coalesce(inq.summary, '')
                || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
                || ' working days of the reveal. If you have not responded after ' || v_chase::text
                || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
                || ' our chief executive decides the case, the customer is refunded, and the reveal fee plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
              'queued');
    end if;

    -- 3 and 4: the WhatsApp to each opted-in party is queued by trg_wa_fanout from the two email rows above.
  end if;
  return NEW;
end
$fn$;

-- ── HANG IT ON THE DOOR ─────────────────────────────────────────────────────────────────────────
-- INSERT covers the normal path (stripe_webhook inserts the transaction already revealed). UPDATE OF
-- revealed_at covers a sale recorded first and revealed after. The function's own guard
-- (TG_OP='INSERT' or OLD.revealed_at is null) makes a second UPDATE a no-op, so a re-delivery or a
-- hand repair cannot send a second receipt.
drop trigger if exists z20_reveal_receipt on public.transactions;
create trigger z20_reveal_receipt
  after insert or update of revealed_at on public.transactions
  for each row execute function public.trg_reveal_receipt();

-- ── PROVE IT ON A SYNTHETIC SALE THAT REMOVES ITSELF ────────────────────────────────────────────
do $do$
declare
  v_cust uuid; v_lead bigint; v_tx uuid; v_n int; v_again int;
  v_cust_mail text; v_supp_mail text; v_body text;
begin
  -- POSITIVE CONTROL: the trigger must be attached at all.
  if not exists (select 1 from pg_trigger where tgrelid='public.transactions'::regclass
                   and tgname='z20_reveal_receipt' and not tgisinternal) then
    raise exception 'the trigger did not attach';
  end if;

  select id into v_lead from public.leads where email is not null and email like '%@%' limit 1;
  if v_lead is null then raise exception 'POSITIVE CONTROL FAILED: no lead with an email to stand in as the supplier'; end if;

  insert into public.customers (id, email, email_verified, full_name)
  values (gen_random_uuid(), 'zz-demo-reveal-probe@example.invalid', true, 'ZZ DEMO reveal probe')
  returning id into v_cust;

  v_tx := gen_random_uuid();
  insert into public.transactions (id, customer_id, supplier_id, revealed_at)
  values (v_tx, v_cust, v_lead, now());

  select count(*) into v_n from public.notifications
   where quote_id is null and to_email in ('zz-demo-reveal-probe@example.invalid',
         (select email from public.leads where id = v_lead))
     and created_at > now() - interval '1 minute';

  select body into v_cust_mail from public.notifications
   where to_email = 'zz-demo-reveal-probe@example.invalid' and type = 'reveal_receipt'
   order by id desc limit 1;
  select body into v_supp_mail from public.notifications
   where type = 'quote_accepted' and lead_id = v_lead and created_at > now() - interval '1 minute'
   order by id desc limit 1;

  if v_cust_mail is null then raise exception 'the customer was not told'; end if;
  if v_supp_mail is null then raise exception 'the supplier was not told'; end if;

  -- THE COPY CORRECTION, asserted rather than assumed.
  if v_cust_mail ilike '%founder%' or v_supp_mail ilike '%founder%' then
    raise exception 'a receipt still tells the reader the founder decides the refund';
  end if;
  if v_cust_mail not ilike '%chief executive%' then
    raise exception 'the customer receipt does not say who decides';
  end if;

  -- IDEMPOTENCE: a re-delivery or repair must not send a second receipt.
  update public.transactions set revealed_at = now() where id = v_tx;
  select count(*) into v_again from public.notifications
   where type in ('reveal_receipt','quote_accepted')
     and created_at > now() - interval '1 minute'
     and (to_email = 'zz-demo-reveal-probe@example.invalid' or lead_id = v_lead);
  if v_again > 2 then
    raise exception 'a second reveal sent % messages in total — the guard does not hold', v_again;
  end if;

  -- CLEAN UP. These are queued, never sent: send_outbox is not called from here.
  delete from public.notifications
   where created_at > now() - interval '2 minutes'
     and (to_email = 'zz-demo-reveal-probe@example.invalid'
          or (type = 'quote_accepted' and lead_id = v_lead));
  delete from public.transactions where id = v_tx;
  delete from public.customers where id = v_cust;

  if exists (select 1 from public.transactions where id = v_tx)
     or exists (select 1 from public.customers where id = v_cust)
     or exists (select 1 from public.notifications where to_email = 'zz-demo-reveal-probe@example.invalid') then
    raise exception 'the probe left rows behind';
  end if;

  raise notice 'RECEIPT HUNG. A reveal now queues % message(s) — the customer and the supplier — a second reveal adds none, and neither message says the founder decides the refund any more. Probe rows removed.', v_n;
end
$do$;

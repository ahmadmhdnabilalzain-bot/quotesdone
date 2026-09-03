-- THE REVEAL NOTIFIES BOTH PARTIES, ON BOTH CHANNELS, FROM ONE DOOR (3 Sep 2026).
--
-- Founder, 19 Aug 2026: once the reveal fee is paid, QuotesDone automatically sends an email to BOTH
-- the customer and the supplier confirming the selection, AND a WhatsApp to BOTH, on the numbers each
-- registered with. Measured the same day: the product sent ONE email, to the customer, from
-- trg_reveal_receipt. Later the Stripe webhook grew a second email (quote_accepted, to the supplier)
-- in its own code path — so a reveal recorded by any other path (a fixture, a future promo reveal, a
-- manual correction) told the supplier nothing. The full-funnel rehearsal (3 Sep) measured exactly
-- two emails and no WhatsApp.
--
-- ONE DOOR. A reveal IS the transition of transactions.revealed_at from null to a value, and that is
-- where both EMAILS are queued now: the customer's (unchanged) and the supplier's (moved here from
-- stripe_webhook, same wording). The WHATSAPP half is not written here twice over: trg_wa_fanout on
-- notifications already mirrors every email row to a WhatsApp row when that party registered a number
-- AND opted in (customers.wa_optin / leads.wa_optin — opt-in by law and by Meta's policy). The first
-- cut of this file inserted its own two WhatsApp rows as well and the rehearsal measured SIX messages;
-- the fan-out is the one mechanism, so this trigger queues emails and lets it do the rest. What the
-- fan-out needed and lacked was a template for the supplier's side: send_whatsapp now maps
-- quote_accepted to supplier_quote_accepted, registered through wa_template_setup.
--
-- The kernel emit (K20, W16 start) is untouched and still fires exactly once, inside the same branch.
-- trg_reveal_receipt had no canonical file in scripts/sql; this file is it from here on.

create or replace function public.trg_reveal_receipt()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  cemail  text;
  semail  text;
  comp    text;
  inq     record;
begin
  if NEW.revealed_at is not null and (TG_OP = 'INSERT' or OLD.revealed_at is null) then
    -- K20 cutover. The reveal payment is the declared start of W16. Placed INSIDE the branch that
    -- tests revealed_at, so it fires once when the reveal actually happens and not on every update.
    perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_reveal_receipt_a', jsonb_build_object(
      'source_ref', NEW.id::text,
      'raw_payload', jsonb_build_object(
        'provider_event_id', coalesce(nullif(NEW.payment_ref, ''), NEW.id::text),
        'transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text,
        'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));

    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name, email into comp, semail from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;

    -- 1. customer email (unchanged wording)
    if cemail is not null then
      insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, status)
      values ('reveal_receipt', cemail, 'customer', NEW.inquiry_id, NEW.quote_id,
              'Reveal confirmed — ' || coalesce(comp, 'supplier'),
              'You have unlocked ' || coalesce(comp, 'the supplier') || '''s contact details'
                || coalesce(' for: ' || left(inq.summary, 80), '')
                || '. You can now message them directly in the app. If they do not respond within 72 hours, open the request and Report an issue to request a refund of your reveal fee.',
              'queued');
    end if;

    -- 2. supplier email (moved here from stripe_webhook; same wording)
    if semail is not null and semail like '%@%' then
      insert into public.notifications (type, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, status)
      values ('quote_accepted', semail, 'supplier', NEW.supplier_id, NEW.inquiry_id, NEW.quote_id,
              'A customer revealed your quote on QuotesDone',
              'A customer paid to reveal your contact for: ' || coalesce(inq.summary, '')
                || '. Please respond promptly — if you do not respond within 3 working days the customer may be refunded.',
              'queued');
    end if;

    -- 3 and 4: the WhatsApp to each opted-in party is queued by trg_wa_fanout from the two email rows above.
  end if;
  return NEW;
end
$function$;

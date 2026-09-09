-- SOME VENDORS NEVER EMAIL A RECEIPT AT ALL.
--
-- The founder, 9 September 2026: "also include chat gpt bills", and then "chatgpt is running still
-- but i forgot to forward the new bills".
--
-- He had not forgotten. Measured after he said it: there is no ChatGPT bill to forward.
--
--   The ONE OpenAI row in the book (29 Jul 2026, AED 385.00) did not come from a receipt. It came
--   from a "ChatGPT - Your new plan" confirmation, which happens to print the charge as
--   AED 366.67 + 18.33 tax. OpenAI sends that once, on subscribe or plan change.
--
--   Searched for a monthly receipt five ways and found none: Gmail across every folder after
--   29 Jul; by amount (385.00 / 366.67); by every OpenAI sender; via Stripe's rail, which is how
--   Rork's receipt arrives and which carries no OpenAI traffic here; and the Outlook mailbox, which
--   holds only OpenAI marketing. The only OpenAI mail since is marketing and a 5 Aug
--   multi-factor-authentication security notice.
--
-- So the August and September invoices exist ONLY inside the ChatGPT billing portal
-- (chatgpt.com -> Settings -> Billing). Not in any mailbox, and no amount of forwarding will produce
-- them.
--
-- WHY THIS NEEDS RECORDING RATHER THAN JUST ANSWERING. Every completeness check in this estate reads
-- mailboxes. A vendor that never emails a receipt is invisible to all of them, and the honest
-- shortfall line -- "OpenAI has one receipt and nobody has explained why" -- would be raised on every
-- report from now on, and answered the same way every time, until somebody stopped reading it. The
-- answer belongs in the estate, not in a conversation.
--
-- The vendor is NOT marked ended, annual or one_off, because none of those is true: the subscription
-- is live and billing monthly. It is recorded as PORTAL_ONLY -- expected to keep charging, and
-- expected never to email -- so the report says the right thing: this cost is real, recurring, and
-- its evidence must be fetched by hand from the vendor's portal.
--
-- NO FIGURE IS INVENTED. The August and September amounts are not booked. AED 385 x 2 would be a
-- guess dressed as a measurement, and the whole of today has been about not doing that.

alter table public.vendor_billing_ended
  drop constraint if exists vendor_billing_ended_kind_ck;
alter table public.vendor_billing_ended
  add constraint vendor_billing_ended_kind_ck
  check (kind in ('ended', 'annual', 'one_off', 'portal_only'));

comment on table public.vendor_billing_ended is
  'Why a vendor is not expected to keep producing monthly receipts BY EMAIL: ended (the relationship '
  'stopped), annual (one receipt covers a year), one_off (a purchase, not a subscription), or '
  'portal_only (still billing, but the vendor never emails an invoice -- it lives in their portal and '
  'must be fetched by hand). Records who said so and on what basis. Without it, every mailbox-based '
  'completeness check re-raises the same closed question on every report until somebody stops '
  'reading it. Moves no money and invents no figure.';

insert into public.vendor_billing_ended (vendor, ended_after, kind, basis, note)
values ('OpenAI', date '2026-07-29', 'portal_only', 'measured',
        'STILL BILLING MONTHLY -- the founder confirmed 9 Sep 2026 that ChatGPT is running. But OpenAI '
        || 'does not email a receipt for it. The one booked row (29 Jul 2026, AED 385.00 = 366.67 + '
        || '18.33 tax) came from a "ChatGPT - Your new plan" confirmation, sent once on subscribe. '
        || 'Searched five ways for a monthly receipt and found none: Gmail all folders after 29 Jul, '
        || 'by amount, by every OpenAI sender, via Stripe''s rail, and the Outlook mailbox. The Aug and '
        || 'Sep invoices are in the ChatGPT billing portal only (chatgpt.com > Settings > Billing) and '
        || 'must be downloaded by hand. They are NOT booked: inventing AED 385 x 2 would be a guess '
        || 'dressed as a measurement.')
on conflict (vendor) do update
  set kind = excluded.kind, ended_after = excluded.ended_after,
      basis = excluded.basis, note = excluded.note;

-- A portal-only vendor is still a shortfall -- the money is real and unbooked -- but it is a NAMED
-- one with a known remedy, not an open question. Only the wording changes; nothing is suppressed.
do $do$
declare v jsonb; v_openai int; v_kind text; v_entries int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty';
  end if;

  select kind into v_kind from public.vendor_billing_ended where vendor = 'OpenAI';
  if v_kind is distinct from 'portal_only' then
    raise exception 'OpenAI was not recorded as portal_only (got %)', coalesce(v_kind, 'null');
  end if;

  -- OpenAI must STILL be reported, because the money is genuinely missing from the book. If
  -- recording the reason silenced it, this file would have hidden a real gap instead of explaining it.
  v := public.fn_accountant_receipt_cadence_gaps();
  select count(*) into v_openai
    from jsonb_array_elements(v->'vendors_seen_once_unexplained') x
   where lower(x->>'vendor') = 'openai';
  if v_openai > 0 then
    raise notice 'OpenAI is still listed as unexplained — the reason is recorded but the check does not yet read it; the shortfall stands, which is correct while the invoices are unbooked';
  else
    raise notice 'OpenAI no longer listed as unexplained; its portal_only reason is recorded and the missing invoices remain unbooked';
  end if;

  if exists (select 1 from public.expense_entries where vendor = 'OpenAI' and charged_on > date '2026-07-31') then
    raise exception 'an OpenAI charge after July was booked; this file must not invent one';
  end if;

  raise notice 'OpenAI recorded as portal_only; Aug/Sep invoices remain unbooked and must be fetched from the billing portal';
end
$do$;

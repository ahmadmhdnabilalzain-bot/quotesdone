-- THE ANNUAL TOP-UP OF A MONTHLY ORDER IS STILL OUR COST.
--
-- GoDaddy order 4109276253, 10 June 2026, AED 392.55, was left UNDECIDED by the Gmail-inbox sweep.
-- It prepays 11.933 months of Advanced Email Security and Email Archiving, and the sweep could not
-- tell whether it belonged to this company or to Dorata Jewelries FZCO, whose costs turn up in the
-- same mailboxes. Refusing to guess was right.
--
-- IT IS SETTLED NOW, BY EVIDENCE RATHER THAN JUDGEMENT. Both orders sit in ONE Gmail thread
-- (19eb224e77524346), 90 seconds apart, under one GoDaddy customer number 665432265:
--
--   15:26:42  order 4109275583  Advanced Email Security  AED  18.33   1 month
--                               Email - Archiving        AED  13.00   1 month
--   15:28:13  order 4109276253  Advanced Email Security  AED 218.73   11.933 months
--                               Email - Archiving        AED 155.13   11.933 months
--
-- The second is not a separate purchase; it is the annual top-up of the first, which GoDaddy splits
-- into two orders at checkout. The first is ALREADY BOOKED as ours (AED 103.25, 10 Jun). Two halves
-- of one transaction cannot belong to two different companies, and the same account had bought
-- quotesdone.com two days earlier. So this is ours, and leaving it out understates the company.
--
-- WHAT THIS BOOKING ALSO EXPOSES, AND WHY IT IS WRITTEN ON THE ROW. Those 11.933 months run to about
-- June 2027. Yet the renewals already booked for 10 July (order 4132924111) and 10 August (order
-- 4159524806) EACH charge the same two products again, monthly:
--
--   Advanced Email Security  AED 18.33/month      Email - Archiving  AED 16.00/month
--
-- That is AED 34.33 a month for products that appear to be prepaid to mid-2027, and it is still
-- running. This file does NOT act on that: only GoDaddy's account can say whether the annual term
-- was superseded, refunded, or applied to a different mailbox, and inventing a credit note from
-- three receipts would be exactly the kind of guess the sweep correctly refused. It is recorded on
-- the row so the cost is visible to whoever asks GoDaddy the question, rather than living only in a
-- conversation.
--
-- The amount, the VAT and the date are read off the receipt: subtotal 373.86, tax 18.69, total
-- 392.55, 10 June 2026. Nothing is derived.

do $do$
declare
  v_id   bigint;
  v_jid  bigint;
  v_dupe int;
  v_before numeric;
  v_after  numeric;
begin
  select round(sum(case when currency='AED' then amount else amount * 3.6725 end), 2)
    into v_before from public.expense_entries;
  if v_before is null then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so this booking has no book to join';
  end if;

  -- THE ECONOMIC IDENTITY, not just the key. The same charge reaching two mailboxes carries two
  -- different message ids, so the message key alone cannot prevent a duplicate.
  select count(*) into v_dupe from public.expense_entries
   where vendor = 'GoDaddy' and charged_on::date = date '2026-06-10'
     and amount = 392.55 and currency = 'AED';
  if v_dupe > 0 then
    raise notice 'already booked (% row(s)) — nothing to do', v_dupe;
  else
    insert into public.expense_entries
      (vendor, category, amount, currency, charged_on, vat_amount, source, source_msg_id, note)
    values
      ('GoDaddy', 'Subscription', 392.55, 'AED', date '2026-06-10', 18.69,
       'gmail_inbox', 'gmail:19eb225fdb9c1a21',
       'GoDaddy order #4109276253, 10 Jun 2026. Advanced Email Security AED 218.73 and Email - '
       || 'Archiving AED 155.13, 11.933 months each. Subtotal 373.86, tax 18.69, total 392.55, all '
       || 'read off the receipt. THE ANNUAL TOP-UP of order #4109275583 placed 90 seconds earlier in '
       || 'the same thread under GoDaddy customer 665432265; that order is booked as ours, so this '
       || 'half is too. WORTH ASKING GODADDY: this prepays those two products to about Jun 2027, yet '
       || 'the 10 Jul (#4132924111) and 10 Aug (#4159524806) renewals each charge Advanced Email '
       || 'Security AED 18.33 and Email - Archiving AED 16.00 again, monthly. That is AED 34.33/month '
       || 'apparently paid twice and still running. Only GoDaddy''s account can say whether the '
       || 'annual term was superseded or refunded, so no credit is assumed here.')
    returning id into v_id;

    v_jid := public.fn_expense_post_to_gl(v_id);
    if v_jid is null then
      raise exception 'the entry was written but did not post to the ledger';
    end if;
  end if;

  -- The undecided row can now be answered. It was correct while the question was open.
  update public.expense_vendor_billing_mailbox
     set in_ledger_scope = true,
         note = coalesce(nullif(note,'') || ' | ', '')
             || 'QuotesDone, settled 9 Sep 2026 by evidence, not judgement: same Gmail thread, same '
             || 'GoDaddy customer 665432265, 90 seconds after order #4109275583 which is booked as '
             || 'ours. Booked at AED 392.55.'
   where vendor ilike 'GoDaddy (order 4109276253)%';

  select round(sum(case when currency='AED' then amount else amount * 3.6725 end), 2)
    into v_after from public.expense_entries;

  -- The ledger must still balance across every posted, non-reversal journal.
  declare v_dr numeric; v_cr numeric;
  begin
    select round(sum(l.debit),2), round(sum(l.credit),2) into v_dr, v_cr
      from public.gl_journal_lines l join public.gl_journal g on g.id = l.journal_id
     where g.status = 'posted';
    if v_dr is distinct from v_cr then
      raise exception 'the ledger no longer balances after booking: DR % CR %', v_dr, v_cr;
    end if;
  end;

  raise notice 'book moved from AED % to AED % (entry %, journal %)', v_before, v_after, coalesce(v_id::text,'-'), coalesce(v_jid::text,'-');
end
$do$;

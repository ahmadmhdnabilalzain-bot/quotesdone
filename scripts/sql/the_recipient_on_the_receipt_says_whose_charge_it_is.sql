-- THE RECIPIENT ON THE RECEIPT SAYS WHOSE CHARGE IT IS.
--
-- The founder, 9 September 2026: "godaddy has my other email also \"bookings@djzaino.com\" so thats
-- not for quotesdone".
--
-- Six GoDaddy charges were in the book, AED 970.53 in total, and none of the receipts names a domain
-- against the email products -- only "Microsoft 365 Email Plus", "Advanced Email Security" and so on.
-- From the line items alone there is no way to tell one mailbox from another, which is exactly the
-- ambiguity he was warning about.
--
-- THE RECEIPTS SETTLE IT ANYWAY, on a field nobody had looked at: who the vendor addressed them to.
--
--   #56  12 Aug 2026  AED 40.95  order 4161152146
--        "From: GoDaddy <donotreply@godaddy.com> Sent: Wednesday, 12 August 2026 16:38:14
--         To: djzaino@outlook.com"
--        Forwarded to the expenses mailbox by Djzaino@outlook.com, which is on the approved
--        forwarder list -- so it was accepted in good faith and booked.
--
--   Every other GoDaddy receipt was addressed to ahmadmhdnabilalzain@gmail.com under GoDaddy
--   customer number 665432265 -- the same account that bought quotesdone.com and .net on 8 June,
--   which is the one order that names a domain at all.
--
-- So this is a SECOND GoDaddy account, not a second product on the same one, and #56 is the only
-- charge from it. It is reversed out.
--
-- WHY THIS IS WORTH WRITING DOWN BEYOND THE AED 40.95. Being on the forwarder allowlist means a
-- person is trusted to send receipts; it does not mean everything they send is this company's cost.
-- The allowlist answers "is this sender legitimate", and the entirely different question -- "is this
-- charge ours" -- was being answered by silence. The recipient address on the vendor's own receipt
-- answers it, and it is evidence rather than judgement. Recorded so the next sweep reads it.

do $do$
declare
  v_id bigint; v_j record; v_new bigint; v_reversed int := 0; v_before numeric; v_after numeric;
begin
  select round(sum(case when currency='AED' then amount else amount * 3.6725 end), 2)
    into v_before from public.expense_entries;
  if v_before is null then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty';
  end if;

  select id into v_id from public.expense_entries
   where vendor ilike 'godaddy%' and charged_on::date = date '2026-08-12' and amount = 40.95;

  if v_id is null then
    raise notice 'the djzaino GoDaddy charge is not in the book — already reversed, or never booked';
  else
    for v_j in
      select g.id from public.gl_journal g
       where g.source = 'expense' and g.status = 'posted' and g.source_ref = v_id::text
    loop
      v_new := public.fn_gl_reverse(v_j.id,
        'Not a QuotesDone cost. GoDaddy addressed this receipt (order 4161152146) To: '
        || 'djzaino@outlook.com -- a separate GoDaddy account from customer 665432265, which is the '
        || 'one that bought quotesdone.com. Founder''s ruling 9 Sep 2026: "godaddy has my other email '
        || 'also bookings@djzaino.com so thats not for quotesdone". Booked in good faith because the '
        || 'forwarder is on the approved list; being a trusted sender is not the same as the charge '
        || 'being ours.');
      v_reversed := v_reversed + 1;
    end loop;

    delete from public.expense_entries where id = v_id;

    if exists (select 1 from public.expense_entries where id = v_id) then
      raise exception 'the entry survived deletion';
    end if;
    if v_reversed <> 1 then
      raise exception 'expected exactly 1 journal to reverse, reversed %', v_reversed;
    end if;
  end if;

  -- Record WHY, keyed on the vendor+mailbox pair so the next sweep does not re-book it.
  insert into public.expense_vendor_billing_mailbox (vendor, mailbox, in_ledger_scope, evidence, note)
  values ('GoDaddy (djzaino@outlook.com account)', 'expenses@mail.quotesdone.com', false,
          'GoDaddy order 4161152146, 12 Aug 2026, AED 40.95, addressed by the vendor To: '
          || 'djzaino@outlook.com and forwarded to the expenses mailbox by Djzaino@outlook.com.',
          'NOT QuotesDone. A SECOND GoDaddy account, distinct from customer 665432265 which owns '
          || 'quotesdone.com. Founder''s ruling 9 Sep 2026. The recipient address on the vendor''s own '
          || 'receipt is what distinguishes them -- the line items do not name a domain.')
  on conflict (vendor, mailbox) do update
    set in_ledger_scope = false, note = excluded.note;

  select round(sum(case when currency='AED' then amount else amount * 3.6725 end), 2)
    into v_after from public.expense_entries;

  declare v_dr numeric; v_cr numeric;
  begin
    select round(sum(l.debit),2), round(sum(l.credit),2) into v_dr, v_cr
      from public.gl_journal_lines l join public.gl_journal g on g.id = l.journal_id
     where g.status = 'posted';
    if v_dr is distinct from v_cr then
      raise exception 'the ledger no longer balances: DR % CR %', v_dr, v_cr;
    end if;
  end;

  raise notice 'book moved AED % -> AED %, % journal(s) reversed', v_before, v_after, v_reversed;
end
$do$;

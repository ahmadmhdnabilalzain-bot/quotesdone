-- SUNO AND ADIB ARE NOT OURS, AND NOTHING IS UNDECIDED NOW.
--
-- The founder, 9 September 2026, verbatim: "suno and adib dont belong to quotesdone."
--
-- These were the last two vendors the mailbox sweeps had recorded as UNDECIDED. Both were left that
-- way deliberately rather than guessed:
--
--   SUNO  $30.00 paid 11 May (#2779-8959-3255) and $30.00 on 11 Jun (#2855-6239-8138), "Suno
--         Premier", card ending 5057. Music generation. Nothing on either receipt ties it to a
--         procurement marketplace, and nothing ruled it out either -- QuotesDone buys AI tooling.
--   ADIB  four monthly VAT invoices found in the Dorata Jewelries FZCO mailbox, whose figures are
--         inside a password-protected attachment (the RIM number). The amounts were never readable,
--         so it could not have been booked even if it had been ours.
--
-- WHY THIS MATTERS BEYOND THE TWO VENDORS. fn_accountant_spend_report_coverage names undecided
-- vendors as a shortfall and marks the report INCOMPLETE while any stands. That is correct: spend
-- whose ownership is unknown is spend the total cannot claim to cover. With these answered, every
-- vendor either of the sweeps has ever seen now has a yes or a no against it, so the report's
-- incompleteness -- if it still reports any -- is about something real rather than a question
-- nobody had got round to answering.
--
-- NO FIGURE MOVES. Neither vendor was ever booked. This records scope, not accounts.

update public.expense_vendor_billing_mailbox
   set in_ledger_scope = false,
       note = coalesce(nullif(note, '') || ' | ', '')
           || 'NOT QuotesDone. Founder''s ruling 9 Sep 2026, in his own words: "suno and adib dont '
           || 'belong to quotesdone." Do not book, and do not re-raise as undecided.'
 where (vendor ilike 'suno%' or vendor ilike 'adib%')
   and in_ledger_scope is distinct from false;

do $do$
declare v_undecided int; v_who text; v_out int; v_booked int; v_total int;
begin
  select count(*) into v_total from public.expense_vendor_billing_mailbox;
  if v_total = 0 then
    raise exception 'POSITIVE CONTROL FAILED: the vendor register is empty, so this ruling was recorded against nothing';
  end if;

  select count(*), coalesce(string_agg(vendor, ', ' order by vendor), '')
    into v_undecided, v_who
    from public.expense_vendor_billing_mailbox where in_ledger_scope is null;
  if v_undecided > 0 then
    raise exception '% vendor(s) are still undecided (%); the ruling did not reach them all', v_undecided, v_who;
  end if;

  -- Nothing ruled out may be sitting in the book. This is the check that would catch a sweep
  -- booking one of them after the fact.
  select count(*) into v_booked
    from public.expense_entries e
    join public.expense_vendor_billing_mailbox m on m.vendor = e.vendor
   where m.in_ledger_scope = false;
  if v_booked > 0 then
    raise exception '% booked entry/entries belong to a vendor ruled out of scope', v_booked;
  end if;

  select count(*) into v_out from public.expense_vendor_billing_mailbox where in_ledger_scope = false;
  raise notice 'vendor scope closed: % registered, % out of scope, 0 undecided, 0 out-of-scope entries booked', v_total, v_out;
end
$do$;

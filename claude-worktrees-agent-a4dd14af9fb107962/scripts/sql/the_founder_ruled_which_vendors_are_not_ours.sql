-- THE FOUNDER RULED WHICH VENDORS ARE NOT OURS.
--
-- 9 September 2026, verbatim: "skywork / artguru/grok dont belong to quotesdone".
--
-- BACKGROUND. Sweeping management@doratajewelries.com for the receipts Anthropic bills there turned
-- up seven other vendors. That mailbox belongs to Dorata Jewelries FZCO, a different company, so the
-- sweep deliberately recorded all seven as UNDECIDED (in_ledger_scope null) rather than booking
-- them: putting another company's costs into this ledger corrupts it as surely as leaving ours out,
-- and an amount you cannot attribute is not an amount you may assume.
--
-- Four of the seven read as the jewellery business on their face and nobody disputed it -- DEWA is
-- an electricity account, ADIB a bank, Dubai Customs a customs receipt, Network International a card
-- acquirer. The three genuinely ambiguous ones were AI tooling, which QuotesDone also buys, so they
-- were put to the founder. He ruled them out.
--
-- WHY THIS IS WRITTEN DOWN RATHER THAN JUST ACTED ON. A vendor left at "undecided" is re-examined by
-- every future sweep and re-surfaced on every report that lists unattributed vendors -- correct while
-- the question is open, noise once it is answered. Recording the ruling closes the question with its
-- reason attached, so the next sweep does not ask the founder again and no later reader mistakes a
-- deliberate exclusion for an oversight. It is also the difference between "these were missed" and
-- "these were decided", which matters if anyone ever audits why USD ~215 of AI tooling is absent
-- from a company that visibly buys AI tooling.
--
-- NO FIGURE MOVES. These vendors were never booked, so nothing is being removed from the ledger.
-- This records a decision about scope, not a change to the accounts.

update public.expense_vendor_billing_mailbox
   set in_ledger_scope = false,
       note = coalesce(nullif(note, '') || ' | ', '')
           || 'NOT QuotesDone. Founder''s ruling 9 Sep 2026, in his own words: "skywork / artguru/grok '
           || 'dont belong to quotesdone". Billed to the Dorata Jewelries FZCO mailbox and belonging '
           || 'to that entity, not this one. Do not book, and do not re-raise as undecided.'
 where vendor in ('SKYWORK AI PTE. LTD.', 'Artguru', 'Grok xAI')
   and in_ledger_scope is null;

update public.expense_vendor_billing_mailbox
   set in_ledger_scope = false,
       note = coalesce(nullif(note, '') || ' | ', '')
           || 'NOT QuotesDone. A utility, bank, customs or card-acquirer account of Dorata Jewelries '
           || 'FZCO, whose mailbox these were found in. Settled 9 Sep 2026 alongside the founder''s '
           || 'ruling on the three AI vendors; these four were never in question. Do not book.'
 where vendor in ('DEWA', 'ADIB', 'Dubai Customs', 'Network International')
   and in_ledger_scope is null;

-- CLOSING ASSERTION. The point of this file is that NOTHING is left undecided from that mailbox and
-- that no in-scope vendor was caught by the same net. Both are checked, and the positive control
-- comes first: if the table were empty, every count below would pass while proving nothing.
do $do$
declare
  v_rows int; v_still_null int; v_out int; v_in int; v_entries int;
begin
  select count(*) into v_rows from public.expense_vendor_billing_mailbox;
  if v_rows = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_vendor_billing_mailbox is empty, so this ruling was recorded against nothing';
  end if;

  select count(*) into v_still_null from public.expense_vendor_billing_mailbox where in_ledger_scope is null;
  if v_still_null > 0 then
    raise exception '% vendor(s) are still undecided; the ruling did not reach them all', v_still_null;
  end if;

  select count(*) into v_out from public.expense_vendor_billing_mailbox where in_ledger_scope = false;
  select count(*) into v_in  from public.expense_vendor_billing_mailbox where in_ledger_scope = true;
  if v_out <> 7 then
    raise exception 'expected exactly 7 out-of-scope vendors, found %', v_out;
  end if;

  -- Nothing excluded may already be in the book. If one is, the exclusion and the ledger disagree
  -- and somebody must look, rather than the report quietly under-reporting a booked cost.
  select count(*) into v_entries
    from public.expense_entries e
    join public.expense_vendor_billing_mailbox m on m.vendor = e.vendor
   where m.in_ledger_scope = false;
  if v_entries > 0 then
    raise exception '% booked entry/entries belong to a vendor now ruled out of scope', v_entries;
  end if;

  raise notice 'vendor scope settled: % in scope, % out, 0 undecided, 0 booked entries affected', v_in, v_out;
end
$do$;

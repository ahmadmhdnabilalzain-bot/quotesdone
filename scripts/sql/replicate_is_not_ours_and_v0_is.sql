-- REPLICATE IS NOT OURS, AND v0 IS.
--
-- The founder, 9 September 2026, verbatim: "replicate no / vercel yea / vo by vercel yea", and just
-- before it "but figma and chatgpt yea".
--
-- WHY REPLICATE NEEDS RECORDING RIGHT NOW RATHER THAN AFTER THE FACT. Replicate was found in the
-- founder's Gmail INBOX (invoice+statements@replicate.com, 31 Aug and 4 Sep), never forwarded to the
-- expenses address, and never booked -- the ledger had never heard of the vendor at all. A sweep of
-- that inbox is running as this is written and would otherwise book it, because from a receipt alone
-- Replicate is indistinguishable from the AI vendors that ARE ours. Recording the exclusion before
-- the sweep decides is the difference between a rule and a correction.
--
-- If the sweep books it anyway, the closing assertion below fails loudly and names the rows, rather
-- than letting another company's cost sit quietly in this ledger.
--
-- v0 IS A DIFFERENT VENDOR NAME FOR THE SAME RELATIONSHIP. Vercel is already in scope and booked
-- five times. v0 is Vercel's product and may bill under its own name, so it is recorded in its own
-- right: a future sweep meeting a "v0" receipt must not have to guess, and must not treat it as an
-- unknown vendor merely because the string differs from "Vercel".
--
-- NO FIGURE MOVES HERE. Replicate was never booked, so nothing is removed. v0 has no receipt in the
-- book yet, so nothing is added. This records scope, not accounts.

-- THE GMAIL INBOX IS A SOURCE AND WAS NOT DECLARED AS ONE. The first attempt at this file failed on
-- expense_vendor_billing_mailbox_mailbox_fkey: 'founder Gmail inbox' is not in expense_billing_mailbox.
-- The FK was right and the omission is the point. Three mailboxes were registered -- the expenses
-- address, the founder's Gmail SENT folder, and the Outlook mailbox -- and all three describe mail
-- somebody chose to forward or that a vendor sent to a known address. The Gmail INBOX is where
-- receipts land BEFORE anyone decides to forward them, which is exactly where Replicate sat unread.
-- An undeclared source cannot be reported as unread, so it is declared here, is_swept false until a
-- sweep actually completes against it.
insert into public.expense_billing_mailbox (mailbox, description, reachable_by, is_swept, note)
values ('founder Gmail inbox',
        'Receipts as they ARRIVE in the founder''s Gmail, before any decision to forward them on.',
        'Gmail connector, search of the inbox rather than sent mail',
        false,
        'Declared 9 Sep 2026. The other registered sources all describe mail that was forwarded; this one is where a receipt sits when it is not. Replicate (31 Aug, 4 Sep 2026) was found here having never been forwarded and never booked, which is what showed this source existed at all.')
on conflict (mailbox) do nothing;

-- REPLICATE IS RULED OUT BY VENDOR, NOT BY MAILBOX. The first attempt keyed this on the pair
-- (vendor, mailbox) and guessed the mailbox string, so it missed the row the sweep had already
-- written under a different one and left Replicate reading as OURS while its entries were being
-- reversed out of the ledger. A scope ruling is about the VENDOR: whichever mailbox a Replicate
-- receipt turns up in, the answer is the same, and matching on the mailbox is how a rule silently
-- fails to apply to the row that matters.
update public.expense_vendor_billing_mailbox
   set in_ledger_scope = false,
       note = coalesce(nullif(note, '') || ' | ', '')
           || 'NOT QuotesDone. Founder''s ruling 9 Sep 2026, in his own words: "replicate no". Two '
           || 'invoices ($20.00 on 31 Aug, $20.00 on 4 Sep 2026) had already been booked in good '
           || 'faith by the Gmail-inbox sweep and were reversed out by fn_gl_reverse. Do NOT book a '
           || 'Replicate receipt from any mailbox, and do not re-raise it as undecided.'
 where vendor ilike 'replicate%';

insert into public.expense_vendor_billing_mailbox
  (vendor, mailbox, in_ledger_scope, evidence, note)
values
  ('v0 by Vercel', 'founder Gmail inbox', true,
   'Named by the founder 9 Sep 2026 as a QuotesDone cost. No receipt is booked under this name yet; recorded so a future sweep recognises it rather than treating it as an unknown vendor.',
   'QuotesDone. Founder''s ruling 9 Sep 2026: "vo by vercel yea". Vercel''s own product; may bill under its own name rather than "Vercel", which is separately in scope.')
on conflict (vendor, mailbox) do update
   set in_ledger_scope = excluded.in_ledger_scope,
       note = excluded.note;

-- CLOSING ASSERTION. Positive control first: the ruling must actually be readable back, or the two
-- checks after it prove nothing. Then the thing that matters -- no vendor ruled out of scope may
-- have a booked entry, which is also how this file catches the running sweep if it books Replicate.
do $do$
declare
  v_rep boolean; v_v0 boolean; v_bad int; v_who text; v_undecided int;
begin
  select in_ledger_scope into v_rep from public.expense_vendor_billing_mailbox where vendor = 'Replicate';
  select in_ledger_scope into v_v0  from public.expense_vendor_billing_mailbox where vendor = 'v0 by Vercel';
  if v_rep is distinct from false then
    raise exception 'POSITIVE CONTROL FAILED: Replicate did not record as out of scope (got %)', coalesce(v_rep::text, 'null');
  end if;
  if v_v0 is distinct from true then
    raise exception 'v0 by Vercel did not record as in scope (got %)', coalesce(v_v0::text, 'null');
  end if;

  select count(*), coalesce(string_agg(distinct e.vendor, ', '), '')
    into v_bad, v_who
    from public.expense_entries e
    join public.expense_vendor_billing_mailbox m on m.vendor = e.vendor
   where m.in_ledger_scope = false;
  if v_bad > 0 then
    raise exception '% booked entry/entries belong to a vendor ruled out of scope (%); they must be removed and the ledger re-checked', v_bad, v_who;
  end if;

  select count(*) into v_undecided from public.expense_vendor_billing_mailbox where in_ledger_scope is null;
  raise notice 'scope: Replicate out, v0 by Vercel in, 0 out-of-scope vendors booked, % still undecided', v_undecided;
end
$do$;

-- ONE MAILBOX SHOULD HAVE ONE ROW.
--
-- My own error, 9 September 2026, and worth writing down because of what it did rather than what it
-- was. Registering the founder's Gmail INBOX as a billing source, I wrote the mailbox as
--
--     'founder Gmail inbox'
--
-- while the sweep that had actually read it had already registered
--
--     'founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)'
--
-- expense_billing_mailbox is keyed on the mailbox STRING, so the two are different rows describing
-- the same mailbox: one marked swept, mine marked unswept because no sweep had ever run against a
-- name that had just been invented.
--
-- WHAT THAT COST. fn_accountant_spend_report_coverage counts unswept sources and reports them as
-- coverage the accountant does not have. So the corrected report delivered to the founder minutes
-- ago states "1 known billing mailbox(es) that the accountant cannot read" -- and there is no such
-- mailbox. The inbox WAS read; 10 charges came out of it. A duplicate row invented a gap.
--
-- The irony is exact and worth keeping: this whole day's work was about a report claiming to be
-- complete when it was not, and the fix for it introduced a report claiming to be incomplete when
-- that particular reason was not real. A coverage line is only as good as the register beneath it,
-- and a register keyed on a free-text name will drift the moment two writers describe one thing
-- differently. The founder's TOTAL was never affected -- 3 genuinely undecided vendors mean the
-- report is correctly marked incomplete either way -- but one of its two stated reasons was noise.
--
-- Fixed by pointing everything at the row the sweep actually wrote and deleting mine. The remaining
-- name carries the address, which is the better identifier of the two.

-- v0 by Vercel was recorded against my invented row; move it before that row can be removed.
update public.expense_vendor_billing_mailbox
   set mailbox = 'founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)'
 where mailbox = 'founder Gmail inbox'
   and not exists (
     select 1 from public.expense_vendor_billing_mailbox x
      where x.vendor = expense_vendor_billing_mailbox.vendor
        and x.mailbox = 'founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)');

-- Anything that WOULD have collided is a genuine duplicate of a row already under the right mailbox.
delete from public.expense_vendor_billing_mailbox where mailbox = 'founder Gmail inbox';

delete from public.expense_billing_mailbox where mailbox = 'founder Gmail inbox';

do $do$
declare v_dupe int; v_unswept int; v_v0 int; v_total int;
begin
  select count(*) into v_total from public.expense_billing_mailbox;
  if v_total = 0 then
    raise exception 'POSITIVE CONTROL FAILED: no mailboxes are registered at all, so nothing here proves anything';
  end if;

  select count(*) into v_dupe from public.expense_billing_mailbox where mailbox = 'founder Gmail inbox';
  if v_dupe <> 0 then raise exception 'the duplicate mailbox row survived'; end if;

  -- v0 by Vercel must still be recorded, and still in scope: the point was to remove a duplicate
  -- source, never to lose the founder's ruling that v0 is ours.
  select count(*) into v_v0 from public.expense_vendor_billing_mailbox
   where vendor = 'v0 by Vercel' and in_ledger_scope = true;
  if v_v0 <> 1 then raise exception 'v0 by Vercel is no longer recorded as in scope (found % row(s))', v_v0; end if;

  select count(*) into v_unswept from public.expense_billing_mailbox where not is_swept;
  if v_unswept <> 0 then
    raise notice '% mailbox(es) still unswept — check whether that is real before the next report claims it', v_unswept;
  end if;

  raise notice 'mailboxes: % registered, % unswept, duplicate removed, v0 ruling intact', v_total, v_unswept;
end
$do$;

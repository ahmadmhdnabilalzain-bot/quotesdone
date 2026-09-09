-- COLLECTIONS BELONG TO THE ACCOUNTANT.
--
-- The founder, 9 September 2026: "Collection definitely goes to the accountant."
--
-- Recorded now, before there is anything to collect, because ownership decided in advance is a
-- decision and ownership decided under pressure is an argument. There is no receivable today: the
-- 3% reveal fee is prepaid at Stripe checkout so it never becomes a debt, and supplier registration
-- is free until the thousandth registrant. But two debts are already defined and will exist the
-- moment the marketplace trades:
--
--   1. THE SUPPLIER NON-RESPONSE PENALTY, built earlier today — 3% of the job value recovered from
--      the supplier, plus AED 250 administration, plus 9% simple annual interest accruing daily
--      from the date the customer was refunded. Interest that accrues is by definition a debt that
--      someone must chase, and fn_supplier_nonresponse_penalty already computes the running total.
--   2. SUPPLIER SUBSCRIPTION at AED 1,000 a year, which begins with registration number 1,001.
--
-- Both are money owed TO the company, which is why they sit with the seat that owns "every
-- financial matter" rather than with sales. The accountant does not decide whether a debt exists —
-- the terms and the CEO's approval decide that — it measures, invoices, chases and books it.
--
-- WHY THIS IS A ROLE CHANGE AND NOT A ROUTINE. Nothing is built here, deliberately. Writing a
-- dunning ladder against zero receivables would be building against a table that has never had a
-- row, which is how this estate accumulated ninety-nine routines nothing calls. The ownership is
-- recorded so that when the first debt exists, it already has an owner and does not fall on the
-- floor while someone decides whose job it is.

do $do$
declare v_resp text; v_owned text[];
begin
  select responsibilities, owned_decisions into v_resp, v_owned
    from public.org_role where role_id = 'accountant';
  if v_resp is null then
    raise exception 'POSITIVE CONTROL FAILED: no accountant row to amend';
  end if;
  if v_resp ilike '%collect%' then
    raise notice 'collections is already recorded on the accountant; nothing to change';
    return;
  end if;

  update public.org_role
     set responsibilities =
           'Own every financial matter on the platform: the ledger, expense capture from the expenses '
           'inbox, reconciliation of the two cashflow sources (Stripe in, the expenses mailbox out), '
           'refunds, COLLECTIONS of every amount owed to the company, and the weekly report. Money is '
           'measured, never estimated -- a figure this seat publishes is one it can point at a source '
           'row for. Collections covers the supplier non-response penalty (reveal fee recovered plus '
           'the administration fee plus daily interest) and supplier subscription once charging '
           'begins at registration number 1,001; it does not cover the reveal fee itself, which is '
           'prepaid at checkout and therefore never a receivable.',
         owned_decisions = v_owned || array[
           'when an amount owed to the company is due, overdue, and what it has accrued'
         ],
         updated_at = now()
   where role_id = 'accountant';

  -- The seat must not have acquired the right to decide the debt exists. Approval is the CEO's.
  if exists (select 1 from public.org_role
              where role_id = 'accountant'
                and not (forbidden_decisions::text ilike '%refund%')) then
    raise exception 'the accountant lost its refund refusal while gaining collections';
  end if;

  raise notice 'collections recorded on the accountant. Nothing built: there is no receivable yet (the reveal fee is prepaid and supplier charging starts at registrant 1,001). The two future debts already have their arithmetic in fn_supplier_nonresponse_penalty.';
end
$do$;

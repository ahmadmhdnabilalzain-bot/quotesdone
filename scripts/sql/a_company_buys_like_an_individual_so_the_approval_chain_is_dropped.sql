-- A COMPANY BUYS LIKE AN INDIVIDUAL, SO THE APPROVAL CHAIN IS DROPPED — founder, 14 Sep 2026.
--
--   "i think its better just to remove the approvals tab. cause even if a company signed up, we
--    don't wanna interfere in their approvals process and they are treated like normal individuals"
--
-- WHAT WAS MEASURED ON PRODUCTION BEFORE THIS FILE (14 Sep 2026, 10:41 UTC):
--   procurement_approval_policy     0 rows
--   procurement_approval_request    0 rows
--   customer_organization           0 rows
--   customer_organization_member    0 rows
--   Routines whose body names any of these tables or the fn_approval_* family: the four approval
--   routines themselves and fn_twin (its `approval_chain` key). fn_review_submit matched only on the
--   string literal 'Published after full approval chain' — the staff review ladder, not this.
--   No cron job names any of it. No RLS policy exists on any of the four tables. The only foreign keys
--   into customer_organization come from the two approval tables and from its own member table.
--   Edge functions: procurement_api (approvals / trace / decide) and customer_portal (the
--   "approval_due" alert) — both edited in the same change to stop calling them.
--
-- WAS ANY AWARD, REVEAL OR PAYMENT GATED? NO — measured, not assumed. The only link from the award
-- path was trg_approval_raise_on_award: AFTER UPDATE OF hired_supplier_id on inquiries, and its body
-- (read back live) only INSERTed a procurement_approval_request and swallowed every error with
-- `exception when others then ... return new`. Nothing read that request back to hold a reveal, a
-- payment or an award, and no other routine references the tables. So the award already proceeded
-- exactly as for an individual; what this file removes is the side-effect that put a company's
-- purchase in a sign-off queue on our platform, plus everything that only existed to serve it.
--
-- WHAT GOES: the award trigger, the four routines, the view, and the four tables. The organisation
-- tables go too because after the approval tables they have NO reader and no writer — an
-- organisation account existed only to own an approval chain, and the founder's ruling is that a
-- company is treated like an individual.
--
-- WHAT STAYS: po_orders, fn_customer_orders and trg_po_orders_link (the Orders module — explicitly
-- not part of this decision; they share approvals_and_orders.sql but not a single dependency).
-- ceo_approval and the refund triggers are QuotesDone's own CEO decision register, unrelated.
--
-- ORDER: fn_twin must no longer read procurement_approval_policy before the table goes, or every
-- customer overview would fail at run time (plpgsql resolves names late). The twin is re-applied from
-- its owning file, the_twin_claims_no_understanding_before_a_request.sql, BEFORE this one, and the
-- first block below refuses to proceed if it was not.

do $$
declare n bigint;
begin
  if position('procurement_approval' in pg_get_functiondef('public.fn_twin(text,text)'::regprocedure)) > 0 then
    raise exception 'fn_twin still reads procurement_approval_policy - apply the_twin_claims_no_understanding_before_a_request.sql first';
  end if;
  -- The ruling is about a feature with no users. If rows ever appeared, dropping them silently would
  -- be destroying a customer's data, so this file refuses rather than guesses.
  select (select count(*) from public.procurement_approval_policy)
       + (select count(*) from public.procurement_approval_request)
       + (select count(*) from public.customer_organization)
       + (select count(*) from public.customer_organization_member) into n;
  if n <> 0 then raise exception 'approval/organisation tables hold % row(s) - refusing to drop real data', n; end if;
end $$;

drop trigger  if exists trg_approval_raise_on_award on public.inquiries;
drop function if exists public.fn_approval_raise_on_award();
drop function if exists public.fn_approval_decide(uuid, uuid, text, text);
drop function if exists public.fn_approval_list(uuid);
drop function if exists public.fn_approval_policy_match(uuid, text, numeric, text, text);
drop view     if exists public.v_approval_trace;
drop table    if exists public.procurement_approval_request;
drop table    if exists public.procurement_approval_policy;
drop table    if exists public.customer_organization_member;
drop table    if exists public.customer_organization;

-- Read back in the same transaction: every object gone, the award path carries no approval trigger,
-- and the Orders objects that share the old file are untouched.
do $$
declare left_over text;
begin
  select string_agg(x, ', ') into left_over from (
    select c.relname::text x from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname in ('procurement_approval_policy','procurement_approval_request',
           'customer_organization','customer_organization_member','v_approval_trace')
    union all
    select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'fn\_approval\_%'
    union all
    select t.tgname::text from pg_trigger t where t.tgname = 'trg_approval_raise_on_award') s;
  if left_over is not null then raise exception 'still present after drop: %', left_over; end if;
  if to_regprocedure('public.fn_customer_orders(uuid)') is null
     or not exists (select 1 from pg_trigger where tgname = 'trg_po_orders_link') then
    raise exception 'the Orders objects were disturbed';
  end if;
  raise notice 'approval chain dropped; Orders intact';
end $$;

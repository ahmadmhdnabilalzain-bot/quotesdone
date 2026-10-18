-- Assigned: it_engineer
-- A DEMO RUN'S SUPPORT PROFILE LEAVES WITH ITS CUSTOMER (19 Oct 2026).
-- Measured 18 Oct 20:35 UTC: 28 support_customer_profile rows with no customer (29 by 19 Oct), oldest
-- 2026-10-07 05:45. Every one carries an @example.invalid address (qd-<tag>-* from demo_factory runs, and one
-- zz-demo-inbound-probe), each with exactly one support_case, no feedback, notification, refund case or intake.
-- Cause: customer_id/lead_id are ON DELETE SET NULL and support_case has no cascade, so teardown's FK step
-- failed 23503 and the customer delete then nulled the link. demo_factory teardown now removes them (same PR).
-- This removes the leftovers. Scope is the address: a row without @example.invalid is never touched, whatever
-- its links. Aborted probe on production 19 Oct: profiles 29, cases 29, others 0, orphans remaining 0.
do $$
declare p bigint[];
begin
  select coalesce(array_agg(sp.id), '{}') into p from public.support_customer_profile sp
   where sp.email like '%@example.invalid'
     and not exists (select 1 from public.customers c where c.id = sp.customer_id);
  update public.support_case set recovery_of_case_id = null
   where recovery_of_case_id in (select case_id from public.support_case where customer_profile_id = any(p));
  delete from public.support_notification where case_id in (select case_id from public.support_case where customer_profile_id = any(p));
  delete from public.refund_case where case_id in (select case_id from public.support_case where customer_profile_id = any(p));
  delete from public.support_document_intake where case_id in (select case_id from public.support_case where customer_profile_id = any(p));
  delete from public.feedback where profile_id = any(p)
     or case_id in (select case_id from public.support_case where customer_profile_id = any(p));
  delete from public.support_case where customer_profile_id = any(p);
  delete from public.support_customer_profile where id = any(p);
end $$;

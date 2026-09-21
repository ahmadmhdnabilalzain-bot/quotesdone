-- customer_support, 22 Sep 2026. Pure probe, no DDL, no writes: one verdict row for
-- a_supplier_reply_reaches_a_mailbox_that_is_read.sql. PROBE FAILED until that file is applied.
with checks as (
  select 'Reply-To for supplier mail is on the Resend inbound domain' as what,
         (select value = 'suppliers@mail.quotesdone.com' from public.app_secrets where key = 'email_reply_supplier') as ok
  union all select 'the needs_review trigger is installed on inbound_messages',
         exists (select 1 from pg_trigger where tgname = 'trg_inbound_supplier_reply' and tgrelid = 'public.inbound_messages'::regclass)
  union all select 'the reply mailbox is not a Microsoft 365 address nobody reads',
         (select value not ilike '%@quotesdone.com' from public.app_secrets where key = 'email_reply_supplier')
)
select case when bool_and(coalesce(ok, false)) then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       jsonb_object_agg(what, coalesce(ok, false)) as detail
  from checks;

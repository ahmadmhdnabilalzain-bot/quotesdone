-- customer_support, 22 Sep 2026. Pure probe, no DDL, no writes: one verdict row for
-- a_supplier_reply_reaches_a_mailbox_that_is_read.sql. PROBE FAILED until that file is applied.
-- The opt-out cases replay the exact trap: the quoted invitation itself says "remove you" and
-- "Unsubscribe", so a reply that only quotes it must NOT be read as a request to stop.
with checks as (
  select 'Reply-To for supplier mail is on the Resend inbound domain' as what,
         (select value = 'suppliers@mail.quotesdone.com' from public.app_secrets where key = 'email_reply_supplier') as ok
  union all select 'the trigger is installed on inbound_messages',
         exists (select 1 from pg_trigger where tgname = 'trg_inbound_supplier_reply' and tgrelid = 'public.inbound_messages'::regclass)
  union all select 'EN request to stop is read',
         (select public.fn_reply_asks_to_stop('Re: Invitation', E'Please remove us from your list.\n\nOn Tue, 22 Sep 2026 QuotesDone Suppliers wrote:\n> Dear ZZ DEMO'))
  union all select 'a reply that only QUOTES the opt-out sentence is not a request to stop',
         (select not public.fn_reply_asks_to_stop('Re: Invitation', E'Interested, please call us.\n\nOn Tue, 22 Sep 2026 QuotesDone Suppliers wrote:\n> If you would prefer not to receive these invitations, simply reply and we will remove you.\n> Unsubscribe'))
  union all select 'an Outlook-style quote is cut too',
         (select not public.fn_reply_asks_to_stop('RE: Invitation', E'Thanks, we are interested.\n\nFrom: QuotesDone Suppliers <supplier@quotesdone.com>\nSent: Tuesday\nUnsubscribe: https://example.invalid/u'))
  union all select 'AR request to stop is read',
         (select public.fn_reply_asks_to_stop('رد: دعوة', E'الرجاء إلغاء الاشتراك وإزالة عنواننا.\n\nفي 22 سبتمبر كتب QuotesDone:\n> السادة'))
  union all select 'the subject alone can carry it',
         (select public.fn_reply_asks_to_stop('Unsubscribe', ''))
)
select case when bool_and(coalesce(ok, false)) then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       jsonb_object_agg(what, coalesce(ok, false)) as detail
  from checks;

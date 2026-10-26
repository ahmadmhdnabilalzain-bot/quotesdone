-- customer_support, 22 Sep 2026. Pure probe, no DDL, no writes: one verdict row for
-- the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql.
-- Answers PROBE FAILED against the database before that file is applied (the ramp has no caller, there
-- is no not_before, no invite_warmup, and a careers@ mailbox on an MX domain is still eligible).
-- The eligibility cases are built with jsonb_populate_record from a real eligible lead, so nothing is
-- inserted and no real person can be reached.
with base as (
  select l from public.leads l
    join public.email_domain_mx m on m.domain = split_part(lower(btrim(l.email)), '@', 2) and m.kind = 'mx'
   where public.fn_supplier_invite_eligible(l) limit 1
), a_only as (
  select domain from public.email_domain_mx where kind = 'a_implicit' limit 1
), checks as (
  select 'the daily tick calls the ramp' as what,
         (select prosrc ilike '%fn_invite_ramp()%' from pg_proc where proname = 'fn_sales_engineer_supplier_outreach_tick') as ok
  union all select 'the ramp reads app_secrets.invite_warmup and counts complaints',
         (select prosrc ilike '%invite_warmup%' and prosrc ilike '%complained%' from pg_proc where proname = 'fn_invite_ramp')
  union all select 'invite_warmup parses and carries every number',
         (select v ? 'base_cap' and v ? 'ceiling_cap' and v ? 'growth_factor' and v ? 'grow_max_bounce_rate'
                 and v ? 'grow_max_complaint_rate' and v ? 'pause_complaint_rate' and v ? 'window_end_hour'
            from (select value::jsonb v from public.app_secrets where key = 'invite_warmup') x)
  union all select 'notifications.not_before exists',
         exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'notifications' and column_name = 'not_before')
  union all select 'enqueue spreads invitations with not_before',
         (select prosrc ilike '%not_before%' from pg_proc where proname = 'enqueue_supplier_invites')
  union all select 'the deliverability view exists',
         exists (select 1 from pg_views where schemaname = 'public' and viewname = 'v_invite_deliverability_daily')
  union all select 'an eligible lead stays eligible',
         (select public.fn_supplier_invite_eligible(b.l) from base b)
  union all select 'a careers@ mailbox on the same domain is refused',
         (select not public.fn_supplier_invite_eligible(jsonb_populate_record(null::public.leads,
                   to_jsonb(b.l) || jsonb_build_object('email', 'careers@' || split_part((b.l).email, '@', 2)))) from base b)
  union all select 'an A-record-only domain is refused for a cold invitation',
         (select not public.fn_supplier_invite_eligible(jsonb_populate_record(null::public.leads,
                   to_jsonb(b.l) || jsonb_build_object('email', 'sales@' || a.domain))) from base b, a_only a)
)
select case when bool_and(coalesce(ok, false)) then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       jsonb_object_agg(what, coalesce(ok, false)) as detail
  from checks;

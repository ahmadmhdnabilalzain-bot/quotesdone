-- PHASE 1 HARDENING 4 - ONE SOURCE OF TRUTH FOR THE SUPPLIER SUBSCRIPTION
--
-- WHAT THE PRICING TEST FOUND. Phase 1.2 CHECK-locked pricing_config.supplier_reg_fee / _currency /
-- _period. But nothing that actually charges a supplier reads pricing_config:
--   fn_subscription_billing_run -> app_secrets.supplier_subscription_aed  (default 1000)
--   v_supplier_billing          -> app_secrets.supplier_subscription_aed, .supplier_subscription_start,
--                                  .founding_free_limit
--   supplier_api pay_registration -> leads.registration_fee_due, written by the run above
-- Both currently say 1000, so there is no live discrepancy - but the constraint was guarding a value
-- the biller never reads. Two sources that agree by luck are one silent incident away from two
-- sources that do not, and the one under a CHECK was the wrong one.
--
-- This collapses them. fn_supplier_subscription() is now the only place the fee, currency, period,
-- start date and free limit are resolved: pricing_config first (constrained), app_secrets second
-- (operational override, still honoured so nothing breaks), literal last. Every reader goes through
-- it, and v_pricing_consistency reports if the two ever disagree.

create or replace function public.fn_supplier_subscription()
returns table (fee numeric, currency text, period text, start_date date, free_limit int,
               fee_source text, start_source text, free_source text)
language sql stable security definer set search_path to 'public' as $fn$
  with pc as (select * from public.pricing_config order by id limit 1),
       s as (
         select
           (select nullif(value,'')::numeric from public.app_secrets where key='supplier_subscription_aed')  as fee,
           (select nullif(value,'')::date    from public.app_secrets where key='supplier_subscription_start') as start_date,
           (select nullif(value,'')::int     from public.app_secrets where key='founding_free_limit')         as free_limit
       )
  select
    coalesce((select supplier_reg_fee::numeric from pc), (select fee from s), 1000)                as fee,
    coalesce((select supplier_reg_currency from pc), 'AED')                                        as currency,
    coalesce((select supplier_reg_period   from pc), 'yearly')                                     as period,
    coalesce((select start_date from s), date '2027-08-01')                                        as start_date,
    coalesce((select supplier_free_count from pc), (select free_limit from s), 1000)               as free_limit,
    case when (select supplier_reg_fee from pc) is not null then 'pricing_config'
         when (select fee from s) is not null then 'app_secrets' else 'default' end                as fee_source,
    case when (select start_date from s) is not null then 'app_secrets' else 'default' end         as start_source,
    case when (select supplier_free_count from pc) is not null then 'pricing_config'
         when (select free_limit from s) is not null then 'app_secrets' else 'default' end         as free_source;
$fn$;

-- Rebuilt to read the resolver rather than app_secrets directly. Logic below the cfg CTE is
-- unchanged, deliberately: this migration moves where the numbers come from, nothing else.
create or replace view public.v_supplier_billing as
 WITH cfg AS (
     SELECT s.start_date, s.fee, s.free_limit,
            COALESCE((SELECT lower(a.value) = 'true' FROM app_secrets a WHERE a.key = 'subscription_honour_12m'), false) AS honour_12m
       FROM public.fn_supplier_subscription() s
    ), s AS (
     SELECT l.id AS supplier_id, l.company_name, l.claimed_by AS email, l.founding_rank,
            l.subscription_exempt, l.subscription_paid_until, l.banned, l.matching_blocked,
            COALESCE(l.registration_submitted_at, l.approved_at, l.created_at)::date AS registered_on,
            c.start_date, c.fee, c.free_limit, c.honour_12m
       FROM leads l CROSS JOIN cfg c
      WHERE COALESCE(l.claimed, false) = true AND l.approval_status = 'approved'
    )
 SELECT supplier_id, company_name, email, founding_rank, subscription_exempt, registered_on,
    subscription_paid_until,
    CASE WHEN honour_12m THEN GREATEST(start_date, (registered_on + '1 year'::interval)::date)
         ELSE start_date END AS billing_starts_on,
    CASE WHEN subscription_exempt THEN 'exempt'
         WHEN CURRENT_DATE < CASE WHEN honour_12m THEN GREATEST(start_date, (registered_on + '1 year'::interval)::date) ELSE start_date END THEN 'not_due'
         WHEN subscription_paid_until IS NOT NULL AND subscription_paid_until >= CURRENT_DATE THEN 'active'
         WHEN subscription_paid_until IS NULL THEN 'due'
         ELSE 'past_due' END AS billing_status,
    CASE WHEN subscription_exempt THEN 0::numeric
         WHEN CURRENT_DATE < CASE WHEN honour_12m THEN GREATEST(start_date, (registered_on + '1 year'::interval)::date) ELSE start_date END THEN 0::numeric
         WHEN subscription_paid_until IS NOT NULL AND subscription_paid_until >= CURRENT_DATE THEN 0::numeric
         ELSE fee END AS amount_due_aed,
    fee AS annual_fee_aed, free_limit
   FROM s;

create or replace function public.fn_subscription_billing_run(p_dry_run boolean DEFAULT false)
returns json language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_flagged int := 0; v_cfg record; v_admin text;
begin
  select * into v_cfg from public.fn_supplier_subscription();
  v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');

  for r in
    select b.* from v_supplier_billing b
    where b.billing_status in ('due','past_due')
      and coalesce(b.email,'') <> ''
      and not exists (
        select 1 from notifications n
        where n.type='subscription_due' and n.lead_id = b.supplier_id
          and n.created_at > now() - interval '30 days')
  loop
    if not p_dry_run then
      update leads set registration_fee_due = v_cfg.fee, registration_status = 'due' where id = r.supplier_id;
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
      values('subscription_due', r.email, 'supplier', r.supplier_id, 'email',
        'Your QuotesDone annual subscription is due',
        'Dear '||coalesce(r.company_name,'there')||E',\n\nYour QuotesDone annual supplier subscription of '||v_cfg.currency||' '||v_cfg.fee||E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
        'queued');
    end if;
    v_flagged := v_flagged + 1;
  end loop;

  if v_flagged > 0 and not p_dry_run then
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('subscription_billing_summary', v_admin,'admin','email','Supplier subscriptions invoiced',
      v_flagged||' supplier(s) were invoiced '||v_cfg.currency||' '||v_cfg.fee||' for their annual subscription. Founding suppliers (first '||
      v_cfg.free_limit||') are exempt and were not billed.','queued');
  end if;

  return json_build_object('billing_starts', v_cfg.start_date, 'fee', v_cfg.fee, 'currency', v_cfg.currency,
    'free_limit', v_cfg.free_limit, 'invoiced', v_flagged, 'dry_run', p_dry_run, 'ran_at', now());
end $fn$;

-- The consistency report. One row per fact, with every place that states it and whether they agree.
create or replace view public.v_pricing_consistency as
with c as (select * from public.fn_supplier_subscription()),
     pc as (select * from public.pricing_config order by id limit 1),
     s as (
       select (select nullif(value,'')::numeric from public.app_secrets where key='supplier_subscription_aed')  as fee,
              (select nullif(value,'')::date    from public.app_secrets where key='supplier_subscription_start') as start_date,
              (select nullif(value,'')::int     from public.app_secrets where key='founding_free_limit')         as free_limit
     )
select 'annual_fee' as fact,
       (select fee::text from c) as resolved,
       (select supplier_reg_fee::text from pc) as pricing_config,
       (select fee::text from s) as app_secrets,
       ((select supplier_reg_fee::numeric from pc) is not distinct from coalesce((select fee from s), (select supplier_reg_fee::numeric from pc))) as agree
union all
select 'currency', (select currency from c), (select supplier_reg_currency from pc), null, (select supplier_reg_currency from pc) = 'AED'
union all
select 'period', (select period from c), (select supplier_reg_period from pc), null, (select supplier_reg_period from pc) = 'yearly'
union all
select 'billing_starts', (select start_date::text from c), null, (select start_date::text from s),
       coalesce((select start_date from s), date '2027-08-01') = date '2027-08-01'
union all
select 'free_registrations', (select free_limit::text from c), (select supplier_free_count::text from pc), (select free_limit::text from s),
       (select supplier_free_count from pc) is not distinct from coalesce((select free_limit from s), (select supplier_free_count from pc));

revoke all on function public.fn_supplier_subscription() from public, anon, authenticated;

comment on function public.fn_supplier_subscription() is
  'The only resolver for supplier subscription pricing. pricing_config first (CHECK-constrained), app_secrets second, literal last. v_supplier_billing, fn_subscription_billing_run and v_pricing_consistency all read it.';

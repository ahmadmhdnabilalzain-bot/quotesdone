-- PRICING HAS NO DATE, NO DISCOUNT AND NO CAP (6 Sep 2026, the founder's decisions, verbatim in substance).
--
--   "no discounts and no caps for reveals. a category count is open after having 10 verified registered
--    suppliers. supplier registration is free for the first 1000 registration. after that its 1000 AED
--    per year. dont use a deadline with dates. these are my decisions so never ask about them again.
--    make sure everything is in sync"
--
-- WHAT WAS MEASURED BEFORE THIS FILE. pricing_config.supplier_charging_starts = 2027-08-01 (column
-- default the same); app_secrets.supplier_subscription_start held a 10-character date;
-- fn_supplier_subscription() resolved start_date from that secret with a 2027-08-01 default;
-- v_supplier_billing turned a NULL start into 'due' for every non-exempt supplier; v_pricing_consistency
-- called the 2027-08-01 default "agree"; fn_company_facts_sync rendered a NULL date as "say the founder
-- must confirm it"; reveal_fee() still carried the promo branch (promo_until / promo_reveal_rate) and a
-- least(cap) even though the live values were 3% / no promo / 99999999; no table or view decided when a
-- category is OPEN (the public tiles are static i18n; v_marketplace_liquidity's 'liquid' is 5 verified).
--
-- WHAT THIS FILE DOES, BY MECHANISM.
--   * pricing_config: supplier_charging_starts -> NULL and its default dropped ("dont use a deadline
--     with dates"); category_open_min_suppliers = 10 added; a CHECK pins promo_until NULL, the promo
--     rate equal to the standard rate and both caps >= 99,999,999 - so no discount, promo, coupon or cap
--     can be configured by anyone, and every reader (SQL reveal_fee below; the revealFee() copies in
--     supabase/functions/customer_api, stripe_checkout and money_tests, which read the same row) is
--     inert by construction rather than by trusting each copy.
--   * reveal_fee(): 3% of the amount, full stop. No promo branch, no cap.
--   * Every reader of supplier_charging_starts treats NULL as "charging starts with the 1,001st verified
--     registration, on no date": fn_derive_supplier_registration_state (the leads trigger),
--     fn_supplier_registration_state, fn_supplier_subscription, v_supplier_billing (the billing run's
--     source), v_pricing_consistency, fn_company_facts_sync. A supplier whose founding rank is not yet
--     stamped, or is within the free count, is 'not_due'; only a stamped rank past the free count is 'due'.
--   * v_supplier_pricing (the published statement the portal/marketing read): a NULL date renders the cohort
--     rule, not "Free until <null>". Column defaults now agree with the constraint (3% / no cap).
--   * company_economics row 2 (every employee must know it) no longer says "capped at standard_reveal_cap".
--   * kernel_routine_ownership: the five routines this file defines follow the manifest.
--
-- The proof block at the end measures all of it and raises if any decision is not in force.
--
--   node scripts/apply_sql.mjs scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql --apply --ddl
begin;

-- 1. THE TABLE. The rules are pinned where every reader reads them.
alter table public.pricing_config alter column supplier_charging_starts drop default;
-- measured on the first apply: the column was NOT NULL (the 23502 rolled the whole file back); NULL is the rule now
alter table public.pricing_config alter column supplier_charging_starts drop not null;
-- defaults agree with the rule (a fresh row could never satisfy the constraint below with 0.02 / 250)
alter table public.pricing_config alter column standard_reveal_rate set default 0.03;
alter table public.pricing_config alter column promo_reveal_rate set default 0.03;
alter table public.pricing_config alter column standard_reveal_cap set default 99999999;
alter table public.pricing_config alter column promo_reveal_cap set default 99999999;
alter table public.pricing_config add column if not exists category_open_min_suppliers integer not null default 10;
alter table public.pricing_config drop constraint if exists pricing_config_category_open_ck;
alter table public.pricing_config add constraint pricing_config_category_open_ck
  check (category_open_min_suppliers >= 1);
         and promo_reveal_cap >= 99999999
         and standard_reveal_cap >= 99999999);
comment on column public.pricing_config.supplier_charging_starts is
  'Founder, 6 Sep 2026: NULL and stays NULL - supplier charging starts with the registration after supplier_free_count, never on a calendar date. Every reader treats NULL as "no date".';
comment on column public.pricing_config.category_open_min_suppliers is
  'Founder, 6 Sep 2026: a category is OPEN (listed as available to the public) once it has this many verified registered suppliers. RFQ matching still needs one confirmed supplier.';
comment on constraint pricing_config_no_discount_no_cap_ck on public.pricing_config is
  'Founder, 6 Sep 2026: reveal fee has no discount, no promotional rate, no coupon and no cap. The promo columns stay only because edge functions select them; this constraint keeps them inert.';

-- 2. THE REVEAL FEE. 3% of the amount. No promo branch, no cap. Signature unchanged for its callers.
CREATE OR REPLACE FUNCTION public.reveal_fee(amount numeric, at_time timestamp with time zone DEFAULT now())
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 6 Sep 2026: no discount, no promo, no cap (founder). at_time is kept so callers need no change;
  -- it no longer selects a rate because there is only one rate.
  select case when amount is null or amount <= 0 then 0
              else round(amount * (select c.standard_reveal_rate from public.pricing_config c where c.id = 1), 2)
         end
$function$;

-- 3. THE SUBSCRIPTION FACTS. start_date is NULL: charging begins with the registration after the free
--    count, not on a date. The app_secrets start-date key is no longer consulted.
CREATE OR REPLACE FUNCTION public.fn_supplier_subscription()
 RETURNS TABLE(fee numeric, currency text, period text, start_date date, free_limit integer, fee_source text, start_source text, free_source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with pc as (select * from public.pricing_config order by id limit 1),
       s as (
         select
           (select nullif(value,'')::numeric from public.app_secrets where key='supplier_subscription_aed')  as fee,
           (select nullif(value,'')::int     from public.app_secrets where key='founding_free_limit')         as free_limit
       )
  select
    coalesce((select supplier_reg_fee::numeric from pc), (select fee from s), 1000)                as fee,
    coalesce((select supplier_reg_currency from pc), 'AED')                                        as currency,
    coalesce((select supplier_reg_period   from pc), 'yearly')                                     as period,
    (select supplier_charging_starts from pc)                                                      as start_date,
    coalesce((select supplier_free_count from pc), (select free_limit from s), 1000)               as free_limit,
    case when (select supplier_reg_fee from pc) is not null then 'pricing_config'
         when (select fee from s) is not null then 'app_secrets' else 'default' end                as fee_source,
    case when (select supplier_charging_starts from pc) is not null then 'pricing_config'
         else 'no date: charging starts with the registration after the free count (founder, 6 Sep 2026)' end as start_source,
    case when (select supplier_free_count from pc) is not null then 'pricing_config'
         when (select free_limit from s) is not null then 'app_secrets' else 'default' end         as free_source;
$function$;

-- 4. THE BILLING VIEW the subscription run reads. NULL start date: 'not_due' unless a stamped founding
--    rank is past the free count. Same columns as before so fn_subscription_billing_run is unchanged.
create or replace view public.v_supplier_billing as
 with cfg as (
   select s_1.start_date, s_1.fee, s_1.free_limit,
          coalesce((select lower(a.value) = 'true' from public.app_secrets a where a.key = 'subscription_honour_12m'), false) as honour_12m
   from public.fn_supplier_subscription() s_1(fee, currency, period, start_date, free_limit, fee_source, start_source, free_source)
 ), s as (
   select l.id as supplier_id, l.company_name, l.claimed_by as email, l.founding_rank, l.subscription_exempt,
          l.subscription_paid_until, l.banned, l.matching_blocked,
          coalesce(l.registration_submitted_at, l.approved_at, l.created_at)::date as registered_on,
          c.start_date, c.fee, c.free_limit, c.honour_12m
   from public.leads l
   cross join cfg c
   where coalesce(l.claimed, false) = true and l.approval_status = 'approved'
 ), st as (
   select s.*,
          case when s.start_date is null then null
               when s.honour_12m then greatest(s.start_date, (s.registered_on + interval '1 year')::date)
               else s.start_date end as billing_starts_on,
          -- not yet chargeable: a date in the future, or (no date) a rank not stamped / inside the free count
          case when s.start_date is not null then current_date < (case when s.honour_12m then greatest(s.start_date, (s.registered_on + interval '1 year')::date) else s.start_date end)
               else (s.founding_rank is null or s.founding_rank <= s.free_limit) end as not_yet
   from s
 )
 select supplier_id, company_name, email, founding_rank, subscription_exempt, registered_on, subscription_paid_until,
        billing_starts_on,
        case when subscription_exempt then 'exempt'
             when not_yet then 'not_due'
             when subscription_paid_until is not null and subscription_paid_until >= current_date then 'active'
             when subscription_paid_until is null then 'due'
             else 'past_due' end as billing_status,
        case when subscription_exempt then 0::numeric
             when not_yet then 0::numeric
             when subscription_paid_until is not null and subscription_paid_until >= current_date then 0::numeric
             else fee end as amount_due_aed,
        fee as annual_fee_aed,
        free_limit
 from st;

-- 5. THE CONSISTENCY VIEW. 'billing_starts' agrees only when there is NO date anywhere.
create or replace view public.v_pricing_consistency as
 with c as (
   select * from public.fn_supplier_subscription() f(fee, currency, period, start_date, free_limit, fee_source, start_source, free_source)
 ), pc as (
   select id, supplier_free_count, supplier_reg_fee, supplier_reg_period, supplier_reg_currency, supplier_charging_starts
   from public.pricing_config order by id limit 1
 ), s as (
   select (select nullif(value,'')::numeric from public.app_secrets where key = 'supplier_subscription_aed')  as fee,
          (select nullif(value,'')::date    from public.app_secrets where key = 'supplier_subscription_start') as start_date,
          (select nullif(value,'')::integer from public.app_secrets where key = 'founding_free_limit')         as free_limit
 )
 select 'annual_fee'::text as fact, (select c.fee::text from c) as resolved, (select pc.supplier_reg_fee::text from pc) as pricing_config,
        (select s.fee::text from s) as app_secrets,
        not ((select pc.supplier_reg_fee from pc) is distinct from coalesce((select s.fee from s), (select pc.supplier_reg_fee from pc))) as agree
 union all
 select 'currency', (select c.currency from c), (select pc.supplier_reg_currency from pc), null,
        (select pc.supplier_reg_currency from pc) = 'AED'
 union all
 select 'period', (select c.period from c), (select pc.supplier_reg_period from pc), null,
        (select pc.supplier_reg_period from pc) = 'yearly'
 union all
 select 'billing_starts', (select c.start_date::text from c), (select pc.supplier_charging_starts::text from pc), (select s.start_date::text from s),
        -- founder, 6 Sep 2026: no deadline with dates. Consistent = no date in any store.
        (select c.start_date from c) is null and (select pc.supplier_charging_starts from pc) is null and (select s.start_date from s) is null
 union all
 select 'free_registrations', (select c.free_limit::text from c), (select pc.supplier_free_count::text from pc), (select s.free_limit::text from s),
        not ((select pc.supplier_free_count from pc) is distinct from coalesce((select s.free_limit from s), (select pc.supplier_free_count from pc)));

-- 6. THE REGISTRATION STATE, derived on every lead write (the trigger) and on demand (the function).
CREATE OR REPLACE FUNCTION public.fn_derive_supplier_registration_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_fee numeric; v_start date; v_free int;
begin
  -- Only registered suppliers carry a registration state. The other ~20k scraped listings are
  -- left completely untouched so bulk maintenance on leads stays cheap.
  if coalesce(new.claimed,false) is not true and new.founding_rank is null then
    return new;
  end if;

  select coalesce(p.supplier_reg_fee,1000), p.supplier_charging_starts, coalesce(p.supplier_free_count,1000)
    into v_fee, v_start, v_free from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_free := coalesce(v_free,1000);

  if coalesce(new.subscription_exempt,false) then
    new.registration_status := 'exempt'; new.registration_fee_due := 0;
  elsif new.subscription_paid_until is not null and new.subscription_paid_until >= current_date then
    new.registration_status := 'paid'; new.registration_fee_due := 0;
  elsif v_start is not null and current_date < v_start then
    new.registration_status := 'not_due'; new.registration_fee_due := 0;
  elsif v_start is null and (new.founding_rank is null or new.founding_rank <= v_free) then
    -- 6 Sep 2026 (founder): no calendar start. Charging begins with the registration after the free
    -- count; a rank not yet stamped, or inside the free count, owes nothing.
    new.registration_status := 'not_due'; new.registration_fee_due := 0;
  else
    new.registration_status := 'due'; new.registration_fee_due := v_fee;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_registration_state(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_exempt boolean; v_rank int; v_paid_until date; v_claimed boolean;
  v_fee numeric; v_ccy text; v_start date; v_free int;
  v_status text; v_due numeric; v_reason text;
begin
  select coalesce(l.subscription_exempt,false), l.founding_rank, l.subscription_paid_until, coalesce(l.claimed,false)
    into v_exempt, v_rank, v_paid_until, v_claimed
  from public.leads l where l.id = p_lead_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'lead_not_found', 'lead_id', p_lead_id);
  end if;

  select coalesce(p.supplier_reg_fee,1000), coalesce(p.supplier_reg_currency,'AED'), p.supplier_charging_starts, coalesce(p.supplier_free_count,1000)
    into v_fee, v_ccy, v_start, v_free
  from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_ccy := coalesce(v_ccy,'AED'); v_free := coalesce(v_free,1000);

  if v_exempt then
    v_status := 'exempt'; v_due := 0;
    v_reason := 'founding rank ' || coalesce(v_rank::text,'(unranked)') || ' is inside the permanently exempt founding cohort';
  elsif v_paid_until is not null and v_paid_until >= current_date then
    v_status := 'paid'; v_due := 0;
    v_reason := 'subscription paid until ' || v_paid_until::text;
  elsif v_start is not null and current_date < v_start then
    v_status := 'not_due'; v_due := 0;
    v_reason := 'charging does not start until ' || v_start::text;
  elsif v_start is null and (v_rank is null or v_rank <= v_free) then
    v_status := 'not_due'; v_due := 0;
    v_reason := case when v_rank is null then 'founding rank not yet stamped (stamped at verification); the first ' || v_free || ' verified registrations are free and there is no calendar start date'
                     else 'founding rank ' || v_rank || ' is within the first ' || v_free || ' free registrations; charging starts with registration ' || (v_free + 1) || ', on no calendar date' end;
  else
    v_status := 'due'; v_due := v_fee;
    v_reason := case when v_paid_until is null then 'never paid' else 'subscription lapsed on ' || v_paid_until::text end;
  end if;

  return jsonb_build_object(
    'ok', true, 'lead_id', p_lead_id, 'status', v_status, 'fee_due', v_due, 'currency', v_ccy,
    'may_quote', (v_status <> 'due'), 'exempt', v_exempt, 'founding_rank', v_rank,
    'paid_until', v_paid_until, 'charging_starts', v_start, 'free_count', v_free, 'claimed', v_claimed, 'reason', v_reason);
end $function$;

-- 7. THE LIVE PRICING FACT every agent reads (agent_knowledge '_global'). NULL date is a fact, not a gap.
CREATE OR REPLACE FUNCTION public.fn_company_facts_sync()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c record; pct text; capnote text; txt text; regline text;
begin
  select * into c from pricing_config where id=1; if c is null then return; end if;

  pct := trim(to_char(coalesce(c.standard_reveal_rate,0)*100,'FM990.##'))||'%';
  capnote := 'NO cap, NO discount, NO promotional rate, NO coupon and NO free reveal - the founder''s decision of 6 Sep 2026, enforced by a pricing_config constraint';

  -- The registration sentence is DERIVED. 6 Sep 2026 (founder): "dont use a deadline with dates" -
  -- a NULL start date is the rule itself, never a gap to ask him about.
  if c.supplier_charging_starts is null then
    regline := 'Supplier registration is FREE for the first ' || c.supplier_free_count || ' verified registrations, and those '
            || c.supplier_free_count || ' suppliers are exempt PERMANENTLY. Every registration after them pays a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of ' || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || '. There is NO calendar start date and there will not be one: '
            || 'charging begins with registration number ' || (c.supplier_free_count + 1) || ', whenever that happens. '
            || 'Never state a date, never ask the founder for one. ';
  else
    regline := 'Supplier registration is FREE for EVERY supplier until '
            || to_char(c.supplier_charging_starts - 1, 'FMDD FMMonth YYYY') || '. '
            || 'From ' || to_char(c.supplier_charging_starts, 'FMDD FMMonth YYYY') || ' a '
            || coalesce(c.supplier_reg_period,'yearly') || ' subscription of '
            || coalesce(c.supplier_reg_currency,'AED') || ' '
            || trim(to_char(c.supplier_reg_fee,'FM999,999,990.##')) || ' applies, and it is NOT charged '
            || 'before that date. The first ' || c.supplier_free_count || ' businesses to register are '
            || 'exempt PERMANENTLY and never pay it - that exemption does not expire. ';
  end if;

  txt := 'PRICING & FEES - LIVE, AUTO-SYNCED FROM pricing_config (authoritative; OVERRIDES any pricing figure stated elsewhere). '
    ||'Customer REVEAL FEE: '||pct||' of the accepted quotation value ('||capnote||'), paid by the customer to unlock their chosen supplier. '
    ||'Suppliers pay NO commission on won jobs. '
    ||regline
    ||'CATEGORY OPENING: a category is OPEN once it has '||coalesce(c.category_open_min_suppliers,10)||' verified registered suppliers (public.v_category_open); matching an RFQ still needs at least one confirmed supplier. '
    ||'Non-response window: '||c.refund_window_working_days||' working days - if a revealed supplier does not respond in that window and cannot be reached, the customer reveal fee is refunded and the supplier is charged a non-response fee equal to that reveal fee and blocked from matching until paid. '
    ||'There is NO 2% fee and NO supplier commission - never quote those. (Auto-updated '||to_char(now(),'YYYY-MM-DD HH24:MI')||' UTC.)';

  update agent_knowledge set content=txt, priority=100, updated_at=now()
    where agent_key='_global' and topic='Pricing & fees (LIVE — auto-synced)';
  if not found then
    insert into agent_knowledge(agent_key,topic,content,priority,updated_at)
      values ('_global','Pricing & fees (LIVE — auto-synced)',txt,100,now());
  end if;
end $function$;

-- 8. WHICH CATEGORIES ARE OPEN. A verified registered supplier = registration submitted, approved and
--    verified. Mapped to the catalogue through lead_trade_map, exactly as v_marketplace_liquidity does.
--    ponytail: lead_trade_map covers 36 of 86 slugs today; an unmapped category counts 0 until its trades
--    are mapped, which is the honest number while it has no registered supplier anyway.
create or replace view public.v_category_open as
 select c.num, c.slug, c.name, c.regulated,
        (select count(distinct l.id)
           from public.leads l
           join public.lead_trade_map t on l.invite_trades && array[t.trade_key]
          where t.catalog_slug = c.slug
            and l.registration_submitted_at is not null
            and l.approval_status = 'approved'
            and coalesce(l.verified, false)) as verified_registered_suppliers,
        p.category_open_min_suppliers as min_required,
        (select count(distinct l.id)
           from public.leads l
           join public.lead_trade_map t on l.invite_trades && array[t.trade_key]
          where t.catalog_slug = c.slug
            and l.registration_submitted_at is not null
            and l.approval_status = 'approved'
            and coalesce(l.verified, false)) >= p.category_open_min_suppliers as is_open
   from public.catalog_supplier_categories c
  cross join (select category_open_min_suppliers from public.pricing_config where id = 1) p;
comment on view public.v_category_open is
  'Founder, 6 Sep 2026: a category is OPEN once it has pricing_config.category_open_min_suppliers (10) verified registered suppliers. RFQ matching is separate and still needs one confirmed supplier.';
revoke all on public.v_category_open from public, anon, authenticated;

-- 8b. THE PUBLISHED STATEMENT (v_supplier_pricing). Same columns as before; a NULL date is the cohort rule.
create or replace view public.v_supplier_pricing as
 select supplier_reg_fee as annual_fee,
        supplier_reg_currency as currency,
        supplier_reg_period as period,
        supplier_free_count as free_registrations,
        public.registered_supplier_count() as ranked_suppliers,
        greatest(0, supplier_free_count - public.registered_supplier_count()) as free_slots_remaining,
        supplier_charging_starts as charging_starts,
        standard_reveal_rate as reveal_rate,
        reveal_currency,
        case when supplier_charging_starts is null
             then 'Free for the first ' || supplier_free_count || ' registered suppliers, who stay free permanently. From registration '
                  || (supplier_free_count + 1) || ': ' || supplier_reg_currency || ' ' || trim(to_char(supplier_reg_fee, '999G999'))
                  || '/year - there is no calendar start date. No commission, ever.'
             else 'Free until ' || to_char(supplier_charging_starts - 1, 'FMDD FMMonth YYYY') || '. From '
                  || to_char(supplier_charging_starts, 'FMDD FMMonth YYYY') || ': ' || supplier_reg_currency || ' '
                  || trim(to_char(supplier_reg_fee, '999G999')) || '/year. The first ' || supplier_free_count
                  || ' registered suppliers are permanently exempt. No commission, ever.' end as published_statement
   from public.pricing_config p
  where id = 1;

-- 8c. THE ECONOMICS ROW every employee must know (company_economics.every_employee_must_know).
update public.company_economics
   set formula = 'reveal_fee = quote_amount * standard_reveal_rate (3%) - no cap, no discount, no promotional rate (founder, 6 Sep 2026)',
       current_value = '3.0%, NO cap, NO discount, refund window 3 working days',
       updated_at = now()
 where id = 2;

-- 8d. THE OWNERSHIP LEDGER follows the manifest: these five were HISTORICAL_APPLICATION (defined only in
--     migrations_history); this file defines them now.
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public', 'reveal_fee', 'amount numeric, at_time timestamp with time zone', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (6 Sep 2026): 3% of the amount, no promo, no cap.', 'MANIFEST', 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql'),
  ('public', 'fn_supplier_subscription', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (6 Sep 2026): start_date is pricing_config.supplier_charging_starts (NULL = no date).', 'MANIFEST', 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql'),
  ('public', 'fn_derive_supplier_registration_state', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (6 Sep 2026): NULL start date = charging begins after the free count.', 'MANIFEST', 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql'),
  ('public', 'fn_supplier_registration_state', 'p_lead_id bigint', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (6 Sep 2026): NULL start date = charging begins after the free count.', 'MANIFEST', 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql'),
  ('public', 'fn_company_facts_sync', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql (6 Sep 2026): the live pricing fact states the no-date, no-discount, no-cap rule.', 'MANIFEST', 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql')
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule, evidence = excluded.evidence,
  source_kind = excluded.source_kind, source_file = excluded.source_file, justification = null, recorded_at = now();


-- 9. THE VALUES. Readers are restated above, so the trigger on pricing_config renders the new fact.
update public.app_secrets set value = '', updated_at = now() where key = 'supplier_subscription_start';
update public.pricing_config
   set supplier_charging_starts = null,
       category_open_min_suppliers = 10,
       promo_until = null,
       promo_reveal_rate = standard_reveal_rate,
       updated_at = now()
  select id into v_lead from public.leads where approval_status = 'approved' order by id limit 1;
  if v_lead is not null then
    v_state := public.fn_supplier_registration_state(v_lead);
    if v_state->>'status' = 'due' then raise exception 'approved lead % became due under the no-date rule: %', v_lead, v_state->>'reason'; end if;
  end if;
  select count(*) into v_due from public.v_supplier_billing where billing_status in ('due','past_due');

  -- the published statement names the cohort, not a date
  select published_statement into v_txt from public.v_supplier_pricing;
  if v_txt is null or v_txt ~ '2027' or position('no calendar start date' in v_txt) = 0 then
    raise exception 'v_supplier_pricing.published_statement still names a date or is null: %', v_txt;
  end if;
  select count(*) into v_n from public.kernel_routine_ownership
   where routine_name in ('reveal_fee','fn_supplier_subscription','fn_derive_supplier_registration_state','fn_supplier_registration_state','fn_company_facts_sync')
     and ownership_class = 'QUOTESDONE_APPLICATION' and source_file = 'scripts/sql/pricing_has_no_date_no_discount_and_no_cap.sql';
  if v_n <> 5 then raise exception 'expected 5 ledger rows to follow this file, got %', v_n; end if;


  -- the open-category rule, measured
  select count(*), count(*) filter (where is_open), max(verified_registered_suppliers) into v_cats, v_open, v_vr from public.v_category_open;
  if v_cats <> (select count(*) from public.catalog_supplier_categories) then raise exception 'v_category_open does not cover the catalogue'; end if;
  select count(*) into v_n from public.leads where registration_submitted_at is not null and approval_status = 'approved' and coalesce(verified,false);
  if v_n = 0 and v_open <> 0 then raise exception 'a category reads OPEN with zero verified registered suppliers'; end if;

  raise notice 'proof: reveal_fee(10000)=% (3%%, no cap, no discount path: promo and cap updates refused, % promo readers); start_date=% (source: %); billing rows due=%; approved lead % state=%; categories=% open=% max_verified_registered=% (verified registered suppliers in total: %)',
    v_fee, v_promo_readers, v_sub.start_date, v_sub.start_source, v_due, v_lead, v_state->>'status', v_cats, v_open, v_vr, v_n;
end $proof$;

commit;

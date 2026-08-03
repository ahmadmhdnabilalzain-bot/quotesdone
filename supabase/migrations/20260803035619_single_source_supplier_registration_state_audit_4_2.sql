-- AUDIT 4.2 - "First 1,000 permanently exempt"
-- The audit found FOUR competing rules deciding whether a supplier owes the yearly fee:
--   1. fn_assign_founding_rank()            -> founding_rank vs app_secrets.founding_free_limit
--   2. supplier_api.setRegistration()       -> registered_supplier_count() vs pricing_config.supplier_free_count,
--                                              evaluated AFTER insert, so only 999 were ever free
--   3. registered_supplier_count()          -> counted leads.claimed/source, drifting from the rank sequence
--   4. v_supplier_pricing.free_slots_remaining -> a fourth counter over approval_status='approved',
--                                              with the charging start date hardcoded in the view
-- Supplier #1000 could therefore be subscription_exempt=true AND registration_status='due' at the same time.
-- setRegistration() also had no date test at all, so it marked suppliers 'due' - and supplier_api
-- refuses quote submission when status is 'due' - a full year before the contractual charging date.
-- And nothing anywhere wrote leads.subscription_paid_until, so a supplier who paid stayed due forever.
--
-- This migration collapses all four into ONE rule, enforced by a trigger so no code path can write a
-- contradictory value, and moves the charging date into pricing_config so it exists in exactly one place.

-- ---------------------------------------------------------------- 1. the one date
alter table public.pricing_config
  add column if not exists supplier_charging_starts date not null default '2027-08-01'::date;

comment on column public.pricing_config.supplier_charging_starts is
  'The single source for the date the yearly supplier registration fee starts being charged. Read by fn_supplier_registration_state, trg_bz_supplier_registration_state and v_supplier_pricing. Never hardcode this date anywhere else.';

-- ---------------------------------------------------------------- 2. the one counter
create or replace function public.registered_supplier_count()
returns integer language sql stable set search_path to 'public' as $fn$
  select coalesce(max(founding_rank), 0)::int from public.leads
$fn$;

comment on function public.registered_supplier_count() is
  'Number of suppliers that have ever been issued a founding rank. Ranks are assigned once, under an advisory lock, and never reused, so this is monotonic and cannot drift. It previously counted leads.claimed/source, which drifted away from the rank sequence and produced a different answer to the exemption rule.';

-- ---------------------------------------------------------------- 3. the one rule (read)
create or replace function public.fn_supplier_registration_state(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  v_exempt boolean; v_rank int; v_paid_until date; v_claimed boolean;
  v_fee numeric; v_ccy text; v_start date;
  v_status text; v_due numeric; v_reason text;
begin
  select coalesce(l.subscription_exempt,false), l.founding_rank, l.subscription_paid_until, coalesce(l.claimed,false)
    into v_exempt, v_rank, v_paid_until, v_claimed
  from public.leads l where l.id = p_lead_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'lead_not_found', 'lead_id', p_lead_id);
  end if;

  select coalesce(p.supplier_reg_fee,1000), coalesce(p.supplier_reg_currency,'AED'), coalesce(p.supplier_charging_starts,'2027-08-01'::date)
    into v_fee, v_ccy, v_start
  from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_ccy := coalesce(v_ccy,'AED'); v_start := coalesce(v_start,'2027-08-01'::date);

  if v_exempt then
    v_status := 'exempt'; v_due := 0;
    v_reason := 'founding rank ' || coalesce(v_rank::text,'(unranked)') || ' is inside the permanently exempt founding cohort';
  elsif v_paid_until is not null and v_paid_until >= current_date then
    v_status := 'paid'; v_due := 0;
    v_reason := 'subscription paid until ' || v_paid_until::text;
  elsif current_date < v_start then
    v_status := 'not_due'; v_due := 0;
    v_reason := 'charging does not start until ' || v_start::text;
  else
    v_status := 'due'; v_due := v_fee;
    v_reason := case when v_paid_until is null then 'never paid' else 'subscription lapsed on ' || v_paid_until::text end;
  end if;

  return jsonb_build_object(
    'ok', true, 'lead_id', p_lead_id, 'status', v_status, 'fee_due', v_due, 'currency', v_ccy,
    'may_quote', (v_status <> 'due'), 'exempt', v_exempt, 'founding_rank', v_rank,
    'paid_until', v_paid_until, 'charging_starts', v_start, 'claimed', v_claimed, 'reason', v_reason);
end $fn$;

comment on function public.fn_supplier_registration_state(bigint) is
  'AUDIT 4.2. The single authoritative answer to "does this supplier owe the registration fee, and may they quote?". Precedence: permanent founding exemption > paid subscription > before the charging start date > due. Callers must use this rather than re-deriving from counts.';

grant execute on function public.fn_supplier_registration_state(bigint) to service_role;

-- ---------------------------------------------------------------- 4. the one rule (write)
create or replace function public.fn_derive_supplier_registration_state()
returns trigger language plpgsql set search_path to 'public' as $fn$
declare v_fee numeric; v_start date;
begin
  -- Only registered suppliers carry a registration state. The other ~20k scraped listings are
  -- left completely untouched so bulk maintenance on leads stays cheap.
  if coalesce(new.claimed,false) is not true and new.founding_rank is null then
    return new;
  end if;

  select coalesce(p.supplier_reg_fee,1000), coalesce(p.supplier_charging_starts,'2027-08-01'::date)
    into v_fee, v_start from public.pricing_config p where p.id = 1;
  v_fee := coalesce(v_fee,1000); v_start := coalesce(v_start,'2027-08-01'::date);

  if coalesce(new.subscription_exempt,false) then
    new.registration_status := 'exempt'; new.registration_fee_due := 0;
  elsif new.subscription_paid_until is not null and new.subscription_paid_until >= current_date then
    new.registration_status := 'paid'; new.registration_fee_due := 0;
  elsif current_date < v_start then
    new.registration_status := 'not_due'; new.registration_fee_due := 0;
  else
    new.registration_status := 'due'; new.registration_fee_due := v_fee;
  end if;
  return new;
end $fn$;

-- Trigger name is deliberate. BEFORE triggers fire in alphabetical order, so this must sort
-- AFTER trg_assign_founding_rank (which stamps subscription_exempt) and BEFORE
-- trg_leads_lifecycle_stage (which reads registration_status). 'trg_bz_' sits between
-- 'trg_block_disposable_leads' and 'trg_leads_lifecycle_stage'.
drop trigger if exists trg_bz_supplier_registration_state on public.leads;
create trigger trg_bz_supplier_registration_state
  before insert or update on public.leads
  for each row execute function public.fn_derive_supplier_registration_state();

-- ---------------------------------------------------------------- 5. no other vocabulary is possible
alter table public.leads drop constraint if exists leads_registration_status_check;
alter table public.leads add constraint leads_registration_status_check
  check (registration_status is null or registration_status in ('exempt','paid','not_due','due'));

-- ---------------------------------------------------------------- 6. drift repair for stored state
-- The derived column is only recomputed on write, so a supplier sitting untouched across the
-- charging start date would keep a stale label. Authoritative reads use the function; this keeps
-- the stored column (which the portal displays) honest.
create or replace function public.fn_resync_supplier_registration_state()
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare n int;
begin
  with c as (
    update public.leads l
       set registration_status = l.registration_status   -- the trigger overwrites this with the derived value
     where (coalesce(l.claimed,false) or l.founding_rank is not null)
       and l.registration_status is distinct from (public.fn_supplier_registration_state(l.id)->>'status')
    returning 1
  ) select count(*)::int into n from c;
  return n;
end $fn$;

-- ---------------------------------------------------------------- 7. the published view, same sources
drop view if exists public.v_supplier_pricing;
create view public.v_supplier_pricing as
select
  p.supplier_reg_fee                as annual_fee,
  p.supplier_reg_currency           as currency,
  p.supplier_reg_period             as period,
  p.supplier_free_count             as free_registrations,
  public.registered_supplier_count() as ranked_suppliers,
  greatest(0, p.supplier_free_count - public.registered_supplier_count()) as free_slots_remaining,
  p.supplier_charging_starts        as charging_starts,
  p.standard_reveal_rate            as reveal_rate,
  p.reveal_currency,
  'Free until ' || to_char(p.supplier_charging_starts - 1, 'FMDD FMMonth YYYY')
    || '. From ' || to_char(p.supplier_charging_starts, 'FMDD FMMonth YYYY') || ': '
    || p.supplier_reg_currency || ' ' || trim(to_char(p.supplier_reg_fee, '999G999'))
    || '/year. The first ' || p.supplier_free_count
    || ' registered suppliers are permanently exempt. No commission, ever.' as published_statement
from public.pricing_config p
where p.id = 1;

grant select on public.v_supplier_pricing to service_role;

comment on view public.v_supplier_pricing is
  'AUDIT 4.2. Reads the same pricing_config row and the same rank-based counter as fn_supplier_registration_state. It previously carried its own counter over approval_status=''approved'' and its own hardcoded 2027-08-01, which is how the published free-slot number could disagree with who was actually exempt.';
;

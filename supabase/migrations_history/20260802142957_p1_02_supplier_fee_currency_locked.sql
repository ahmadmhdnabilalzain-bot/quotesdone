-- PHASE 1.2 - the supplier subscription is AED 1,000/year, stated once and enforced.
-- The founder confirmed AED on 2 Aug after the external reviewer flagged that pricing_config held
-- the number 1000 with NO currency column at all, while the written spec said EUR 1,000 and
-- everything built said AED. A 4x pricing error that depends on which document you happen to read
-- is not a documentation problem, so the currency is now a column with a CHECK, not a convention.
alter table public.pricing_config
  alter column supplier_reg_currency set default 'AED',
  alter column reveal_currency set default 'AED';

update public.pricing_config
set supplier_reg_fee = 1000,
    supplier_reg_period = 'yearly',
    supplier_reg_currency = 'AED',
    reveal_currency = 'AED',
    updated_at = now()
where id = 1;

-- Stripe charges in aed (supplier_pay line_items[0][price_data][currency] = 'aed') and every
-- customer-facing surface says AED. Anything else silently mis-bills, so make it un-typo-able.
alter table public.pricing_config
  drop constraint if exists pricing_config_currency_ck,
  add constraint pricing_config_currency_ck
  check (supplier_reg_currency = 'AED' and reveal_currency = 'AED');

alter table public.pricing_config
  drop constraint if exists pricing_config_period_ck,
  add constraint pricing_config_period_ck
  check (supplier_reg_period in ('yearly','monthly'));

comment on column public.pricing_config.supplier_reg_currency is
  'AED, confirmed by the founder 2 Aug 2026. CHECK-constrained because Stripe charges in aed and every published surface says AED; a change here without changing all of them mis-bills silently. To move currency: change supplier_pay, the Supplier Agreement (app_secrets.supplier_terms_html), the public supplier page and the accounting entries in the same migration, then relax the constraint.';

-- One place any surface can read the fee from, so no function ever hardcodes it again.
create or replace view public.v_supplier_pricing as
select p.supplier_reg_fee as annual_fee,
       p.supplier_reg_currency as currency,
       p.supplier_reg_period as period,
       p.supplier_free_count as free_registrations,
       (select count(*) from public.leads where approval_status = 'approved') as approved_suppliers,
       greatest(0, p.supplier_free_count - (select count(*) from public.leads where approval_status = 'approved')) as free_slots_remaining,
       date '2027-08-01' as charging_starts,
       p.standard_reveal_rate as reveal_rate,
       p.reveal_currency,
       'Free until 31 July 2027. From 1 August 2027: ' || p.supplier_reg_currency || ' ' ||
         trim(to_char(p.supplier_reg_fee, '999G999')) || '/year. The first ' ||
         p.supplier_free_count || ' registered suppliers are permanently exempt. No commission, ever.'
         as published_statement
from public.pricing_config p where p.id = 1;

comment on view public.v_supplier_pricing is
  'The single readable statement of supplier pricing. Every surface that quotes a fee should read this rather than restating the number.';

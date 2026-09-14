-- EVERY REVEAL CHARGE IS AUDITED AGAINST WHAT STRIPE ACTUALLY TOOK, EVERY DAY.
--
-- Assigned: accountant (duty 10, founder 14 Sep 2026: "yea add them").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh and the repository):
--   * The charge is decided in ONE place, supabase/functions/_shared/reveal_fee.ts (PR #616):
--     revealChargeFor(quote, rate, basis) = the 3% base plus every Stripe cost of taking it (card fee,
--     Invoicing fee, the VAT Stripe charges on its fees) grossed up. The Payment Element flow records the
--     basis it used on the invoice (metadata.fee_basis); the Checkout Session flow prices at the
--     international (safest) basis, revealCharge's default.
--   * stripe_webhook reads the balance transaction once, at payment, and raises a CEO incident when the
--     processing line did not cover Stripe's cost. Nothing re-checked a sale after that, and nothing
--     compared the TOTAL the customer paid with the total the formula says they should have paid.
--
-- WHAT THIS BUILDS: public.charge_audit, one row per reveal, written daily by the accountant runtime,
-- which recomputes the expected total with revealChargeFor itself (the TypeScript function; nothing here
-- re-implements it) and reads Stripe's balance transaction for the actual. Any difference of AED 0.01 or
-- more is a finding with the evidence; an overcharge is customer-facing. Past a configured count of
-- differences in the same direction inside thirty days, the CEO gets a serious report: that is a formula
-- or a rate that is wrong for everyone, not one sale. A difference stays a finding until it is resolved
-- (fn_accountant_charge_audit_resolve names what was done: the difference refunded, or why it stands).
--
--   node scripts/apply_sql.mjs scripts/sql/every_reveal_charge_is_audited_against_what_stripe_took.sql --apply --ddl

create table if not exists public.charge_audit (
  transaction_id    uuid primary key references public.transactions(id),
  audited_at        timestamptz   not null default now(),
  livemode          boolean       not null,
  basis             text          not null,
  quote_amount      numeric(14,2) not null,
  rate              numeric(8,5)  not null,
  expected_total    numeric(14,2) not null,
  expected_processing numeric(14,2) not null,
  actual_total      numeric(14,2) not null,
  actual_fee_fils   bigint,
  diff_aed          numeric(14,2) not null,
  shortfall_aed     numeric(14,2),
  evidence          jsonb         not null default '{}'::jsonb,
  resolved_at       timestamptz,
  resolution        text,
  check (resolved_at is null or coalesce(btrim(resolution), '') <> '')
);
comment on table public.charge_audit is
  'The daily audit of every reveal charge: expected_total from supabase/functions/_shared/reveal_fee.ts revealChargeFor (the #616 formula), actual_total from Stripe''s balance transaction. diff_aed = actual - expected; positive is an overcharge. A difference is a finding until resolved.';
alter table public.charge_audit enable row level security;
drop policy if exists charge_audit_service_role_only on public.charge_audit;
create policy charge_audit_service_role_only on public.charge_audit as permissive for all to public using (false) with check (false);
revoke all on public.charge_audit from anon, authenticated;

insert into public.gl_settings (key, num_value, txt_value) values
  ('charge_audit_systematic_count', 3, 'Differences in the same direction inside 30 days at which the charge audit reports a systematic error to the CEO.'),
  ('charge_audit_every_hours', 20, 'A reveal is re-audited once this many hours have passed since its last audit (the runtime runs hourly; this makes it daily).')
on conflict (key) do nothing;

-- ── 1. WHAT TO AUDIT ─────────────────────────────────────────────────────────────────────────────
-- The rate a sale was priced at: the promotional rate while pricing_config.promo_until was ahead of the
-- reveal, else the standard rate. The runtime passes it to revealChargeFor unchanged.
create or replace function public.fn_accountant_charge_audit_candidates(p_limit int default 200)
returns table(transaction_id uuid, payment_ref text, quote_amount numeric, rate numeric, revealed_at timestamptz, demo boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select t.id, t.payment_ref, t.quote_amount,
         case when c.promo_until is not null and t.revealed_at < c.promo_until then c.promo_reveal_rate else c.standard_reveal_rate end,
         t.revealed_at, coalesce(cu.is_demo, false)
    from public.transactions t
    cross join lateral (select * from public.pricing_config order by id limit 1) c
    left join public.customers cu on cu.id = t.customer_id
    left join public.charge_audit a on a.transaction_id = t.id
   where t.fee_status = 'paid' and t.payment_ref like 'pi\_%' and coalesce(t.quote_amount, 0) > 0
     and (a.transaction_id is null or a.audited_at < now()
          - make_interval(hours => (select num_value::int from public.gl_settings where key = 'charge_audit_every_hours')))
   order by a.audited_at nulls first, t.revealed_at
   limit greatest(p_limit, 1);
$fn$;
revoke execute on function public.fn_accountant_charge_audit_candidates(int) from public, anon, authenticated;

-- ── 2. RECORDING THE AUDIT, AND THE FINDINGS ─────────────────────────────────────────────────────
-- p_results: [{transaction_id, livemode, basis, quote_amount, rate, expected_total, expected_processing,
--              actual_total, actual_fee_fils, shortfall_aed, evidence}] as the runtime computed them.
create or replace function public.fn_accountant_charge_audit_record(p_results jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x jsonb; n int := 0; v_items jsonb := '[]'::jsonb; r record; v_sys int; v_rep jsonb; v_sign text;
begin
  if jsonb_typeof(p_results) is distinct from 'array' then
    raise exception 'fn_accountant_charge_audit_record(results[]): an array of audit results is required';
  end if;
  for x in select e from jsonb_array_elements(p_results) e loop
    insert into public.charge_audit (transaction_id, audited_at, livemode, basis, quote_amount, rate, expected_total,
                                     expected_processing, actual_total, actual_fee_fils, diff_aed, shortfall_aed, evidence)
    values ((x->>'transaction_id')::uuid, now(), (x->>'livemode')::boolean, x->>'basis', (x->>'quote_amount')::numeric,
            (x->>'rate')::numeric, (x->>'expected_total')::numeric, (x->>'expected_processing')::numeric,
            (x->>'actual_total')::numeric, (x->>'actual_fee_fils')::bigint,
            round((x->>'actual_total')::numeric - (x->>'expected_total')::numeric, 2),
            (x->>'shortfall_aed')::numeric, coalesce(x->'evidence', '{}'::jsonb))
    on conflict (transaction_id) do update
       set audited_at = now(), livemode = excluded.livemode, basis = excluded.basis, quote_amount = excluded.quote_amount,
           rate = excluded.rate, expected_total = excluded.expected_total, expected_processing = excluded.expected_processing,
           actual_total = excluded.actual_total, actual_fee_fils = excluded.actual_fee_fils, diff_aed = excluded.diff_aed,
           shortfall_aed = excluded.shortfall_aed, evidence = excluded.evidence,
           -- a difference that changed is a new difference: its old resolution no longer covers it
           resolved_at = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolved_at end,
           resolution = case when charge_audit.diff_aed = excluded.diff_aed then charge_audit.resolution end;
    n := n + 1;
  end loop;

  -- Every unresolved difference is a finding, whether or not it was audited on this run.
  for r in select a.*, coalesce(cu.is_demo, false) demo from public.charge_audit a
             join public.transactions t on t.id = a.transaction_id left join public.customers cu on cu.id = t.customer_id
            where abs(a.diff_aed) >= 0.01 and a.resolved_at is null loop
    v_items := v_items || jsonb_build_object('item', 'charge:' || r.transaction_id,
      'owner_seat', 'accountant', 'subject', 'stripe_checkout',
      'title', case when r.diff_aed > 0
                    then 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || r.diff_aed || ' more than the formula''s AED ' || r.expected_total
                    else 'Reveal ' || left(r.transaction_id::text, 8) || ' was charged AED ' || r.actual_total || ', AED ' || abs(r.diff_aed) || ' less than the formula''s AED ' || r.expected_total end,
      'blast', case when r.diff_aed > 0 then 'customer_facing' else 'agent_facing' end, 'affected', 1,
      'demo', r.demo or not r.livemode,
      'evidence', to_jsonb(r) - 'demo' || jsonb_build_object('formula', 'supabase/functions/_shared/reveal_fee.ts revealChargeFor'));
  end loop;

  -- Systematic: the same direction too often inside thirty days is the formula or a rate, not a sale.
  select num_value::int into v_sys from public.gl_settings where key = 'charge_audit_systematic_count';
  foreach v_sign in array array['over', 'under'] loop
    if (select count(*) from public.charge_audit a
         where a.livemode and a.audited_at > now() - interval '30 days'
           and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) >= coalesce(v_sys, 3) then
      v_rep := public.fn_support_report_to_ceo('charge_audit_systematic:' || v_sign || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'),
        'serious',
        'Reveal charges are systematically ' || v_sign || ' the formula: ' || (select count(*) from public.charge_audit a
          where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01))) || ' sale(s) in 30 days',
        jsonb_build_object('direction', v_sign, 'sales', (select jsonb_agg(jsonb_build_object('transaction_id', a.transaction_id,
            'expected', a.expected_total, 'actual', a.actual_total, 'diff', a.diff_aed, 'basis', a.basis))
          from public.charge_audit a where a.livemode and a.audited_at > now() - interval '30 days'
            and ((v_sign = 'over' and a.diff_aed >= 0.01) or (v_sign = 'under' and a.diff_aed <= -0.01)))),
        '[]'::jsonb,
        'A rate in supabase/functions/_shared/reveal_fee.ts or a Stripe price has moved: every sale is affected, not one. Decide the correction; the accountant refunds any overcharge on your approval and keeps auditing daily.',
        p_review_in => interval '1 day', p_source_agent => 'accountant');
    end if;
  end loop;

  return jsonb_build_object('audited', n, 'findings', public.fn_accountant_duty_settle('charge_audit', v_items));
end $fn$;
revoke execute on function public.fn_accountant_charge_audit_record(jsonb) from public, anon, authenticated;

-- A difference is closed only by saying what was done about it.
create or replace function public.fn_accountant_charge_audit_resolve(p_transaction_id uuid, p_resolution text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_resolution), '') = '' then raise exception 'a charge difference is resolved only with what was done about it'; end if;
  update public.charge_audit set resolved_at = now(), resolution = p_resolution
   where transaction_id = p_transaction_id and resolved_at is null and abs(diff_aed) >= 0.01;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no open charge difference on ' || p_transaction_id); end if;
  return jsonb_build_object('ok', true, 'transaction_id', p_transaction_id);
end $fn$;
revoke execute on function public.fn_accountant_charge_audit_resolve(uuid, text) from public, anon, authenticated;

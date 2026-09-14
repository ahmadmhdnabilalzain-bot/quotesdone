-- EVERY META INVOICE IS MATCHED TO THE SPEND META REPORTED, AND EVERY INQUIRY AND REVEAL CARRIES ITS COST.
--
-- Assigned: accountant. Founder, 14 Sep 2026: "add all for accountant and IT" — duty 2 of the five further
-- accountant duties: ad spend matched to Meta invoices; cost per inquiry and per reveal.
--
-- WHAT WAS MEASURED (14 Sep 2026, the repository at #645's head):
--   * The only spend figure Meta reports back is ad_spend_policy.month_spent_aed, written by meta_sync once
--     the Meta token exists, and it RESETS with the month (scripts/sql/ad_spend_autopilot.sql). No function
--     in supabase/functions writes public.meta_insights. A month's reported spend was therefore lost at the
--     reset unless someone kept it.
--   * Meta's invoices reach the books as expense_entries through the expenses mailbox ('Meta' is one of
--     decision_policy accountant_expected_subscription_vendors). Nothing compared invoiced with reported,
--     and nothing divided the spend by the inquiries and reveals it bought.
--
-- WHAT THIS BUILDS:
--   accountant_ad_spend_month        the reported spend, kept every hour under the month it belongs to
--   fn_accountant_ad_spend_figures   invoiced (booked) against reported, and cost per inquiry and per
--                                    reveal from the INVOICED figure. Missing data is null, with the reason.
--   fn_accountant_ad_spend_tick      the hourly duty: keep the snapshot, then judge each ended month once its
--                                    invoice grace has passed, and settle the findings through the IT loop.
--
-- WHAT IT DOES NOT DO. It books nothing (the expenses duty books invoices), reads no Meta API (meta_sync
-- does), and never stores a reported 0: month_spent_aed is 0 both when nothing was spent and when meta_sync
-- has never read the account, so a 0 is "not reported", not a measured zero.
--
--   node scripts/apply_sql.mjs scripts/sql/every_meta_invoice_is_matched_to_the_spend_meta_reported.sql --apply --ddl

create table if not exists public.accountant_ad_spend_month (
  month              date primary key check (month = date_trunc('month', month)::date),
  reported_spend_aed numeric(14,2) check (reported_spend_aed is null or reported_spend_aed > 0),
  reported_at        timestamptz,
  updated_at         timestamptz not null default now()
);
comment on table public.accountant_ad_spend_month is
  'The ad spend Meta reported for a month (ad_spend_policy.month_spent_aed as meta_sync last wrote it), kept by the accountant before the monthly reset. Matched against the Meta invoices booked in expense_entries.';
alter table public.accountant_ad_spend_month enable row level security;
drop policy if exists accountant_ad_spend_month_service_role_only on public.accountant_ad_spend_month;
create policy accountant_ad_spend_month_service_role_only on public.accountant_ad_spend_month
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_ad_spend_month from anon, authenticated;

insert into public.decision_policy (key, value, description) values
  ('accountant_meta_invoice_vendor_pattern', to_jsonb('^\s*(meta|facebook)'::text),
   'Case-insensitive regex on expense_entries.vendor that marks a Meta ads invoice (duty 2 of the five further accountant duties).'),
  ('accountant_ad_spend_match_tolerance_aed', '1'::jsonb,
   'Largest difference in AED between the Meta invoices booked for a month and the spend Meta reported for it that is not a finding.'),
  ('accountant_ad_spend_invoice_grace_days', '10'::jsonb,
   'Days after a month ends before its Meta invoices are expected in the books and the month is judged.')
on conflict (key) do nothing;

-- ── 1. KEEP WHAT META REPORTED BEFORE THE MONTH RESETS IT ────────────────────────────────────────
create or replace function public.fn_accountant_ad_spend_snapshot()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ad_spend_policy; v_m date;
begin
  select * into p from public.ad_spend_policy where policy_key = 'default';
  if not found or coalesce(p.month_label, '') !~ '^\d{4}-\d{2}$' then
    return jsonb_build_object('kept', false, 'reason', 'no default ad_spend_policy row with a YYYY-MM month_label');
  end if;
  v_m := to_date(p.month_label || '-01', 'YYYY-MM-DD');
  if coalesce(p.month_spent_aed, 0) <= 0 then
    return jsonb_build_object('kept', false, 'month', p.month_label,
      'reason', 'month_spent_aed is 0: nothing was spent, or meta_sync has not read the account');
  end if;
  insert into public.accountant_ad_spend_month (month, reported_spend_aed, reported_at, updated_at)
  values (v_m, round(p.month_spent_aed, 2), p.updated_at, now())
  on conflict (month) do update set reported_spend_aed = excluded.reported_spend_aed,
                                    reported_at = excluded.reported_at, updated_at = now();
  return jsonb_build_object('kept', true, 'month', p.month_label, 'reported_spend_aed', round(p.month_spent_aed, 2));
end $fn$;
revoke execute on function public.fn_accountant_ad_spend_snapshot() from public, anon, authenticated;

-- ── 2. THE MONTH'S FIGURES ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_ad_spend_figures(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_from timestamptz; v_to timestamptz;
  v_fx numeric; v_pat text; v_inv numeric; v_n int; v_unconv int; v_rep numeric; v_inq int; v_rev int;
begin
  v_e := (v_m + interval '1 month')::date - 1;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  -- The same conversion the monthly close uses (gl_settings usd_to_aed; AED is pegged at 3.6725).
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  v_pat := (select value #>> '{}' from public.decision_policy where key = 'accountant_meta_invoice_vendor_pattern');
  if v_pat is null then raise exception 'decision_policy accountant_meta_invoice_vendor_pattern is missing'; end if;

  select count(*) filter (where upper(currency) in ('AED', 'USD')),
         round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end) filter (where upper(currency) in ('AED', 'USD')), 2),
         count(*) filter (where upper(currency) not in ('AED', 'USD'))
    into v_n, v_inv, v_unconv
    from public.expense_entries where vendor ~* v_pat and charged_on between v_m and v_e;
  select reported_spend_aed into v_rep from public.accountant_ad_spend_month where month = v_m;
  select count(*) into v_inq from public.inquiries i left join public.customers c on c.id = i.customer_id
   where i.created_at >= v_from and i.created_at < v_to and not coalesce(c.is_demo, false);
  select count(*) into v_rev from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false);

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'invoiced_aed', case when v_n > 0 then v_inv end,
    'meta_invoices', v_n, 'meta_invoices_unconverted', v_unconv,
    'reported_spend_aed', v_rep,
    'difference_aed', case when v_n > 0 and v_rep is not null then v_inv - v_rep end,
    'inquiries', v_inq, 'reveals', v_rev,
    'cost_per_inquiry_aed', case when v_n > 0 and v_inq > 0 then round(v_inv / v_inq, 2) end,
    'cost_per_reveal_aed', case when v_n > 0 and v_rev > 0 then round(v_inv / v_rev, 2) end,
    'missing', to_jsonb(array_remove(array[
      case when v_n = 0 then 'no Meta invoice is booked in expense_entries for the month' end,
      case when v_unconv > 0 then v_unconv || ' Meta invoice(s) in a currency other than AED or USD are not converted' end,
      case when v_rep is null then 'Meta reported no spend for the month (meta_sync wrote none, or nothing was spent)' end,
      case when v_inq = 0 then 'no inquiry in the month, so there is no cost per inquiry' end,
      case when v_rev = 0 then 'no paid reveal in the month, so there is no cost per reveal' end], null)),
    'basis', 'Invoiced = Meta ads invoices booked in expense_entries (vendor matching decision_policy accountant_meta_invoice_vendor_pattern), USD at gl_settings usd_to_aed. Reported = ad_spend_policy.month_spent_aed as meta_sync last wrote it for the month. Cost per inquiry and per reveal divide the INVOICED figure by the inquiries created and the reveals paid in the month (Asia/Dubai). ZZ DEMO customers are not counted.');
end $fn$;
revoke execute on function public.fn_accountant_ad_spend_figures(date) from public, anon, authenticated;

-- ── 3. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
-- Judges the three most recent ended months whose invoice grace has passed. A finding stays open until
-- the books and Meta agree (the next run closes it through the same settle call).
create or replace function public.fn_accountant_ad_spend_tick(p_as_of date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_as_of date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_tol numeric := (select (value #>> '{}')::numeric from public.decision_policy where key = 'accountant_ad_spend_match_tolerance_aed');
  v_grace int := (select (value #>> '{}')::int from public.decision_policy where key = 'accountant_ad_spend_invoice_grace_days');
  v_snap jsonb; v_last date; v_m date; f jsonb; v_mon text; v_items jsonb := '[]'::jsonb; v_months jsonb := '[]'::jsonb;
begin
  if v_tol is null or v_grace is null then
    raise exception 'decision_policy accountant_ad_spend_match_tolerance_aed and accountant_ad_spend_invoice_grace_days are required';
  end if;
  v_snap := public.fn_accountant_ad_spend_snapshot();
  v_last := (date_trunc('month', v_as_of - v_grace) - interval '1 month')::date;
  for v_m in select generate_series(v_last - interval '2 months', v_last, interval '1 month')::date loop
    f := public.fn_accountant_ad_spend_figures(v_m);
    v_months := v_months || f;
    v_mon := to_char(v_m, 'Mon YYYY');
    if (f->>'reported_spend_aed') is not null and (f->>'invoiced_aed') is null then
      v_items := v_items || jsonb_build_object('item', 'uninvoiced:' || (f->>'month'), 'owner_seat', 'accountant', 'subject', 'expense_entries',
        'title', 'Meta reported AED ' || (f->>'reported_spend_aed') || ' of ad spend in ' || v_mon || ' and no Meta invoice is booked for it',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    elsif (f->>'reported_spend_aed') is not null and abs((f->>'difference_aed')::numeric) > v_tol then
      v_items := v_items || jsonb_build_object('item', 'mismatch:' || (f->>'month'), 'owner_seat', 'accountant', 'subject', 'expense_entries',
        'title', 'Meta invoices booked for ' || v_mon || ' total AED ' || (f->>'invoiced_aed') || ' but Meta reported AED '
                 || (f->>'reported_spend_aed') || ' (difference AED ' || (f->>'difference_aed') || ')',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    elsif (f->>'invoiced_aed') is not null and (f->>'reported_spend_aed') is null then
      -- The Meta token is the founder's to mint (the ad-spend build), so an account nobody read is the CEO's.
      v_items := v_items || jsonb_build_object('item', 'unreported:' || (f->>'month'), 'owner_seat', 'ceo', 'subject', 'ad_spend_policy',
        'title', 'Meta invoices of AED ' || (f->>'invoiced_aed') || ' are booked for ' || v_mon
                 || ' but no reported spend was kept for the month: meta_sync did not read the account',
        'blast', 'agent_facing', 'affected', 1, 'evidence', f);
    end if;
  end loop;
  return jsonb_build_object('snapshot', v_snap, 'months', v_months, 'findings', public.fn_accountant_duty_settle('ad_spend', v_items));
end $fn$;
revoke execute on function public.fn_accountant_ad_spend_tick(date) from public, anon, authenticated;

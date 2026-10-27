-- THE CEO'S PRICING EVIDENCE READS ONLY REAL ROWS (ceo, 27 Oct 2026). Founder ruling 1199 (12 Oct 2026): no agent ever
-- works on demo data as if it were real.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 27 Oct 2026): the duty ceo.pricing_evidence
-- (fn_ceo_pricing_evidence, defined in the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql, MANIFEST line
-- 2088, after #1348's fence at line 2022) reads inquiries, quotes, transactions and leads with no demo predicate.
-- Its last result (week 2026-10-26) recorded requests_90d 3, quotes_90d 3, reveals_90d 1, avg_quote_aed 37,826.67 and
-- avg_reveal_fee_aed 777.6 into ceo_pricing_evidence - pre-launch, with 0 real customers, those are ZZ DEMO rows the CEO
-- would price on. scripts/checks/no_seat_duty_reads_demo_rows.test.mjs reports it.
--
-- WHAT THIS CHANGES: the fence #1418 / two_more_fenced_seat_duties_keep_their_fixture_switch.sql gave the other fenced
-- duties - every subject read compares its demo predicate to the duty's fixture switch (qd.duty_fixtures = 'on', set
-- local, only inside a probe): a real run reads ONLY real rows, a fixture run ONLY demo ones. Predicates are the estate's
-- (fn_inquiry_is_demo, fn_quote_is_demo, fn_transaction_is_demo, leads.is_demo). Nothing else in the body changes;
-- it was taken from the canonical file (MANIFEST line 2088), whose prosrc equalled production's
-- (md5 363a21088f0acbd3903eebc27c05124e) before this edit. CREATE OR REPLACE keeps the ACL (revoked when created).
--
-- Prevented by: scripts/checks/no_seat_duty_reads_demo_rows.test.mjs (the duty is now named in its static list too).
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_pricing_evidence_reads_only_real_rows.sql --apply --ddl --seat ceo

create or replace function public.fn_ceo_pricing_evidence()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; v public.ceo_pricing_evidence;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
begin
  with q as (select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) n from public.inquiries i
              where i.created_at > now() - interval '90 days' and public.fn_inquiry_is_demo(i.id) = v_fx),
       t as (select * from public.transactions where revealed_at > now() - interval '90 days' and public.fn_transaction_is_demo(id) = v_fx)
  select v_week, (select count(*) from q), (select count(*) from q where n > 0), (select coalesce(sum(n), 0) from q), (select count(*) from t),
         round(100.0 * (select count(*) from t) / nullif((select count(*) from q where n > 0), 0), 1),
         (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0
             and public.fn_quote_is_demo(id) = v_fx),
         (select round(avg(reveal_fee), 2) from t),
         (select round(100.0 * sum(reveal_fee) / nullif(sum(quote_amount), 0), 2) from t where quote_amount > 0),
         (select count(*) from t where refund_requested_at is not null),
         round(100.0 * (select count(*) from t where refund_requested_at is not null) / nullif((select count(*) from t), 0), 1),
         (select count(*) from public.leads where registration_paid_at is not null and coalesce(is_demo, false) = v_fx),
         (select count(*) from q where n > 0) >= 20, now()
    into v;
  insert into public.ceo_pricing_evidence select v.*
  on conflict (week) do update set requests_90d = excluded.requests_90d, quoted_requests_90d = excluded.quoted_requests_90d,
    quotes_90d = excluded.quotes_90d, reveals_90d = excluded.reveals_90d, reveal_conversion_pct = excluded.reveal_conversion_pct,
    avg_quote_aed = excluded.avg_quote_aed, avg_reveal_fee_aed = excluded.avg_reveal_fee_aed, fee_pct_of_quote = excluded.fee_pct_of_quote,
    refunds_90d = excluded.refunds_90d, refund_rate_pct = excluded.refund_rate_pct, supplier_fee_paying = excluded.supplier_fee_paying,
    ready = excluded.ready, recorded_at = excluded.recorded_at;
  return to_jsonb(v) - 'recorded_at';
end $fn$;

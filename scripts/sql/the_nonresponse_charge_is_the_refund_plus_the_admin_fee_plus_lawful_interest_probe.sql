-- PROBE: what a silent supplier owes, computed by fn_accountant_nonresponse_charge, not by hand.
-- Seat: sales_engineer. 22 Sep 2026. Founder's non-response rule (14 Sep 2026).
--
-- WHY THIS EXISTS. Founder instruction 2's evidence in the ledger still names
-- fn_supplier_nonresponse_penalty, which was DROPPED (scripts/sql/DROPPED.txt line 647: it charged
-- 3% of the JOB VALUE, which the founder's rule of 14 Sep does not say). The live routine is
-- fn_accountant_nonresponse_charge(uuid, date), and the evidence had never been re-measured against
-- it. This probe measures it: the reveal fee the customer actually got back, + the administration
-- fee from pricing_config, + simple interest at the lower of the configured APR and the lawful
-- maximum, counted from the due date. Nothing here is typed into the answer.
--
-- Everything runs inside ONE transaction that RAISES at the end, so nothing is committed and the
-- numbers still come out in the error message. The fixture transaction carries no supplier, no
-- customer and no quote (every one of those columns is nullable), so no row that names a real
-- person is read or written and no notification can be addressed to anyone.
--   node scripts/qsql.mjs scripts/sql/the_nonresponse_charge_is_the_refund_plus_the_admin_fee_plus_lawful_interest_probe.sql
--
-- WHAT IT ASSERTS, on a job of AED 100,000 whose 3% reveal fee (AED 3,000) was refunded in full:
--   1. base   = the refunded reveal fee, 3% of the job = 3,000.00 (not 3% of the job value again)
--   2. fee    = pricing_config.supplier_nonresponse_admin_fee_aed = 250.00
--   3. rate   = least(configured APR, decision_policy supplier_charge_max_lawful_apr) = 0.09
--   4. due    = the refund's settlement date + decision_policy supplier_charge_due_days (7)
--   5. day 0  = no interest at all; day 30 = (3,000 + 250) * 0.09 * 30/365 = 24.04; total 3,274.04
--   6. a transaction with no settled refund is refused, never charged.
do $$
declare
  v_txn   uuid := gen_random_uuid();
  v_settled timestamptz := timestamptz '2026-09-01 08:00:00+04';
  v_due   date := date '2026-09-08';            -- 1 Sep (Dubai) + 7 due days
  v_job   numeric := 100000;                    -- the job the reveal fee was 3% of
  v_rate  numeric := (select standard_reveal_rate from public.pricing_config order by id limit 1);
  v_fee   numeric := v_job * v_rate;            -- 3,000.00 paid, then refunded in full
  v_admin numeric := (select supplier_nonresponse_admin_fee_aed from public.pricing_config order by id limit 1);
  v_apr   numeric := least((select supplier_nonresponse_interest_apr from public.pricing_config order by id limit 1),
                           (select (value #>> '{}')::numeric from public.decision_policy where key = 'supplier_charge_max_lawful_apr'));
  v_at_due  jsonb; v_at_30 jsonb; v_no_refund jsonb;
  v_expect_int numeric; v_problems text[] := '{}';
begin
  set local statement_timeout = '8s';

  insert into public.transactions (id, reveal_fee, total_charged, refund_amount_aed, refund_status, refund_confirmed_at)
  values (v_txn, v_fee, v_fee, v_fee, 'refunded', v_settled);

  v_at_due := public.fn_accountant_nonresponse_charge(v_txn, v_due);
  v_at_30  := public.fn_accountant_nonresponse_charge(v_txn, v_due + 30);
  v_expect_int := round((v_fee + v_admin) * v_apr * 30 / 365.0, 2);

  if (v_at_due->>'ok')::boolean is not true then v_problems := v_problems || 'the charge refused a settled refund'; end if;
  if (v_at_due->>'refunded_aed')::numeric <> v_fee then v_problems := v_problems || ('base is ' || (v_at_due->>'refunded_aed') || ', not the refunded reveal fee ' || v_fee); end if;
  if (v_at_due->>'admin_fee_aed')::numeric <> v_admin then v_problems := v_problems || ('admin fee is ' || (v_at_due->>'admin_fee_aed')); end if;
  if (v_at_due->>'interest_apr')::numeric <> v_apr then v_problems := v_problems || ('apr is ' || (v_at_due->>'interest_apr')); end if;
  if (v_at_due->>'due_date')::date <> v_due then v_problems := v_problems || ('due date is ' || (v_at_due->>'due_date')); end if;
  if (v_at_due->>'interest_aed')::numeric <> 0 then v_problems := v_problems || 'interest was charged on the due date itself'; end if;
  if (v_at_due->>'total_aed')::numeric <> v_fee + v_admin then v_problems := v_problems || ('total on the due date is ' || (v_at_due->>'total_aed')); end if;
  if (v_at_30->>'interest_days')::int <> 30 then v_problems := v_problems || ('interest days is ' || (v_at_30->>'interest_days')); end if;
  if (v_at_30->>'interest_aed')::numeric <> v_expect_int then v_problems := v_problems || ('30-day interest is ' || (v_at_30->>'interest_aed') || ', not ' || v_expect_int); end if;
  if (v_at_30->>'total_aed')::numeric <> round(v_fee + v_admin + v_expect_int, 2) then v_problems := v_problems || ('30-day total is ' || (v_at_30->>'total_aed')); end if;

  -- A transaction nobody was refunded on owes nothing: the routine refuses rather than inventing a base.
  update public.transactions set refund_amount_aed = null, refund_status = null, refund_confirmed_at = null where id = v_txn;
  v_no_refund := public.fn_accountant_nonresponse_charge(v_txn, v_due + 30);
  if (v_no_refund->>'ok')::boolean is not false then v_problems := v_problems || 'a transaction with no settled refund was still charged'; end if;

  raise exception 'CHK<<nonresponse charge: base % + admin % + apr % ; on the due date % -> total %, 30 days later interest % -> total % ; no-refund case: % ; problems: %>>',
    v_fee, v_admin, v_apr, v_due, v_at_due->>'total_aed', v_at_30->>'interest_aed', v_at_30->>'total_aed',
    coalesce(v_no_refund->>'reason', '(none)'), coalesce(array_to_string(v_problems, ' | '), '');
end $$;

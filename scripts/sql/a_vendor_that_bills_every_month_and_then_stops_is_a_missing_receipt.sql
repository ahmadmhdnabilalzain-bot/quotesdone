-- A VENDOR THAT BILLS EVERY MONTH AND THEN STOPS IS A MISSING RECEIPT.
--
-- The founder, 9 September 2026, looking at a spend report that said AED 4,400.51 and complete:
-- "anthropic must be much more than than that. i pay 200 usd monthly". He was right. Measured after
-- he said it: Anthropic's own mailbox holds SIX receipts (invoices YXWTXUVD-0001..0006) and the book
-- had THREE. The 23 Aug one reads "Max plan 20x, $200.00 + $10.00 UAE VAT (5%) = $210.00".
--
-- The report was not lying about anything it looked at. fn_accountant_spend_report decides
-- completeness like this (line 139 of its body):
--
--     v_complete := array_length(v_short, 1) is null;
--
-- where v_short accumulates: receipts HELD because no amount could be read, senders REFUSED as
-- not on the allowlist, currencies with no FX rate, and entries not yet posted to the ledger.
--
-- Every one of those four is an INTAKE-SIDE question -- "did everything that arrived get handled?"
-- The answer was yes: 36 of 36 read, 0 held, 0 refused, 0 unconverted, 0 unposted. So it reported
-- itself complete while missing three Anthropic receipts, two ChatGPT months, two Figma months, a
-- Google month, and a vendor (Replicate) it had never heard of.
--
-- THIS IS THE INSTRUMENT MEASURING THE WRONG SUBJECT. A pipeline that processes 100% of what it
-- receives will always report itself healthy, however much it never receives. The expenses mailbox
-- is fed by a human remembering to forward; what was never forwarded leaves no trace on the intake
-- side at all. Completeness therefore has to be asked from the VENDOR side: not "did we handle
-- everything that came in", but "did every vendor that bills us on a cadence produce a receipt for
-- every period in that cadence".
--
-- WHAT THIS ROUTINE CLAIMS, AND WHAT IT DOES NOT. It reports SUSPECTED gaps, never proven ones. A
-- subscription can genuinely be cancelled, downgraded, paused or annual. So each finding carries the
-- evidence that produced it and the report shows them as things to check -- an honest "this looks
-- short by N" beats both a false "complete" and a false alarm presented as fact. What it does claim
-- is bounded and true: this vendor billed in these months, and this month inside that run has none.
--
-- Deterministic. No model anywhere in this path -- the founder was explicit that work like this
-- belongs in code.

create or replace function public.fn_accountant_receipt_cadence_gaps(p_as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_tz      text := 'Asia/Dubai';
  v_as_of   date;
  v_gaps    jsonb;
  v_stale   jsonb;
  v_single  jsonb;
  v_n_gap   int;
  v_n_stale int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);

  with per_vendor_month as (
    select vendor,
           date_trunc('month', charged_on)::date mo,
           count(*) n
      from public.expense_entries
     group by vendor, date_trunc('month', charged_on)::date
  ),
  span as (
    select vendor, min(mo) first_mo, max(mo) last_mo, count(*) months_seen,
           sum(n) receipts
      from per_vendor_month
     group by vendor
  ),
  -- TWO distinct months, not three. The first version of this file required three and therefore
  -- examined NEITHER of the two vendors it was written to catch: in the book Anthropic bills May and
  -- June (2 months) and Google bills June and August (2 months). It reported "0 suspected missing"
  -- against a book known to be short three Anthropic receipts. A threshold that excludes the case
  -- the guard exists for is the guard not existing -- and it fails in the flattering direction.
  -- Two separate months from one vendor already establishes a repeat relationship, which is all the
  -- gap and staleness tests need. A vendor seen once still makes only the weaker `single_receipt`
  -- claim, because one receipt is not a cadence.
  cadenced as (
    select * from span where months_seen >= 2
  ),
  expected as (
    select c.vendor, gs::date mo
      from cadenced c
      cross join lateral generate_series(c.first_mo, c.last_mo, interval '1 month') gs
  ),
  -- A month INSIDE the vendor's own run with no receipt. This is the strongest signal available
  -- without leaving the database: the vendor demonstrably billed before it and after it.
  gap as (
    select e.vendor, to_char(e.mo, 'YYYY-MM') missing_month
      from expected e
      left join per_vendor_month p on p.vendor = e.vendor and p.mo = e.mo
     where p.vendor is null
  ),
  -- A cadenced vendor whose LAST receipt is more than 45 days old. 45 rather than 31: a monthly
  -- charge can land a few days late, and the report should not cry wolf on the 32nd day. This is
  -- what catches a vendor that simply stopped appearing -- Anthropic stopping at June, and every
  -- renewal after it, which no in-span gap check can see because the run ends there.
  stale as (
    select c.vendor, to_char(c.last_mo, 'YYYY-MM') last_month,
           (v_as_of - c.last_mo) days_since_last_month_started, c.receipts
      from cadenced c
     where v_as_of - c.last_mo > 45
  ),
  -- Exactly one receipt from a vendor is not evidence of a cadence, but it IS worth surfacing:
  -- if that vendor is a subscription, every renewal after it is missing and nothing else will say
  -- so. Deliberately a WEAKER claim -- an annual domain registration belongs here and is fine.
  single_receipt as (
    select vendor, to_char(first_mo, 'YYYY-MM') only_month
      from span where receipts = 1 and v_as_of - first_mo > 45
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'missing_month', missing_month)
              order by vendor, missing_month), '[]'::jsonb) from gap),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_month', last_month,
              'receipts_seen', receipts, 'days_since', days_since_last_month_started)
              order by vendor), '[]'::jsonb) from stale),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'only_month', only_month)
              order by vendor), '[]'::jsonb) from single_receipt)
    into v_gaps, v_stale, v_single;

  v_n_gap   := jsonb_array_length(v_gaps);
  v_n_stale := jsonb_array_length(v_stale);

  return jsonb_build_object(
    'as_of', v_as_of,
    'timezone', v_tz,
    'basis', 'Measured from the VENDOR side: what each vendor billed, not what the mailbox received. '
          || 'The intake-side checks (held, refused, unconvertible, unposted) cannot see a receipt '
          || 'that never arrived, which is why a report can read complete while a subscription is '
          || 'missing three months.',
    'months_with_no_receipt_inside_a_run', v_gaps,
    'vendors_gone_quiet', v_stale,
    'vendors_seen_once', v_single,
    'suspected_missing', v_n_gap + v_n_stale,
    'claim', case when v_n_gap + v_n_stale = 0
              then 'No vendor with a monthly run is missing a month or has gone quiet. That is NOT a '
                || 'claim that the book is complete: a vendor never forwarded even once is invisible '
                || 'to this and to every other check here.'
              else 'These are SUSPECTED gaps, not proven ones -- a subscription can be cancelled, '
                || 'downgraded or paused. Each carries the evidence that produced it. The book '
                || 'should not be described as complete while any of them stands unexplained.' end);
end;
$function$;

revoke execute on function public.fn_accountant_receipt_cadence_gaps(date) from public;
grant execute on function public.fn_accountant_receipt_cadence_gaps(date) to service_role;

comment on function public.fn_accountant_receipt_cadence_gaps(date) is
  'Completeness measured from the VENDOR side. Returns months with no receipt inside a vendor''s own '
  'billing run, vendors with a monthly run that have gone quiet for more than 45 days, and vendors '
  'seen exactly once. Built 9 Sep 2026 after the founder spotted that a spend report reading '
  '"complete" was short three Anthropic receipts: fn_accountant_spend_report decides completeness '
  'from held/refused/unconvertible/unposted counts, all of which are intake-side and none of which '
  'can see a receipt that never arrived. Reports SUSPECTED gaps with their evidence, never proven '
  'ones -- a subscription can legitimately be cancelled. Deterministic; no model on this path.';

-- CLOSING ASSERTION. A gap detector that finds nothing on a book known to be short would be worse
-- than no detector, so this asserts it catches the real, named shortfall the founder found. It also
-- runs a positive control first: the routine must return a well-formed answer at all.
do $do$
declare
  v jsonb; v_anthropic_stale int; v_entries int; v_anthropic_months int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so this detector cannot be tested against anything';
  end if;

  v := public.fn_accountant_receipt_cadence_gaps();
  if v is null or v->'vendors_gone_quiet' is null then
    raise exception 'the routine returned nothing usable: %', coalesce(v::text, 'null');
  end if;

  -- THE REAL CASE. Anthropic's booked receipts stop at June 2026 while it bills monthly; its July
  -- and August receipts exist in the founder's Outlook mailbox and are not in the book. If this
  -- detector does not name Anthropic, it does not do the job it was written for.
  select count(*) into v_anthropic_stale
    from jsonb_array_elements(v->'vendors_gone_quiet') x
   where lower(x->>'vendor') like '%anthropic%';

  -- THIS IS A HARD FAILURE, and the first version of this file wrongly made it a notice. A detector
  -- that finds nothing on a book known to be short is worse than no detector: it converts a real
  -- shortfall into a clean bill of health. The only legitimate reason for Anthropic to be absent
  -- here is that its missing receipts have since been booked, so that is checked explicitly rather
  -- than assumed, and anything else raises.
  if v_anthropic_stale = 0 then
    select count(*) into v_anthropic_months
      from (select distinct date_trunc('month', charged_on) m from public.expense_entries
             where vendor ilike '%anthropic%') q;
    if v_anthropic_months <= 2 then
      raise exception 'DETECTOR DOES NOT WORK: Anthropic has only % booked month(s) and is known to be short three receipts, yet it is not reported as gone quiet', v_anthropic_months;
    end if;
    raise notice 'Anthropic now spans % months and is current, so its absence here is correct', v_anthropic_months;
  else
    raise notice 'detector names Anthropic as gone quiet, which is the shortfall the founder found';
  end if;

  raise notice 'cadence gaps: % month(s) missing inside a run, % vendor(s) gone quiet, % seen once',
    jsonb_array_length(v->'months_with_no_receipt_inside_a_run'),
    jsonb_array_length(v->'vendors_gone_quiet'),
    jsonb_array_length(v->'vendors_seen_once');
end
$do$;

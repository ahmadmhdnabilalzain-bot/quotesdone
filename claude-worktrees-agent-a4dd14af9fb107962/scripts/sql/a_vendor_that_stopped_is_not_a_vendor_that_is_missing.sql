-- A VENDOR THAT STOPPED IS NOT A VENDOR THAT IS MISSING.
--
-- The founder, 9 September 2026, verbatim: "rork was a month thing then i stopped it".
--
-- fn_accountant_receipt_cadence_gaps reports a vendor that billed on a cadence and then went quiet
-- for more than 45 days, because that is usually a receipt nobody forwarded. Rork billed in May and
-- June and stopped. Nothing in the estate could tell the difference between "the receipts stopped
-- arriving" and "the charges stopped happening", so Rork would have been reported as a suspected
-- shortfall on every report from now until somebody got tired of reading it.
--
-- THAT IS HOW A USEFUL CHECK BECOMES NOISE. A finding nobody can close gets skimmed, then ignored,
-- and the day it is right it is ignored too. The cure is not to soften the check -- the check is
-- correct, a quiet vendor really is worth asking about -- but to give the answer somewhere it can
-- be recorded, so the question is asked ONCE.
--
-- So a vendor's billing relationship can now be recorded as ENDED, with who said so and on what
-- basis, and the cadence check stops asking. The gap-inside-a-run test is deliberately NOT
-- suppressed by it: if a vendor billed May, skipped June and billed July, that missing June is a
-- real hole whatever happened afterwards.
--
-- WHY THE FOUNDER'S WORD IS ENOUGH HERE. Booking an AMOUNT on his word would put an unevidenced
-- figure in the ledger, and this estate refuses that. Recording that a subscription ENDED moves no
-- money and invents no number -- it answers a question only he can answer, and it is stored with
-- his exact words so a later reader can weigh it.

create table if not exists public.vendor_billing_ended (
  vendor      text primary key,
  ended_after date not null,
  basis       text not null,
  note        text,
  recorded_at timestamptz not null default now()
);

comment on table public.vendor_billing_ended is
  'Vendors whose billing relationship is known to have ENDED, so fn_accountant_receipt_cadence_gaps '
  'stops reporting them as gone quiet. Records WHO said so and on what basis -- a subscription that '
  'stopped and a receipt that never arrived look identical from inside the book, and only somebody '
  'outside it can tell them apart. Moves no money and invents no figure: recording that a vendor '
  'ended is not the same as booking an amount on somebody''s word, which this estate refuses.';

insert into public.vendor_billing_ended (vendor, ended_after, basis, note)
values ('Rork', date '2026-06-30', 'founder',
        'Founder''s own words, 9 Sep 2026: "rork was a month thing then i stopped it". Two receipts '
        || 'were booked (27 May and 27 Jun 2026, USD 20.00 each) and no charge is expected after '
        || 'them. Recorded so the cadence check asks once rather than on every report.')
on conflict (vendor) do update
  set ended_after = excluded.ended_after, basis = excluded.basis, note = excluded.note;

-- The cadence check now respects it. Only the `stale` branch changes; a gap INSIDE a vendor's run
-- is still reported, because a skipped month between two billed months is a hole no ending explains.
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
  v_ended   jsonb;
  v_n_gap   int;
  v_n_stale int;
begin
  v_as_of := coalesce(p_as_of, (now() at time zone v_tz)::date);

  with per_vendor_month as (
    select vendor, date_trunc('month', charged_on)::date mo, count(*) n
      from public.expense_entries
     group by vendor, date_trunc('month', charged_on)::date
  ),
  span as (
    select vendor, min(mo) first_mo, max(mo) last_mo, count(*) months_seen, sum(n) receipts
      from per_vendor_month group by vendor
  ),
  -- TWO distinct months, not three. Requiring three examined neither vendor this was written to
  -- catch: Anthropic had two months booked and Google two. A threshold that excludes the case the
  -- guard exists for is the guard not existing, and it fails in the flattering direction.
  cadenced as (
    select * from span where months_seen >= 2
  ),
  expected as (
    select c.vendor, gs::date mo
      from cadenced c
      cross join lateral generate_series(c.first_mo, c.last_mo, interval '1 month') gs
  ),
  -- A month INSIDE the vendor's own run with no receipt. NOT suppressed by an ending: a vendor that
  -- billed May, skipped June and billed July has a real hole whatever happened afterwards.
  gap as (
    select e.vendor, to_char(e.mo, 'YYYY-MM') missing_month
      from expected e
      left join per_vendor_month p on p.vendor = e.vendor and p.mo = e.mo
     where p.vendor is null
  ),
  -- A cadenced vendor whose last receipt is more than 45 days old -- 45 rather than 31 so a charge
  -- landing a few days late does not cry wolf. This is what catches a vendor that simply stopped
  -- appearing, which no in-run gap test can see because the run ends there.
  -- UNLESS its billing is recorded as ended: then it stopped on purpose and there is nothing to find.
  stale as (
    select c.vendor, to_char(c.last_mo, 'YYYY-MM') last_month,
           (v_as_of - c.last_mo) days_since_last_month_started, c.receipts
      from cadenced c
      left join public.vendor_billing_ended e on e.vendor = c.vendor
     where v_as_of - c.last_mo > 45
       and e.vendor is null
  ),
  -- One receipt is not a cadence, but it is worth surfacing: if that vendor is a subscription, every
  -- renewal after it is missing and nothing else will say so. A weaker claim on purpose -- an annual
  -- domain registration belongs here and is perfectly fine. Also suppressed by a recorded ending.
  single_receipt as (
    select s.vendor, to_char(s.first_mo, 'YYYY-MM') only_month
      from span s
      left join public.vendor_billing_ended e on e.vendor = s.vendor
     where s.receipts = 1 and v_as_of - s.first_mo > 45 and e.vendor is null
  ),
  ended as (
    select vendor, to_char(ended_after, 'YYYY-MM') ended_after_month, basis
      from public.vendor_billing_ended
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'missing_month', missing_month)
              order by vendor, missing_month), '[]'::jsonb) from gap),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_month', last_month,
              'receipts_seen', receipts, 'days_since', days_since_last_month_started)
              order by vendor), '[]'::jsonb) from stale),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'only_month', only_month)
              order by vendor), '[]'::jsonb) from single_receipt),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'ended_after', ended_after_month,
              'basis', basis) order by vendor), '[]'::jsonb) from ended)
    into v_gaps, v_stale, v_single, v_ended;

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
    'vendors_recorded_as_ended', v_ended,
    'suspected_missing', v_n_gap + v_n_stale,
    'claim', case when v_n_gap + v_n_stale = 0
              then 'No vendor with a billing run is missing a month or has gone unexplained-quiet. '
                || 'That is NOT a claim that the book is complete: a vendor never forwarded even '
                || 'once is invisible to this and to every other check here.'
              else 'These are SUSPECTED gaps, not proven ones -- a subscription can be cancelled, '
                || 'downgraded or paused. Each carries the evidence that produced it, and one can be '
                || 'closed for good by recording the vendor in vendor_billing_ended. The book should '
                || 'not be described as complete while any of them stands unexplained.' end);
end;
$function$;

revoke execute on function public.fn_accountant_receipt_cadence_gaps(date) from public;
grant execute on function public.fn_accountant_receipt_cadence_gaps(date) to service_role;

do $do$
declare v jsonb; v_quiet int; v_rork int; v_entries int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so nothing here is being tested';
  end if;

  -- Rork must be booked with 2 receipts, or "the ending suppressed it" proves nothing.
  select count(*) into v_rork from public.expense_entries where vendor = 'Rork';
  if v_rork < 2 then
    raise exception 'POSITIVE CONTROL FAILED: Rork has % booked receipt(s); it needs at least 2 to be treated as cadenced at all', v_rork;
  end if;

  v := public.fn_accountant_receipt_cadence_gaps();

  select count(*) into v_quiet from jsonb_array_elements(v->'vendors_gone_quiet') x
   where lower(x->>'vendor') = 'rork';
  if v_quiet > 0 then
    raise exception 'Rork is still reported as gone quiet despite its billing being recorded as ended';
  end if;

  if jsonb_array_length(v->'vendors_recorded_as_ended') < 1 then
    raise exception 'the ended list is empty, so the suppression above may be for the wrong reason';
  end if;

  raise notice 'cadence check: % suspected, % vendor(s) recorded as ended, Rork correctly silent',
    v->>'suspected_missing', jsonb_array_length(v->'vendors_recorded_as_ended');
end
$do$;

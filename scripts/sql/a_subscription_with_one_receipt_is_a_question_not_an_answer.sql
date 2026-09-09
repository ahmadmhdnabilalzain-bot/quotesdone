-- A SUBSCRIPTION WITH ONE RECEIPT IS A QUESTION, NOT AN ANSWER.
--
-- The founder, 9 September 2026: "also include chat gpt bills". Measured after he said it: the book
-- holds exactly ONE OpenAI receipt, 29 Jul 2026, AED 385.00. ChatGPT Pro renews monthly, so August
-- and September should exist. An exhaustive search found them in no mailbox at all -- Gmail across
-- every folder, by amount, by every OpenAI sender, by Stripe's rail, and Outlook. Nothing was booked,
-- because AED 385 x 2 would be an invented figure.
--
-- AND THE REPORT STILL SAID COMPLETE. fn_accountant_receipt_cadence_gaps needs TWO billed months
-- before it will treat a vendor as cadenced, so a vendor with exactly one receipt can never be
-- "gone quiet". It surfaced OpenAI in `vendors_seen_once`, which fed nothing. The weakest signal was
-- attached to the strongest case: one receipt from a monthly subscription means EVERY renewal after
-- it is missing, and that is the situation most worth flagging, not least.
--
-- So a vendor seen once and silent for more than 45 days is now a shortfall -- unless the estate
-- knows why it was only ever going to bill once.
--
-- THREE REASONS A SINGLE RECEIPT IS CORRECT, and each is read off the receipt rather than assumed:
--   ended   the relationship stopped. Rork: "rork was a month thing then i stopped it" (founder).
--   annual  it bills once a year, so one receipt is a full year of coverage. Tasjeel.ae prints
--           "Domain Registration - quotesdone.ae - 1 Year/s (08/06/2026 - 07/06/2027)".
--   one_off a purchase, not a subscription. Twilio prints "Your Twilio account has been funded" --
--           an account top-up, which recurs only when somebody tops it up again.
-- Anything else with one receipt and no explanation is a question the report should be asking.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not book a figure for the missing ChatGPT months, and
-- it does not guess whether the subscription was cancelled. It makes the report say, on its face,
-- that a monthly vendor has one receipt and nobody has explained why -- which is a question only the
-- founder can close, and exactly the kind a report should put to him rather than quietly resolve.

alter table public.vendor_billing_ended
  add column if not exists kind text not null default 'ended';

alter table public.vendor_billing_ended
  drop constraint if exists vendor_billing_ended_kind_ck;
alter table public.vendor_billing_ended
  add constraint vendor_billing_ended_kind_ck
  check (kind in ('ended', 'annual', 'one_off'));

comment on table public.vendor_billing_ended is
  'Why a vendor is not expected to keep billing monthly: ended (the relationship stopped), annual '
  '(one receipt covers a year) or one_off (a purchase, not a subscription). Records WHO said so and '
  'on what basis. Without it, a subscription that stopped and a receipt that never arrived look '
  'identical from inside the book, and the cadence check would report the same closed question on '
  'every report until somebody stopped reading it. Moves no money and invents no figure.';

insert into public.vendor_billing_ended (vendor, ended_after, kind, basis, note)
values
  ('Tasjeel.ae', date '2026-06-08', 'annual', 'receipt',
   'The receipt itself prints "Domain Registration - quotesdone.ae - 1 Year/s (08/06/2026 - '
   || '07/06/2027)". One receipt is a full year of coverage; the next is due around 08 Jun 2027. '
   || 'Read off the document, not assumed.'),
  ('Twilio', date '2026-06-25', 'one_off', 'receipt',
   'The receipt is "Your Twilio account has been funded", USD 20.00 -- an account top-up, not a '
   || 'subscription. It recurs only when the account is funded again, so a single receipt is the '
   || 'expected state. Read off the document, not assumed.')
on conflict (vendor) do update
  set kind = excluded.kind, ended_after = excluded.ended_after,
      basis = excluded.basis, note = excluded.note;

-- A vendor seen once, silent, and unexplained is now reported as a shortfall.
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
  v_n_once  int;
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
  -- A month INSIDE the vendor's own run with no receipt. NEVER suppressed by an explanation: a
  -- vendor that billed May, skipped June and billed July has a real hole whatever happened after.
  gap as (
    select e.vendor, to_char(e.mo, 'YYYY-MM') missing_month
      from expected e
      left join per_vendor_month p on p.vendor = e.vendor and p.mo = e.mo
     where p.vendor is null
  ),
  -- Billed on a cadence, then silent for more than 45 days. 45 rather than 31 so a charge landing a
  -- few days late does not cry wolf. Suppressed only by a recorded explanation.
  stale as (
    select c.vendor, to_char(c.last_mo, 'YYYY-MM') last_month,
           (v_as_of - c.last_mo) days_since_last_month_started, c.receipts
      from cadenced c
      left join public.vendor_billing_ended e on e.vendor = c.vendor
     where v_as_of - c.last_mo > 45 and e.vendor is null
  ),
  -- ONE receipt, silent, and nobody has said why. This is the STRONGEST case, not the weakest: if
  -- that vendor is a monthly subscription then every renewal after it is missing, and no other check
  -- here can see it, because one month is not a cadence. It fed nothing until 9 Sep 2026, which is
  -- how a report claimed completeness while the founder's ChatGPT renewals were unaccounted for.
  single_receipt as (
    select s.vendor, to_char(s.first_mo, 'YYYY-MM') only_month,
           (v_as_of - s.first_mo) days_since
      from span s
      left join public.vendor_billing_ended e on e.vendor = s.vendor
     where s.receipts = 1 and v_as_of - s.first_mo > 45 and e.vendor is null
  ),
  explained as (
    select vendor, to_char(ended_after, 'YYYY-MM') ended_after_month, kind, basis
      from public.vendor_billing_ended
  )
  select
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'missing_month', missing_month)
              order by vendor, missing_month), '[]'::jsonb) from gap),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'last_month', last_month,
              'receipts_seen', receipts, 'days_since', days_since_last_month_started)
              order by vendor), '[]'::jsonb) from stale),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'only_month', only_month,
              'days_since', days_since) order by vendor), '[]'::jsonb) from single_receipt),
    (select coalesce(jsonb_agg(jsonb_build_object('vendor', vendor, 'kind', kind,
              'since', ended_after_month, 'basis', basis) order by vendor), '[]'::jsonb) from explained)
    into v_gaps, v_stale, v_single, v_ended;

  v_n_gap   := jsonb_array_length(v_gaps);
  v_n_stale := jsonb_array_length(v_stale);
  v_n_once  := jsonb_array_length(v_single);

  return jsonb_build_object(
    'as_of', v_as_of,
    'timezone', v_tz,
    'basis', 'Measured from the VENDOR side: what each vendor billed, not what the mailbox received. '
          || 'The intake-side checks (held, refused, unconvertible, unposted) cannot see a receipt '
          || 'that never arrived, which is why a report can read complete while a subscription is '
          || 'missing three months.',
    'months_with_no_receipt_inside_a_run', v_gaps,
    'vendors_gone_quiet', v_stale,
    'vendors_seen_once_unexplained', v_single,
    'vendors_with_a_recorded_reason', v_ended,
    'suspected_missing', v_n_gap + v_n_stale + v_n_once,
    'claim', case when v_n_gap + v_n_stale + v_n_once = 0
              then 'No vendor is missing a month, unexplained-quiet, or seen once without a reason. '
                || 'That is NOT a claim that the book is complete: a vendor never forwarded even '
                || 'once is invisible to this and to every other check here.'
              else 'These are SUSPECTED gaps, not proven ones -- a subscription can be cancelled, '
                || 'downgraded or paused, and a one-off purchase legitimately bills once. Each '
                || 'carries the evidence that produced it, and any of them can be closed for good by '
                || 'recording the vendor in vendor_billing_ended as ended, annual or one_off. The '
                || 'book should not be called complete while one stands unexplained.' end);
end;
$function$;

revoke execute on function public.fn_accountant_receipt_cadence_gaps(date) from public;
grant execute on function public.fn_accountant_receipt_cadence_gaps(date) to service_role;

do $do$
declare v jsonb; v_once int; v_openai int; v_tas int; v_entries int;
begin
  select count(*) into v_entries from public.expense_entries;
  if v_entries = 0 then
    raise exception 'POSITIVE CONTROL FAILED: expense_entries is empty, so nothing here is tested';
  end if;

  -- OpenAI must have exactly one receipt, or "one receipt is now a shortfall" proves nothing here.
  select count(*) into v_openai from public.expense_entries where vendor = 'OpenAI';
  if v_openai <> 1 then
    raise exception 'POSITIVE CONTROL FAILED: OpenAI has % receipt(s), expected exactly 1', v_openai;
  end if;

  v := public.fn_accountant_receipt_cadence_gaps();

  -- The case the founder raised must now be reported.
  select count(*) into v_once from jsonb_array_elements(v->'vendors_seen_once_unexplained') x
   where lower(x->>'vendor') = 'openai';
  if v_once = 0 then
    raise exception 'OpenAI is not reported despite having one receipt and no recorded reason';
  end if;

  -- And an explained one must NOT be, or the check is just noise again.
  select count(*) into v_tas from jsonb_array_elements(v->'vendors_seen_once_unexplained') x
   where lower(x->>'vendor') like 'tasjeel%';
  if v_tas > 0 then
    raise exception 'Tasjeel.ae is reported despite its annual billing being recorded';
  end if;

  raise notice 'cadence: % suspected; OpenAI flagged, Tasjeel and Twilio explained', v->>'suspected_missing';
end
$do$;

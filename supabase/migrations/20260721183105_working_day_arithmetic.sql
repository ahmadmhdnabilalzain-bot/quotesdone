-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721183105   name: working_day_arithmetic
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Every deadline in the refund flow is expressed in WORKING days: 24h before the customer can
-- notify, 3 days before the founder calls. Weekends and UAE public holidays must not burn a
-- supplier's response window - a reveal paid on Thursday evening should not put them in breach by
-- Sunday morning. Built once here so the nudge job, the refund gate and the portal countdown all
-- agree; three separate implementations of "3 working days" is how a supplier gets wrongly charged.
--
-- UAE weekend is Saturday + Sunday (changed from Fri/Sat in January 2022).
-- ISO dow: 6 = Saturday, 7 = Sunday.

create or replace function public.fn_is_working_day(p_date date)
returns boolean language sql stable
set search_path to 'public','pg_temp' as $$
  select extract(isodow from p_date) < 6
     and not exists (select 1 from public.public_holidays h where h.holiday_date = p_date);
$$;

-- Whole working days strictly between two timestamps, counting the start day only if the clock
-- has actually passed it. Used for "has it been 3 working days since we notified them".
create or replace function public.fn_working_days_between(p_from timestamptz, p_to timestamptz)
returns integer language plpgsql stable
set search_path to 'public','pg_temp' as $$
declare d date; n int := 0; last date;
begin
  if p_from is null or p_to is null or p_to <= p_from then return 0; end if;
  d := (p_from at time zone 'Asia/Dubai')::date + 1;
  last := (p_to at time zone 'Asia/Dubai')::date;
  while d <= last loop
    if public.fn_is_working_day(d) then n := n + 1; end if;
    d := d + 1;
  end loop;
  return n;
end $$;

-- The moment N working days after a timestamp, preserving time of day. N=0 rolls forward to the
-- next working day if the start lands on a weekend/holiday, so a deadline is never set on a day
-- nobody works.
create or replace function public.fn_add_working_days(p_from timestamptz, p_days integer)
returns timestamptz language plpgsql stable
set search_path to 'public','pg_temp' as $$
declare d date; left_ int := greatest(0, coalesce(p_days,0)); tod time; res timestamptz;
begin
  if p_from is null then return null; end if;
  d   := (p_from at time zone 'Asia/Dubai')::date;
  tod := (p_from at time zone 'Asia/Dubai')::time;
  while left_ > 0 loop
    d := d + 1;
    if public.fn_is_working_day(d) then left_ := left_ - 1; end if;
  end loop;
  -- if we consumed no days and landed on a non-working day, roll forward
  while not public.fn_is_working_day(d) loop d := d + 1; end loop;
  res := ((d::text || ' ' || tod::text)::timestamp) at time zone 'Asia/Dubai';
  return res;
end $$;

comment on function public.fn_add_working_days is
  'Adds N UAE working days (Sat/Sun and public_holidays excluded), preserving time of day, in Asia/Dubai. Single source of truth for every refund-flow deadline.';

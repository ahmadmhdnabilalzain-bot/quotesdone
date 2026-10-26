-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711192752   name: uae_public_holidays_working_days
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- UAE public holidays calendar + holiday-aware working-day math.
-- Money deadlines (refund window, non-response fines) now skip UAE public
-- holidays in addition to weekends, so deadlines are legally defensible.

create table if not exists public.public_holidays (
  holiday_date date primary key,
  name         text not null,
  confirmed    boolean not null default true,   -- false = moon-sighting estimate
  created_at   timestamptz not null default now()
);
comment on table public.public_holidays is
  'UAE public holiday calendar used by add_working_days(). Islamic dates are moon-sighting dependent; confirm each year.';

-- Match the project-wide deny-by-default posture (RLS on, no policy).
alter table public.public_holidays enable row level security;

-- 2026 UAE public holidays (13 official days). Islamic dates confirmed for 2026.
insert into public.public_holidays (holiday_date, name, confirmed) values
  ('2026-01-01','New Year''s Day', true),
  ('2026-03-19','Eid al-Fitr', true),
  ('2026-03-20','Eid al-Fitr', true),
  ('2026-03-21','Eid al-Fitr', true),
  ('2026-03-22','Eid al-Fitr', true),
  ('2026-05-26','Arafat Day', true),
  ('2026-05-27','Eid al-Adha', true),
  ('2026-05-28','Eid al-Adha', true),
  ('2026-05-29','Eid al-Adha', true),
  ('2026-06-15','Hijri New Year', true),
  ('2026-08-24','Prophet Muhammad''s Birthday', true),
  ('2026-12-02','UAE National Day', true),
  ('2026-12-03','UAE National Day', true),
  -- fixed-Gregorian 2027 holidays (Islamic 2027 dates to be added when announced)
  ('2027-01-01','New Year''s Day', true),
  ('2027-12-02','UAE National Day', true),
  ('2027-12-03','UAE National Day', true)
on conflict (holiday_date) do nothing;

-- date overload: skip weekends (Sat=6, Sun=0) AND public holidays
create or replace function public.add_working_days(d date, n integer)
 returns date
 language plpgsql
 stable
 set search_path to 'public','pg_temp'
as $function$
declare cur date := d; added int := 0; dow int;
begin
  while added < n loop
    cur := cur + 1; dow := extract(dow from cur);
    if dow <> 0 and dow <> 6
       and not exists (select 1 from public.public_holidays h where h.holiday_date = cur)
    then added := added + 1; end if;
  end loop;
  return cur;
end;$function$;

-- timestamptz overload: same, evaluating the calendar date in UAE local time
create or replace function public.add_working_days(start_ts timestamp with time zone, n integer)
 returns timestamp with time zone
 language plpgsql
 stable
 set search_path to 'public','pg_temp'
as $function$
declare d timestamptz := start_ts; added int := 0;
begin
  while added < n loop
    d := d + interval '1 day';
    if extract(isodow from d) < 6
       and not exists (select 1 from public.public_holidays h
                        where h.holiday_date = (d at time zone 'Asia/Dubai')::date)
    then added := added + 1; end if;
  end loop;
  return d;
end;$function$;

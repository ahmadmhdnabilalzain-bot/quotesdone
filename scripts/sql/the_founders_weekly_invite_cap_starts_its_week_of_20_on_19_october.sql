-- Assigned: it_engineer. Founder ruling 1231, in his words: "this week 20, next week 30, the week after 40,
-- until we reach 50 a day".
--
-- THE SCHEDULE WAS ONE WEEK EARLY. the_supplier_invitations_follow_the_founders_weekly_cap_of_20_30_40_then_50.sql
-- (MANIFEST key 2028, the canonical body) returned 30 from 19 Oct, 40 from 26 Oct and 50 from 2 Nov. The week of
-- 20 is the week of 19 Oct, so every step moves one week later: 20 until 25 Oct, 30 from 26 Oct, 40 from 2 Nov,
-- 50 from 9 Nov and never more.
--
-- Only fn_invite_founder_cap changes. fn_invite_ramp (base and ceiling) and enqueue_supplier_invites (v_cap) both
-- take least(..., fn_invite_founder_cap(Dubai today)), read on production 19 Oct 2026, so nothing can exceed 20
-- this week. Measured the same morning: invite_daily_cap = 20, invite_warmup base_cap = 20, ceiling_cap = 50
-- (the configured ceiling the founder cap bounds; unchanged since key 2028), invite_enabled = false.
-- Grants as live: EXECUTE for postgres and service_role only (CREATE OR REPLACE keeps them; the revoke restates).

create or replace function public.fn_invite_founder_cap(p_day date)
returns integer
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when p_day < date '2026-10-26' then 20
    when p_day < date '2026-11-02' then 30
    when p_day < date '2026-11-09' then 40
    else 50
  end;
$fn$;
revoke execute on function public.fn_invite_founder_cap(date) from public, anon, authenticated;

-- Guarded by key: the stored daily cap never sits above this week's 20. A no-op when measured (it held 20).
set local app.change_reason = 'it_engineer: founder ruling 1231, the weekly cap starts its week of 20 on 19 Oct';
update public.app_secrets set value = '20'
 where key = 'invite_daily_cap' and nullif(value, '')::int > 20
   and (now() at time zone 'Asia/Dubai')::date < date '2026-10-26';

-- PROBE (verdict row; DDL in this file, so it does not raise). Reads only.
select case
  when public.fn_invite_founder_cap(date '2026-10-19') <> 20 then 'PROBE FAILED: 19 Oct is not 20'
  when public.fn_invite_founder_cap(date '2026-10-25') <> 20 then 'PROBE FAILED: 25 Oct is not 20'
  when public.fn_invite_founder_cap(date '2026-10-26') <> 30 then 'PROBE FAILED: 26 Oct is not 30'
  when public.fn_invite_founder_cap(date '2026-11-02') <> 40 then 'PROBE FAILED: 2 Nov is not 40'
  when public.fn_invite_founder_cap(date '2026-11-09') <> 50 then 'PROBE FAILED: 9 Nov is not 50'
  when position('fn_invite_founder_cap' in pg_get_functiondef('public.fn_invite_ramp()'::regprocedure)) = 0 then 'PROBE FAILED: the ramp does not read the founder cap'
  when position('fn_invite_founder_cap' in pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure)) = 0 then 'PROBE FAILED: the sender does not clamp to the founder cap'
  else 'PROBE OK' end as verdict;

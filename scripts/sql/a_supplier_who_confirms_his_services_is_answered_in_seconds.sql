-- a_supplier_who_confirms_his_services_is_answered_in_seconds
-- Seat: sales_engineer (the verification gate and its re-run); customer_support is not involved. 10 Nov 2026.
-- Founder, 10 Nov 2026: supplier registration must work 100% before anything else.
--
-- MEASURED ON PRODUCTION, 10 Nov 2026 (docs/reports/2026-11-10-launch-verification.md, should-fix 1):
--   * 03:14:05 and 03:14:13 UTC: supplier_api capabilityConfirm -> rpc fn_sales_engineer_verifies_supplier for a ZZ DEMO
--     supplier ended twice in "canceling statement due to statement timeout" (edge log: "the gate failed after the confirm
--     155057"). In the same postgres log window three other backends were "still waiting for ExclusiveLock on advisory lock
--     [5,0,1576998530,1]". 1576998530 = hashtext('qd_founding_rank'): the lock fn_assign_founding_rank takes, BEFORE every
--     update that makes a supplier verified, and HOLDS UNTIL ITS TRANSACTION ENDS. The local gate was running its probes
--     against production at that minute; those probes approve ZZ DEMO suppliers inside rolled-back transactions that last
--     up to 17 s (a "duration: 17256 ms" plan in the same window), so every approval anywhere queued behind them. A
--     second walk measured one 40.4 s confirm the same way.
--   * The gate itself is cheap: 336 PostgREST calls of it averaged 204 ms (pg_stat_statements); max(founding_rank) is
--     an index read (leads_founding_rank_uidx). The wait was the lock, never the work.
--
-- WHAT CHANGES
--   1. fn_assign_founding_rank TRIES the lock. If another open transaction holds it, the supplier is approved now and
--      left unranked; fn_sales_engineer_reruns_held_verifications ranks him within the minute. Unranked costs nothing:
--      fn_derive_supplier_registration_state and fn_supplier_registration_state read a null rank as 'not_due' (free),
--      and the unique index leads_founding_rank_uidx still makes two suppliers sharing a number impossible.
--   2. fn_sales_engineer_verifies_supplier_now: the gate with lock_timeout 3 s, for a caller a person is waiting on
--      (the services confirm). A row lock it cannot take in 3 s answers {decision:'queued'} instead of hanging; the
--      confirm stands and the minute tick decides.
--   3. fn_sales_engineer_reruns_held_verifications, every minute (cron job sales_engineer_verification_rerun, owned by
--      the sales engineer in writer_seat): ranks every verified supplier left unranked, and re-runs the gate for every supplier still held
--      'services_unconfirmed' although his capability is confirmed for the current version (the gate's own predicate)
--      - the state IS the queue, so a lost call cannot lose a supplier. Measured before this file: 0 such suppliers and
--      0 unranked verified suppliers on production, so the first tick changes nothing real.
--
-- Prevented by: supabase/functions/_shared/founding_rank_race.check.ts (a throwaway Postgres: an approval while another
-- open transaction holds the rank lock must finish in under 2 s and be ranked by the tick; fails on the old body with a
-- lock wait), supabase/functions/_shared/services_hold.test.ts (a timeout is answered 'queued', never retried for 16 s),
-- and the probe a_supplier_who_confirms_his_services_is_answered_in_seconds_probe.sql.

-- 1. The rank never waits on another transaction.
create or replace function public.fn_assign_founding_rank()
returns trigger language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_limit int; v_rank int;
begin
  -- Rank a supplier once, and only once they are a VERIFIED supplier. Claiming a scraped listing
  -- is not registration; registration without documents is not verification.
  if new.founding_rank is not null then return new; end if;
  if coalesce(new.verified,false) is not true then return new; end if;
  if coalesce(new.banned,false) is true then return new; end if;
  if coalesce(new.approval_status,'') in ('rejected','action_required') then return new; end if;

  -- Serialise rank assignment so two concurrent verifications cannot take the same number - but never WAIT for it.
  -- The lock is held to the end of whichever transaction took it; a long one (a probe, a bulk fix) used to stall every
  -- approval behind it (10 Nov 2026: two 8 s statement timeouts and a 40 s confirm). Busy = approve now, rank in the
  -- minute (fn_sales_engineer_reruns_held_verifications). A rank taken in the same transaction re-enters the lock.
  if not pg_try_advisory_xact_lock(hashtext('qd_founding_rank')) then return new; end if;

  v_limit := coalesce((select nullif(value,'')::int from public.app_secrets where key='founding_free_limit'), 1000);
  select coalesce(max(founding_rank),0) + 1 into v_rank from public.leads;

  new.founding_rank := v_rank;
  -- Exemption is permanent: it is stamped at verification and never recalculated, so a supplier
  -- who was inside the first 1,000 stays exempt even as the base grows.
  new.subscription_exempt := (v_rank <= v_limit);
  return new;
end;
$fn$;

-- 2. The gate for a caller a person is waiting on: an answer in seconds, or 'queued'.
create or replace function public.fn_sales_engineer_verifies_supplier_now(p_lead_id bigint, p_source text default 'services_confirmed')
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set lock_timeout to '3s'
as $fn$
declare v jsonb; l record;
begin
  begin
    v := public.fn_sales_engineer_verifies_supplier(p_lead_id, p_source);
    return v || jsonb_build_object('queued', false);
  exception when lock_not_available then
    -- Another transaction holds this supplier's row. Nothing was written (the block rolled back). The tick re-runs the
    -- gate within the minute from the supplier's own state; the caller tells the supplier so.
    select approval_status, licence_gate_reason into l from public.leads where id = p_lead_id;
    return jsonb_build_object('ok', true, 'queued', true, 'decision', 'queued', 'approval_status', l.approval_status,
                              'reason', l.licence_gate_reason, 'rerun_by', 'fn_sales_engineer_reruns_held_verifications');
  end;
end
$fn$;
revoke execute on function public.fn_sales_engineer_verifies_supplier_now(bigint, text) from public, anon, authenticated;

-- 3. The minute tick: rank the unranked, decide the held-but-confirmed.
create or replace function public.fn_sales_engineer_reruns_held_verifications()
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
set lock_timeout to '5s'
as $fn$
declare r record; v jsonb; v_ranked int := 0; v_unranked_left int := 0; v_rerun int := 0; v_approved int := 0; v_busy int := 0;
begin
  -- Rank each verified supplier the rank trigger skipped because the lock was busy, oldest approval first. The no-op
  -- write fires trg_assign_founding_rank, which ranks it (or skips it again while the lock is still held elsewhere).
  for r in select l.id from public.leads l
            where l.verified and l.founding_rank is null and not coalesce(l.banned, false)
              and coalesce(l.approval_status, '') not in ('rejected', 'action_required')
            order by l.approved_at nulls last, l.id limit 50 loop
    begin
      update public.leads set verified = verified where id = r.id;
      if exists (select 1 from public.leads where id = r.id and founding_rank is not null) then v_ranked := v_ranked + 1;
      else v_unranked_left := v_unranked_left + 1; end if;
    exception when lock_not_available then v_busy := v_busy + 1;
    end;
  end loop;

  -- A supplier held only because his services were unconfirmed, whose confirmation is on file for the current version:
  -- the confirm's own gate run did not finish (timeout, queued, lost). The same predicate fn_sales_engineer_verifies_supplier uses.
  for r in select l.id from public.leads l
            where l.approval_status = 'pending' and l.licence_gate_reason = 'services_unconfirmed'
              and exists (select 1 from public.supplier_capabilities c
                           where c.supplier_id = l.id and c.confirmed_at is not null
                             and coalesce(c.confirmed_version, 0) >= coalesce((select max(k.version) from public.supplier_capability_confirmation k
                                                                               where k.supplier_id = l.id), 0))
            order by l.id limit 50 loop
    begin
      v := public.fn_sales_engineer_verifies_supplier(r.id, 'services_confirmed_rerun');
      v_rerun := v_rerun + 1;
      if v ->> 'decision' = 'approved' then v_approved := v_approved + 1; end if;
    exception when lock_not_available then v_busy := v_busy + 1;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'ranked', v_ranked, 'unranked_left', v_unranked_left, 'rerun', v_rerun,
                            'approved', v_approved, 'busy', v_busy);
end
$fn$;
revoke execute on function public.fn_sales_engineer_reruns_held_verifications() from public, anon, authenticated;

-- The tick is cheap only if finding nothing is cheap: two partial indexes over the ~20k leads, each empty on a quiet day.
create index if not exists leads_unranked_verified_idx on public.leads (id) where verified and founding_rank is null;
create index if not exists leads_services_unconfirmed_idx on public.leads (id) where licence_gate_reason = 'services_unconfirmed';

-- The job: every minute, owned by the sales engineer. Not a seat duty: seat_duty refuses anything more frequent than
-- 5 minutes (seat_duty_every_check), and a supplier waiting on the page cannot wait 5. Owned the way
-- reask_refused_turns is: cron_registry says what it is, writer_seat says whose it is.
select cron.schedule('sales_engineer_verification_rerun', '* * * * *',
  $c$set statement_timeout = '50s'; select public.fn_sales_engineer_reruns_held_verifications();$c$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('sales_engineer_verification_rerun', 'a supplier the confirm could not decide is decided within the minute', 'Supplier growth',
   'Every minute: ranks each verified supplier whose founding rank was skipped while another transaction held the rank lock, '
   || 'and re-runs the verification gate for each supplier still held services_unconfirmed although his services are confirmed '
   || 'for the current version. The services confirm answers in seconds; this decides what it could not.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'sales_engineer_verification_rerun', 'sales_engineer',
   'Every minute: fn_sales_engineer_reruns_held_verifications() ranks the unranked verified suppliers and decides the held-but-confirmed ones.',
   'scripts/sql/a_supplier_who_confirms_his_services_is_answered_in_seconds.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines routines, so it must not raise - apply-discipline section 4)
select case
  when not exists (select 1 from pg_proc where proname = 'fn_assign_founding_rank' and prosrc like '%pg_try_advisory_xact_lock(hashtext(''qd_founding_rank''))%')
    then 'PROBE FAILED: fn_assign_founding_rank still waits on the rank lock'
  when not exists (select 1 from pg_proc where proname = 'fn_sales_engineer_verifies_supplier_now' and 'lock_timeout=3s' = any(proconfig))
    then 'PROBE FAILED: fn_sales_engineer_verifies_supplier_now has no lock_timeout of its own'
  when has_function_privilege('anon', 'public.fn_sales_engineer_verifies_supplier_now(bigint,text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_sales_engineer_reruns_held_verifications()', 'execute')
    then 'PROBE FAILED: a new routine is executable by anon or authenticated'
  when not exists (select 1 from cron.job where jobname = 'sales_engineer_verification_rerun' and schedule = '* * * * *' and active)
    then 'PROBE FAILED: the one-minute job is not scheduled'
  else 'PROBE OK' end as verdict;

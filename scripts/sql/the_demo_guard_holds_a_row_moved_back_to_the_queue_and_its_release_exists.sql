-- THE DEMO GUARD HOLDS A ROW MOVED BACK TO THE QUEUE, AND THE RELEASE IT NAMES EXISTS — owner: customer_support
--
-- MEASURED 15 SEP 2026, two defects in one guard.
--
-- 1. THE REMEDY IT NAMES DID NOT EXIST. zzz_fn_notifications_demo_guard stamps every row it holds
--    with "Release with fn_notifications_release_held()", and decision_policy.demo_rehearsal_active
--    says the same. That routine was dropped on 7 Sep (DROPPED.txt). An operator following the hint
--    after a rehearsal gets 42883, and the founder's own held mail stays held.
--
-- 2. IT STOPPED A REAL RECIPIENT ONLY ON THE WAY IN. The trigger was BEFORE INSERT (pg_trigger
--    tgtype 7). During a rehearsal, a held row UPDATEd back to 'queued', by a retry or a hand, was
--    never seen by the guard, and the dispatchers drain 'queued'. The containment was a promise about
--    inserts. zzzz_notifications_demo_capture already watches UPDATE OF status, to_email, to_phone,
--    but it only catches DEMO recipients and subjects. A real recipient re-queued mid-rehearsal
--    passed both.
--
-- WHAT THIS CHANGES.
--   * The guard also fires BEFORE UPDATE OF status, to_email, to_phone. While the switch is on, a row
--     moved INTO a dispatchable status (queued, pending, digest) whose recipient is not
--     @example.invalid is held again. Terminal moves (sent, failed, suppressed, skipped) pass. Insert
--     behaviour is unchanged. The name keeps zzz_ so it still fires before zzzz_ capture (BEFORE
--     triggers fire in name order).
--   * fn_notifications_release_held(p_limit) exists. It refuses while the switch is on. It releases
--     only rows THIS guard held (last_error starts with its own stamp). A row held for being stale,
--     or by the capture guard erroring, is left alone. It sets them to 'queued', and that UPDATE
--     passes back through zzzz_notifications_demo_capture, so any demo recipient or demo subject is
--     turned to 'suppressed' in the same statement. Only a real recipient ends up queued. The
--     staleness bars in send_outbox and send_whatsapp still apply after release.
--
-- WHAT THIS DOES NOT CHANGE. The four direct senders the header of demo_rehearsal_containment.sql
-- lists are still outside this trigger. contact_submit has since moved into the outbox.
-- Measured today: 1 held row, a stale founder_alert that send_whatsapp held. The release does not
-- touch it.

create or replace function public.zzz_fn_notifications_demo_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_on boolean;
begin
  select coalesce((d.value #>> '{}')::boolean, false) into v_on
    from public.decision_policy d where d.key = 'demo_rehearsal_active';
  if not coalesce(v_on, false) then return NEW; end if;

  -- On UPDATE only a move INTO a status a dispatcher drains is judged. A dispatcher marking a row
  -- sent, failed or suppressed is not a send and must not be turned back into held.
  if TG_OP = 'UPDATE' and coalesce(NEW.status, '') not in ('queued', 'pending', 'digest') then return NEW; end if;

  -- RFC 2606 reserves .invalid as permanently undeliverable. Anything else, including NULL, is
  -- treated as possibly real and held. Failing closed is the whole point of this trigger.
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  NEW.status := 'held';
  -- Deliberately does NOT contain the marker pattern: a scan of every text column for it must be
  -- able to reach zero after a teardown.
  NEW.last_error := 'HELD by zzz_notifications_demo_guard: decision_policy.demo_rehearsal_active is '
                 || 'true and the recipient is not a reserved .invalid address. Release with '
                 || 'fn_notifications_release_held() once the rehearsal is torn down.';
  return NEW;
exception when others then
  -- A DIFFERENT PREFIX ON PURPOSE (database review, 15 Sep). The release below picks rows by the
  -- deliberate stamp's prefix. When this fallback shared it, a row held because the guard itself
  -- failed, where nothing was ever judged, would have been released with the rest. A row the guard
  -- could not judge is left for a person to look at.
  NEW.status := 'held';
  NEW.last_error := 'GUARD ERROR, held by zzz_notifications_demo_guard (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $function$;

drop trigger if exists zzz_notifications_demo_guard on public.notifications;
create trigger zzz_notifications_demo_guard
  before insert or update of status, to_email, to_phone on public.notifications
  for each row execute function public.zzz_fn_notifications_demo_guard();

create or replace function public.fn_notifications_release_held(p_limit integer default 1000)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_on boolean; v_queued int := 0; v_suppressed int := 0; v_other int := 0;
begin
  select coalesce((d.value #>> '{}')::boolean, false) into v_on
    from public.decision_policy d where d.key = 'demo_rehearsal_active';
  if coalesce(v_on, false) then
    raise exception 'fn_notifications_release_held refuses while decision_policy.demo_rehearsal_active is true: tear the rehearsal down and set it false first';
  end if;

  with picked as (
    select n.id from public.notifications n
     where n.status = 'held'
       and starts_with(coalesce(n.last_error, ''), 'HELD by zzz_notifications_demo_guard')
     order by n.id
     limit greatest(coalesce(p_limit, 0), 0)
     for update skip locked
  ), released as (
    update public.notifications n
       set status = 'queued',
           last_error = left('released by fn_notifications_release_held at ' || now()::text
                             || '; was: ' || coalesce(n.last_error, ''), 500)
      from picked where n.id = picked.id
    returning n.status   -- the stored status, after zzzz_notifications_demo_capture has judged it
  )
  select count(*) filter (where status = 'queued'),
         count(*) filter (where status = 'suppressed'),
         count(*) filter (where status not in ('queued', 'suppressed'))
    into v_queued, v_suppressed, v_other
    from released;

  return jsonb_build_object('released_to_queue', v_queued, 'captured_as_demo', v_suppressed, 'other', v_other);
end $function$;

revoke execute on function public.fn_notifications_release_held(integer) from public, anon, authenticated;

-- The routine answers with the switch off (it is, measured 15 Sep). This probe releases nothing:
-- a limit of 0 picks no row. Ends in a notice, not an exception, so the DDL above survives.
do $$
declare r jsonb;
begin
  r := public.fn_notifications_release_held(0);
  if r->>'released_to_queue' is distinct from '0' then raise exception 'release with limit 0 moved a row: %', r; end if;
  raise notice 'fn_notifications_release_held answers: %', r;
end $$;

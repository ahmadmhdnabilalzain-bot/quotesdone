-- THE GUARD'S OWN WORDING WAS FAILING THE TEARDOWN PROOF.
--
-- fn_demo_marker_scan matches 'ZZ DEMO | example\.invalid | qd-demo' over every text column in
-- public. The containment shipped an hour earlier wrote the literal string '@example.invalid' into
-- two places that are NOT demo data and are meant to stay:
--
--   decision_policy.description         1 row   (the switch's own explanation)
--   notifications.last_error            8 rows  (the reason stamped on each held notification)
--
-- So the teardown proof — "re-run the scan and assert every count is back to the baseline" — could
-- never reach the baseline while the guard was doing its job. A permanent false positive in the
-- instrument that proves the teardown is exactly the class of defect this whole session is about.
--
-- Reworded to say "a reserved .invalid address", which carries the same meaning and is not the
-- pattern. Nothing about the behaviour changes.

update public.decision_policy
   set description = 'While true, every notifications insert whose recipient is not a reserved '
                     '.invalid address is HELD rather than queued. Set true before seeding a '
                     'ZZ-DEMO rehearsal, false after teardown, then run '
                     'fn_notifications_release_held() to let the real backlog go.'
 where key = 'demo_rehearsal_active';

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

  -- RFC 2606 reserves .invalid as permanently undeliverable. Anything else, including NULL, is
  -- treated as possibly real and held. Failing closed is the whole point of this trigger.
  if coalesce(NEW.to_email, '') ~* '@example[.]invalid$' then return NEW; end if;

  NEW.status := 'held';
  -- Deliberately does NOT contain the marker pattern: fn_demo_marker_scan reads every text column,
  -- and a guard that stamps the pattern on its own rows can never let the teardown proof reach zero.
  NEW.last_error := 'HELD by zzz_notifications_demo_guard: decision_policy.demo_rehearsal_active is '
                 || 'true and the recipient is not a reserved .invalid address. Release with '
                 || 'fn_notifications_release_held() once the rehearsal is torn down.';
  return NEW;
exception when others then
  NEW.status := 'held';
  NEW.last_error := 'HELD by zzz_notifications_demo_guard (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $function$;

update public.notifications
   set last_error = 'HELD by zzz_notifications_demo_guard: decision_policy.demo_rehearsal_active is '
                 || 'true and the recipient is not a reserved .invalid address. Release with '
                 || 'fn_notifications_release_held() once the rehearsal is torn down.'
 where status = 'held' and last_error like '%example.invalid%';

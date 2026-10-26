-- THE DEMO GUARD KEEPS A REHEARSAL OUT OF THE REAL NOTIFICATION STREAM.
--
-- A rehearsal writes fixture rows that look exactly like live ones. This guard is what stops a
-- fixture notification reaching a real person, and it is why a rehearsal can be run against
-- production at all.
--
-- The deployed body differs from the one in demo_rehearsal_containment.sql, which is the definition
-- this routine had before it was last corrected. This file carries what is actually deployed, taken
-- from pg_get_functiondef, and being listed later in MANIFEST.txt it is the current one.
--
-- It is a repository reorganisation: the routine was written inside a file whose name belonged to a
-- programme that no longer exists, and the routine outlived it. Nothing about the behaviour changes.

CREATE OR REPLACE FUNCTION public.zzz_fn_notifications_demo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

-- ---------------------------------------------------------------------------------------------
-- THE HEADER PILL TELLS THE FOUNDER NOTHING CAN BE CHANGED. THAT HAS BEEN FALSE SINCE 15 AUG.
--
-- Measured on production, 16 Aug 2026:
--   phase1_rollback_log newest row: tier='disarm', 15 Aug 2026 12:09 UTC, by
--   management@quotesdone.com — "Founder instruction: remove Observe/Control Mode."
--   public.fn_phase1_disarmed() therefore returns true, and fn_control_mode_require lets every
--   mutating action through without a session.
--
-- fn_control_mode_status knows none of that. It looks only for an OPEN session, finds none, and
-- returns:
--     mode: observe
--     message: "Observe Mode. Everything is readable; nothing can be changed until Control Mode
--               is opened with a code."
--
-- The OS header renders that as a pill reading "Observe" with the tooltip "everything is readable,
-- nothing can be changed". Clicked today on production: the pill is there, and the claim is wrong.
-- Things can be changed. The gate it names was deliberately switched off by the founder himself.
--
-- This is worse than an under-explained number. A screen that overstates a security posture is
-- the one kind of wrong that makes someone act less carefully: it invites the reader to believe a
-- lock is holding when nothing is holding.
--
-- THE FIX IS A THIRD MODE, NOT A REWORDING. 'observe' and 'control' cannot express "the gate is
-- off", so the function gained no way to say it. `disarmed` is returned only while
-- fn_phase1_disarmed() is true, and it disappears by itself the moment a tier='rearm' row is
-- inserted — the state is read, never cached, so it cannot go stale the way this message did.
--
-- The existing two modes are untouched, so a re-armed system behaves exactly as before, and
-- callers that only test `mode = 'control'` (the ones that gate writes) keep working unchanged:
-- 'disarmed' is not 'control', and the actual permission still comes from fn_control_mode_require.
-- This function reports; it does not authorise.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_control_mode_status(p_actor_email text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    -- An open session still reads as Control, disarmed or not: if one exists it is real and it
    -- is audited, and hiding it would be its own lie.
    (select jsonb_build_object(
       'mode','control', 'session_id', s.id, 'reason', s.reason,
       'opened_at', s.opened_at, 'expires_at', s.expires_at,
       'seconds_remaining', greatest(0, extract(epoch from (s.expires_at - now()))::int),
       'actions_used', s.actions_used)
     from public.control_mode_session s
     where s.actor_email = p_actor_email and s.closed_at is null and s.expires_at > now()
     order by s.opened_at desc limit 1),
    -- THE GATE IS OFF. Say so, say who turned it off and when, and say what is still holding —
    -- because "no second factor" is not "no security", and the founder should not read it as one.
    (select jsonb_build_object(
       'mode','disarmed', 'session_id', null,
       'disarmed_at', r.at, 'disarmed_by', r.actor,
       'message','Control Mode is switched off. Changes go through without a code, and every one '
                 ||'of them is still authenticated, attributed and audited. Turned off '
                 ||to_char(r.at at time zone 'UTC','DD Mon YYYY')||' by '||coalesce(r.actor,'an administrator')||'.')
     from public.phase1_rollback_log r
     where public.fn_phase1_disarmed()
     order by r.at desc limit 1),
    jsonb_build_object('mode','observe','session_id', null,
      'message','Observe Mode. Everything is readable; nothing can be changed until Control Mode is opened with a code.'));
$function$;

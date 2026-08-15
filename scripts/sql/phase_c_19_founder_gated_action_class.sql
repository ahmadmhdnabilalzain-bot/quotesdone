-- Phase C — the founder's own channel stops asking him for a phone code.
--
-- The founder's instruction, 15 Aug 2026: "remove the control gate for now… you can't wait every
-- time for me to give you an OTP."
--
-- Measured before writing this: public.fn_phase1_disarmed() = false and there are zero open
-- Control Mode sessions, so the friction is real and not imagined — every order he gave would have
-- demanded a fresh phone code, and Control Mode sessions last fifteen minutes.
--
-- WHAT THIS DOES NOT DO. It does not disarm Control Mode, and it does not reclassify a mutating
-- action as read-only. Calling `founder_command` "read_only" would have been the one-line version
-- and it would have been a lie: the action writes. It would also have put it inside the x-os-key
-- preview bypass, which is read-only by construction — so the shortcut would have opened a static
-- string to the command channel. Both gates share one vocabulary and the vocabulary has to stay
-- true.
--
-- WHAT IT DOES. A fourth classification, `founder_gated`, that says what is actually the case:
--
--   this action WRITES, and it is gated by FOUNDER IDENTITY rather than by Control Mode.
--
-- That is a real control, not an absence of one. fn_founder_command_submit refuses any caller not
-- in public.phase_c_founder_identity — a two-row allow-list — so a stolen ADMIN session still
-- cannot issue a command. None of the other mutating actions has that second factor.
--
-- And the blast radius is narrow by construction. A founder command creates a command record, an
-- interpretation, workflow links, tasks, an outbox row and a trace. It executes nothing. Every
-- consequential thing downstream still passes its own gate: fn_phase_c_authority_check (unknown
-- action fails closed), per-step gate evaluation, reviewer independence, and the four guards that
-- keep a non-refund approval away from him. Issuing an order is closer to filing a ticket than to
-- inbox_send, refund_resolve or blog_publish — which stay exactly as gated as they were.
--
-- THREE THINGS KEPT DELIBERATELY:
--
--   * It is still AUDITED. fn_control_mode_require writes a control_mode_audit row for every
--     founder_gated call. During an incident the record of what was done under the relaxed control
--     is the most valuable thing here, which is the same reasoning the phase-1 disarm branch uses.
--   * It is still outside the x-os-key bypass, because that bypass allows only `read_only`.
--   * A CHECK PINS the new class to the two founder-command actions, exactly as mode_control is
--     pinned to its four. Without that pin, `founder_gated` becomes a general-purpose way to take
--     any mutation out of Control Mode, which is the failure this file is one bad afternoon away
--     from causing.
--
-- Reversing it is one statement: set both actions back to 'mutating'.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ---------------------------------------------------------------- the vocabulary
alter table public.control_mode_action drop constraint if exists control_mode_action_classification_chk;
alter table public.control_mode_action add constraint control_mode_action_classification_chk
  check (classification = any (array['read_only','mutating','mode_control','founder_gated']));

-- The pin. Only the founder's own two command actions may carry it.
alter table public.control_mode_action drop constraint if exists control_mode_action_founder_gated_pinned;
alter table public.control_mode_action add constraint control_mode_action_founder_gated_pinned
  check (classification <> 'founder_gated'
         or action = any (array['founder_command','founder_command_control']));

-- requires_control is GENERATED as (classification = 'mutating'), so founder_gated yields false
-- without touching the column. That is the right shape: the generated column keeps expressing
-- "Control Mode applies", and this class honestly says it does not.
update public.control_mode_action
   set classification = 'founder_gated',
       description = description || ' Founder-identity gated rather than Control Mode gated: it writes a work plan, executes nothing, and refuses any caller who is not the registered founder.'
 where action in ('founder_command','founder_command_control')
   and classification <> 'founder_gated';

-- ---------------------------------------------------------------- the gate
create or replace function public.fn_control_mode_require(p_actor_email text, p_action text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_class text; v_s record;
begin
  -- AUDIT 8.3 TIER 0. Phase 1 rolled back to observe-only. Still audited, deliberately: during an
  -- incident, the record of what was done under the relaxed control is the most valuable thing here.
  if public.fn_phase1_disarmed() then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_allowed_phase1_disarmed', p_action, true,
            'Phase 1 Control Mode is disarmed - see public.phase1_rollback_log for who disarmed it and why');
    return jsonb_build_object('allowed', true, 'mode', 'disarmed',
      'reason', 'Phase 1 Control Mode is disarmed (rollback tier 0)');
  end if;

  select classification into v_class from public.control_mode_action where action = p_action;

  -- FAIL CLOSED. An action nobody classified is an action nobody thought about, and the cost of
  -- being wrong is asymmetric: refusing a read is an inconvenience, allowing an unreviewed mutation
  -- is the incident. The refusal is audited so the missing classification is discoverable.
  if v_class is null then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_unclassified', p_action, false, 'action is not in control_mode_action');
    return jsonb_build_object(
      'allowed', false, 'mode', 'observe', 'error', 'action_classification_required',
      'message', 'This action has not been classified as read-only or mutating, so it is refused. '
              || 'Classify it in control_mode_action (and in os_api ACTION_CLASS) before using it.');
  end if;

  if v_class = 'read_only' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action is registered read-only');
  end if;

  if v_class = 'mode_control' then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'Control Mode plumbing; handled before the gate');
  end if;

  -- FOUNDER-GATED (15 Aug 2026). The founder's own command channel. It writes, so it is audited
  -- exactly like a Control Mode action; it is not gated by Control Mode, because the identity
  -- allow-list in phase_c_founder_identity is the control, and it is a stronger one than a
  -- fifteen-minute session — a stolen admin session is not the founder.
  if v_class = 'founder_gated' then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_allowed_founder_gated', p_action, true,
            'founder-identity gated: writes a work plan only, and fn_founder_command_submit refuses a caller who is not the registered founder');
    return jsonb_build_object('allowed', true, 'mode', 'founder',
      'reason', 'founder-identity gated; Control Mode does not apply to the founder''s own command channel');
  end if;

  select * into v_s from public.control_mode_session
   where actor_email = p_actor_email and closed_at is null and expires_at > now()
   order by opened_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, action, allowed, reason)
    values (p_actor_email, 'action_denied', p_action, false, 'no active Control Mode session');
    return jsonb_build_object('allowed', false, 'mode', 'observe', 'error', 'control_mode_required',
      'message', 'This changes something, so it needs Control Mode. Open it with a code sent to your phone, and say why.');
  end if;

  update public.control_mode_session set actions_used = actions_used + 1 where id = v_s.id;
  insert into public.control_mode_audit (actor_email, event, action, session_id, allowed, reason)
  values (p_actor_email, 'action_allowed', p_action, v_s.id, true, v_s.reason);

  return jsonb_build_object('allowed', true, 'mode', 'control', 'session_id', v_s.id, 'reason', v_s.reason,
                            'seconds_remaining', greatest(0, extract(epoch from (v_s.expires_at - now()))::int));
end $function$;

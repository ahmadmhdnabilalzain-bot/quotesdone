-- The first real use of Control Mode (audit id 100, 4 Aug 13:49:33Z) wrote 12,736 characters into
-- control_mode_audit.reason. The next-largest reason in the table is 36 characters. user_agent is
-- bounded with left(...,300) on the very same INSERT; reason was handed straight through.
--
-- Change is confined to input validation. No control flow, no checks, no return shape, no message
-- text is altered, so the 3.6 certification of 4 Aug still describes this function.
--
-- Truncation is marked, not silent: an audit trail that quietly drops evidence is worse than one
-- that says how much it dropped. 1000 characters is ~28x the largest genuine reason ever written
-- and still leaves a break-glass operator room to explain themselves at 3am. detail now carries
-- reason_chars and reason_truncated so the original length survives even when the text does not.

CREATE OR REPLACE FUNCTION public.fn_control_mode_open(p_actor_email text, p_reason text, p_challenge_id uuid, p_nonce text, p_code text, p_user_id uuid DEFAULT NULL::uuid, p_ip text DEFAULT NULL::text, p_ua text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_c public.control_mode_challenge%rowtype; v_id uuid; v_min int := public.fn_control_mode_minutes();
        v_reason text; v_raw_len int;
begin
  if coalesce(btrim(p_reason),'') = '' then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'no reason given');
    return jsonb_build_object('ok', false, 'error', 'reason_required',
      'message', 'Control Mode needs a reason. It is written into the audit trail beside whatever you change.');
  end if;

  -- Bound the reason exactly as user_agent is bounded below, and record what was dropped.
  v_reason := btrim(p_reason);
  v_raw_len := length(v_reason);
  if v_raw_len > 1000 then
    v_reason := left(v_reason, 1000) || ' [truncated from ' || v_raw_len || ' characters]';
  end if;

  select * into v_c from public.control_mode_challenge
   where id = p_challenge_id
     and admin_email = lower(btrim(p_actor_email))
     and purpose = 'control_mode'
   for update;

  if not found then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'no such Control Mode challenge for this identity');
    return jsonb_build_object('ok', false, 'error', 'challenge_not_found',
      'message', 'That Control Mode request does not exist, or belongs to a different account. Start a new one.');
  end if;

  if v_c.consumed_at is not null then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'challenge already used: ' || coalesce(v_c.consumed_why,'used'));
    return jsonb_build_object('ok', false, 'error', 'challenge_already_used',
      'message', 'That code has already been used. Request a new one.');
  end if;

  if v_c.expires_at <= now() then
    update public.control_mode_challenge set consumed_at = now(), consumed_why = 'expired' where id = v_c.id;
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'challenge expired');
    return jsonb_build_object('ok', false, 'error', 'challenge_expired',
      'message', 'That code has expired. Request a new one.');
  end if;

  if v_c.attempts >= v_c.max_attempts then
    update public.control_mode_challenge set consumed_at = now(), consumed_why = 'attempts_exhausted' where id = v_c.id;
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'attempt limit reached');
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts',
      'message', 'Too many wrong codes. That request is closed - start a new one.');
  end if;

  -- Nonce and code are checked together, and only the hashed code is ever compared.
  if v_c.nonce <> coalesce(p_nonce,'') or v_c.code_hash <> public.fn_otp_hash(coalesce(p_code,'')) then
    update public.control_mode_challenge set attempts = attempts + 1 where id = v_c.id;
    insert into public.control_mode_audit (actor_email, event, allowed, reason, detail)
    values (p_actor_email, 'open_denied', false, 'mfa_failed',
            jsonb_build_object('attempt', v_c.attempts + 1, 'of', v_c.max_attempts));
    return jsonb_build_object('ok', false, 'error', 'mfa_failed',
      'attempts_left', greatest(0, v_c.max_attempts - (v_c.attempts + 1)),
      'message', 'That code is not right. Check the message and try again.');
  end if;

  update public.control_mode_challenge set consumed_at = now(), consumed_why = 'opened' where id = v_c.id;

  update public.control_mode_session
     set closed_at = now(), closed_reason = 'superseded by a new session'
   where actor_email = p_actor_email and closed_at is null;

  insert into public.control_mode_session (user_id, actor_email, reason, expires_at, mfa_method, mfa_ref, ip, user_agent)
  values (p_user_id, p_actor_email, v_reason, now() + make_interval(mins => v_min),
          'control_mode_challenge', v_c.id, p_ip, left(coalesce(p_ua,''), 300))
  returning id into v_id;

  insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason, detail)
  values (p_actor_email, 'open', v_id, true, v_reason,
          jsonb_build_object('minutes', v_min, 'ip', p_ip, 'challenge_id', v_c.id,
                             'reason_chars', v_raw_len, 'reason_truncated', (v_raw_len > 1000)));

  return jsonb_build_object('ok', true, 'session_id', v_id, 'expires_at', now() + make_interval(mins => v_min),
                            'minutes', v_min,
                            'message', 'Control Mode is open for ' || v_min || ' minutes. It closes on its own.');
end $function$;

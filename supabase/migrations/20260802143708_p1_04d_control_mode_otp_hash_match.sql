-- The OTP codes in phone_verifications are NOT plaintext. They are HMAC-SHA256(code, otp_hmac_key)
-- rendered as lowercase hex - a deliberate hardening on 27 Jul, because an unsalted hash of a
-- 6-digit code is reversible from one table leak by precomputing all 10^6.
-- fn_control_mode_open compared the raw code against that column, so it could never match. Every
-- refusal path worked and the ONE path that actually opens Control Mode was dead: a gate that can
-- never be opened is indistinguishable from a gate that works, right up to the moment the founder
-- needs it.
-- Hash on the SQL side with pgcrypto so there is exactly one implementation, and it produces the
-- same lowercase hex the edge function writes.
create or replace function public.fn_otp_hash(p_code text)
returns text language sql stable security definer set search_path = public, extensions as $$
  select encode(extensions.hmac(p_code, (select value from public.app_secrets where key='otp_hmac_key'), 'sha256'), 'hex');
$$;
revoke all on function public.fn_otp_hash(text) from public, anon, authenticated;
grant execute on function public.fn_otp_hash(text) to service_role;

create or replace function public.fn_control_mode_open(
  p_actor_email text, p_reason text, p_phone text, p_code text,
  p_user_id uuid default null, p_ip text default null, p_ua text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pv record; v_id uuid; v_min int := public.fn_control_mode_minutes(); v_hash text;
begin
  if coalesce(btrim(p_reason),'') = '' then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'no reason given');
    return jsonb_build_object('ok', false, 'error', 'reason_required',
      'message', 'Control Mode needs a reason. It is written into the audit trail beside whatever you change.');
  end if;

  v_hash := public.fn_otp_hash(p_code);

  -- Accept either the hashed form (normal) or a literal match, so a verification row written by an
  -- older code path is still usable. The hashed comparison is the one that matters.
  select * into v_pv from public.phone_verifications
   where phone = p_phone and code in (v_hash, p_code) and used_at is null and expires_at > now()
   order by created_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, allowed, reason, detail)
    values (p_actor_email, 'open_denied', false, 'mfa_failed', jsonb_build_object('phone_tail', right(coalesce(p_phone,''),4)));
    return jsonb_build_object('ok', false, 'error', 'mfa_failed',
      'message', 'That code is not valid, has expired, or has already been used. Request a new one.');
  end if;

  update public.phone_verifications set used_at = now() where id = v_pv.id;

  update public.control_mode_session
     set closed_at = now(), closed_reason = 'superseded by a new session'
   where actor_email = p_actor_email and closed_at is null;

  insert into public.control_mode_session (user_id, actor_email, reason, expires_at, mfa_method, mfa_ref, ip, user_agent)
  values (p_user_id, p_actor_email, btrim(p_reason), now() + make_interval(mins => v_min),
          'phone_otp', v_pv.id, p_ip, left(coalesce(p_ua,''), 300))
  returning id into v_id;

  insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason, detail)
  values (p_actor_email, 'open', v_id, true, btrim(p_reason), jsonb_build_object('minutes', v_min, 'ip', p_ip));

  return jsonb_build_object('ok', true, 'session_id', v_id, 'expires_at', now() + make_interval(mins => v_min),
                            'minutes', v_min,
                            'message', 'Control Mode is open for ' || v_min || ' minutes. It closes on its own.');
end $$;

revoke all on function public.fn_control_mode_open(text,text,text,text,uuid,text,text) from public, anon, authenticated;
grant execute on function public.fn_control_mode_open(text,text,text,text,uuid,text,text) to service_role;

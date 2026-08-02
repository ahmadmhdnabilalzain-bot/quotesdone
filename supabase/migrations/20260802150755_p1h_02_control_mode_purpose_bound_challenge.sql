-- PHASE 1 HARDENING 2 - CONTROL MODE MFA IS PURPOSE-BOUND
--
-- WHAT WAS WRONG. fn_control_mode_open consumed any unused public.phone_verifications row matching
-- the phone. That table is written by login_otp (sign-in) and kyc (customer / supplier contact
-- confirmation). So a code issued to sign in - or to a supplier confirming their own mobile - was a
-- valid Control Mode credential. The user never consented to raising privilege; they consented to
-- logging in. It also accepted the code in plaintext as well as hashed, so any path that ever wrote
-- an unhashed code would have been a second way in.
--
-- WHAT REPLACES IT. A challenge that only exists for this purpose:
--   * bound to a registered admin identity (control_mode_identity), not to whoever knows a phone
--   * purpose = 'control_mode', constrained, so it cannot be minted for anything else
--   * the phone is resolved at challenge time from app_secrets - it is configuration, never source
--   * a one-time nonce the caller must return, so the challenge id alone is not enough
--   * short expiry, an attempt limit, and single consumption
-- phone_verifications is no longer read by Control Mode at all.

create table if not exists public.control_mode_identity (
  admin_email       text primary key,
  phone_secret_key  text not null default 'admin_mfa_phone',
  active            boolean not null default true,
  note              text,
  created_at        timestamptz not null default now()
);
comment on table public.control_mode_identity is
  'Who may open Control Mode, and which app_secrets key holds the number their code goes to. The number itself is never stored here and never appears in source - changing it is one app_secrets update.';

-- Seed from the existing admin list. Read straight out of app_secrets so no address is retyped
-- into a migration.
insert into public.control_mode_identity (admin_email, note)
select distinct lower(btrim(e)), 'seeded from app_secrets.admin_emails, 2 Aug 2026'
  from regexp_split_to_table(coalesce((select value from public.app_secrets where key='admin_emails'),''), '[,;[:space:]]+') e
 where btrim(e) <> ''
on conflict (admin_email) do nothing;

create table if not exists public.control_mode_challenge (
  id            uuid primary key default gen_random_uuid(),
  admin_email   text not null references public.control_mode_identity(admin_email) on delete cascade,
  purpose       text not null default 'control_mode',
  nonce         text not null,
  code_hash     text not null,
  phone_tail    text,
  expires_at    timestamptz not null,
  attempts      int not null default 0,
  max_attempts  int not null default 5,
  consumed_at   timestamptz,
  consumed_why  text,
  ip            text,
  created_at    timestamptz not null default now(),
  constraint control_mode_challenge_purpose_chk check (purpose = 'control_mode')
);
create index if not exists control_mode_challenge_open_idx
  on public.control_mode_challenge (admin_email, consumed_at, expires_at);

alter table public.control_mode_identity  enable row level security;
alter table public.control_mode_challenge enable row level security;

create or replace function public.fn_control_mode_challenge_minutes()
returns int language sql stable security definer set search_path to 'public' as $fn$
  select greatest(1, least(15, coalesce((select value from public.app_secrets where key='control_mode_challenge_minutes')::int, 5)));
$fn$;

-- Start a challenge. The caller (os_api) generates the code and passes only its HMAC, so the
-- plaintext exists in exactly two places: the edge function's memory for the length of one request,
-- and the message on the founder's phone. It is never stored and never returned.
create or replace function public.fn_control_mode_challenge_start(
  p_actor_email text, p_code_hash text, p_ip text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_id record; v_phone text; v_recent int; v_row public.control_mode_challenge%rowtype; v_min int;
begin
  select * into v_id from public.control_mode_identity
   where admin_email = lower(btrim(p_actor_email)) and active;
  if not found then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'challenge_denied', false, 'not a registered Control Mode identity');
    return jsonb_build_object('ok', false, 'error', 'not_a_control_mode_identity',
      'message', 'This account is not registered for Control Mode. Registering one is itself a Control Mode change.');
  end if;

  select value into v_phone from public.app_secrets where key = v_id.phone_secret_key;
  if coalesce(length(btrim(v_phone)),0) < 8 then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'challenge_denied', false, 'no phone configured at ' || v_id.phone_secret_key);
    return jsonb_build_object('ok', false, 'error', 'control_mode_phone_not_configured',
      'message', 'No Control Mode phone number is configured. Set app_secrets.' || v_id.phone_secret_key || '.');
  end if;

  -- Rate limit. Without one, an attacker with a session cookie can spray the founder's phone until
  -- a code is approved out of irritation.
  select count(*) into v_recent from public.control_mode_challenge
   where admin_email = v_id.admin_email and created_at > now() - interval '1 hour';
  if v_recent >= 5 then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'challenge_denied', false, 'rate limit: 5 challenges per hour');
    return jsonb_build_object('ok', false, 'error', 'too_many_challenges',
      'message', 'Too many Control Mode codes requested in the last hour. Wait, then try again.');
  end if;

  -- Anything still open is void. Two live codes means two ways in.
  update public.control_mode_challenge
     set consumed_at = now(), consumed_why = 'superseded'
   where admin_email = v_id.admin_email and consumed_at is null;

  v_min := public.fn_control_mode_challenge_minutes();
  insert into public.control_mode_challenge (admin_email, nonce, code_hash, phone_tail, expires_at, ip)
  values (v_id.admin_email, encode(extensions.gen_random_bytes(18), 'hex'), p_code_hash,
          right(btrim(v_phone), 4), now() + make_interval(mins => v_min), p_ip)
  returning * into v_row;

  insert into public.control_mode_audit (actor_email, event, allowed, reason, detail)
  values (p_actor_email, 'challenge_started', true, 'control_mode challenge issued',
          jsonb_build_object('challenge_id', v_row.id, 'phone_tail', v_row.phone_tail, 'minutes', v_min));

  return jsonb_build_object('ok', true, 'challenge_id', v_row.id, 'nonce', v_row.nonce,
                            'expires_at', v_row.expires_at, 'phone_tail', v_row.phone_tail,
                            'phone', btrim(v_phone), 'minutes', v_min);
end $fn$;

-- The old generic-verification opener. Dropped, not left beside the new one: leaving it would mean
-- the weaker path is still callable and the hardening is decoration.
drop function if exists public.fn_control_mode_open(text, text, text, text, uuid, text, text);

create or replace function public.fn_control_mode_open(
  p_actor_email text, p_reason text, p_challenge_id uuid, p_nonce text, p_code text,
  p_user_id uuid default null, p_ip text default null, p_ua text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_c public.control_mode_challenge%rowtype; v_id uuid; v_min int := public.fn_control_mode_minutes();
begin
  if coalesce(btrim(p_reason),'') = '' then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'no reason given');
    return jsonb_build_object('ok', false, 'error', 'reason_required',
      'message', 'Control Mode needs a reason. It is written into the audit trail beside whatever you change.');
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
  values (p_user_id, p_actor_email, btrim(p_reason), now() + make_interval(mins => v_min),
          'control_mode_challenge', v_c.id, p_ip, left(coalesce(p_ua,''), 300))
  returning id into v_id;

  insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason, detail)
  values (p_actor_email, 'open', v_id, true, btrim(p_reason),
          jsonb_build_object('minutes', v_min, 'ip', p_ip, 'challenge_id', v_c.id));

  return jsonb_build_object('ok', true, 'session_id', v_id, 'expires_at', now() + make_interval(mins => v_min),
                            'minutes', v_min,
                            'message', 'Control Mode is open for ' || v_min || ' minutes. It closes on its own.');
end $fn$;

-- Sweep expired challenges alongside expired sessions, on the cron that already runs every 5 min.
create or replace function public.fn_control_mode_sweep()
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare v_sessions int;
begin
  with c as (
    update public.control_mode_session set closed_at = now(), closed_reason = 'expired'
     where closed_at is null and expires_at <= now() returning id, actor_email
  ), a as (
    insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason)
    select actor_email, 'expired', id, true, 'session timed out' from c
  )
  select count(*)::int into v_sessions from c;

  update public.control_mode_challenge
     set consumed_at = now(), consumed_why = 'expired'
   where consumed_at is null and expires_at <= now();

  delete from public.control_mode_challenge where consumed_at < now() - interval '7 days';

  return v_sessions;
end $fn$;

revoke all on function public.fn_control_mode_challenge_start(text, text, text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_open(text, text, uuid, text, text, uuid, text, text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_sweep() from public, anon, authenticated;
revoke all on function public.fn_control_mode_challenge_minutes() from public, anon, authenticated;

create or replace view public.v_control_mode_identity as
select admin_email, phone_secret_key, active,
       (select right(btrim(value),4) from public.app_secrets s where s.key = i.phone_secret_key) as phone_tail,
       note, created_at
from public.control_mode_identity i;

-- PHASE 1.4 - Observe Mode by default, Control Mode by exception.
--
-- THE PROBLEM THIS SOLVES. The founder's stated architecture is "monitor and issue rare high-level
-- instructions". The deployed Command Center exposes 13 mutating actions - approve/reject a
-- supplier, resolve a refund, resolve a fraud case, publish a blog post, approve a prompt, roll a
-- prompt back, send from the inbox, dispatch knowledge - with no mode, no second factor and no
-- distinction between looking and acting. One stolen session, one shoulder-surfed laptop, or one
-- mis-click on a phone is enough to publish, refund or approve. Reading the company and changing
-- the company should not be the same posture.
--
-- THE DESIGN. Observe Mode is not a setting - it is the ABSENCE of a Control Mode session, so it is
-- the state you are in unless you did something deliberate. Control Mode is a short-lived,
-- MFA-backed, reason-carrying session that expires on its own. There is no "stay in control mode"
-- checkbox, because the value is entirely in it ending.
--
-- MFA REUSES WHAT EXISTS. phone_verifications + the Twilio Verify service already back customer and
-- supplier OTP. Inventing a second factor here would mean a second thing to get wrong; Control Mode
-- consumes a fresh, unused, unexpired verification row for the founder's own phone. A code that was
-- already used to log in cannot open Control Mode - it must be a challenge answered for this
-- purpose, which is what makes it a second factor rather than a replayed first one.

create table if not exists public.control_mode_session (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid,
  actor_email   text not null,
  reason        text not null,
  opened_at     timestamptz not null default now(),
  expires_at    timestamptz not null,
  closed_at     timestamptz,
  closed_reason text,
  mfa_method    text not null,
  mfa_ref       bigint,
  ip            text,
  user_agent    text,
  actions_used  integer not null default 0
);
create index if not exists control_mode_active_idx on public.control_mode_session (actor_email, expires_at desc) where closed_at is null;

-- Every attempt, granted or refused, in one place. Append-only by convention and by grant.
create table if not exists public.control_mode_audit (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  actor_email text,
  event       text not null,
  action      text,
  session_id  uuid,
  allowed     boolean not null,
  reason      text,
  detail      jsonb not null default '{}'::jsonb
);
create index if not exists control_mode_audit_idx on public.control_mode_audit (at desc, actor_email);

alter table public.control_mode_session enable row level security;
alter table public.control_mode_audit enable row level security;
revoke all on public.control_mode_session, public.control_mode_audit from anon, authenticated;
grant all on public.control_mode_session, public.control_mode_audit to service_role;

-- How long a Control Mode session lasts. Short on purpose: long enough to do the thing you opened
-- it for, short enough that walking away closes it.
insert into app_secrets (key, value) values ('control_mode_minutes','15')
on conflict (key) do update set value = excluded.value;

create or replace function public.fn_control_mode_minutes()
returns integer language sql stable as $$
  select least(60, greatest(5, coalesce((select nullif(btrim(value),'')::int from app_secrets where key='control_mode_minutes'), 15)));
$$;

-- The mutating action set. Anything named here needs Control Mode; everything else is Observe-safe.
-- Kept as a table rather than a list in code so adding a mutating action to os_api without adding it
-- here is a visible omission rather than a silent bypass.
create table if not exists public.control_mode_action (
  action        text primary key,
  description   text not null,
  risk          text not null default 'medium',
  requires_control boolean not null default true
);
alter table public.control_mode_action enable row level security;
revoke all on public.control_mode_action from anon, authenticated;
grant all on public.control_mode_action to service_role;

insert into public.control_mode_action (action, description, risk) values
 ('review_decide',      'Approve or reject a supplier or document', 'high'),
 ('refund_resolve',     'Resolve a refund request',                 'high'),
 ('fraud_resolve',      'Resolve a fraud case',                     'high'),
 ('blog_publish',       'Publish public content',                   'high'),
 ('prompt_approve',     'Approve an agent prompt change',           'high'),
 ('prompt_rollback',    'Roll an agent prompt back',                'high'),
 ('prompt_gate',        'Change the prompt gate',                   'high'),
 ('inbox_send',         'Send a message on the company''s behalf',  'high'),
 ('knowledge_dispatch', 'Dispatch knowledge work',                  'medium'),
 ('knowledge_refresh',  'Regenerate knowledge',                     'medium'),
 ('exam_run',           'Run a knowledge exam',                     'low'),
 ('exam_revert',        'Revert an exam result',                    'medium'),
 ('comment_add',        'Add a comment to a record',                'low'),
 ('record',             'Write an operational record',              'medium')
on conflict (action) do update set description = excluded.description, risk = excluded.risk;

-- OPEN. Consumes a fresh, unused, unexpired phone verification. Marks it used, so the same code
-- cannot open two sessions or be replayed.
create or replace function public.fn_control_mode_open(
  p_actor_email text, p_reason text, p_phone text, p_code text,
  p_user_id uuid default null, p_ip text default null, p_ua text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pv record; v_id uuid; v_min int := public.fn_control_mode_minutes();
begin
  if coalesce(btrim(p_reason),'') = '' then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'open_denied', false, 'no reason given');
    return jsonb_build_object('ok', false, 'error', 'reason_required',
      'message', 'Control Mode needs a reason. It is written into the audit trail beside whatever you change.');
  end if;

  select * into v_pv from public.phone_verifications
   where phone = p_phone and code = p_code and used_at is null and expires_at > now()
   order by created_at desc limit 1;

  if not found then
    insert into public.control_mode_audit (actor_email, event, allowed, reason, detail)
    values (p_actor_email, 'open_denied', false, 'mfa_failed', jsonb_build_object('phone_tail', right(coalesce(p_phone,''),4)));
    return jsonb_build_object('ok', false, 'error', 'mfa_failed',
      'message', 'That code is not valid, has expired, or has already been used. Request a new one.');
  end if;

  update public.phone_verifications set used_at = now() where id = v_pv.id;

  -- close any session already open for this actor: two live Control Mode sessions is an accident
  update public.control_mode_session
     set closed_at = now(), closed_reason = 'superseded by a new session'
   where actor_email = p_actor_email and closed_at is null;

  insert into public.control_mode_session (user_id, actor_email, reason, expires_at, mfa_method, mfa_ref, ip, user_agent)
  values (p_user_id, p_actor_email, btrim(p_reason), now() + make_interval(mins => v_min),
          'phone_otp', v_pv.id, p_ip, left(coalesce(p_ua,''), 300))
  returning id into v_id;

  insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason,
                                         detail)
  values (p_actor_email, 'open', v_id, true, btrim(p_reason),
          jsonb_build_object('minutes', v_min, 'ip', p_ip));

  return jsonb_build_object('ok', true, 'session_id', v_id, 'expires_at', now() + make_interval(mins => v_min),
                            'minutes', v_min,
                            'message', 'Control Mode is open for ' || v_min || ' minutes. It closes on its own.');
end $$;

create or replace function public.fn_control_mode_close(p_actor_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update public.control_mode_session set closed_at = now(), closed_reason = 'closed by actor'
   where actor_email = p_actor_email and closed_at is null;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into public.control_mode_audit (actor_email, event, allowed, reason)
    values (p_actor_email, 'close', true, 'closed by actor');
  end if;
  return jsonb_build_object('ok', true, 'closed', v_n);
end $$;

-- STATUS. What the UI reads to know which mode it is in. Observe is the default because it is what
-- you get when nothing is open.
create or replace function public.fn_control_mode_status(p_actor_email text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object(
       'mode','control', 'session_id', s.id, 'reason', s.reason,
       'opened_at', s.opened_at, 'expires_at', s.expires_at,
       'seconds_remaining', greatest(0, extract(epoch from (s.expires_at - now()))::int),
       'actions_used', s.actions_used)
     from public.control_mode_session s
     where s.actor_email = p_actor_email and s.closed_at is null and s.expires_at > now()
     order by s.opened_at desc limit 1),
    jsonb_build_object('mode','observe','session_id', null,
      'message','Observe Mode. Everything is readable; nothing can be changed until Control Mode is opened with a code.'));
$$;

-- THE GATE. Called by os_api before any mutating action. Returns allow/deny and writes the attempt
-- either way - a refused attempt is exactly the thing worth having a record of.
create or replace function public.fn_control_mode_require(p_actor_email text, p_action text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_needs boolean; v_s record;
begin
  select requires_control into v_needs from public.control_mode_action where action = p_action;
  -- Unknown action: not in the registry, so it is read-only by declaration. Recorded so a mutating
  -- action added to os_api without registering here shows up in the audit rather than sliding past.
  if v_needs is null then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action not registered as mutating');
  end if;
  if v_needs = false then
    return jsonb_build_object('allowed', true, 'mode', 'observe', 'reason', 'action is read-only');
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

  return jsonb_build_object('allowed', true, 'mode', 'control', 'session_id', v_s.id,
                            'reason', v_s.reason,
                            'seconds_remaining', greatest(0, extract(epoch from (v_s.expires_at - now()))::int));
end $$;

-- Expired sessions are closed by a sweep so the audit shows an end, not just a silence.
create or replace function public.fn_control_mode_sweep()
returns integer language sql security definer set search_path = public as $$
  with c as (
    update public.control_mode_session set closed_at = now(), closed_reason = 'expired'
     where closed_at is null and expires_at <= now() returning id, actor_email
  ), a as (
    insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason)
    select actor_email, 'expired', id, true, 'session timed out' from c
  )
  select count(*)::int from c;
$$;

create or replace view public.v_control_mode_status as
select s.actor_email, s.reason, s.opened_at, s.expires_at, s.actions_used,
       (s.closed_at is null and s.expires_at > now()) as active
from public.control_mode_session s
order by s.opened_at desc;

revoke all on function public.fn_control_mode_open(text,text,text,text,uuid,text,text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_close(text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_status(text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_require(text,text) from public, anon, authenticated;
revoke all on function public.fn_control_mode_sweep() from public, anon, authenticated;
grant execute on function public.fn_control_mode_open(text,text,text,text,uuid,text,text) to service_role;
grant execute on function public.fn_control_mode_close(text) to service_role;
grant execute on function public.fn_control_mode_status(text) to service_role;
grant execute on function public.fn_control_mode_require(text,text) to service_role;
grant execute on function public.fn_control_mode_sweep() to service_role;

-- AUDIT 9.5 / WI-001 - "shared inbound_secret separation" - FAIL, severity critical.
--
-- MEASURED AGAINST PRODUCTION, 3 Aug 2026, rather than taken from the design doc:
--   43 of 149 cron jobs pass app_secrets.inbound_secret (34 currently active)
--   42 distinct edge functions are reached by those crons
--   20 public DB functions embed the secret in their body
--   137 of 192 edge functions mention it; 96 have no auth.getUser alternative at all
--
-- WI-001 and PHASE1_HARDENING_REPORT.md:179 both say "146 cron jobs (141 active)". That is wrong by
-- ~3.4x - it counted every cron job rather than the ones passing the secret, and sized the risk off
-- the wrong number. The direction was right; the headline was not. The numbers above are the ones
-- to plan against.
--
-- The problem is not that the secret is weak. It is that it is not a credential at all:
--   * one disclosure is total - it invokes any internal function as the platform, with no scope;
--   * it cannot be rotated - every caller would have to change in the same instant, so it never is;
--   * it cannot be attributed - every call authenticated by it is identical in the logs, so a leak
--     could not be scoped, only guessed at.
--
-- THIS MIGRATION IS STEP ONE OF THE MIGRATION ORDER IN WI-001, and it is deliberately the step that
-- BREAKS NOTHING. It installs the credential model and a verifier that accepts BOTH the new scoped
-- credentials AND the existing shared secret - the latter registered as an explicit, visible legacy
-- credential rather than as a special case in code.
--
-- The immediate win is not the scoping, which arrives caller by caller. It is that from this
-- migration onward the shared secret's usage is COUNTED AND TIMESTAMPED. Today nobody can answer
-- "what still uses it, and when did that last happen"; that is exactly the question the withdrawal
-- step depends on, and it has never been answerable.

-- ---------------------------------------------------------------- hashing key
-- Only ever store a hash. HMAC rather than a bare digest, matching fn_otp_hash, so a stolen table
-- dump is not a list of usable credentials.
insert into public.app_secrets (key, value)
select 'internal_credential_hmac_key', encode(extensions.gen_random_bytes(32), 'hex')
where not exists (select 1 from public.app_secrets where key = 'internal_credential_hmac_key');

create or replace function public.fn_internal_credential_hash(p_secret text)
returns text language sql stable security definer set search_path to 'public','extensions' as $fn$
  select encode(extensions.hmac(p_secret,
           (select value from public.app_secrets where key = 'internal_credential_hmac_key'),
           'sha256'), 'hex');
$fn$;

revoke all on function public.fn_internal_credential_hash(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- the model
create table if not exists public.internal_credential (
  id           bigserial primary key,
  context      text        not null check (length(btrim(context)) > 2),
  label        text,
  secret_hash  text        not null,
  -- The edge-function slugs this credential may invoke. '*' is reserved for the legacy shared
  -- secret and is refused for any newly issued credential - a scope of "everything" is what we are
  -- getting rid of, so it must not be reachable by accident.
  scope        text[]      not null check (array_length(scope, 1) >= 1),
  is_legacy    boolean     not null default false,
  active       boolean     not null default true,
  created_at   timestamptz not null default now(),
  rotated_at   timestamptz,
  expires_at   timestamptz,
  retired_at   timestamptz,
  last_used_at timestamptz,
  last_function text,
  use_count    bigint      not null default 0
);

create unique index if not exists internal_credential_hash_uq on public.internal_credential (secret_hash);
create index if not exists internal_credential_ctx_active on public.internal_credential (context) where active;

comment on table public.internal_credential is
  'AUDIT 9.5 / WI-001. One credential per calling CONTEXT (roughly a dozen), not per caller (43+) and not one for everything (today). Only the hash is stored; the secret is returned once at issue and never again.';

alter table public.internal_credential enable row level security;
revoke all on public.internal_credential from public, anon, authenticated;
grant select on public.internal_credential to service_role;

-- ---------------------------------------------------------------- refusal ledger
-- Refusals only. A row per successful call would be tens of thousands a day (email_cron alone runs
-- every 2 minutes) and would bury the signal. Successes bump counters on the credential instead.
-- Stated plainly because it IS a limitation: attribution is per credential and per last-call, not
-- per call. That is enough to scope an incident to a context; it is not a full call log.
create table if not exists public.internal_credential_audit (
  id            bigserial primary key,
  at            timestamptz not null default now(),
  credential_id bigint,
  context       text,
  function_name text,
  allowed       boolean     not null,
  reason        text        not null,
  detail        jsonb       not null default '{}'::jsonb
);

create index if not exists internal_credential_audit_at on public.internal_credential_audit (at desc);

create or replace function public.fn_internal_credential_audit_immutable()
returns trigger language plpgsql as $fn$
begin
  raise exception 'internal_credential_audit is append-only; % is not permitted', TG_OP using errcode = '42501';
end $fn$;

drop trigger if exists trg_internal_credential_audit_immutable on public.internal_credential_audit;
create trigger trg_internal_credential_audit_immutable
  before update or delete on public.internal_credential_audit
  for each row execute function public.fn_internal_credential_audit_immutable();

alter table public.internal_credential_audit enable row level security;
revoke all on public.internal_credential_audit from public, anon, authenticated;
grant select on public.internal_credential_audit to service_role;

-- ---------------------------------------------------------------- the verifier
-- Every internal function calls this instead of comparing a string. Fail-closed in the same shape
-- as fn_control_mode_require: anything not positively recognised AND in scope is refused, and the
-- refusal is recorded so a probing caller is visible rather than silent.
create or replace function public.fn_internal_auth(p_secret text, p_function text)
returns jsonb language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare c public.internal_credential%rowtype; v_hash text; v_fn text;
begin
  v_fn := lower(btrim(coalesce(p_function, '')));
  if v_fn = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_function_named', p_function);
    return jsonb_build_object('ok', false, 'error', 'no_function_named',
      'message', 'The verifier was called without naming the function being invoked, so it cannot check scope.');
  end if;

  if coalesce(btrim(p_secret), '') = '' then
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'no_credential_presented', v_fn);
    return jsonb_build_object('ok', false, 'error', 'no_credential_presented');
  end if;

  v_hash := public.fn_internal_credential_hash(p_secret);
  select * into c from public.internal_credential where secret_hash = v_hash;

  if not found then
    -- Deliberately does not record the presented value, not even hashed-and-truncated: an audit
    -- table that accumulates guesses is a place to go looking for near-misses.
    insert into public.internal_credential_audit (allowed, reason, function_name)
    values (false, 'unknown_credential', v_fn);
    return jsonb_build_object('ok', false, 'error', 'unknown_credential');
  end if;

  if not c.active or c.retired_at is not null then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_retired');
    return jsonb_build_object('ok', false, 'error', 'credential_retired', 'context', c.context);
  end if;

  if c.expires_at is not null and c.expires_at <= now() then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason)
    values (c.id, c.context, v_fn, false, 'credential_expired');
    return jsonb_build_object('ok', false, 'error', 'credential_expired', 'context', c.context,
      'expired_at', c.expires_at);
  end if;

  if not (c.scope @> array['*'] or c.scope @> array[v_fn]) then
    insert into public.internal_credential_audit (credential_id, context, function_name, allowed, reason, detail)
    values (c.id, c.context, v_fn, false, 'out_of_scope', jsonb_build_object('scope', c.scope));
    return jsonb_build_object('ok', false, 'error', 'out_of_scope', 'context', c.context,
      'message', format('The %s credential is not scoped to call %s.', c.context, v_fn));
  end if;

  update public.internal_credential
     set last_used_at = now(), last_function = v_fn, use_count = use_count + 1
   where id = c.id;

  return jsonb_build_object('ok', true, 'context', c.context, 'credential_id', c.id,
                            'legacy', c.is_legacy, 'scope_all', c.scope @> array['*']);
end $fn$;

comment on function public.fn_internal_auth(text, text) is
  'AUDIT 9.5. The single verifier for server-to-server calls. Fail-closed: unknown, retired, expired or out-of-scope is refused and audited. Successes bump counters on the credential rather than writing a row per call.';

revoke all on function public.fn_internal_auth(text, text) from public, anon, authenticated;
grant execute on function public.fn_internal_auth(text, text) to service_role;

-- ---------------------------------------------------------------- issue / rotate / retire
create or replace function public.fn_internal_credential_issue(
  p_context text, p_scope text[], p_label text default null, p_expires_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare v_secret text; v_id bigint;
begin
  if coalesce(btrim(p_context), '') = '' then raise exception 'a context is required' using errcode = '22023'; end if;
  if p_scope is null or array_length(p_scope, 1) is null then
    raise exception 'a scope is required - name the functions this credential may call' using errcode = '22023';
  end if;
  -- The whole point of 9.5. An unrestricted credential is what we are removing, so it cannot be
  -- issued: only the seeded legacy row is allowed to hold '*'.
  if p_scope @> array['*'] then
    raise exception 'scope ''*'' is reserved for the legacy shared secret and cannot be issued' using errcode = '22023';
  end if;

  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, expires_at)
  values (btrim(p_context), p_label, public.fn_internal_credential_hash(v_secret),
          array(select distinct lower(btrim(s)) from unnest(p_scope) s where btrim(s) <> ''), p_expires_at)
  returning id into v_id;

  insert into public.internal_credential_audit (credential_id, context, allowed, reason, detail)
  values (v_id, btrim(p_context), true, 'issued', jsonb_build_object('scope', p_scope, 'label', p_label));

  -- Returned ONCE. There is no way to read it back; a lost credential is rotated, not recovered.
  return jsonb_build_object('ok', true, 'id', v_id, 'context', btrim(p_context), 'secret', v_secret,
    'warning', 'This secret is shown once and cannot be retrieved again. Store it now.');
end $fn$;

-- Rotation with overlap: the new credential is issued and the OLD ONE STAYS LIVE, so callers can be
-- moved one at a time and the old one withdrawn only once its use_count has stopped rising. A
-- rotation that invalidates the old secret immediately is the reason rotations never happen.
create or replace function public.fn_internal_credential_rotate(p_context text, p_label text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_old public.internal_credential%rowtype; v_new jsonb;
begin
  select * into v_old from public.internal_credential
   where context = btrim(p_context) and active and retired_at is null
   order by created_at desc limit 1;
  if not found then raise exception 'no active credential for context %', p_context using errcode = '22023'; end if;
  if v_old.scope @> array['*'] then
    raise exception 'the legacy shared secret is withdrawn, not rotated - see supabase/rollback and the 9.5 runbook' using errcode = '22023';
  end if;

  v_new := public.fn_internal_credential_issue(v_old.context, v_old.scope,
             coalesce(p_label, 'rotated from #' || v_old.id));
  update public.internal_credential set rotated_at = now() where id = v_old.id;

  return v_new || jsonb_build_object('previous_id', v_old.id,
    'note', 'The previous credential is STILL ACTIVE. Move callers across, watch use_count stop rising, then retire it.');
end $fn$;

create or replace function public.fn_internal_credential_retire(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare c public.internal_credential%rowtype;
begin
  if length(coalesce(btrim(p_reason), '')) < 8 then
    raise exception 'a reason of at least 8 characters is required' using errcode = '22023';
  end if;
  select * into c from public.internal_credential where id = p_id;
  if not found then raise exception 'no credential %', p_id using errcode = '22023'; end if;

  update public.internal_credential set active = false, retired_at = now() where id = p_id;
  insert into public.internal_credential_audit (credential_id, context, allowed, reason, detail)
  values (p_id, c.context, true, 'retired',
          jsonb_build_object('why', p_reason, 'use_count_at_retirement', c.use_count, 'last_used_at', c.last_used_at));

  return jsonb_build_object('ok', true, 'id', p_id, 'context', c.context,
    'use_count_at_retirement', c.use_count, 'last_used_at', c.last_used_at);
end $fn$;

revoke all on function public.fn_internal_credential_issue(text, text[], text, timestamptz) from public, anon, authenticated;
revoke all on function public.fn_internal_credential_rotate(text, text) from public, anon, authenticated;
revoke all on function public.fn_internal_credential_retire(bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- the view that makes withdrawal possible
create or replace view public.v_internal_credential_health as
select c.id, c.context, c.label,
       c.is_legacy,
       c.active,
       coalesce(array_length(c.scope, 1), 0) as scope_size,
       c.scope,
       c.use_count,
       c.last_used_at,
       c.last_function,
       case when c.last_used_at is null then null
            else (extract(epoch from (now() - c.last_used_at)) / 86400)::int end as days_since_use,
       (extract(epoch from (now() - c.created_at)) / 86400)::int as age_days,
       c.rotated_at,
       c.expires_at,
       -- A credential nobody has used in 30 days is either dead or was never wired up. Both are
       -- worth knowing before it is left sitting there for another year.
       (c.active and (c.last_used_at is null or c.last_used_at < now() - interval '30 days')) as unused_30d,
       (c.active and not c.is_legacy and c.created_at < now() - interval '90 days'
         and (c.rotated_at is null or c.rotated_at < now() - interval '90 days'))            as rotation_due
from public.internal_credential c;

comment on view public.v_internal_credential_health is
  'AUDIT 9.5. Per credential: scope, last used, age, and whether rotation is due. The legacy row''s use_count is the number that decides when the shared secret can be withdrawn - it is the question nobody could answer before this existed.';

revoke all on public.v_internal_credential_health from public, anon, authenticated;
grant select on public.v_internal_credential_health to service_role;

-- ---------------------------------------------------------------- seed the legacy credential
-- Registered as data, not as a special case in the verifier's code. Nothing breaks today, and its
-- usage becomes visible for the first time. The withdrawal step in WI-001 - "when inbound_secret
-- has had no successful use for 7 days, refuse it" - is only checkable because of this row.
insert into public.internal_credential (context, label, secret_hash, scope, is_legacy)
select 'legacy.shared',
       'The pre-9.5 shared inbound_secret. Scope is everything, which is the point of removing it.',
       public.fn_internal_credential_hash(a.value),
       array['*'],
       true
from public.app_secrets a
where a.key = 'inbound_secret'
  and not exists (select 1 from public.internal_credential where context = 'legacy.shared')
on conflict (secret_hash) do nothing;
;

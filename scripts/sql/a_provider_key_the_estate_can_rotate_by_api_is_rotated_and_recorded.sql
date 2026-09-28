-- A PROVIDER KEY THE ESTATE CAN ROTATE BY API IS ROTATED, AND EVERY ROTATION IS RECORDED.
--
-- Assigned: it_engineer (IT duty 15, credential rotation).
--
-- MEASURED (28 Sep 2026, production htdblwldjkcgjvmqkbeh): public.it_credential_rotation holds 0 rows. The daily
-- duty runs (agent_runs 'duty:rotation' every day since 18 Sep, rotated 0): the 89 active internal credentials
-- are all younger than credential_rotate_days = 90 (oldest created 3 Aug; the first falls due 1 Nov 2026), and
-- no third-party key was ever rotated by the estate - each was left to the founder's dashboard.
--
-- The Twilio API key CAN be rotated by API with what app_secrets holds (account SID + auth token create and
-- delete Standard API keys). _shared/it_rotate_by_api.ts, called by resilience_ping, does the provider half; this
-- file is the database half:
--   * it_credential_rotation carries provider rows: provider + old_ref/new_ref (the provider's key IDs, never a
--     secret); old_id/new_id stay required for internal rows only.
--   * fn_it_provider_rotation_claim   is it due (no rotation of this provider open, none within
--                                     credential_rotate_days) - and claims the run so two ticks cannot both rotate.
--     A provider never rotated is due at once, so the first rotation runs on the first tick after this applies.
--   * fn_it_provider_rotation_record  stores the new key in app_secrets AND records the rotation in one
--                                     transaction; returns the row id, never the secret.
--   * fn_it_provider_rotation_retire_due / _retired  the old key is deleted at the provider only after the overlap
--                                     (credential_overlap_hours + two cadences of the duty, the same window
--                                     a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql gives an
--                                     internal credential), then its row is closed.
--   * fn_it_credential_reverify now reads internal rows only; a provider row has no internal_credential.
--
-- Prevented by: supabase/functions/_shared/it_rotate_by_api.test.ts (no secret leaves the module; a key that does
-- not authenticate, or a failed store, never replaces the working one) and the verdict row at the end of this file.

alter table public.it_credential_rotation add column if not exists provider text;
alter table public.it_credential_rotation add column if not exists old_ref text;
alter table public.it_credential_rotation add column if not exists new_ref text;
alter table public.it_credential_rotation alter column old_id drop not null;
alter table public.it_credential_rotation alter column new_id drop not null;
alter table public.it_credential_rotation drop constraint if exists it_credential_rotation_kind_ck;
alter table public.it_credential_rotation add constraint it_credential_rotation_kind_ck check (
  (provider is null and old_id is not null and new_id is not null)
  or (provider is not null and new_ref is not null));

-- The provider -> the app_secrets keys its rotation replaces. One place, so the record cannot write the wrong pair.
create or replace function public.fn_it_provider_rotation_keys(p_provider text)
returns text[] language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case p_provider when 'twilio' then array['twilio_api_key_sid', 'twilio_api_key_secret'] end;
$fn$;
revoke execute on function public.fn_it_provider_rotation_keys(text) from public, anon, authenticated;

create or replace function public.fn_it_provider_rotation_claim(p_provider text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_last timestamptz; v_days int;
begin
  if public.fn_it_provider_rotation_keys(p_provider) is null then
    return jsonb_build_object('due', false, 'reason', 'no rotation is defined for provider ' || coalesce(p_provider, 'null'));
  end if;
  perform pg_advisory_xact_lock(hashtext('it_provider_rotation:' || p_provider));
  if exists (select 1 from public.it_credential_rotation where provider = p_provider and status in ('overlap', 'held')) then
    return jsonb_build_object('due', false, 'reason', 'a rotation of ' || p_provider || ' is still in its overlap');
  end if;
  v_days := coalesce(public.fn_it_threshold('credential_rotate_days'), 90)::int;
  select max(rotated_at) into v_last from public.it_credential_rotation where provider = p_provider;
  if v_last is not null and v_last > now() - make_interval(days => v_days) then
    return jsonb_build_object('due', false, 'reason', 'rotated ' || to_char(v_last, 'YYYY-MM-DD') || ', next after ' || v_days || ' days');
  end if;
  -- A claim in the last 20 hours that recorded nothing is a failed attempt: the next day retries, not the next tick.
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'provider_rotation_claim'
               and counts->>'provider' = p_provider and started_at > now() - interval '20 hours') then
    return jsonb_build_object('due', false, 'reason', 'claimed within the last 20 hours');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'provider_rotation_claim', 'provider', p_provider), null);
  return jsonb_build_object('due', true);
end $fn$;
revoke execute on function public.fn_it_provider_rotation_claim(text) from public, anon, authenticated;

create or replace function public.fn_it_provider_rotation_record(p_provider text, p_old_ref text, p_new_ref text, p_new_secret text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare k text[] := public.fn_it_provider_rotation_keys(p_provider); v_id bigint; v_overlap interval; v_cadence interval;
begin
  if k is null then raise exception 'no rotation is defined for provider %', p_provider; end if;
  if coalesce(p_new_ref, '') = '' or coalesce(p_new_secret, '') = '' then raise exception 'a rotation needs the new key id and its secret'; end if;
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  insert into public.app_secrets (key, value, updated_at) values (k[1], p_new_ref, now()), (k[2], p_new_secret, now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;
  insert into public.it_credential_rotation (context, provider, old_ref, new_ref, secret_key, overlap_until, status, note)
  values (p_provider || '.api_key', p_provider, p_old_ref, p_new_ref, array_to_string(k, ','), now() + v_overlap + 2 * v_cadence,
          case when p_old_ref is null then 'retired' else 'overlap' end,
          'rotated by the provider API; the new key authenticated before it was stored')
  returning id into v_id;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(),
          jsonb_build_object('job', 'duty:rotation:provider', 'provider', p_provider, 'rotation_id', v_id, 'old_ref', p_old_ref, 'new_ref', p_new_ref), null);
  return v_id;
end $fn$;
revoke execute on function public.fn_it_provider_rotation_record(text, text, text, text) from public, anon, authenticated;

create or replace function public.fn_it_provider_rotation_retire_due(p_provider text)
returns table (id bigint, old_ref text) language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select r.id, r.old_ref from public.it_credential_rotation r
   where r.provider = p_provider and r.status in ('overlap', 'held') and r.overlap_until <= now() and r.old_ref is not null
   order by r.id;
$fn$;
revoke execute on function public.fn_it_provider_rotation_retire_due(text) from public, anon, authenticated;

create or replace function public.fn_it_provider_rotation_retired(p_id bigint, p_note text)
returns void language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  update public.it_credential_rotation set status = 'retired', closed_at = now(), note = left(p_note, 500)
   where id = p_id and provider is not null and status in ('overlap', 'held');
$fn$;
revoke execute on function public.fn_it_provider_rotation_retired(bigint, text) from public, anon, authenticated;

-- The canonical body of a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql, with ONE change:
-- the loop reads internal rows only (provider is null). A provider row has no internal_credential to hold or retire.
create or replace function public.fn_it_credential_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.it_credential_rotation; o public.internal_credential; n public.internal_credential;
        v_items jsonb := '[]'::jsonb; n_ret int := 0; n_held int := 0; v_overlap interval; v_cadence interval;
begin
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  for r in select * from public.it_credential_rotation where status in ('overlap', 'held') and provider is null order by id for update loop
    -- Locked, so a use of the old credential between this read and the retire cannot be missed.
    select * into o from public.internal_credential where id = r.old_id for update;
    select * into n from public.internal_credential where id = r.new_id;
    if o.last_used_at is null or o.last_used_at < r.rotated_at then
      if now() >= r.overlap_until then
        update public.internal_credential set active = false, retired_at = now() where id = r.old_id;
        update public.it_credential_rotation set status = 'retired', closed_at = now(),
               note = 'old credential quiet since rotation; new used ' || coalesce(n.use_count, 0) || ' time(s)' where id = r.id;
        n_ret := n_ret + 1;
      end if;
    elsif now() >= r.overlap_until then
      -- Still presented after the rotation: keep it valid past the NEXT run, which decides again.
      update public.internal_credential set expires_at = now() + v_overlap + 2 * v_cadence where id = r.old_id;
      update public.it_credential_rotation set status = 'held', overlap_until = now() + v_overlap,
             note = 'old credential still used by ' || coalesce(o.last_function, '?') || ' at ' || o.last_used_at where id = r.id;
      v_items := v_items || jsonb_build_object('item', r.context, 'subject', o.last_function,
        'title', 'After rotating ' || r.context || ', ' || coalesce(o.last_function, 'a caller') || ' still presents the old credential',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('rotation_id', r.id, 'old_last_used_at', o.last_used_at, 'last_function', o.last_function,
                                       'fix', 'the caller must read ' || r.secret_key || ' from app_secrets at call time'));
      n_held := n_held + 1;
    end if;
  end loop;
  return jsonb_build_object('retired', n_ret, 'held', n_held,
                            'settle', public.fn_it_duty_settle('rotation', v_items),
                            'key_age', public.fn_it_key_age_refresh());
end $fn$;

-- ── VERDICT (a row, never a notice; this file defines routines, so it must not raise) ─────────────
select case
  when public.fn_it_provider_rotation_keys('twilio') is distinct from array['twilio_api_key_sid', 'twilio_api_key_secret']
    then 'PROBE FAILED: the twilio key pair is not the one the Verify callers read'
  when (public.fn_it_provider_rotation_claim('nope')->>'due')::boolean
    then 'PROBE FAILED: an unknown provider was claimed as due'
  when (select count(*) from public.app_secrets where key in ('twilio_account_sid', 'twilio_auth_token', 'twilio_api_key_sid')) <> 3
    then 'PROBE FAILED: app_secrets lacks the Twilio account SID, auth token or current key SID the rotation needs'
  when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname like 'fn_it_provider_rotation%'
                  and has_function_privilege('anon', p.oid, 'execute'))
    then 'PROBE FAILED: anon can execute a provider rotation routine'
  else 'PROBE OK' end as verdict;

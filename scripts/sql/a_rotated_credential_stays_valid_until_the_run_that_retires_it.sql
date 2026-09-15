-- A ROTATED CREDENTIAL STAYS VALID UNTIL THE RUN THAT RETIRES IT, EVERY INTERNAL CREDENTIAL CAN BE
-- ROTATED, AND A THIRD-PARTY KEY IS REMEMBERED 30 DAYS BEFORE ITS FIRST BIRTHDAY.
--
-- Assigned: it_engineer (rotation is IT duty 15; the key-age reminder rides the same duty and reaches
-- the accountant through the renewal watch, IT duty 20).
--
-- WHAT THE 15 SEP AUDIT SAID, AND WHAT WAS MEASURED. "Internal credential rotation is not running:
-- rotated_at is NULL for 92 of 93." Measured 15 Sep 2026 07:52 UTC, the rotation duty IS running:
-- public.fn_it_duties_scheduled carries it (duty 'rotation', every 1 day, canonical file
-- a_blocklist_refusal_is_never_a_listing.sql), agent_runs holds its run of 14 Sep 19:01 UTC with
-- rotated = 0, and the hourly duty in the same routine ('otp') has run 13 times since. rotated_at is
-- NULL because nothing is due: the oldest active credential was created 3 Aug 2026 (43 days), the
-- threshold is 90 days (it_threshold credential_rotate_days), and the soonest expires_at is
-- 3 Aug 2027. The first rotations fall due around 1 Nov 2026, three a day. The one non-null rotated_at
-- is db.internal, rotated by hand on 4 Sep and now inactive. (The founder's 9 Sep "no need for
-- credentials rotate, remove it", founder_instruction 23, was followed on 14 Sep by his approval of the
-- IT duties that include this one, founder_instruction 324; this file changes how the duty works, not
-- whether it exists.)
--
-- THREE DEFECTS THE MEASUREMENT FOUND, fixed here:
--
--   1. THE OLD CREDENTIAL WAS REFUSED BEFORE ANYTHING DECIDED ITS FATE. fn_it_credential_rotate set the
--      old credential's expires_at to rotation + 24 h (credential_overlap_hours), and only
--      fn_it_credential_reverify can hold it for a straggler, but reverify runs inside the same daily
--      duty. The run after a rotation comes ~23 h 55 m later (fn_it_scheduled_due allows 5 minutes of
--      slack), before overlap_until, so it does nothing; the run after that comes ~48 h later. For the
--      day in between, a caller still presenting the old secret was refused by fn_internal_auth
--      (credential_expired) and the "hold" only arrived after the outage it existed to prevent. The old
--      credential now stays valid for the overlap PLUS two cadences of the duty, so the deciding run
--      comes first even when it is late or one run is missed.
--   2. A HOLD GREW WITHOUT BOUND. The held branch extended by (overlap_until - rotated_at). After the
--      first hold overlap_until had moved, so each later hold extended by the whole time since rotation
--      (1 day, then 3, then 7...). It now extends by the configured overlap every time.
--   3. TWO CREDENTIALS COULD NEVER ROTATE. The duty finds a credential's secret at
--      app_secrets.cred_<context, dots as underscores>. fn.wa_inbound_docs and fn.wa_inbound_pdf keep
--      theirs at cred_fn_wa_docs and cred_fn_wa_pdf (measured: those keys' hashes match the two active
--      credentials; wa_inbound reads those two keys), so the duty skipped both forever. Their context
--      label is renamed to match the key the caller already reads. Neither has ever been used
--      (use_count 0), so no audit history carries the old label, and no code compares either label.
--
-- WHY A CONSUMER CANNOT BE BROKEN BY A ROTATION (measured 15 Sep 2026, repository at 4cf0cd2):
--   * All 84 keyed credentials' app_secrets values hash to their active credential (0 mismatches).
--   * Every edge function reads app_secrets per call through its own sec() helper (no module-level
--     cache of a cred_ value found); the SQL callers (fn_backup_kick, fn_kb_embed_dispatch, ...) read
--     it at call time too. The edge functions' environment holds only the seven Supabase-managed
--     variables, GitHub Actions hold only SUPABASE_ACCESS_TOKEN, and the Vercel resilience-ping route
--     presents no credential. No copy of an internal credential lives outside app_secrets.
--   * fn_internal_auth matches on the secret's hash, so the old and the new credential both
--     authenticate during the overlap, and a retired one is refused.
--   * app_secrets' audit trigger (fn_security_audit) redacts the value; fn_protect_app_secret guards
--     five named keys, none of them cred_.
--
-- THIRD-PARTY KEYS (docs/security/THIRD_PARTY_KEY_ROTATION.md). Their rotation is the founder's action
-- in each provider's dashboard. What the estate can do is remember: each key becomes a 'token' row of
-- public.it_expiry whose date is one year after its CURRENT value was first seen, warned at 30 days by
-- fn_it_renewal_watch (the existing handoff to the accountant, escalating to the ceo). The value is
-- recognised by fn_internal_credential_hash (an HMAC under a server-held key), stored in a column no
-- finding carries, so a rewrite of the same value is not a rotation and a new value is, whether or not
-- the writer remembered updated_at. When the founder stores a rotated key the date moves and the watch
-- closes its own handoff.
--
--   node scripts/apply_sql.mjs scripts/sql/a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql --apply --ddl

-- ── 3. THE TWO CONTEXTS TAKE THE NAME OF THE KEY THEIR CALLER ALREADY READS ──────────────────────
-- Renamed only when the key really holds that credential's secret, and only if the new label is free.
update public.internal_credential ic
   set context = m.new_ctx
  from (values ('fn.wa_inbound_docs', 'fn.wa_docs', 'cred_fn_wa_docs'),
               ('fn.wa_inbound_pdf',  'fn.wa_pdf',  'cred_fn_wa_pdf')) m(old_ctx, new_ctx, k)
 where ic.context = m.old_ctx and ic.active and ic.retired_at is null
   and exists (select 1 from public.app_secrets s
                where s.key = m.k and public.fn_internal_credential_hash(s.value) = ic.secret_hash)
   and not exists (select 1 from public.internal_credential o where o.context = m.new_ctx);

-- ── 1. ROTATE: the old credential outlives the run that decides it ───────────────────────────────
create or replace function public.fn_it_credential_rotate(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $fn$
declare c public.internal_credential; v_key text; v_secret text; v_new bigint; v_overlap interval; v_cadence interval;
begin
  select * into c from public.internal_credential where id = p_id and active and retired_at is null for update;
  if not found then raise exception 'fn_it_credential_rotate: no active credential %', p_id; end if;
  if c.is_legacy then raise exception 'fn_it_credential_rotate: % is legacy and is never rotated automatically', c.context; end if;
  v_key := 'cred_' || replace(c.context, '.', '_');
  if not exists (select 1 from public.app_secrets where key = v_key) then
    raise exception 'fn_it_credential_rotate: % has no app_secrets key %, so no caller would receive a new secret', c.context, v_key;
  end if;
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, rotated_at, expires_at)
  values (c.context, c.label, public.fn_internal_credential_hash(v_secret), c.scope, false, true, now(),
          now() + make_interval(days => (coalesce(public.fn_it_threshold('credential_rotate_days'), 90) + 30)::int))
  returning id into v_new;
  -- Every caller reads this key at call time, so this one write moves them all to the new secret.
  update public.app_secrets set value = v_secret, updated_at = now() where key = v_key;
  -- overlap_until is when reverify may first decide; the old credential is still accepted for TWO
  -- more cadences of the duty after that, so the run that decides comes before it is refused even
  -- when that run is late or one run is missed (review of #709: one cadence left no margin at all).
  update public.internal_credential set expires_at = now() + v_overlap + 2 * v_cadence where id = c.id;
  insert into public.it_credential_rotation (context, old_id, new_id, secret_key, overlap_until)
  values (c.context, c.id, v_new, v_key, now() + v_overlap);
  return jsonb_build_object('context', c.context, 'old_id', c.id, 'new_id', v_new, 'overlap_until', now() + v_overlap,
                            'old_valid_until', now() + v_overlap + 2 * v_cadence);
end $fn$;

-- ── THIRD-PARTY KEY AGE ──────────────────────────────────────────────────────────────────────────
alter table public.it_expiry add column if not exists secret_fingerprint text;
alter table public.it_expiry add column if not exists secret_seen_since timestamptz;
comment on column public.it_expiry.secret_fingerprint is
  'For a key:<app_secrets key> row: fn_internal_credential_hash of the value last seen. Never shown in a finding. A different value is a rotation; the same value rewritten is not.';
comment on column public.it_expiry.secret_seen_since is
  'For a key:<app_secrets key> row: when the current value was first seen. The first sighting takes app_secrets.updated_at, the best evidence there is of when it was stored.';

insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source, warn_days)
select 'key:' || k, 'token', null, 'accountant',
       'the founder rotates it in the provider dashboard and stores the new value in app_secrets.' || k ||
       ' (docs/security/THIRD_PARTY_KEY_ROTATION.md); the date moves by itself once the new value is stored',
       'one year after the current value of app_secrets.' || k || ' was first seen (fn_it_key_age_refresh, daily)',
       '{30}'
  from unnest(array['openrouter_api_key', 'stripe_secret_key', 'stripe_webhook_secret', 'resend_api_key',
                    'resend_webhook_signing_secret', 'resend_inbound_signing_secret', 'github_token', 'vercel_token',
                    'dropbox_app_secret', 'dropbox_refresh_token', 'twilio_api_key_secret', 'twilio_auth_token']) k
on conflict (item) do update set kind = excluded.kind, owner_seat = excluded.owner_seat, route = excluded.route,
  source = excluded.source, warn_days = excluded.warn_days;

-- ponytail: the date is the key's first birthday, not a provider-side expiry. A token minted with a
-- shorter expiry (GitHub, Vercel) is warned late; the doc says to mint them for a year. Read the
-- provider's expiry here if one is ever minted shorter.
-- If app_secrets.internal_credential_hmac_key is ever rotated every fingerprint changes and every
-- key's age restarts; that key also re-hashes every internal credential, so it is not rotated lightly.
create or replace function public.fn_it_key_age_refresh()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare e public.it_expiry; v_val text; v_upd timestamptz; v_fp text; v_seen timestamptz;
        n_new int := 0; n_missing int := 0; n_same int := 0;
begin
  for e in select * from public.it_expiry where kind = 'token' and item like 'key:%' order by item for update loop
    v_val := null; v_upd := null;
    select s.value, s.updated_at into v_val, v_upd from public.app_secrets s where s.key = substr(e.item, 5);
    if coalesce(btrim(v_val), '') = '' then
      -- No value to age: the renewal watch reports the unknown date to the accountant.
      update public.it_expiry set expires_on = null, secret_fingerprint = null, secret_seen_since = null,
             checked_at = now() where item = e.item;
      n_missing := n_missing + 1;
      continue;
    end if;
    v_fp := public.fn_internal_credential_hash(v_val);
    if e.secret_fingerprint is distinct from v_fp then
      v_seen := case when e.secret_fingerprint is null then coalesce(v_upd, now()) else now() end;
      update public.it_expiry set secret_fingerprint = v_fp, secret_seen_since = v_seen,
             expires_on = (v_seen + interval '1 year')::date, checked_at = now() where item = e.item;
      n_new := n_new + 1;
    else
      update public.it_expiry set checked_at = now() where item = e.item;
      n_same := n_same + 1;
    end if;
  end loop;
  return jsonb_build_object('changed_or_first_seen', n_new, 'unchanged', n_same, 'missing', n_missing);
end $fn$;
revoke execute on function public.fn_it_key_age_refresh() from public, anon, authenticated;

-- ── 2. REVERIFY: a hold extends by the overlap, and key ages are refreshed on the same daily run ──
create or replace function public.fn_it_credential_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.it_credential_rotation; o public.internal_credential; n public.internal_credential;
        v_items jsonb := '[]'::jsonb; n_ret int := 0; n_held int := 0; v_overlap interval; v_cadence interval;
begin
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_cadence := coalesce((select every from public.it_duty_schedule where duty = 'rotation'), interval '1 day');
  for r in select * from public.it_credential_rotation where status in ('overlap', 'held') order by id for update loop
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

-- Seed the key ages now rather than at the next daily run.
select public.fn_it_key_age_refresh();

-- ── WHAT THIS FILE MUST LEAVE TRUE (an apply that cannot say so is rolled back) ────────────────────
do $chk$
declare v_keyless int; v_rows int; v_dated int; v_due30 int;
begin
  select count(*) into v_keyless from public.internal_credential ic
   where ic.active and ic.retired_at is null and not ic.is_legacy
     and not exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'));
  select count(*), count(expires_on), count(*) filter (where expires_on <= current_date + 30)
    into v_rows, v_dated, v_due30 from public.it_expiry where kind = 'token' and item like 'key:%';
  if v_keyless <> 0 then raise exception 'still % active credential(s) with no app_secrets key the duty can rotate', v_keyless; end if;
  if v_rows <> 12 then raise exception 'expected 12 third-party key rows in it_expiry, found %', v_rows; end if;
  raise notice 'rotation: every active credential has its key; key ages: % rows, % dated, % inside 30 days', v_rows, v_dated, v_due30;
end
$chk$;

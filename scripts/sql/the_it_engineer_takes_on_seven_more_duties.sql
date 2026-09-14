-- THE IT ENGINEER TAKES ON SEVEN MORE DUTIES (9-15), EACH ROUND THE SAME LOOP.
--
-- Assigned: it_engineer (every check, the OTP block and credential rotation it applies itself).
-- Findings are answered by their owning seat: backups -> sales_engineer, sender health ->
-- customer_support, spend -> accountant, everything else -> ceo (function_owner when it names one).
--
-- Founder, 14 Sep 2026: "fine build those tasks for IT agent". Deterministic: comparisons, thresholds
-- and dates, no model call. Every threshold is a row of public.it_threshold with the reason for its
-- value, so no number in this file decides anything on its own.
--
-- HOW IT RUNS. Each duty has a cadence in public.it_duty_schedule. resilience_ping asks
-- fn_it_scheduled_due() which duties are due, takes the HTTP readings only those need
-- (_shared/it_scheduled_readings.ts) and hands them to fn_it_duties_scheduled, which decides and
-- settles findings through fn_it_duty_settle (the_it_engineer_runs_its_duties_every_hour.sql).
-- Readings only a Supabase management token can take (database backups/PITR, org members, disk size)
-- arrive through fn_it_platform_ingest from .github/workflows/it-weekly-readings.yml.
--
-- KNOWN FIXES THE IT ENGINEER APPLIES ITSELF, then re-verifies on the next run:
--   OTP pumping    a burst to a country we do not serve blocks that prefix for 24 hours
--                  (public.otp_blocked_prefix, read by _shared/otp_guard.ts before any Twilio call).
--   credentials    rotated on schedule with an overlap; the old one is retired only once the new one
--                  is in use and the old one has gone quiet (public.it_credential_rotation).
-- Anything else is handed to the owning seat.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_takes_on_seven_more_duties.sql --apply --ddl

-- ── THRESHOLDS AND CADENCES ──────────────────────────────────────────────────────────────────────
create table if not exists public.it_threshold (
  key    text primary key,
  value  numeric,
  unit   text not null,
  basis  text not null check (btrim(basis) <> '')
);
comment on table public.it_threshold is
  'Every number the IT engineer''s scheduled duties compare against, with why it has that value. A null value means "not measured yet" and the check that needs it reports so instead of passing.';
alter table public.it_threshold enable row level security;
drop policy if exists it_threshold_service_role_only on public.it_threshold;
create policy it_threshold_service_role_only on public.it_threshold as permissive for all to public using (false) with check (false);
revoke all on public.it_threshold from anon, authenticated;

insert into public.it_threshold (key, value, unit, basis) values
  ('restore_sample_files',        5,     'files',  'Five backed-up files a month, drawn at random, keeps a Dropbox or storage fault from hiding for more than a month.'),
  ('sender_min_sends_7d',         20,    'emails', 'Below twenty sends a week a single bounce is a 5% rate; the rates are not evaluated on less.'),
  ('sender_bounce_rate_max',      0.02,  'ratio',  'Hard bounces above 2% of sends put a sending domain at risk with the mailbox providers.'),
  ('sender_complaint_rate_max',   0.003, 'ratio',  'Gmail and Yahoo bulk-sender rules: keep spam complaints under 0.3%.'),
  ('spend_anomaly_multiple',      2,     'x',      'A day costing more than twice its own trailing 14-day p90 is not normal variation.'),
  ('spend_floor_aed',             20,    'AED',    'A day under AED 20 is never an anomaly, whatever its multiple: the business is pre-launch and small days swing.'),
  ('otp_burst_per_prefix_hour',   5,     'codes',  'More than five codes in an hour to one 5-digit prefix is a list being walked, not people signing in.'),
  ('otp_sms_per_ip_hour',         10,    'codes',  'Was the literal SMS_PER_IP_HOUR in login_otp; moved here so the IT engineer''s playbook can tighten it.'),
  ('otp_signup_global_hour',      60,    'codes',  'Was the literal SMS_SIGNUP_GLOBAL_HOUR in login_otp; the hourly cap on sign-up codes.'),
  ('otp_block_hours',             24,    'hours',  'How long an automatic prefix block lasts before it is re-evaluated.'),
  ('slow_query_mean_ms',          500,   'ms',     'A statement averaging over half a second is felt by a person waiting on a page.'),
  ('slow_query_min_calls',        50,    'calls',  'Fewer calls than this is a one-off, not a pattern worth an index.'),
  ('table_growth_7d_multiple',    2,     'x',      'A table more than doubling in a week is growth nobody planned.'),
  ('table_growth_min_bytes',      104857600, 'bytes', 'Growth under 100 MB is not worth a finding however fast.'),
  ('connections_ratio_max',       0.8,   'ratio',  'At 80% of max_connections the next burst refuses connections.'),
  ('disk_ratio_max',              0.8,   'ratio',  'Warn at 80% of the plan''s disk so there is time to act.'),
  ('db_disk_limit_bytes',         null,  'bytes',  'Set by fn_it_platform_ingest from the management API; null until the first platform reading.'),
  ('credential_rotate_days',      90,    'days',   'Internal credentials are rotated every 90 days.'),
  ('credential_overlap_hours',    24,    'hours',  'The old credential stays valid this long after rotation so a warm edge instance holding it never breaks.'),
  ('credential_rotations_per_run', 3,    'credentials', 'At most three rotations a day, so one fault cannot take every internal call down at once.'),
  ('access_reconfirm_days',       90,    'days',   'Accepted access is reconfirmed every 90 days.')
on conflict (key) do update set unit = excluded.unit, basis = excluded.basis,
  value = case when public.it_threshold.key = 'db_disk_limit_bytes' then public.it_threshold.value else excluded.value end;

create or replace function public.fn_it_threshold(p_key text)
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select value from public.it_threshold where key = p_key
$fn$;
-- login_otp reads its two ceilings through this as the service role; no browser role may.
revoke execute on function public.fn_it_threshold(text) from public, anon, authenticated;

create table if not exists public.it_duty_schedule (
  duty   text primary key,
  every  interval not null check (every > interval '0'),
  note   text not null
);
alter table public.it_duty_schedule enable row level security;
drop policy if exists it_duty_schedule_service_role_only on public.it_duty_schedule;
create policy it_duty_schedule_service_role_only on public.it_duty_schedule as permissive for all to public using (false) with check (false);
revoke all on public.it_duty_schedule from anon, authenticated;
insert into public.it_duty_schedule (duty, every, note) values
  ('restore',     interval '30 days', 'duty 9: restore a random sample from Dropbox and from Supabase storage'),
  ('backup_gap',  interval '1 day',   'duty 9: every OPEN GAP source in the backup registry'),
  ('sender',      interval '1 day',   'duty 10: SPF/DKIM/DMARC, blocklists, bounce and complaint rates, WhatsApp quality and templates'),
  ('spend',       interval '1 day',   'duty 11: daily spend per provider against its own baseline'),
  ('otp',         interval '1 hour',  'duty 11: OTP pumping'),
  ('access',      interval '30 days', 'duty 13: who holds access on GitHub, Vercel, Stripe, Dropbox'),
  ('db_health',   interval '1 day',   'duty 14: slow queries, table growth, connections, disk'),
  ('rotation',    interval '1 day',   'duty 15: internal credential rotation')
on conflict (duty) do update set every = excluded.every, note = excluded.note;

create or replace function public.fn_it_scheduled_due()
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(s.duty order by s.duty), '{}')
    from public.it_duty_schedule s
   where not exists (select 1 from public.agent_runs r
                      where r.agent = 'it_engineer' and r.counts->>'job' = 'duty:' || s.duty
                        and r.started_at > now() - s.every + interval '5 minutes')
$fn$;
revoke execute on function public.fn_it_scheduled_due() from public, anon, authenticated;

create or replace function public.fn_it_duty_ran(p_duty text, p_result jsonb)
returns void language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duty:' || p_duty, 'result', p_result), null)
$fn$;
revoke execute on function public.fn_it_duty_ran(text, jsonb) from public, anon, authenticated;

-- ── STATE THE DUTIES KEEP ────────────────────────────────────────────────────────────────────────
create table if not exists public.it_spend_daily (
  day          date not null,
  source       text not null,
  amount_minor bigint not null,
  currency     text not null,
  recorded_at  timestamptz not null default now(),
  primary key (day, source)
);
create table if not exists public.it_table_size_daily (
  day    date not null,
  relid  text not null,
  bytes  bigint not null,
  primary key (day, relid)
);
create table if not exists public.otp_blocked_prefix (
  prefix      text primary key check (prefix ~ '^[0-9]{3,8}$'),
  reason      text not null check (btrim(reason) <> ''),
  blocked_by  text not null,
  blocked_at  timestamptz not null default now(),
  expires_at  timestamptz
);
comment on table public.otp_blocked_prefix is
  'Phone-number prefixes (country code + digits, no +) that receive no sign-in code. Read by _shared/otp_guard.ts before any Twilio call. The IT engineer adds a row with an expiry when a burst hits a country we do not serve.';
create table if not exists public.otp_served_country (
  prefix  text primary key check (prefix ~ '^[0-9]{1,4}$'),
  country text not null
);
comment on table public.otp_served_country is
  'Country calling codes the company serves (UAE, the GCC). A burst of codes to any other code is treated as pumping.';
insert into public.otp_served_country (prefix, country) values
  ('971', 'United Arab Emirates'), ('966', 'Saudi Arabia'), ('965', 'Kuwait'),
  ('968', 'Oman'), ('973', 'Bahrain'), ('974', 'Qatar')
on conflict (prefix) do update set country = excluded.country;
create table if not exists public.it_access_known (
  system        text not null,
  principal     text not null,
  reason        text not null check (btrim(reason) <> ''),
  accepted_by   text not null check (btrim(accepted_by) <> ''),
  accepted_at   timestamptz not null default now(),
  last_seen_at  timestamptz,
  primary key (system, principal)
);
comment on table public.it_access_known is
  'Access someone has accepted, with a reason and who accepted it. Starts empty: every principal a provider lists that is not here is raised to the CEO. Principals are logins or ids, never secrets.';
create table if not exists public.it_credential_rotation (
  id            bigint generated always as identity primary key,
  context       text not null,
  old_id        bigint not null references public.internal_credential(id),
  new_id        bigint not null references public.internal_credential(id),
  secret_key    text not null,
  rotated_at    timestamptz not null default now(),
  overlap_until timestamptz not null,
  status        text not null default 'overlap' check (status in ('overlap', 'retired', 'held')),
  closed_at     timestamptz,
  note          text
);
do $rls$
declare t text;
begin
  foreach t in array array['it_spend_daily', 'it_table_size_daily', 'otp_blocked_prefix', 'otp_served_country',
                           'it_access_known', 'it_credential_rotation'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_service_role_only', t);
    execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end
$rls$;

-- Read by _shared/otp_guard.ts (service role) before any code is sent.
create or replace function public.fn_otp_prefix_blocked(p_phone text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select exists (select 1 from public.otp_blocked_prefix b
                  where regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') like b.prefix || '%'
                    and (b.expires_at is null or b.expires_at > now()))
$fn$;
revoke execute on function public.fn_otp_prefix_blocked(text) from public, anon, authenticated;

-- THE HUMAN OVERRIDE (review of #641). The CEO or the founder lifts a block with a reason; the prefix
-- is then allowed, so the next burst does not re-block it, until someone withdraws the allowance.
-- Every lift is recorded in agent_runs (job otp_unblock) with who and why.
create table if not exists public.otp_prefix_allowed (
  prefix      text primary key check (prefix ~ '^[0-9]{3,8}$'),
  reason      text not null check (btrim(reason) <> ''),
  allowed_by  text not null check (allowed_by in ('ceo', 'founder', 'otp_served_country')),
  allowed_at  timestamptz not null default now()
);
alter table public.otp_prefix_allowed enable row level security;
drop policy if exists otp_prefix_allowed_service_role_only on public.otp_prefix_allowed;
create policy otp_prefix_allowed_service_role_only on public.otp_prefix_allowed as permissive for all to public using (false) with check (false);
revoke all on public.otp_prefix_allowed from anon, authenticated;

create or replace function public.fn_it_otp_unblock(p_prefix text, p_reason text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  if coalesce(p_by, '') not in ('ceo', 'founder') then
    raise exception 'fn_it_otp_unblock: only the ceo or the founder lifts a prefix block (got %)', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'fn_it_otp_unblock: a reason is required'; end if;
  if coalesce(p_prefix, '') !~ '^[0-9]{3,8}$' then raise exception 'fn_it_otp_unblock: % is not a digits-only prefix', p_prefix; end if;
  delete from public.otp_blocked_prefix where prefix = p_prefix;
  get diagnostics n = row_count;
  insert into public.otp_prefix_allowed (prefix, reason, allowed_by) values (p_prefix, p_reason, p_by)
  on conflict (prefix) do update set reason = excluded.reason, allowed_by = excluded.allowed_by, allowed_at = now();
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'otp_unblock', 'prefix', p_prefix, 'by', p_by, 'lifted', n), p_reason);
  return jsonb_build_object('ok', true, 'prefix', p_prefix, 'lifted', n, 'allowed_by', p_by);
end $fn$;
revoke execute on function public.fn_it_otp_unblock(text, text, text) from public, anon, authenticated;

-- A country added to otp_served_country lifts every automatic block now inside it.
create or replace function public.trg_otp_served_country_lifts_blocks()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  delete from public.otp_blocked_prefix where prefix like new.prefix || '%' and blocked_by = 'it_engineer';
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'otp_unblock', 'prefix', new.prefix, 'by', 'otp_served_country', 'lifted', n),
            new.country || ' is now a served country');
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_otp_served_country_lifts_blocks() from public, anon, authenticated;
drop trigger if exists otp_served_country_lifts_blocks on public.otp_served_country;
create trigger otp_served_country_lifts_blocks after insert or update of prefix on public.otp_served_country
  for each row execute function public.trg_otp_served_country_lifts_blocks();

-- ── 15. ROTATION ─────────────────────────────────────────────────────────────────────────────────
-- A credential is rotatable when its secret lives in app_secrets under cred_<context with dots as
-- underscores> (84 of 86 active on 14 Sep 2026; fn.wa_inbound_docs and fn.wa_inbound_pdf have no key
-- and are warned by the expiry duty instead). Every caller reads that key at call time, so writing the
-- new secret there moves the callers; the old credential stays valid for the overlap.
create or replace function public.fn_it_credential_rotate(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $fn$
declare c public.internal_credential; v_key text; v_secret text; v_new bigint; v_overlap interval;
begin
  select * into c from public.internal_credential where id = p_id and active and retired_at is null for update;
  if not found then raise exception 'fn_it_credential_rotate: no active credential %', p_id; end if;
  if c.is_legacy then raise exception 'fn_it_credential_rotate: % is legacy and is never rotated automatically', c.context; end if;
  v_key := 'cred_' || replace(c.context, '.', '_');
  if not exists (select 1 from public.app_secrets where key = v_key) then
    raise exception 'fn_it_credential_rotate: % has no app_secrets key %, so no caller would receive a new secret', c.context, v_key;
  end if;
  v_overlap := make_interval(hours => coalesce(public.fn_it_threshold('credential_overlap_hours'), 24)::int);
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, rotated_at, expires_at)
  values (c.context, c.label, public.fn_internal_credential_hash(v_secret), c.scope, false, true, now(),
          now() + make_interval(days => (coalesce(public.fn_it_threshold('credential_rotate_days'), 90) + 30)::int))
  returning id into v_new;
  update public.app_secrets set value = v_secret, updated_at = now() where key = v_key;
  update public.internal_credential set expires_at = now() + v_overlap where id = c.id;
  insert into public.it_credential_rotation (context, old_id, new_id, secret_key, overlap_until)
  values (c.context, c.id, v_new, v_key, now() + v_overlap);
  return jsonb_build_object('context', c.context, 'old_id', c.id, 'new_id', v_new, 'overlap_until', now() + v_overlap);
end $fn$;
revoke execute on function public.fn_it_credential_rotate(bigint) from public, anon, authenticated;

-- The old credential is retired once the overlap is over AND nothing has used it since the rotation.
-- If something still does, it is held: the old stays valid another overlap and the caller's owner is
-- asked (a finding keyed on the context).
create or replace function public.fn_it_credential_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.it_credential_rotation; o public.internal_credential; n public.internal_credential;
        v_items jsonb := '[]'::jsonb; n_ret int := 0; n_held int := 0;
begin
  for r in select * from public.it_credential_rotation where status in ('overlap', 'held') order by id loop
    select * into o from public.internal_credential where id = r.old_id;
    select * into n from public.internal_credential where id = r.new_id;
    if o.last_used_at is null or o.last_used_at < r.rotated_at then
      if now() >= r.overlap_until then
        update public.internal_credential set active = false, retired_at = now() where id = r.old_id;
        update public.it_credential_rotation set status = 'retired', closed_at = now(),
               note = 'old credential quiet since rotation; new used ' || coalesce(n.use_count, 0) || ' time(s)' where id = r.id;
        n_ret := n_ret + 1;
      end if;
    elsif now() >= r.overlap_until then
      update public.internal_credential set expires_at = now() + (r.overlap_until - r.rotated_at) where id = r.old_id;
      update public.it_credential_rotation set status = 'held', overlap_until = now() + (r.overlap_until - r.rotated_at),
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
                            'settle', public.fn_it_duty_settle('rotation', v_items));
end $fn$;
revoke execute on function public.fn_it_credential_reverify() from public, anon, authenticated;

-- ── THE SCHEDULED DUTIES ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_duties_scheduled(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $fn$
declare
  v_due text[] := public.fn_it_scheduled_due(); v_out jsonb := '{}'::jsonb; v_items jsonb; x record; e jsonb;
  d public.doc_backups; v_n numeric; v_d numeric; v_rate numeric; v_mult numeric; v_floor numeric;
  v_p90 numeric; v_max int; v_lim numeric; v_used numeric; c record; v_rot int := 0;
begin
  if jsonb_typeof(coalesce(p_r, '{}'::jsonb)) <> 'object' then
    raise exception 'fn_it_duties_scheduled takes the readings object from _shared/it_scheduled_readings.ts';
  end if;
  v_out := v_out || jsonb_build_object('workflow_heartbeat', public.fn_it_workflow_heartbeats());

  -- ── 9a. RESTORE DRILL ──
  -- Reads: the sample the tick downloaded — each file opened from Dropbox (content hash and size) and
  -- from Supabase storage (size) — against what doc_backups recorded when it was backed up.
  if 'restore' = any (v_due) and jsonb_typeof(p_r->'restore'->'samples') = 'array' then
    v_items := '[]'::jsonb;
    for e in select s from jsonb_array_elements(p_r->'restore'->'samples') s loop
      select * into d from public.doc_backups where id = (e->>'doc_backup_id')::bigint;
      if d.id is null then continue; end if;
      -- Duty 19 (founder, 14 Sep 2026: "add all for accountant and IT"): a restored copy must also open.
      -- Compared as text so a reading taken before duty 19 (no 'opens' key) is not failed for it.
      if not coalesce((e->'dropbox'->>'ok')::boolean, false)
         or (e->'dropbox'->>'opens') = 'false'
         or (d.dropbox_content_hash is not null and e->'dropbox'->>'content_hash' is distinct from d.dropbox_content_hash)
         or (d.dropbox_size is not null and (e->'dropbox'->>'size')::bigint is distinct from d.dropbox_size) then
        v_items := v_items || jsonb_build_object('item', 'dropbox:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.dropbox_path) || ' did not come back intact from Dropbox',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'recorded_hash', d.dropbox_content_hash,
                                         'recorded_size', d.dropbox_size, 'restored', e->'dropbox'));
      end if;
      -- Duty 19: the storage copy must open and must be the same file as the Dropbox copy.
      if d.bucket is not null and (not coalesce((e->'storage'->>'ok')::boolean, false)
         or (e->'storage'->>'opens') = 'false'
         or (e->'storage'->>'content_hash' is not null and e->'dropbox'->>'content_hash' is not null
             and e->'storage'->>'content_hash' <> e->'dropbox'->>'content_hash')
         or (d.bytes is not null and (e->'storage'->>'size')::bigint is distinct from d.bytes)) then
        v_items := v_items || jsonb_build_object('item', 'storage:' || d.id, 'owner_seat', 'sales_engineer', 'subject', 'storage',
          'title', 'Restore drill: ' || coalesce(d.file_name, d.path) || ' did not come back intact from Supabase storage',
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('doc_backup_id', d.id, 'bucket', d.bucket, 'path', d.path, 'recorded_bytes', d.bytes,
                                         'restored', e->'storage'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('restore', public.fn_it_duty_settle('restore', v_items));
    perform public.fn_it_duty_ran('restore', v_out->'restore');
  end if;

  -- ── 9b. OPEN GAPS IN THE BACKUP REGISTRY ──
  if 'backup_gap' = any (v_due) then
    v_items := '[]'::jsonb;
    for x in select * from public.fn_backup_source_registry() r where not r.backed_up loop
      v_items := v_items || jsonb_build_object('item', x.source, 'owner_seat', 'sales_engineer', 'subject', 'dropbox_backup',
        'title', 'Not backed up to Dropbox: ' || x.source || coalesce(' — ' || x.reason, ''),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('source', x.source, 'kind', x.kind, 'bucket', x.bucket));
    end loop;
    v_out := v_out || jsonb_build_object('backup_gap', public.fn_it_duty_settle('backup_gap', v_items));
    perform public.fn_it_duty_ran('backup_gap', v_out->'backup_gap');
  end if;

  -- ── 10. SENDER HEALTH ──
  -- Reads: DNS (SPF, DMARC, DKIM) and blocklists by DNS-over-HTTPS, Resend's own verdict on each
  -- domain record, Twilio's WhatsApp sender quality and template approvals — and from our own tables
  -- the hard bounces and complaints resend_webhook recorded against the emails we sent.
  if 'sender' = any (v_due) and jsonb_typeof(p_r->'sender') = 'object' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(coalesce(p_r->'sender'->'dns', '{}'::jsonb)) loop
      if coalesce(x.value->>'basis', '') = 'measured' then
        if not coalesce((x.value->>'spf')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'spf:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no SPF record that includes our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dmarc')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dmarc:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DMARC record', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
        if not coalesce((x.value->>'dkim')::boolean, false) then
          v_items := v_items || jsonb_build_object('item', 'dkim:' || x.key, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
            'title', x.key || ' has no DKIM key published for our sender', 'blast', 'customer_facing', 'affected', 0, 'evidence', x.value);
        end if;
      end if;
    end loop;
    for e in select b from jsonb_array_elements(coalesce(p_r->'sender'->'blocklists', '[]'::jsonb)) b loop
      if e->>'basis' = 'measured' and coalesce((e->>'listed')::boolean, false) then
        v_items := v_items || jsonb_build_object('item', 'blocklist:' || (e->>'list') || ':' || (e->>'target'), 'owner_seat', 'customer_support',
          'subject', 'send_outbox', 'title', (e->>'target') || ' is listed on ' || (e->>'list'),
          'blast', 'customer_facing', 'affected', 1, 'evidence', e);
      end if;
    end loop;
    if coalesce(p_r->'sender'->'resend'->>'basis', '') = 'measured' and coalesce(p_r->'sender'->'resend'->>'status', '') <> 'verified' then
      v_items := v_items || jsonb_build_object('item', 'resend_domain', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
        'title', 'Resend reports the sending domain as ' || coalesce(p_r->'sender'->'resend'->>'status', 'unknown'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'resend');
    end if;
    if coalesce(p_r->'sender'->'whatsapp'->>'basis', '') = 'measured'
       and upper(coalesce(p_r->'sender'->'whatsapp'->>'quality', '')) not in ('HIGH', 'GREEN', 'UNKNOWN') then
      v_items := v_items || jsonb_build_object('item', 'whatsapp_quality', 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
        'title', 'The WhatsApp number''s quality rating is ' || (p_r->'sender'->'whatsapp'->>'quality'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'sender'->'whatsapp');
    end if;
    for e in select t from jsonb_array_elements(coalesce(p_r->'sender'->'templates', '[]'::jsonb)) t loop
      if e->>'basis' = 'measured' and lower(coalesce(e->>'status', '')) not in ('approved') then
        v_items := v_items || jsonb_build_object('item', 'template:' || (e->>'name'), 'owner_seat', 'customer_support', 'subject', 'send_whatsapp',
          'title', 'WhatsApp template ' || (e->>'name') || ' is ' || coalesce(e->>'status', 'unknown'),
          'blast', 'customer_facing', 'affected', 0, 'evidence', e);
      end if;
    end loop;
    select count(*) into v_d from public.notifications
     where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
    if v_d >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20) then
      select count(*) filter (where reason like 'hard_bounce%'), count(*) filter (where reason = 'spam_complaint')
        into v_n, v_rate from public.email_suppressions
       where source = 'resend_webhook' and created_at > now() - interval '7 days';
      if v_n / v_d > public.fn_it_threshold('sender_bounce_rate_max') then
        v_items := v_items || jsonb_build_object('item', 'bounce_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
          'title', round(100 * v_n / v_d, 2) || '% of last week''s emails hard-bounced', 'blast', 'customer_facing', 'affected', 1,
          'evidence', jsonb_build_object('hard_bounces', v_n, 'sent', v_d, 'max', public.fn_it_threshold('sender_bounce_rate_max')));
      end if;
      if v_rate / v_d > public.fn_it_threshold('sender_complaint_rate_max') then
        v_items := v_items || jsonb_build_object('item', 'complaint_rate', 'owner_seat', 'customer_support', 'subject', 'send_outbox',
          'title', round(100 * v_rate / v_d, 3) || '% of last week''s emails were reported as spam', 'blast', 'customer_facing', 'affected', 1,
          'evidence', jsonb_build_object('complaints', v_rate, 'sent', v_d, 'max', public.fn_it_threshold('sender_complaint_rate_max')));
      end if;
    end if;
    v_out := v_out || jsonb_build_object('sender', public.fn_it_duty_settle('sender', v_items));
    perform public.fn_it_duty_ran('sender', v_out->'sender');
  end if;

  -- ── 11a. SPEND ──
  -- Reads: yesterday's cost per provider the tick could read (Twilio usage, Stripe fees), stored in
  -- it_spend_daily; each source is compared with its own trailing 14 days. The Supabase and Vercel
  -- bills are not readable with the tokens this estate holds, and the reading says so.
  if 'spend' = any (v_due) and jsonb_typeof(p_r->'spend') = 'array' then
    for e in select s from jsonb_array_elements(p_r->'spend') s loop
      if e->>'basis' = 'measured' then
        insert into public.it_spend_daily (day, source, amount_minor, currency)
        values ((e->>'day')::date, e->>'source', (e->>'amount_minor')::bigint, e->>'currency')
        on conflict (day, source) do update set amount_minor = excluded.amount_minor, recorded_at = now();
      end if;
    end loop;
    v_items := '[]'::jsonb;
    v_mult := public.fn_it_threshold('spend_anomaly_multiple'); v_floor := public.fn_it_threshold('spend_floor_aed');
    for x in select s.source, s.day, s.amount_minor, s.currency,
                    (select percentile_cont(0.9) within group (order by b.amount_minor) from public.it_spend_daily b
                      where b.source = s.source and b.day between s.day - 14 and s.day - 1) p90,
                    (select count(*) from public.it_spend_daily b where b.source = s.source and b.day between s.day - 14 and s.day - 1) n
               from public.it_spend_daily s
              where s.day = (select max(day) from public.it_spend_daily t where t.source = s.source) loop
      -- Fewer than seven days of history is not a baseline; the source is reported, not judged.
      continue when x.n < 7;
      if x.amount_minor / 100.0 >= v_floor and x.amount_minor > v_mult * x.p90 then
        v_items := v_items || jsonb_build_object('item', x.source, 'owner_seat', 'accountant', 'subject', x.source,
          'title', x.source || ' cost ' || round(x.amount_minor / 100.0, 2) || ' ' || x.currency || ' on ' || x.day
                   || ', over ' || v_mult || 'x its 14-day p90 of ' || round(x.p90 / 100.0, 2),
          'blast', 'agent_facing', 'affected', 1,
          'evidence', jsonb_build_object('day', x.day, 'amount_minor', x.amount_minor, 'p90_minor', x.p90, 'history_days', x.n));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('spend', public.fn_it_duty_settle('spend', v_items),
                                         'spend_readings', p_r->'spend');
    perform public.fn_it_duty_ran('spend', v_out->'spend');
  end if;

  -- ── 11b. OTP PUMPING — the IT engineer's own playbook ──
  -- Reads: codes issued in the last hour (phone_verifications from login_otp, customer_phone_otps from
  -- mobile_otp) per 5-digit prefix. A burst to a country we do not serve is blocked for
  -- otp_block_hours at once and reported; a burst inside a served country is handed to the CEO,
  -- because blocking it could lock real customers out. The block is re-verified next hour.
  if 'otp' = any (v_due) then
    v_items := '[]'::jsonb;
    v_max := coalesce(public.fn_it_threshold('otp_burst_per_prefix_hour'), 5)::int;
    for x in select left(regexp_replace(phone, '\D', '', 'g'), 5) prefix, count(*) n
               from (select phone, created_at from public.phone_verifications
                     union all select phone, created_at from public.customer_phone_otps) z
              where created_at > now() - interval '1 hour' and phone is not null
              group by 1 having count(*) > v_max loop
      -- A prefix the CEO or founder allowed is never auto-blocked again; its burst is handed on instead.
      if not exists (select 1 from public.otp_served_country s where x.prefix like s.prefix || '%')
         and not exists (select 1 from public.otp_prefix_allowed a where x.prefix like a.prefix || '%') then
        insert into public.otp_blocked_prefix (prefix, reason, blocked_by, expires_at)
        values (x.prefix, x.n || ' codes in an hour to a country we do not serve', 'it_engineer',
                now() + make_interval(hours => coalesce(public.fn_it_threshold('otp_block_hours'), 24)::int))
        on conflict (prefix) do update set expires_at = excluded.expires_at, reason = excluded.reason;
        -- agent_facing with nobody stuck: recorded, and handed on only if it is still happening in six hours.
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n || ' sign-in codes in an hour to +' || x.prefix || '…, a country we do not serve — prefix blocked by the IT engineer',
          'blast', 'agent_facing', 'affected', 0,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n, 'remedy', 'otp_blocked_prefix'));
      else
        v_items := v_items || jsonb_build_object('item', 'prefix:' || x.prefix, 'owner_seat', 'ceo', 'subject', 'login_otp',
          'title', x.n || ' sign-in codes in an hour to +' || x.prefix || '…, inside a country we serve',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('prefix', x.prefix, 'codes_last_hour', x.n,
                                         'why_not_blocked', 'a served country: blocking could lock real customers out'));
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('otp', public.fn_it_duty_settle('otp', v_items));
    perform public.fn_it_duty_ran('otp', v_out->'otp');
  end if;

  -- ── 13. ACCESS REVIEW ──
  -- Reads: who each provider lists (GitHub collaborators and deploy keys, Vercel team members, the
  -- Dropbox account; Supabase members arrive through fn_it_platform_ingest). A principal not accepted
  -- in it_access_known, or accepted longer ago than access_reconfirm_days, is raised to the CEO.
  -- Stripe publishes no team-member API; the reading says so.
  if 'access' = any (v_due) and jsonb_typeof(p_r->'access') = 'object' then
    v_items := public.fn_it_access_items(p_r->'access');
    v_out := v_out || jsonb_build_object('access', public.fn_it_duty_settle('access', v_items));
    perform public.fn_it_duty_ran('access', v_out->'access');
  end if;

  -- ── 14. DATABASE HEALTH ──
  if 'db_health' = any (v_due) then
    v_items := '[]'::jsonb;
    for x in select s.queryid, left(regexp_replace(s.query, '\s+', ' ', 'g'), 200) q, s.calls, round(s.mean_exec_time::numeric, 1) mean_ms
               from extensions.pg_stat_statements s
              where s.calls >= public.fn_it_threshold('slow_query_min_calls')
                and s.mean_exec_time > public.fn_it_threshold('slow_query_mean_ms')
              order by s.mean_exec_time desc limit 10 loop
      v_items := v_items || jsonb_build_object('item', 'slow:' || x.queryid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'A statement averages ' || x.mean_ms || ' ms over ' || x.calls || ' calls: ' || left(x.q, 90),
        'blast', 'internal', 'affected', 1, 'evidence', jsonb_build_object('queryid', x.queryid, 'query', x.q, 'calls', x.calls, 'mean_ms', x.mean_ms));
    end loop;
    insert into public.it_table_size_daily (day, relid, bytes)
    -- pc/pn, not c/n: c is a record variable of this function, and inside PL/pgSQL `c.oid` named the
    -- variable ("record c is not assigned yet"), so the whole routine raised whenever db_health was due.
    select current_date, pc.oid::regclass::text, pg_total_relation_size(pc.oid)
      from pg_class pc join pg_namespace pn on pn.oid = pc.relnamespace
     where pn.nspname = 'public' and pc.relkind = 'r'
    on conflict (day, relid) do update set bytes = excluded.bytes;
    for x in select t.relid, t.bytes, o.bytes old_bytes from public.it_table_size_daily t
               join public.it_table_size_daily o on o.relid = t.relid and o.day = current_date - 7
              where t.day = current_date
                and t.bytes > public.fn_it_threshold('table_growth_7d_multiple') * o.bytes
                and t.bytes - o.bytes > public.fn_it_threshold('table_growth_min_bytes') loop
      v_items := v_items || jsonb_build_object('item', 'growth:' || x.relid, 'owner_seat', 'ceo', 'subject', 'database',
        'title', x.relid || ' grew from ' || pg_size_pretty(x.old_bytes) || ' to ' || pg_size_pretty(x.bytes) || ' in a week',
        'blast', 'internal', 'affected', 1, 'evidence', jsonb_build_object('bytes', x.bytes, 'bytes_7d_ago', x.old_bytes));
    end loop;
    select count(*) into v_used from pg_stat_activity;
    v_lim := current_setting('max_connections')::numeric;
    if v_used > public.fn_it_threshold('connections_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'connections', 'owner_seat', 'ceo', 'subject', 'database',
        'title', v_used || ' of ' || v_lim || ' database connections are in use',
        'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('in_use', v_used, 'max', v_lim));
    end if;
    v_lim := public.fn_it_threshold('db_disk_limit_bytes');
    if v_lim is not null and pg_database_size(current_database()) > public.fn_it_threshold('disk_ratio_max') * v_lim then
      v_items := v_items || jsonb_build_object('item', 'disk', 'owner_seat', 'accountant', 'subject', 'database',
        'title', 'The database uses ' || pg_size_pretty(pg_database_size(current_database())) || ' of ' || pg_size_pretty(v_lim::bigint),
        'blast', 'customer_facing', 'affected', 0,
        'evidence', jsonb_build_object('bytes', pg_database_size(current_database()), 'limit_bytes', v_lim,
                                       'route', 'the accountant approves a larger disk or plan'));
    end if;
    v_out := v_out || jsonb_build_object('db_health', public.fn_it_duty_settle('db_health', v_items),
                                         'disk_limit_basis', case when v_lim is null then 'not_measured_yet' else 'measured' end);
    perform public.fn_it_duty_ran('db_health', v_out->'db_health');
  end if;

  -- ── 15. ROTATION ──
  if 'rotation' = any (v_due) then
    for c in select ic.id from public.internal_credential ic
              where ic.active and ic.retired_at is null and not ic.is_legacy
                and exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))
                and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
                and (coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => public.fn_it_threshold('credential_rotate_days')::int)
                     or ic.expires_at < now() + interval '30 days')
              order by coalesce(ic.rotated_at, ic.created_at)
              limit public.fn_it_threshold('credential_rotations_per_run')::int loop
      perform public.fn_it_credential_rotate(c.id);
      v_rot := v_rot + 1;
    end loop;
    v_out := v_out || jsonb_build_object('rotation', jsonb_build_object('rotated', v_rot, 'reverify', public.fn_it_credential_reverify()));
    perform public.fn_it_duty_ran('rotation', v_out->'rotation');
  end if;

  return v_out;
end $fn$;
revoke execute on function public.fn_it_duties_scheduled(jsonb) from public, anon, authenticated;

-- ── 13. WHO IS NOT ACCEPTED ──────────────────────────────────────────────────────────────────────
-- p_access: {<system>: {basis, principals:[{principal, role}]}}. Updates last_seen_at on accepted rows.
create or replace function public.fn_it_access_items(p_access jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x record; e jsonb; v_items jsonb := '[]'::jsonb; k public.it_access_known;
begin
  for x in select key, value from jsonb_each(p_access) loop
    continue when coalesce(x.value->>'basis', '') <> 'measured';
    for e in select p from jsonb_array_elements(coalesce(x.value->'principals', '[]'::jsonb)) p loop
      select * into k from public.it_access_known where system = x.key and principal = e->>'principal';
      if k.principal is null then
        v_items := v_items || jsonb_build_object('item', x.key || ':' || (e->>'principal'), 'owner_seat', 'ceo', 'subject', x.key,
          'title', (e->>'principal') || ' has ' || coalesce(e->>'role', 'access') || ' on ' || x.key || ' and nobody has accepted it',
          'blast', 'security', 'affected', 1,
          'evidence', jsonb_build_object('system', x.key, 'principal', e->>'principal', 'role', e->>'role',
                                         'accept', 'select public.fn_it_access_accept(system, principal, reason, accepted_by)'));
      else
        update public.it_access_known set last_seen_at = now() where system = k.system and principal = k.principal;
        if k.accepted_at < now() - make_interval(days => public.fn_it_threshold('access_reconfirm_days')::int) then
          v_items := v_items || jsonb_build_object('item', x.key || ':' || k.principal || ':reconfirm', 'owner_seat', 'ceo', 'subject', x.key,
            'title', k.principal || '''s access on ' || x.key || ' was accepted on ' || k.accepted_at::date || ' and is due to be reconfirmed',
            'blast', 'agent_facing', 'affected', 0, 'evidence', to_jsonb(k));
        end if;
      end if;
    end loop;
  end loop;
  return v_items;
end $fn$;
revoke execute on function public.fn_it_access_items(jsonb) from public, anon, authenticated;

create or replace function public.fn_it_access_accept(p_system text, p_principal text, p_reason text, p_accepted_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_reason), '') = '' or coalesce(btrim(p_accepted_by), '') = '' then
    raise exception 'fn_it_access_accept: accepting access needs a reason and who accepted it';
  end if;
  insert into public.it_access_known (system, principal, reason, accepted_by)
  values (p_system, p_principal, p_reason, p_accepted_by)
  on conflict (system, principal) do update set reason = excluded.reason, accepted_by = excluded.accepted_by, accepted_at = now();
  return jsonb_build_object('ok', true, 'system', p_system, 'principal', p_principal);
end $fn$;
revoke execute on function public.fn_it_access_accept(text, text, text, text) from public, anon, authenticated;

-- ── READINGS ONLY A MANAGEMENT TOKEN CAN TAKE ────────────────────────────────────────────────────
-- p_r: {backups:{basis, pitr_enabled, latest_backup_at}, disk:{basis, size_bytes}, members:{basis, principals}}
-- from scripts/it/report_platform_readings.mjs. Database backups older than 26 hours, or PITR off,
-- is a finding for the CEO; members join the access review; disk sets db_disk_limit_bytes.
create or replace function public.fn_it_platform_ingest(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; v_out jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then raise exception 'fn_it_platform_ingest takes the platform readings object'; end if;
  if p_r->'backups'->>'basis' = 'measured' then
    if not coalesce((p_r->'backups'->>'pitr_enabled')::boolean, false) then
      v_items := v_items || jsonb_build_object('item', 'pitr', 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'Point-in-time recovery is not enabled on the database', 'blast', 'agent_facing', 'affected', 1, 'evidence', p_r->'backups');
    end if;
    if (p_r->'backups'->>'latest_backup_at') is null or (p_r->'backups'->>'latest_backup_at')::timestamptz < now() - interval '26 hours' then
      v_items := v_items || jsonb_build_object('item', 'daily_backup', 'owner_seat', 'ceo', 'subject', 'database',
        'title', 'The newest database backup is ' || coalesce('from ' || (p_r->'backups'->>'latest_backup_at'), 'missing'),
        'blast', 'customer_facing', 'affected', 1, 'evidence', p_r->'backups');
    end if;
    v_out := v_out || jsonb_build_object('db_backup', public.fn_it_duty_settle('db_backup', v_items));
  end if;
  if p_r->'disk'->>'basis' = 'measured' and (p_r->'disk'->>'size_bytes') is not null then
    update public.it_threshold set value = (p_r->'disk'->>'size_bytes')::numeric,
           basis = 'management API disk size, read ' || now()::date where key = 'db_disk_limit_bytes';
  end if;
  if p_r->'members'->>'basis' = 'measured' then
    v_out := v_out || jsonb_build_object('supabase_access',
      public.fn_it_duty_settle('supabase_access', public.fn_it_access_items(jsonb_build_object('supabase', p_r->'members'))));
  end if;
  perform public.fn_it_duty_ran('platform', v_out);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_platform_ingest(jsonb) from public, anon, authenticated;

-- ── 12. DEPENDENCY ADVISORIES ────────────────────────────────────────────────────────────────────
-- p_r: {advisories:[{ecosystem, package, severity, id, title, via}]} from
-- scripts/it/report_dependency_audit.mjs (npm audit for the app, OSV for the edge functions' npm and
-- jsr imports). High and critical are blast 'security' and so reach the founder as a new bug if the
-- owner cannot clear them; moderate and low are recorded for the owner and never email him.
create or replace function public.fn_it_dependency_ingest(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare e jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
begin
  if jsonb_typeof(p_r->'advisories') is distinct from 'array' then
    raise exception 'fn_it_dependency_ingest takes {advisories:[...]} from scripts/it/report_dependency_audit.mjs';
  end if;
  for e in select a from jsonb_array_elements(p_r->'advisories') a loop
    v_items := v_items || jsonb_build_object('item', (e->>'ecosystem') || ':' || (e->>'package') || ':' || coalesce(e->>'id', '?'),
      'owner_seat', case when e->>'ecosystem' = 'app' then 'ceo' else coalesce(e->>'owner_seat', 'ceo') end,
      'subject', coalesce(e->>'function', e->>'package'),
      'title', upper(coalesce(e->>'severity', '?')) || ' advisory in ' || (e->>'package') || ': ' || left(coalesce(e->>'title', ''), 120),
      'blast', case when lower(e->>'severity') in ('high', 'critical') then 'security' else 'internal' end,
      'affected', case when lower(e->>'severity') in ('high', 'critical') then 1 else 0 end,
      'evidence', e || jsonb_build_object('no_founder_email', lower(e->>'severity') not in ('high', 'critical')));
  end loop;
  v_res := public.fn_it_duty_settle('dependency', v_items);
  perform public.fn_it_duty_ran('dependency', v_res);
  return v_res;
end $fn$;
revoke execute on function public.fn_it_dependency_ingest(jsonb) from public, anon, authenticated;

-- ── HEARTBEATS FOR THE READINGS THAT ARRIVE FROM GITHUB ──────────────────────────────────────────
-- Checked by the hourly duties tick: a weekly audit or a platform reading that stops arriving is a
-- finding for the CEO — once the scheduled duties have themselves run longer than the interval, so a
-- workflow merged today is not reported missing before its first schedule comes round.
create or replace function public.fn_it_workflow_heartbeats()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; x record;
begin
  for x in select * from (values ('dependency', interval '8 days', '.github/workflows/it-weekly-readings.yml'),
                                 ('platform',   interval '8 days', '.github/workflows/it-weekly-readings.yml')) v(job, every, wf) loop
    if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%'
                and started_at < now() - x.every)
       and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:' || x.job
                    and started_at > now() - x.every) then
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'The ' || x.job || ' readings from GitHub have not arrived for ' || x.every,
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report'));
    end if;
  end loop;
  return public.fn_it_duty_settle('workflow_heartbeat', v_items);
end $fn$;
revoke execute on function public.fn_it_workflow_heartbeats() from public, anon, authenticated;

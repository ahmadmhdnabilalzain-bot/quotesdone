-- DROPBOX IS CHECKED EVERY DAY: THE LOGIN, A WRITE/READ/DELETE PROBE, AND HOW FULL IT IS.
--
-- Assigned: it_engineer. 15 Sep 2026. No model call: every decision here is a rule.
--
-- The founder, 14 Sep 2026 (founder_instruction 208): backups go to Supabase AND Dropbox, and may fail
-- only during a provider outage, never for an internal cause. A full Dropbox or a revoked login would
-- break that silently.
--
-- MEASURED BEFORE WRITING (15 Sep 2026, production and origin/main 73db36d):
--   * dropbox_backup op 'health' called public.fn_it_dropbox_health_record, which existed in neither
--     production nor any scripts/sql file on main, and nothing called op 'health'. So no daily probe
--     ran, no failure was classified, and the account's fill level was unmeasured.
--   * The routine was written in d49b9253 (origin/backup/no-internal-cause-left, never applied). This
--     file keeps only the health half of it, and routes it the way duties 19-24 (#661, #675) do:
--     fn_it_duty_settle -> public.it_engineer_finding -> the IT loop (the owning seat answers, the CEO
--     decides, customer_support sends one deduplicated email). d49b9253's direct CEO report, its
--     new-bug email routine and the accountant's renewal item are NOT carried: the loop already owns
--     escalation, and the renewal date belongs to renewals_warn_the_accountant_at_sixty_and_thirty_days.sql.
--
-- THE READING comes from supabase/functions/dropbox_backup (health()): auth_ok, write_ok, read_ok,
-- delete_ok, error + class (health.ts: auth, quota, rate_limit, provider_outage, network, internal),
-- used, allocated, plan, space_error + space_class. resilience_ping asks for it once a Dubai day
-- (fn_it_dropbox_health_due), and again two hours after a failed reading.
--
-- HOW LOUD, through fn_it_engineer_severity (high or critical is actionable and enters the loop):
--   duty dropbox_login   the probe failed. auth, quota, internal: agent_facing, high at once.
--                        rate_limit, provider_outage, network: internal, so warn until the fault is six
--                        hours old and high after that - the founder's one allowed cause, until it lasts.
--   duty dropbox_space   pct >= it_threshold dropbox_space_loud_pct (85): agent_facing, high (loud).
--                        pct >= dropbox_space_quiet_pct (70): internal, affected 0, warn (quiet: it shows
--                        in the daily line and never emails). A probe that worked with the space unread
--                        is space_unread, quiet. Each reading closes what it no longer finds.
--
--   node scripts/apply_sql.mjs scripts/sql/dropbox_is_checked_every_day_login_and_space.sql --apply --ddl
--   node --test scripts/checks/dropbox_health_thresholds.test.mjs     (rolled back; works before the apply)

do $check$ begin
  assert to_regprocedure('public.fn_it_duty_settle(text, jsonb)') is not null, 'fn_it_duty_settle is missing (the_it_engineer_runs_its_duties_every_hour.sql)';
  assert to_regprocedure('public.fn_it_threshold(text)') is not null, 'fn_it_threshold is missing';
end $check$;

-- ── 1. THE TWO THRESHOLDS, as it_threshold rows like every other IT limit ────────────────────────
insert into public.it_threshold (key, value, unit, basis) values
  ('dropbox_space_quiet_pct', 70, 'percent', 'founder brief 15 Sep 2026: a quiet finding at 70% of the Dropbox allocation'),
  ('dropbox_space_loud_pct',  85, 'percent', 'founder brief 15 Sep 2026: a loud finding at 85% of the Dropbox allocation; at 100% new documents stop reaching Dropbox')
on conflict (key) do nothing;

-- ── 2. DUE: once a Dubai day after a reading that worked; two hours after one that failed ────────
create or replace function public.fn_it_dropbox_health_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status in ('ok', 'warn') and r.started_at > now() - interval '1 day'
                        and (r.started_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date)
     and not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status = 'error' and r.started_at > now() - interval '2 hours');
$fn$;
revoke execute on function public.fn_it_dropbox_health_due() from public, anon, authenticated;

-- ── 3. RECORD: settle both duties, write the reading to agent_runs ────────────────────────────────
create or replace function public.fn_it_dropbox_health_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_quiet numeric := coalesce(public.fn_it_threshold('dropbox_space_quiet_pct'), 70);
  v_loud  numeric := coalesce(public.fn_it_threshold('dropbox_space_loud_pct'), 85);
  v_ok boolean; v_cls text; v_pct numeric; v_status text;
  v_login jsonb := '[]'::jsonb; v_space jsonb := '[]'::jsonb; v_login_out jsonb; v_space_out jsonb;
  v_classes constant text[] := array['auth', 'quota', 'rate_limit', 'provider_outage', 'network', 'internal'];
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'fn_it_dropbox_health_record: the reading must be a json object'; end if;

  v_ok := p->>'error' is null and coalesce((p->>'write_ok')::boolean, false) and coalesce((p->>'read_ok')::boolean, false)
          and coalesce((p->>'delete_ok')::boolean, false);
  if not v_ok then
    -- a class the edge did not name, or named wrongly, is ours to explain: internal
    v_cls := case when p->>'class' = any (v_classes) then p->>'class' else 'internal' end;
    v_login := jsonb_build_array(jsonb_build_object('item', v_cls,
      'title', case v_cls
        when 'auth'            then 'Dropbox refused the company''s stored login; backups are not reaching Dropbox'
        when 'quota'           then 'Dropbox refused the daily probe write because the account is full'
        when 'rate_limit'      then 'Dropbox rate-limited the daily probe'
        when 'provider_outage' then 'Dropbox answered the daily probe with a server error'
        when 'network'         then 'Dropbox could not be reached for the daily probe'
        else                        'The daily Dropbox probe failed for an internal reason' end,
      'blast', case when v_cls in ('rate_limit', 'provider_outage', 'network') then 'internal' else 'agent_facing' end,
      'affected', 1, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
      'evidence', jsonb_build_object('class', v_cls, 'error', left(p->>'error', 300), 'auth_ok', p->'auth_ok',
                                     'write_ok', p->'write_ok', 'read_ok', p->'read_ok', 'delete_ok', p->'delete_ok',
                                     'look_at', 'dropbox_backup op health; agent_runs job dropbox_health')));
  end if;
  v_login_out := public.fn_it_duty_settle('dropbox_login', v_login);

  if coalesce(p->>'allocated', '') ~ '^[0-9]+(\.[0-9]+)?$' and coalesce(p->>'used', '') ~ '^[0-9]+(\.[0-9]+)?$'
     and (p->>'allocated')::numeric > 0 then
    v_pct := round((p->>'used')::numeric * 100 / (p->>'allocated')::numeric, 1);
    if v_pct >= v_loud then
      v_space := jsonb_build_array(jsonb_build_object('item', 'space_loud',
        'title', 'Dropbox is ' || v_pct || '% full (loud at ' || v_loud || '%); at 100% new documents stop reaching Dropbox',
        'blast', 'agent_facing', 'affected', 1, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
        'evidence', jsonb_build_object('pct_used', v_pct, 'used', p->'used', 'allocated', p->'allocated', 'plan', p->'plan', 'threshold', v_loud)));
    elsif v_pct >= v_quiet then
      v_space := jsonb_build_array(jsonb_build_object('item', 'space_quiet',
        'title', 'Dropbox is ' || v_pct || '% full (quiet at ' || v_quiet || '%, loud at ' || v_loud || '%)',
        'blast', 'internal', 'affected', 0, 'owner_seat', 'ceo', 'subject', 'dropbox_backup',
        'evidence', jsonb_build_object('pct_used', v_pct, 'used', p->'used', 'allocated', p->'allocated', 'plan', p->'plan', 'threshold', v_quiet)));
    end if;
    v_space_out := public.fn_it_duty_settle('dropbox_space', v_space);
  elsif v_ok then
    -- the login works and the space did not read: say so, and leave what the last reading found open
    perform public.fn_it_engineer_finding_upsert('duty:dropbox_space:space_unread',
      'The Dropbox login works but the space used could not be read', 'IT engineer duty: dropbox_space',
      'internal', 0, jsonb_build_object('duty', 'dropbox_space', 'owner_seat', 'ceo', 'subject', 'dropbox_backup', 'demo', false,
        'space_error', left(p->>'space_error', 300), 'space_class', p->>'space_class'),
      '{}'::text[], '{}'::text[], 'it_engineer.dropbox_space');
  else
    -- login probe AND space read both failed: any open dropbox_space finding is deliberately left untouched this tick; the login finding is already loud, and space is re-evaluated on the next good reading
    null;
  end if;

  v_status := case when not v_ok then 'error'
                   when v_pct is null or v_pct >= v_quiet then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, jsonb_build_object('job', 'dropbox_health', 'pct_used', v_pct, 'class', v_cls) || p,
          left('Dropbox health: write ' || coalesce(p->>'write_ok', 'false') || ', read ' || coalesce(p->>'read_ok', 'false')
               || ', delete ' || coalesce(p->>'delete_ok', 'false') || '; '
               || coalesce(v_pct::text || '% of the ' || coalesce(p->>'plan', 'unknown') || ' plan used', 'space not read')
               || coalesce('; ' || v_cls || ': ' || (p->>'error'), ''), 500), now(), now());
  return jsonb_build_object('status', v_status, 'pct_used', v_pct, 'class', v_cls, 'login', v_login_out, 'space', v_space_out);
end $fn$;
revoke execute on function public.fn_it_dropbox_health_record(jsonb) from public, anon, authenticated;

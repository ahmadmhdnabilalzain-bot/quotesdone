-- THE IT ENGINEER HANDS THE FOUNDER A SESSION HE CAN START FROM (9 Sep 2026).
--
-- agent: it_engineer
--
-- THE ORDER, verbatim: "once their is an issue, he will email me directly so i can open a session
-- with you to fix it ... he reports to me directly only".
--
-- Read closely, that is not a notification. The email exists so a FRESH Claude session can begin
-- work from the email alone. An alert that says "registration is failing" costs him a round trip
-- and is barely better than silence. So this is a HANDOVER, and it carries, on its face: what
-- broke, where, when it started, the evidence (ids, counts, error text), what the seat already
-- checked and ruled out, what it could not determine, and the handle to pull the rest.
--
-- THIS FILE IS THE ALERT ONLY. The seat and its runtime (supabase/functions/it_engineer/), the
-- instrumentation, the health detection and the security/malware watch are built beside it and are
-- deliberately NOT touched here. This file owns how a finding REACHES him, and what is worth
-- reaching him for. The detectors call fn_it_engineer_finding_upsert; everything after that is here.
--
-- =============================================================================================
-- WHAT WAS MEASURED FIRST (production htdblwldjkcgjvmqkbeh, 9 Sep 2026 06:41 UTC)
-- =============================================================================================
--   founder_mail_policy            64 kinds. The nine already covering this territory --
--                                  health_alert, incident, ops_alert, os_incident, smoke_alert,
--                                  red_view, security_incident, agent_silence,
--                                  scheduled_runs_failed -- are ALL allowed_to_email = false, and
--                                  all nine are owned by it_operations_engineer / cto /
--                                  cybersecurity_engineer, roles DELETED on 7 Sep 2026.
--                                  security_critical, platform_down and uptime_alert are true.
--   a10_notifications_founder_mail_policy   BEFORE INSERT on notifications, fires first (name
--                                  order), and `return null`s an unregistered kind. A silent drop,
--                                  not an error: an unregistered alert goes NOWHERE and says nothing.
--   org_role                       4 seats: accountant, ceo, customer_support, sales_engineer.
--                                  it_engineer is not registered yet -- that row belongs to the
--                                  seat file being built in parallel. founder_mail_policy.owner_role
--                                  carries no FK (checked: the only constraint is the pkey), so the
--                                  lane can be owned by name before the seat row lands.
--   decision_policy.alert_digest_types   ["health_alert","smoke_alert","exception_alert",
--                                  "ops_alert","supply_health",...]. A kind on that list is folded
--                                  into a digest instead of being sent. Another reason not to reuse
--                                  one of them for a handover that must arrive on its own.
--   resilience_ping                an EDGE FUNCTION, not a pg routine (there is no public.resilience_ping;
--                                  measured: 0 rows in pg_proc for 'resil%'). Vercel cron every 15 min
--                                  -> /api/resilience-ping; GitHub Actions once a day as the
--                                  out-of-cluster cross-check. pg_cron holds ONE inactive row.
--
-- =============================================================================================
-- 1. THE KIND. ONE NEW KIND, it_engineer_handover -- decided, not reflexed.
-- =============================================================================================
-- The tempting move is to flip health_alert or incident to true and be done. It is wrong, and the
-- reason is mechanical rather than aesthetic: those kinds ALREADY HAVE WRITERS. fn_smoke writes
-- smoke_alert, fn_os_incident_watchdog writes os_incident, fn_agent_silence_watch writes
-- agent_silence. Flipping one to true does not enable the IT engineer -- it re-arms every legacy
-- sender that writes that kind, and those senders are precisely the ones that produced the 6 Sep
-- audit finding ("so many errors were sent to me from the engine", ~210 of 244 emails were a
-- department's work). The false rows are a deliberate result, not neglect. Undoing them to make
-- room for this would trade one good email for nine bad ones.
--
-- A new kind gives the policy row exactly ONE writer, so "allowed to email the founder" is a
-- statement about this routine and nothing else, and it can be revoked later without silencing
-- anything else. Same reasoning the accountant used for accountant_weekly_report on 9 Sep.
--
-- ONE kind, not two (no separate critical/degraded lane): severity is carried ON THE FACE of the
-- alert and derived from measurement (section 4). A second kind sitting at allowed_to_email=false
-- would be a silent drop -- strictly worse than not writing the row, because nothing would say so.
-- Below the email bar, no notification row is written at all; the ledger and founder_alerts keep
-- the record, which is the estate's existing "recorded, not mailed" mechanism.
--
-- EMAIL ONLY -- deliberately NOT WhatsApp, even at critical. Three reasons. (a) He named email:
-- "he will email me directly". (b) A handover is ids, counts and error text; WhatsApp is the wrong
-- carrier for a document meant to seed a session. (c) send_whatsapp HOLDS anything older than
-- app_secrets.wa_stale_hours (24) rather than delivering it, so the exact case a second channel
-- would be for -- a long outage -- is the case where the WhatsApp copy silently becomes 'held'.
-- A total platform outage already reaches his WhatsApp through resilience_ping -> alert_founder
-- with kind platform_down, which is allowed and is better suited to it. This does not duplicate it.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('it_engineer_handover', true,
        'The founder ruled on 9 Sep 2026 that the IT engineer reports to him directly: "once their is an issue, he will email me directly so i can open a session with you to fix it". A NEW kind rather than reusing health_alert / incident / ops_alert / os_incident / smoke_alert / red_view / security_incident / agent_silence / scheduled_runs_failed -- those nine are allowed_to_email=false on purpose after the 6 Sep audit, and each already has legacy writers, so flipping one would re-arm every one of them instead of enabling this seat alone. Written only by fn_it_engineer_alert_tick, one email per issue (section 3 of scripts/sql/the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql).',
        'it_engineer')
on conflict (kind) do update
  set allowed_to_email = excluded.allowed_to_email,
      reason           = excluded.reason,
      owner_role       = excluded.owner_role,
      updated_at       = now();

-- =============================================================================================
-- 2. THE LEDGER. Dedupe is on the ISSUE, and the row is also what makes the handover possible.
-- =============================================================================================
-- A detector that fires every 15 minutes for a week is how a real alert gets ignored, so nothing
-- here dedupes on the tick. The unit is the ISSUE, identified by a stable issue_key the detector
-- chooses (e.g. 'registration:signup_500'). The row carries started_at, so "when it started" is a
-- measurement rather than "the time this email was written" -- which is the single fact an alert
-- most often omits and a fresh session most needs.
--
-- ruled_out / undetermined are columns, not prose, because they are the difference between a
-- handover and a notification. A seat that checked the edge logs and eliminated a deploy says so
-- here, and the session does not repeat that work.
create table if not exists public.it_engineer_finding (
  issue_key           text primary key,
  title               text        not null,
  where_it_is         text        not null,          -- routine / function / surface / table
  blast               text        not null,          -- see fn_it_engineer_severity
  affected            integer     not null default 0,-- MEASURED count of affected subjects
  evidence            jsonb       not null default '{}'::jsonb,
  ruled_out           text[]      not null default '{}',
  undetermined        text[]      not null default '{}',
  raised_by           text        not null default 'it_engineer',
  started_at          timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  seen_count          integer     not null default 1,
  closed_at           timestamptz,
  close_note          text,
  -- alert state: what he has ALREADY been told, so the rule can compare against it
  alerted_at          timestamptz,
  alerted_severity    text,
  alerted_affected    integer,
  alert_count         integer     not null default 0,
  close_notified_at   timestamptz,
  notification_id     bigint,
  constraint it_engineer_finding_blast_ck
    check (blast in ('customer_facing','security','agent_facing','internal','monitor')),
  constraint it_engineer_finding_affected_ck check (affected >= 0)
);
create index if not exists it_engineer_finding_open_idx
  on public.it_engineer_finding (closed_at, blast) where closed_at is null;
comment on table public.it_engineer_finding is
  'One row per ISSUE the IT engineer seat has found. Dedupe, escalation and the handover body all read from here. Written by fn_it_engineer_finding_upsert / _close; delivered by fn_it_engineer_alert_tick.';

-- SILENCE MUST BE TRUSTWORTHY. A monitor that fails open is worse than no monitor, because zero
-- findings then reads as a quiet night. Every detector the seat runs registers here and stamps a
-- beat; the tick turns a stale beat or a recorded error into a finding of its own (blast='monitor').
-- So "no email" requires the beats to be FRESH and clean, not merely for nothing to have been said.
create table if not exists public.it_engineer_scanner (
  scanner          text primary key,
  last_beat_at     timestamptz not null default now(),
  last_ok_at       timestamptz,
  last_error       text,
  max_gap_minutes  integer     not null default 60,
  registered_at    timestamptz not null default now(),
  constraint it_engineer_scanner_gap_ck check (max_gap_minutes between 5 and 1440)
);
comment on column public.it_engineer_scanner.max_gap_minutes is
  'How long this scanner may stay silent before its silence is itself a finding. Default 60 = four missed 15-minute ticks.';

alter table public.it_engineer_finding enable row level security;
alter table public.it_engineer_scanner enable row level security;
-- No policies on purpose: evidence carries ids and raw error text. service_role bypasses RLS; every
-- caller here is a SECURITY DEFINER routine. anon and authenticated get nothing.

-- =============================================================================================
-- 3. THE DEDUPE / ESCALATION RULE -- and why it goes QUIET rather than repeating.
-- =============================================================================================
-- DECISION: exactly ONE email per issue while the facts he was given still hold. A continuing
-- problem goes QUIET. It speaks again only when a fact HE WAS TOLD has changed.
--
-- Why quiet and not escalate-by-repetition: the email exists so he can open a session and fix it.
-- Once he holds the handover he has everything a second identical email would carry; repeating it
-- adds no new action and is exactly the failure mode this estate already has a scar from. A
-- reminder is not information.
--
-- The four things that DO re-open his attention, all of them changes in the facts:
--   (a) SEVERITY ROSE      -- warn->high->critical. At most twice per issue, by construction.
--   (b) BLAST RADIUS AT LEAST DOUBLED  -- affected >= 2 x what he was last told, and greater than
--       it. Self-limiting: 1 -> 2 -> 4 -> 8 is log2(n) emails over the life of an issue, and the
--       number in the subject is the one that changed.
--   (c) IT CLOSED          -- one RESOLVED note, and only for an issue he was actually emailed
--       about. Without it he opens a session for something already fixed: the same round trip the
--       handover exists to avoid. Silence cannot distinguish "fixed" from "still broken".
--   (d) IT CAME BACK       -- reopening a closed issue resets the alert state, because a recurrence
--       is news even when the text is identical.
-- Plus a 30-minute floor on every re-alert except (a), so a flapping counter cannot storm.
--
-- warn NEVER emails. It is recorded in the ledger and stays there. That is the whole point of
-- deriving severity from measurement instead of letting a caller type 'high'.

-- =============================================================================================
-- 4. SEVERITY COMES FROM TWO MEASURED NUMBERS AND A CLOCK, NEVER FROM A CONSTANT.
-- =============================================================================================
-- The caller supplies WHAT PATH failed (blast -- which code path it is, a fact about the system)
-- and HOW MANY subjects it affected (affected -- a count it measured). Severity is DERIVED from
-- those plus how long the condition has held. It is deliberately NOT stored: duration keeps moving,
-- so a stored severity would go stale and an issue would sit at 'warn' forever.
--
-- A customer unable to register and a cron beat missed once are therefore not the same thing, and
-- cannot be made the same thing by a caller passing p_severity => 'critical'.
create or replace function public.fn_it_engineer_severity(
  p_blast text, p_affected integer, p_started_at timestamptz
) returns text
language sql stable
set search_path to 'public', 'pg_temp'
as $function$
  select case
    -- data or credentials exposed: there is no count at which this waits
    when p_blast = 'security' then 'critical'
    -- a customer cannot complete something. Someone is actually stuck -> critical;
    -- the path is broken but nobody has hit it yet -> high (still same-day work)
    when p_blast = 'customer_facing' then case when coalesce(p_affected,0) > 0 then 'critical' else 'high' end
    -- a blind detector. High from the first tick, because its silence is now worthless;
    -- critical once we have been blind for 6h, because by then "nothing was reported" means nothing
    when p_blast = 'monitor' then case when now() - p_started_at >= interval '6 hours' then 'critical' else 'high' end
    -- an agent cannot do its job: no customer is stuck yet, but work is not happening
    when p_blast = 'agent_facing' then case when coalesce(p_affected,0) > 0 or now() - p_started_at >= interval '6 hours' then 'high' else 'warn' end
    -- internal only. Quiet by default; a thing still broken six hours later is not routine
    else case when coalesce(p_affected,0) > 0 and now() - p_started_at >= interval '6 hours' then 'high' else 'warn' end
  end;
$function$;

-- =============================================================================================
-- 5. THE DETECTORS' ENTRY POINTS. Deterministic, no model call.
-- =============================================================================================
create or replace function public.fn_it_engineer_finding_upsert(
  p_issue_key    text,
  p_title        text,
  p_where        text,
  p_blast        text,
  p_affected     integer default 0,
  p_evidence     jsonb   default '{}'::jsonb,
  p_ruled_out    text[]  default '{}'::text[],
  p_undetermined text[]  default '{}'::text[],
  p_raised_by    text    default 'it_engineer'
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v public.it_engineer_finding; v_reopened boolean := false;
begin
  if coalesce(btrim(p_issue_key),'') = '' then
    raise exception 'fn_it_engineer_finding_upsert: p_issue_key is the dedupe identity and cannot be blank';
  end if;

  select * into v from public.it_engineer_finding where issue_key = p_issue_key;
  v_reopened := (v.issue_key is not null and v.closed_at is not null);

  insert into public.it_engineer_finding as f
    (issue_key, title, where_it_is, blast, affected, evidence, ruled_out, undetermined, raised_by)
  values
    (p_issue_key, left(p_title, 300), left(p_where, 300), p_blast, greatest(coalesce(p_affected,0),0),
     coalesce(p_evidence,'{}'::jsonb), coalesce(p_ruled_out,'{}'), coalesce(p_undetermined,'{}'),
     coalesce(nullif(btrim(p_raised_by),''),'it_engineer'))
  on conflict (issue_key) do update set
    title         = excluded.title,
    where_it_is   = excluded.where_it_is,
    blast         = excluded.blast,
    affected      = excluded.affected,
    evidence      = excluded.evidence,
    ruled_out     = excluded.ruled_out,
    undetermined  = excluded.undetermined,
    raised_by     = excluded.raised_by,
    last_seen_at  = now(),
    seen_count    = f.seen_count + 1,
    -- A RECURRENCE IS NEWS. Reopening restarts the clock and the alert state, so a problem that
    -- came back is told once more rather than being suppressed by the alert he got last week.
    started_at        = case when f.closed_at is not null then now() else f.started_at end,
    closed_at         = null,
    close_note        = null,
    alerted_at        = case when f.closed_at is not null then null else f.alerted_at end,
    alerted_severity  = case when f.closed_at is not null then null else f.alerted_severity end,
    alerted_affected  = case when f.closed_at is not null then null else f.alerted_affected end,
    -- alert_count is deliberately NOT reset: it is how the tick knows a reopened issue is a
    -- RECURRENCE rather than a first sighting, and says so on the face of the email.
    close_notified_at = null
  returning * into v;

  return jsonb_build_object(
    'issue_key', v.issue_key, 'reopened', v_reopened, 'seen_count', v.seen_count,
    'started_at', v.started_at,
    'severity', public.fn_it_engineer_severity(v.blast, v.affected, v.started_at));
end $function$;

create or replace function public.fn_it_engineer_finding_close(
  p_issue_key text, p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v public.it_engineer_finding;
begin
  update public.it_engineer_finding
     set closed_at = coalesce(closed_at, now()), close_note = left(coalesce(p_note, close_note), 2000)
   where issue_key = p_issue_key
  returning * into v;
  if v.issue_key is null then return jsonb_build_object('closed', false, 'reason', 'no such issue_key'); end if;
  -- the RESOLVED note is not sent here: fn_it_engineer_alert_tick sends it, and only if he was
  -- actually emailed about this issue. Closing something he never heard about is not news.
  return jsonb_build_object('closed', true, 'issue_key', v.issue_key,
                            'was_alerted', v.alert_count > 0, 'open_for', (v.closed_at - v.started_at)::text);
end $function$;

-- A scanner stamps this every time it runs. p_error non-null means the detector itself failed --
-- which the tick treats as a finding, because a detector that threw did not find nothing, it
-- found nothing OUT.
create or replace function public.fn_it_engineer_scanner_beat(
  p_scanner text, p_error text default null, p_max_gap_minutes integer default 60
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v public.it_engineer_scanner;
begin
  insert into public.it_engineer_scanner as s (scanner, last_beat_at, last_ok_at, last_error, max_gap_minutes)
  values (p_scanner, now(), case when p_error is null then now() end, left(p_error, 1000),
          least(greatest(coalesce(p_max_gap_minutes,60), 5), 1440))
  on conflict (scanner) do update set
    last_beat_at    = now(),
    last_ok_at      = case when p_error is null then now() else s.last_ok_at end,
    last_error      = left(p_error, 1000),
    max_gap_minutes = least(greatest(coalesce(p_max_gap_minutes, s.max_gap_minutes), 5), 1440)
  returning * into v;
  return jsonb_build_object('scanner', v.scanner, 'ok', p_error is null, 'max_gap_minutes', v.max_gap_minutes);
end $function$;

-- =============================================================================================
-- 6. THE HANDOVER BODY. A separate routine so the tick stays readable and so the exact text can be
--    rendered and read WITHOUT sending anything.
-- =============================================================================================
create or replace function public.fn_it_engineer_handover_body(
  p_issue_key text, p_reason text default 'first'   -- first | severity_rose | blast_grew | resolved | recurred
) returns text
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare f public.it_engineer_finding; v_sev text; v_age interval; b text; e text; x text;
begin
  select * into f from public.it_engineer_finding where issue_key = p_issue_key;
  if f.issue_key is null then return null; end if;
  v_sev := public.fn_it_engineer_severity(f.blast, f.affected, f.started_at);
  v_age := coalesce(f.closed_at, now()) - f.started_at;

  select coalesce(string_agg('  ' || k || ': ' || left(val, 500), E'\n' order by k), '  (none recorded)')
    into e from jsonb_each_text(coalesce(f.evidence,'{}'::jsonb)) as t(k, val);

  b := case p_reason
         when 'resolved'      then 'RESOLVED. Nothing to do -- this is the close-out of an issue you were emailed about.'
         when 'severity_rose' then 'ESCALATION. You were told about this at ' || coalesce(f.alerted_severity,'?') || '; it is now ' || v_sev || '.'
         when 'blast_grew'    then 'THIS GOT BIGGER. You were told ' || coalesce(f.alerted_affected::text,'?') || ' affected; it is now ' || f.affected || '.'
         when 'recurred'      then 'THIS CAME BACK. The same issue was closed and has re-opened.'
         else                      'NEW. This is the first time you are hearing about this issue.'
       end;

  x := b || E'\n\n'
    || 'WHAT BROKE' || E'\n  ' || f.title || E'\n\n'
    || 'WHERE' || E'\n  ' || f.where_it_is || E'\n\n'
    || 'WHEN IT STARTED' || E'\n'
    || '  first seen  ' || to_char(f.started_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC ('
       || to_char(f.started_at at time zone 'Asia/Dubai','HH24:MI') || ' Dubai), '
       || trim(to_char(extract(epoch from v_age)/3600, '9990.9')) || ' hours ago' || E'\n'
    || '  last seen   ' || to_char(f.last_seen_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC'
       || ', observed on ' || f.seen_count || ' scan(s)' || E'\n'
    || case when f.closed_at is not null
            then '  closed      ' || to_char(f.closed_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC' || E'\n' else '' end
    || E'\n'
    || 'HOW BAD, AND WHY THAT SEVERITY' || E'\n'
    || '  ' || upper(v_sev) || ' -- derived, not typed: a ' || f.blast || ' path, ' || f.affected
       || ' subject(s) measured as affected, open ' || trim(to_char(extract(epoch from v_age)/3600, '9990.9')) || ' hours.' || E'\n'
    || '  (fn_it_engineer_severity is the rule; nothing hand-sets this.)' || E'\n\n'
    || 'EVIDENCE' || E'\n' || e || E'\n\n'
    || 'ALREADY CHECKED AND RULED OUT -- do not repeat this work' || E'\n'
    || coalesce(nullif((select string_agg('  - ' || r, E'\n') from unnest(f.ruled_out) r), ''),
                '  (nothing was ruled out -- treat every cause as open)') || E'\n\n'
    || 'COULD NOT DETERMINE -- start here' || E'\n'
    || coalesce(nullif((select string_agg('  - ' || u, E'\n') from unnest(f.undetermined) u), ''),
                '  (nothing recorded as undetermined)') || E'\n\n'
    || 'RAISED BY' || E'\n  ' || f.raised_by || '   issue key: ' || f.issue_key || E'\n\n'
    || 'TO PICK THIS UP' || E'\n'
    || '  Open a session on the quotesdone repository and paste this email. The full row, including' || E'\n'
    || '  anything added since this was sent:' || E'\n'
    || '    select * from public.it_engineer_finding where issue_key = ' || quote_literal(f.issue_key) || ';' || E'\n\n'
    || 'YOU WILL NOT GET THIS TWICE' || E'\n'
    || '  One email per issue. Another arrives only if the severity rises, the number affected at' || E'\n'
    || '  least doubles, the issue closes, or it comes back after being closed. Silence from here' || E'\n'
    || '  means the detectors are running and clean -- a detector that stops reporting raises its' || E'\n'
    || '  own finding rather than passing for a quiet night.';
  return x;
end $function$;

-- =============================================================================================
-- 7. THE TICK. Idempotent, exception-safe in sections, and it verifies its own delivery.
-- =============================================================================================
-- WHY IT VERIFIES: a10_notifications_founder_mail_policy returns NULL for a kind it does not allow.
-- The insert then succeeds with zero rows and no error. So every insert here uses RETURNING and
-- treats a NULL id as a DELIVERY FAILURE -- recorded in founder_alerts, never swallowed. An
-- untested alert path is an alert path that may be going nowhere.
create or replace function public.fn_it_engineer_alert_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_admin text; v_gap_min numeric; v_last_beat timestamptz;
  r record; v_sev text; v_reason text; v_body text; v_subject text; v_id bigint;
  v_sent int := 0; v_silent int := 0; v_resolved int := 0; v_refused int := 0;
  v_monitor int := 0; v_errors jsonb := '[]'::jsonb;
begin
  select lower(nullif(split_part(coalesce(value,''), ',', 1), '')) into v_admin
    from public.app_secrets where key = 'admin_emails';
  if v_admin is null then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('high','it_engineer:no_admin_address',
            'fn_it_engineer_alert_tick cannot address the founder: app_secrets.admin_emails is empty.','os');
    return jsonb_build_object('ok', false, 'reason', 'no admin address');
  end if;

  ---------------------------------------------------------------------------------------------
  -- A. THE MONITOR WATCHES ITSELF FIRST. A blind detection engine is an alert, not a quiet night.
  --    The gap is read BEFORE this tick's own beat is stamped, or it would always read zero.
  --    (What this cannot catch is the tick never running again at all. That is not left uncovered:
  --    it is the platform_down / uptime_alert path -- resilience_ping via Vercel cron every 15 min
  --    and the once-a-day GitHub Action outside both Supabase and Vercel -- which already emails
  --    him under kinds that are already allowed. This does not duplicate that.)
  ---------------------------------------------------------------------------------------------
  begin
    select last_beat_at into v_last_beat from public.it_engineer_scanner where scanner = 'it_engineer_alert_tick';
    if v_last_beat is not null then
      v_gap_min := extract(epoch from (now() - v_last_beat)) / 60.0;
      if v_gap_min > 60 then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:alert_tick_blind',
          'The IT engineer''s alert tick did not run for ' || round(v_gap_min) || ' minutes',
          'public.fn_it_engineer_alert_tick, called from supabase/functions/resilience_ping',
          'monitor', 1,
          jsonb_build_object('gap_minutes', round(v_gap_min), 'last_beat_at', v_last_beat,
                             'expected_every', '15 minutes (Vercel cron -> /api/resilience-ping)'),
          array['the tick is running now, so the routine itself still executes'],
          array['whether any finding was raised and missed during the gap',
                'whether the 15-minute Vercel cron or the whole edge function was the part that stopped'],
          'fn_it_engineer_alert_tick');
      else
        perform public.fn_it_engineer_finding_close('monitor:alert_tick_blind', 'the tick is running on cadence again');
      end if;
    end if;
    perform public.fn_it_engineer_scanner_beat('it_engineer_alert_tick', null, 60);
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','self_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- B. EVERY REGISTERED SCANNER. Stale beat OR a recorded error becomes a finding of its own.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_scanner where scanner <> 'it_engineer_alert_tick' loop
      if r.last_error is not null then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' is failing, so its silence proves nothing',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('last_error', r.last_error, 'last_beat_at', r.last_beat_at, 'last_ok_at', r.last_ok_at),
          array['the scanner is still being invoked -- it beat at ' || to_char(r.last_beat_at at time zone 'UTC','YYYY-MM-DD HH24:MI') || ' UTC'],
          array['what this detector would have found while it was erroring'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      elsif now() - r.last_beat_at > make_interval(mins => r.max_gap_minutes) then
        perform public.fn_it_engineer_finding_upsert(
          'monitor:' || r.scanner,
          'Detector ' || r.scanner || ' has not reported for ' || round(extract(epoch from (now() - r.last_beat_at))/60.0) || ' minutes',
          'IT engineer scanner ' || r.scanner, 'monitor', 1,
          jsonb_build_object('gap_minutes', round(extract(epoch from (now() - r.last_beat_at))/60.0),
                             'max_gap_minutes', r.max_gap_minutes, 'last_beat_at', r.last_beat_at),
          array['nothing -- this detector has reported nothing to rule anything out with'],
          array['everything this detector covers is currently unwatched'],
          'fn_it_engineer_alert_tick');
        v_monitor := v_monitor + 1;
      else
        perform public.fn_it_engineer_finding_close('monitor:' || r.scanner, 'the detector is reporting on cadence and without error');
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','scanner_watch','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- C. OPEN FINDINGS -> the dedupe/escalation rule of section 3.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_finding where closed_at is null order by started_at loop
      v_sev := public.fn_it_engineer_severity(r.blast, r.affected, r.started_at);
      v_reason := null;
      if v_sev = 'warn' then
        null;                                                        -- never emails. Recorded only.
      elsif r.alerted_at is null then
        v_reason := case when r.alert_count > 0 then 'recurred' else 'first' end;
      elsif array_position(array['warn','high','critical'], v_sev)
          > array_position(array['warn','high','critical'], coalesce(r.alerted_severity,'warn')) then
        v_reason := 'severity_rose';                                  -- no floor: this is new information
      elsif r.affected > coalesce(r.alerted_affected, 0)
        and r.affected >= 2 * greatest(coalesce(r.alerted_affected,0), 1)
        and now() - r.alerted_at >= interval '30 minutes' then
        v_reason := 'blast_grew';
      end if;

      if v_reason is null then v_silent := v_silent + 1; continue; end if;

      v_body    := public.fn_it_engineer_handover_body(r.issue_key, v_reason);
      v_subject := '[' || upper(v_sev) || '] QuotesDone IT: ' || r.title
                   || case when v_reason = 'severity_rose' then ' (escalated)'
                           when v_reason = 'blast_grew'    then ' (now ' || r.affected || ' affected)'
                           when v_reason = 'recurred'      then ' (recurred)' else '' end;

      v_id := null;
      insert into public.notifications (type, kind, to_email, to_role, channel, subject, body)
      values ('it_engineer_handover', 'it_engineer_handover', v_admin, 'admin', 'email',
              left(v_subject, 200), v_body)
      returning id into v_id;

      if v_id is null then
        -- the a10 gate refused the row. It does NOT raise, so without this the alert would vanish.
        v_refused := v_refused + 1;
        insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
        values ('critical', 'it_engineer:handover_refused_by_gate',
                'a10_notifications_founder_mail_policy dropped an it_engineer_handover for issue '
                || r.issue_key || ' (severity ' || v_sev || '). Check founder_mail_policy.it_engineer_handover.',
                'os', 'it_handover_refused');
      else
        update public.it_engineer_finding
           set alerted_at = now(), alerted_severity = v_sev, alerted_affected = r.affected,
               alert_count = alert_count + 1, notification_id = v_id
         where issue_key = r.issue_key;
        v_sent := v_sent + 1;
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','open_findings','error', sqlerrm);
  end;

  ---------------------------------------------------------------------------------------------
  -- D. CLOSED FINDINGS HE WAS TOLD ABOUT -> one RESOLVED note, so silence is not ambiguous.
  ---------------------------------------------------------------------------------------------
  begin
    for r in select * from public.it_engineer_finding
              where closed_at is not null and alert_count > 0 and close_notified_at is null loop
      v_body := public.fn_it_engineer_handover_body(r.issue_key, 'resolved');
      v_id := null;
      insert into public.notifications (type, kind, to_email, to_role, channel, subject, body)
      values ('it_engineer_handover', 'it_engineer_handover', v_admin, 'admin', 'email',
              left('[RESOLVED] QuotesDone IT: ' || r.title, 200), v_body)
      returning id into v_id;
      if v_id is null then
        v_refused := v_refused + 1;
      else
        update public.it_engineer_finding set close_notified_at = now() where issue_key = r.issue_key;
        v_resolved := v_resolved + 1;
      end if;
    end loop;
  exception when others then
    v_errors := v_errors || jsonb_build_object('section','resolved','error', sqlerrm);
  end;

  -- A tick that half-failed must SAY so rather than returning a clean-looking zero.
  if jsonb_array_length(v_errors) > 0 then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values ('high', 'it_engineer:alert_tick_partial', v_errors::text, 'os', 'it_tick_partial');
  end if;

  return jsonb_build_object('ok', jsonb_array_length(v_errors) = 0,
                            'sent', v_sent, 'resolved', v_resolved, 'silent', v_silent,
                            'monitor_findings', v_monitor, 'refused_by_gate', v_refused,
                            'errors', v_errors);
end $function$;

-- =============================================================================================
-- 8. GRANTS. Every routine above is newly CREATED and SECURITY DEFINER, so PUBLIC's implicit
--    EXECUTE is revoked in the same file (session skill §5).
-- =============================================================================================
revoke execute on function public.fn_it_engineer_severity(text, integer, timestamptz) from public;
revoke execute on function public.fn_it_engineer_finding_upsert(text, text, text, text, integer, jsonb, text[], text[], text) from public;
revoke execute on function public.fn_it_engineer_finding_close(text, text) from public;
revoke execute on function public.fn_it_engineer_scanner_beat(text, text, integer) from public;
revoke execute on function public.fn_it_engineer_handover_body(text, text) from public;
revoke execute on function public.fn_it_engineer_alert_tick() from public;

grant execute on function public.fn_it_engineer_severity(text, integer, timestamptz) to service_role;
grant execute on function public.fn_it_engineer_finding_upsert(text, text, text, text, integer, jsonb, text[], text[], text) to service_role;
grant execute on function public.fn_it_engineer_finding_close(text, text) to service_role;
grant execute on function public.fn_it_engineer_scanner_beat(text, text, integer) to service_role;
grant execute on function public.fn_it_engineer_handover_body(text, text) to service_role;
grant execute on function public.fn_it_engineer_alert_tick() to service_role;

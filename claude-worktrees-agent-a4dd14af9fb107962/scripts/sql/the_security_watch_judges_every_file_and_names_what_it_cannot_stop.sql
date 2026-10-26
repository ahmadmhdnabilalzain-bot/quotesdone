-- THE SECURITY WATCH — 9 September 2026.  Agent: ceo.
--
-- The founder, 9 Sep 2026: "he should be able to monitor cyber attacks or hackers or malware files
-- from customers or suppliers."
--
-- WHAT WAS TRUE BEFORE THIS FILE, measured, not assumed:
--   public.security_events      0 rows.  Ever.
--   public.error_events         0 rows.  Ever.
--   security_audit_log 74, os_audit_log 323, os_incidents 62, internal_credential_audit 11 — and
--   NOTHING READ ANY OF THEM.  A table that only accumulates is a diary, not a watch.
--   app_secrets.virustotal_api_key existed and no line of code in the repository called VirusTotal.
--
-- The lens that applies here is the estate's own: "Zero cannot tell a dead guard from an idle
-- system."  An empty security_events on a pre-launch marketplace is indistinguishable from a
-- detector that is switched off, and it WAS switched off — there was no detector.  So this file
-- does two things and refuses to do a third:
--
--   1. It gives every inbound file a RECORDED VERDICT (public.file_scan) instead of a silence.
--   2. It turns tables that already accumulate real rows into DETECTIONS (fn_security_detect),
--      deterministically, with no model anywhere on the path.
--   3. It does NOT add another empty table and call that monitoring.  Every detection below is
--      derived from a table that either has rows today (internal_credential_audit: 11 refusals,
--      all allowed=false) or receives them the moment a customer or supplier acts.
--
-- ── WHY A SCAN CANNOT SIMPLY BLOCK, AND WHAT IS DONE INSTEAD ────────────────────────────────────
-- The ordering question is real and is answered in supabase/functions/_shared/malware.ts, where the
-- code lives.  In short: the HASH LOOKUP blocks (one fast GET; a file VirusTotal already knows to be
-- malicious never reaches storage), and an UNKNOWN file is accepted but recorded as UNKNOWN and
-- never as clean.  file_scan.verdict is the authority; 'clean' is the only value that means safe.
-- A scan that fails — rate limit, outage, missing key — writes 'unavailable', which reads exactly
-- like 'unknown' to every consumer.  There is deliberately no code path that turns a failed scan
-- into a pass.
--
-- ── WHAT THIS SEAT STILL CANNOT DO ─────────────────────────────────────────────────────────────
-- Named in public.security_gap rather than left implied, because a blocker is a claim too and an
-- un-named gap becomes an assumed capability.  Read that table; it is short and it is honest.

-- ── 1. THE FILE VERDICT ────────────────────────────────────────────────────────────────────────
--
-- One row per ARRIVAL, not per hash: the same PDF sent twice by two suppliers is two events, and
-- the audit question is "what reached us and when", not "how many distinct files exist".  The hash
-- is indexed so the verdict for a hash is one lookup.
create table if not exists public.file_scan (
  id                bigint generated always as identity primary key,
  sha256            text        not null,
  verdict           text        not null
                    check (verdict in ('clean','malicious','suspicious','unknown','unavailable')),
  source            text        not null,          -- the edge function the bytes entered through
  subject           text,                          -- supplier id / customer id / sender, when known
  filename          text,
  mime              text,
  size_bytes        bigint,
  bucket            text,
  path              text,
  engines_malicious int         not null default 0,
  engines_suspicious int        not null default 0,
  engines_total     int         not null default 0,
  vt_status         int,                           -- the HTTP status VirusTotal actually returned
  blocked           boolean     not null default false,  -- true when the upload was REFUSED
  detail            jsonb       not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  rechecked_at      timestamptz
);
create index if not exists file_scan_sha256_idx     on public.file_scan (sha256);
create index if not exists file_scan_verdict_idx    on public.file_scan (verdict, created_at desc);
create index if not exists file_scan_created_at_idx on public.file_scan (created_at desc);
alter table public.file_scan enable row level security;   -- service role only, as every sibling table

comment on table public.file_scan is
  'Every file a customer or supplier put into the estate, with the malware verdict it was given. '
  'verdict=clean is the ONLY value that means safe; unknown and unavailable both mean UNJUDGED and '
  'must never be rendered, forwarded or parsed as if they were clean.';

-- The one place that decides whether a file may be used. Written as a function so no consumer has
-- to remember the rule ("clean, and only clean").
create or replace function public.fn_file_is_cleared(p_sha256 text)
returns boolean language sql stable set search_path = public, pg_catalog as $$
  select coalesce(
    (select bool_or(verdict = 'clean') from public.file_scan where sha256 = p_sha256),
    false);
$$;
comment on function public.fn_file_is_cleared(text) is
  'True only when this hash has at least one clean verdict. Absence of a scan is NOT clearance.';

-- Quarantine: everything that entered and has not been cleared.
create or replace view public.v_file_quarantine as
  select f.*
    from public.file_scan f
   where f.verdict <> 'clean'
   order by f.created_at desc;

-- ── 2. THE ADVISOR BASELINE ────────────────────────────────────────────────────────────────────
--
-- Supabase's security advisors return 546 findings today across 4 rule types (494 INFO
-- rls_enabled_no_policy, 47 WARN function_search_path_mutable, 3 WARN extension_in_public, 2 WARN
-- authenticated_security_definer_function_executable).  The session brief said "4 findings"; that
-- counted RULE TYPES, and the difference matters: baselining at rule-type granularity would hide a
-- brand-new table with no policy behind an already-known rule name, which is the "instrument
-- measuring the wrong subject" failure this estate has paid for before.  The baseline is therefore
-- per cache_key, and a 547th key is a NEW finding whatever its rule name.
--
-- Measured, not implied: three of those 47 function_search_path_mutable warnings were the three
-- routines in THIS file on its first apply.  A security watch that adds security findings while
-- installing itself is not a watch, so all three now pin search_path explicitly.
create table if not exists public.security_advisor_baseline (
  cache_key     text primary key,
  name          text        not null,
  level         text        not null,
  title         text,
  metadata      jsonb       not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  in_baseline   boolean     not null default true,   -- false = appeared after the baseline was set
  cleared_at    timestamptz                          -- set when a finding stops being returned
);
create index if not exists security_advisor_baseline_new_idx
  on public.security_advisor_baseline (in_baseline, cleared_at);
alter table public.security_advisor_baseline enable row level security;

comment on table public.security_advisor_baseline is
  'One row per Supabase security-advisor finding, keyed by its cache_key. in_baseline=false marks a '
  'finding that appeared AFTER the baseline was taken — that is the signal. Refreshed by '
  'scripts/checks/security_advisors_match_the_baseline.mjs.';

-- ── 3. THE NAMED GAPS ──────────────────────────────────────────────────────────────────────────
--
-- What this watch CANNOT do about an attack in progress.  Recorded as data so the alerting agent
-- can report it, and so nobody later infers a capability from silence.
create table if not exists public.security_gap (
  name              text primary key,
  description       text        not null,
  what_would_close_it text      not null,
  status            text        not null default 'open'
                    check (status in ('open','closed','partial')),
  measured_at       timestamptz not null default now(),
  detail            jsonb       not null default '{}'::jsonb
);
alter table public.security_gap enable row level security;

comment on table public.security_gap is
  'Named, un-actioned limits of the security watch. A blocker is a claim too: each row states what '
  'was MEASURED and exactly what would close it.';

insert into public.security_gap (name, description, what_would_close_it, status, detail) values
 ('edge_waf_blocks_nothing_yet',
  'The Vercel firewall for prj_6mNIUbqsbg92IMXgMFmbkMlXBGzS answered "Config not found" — there was '
  'no config, so there was nowhere to put a rule and blocking an attacker at the edge was not '
  'possible at all. TESTED rather than assumed on 9 Sep 2026: app_secrets.vercel_token CAN write it. '
  'PUT /v1/security/firewall/config returned 200 and created waf_l2KzGOM8qEy5 (firewallEnabled=true), '
  'and all ELEVEN managed rulesets (sqli, xss, rce, lfi, rfi, php, java, sd, sf, ma, gen) were then '
  'switched ACTIVE with action=log — verified live, config version 13, and www.quotesdone.com still '
  'answers 200. So attacks against the website are now VISIBLE at the edge, and an IP block is one '
  'API call away. What is still true: action=log refuses nothing, and no custom rule or IP block '
  'exists.',
  'Switching a managed ruleset from log to deny, and/or a custom rule. That is a TRAFFIC decision '
  'and it is deliberately not guessed here: enabling deny before launch, against no observed '
  'attacker and no observed false-positive rate, would risk refusing a real supplier to defend '
  'against nothing measured. The log-mode events are the data that decision needs. The credential is '
  'not the blocker — it was proven to work.',
  'partial', jsonb_build_object('config_id','waf_l2KzGOM8qEy5','created_at','2026-09-09T06:44:44Z',
                                'rulesets_active_in_log_mode', 11, 'config_version', 13)),

 ('no_rls_denial_telemetry',
  'A row-level-security refusal is a Postgres event. It is not written to any table in this database, '
  'so a caller probing for rows it may not read leaves no trace fn_security_detect can read. The 74 '
  'rows in security_audit_log are trigger-written row changes, not denials.',
  'Either pgaudit with log_statement on the denied paths shipped to a table, or an application-level '
  'refusal counter written by the portals when a scoped query returns empty for a caller that asked '
  'for a specific id. Neither exists today.',
  'open', '{}'::jsonb),

 ('advisors_unreadable_from_the_runtime',
  'The Supabase security advisors are readable ONLY with a management API token '
  '(GET /v1/projects/{ref}/advisors/security, proven 200 on 9 Sep 2026 with the CLI token). No edge '
  'function has a management token in its environment, so the seat cannot refresh the advisor '
  'baseline from inside the runtime; it is refreshed by a repository script.',
  'A management token set as an edge-function secret (SUPABASE_MANAGEMENT_TOKEN), OR keeping the '
  'refresh where it is — in scripts/checks/security_advisors_match_the_baseline.mjs, run by CI. The '
  'token is broad (whole-account management), which is why it was NOT copied into app_secrets: '
  'putting it there would widen the blast radius of a service-role leak to the entire Supabase '
  'account, to close a gap a scheduled script already closes.',
  'partial', '{}'::jsonb),

 ('virustotal_free_tier_rate_limit',
  'The VirusTotal public API allows roughly 4 requests/minute and 500/day. A burst of uploads will '
  'therefore return 429, and a 429 is recorded as verdict=unavailable — never as clean.',
  'A VirusTotal Premium key, or a second engine. Until then the honest behaviour is the one built: '
  'unavailable files are quarantined, not passed.',
  'open', '{}'::jsonb),

 ('dns_rebinding_residual',
  'safe_url.ts refuses private-address targets by parsed hostname and re-checks the URL after '
  'redirects, but Deno does not expose the resolved IP, so a public hostname whose DNS record points '
  'at a private address is not caught. Stated in that file since 9 Sep 2026 and repeated here so the '
  'watch does not imply coverage it lacks.',
  'A fetch API that exposes the resolved address, or an egress proxy that enforces the rule at the '
  'network layer.',
  'open', '{}'::jsonb),

 ('no_scan_of_the_files_already_stored',
  'file_scan judges files from the moment this watch was deployed. 6,241 objects were already in '
  'storage on 9 Sep 2026 (5,359 of them backups). None carries a verdict.',
  'A backfill pass that hashes every existing object and looks each hash up. It is bounded by the '
  'VirusTotal rate limit above (500/day), so it is a multi-day job, not a one-shot.',
  'open', '{}'::jsonb)
on conflict (name) do update
  set description = excluded.description,
      what_would_close_it = excluded.what_would_close_it,
      status = excluded.status,
      detail = excluded.detail,
      measured_at = now();

-- ── 4. security_events GETS A FINGERPRINT ──────────────────────────────────────────────────────
--
-- Without one, a detector that runs on a schedule re-reports the same fact every run and the table
-- becomes noise nobody reads — which is how the existing 74/323/62 rows came to be ignored.  The
-- fingerprint is derived from the SOURCE ROW, so a re-run is a no-op and a genuinely new occurrence
-- is a new row.
alter table public.security_events add column if not exists fingerprint text;
-- NOT a partial index, and the reason is worth the line. It was written
-- `... (fingerprint) where fingerprint is not null` first, which is the smaller index and reads as
-- the more careful one — and every ON CONFLICT (fingerprint) below then failed at RUNTIME with
-- 42P10, "no unique or exclusion constraint matching the ON CONFLICT specification", because
-- Postgres will only use a partial index as a conflict target if the statement repeats its
-- predicate. Caught by executing the detector rather than by reading it. A plain unique index needs
-- no predicate and costs nothing here: NULLs are distinct in Postgres, so the rows written before
-- this column existed do not collide with each other.
drop index if exists public.security_events_fingerprint_uq;
create unique index if not exists security_events_fingerprint_uq
  on public.security_events (fingerprint);

-- ── 5. THE DETECTOR ────────────────────────────────────────────────────────────────────────────
--
-- Entirely deterministic. No model, no inference, no OpenRouter — it must keep working while the
-- reasoning layer is on hold.  Every branch reads a table that exists and returns rows today or the
-- moment a real customer or supplier acts.
create or replace function public.fn_security_detect(p_window interval default interval '24 hours')
returns jsonb
set search_path = public, pg_catalog
language plpgsql
as $$
declare
  v_since timestamptz := now() - p_window;
  v jsonb := '{}'::jsonb;
  n int;
begin
  -- D1 MALWARE. A recorded malicious verdict is the highest-confidence detection this estate has.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'malware_file', 'high', f.source, coalesce(f.subject, f.filename),
           jsonb_build_object('file_scan_id', f.id, 'sha256', f.sha256, 'filename', f.filename,
                              'mime', f.mime, 'bucket', f.bucket, 'path', f.path,
                              'engines_malicious', f.engines_malicious,
                              'engines_total', f.engines_total, 'blocked', f.blocked),
           'file_scan:' || f.id
      from public.file_scan f
     where f.verdict in ('malicious','suspicious')
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('malware_file', n);

  -- D2 UNJUDGED. A file that entered and still has no clean verdict after 24h is sitting in the
  -- estate unscanned. Low severity, but it must be VISIBLE — an unknown must never render as safe.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'file_unscanned', 'low', f.source, coalesce(f.subject, f.filename),
           jsonb_build_object('file_scan_id', f.id, 'sha256', f.sha256, 'verdict', f.verdict,
                              'filename', f.filename, 'bucket', f.bucket, 'path', f.path),
           'file_unscanned:' || f.id
      from public.file_scan f
     where f.verdict in ('unknown','unavailable')
       and f.created_at < now() - interval '24 hours'
       and not public.fn_file_is_cleared(f.sha256)
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('file_unscanned', n);

  -- D3 CREDENTIAL MISUSE. internal_credential_audit.allowed=false is a presented secret that was
  -- REFUSED: a wrong secret, a retired one, or one used outside its scope. 11 such rows exist today.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'credential_refused', 'medium', a.function_name, a.context,
           jsonb_build_object('audit_id', a.id, 'credential_id', a.credential_id,
                              'reason', a.reason, 'at', a.at, 'detail', a.detail),
           'cred_audit:' || a.id
      from public.internal_credential_audit a
     where a.allowed = false
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('credential_refused', n);

  -- D4 A DEAD CREDENTIAL THAT STILL WORKS. last_used_at after retired_at or after expires_at means
  -- a secret that should have stopped being accepted was accepted. That is containment-worthy:
  -- 83 of the 90 rows in internal_credential are active, so revoking one is a real action available
  -- today, and this detection is the trigger for it.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'credential_used_after_end', 'high', c.last_function, c.context,
           jsonb_build_object('credential_id', c.id, 'label', c.label, 'active', c.active,
                              'retired_at', c.retired_at, 'expires_at', c.expires_at,
                              'last_used_at', c.last_used_at, 'use_count', c.use_count),
           'cred_after_end:' || c.id || ':' || to_char(c.last_used_at at time zone 'utc','YYYYMMDDHH24')
      from public.internal_credential c
     where c.last_used_at is not null
       and ( (c.retired_at is not null and c.last_used_at > c.retired_at)
          or (c.expires_at is not null and c.last_used_at > c.expires_at)
          or (c.active = false and c.last_used_at > coalesce(c.retired_at, c.rotated_at, c.created_at)) )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('credential_used_after_end', n);

  -- D5 OTP BRUTE FORCE. The login is a mobile number and a one-time code (there is no observe mode
  -- and no password), so guessing the code IS the attack on customer identity. attempts is
  -- incremented per wrong code by the verifier.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'otp_brute_force', 'medium', 'customer_phone_otps', o.phone,
           jsonb_build_object('otp_id', o.id, 'attempts', o.attempts, 'consumed', o.consumed,
                              'customer_id', o.customer_id, 'created_at', o.created_at),
           'otp_attempts:' || o.id
      from public.customer_phone_otps o
     where o.attempts >= 5
       and o.created_at >= v_since
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('otp_brute_force', n);

  -- D6 OTP ENUMERATION. Many codes ISSUED to one number in a short window is a different attack
  -- from many codes guessed: it is someone using our SMS to hammer a phone, or mapping which
  -- numbers exist. Bucketed to the hour so the fingerprint is stable across re-runs.
  with agg as (
    select o.phone, date_trunc('hour', o.created_at) as hr, count(*) as issued
      from public.customer_phone_otps o
     where o.created_at >= v_since
     group by 1,2
    having count(*) >= 5),
  ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'otp_enumeration', 'medium', 'customer_phone_otps', agg.phone,
           jsonb_build_object('issued', agg.issued, 'hour', agg.hr),
           'otp_issued:' || agg.phone || ':' || to_char(agg.hr at time zone 'utc','YYYYMMDDHH24')
      from agg
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('otp_enumeration', n);

  -- D7 SSRF. resend_inbound records a refused attachment URL into agent_runs with
  -- counts.ssrf_refused; accountant reports the same refusal in its run note. Both are read here
  -- rather than adding a second write path to two deployed functions.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'ssrf_refused', 'medium', r.agent, r.counts->>'stage',
           jsonb_build_object('agent_run_id', r.id, 'counts', r.counts,
                              'note', left(coalesce(r.note,''), 500), 'at', r.started_at),
           'agent_run_ssrf:' || r.id
      from public.agent_runs r
     where r.started_at >= v_since
       and ( r.counts ? 'ssrf_refused'
          or r.note ilike '%url_refused%'
          or r.note ilike '%url_refused_after_redirect%' )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('ssrf_refused', n);

  -- D8 A REFUSED UPLOAD SHAPE. sanitizeUpload refusing an executable, an HTML polyglot or a zip
  -- bomb is the guard working — and a run of them from one sender is someone probing what we
  -- accept. Recorded low, because a single refusal is far more often a careless browser.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'upload_shape_refused', 'low', r.agent, null,
           jsonb_build_object('agent_run_id', r.id, 'counts', r.counts,
                              'note', left(coalesce(r.note,''), 500), 'at', r.started_at),
           'agent_run_upload:' || r.id
      from public.agent_runs r
     where r.started_at >= v_since
       and ( r.counts ? 'attachment_refused'
          or r.note ilike '%refused by sanitizeUpload%'
          or r.note ilike '%unsafe_file_type%'
          or r.note ilike '%unsafe_file_content%'
          or r.note ilike '%zip_expands_too_far%' )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('upload_shape_refused', n);

  -- D9 SECRETS. security_audit_log is trigger-written and had 76 rows that nothing ever read.
  --
  -- THE FIRST VERSION OF THIS BRANCH WAS WRONG AND THE EXECUTION SHOWED IT. It raised one medium
  -- event per row, which on the first run produced 76 'secret_table_written' events against ONE
  -- malware event — a guard that fires when the system works, burying the signal it exists to
  -- surface. Measured: all 76 rows are app_secrets INSERT/UPDATE by db_user `postgres`, which is
  -- how EVERY secret in this estate is written, so "a secret was written" carries no information.
  -- The 76 noise rows were deleted with this correction; nothing else in security_events was
  -- touched, and the corrected rules below use different fingerprints so they evaluate freely.
  --
  -- What DOES carry information, and is rare enough to mean something:
  --   * a DELETE — no routine in this estate deletes a secret or a credential row;
  --   * a write by a db_user that is not one of ours;
  --   * a BURST. Measured over the whole table: the busiest hour ever recorded is 5 writes. 25 in
  --     one hour is five times the observed peak, so it cannot fire on ordinary operation, and it
  --     is raised ONCE per hour rather than once per row.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select case when s.action = 'DELETE' then 'secret_deleted' else 'secret_written_by_unexpected_role' end,
           'high', 'security_audit_log', s.db_user,
           jsonb_build_object('audit_id', s.id, 'action', s.action, 'table', s.table_name,
                              'row_pk', s.row_pk, 'at', s.at, 'old', s.old_data),
           'sec_audit:' || s.id
      from public.security_audit_log s
     where s.at >= v_since
       and s.table_name in ('app_secrets','internal_credential','internal_credential_audit')
       and ( s.action = 'DELETE'
          or s.db_user is null
          or s.db_user not in ('postgres','supabase_admin','supabase_storage_admin','service_role') )
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('secret_anomaly', n);

  with agg as (
    select date_trunc('hour', s.at) as hr, count(*) as writes
      from public.security_audit_log s
     where s.at >= v_since
       and s.table_name in ('app_secrets','internal_credential')
     group by 1
    having count(*) >= 25),
  ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'secret_write_burst', 'medium', 'security_audit_log', null,
           jsonb_build_object('writes', agg.writes, 'hour', agg.hr,
                              'observed_peak_before_this_rule', 5),
           'secret_burst:' || to_char(agg.hr at time zone 'utc','YYYYMMDDHH24')
      from agg
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('secret_write_burst', n);

  -- D10 A NEW SECURITY ADVISOR FINDING. in_baseline=false means the finding appeared after the
  -- baseline was taken. WARN is medium, INFO is low — a new table with RLS on and no policy is
  -- worth seeing but is not an intrusion.
  with ins as (
    insert into public.security_events (kind, severity, source, subject, detail, fingerprint)
    select 'new_security_advisor',
           case when b.level in ('WARN','ERROR') then 'medium' else 'low' end,
           'supabase_advisors', b.name,
           jsonb_build_object('cache_key', b.cache_key, 'level', b.level, 'title', b.title,
                              'metadata', b.metadata, 'first_seen_at', b.first_seen_at),
           'advisor:' || b.cache_key
      from public.security_advisor_baseline b
     where b.in_baseline = false
       and b.cleared_at is null
    on conflict (fingerprint) do nothing
    returning 1)
  select count(*) into n from ins;  v := v || jsonb_build_object('new_security_advisor', n);

  return v || jsonb_build_object(
    'window', p_window::text,
    'at', now(),
    'total_new', (select coalesce(sum((value)::int), 0)
                    from jsonb_each_text(v) where key <> 'window'));
end;
$$;

comment on function public.fn_security_detect(interval) is
  'Deterministic intrusion/attack detector. Reads file_scan, internal_credential(_audit), '
  'customer_phone_otps, agent_runs, security_audit_log and security_advisor_baseline and writes '
  'security_events. Idempotent: every insert is fingerprinted from its source row, so re-running '
  'reports nothing new. No model on this path.';

revoke execute on function public.fn_security_detect(interval) from public;
revoke execute on function public.fn_file_is_cleared(text) from public;

-- ── 5b. THE DETECTOR RUNS WHEN THE EVIDENCE ARRIVES, NOT WHEN SOMEBODY REMEMBERS ───────────────
--
-- A detector that only runs when a poller calls it is half a control, and the obvious fix — a cron
-- job — is not available: the founder's rule of 7 Sep 2026 is that no job exists without an agent,
-- and this estate holds exactly ONE cron job today. Creating a second one for a seat another agent
-- is building this session would break that rule in order to be timely.
--
-- The evidence itself is the better trigger anyway. A malicious file and a refused credential are
-- both INSERTs, and both are exactly the moment the event should exist — a poller would have added
-- latency to the two detections that least tolerate it. The window is one hour so the trigger does
-- a small amount of work; the SCHEDULED sweep (fn_security_detect over a longer window) remains
-- available to the seat for the rate-based and advisor-derived branches, which have no insert to
-- hang off.
--
-- ponytail: fn_security_detect runs all its branches on each trigger. At current volumes that is
-- microseconds; if uploads ever run hot, split the per-row branches out of the function.
create or replace function public.fn_security_detect_on_evidence()
returns trigger
set search_path = public, pg_catalog
language plpgsql as $$
begin
  -- Never let the watch break the thing it watches: a detector that raises stops a supplier
  -- registering, which is a worse outcome than a late event.
  begin
    perform public.fn_security_detect(interval '1 hour');
  exception when others then
    null;
  end;
  return null;
end;
$$;
revoke execute on function public.fn_security_detect_on_evidence() from public;

drop trigger if exists z90_security_detect on public.file_scan;
create trigger z90_security_detect
  after insert on public.file_scan
  for each row when (new.verdict in ('malicious','suspicious'))
  execute function public.fn_security_detect_on_evidence();

drop trigger if exists z90_security_detect on public.internal_credential_audit;
create trigger z90_security_detect
  after insert on public.internal_credential_audit
  for each row when (new.allowed = false)
  execute function public.fn_security_detect_on_evidence();

-- ── 6. THE ONE THING A WATCHER READS ───────────────────────────────────────────────────────────
--
-- Not a dashboard: a single answer to "is anything happening, and what can I not see".
create or replace function public.fn_security_watch(p_window interval default interval '7 days')
returns jsonb language sql stable set search_path = public, pg_catalog as $$
  select jsonb_build_object(
    'at', now(),
    'window', p_window::text,
    'events_by_kind', coalesce((
        select jsonb_object_agg(kind, c) from (
          select kind, count(*) c from public.security_events
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'events_by_severity', coalesce((
        select jsonb_object_agg(severity, c) from (
          select severity, count(*) c from public.security_events
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'files_scanned', (select count(*) from public.file_scan where created_at >= now() - p_window),
    'files_by_verdict', coalesce((
        select jsonb_object_agg(verdict, c) from (
          select verdict, count(*) c from public.file_scan
           where created_at >= now() - p_window group by 1) t), '{}'::jsonb),
    'files_blocked', (select count(*) from public.file_scan
                       where blocked and created_at >= now() - p_window),
    'quarantined_total', (select count(*) from public.v_file_quarantine),
    'advisors_baseline', (select count(*) from public.security_advisor_baseline where in_baseline),
    'advisors_new', (select count(*) from public.security_advisor_baseline
                      where not in_baseline and cleared_at is null),
    'advisors_last_refreshed', (select max(last_seen_at) from public.security_advisor_baseline),
    'gaps_open', (select jsonb_agg(jsonb_build_object('name', name, 'status', status,
                                                      'needs', what_would_close_it))
                    from public.security_gap where status <> 'closed')
  );
$$;
revoke execute on function public.fn_security_watch(interval) from public;

comment on function public.fn_security_watch(interval) is
  'The security watch in one object: what was detected, what was scanned, what is quarantined, how '
  'far the advisor baseline has drifted, and — deliberately in the same payload — what this watch '
  'still cannot do.';

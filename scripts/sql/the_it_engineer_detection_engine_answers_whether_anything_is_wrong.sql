-- THE IT ENGINEER'S DETECTION ENGINE — "is anything wrong, right now, anywhere".
--
-- Founder, 9 Sep 2026: "we build the it engineer to monitor everything ... he monitor literally
-- everything in the app and the website", with two worked examples — "a bug when a customer
-- registers" and "the generated comparison report is lagging".
--
-- This file is the DETECTION half only. It decides. It does not seat the agent, does not
-- instrument the edge functions, and does not deliver anything to anybody: a sibling build owns
-- supabase/functions/it_engineer/, another owns capture, another owns the founder alerting.
-- The contract between them is public.it_watch_finding (durable) and fn_it_detect() (live).
--
-- EVERYTHING HERE IS DETERMINISTIC. No model call is on this path, and none may be added to it.
--
-- ────────────────────────────────────────────────────────────────────────────────────────────
-- THE DESIGN CONSTRAINT THAT SHAPED EVERY DETECTOR
--
-- This estate is full of checks that fire on a healthy system or cannot fire at all. The company
-- has ONE customer and almost no traffic, so ANY detector keyed to an absolute business count
-- ("fewer than N inquiries today") screams forever and is switched off within a week. So:
--
--   * Every detector below tests a DELTA (this window against this subject's own history) or a
--     STATE (a queue's oldest undrained row, an HTTP status, a deployment state). Not one of them
--     reads a business volume.
--   * Every detector reports its BASIS. A detector that cannot decide says 'insufficient_history'
--     or 'no_capture_yet' rather than returning nothing, because "found nothing" and "was never
--     able to look" are the two things this estate has repeatedly failed to tell apart.
--   * A finding CLOSES ITSELF when the condition clears. A ledger that only ever grows is a
--     backlog, not a monitor.
--
-- WHAT EACH DETECTOR DOES ON AN IDLE ESTATE is written above the detector, in its own words.
--
-- ────────────────────────────────────────────────────────────────────────────────────────────
-- WHY THE FINDINGS DO NOT GO INTO public.os_incidents, THOUGH THAT TABLE EXISTS
--
-- Measured 9 Sep 2026, not assumed. os_incidents carries four triggers, and two of them make an
-- INSERT into it something other than a record:
--   t20_os_incident_open_task -> fn_os_incident_open_task() INSERTs a row into public.org_tasks.
--   trg_event_incident        -> fn_emit_event() INSERTs a row into public.company_event.
-- The founder's ruling of 7 Sep 2026 is "no tasks excepts what i confirm". A monitor that mints
-- an org_task every fifteen minutes would manufacture exactly the thing he deleted, and
-- fn_os_incident_open() additionally net.http_posts alert_founder, which is another build's job.
--
-- So the findings live in public.it_watch_finding: no triggers, no tasks, no email, no cascade.
-- os_incidents remains the human incident ledger; promoting a finding into it is a deliberate act
-- for whoever owns delivery, not a side effect of measuring.
--
-- ────────────────────────────────────────────────────────────────────────────────────────────
-- SEVERITY IS DERIVED, NEVER ASSIGNED
--
-- The founder's two examples differ in kind: a customer failing to register is worse than a cron
-- missing a beat. For the engine to say which is which, severity has to come from a real property
-- of the system rather than a constant somebody typed next to each detector. It comes from two
-- measured facts and nothing else:
--
--   STATE   — how far the subject has fallen, computed from the numbers: 'stopped' (every attempt
--             in the window failed / the subject has gone silent past its own cadence / the site
--             does not answer), 'degraded' (a failure rate above its own baseline, a queue past
--             its threshold, runtime errors), 'delayed' (latency has departed its own baseline).
--   SURFACE — whether the failing subject is reachable by anything OUTSIDE our own backend. This
--             is NOT a label of mine: it is read out of the deployed function, which either checks
--             an internal shared secret in the body (requireInternal / `__secret !==`) and is
--             therefore backend-only, or does not and is therefore reached by a browser, a
--             customer or a third-party webhook. All 64 deployed functions are classified from it
--             in it_watch_subject, alongside their verify_jwt setting as corroborating evidence.
--
-- login_otp has no secret gate. So a login_otp that fails every attempt in a window is
-- state='stopped' on a public surface and comes out CRITICAL — the founder's registration
-- example — while send_outbox, which does have one, comes out HIGH for the same failure. Nobody
-- ranked either of them.
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. WHAT IS BEING WATCHED, AND CAN ANYTHING OUTSIDE THE BACKEND REACH IT ──────────────────
-- Seeded from supabase/config.toml and from each deployed index.ts. This table is a transcription
-- of the deployment, not an opinion about importance.
create table if not exists public.it_watch_subject (
  subject        text primary key,
  kind           text not null default 'edge_function',
  public_surface boolean not null default false,
  verify_jwt     boolean,
  secret_gated   boolean,
  source         text not null default 'supabase/config.toml + supabase/functions/<fn>/index.ts',
  note           text
);
alter table public.it_watch_subject add column if not exists verify_jwt   boolean;
alter table public.it_watch_subject add column if not exists secret_gated boolean;
comment on table public.it_watch_subject is
  'Every monitored subject and whether anything outside our own backend can reach it. public_surface = the deployed function has NO internal shared-secret gate. Severity is derived from this column; it is a transcription of the deployed code and config, never a hand-assigned importance.';

-- HOW public_surface IS DERIVED, and why it is not simply verify_jwt.
-- The first cut of this table used "verify_jwt = false" alone. The positive control caught it, which
-- is what positive controls are for: send_outbox is verify_jwt=false and came out as a CUSTOMER-facing
-- failure at severity high. It is not customer-facing. verify_jwt=false only means the gateway does
-- not demand a JWT; 28 of these functions then check an internal shared secret in the request body
-- (requireInternal, or a literal comparison of __secret), which is precisely the marker of
-- "only our own backend calls this".
--
-- So the axis is the SECRET GATE, and it is read out of the deployed source:
--   public_surface = NOT secret_gated   -- reachable by something that is not our backend
--   verify_jwt     = kept as evidence: false means an anonymous stranger reaches it, true means a
--                    signed-in customer or supplier does. Both are outside the backend; both are
--                    customer-visible when they break, which is the question severity is asking.
-- Measured 9 Sep 2026 over all 64 deployed functions: 36 reachable from outside, 28 backend-only.
-- login_otp, customer_portal, customer_api, supplier_portal and stripe_* are outside; send_outbox,
-- dropbox_backup, email_cron, accountant, sales_engineer and quote_compare are backend-only.
--
-- THIS TABLE IS A SNAPSHOT, AND THE SOURCE MOVES. Within this very session a sibling build added
-- secret gates to edge functions, and the registry seeded an hour earlier no longer described
-- them. A stale row here does not hide a fault — the fault is still detected — but it ranks it
-- wrongly, which is how a monitor loses the founder's trust. scripts/checks/it_watch_subject_matches_the_deployment.mjs
-- re-derives the whole table from config.toml and the function sources and fails on any
-- disagreement, so the drift is a red check rather than a quiet mis-ranking.
insert into public.it_watch_subject (subject, kind, public_surface, verify_jwt, secret_gated) values
  ('accountant','edge_function',false,true,true),
  ('ai_gateway','edge_function',false,false,true),
  ('cad_convert','edge_function',false,false,true),
  ('ceo_agent','edge_function',false,true,true),
  ('claim_lookup','edge_function',true,false,false),
  ('compliance_archive','edge_function',false,false,true),
  ('contact_submit','edge_function',true,true,false),
  ('customer_api','edge_function',true,true,false),
  ('customer_documents','edge_function',true,false,false),
  ('customer_intelligence','edge_function',true,true,false),
  ('customer_portal','edge_function',true,false,false),
  ('doc_extract','edge_function',false,false,true),
  ('drawing_boq','edge_function',false,false,true),
  ('drawing_redact','edge_function',false,false,true),
  ('dropbox_backup','edge_function',false,false,true),
  ('email_cron','edge_function',false,false,true),
  ('email_triage','edge_function',false,false,true),
  ('extract_text','edge_function',false,false,true),
  ('inbound_email','edge_function',true,false,false),
  ('inquiry_intake','edge_function',true,true,false),
  ('it_engineer','edge_function',false,true,true),
  ('kyc','edge_function',true,false,false),
  ('license_extract','edge_function',false,false,true),
  ('login_otp','edge_function',true,false,false),
  ('messages_api','edge_function',true,true,false),
  ('mobile_otp','edge_function',false,false,true),
  ('negotiation_assistant','edge_function',true,true,false),
  ('pdf_native','edge_function',false,false,true),
  ('procurement_api','edge_function',true,true,false),
  ('project_api','edge_function',true,true,false),
  ('quote_compare','edge_function',false,true,true),
  ('quote_extract','edge_function',false,false,true),
  ('refund_flow','edge_function',true,false,false),
  ('refunds_api','edge_function',false,false,true),
  ('resend_inbound','edge_function',true,false,false),
  ('resend_webhook','edge_function',true,false,false),
  ('resilience_ping','edge_function',true,false,false),
  ('reveal_invoice','edge_function',true,false,false),
  ('rfq_flag','edge_function',true,false,false),
  ('role_guard','edge_function',true,false,false),
  ('sales_engineer','edge_function',false,true,true),
  ('send_outbox','edge_function',false,false,true),
  ('send_sms','edge_function',false,false,true),
  ('send_whatsapp','edge_function',false,false,true),
  ('site_assistant','edge_function',true,false,false),
  ('stripe_checkout','edge_function',true,false,false),
  ('stripe_confirm','edge_function',true,false,false),
  ('stripe_setup','edge_function',true,true,false),
  ('stripe_setup_page','edge_function',true,false,false),
  ('stripe_webhook','edge_function',true,false,false),
  ('supplier_ack','edge_function',true,false,false),
  ('supplier_api','edge_function',true,true,false),
  ('supplier_catalog_ingest','edge_function',true,true,false),
  ('supplier_onboard','edge_function',false,true,true),
  ('supplier_pay','edge_function',true,false,false),
  ('supplier_portal','edge_function',true,true,false),
  ('transcribe','edge_function',true,false,false),
  ('unsubscribe','edge_function',true,false,false),
  ('voice_otp','edge_function',true,false,false),
  ('voice_otp_capture','edge_function',true,false,false),
  ('wa_inbound','edge_function',false,false,true),
  ('wa_optin_set','edge_function',false,true,true),
  ('wa_template_setup','edge_function',false,false,true),
  ('wa_templates_watch','edge_function',false,true,true)
on conflict (subject) do update
  set kind = excluded.kind, public_surface = excluded.public_surface,
      verify_jwt = excluded.verify_jwt, secret_gated = excluded.secret_gated,
      source = 'supabase/config.toml + supabase/functions/<fn>/index.ts';

-- Two subjects that are not edge functions and so have neither setting to transcribe. Both are
-- stated explicitly rather than defaulted, so nothing is classified by omission.
insert into public.it_watch_subject (subject, kind, public_surface, verify_jwt, secret_gated, source, note) values
  ('scheduler','scheduler',false,null,null,'Vercel cron -> /api/resilience-ping -> resilience_ping',
   'The tick itself. Nothing outside the backend depends on it directly; what it drives does.'),
  ('website','website',true,null,null,'app_secrets.public_site_url',
   'The Next.js site on Vercel. Outside the backend by definition — this is what a customer opens.')
on conflict (subject) do update
  set kind = excluded.kind, public_surface = excluded.public_surface,
      verify_jwt = excluded.verify_jwt, secret_gated = excluded.secret_gated,
      source = excluded.source, note = excluded.note;


-- ── 2. QUEUES THAT SOMEBODY IS SUPPOSED TO BE DRAINING ───────────────────────────────────────
-- This estate has shipped a queue with no consumer at all TWICE: notifications(channel=whatsapp)
-- sat undelivered from 7 Sep because pg_cron was removed and nothing replaced wa_flush, and
-- exec_reports has held 318 rows at status='new' since 6 July. Both were invisible because a
-- pending row looks exactly like one that is merely waiting its turn. The only thing that tells
-- them apart is HOW LONG the oldest one has waited, which is a state, not a volume.
--
-- pending_predicate is executed as SQL by a SECURITY DEFINER function. RLS below plus the revoke
-- at the foot of this file mean only the service role can write this table; do not loosen either.
create table if not exists public.it_watch_queue (
  queue_key         text primary key,
  table_name        text not null,
  pending_predicate text not null,
  ts_column         text not null default 'created_at',
  stall_minutes     integer not null,
  surface           text not null default 'internal',
  enabled           boolean not null default true,
  note              text
);
comment on table public.it_watch_queue is
  'Queues whose oldest undrained row is watched. Detection is by AGE of the oldest pending row against that queue''s own threshold — never by depth, so an idle estate with an empty queue reports nothing.';

insert into public.it_watch_queue (queue_key, table_name, pending_predicate, ts_column, stall_minutes, surface, note) values
  ('notifications_outbox','notifications',
   $$status = 'queued'$$,'created_at',60,'customer',
   'send_outbox drains this every ~30 min off the resilience tick. status=''held'' is EXCLUDED on purpose: a held message is the founder-hold working, not a stall.'),
  ('notifications_stuck_retry','notifications',
   $$status = 'error' and coalesce(attempts,0) >= 3$$,'created_at',240,'customer',
   'A message the sender has given up on. Distinct from the queue above: this one will never drain on its own.'),
  ('exec_reports_unread','exec_reports',
   $$status = 'new'$$,'created_at',10080,'internal',
   'The queue that proved this detector was needed: 318 rows at status=new, oldest 6 July 2026. Threshold is one week.'),
  ('doc_backups_failed','doc_backups',
   $$status = 'error'$$,'created_at',1440,'internal',
   'dropbox_backup retries error rows on each due tick, so an error row older than a day means the retry is not clearing it.'),
  ('review_queue_pending','review_queue',
   $$status = 'pending'$$,'created_at',4320,'internal',
   'Threshold is three days, deliberately loose: this queue is drained by review, which is not continuous.')
on conflict (queue_key) do update
  set table_name = excluded.table_name, pending_predicate = excluded.pending_predicate,
      ts_column = excluded.ts_column, stall_minutes = excluded.stall_minutes,
      surface = excluded.surface, note = excluded.note;


-- ── 3. THE TICK LOG — heartbeat, and the only history the website baseline has ───────────────
-- Three jobs in one table, which is why it is one table and not three:
--   (a) it is the scheduler heartbeat: the gap between consecutive rows IS scheduler health, and
--       unlike a pg_cron-reading check it cannot be fooled by a scheduler that was deleted;
--   (b) it is the website latency sample store, so the site gets a baseline from its own history
--       the same way an agent gets one from agent_runs;
--   (c) it is the audit trail: what the engine saw, and what it decided, every fifteen minutes.
create table if not exists public.it_watch_tick (
  id            bigint generated always as identity primary key,
  ran_at        timestamptz not null default now(),
  findings      integer not null default 0,
  worst         text,
  site_ms       integer,
  site_status   integer,
  detail        jsonb not null default '{}'::jsonb
);
create index if not exists it_watch_tick_ran_at_idx on public.it_watch_tick (ran_at desc);


-- ── 4. THE FINDING LEDGER — open while true, resolved the moment it stops being true ─────────
create table if not exists public.it_watch_finding (
  detector_key text primary key,
  detector     text not null,
  subject      text not null,
  state        text not null,
  severity     text not null,
  title        text not null,
  evidence     jsonb not null default '{}'::jsonb,
  opened_at    timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  seen_count   integer not null default 1,
  status       text not null default 'open',
  resolved_at  timestamptz
);
create index if not exists it_watch_finding_open_idx
  on public.it_watch_finding (severity, last_seen_at desc) where status = 'open';
comment on table public.it_watch_finding is
  'The IT engineer''s live verdict. One row per detector_key while the condition holds; status flips to resolved the tick after it clears. Read this, or fn_it_detect(null,false) for a fresh read that writes nothing.';

alter table public.it_watch_subject enable row level security;
alter table public.it_watch_queue   enable row level security;
alter table public.it_watch_tick    enable row level security;
alter table public.it_watch_finding enable row level security;
-- No policies, deliberately: anon and authenticated get nothing. The service role bypasses RLS,
-- and fn_it_detect is SECURITY DEFINER. Monitoring data names failing internals and must not be
-- readable from the public surface it is watching.


-- ── 4b. A REFUSAL IS NOT A FAILURE ───────────────────────────────────────────────────────────
-- CAUGHT BY RUNNING THE ENGINE AGAINST THE LIVE ESTATE, 9 Sep 2026 07:11 UTC, and it is the most
-- important correction in this file. A sibling build swept every edge function with no credentials.
-- Every function REFUSED — 401, 403, 400 — which is the security posture working exactly as built.
-- Each refusal wrote itself into agent_runs with status='error', and the first cut of D1 read those
-- twelve rows as twelve total outages and returned:
--
--   critical — resend_inbound failed every one of its 1 attempts in the last hour
--   critical — resend_webhook failed every one of its 1 attempts in the last hour
--   critical — stripe_webhook failed every one of its 1 attempts in the last hour
--   high     — send_whatsapp, send_sms, send_outbox, email_cron, dropbox_backup, doc_extract,
--              quote_extract, refunds_api, wa_inbound ... all of them "failed"
--
-- stripe_webhook's row said "bad_signature (rejected before parsing)". wa_inbound's said it had
-- "rejected a JSON caller with a missing or wrong inbound secret". Those are the guards CATCHING
-- something. A monitor that pages the founder at CRITICAL because the front door held is the
-- estate's own "a guard that fires when the system works", and it would have been switched off
-- within a day — taking the real detection with it.
--
-- THE LINE, and it is the standard one: a 4xx is the CALLER being turned away and is never the
-- function's fault; a 5xx is the function's fault. The `fn:<name>` telemetry rows a sibling build
-- writes already carry the HTTP status, so the classification is read out of the data rather than
-- inferred from note text, and it works for any function instrumented later with no edit here.
--
-- A REFUSAL IS COUNTED, NEVER DROPPED. It is reported as window_refused in the evidence, because a
-- SURGE of refusals is a real signal — a rotated credential that did not reach its callers looks
-- exactly like this — and a detector that silently discarded them could not tell a locked-out
-- estate from a quiet one. Detecting that surge belongs to the security build, not this one; what
-- this file owes it is the honest number, which is now in every finding it emits.
create or replace function public.fn_it_run_is_refusal(p_agent text, p_started timestamptz, p_counts jsonb)
returns boolean
language sql
stable
set search_path to 'public'
as $$
  -- THE coalesce IS THE WHOLE FUNCTION'S CORRECTNESS, and it is not decoration.
  -- Caught by the positive control on 9 Sep 2026 before this shipped. Without it, a run whose
  -- counts carry no `signal` key returns `false OR NULL OR NULL OR false OR false` = NULL, and in
  -- D1 the filter `where bad and not refused` evaluates `not NULL` = NULL and DROPS THE ROW. The
  -- effect was total and silent: an injected run of three genuine HTTP 500s on login_otp produced
  -- no finding at all, because most functions' counts have no `signal` key. A detector that goes
  -- quiet on the majority of real faults, while still looking like it works on the minority that
  -- happen to log a signal, is worse than no detector. Three-valued logic has to be closed here,
  -- once, rather than at each of the three call sites.
  select coalesce(
       -- the row's own telemetry says the caller was turned away
       (p_counts ->> 'http') ~ '^4[0-9][0-9]$'
       -- or the function's own log says so, in the four shapes this estate actually writes
    or (p_counts ->> 'signal') in ('forbidden','bad_secret')
    or (p_counts ->> 'authorised') = '0'
    or coalesce(nullif(p_counts ->> 'forbidden','')::int, 0) > 0
       -- or the paired fn:<name> telemetry row, written within milliseconds, carries a 4xx.
       -- stripe_webhook and refunds_api are only caught by this arm: their own counts say nothing.
    or exists (
         select 1 from public.agent_runs t
         where t.agent = 'fn:' || regexp_replace(p_agent, '^fn:', '')
           and t.started_at between p_started - interval '5 seconds' and p_started + interval '5 seconds'
           and (t.counts ->> 'http') ~ '^4[0-9][0-9]$')
  , false)
$$;
comment on function public.fn_it_run_is_refusal(text, timestamptz, jsonb) is
  'True when an agent_runs row records a caller being TURNED AWAY (4xx / forbidden / bad_secret / authorised=0) rather than the subject failing. A refusal is excluded from failure rates and from latency baselines, and reported separately as window_refused — never silently dropped.';

-- agent_runs is about to grow fast now that every edge function writes to it, and the refusal test
-- looks up a paired row by (agent, started_at) for every row it classifies.
create index if not exists agent_runs_agent_started_idx on public.agent_runs (agent, started_at desc);


-- ── 5. SEVERITY, AS A PURE FUNCTION OF TWO MEASURED FACTS ────────────────────────────────────
create or replace function public.fn_it_severity(p_state text, p_public boolean)
returns text
language sql
immutable
set search_path to 'public'
as $$
  select case
    when p_state = 'stopped'  and p_public then 'critical'
    when p_state = 'stopped'               then 'high'
    when p_state = 'degraded' and p_public then 'high'
    when p_state = 'degraded'              then 'medium'
    when p_state = 'delayed'  and p_public then 'medium'
    when p_state = 'delayed'               then 'low'
    else 'low'
  end
$$;
comment on function public.fn_it_severity(text, boolean) is
  'Severity from STATE (how far the subject fell, computed) x SURFACE (verify_jwt=false, transcribed from the deployment). Nothing else. There is no per-detector severity constant anywhere in this build.';


-- ── 6. THE ENGINE ────────────────────────────────────────────────────────────────────────────
-- fn_it_detect(p_web, p_persist)
--   p_web     the website reading the caller measured this tick (Postgres cannot fetch; the
--             resilience tick can). NULL is honest and says so — it never reads as "site fine".
--   p_persist true  = a real tick: writes the heartbeat and moves the finding ledger.
--             false = a read-only probe: decides identically, writes nothing.
create or replace function public.fn_it_detect(p_web jsonb default null, p_persist boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare
  -- The window is one hour and the baseline is the seven days BEFORE it. The window has to be
  -- long enough that a 30-minute job appears in it and short enough that a fault is news.
  c_win       constant interval := interval '60 minutes';
  c_base      constant interval := interval '7 days';
  -- Statuses agent_runs uses for "this run did its job". Anything else, NULL included, is a
  -- failure: a run that started and never recorded an outcome is not a success.
  c_ok        constant text[] := array['ok','success','completed','skipped','warn','held','noop'];
  v_now       timestamptz := now();
  v_find      jsonb := '[]'::jsonb;
  v_notes     jsonb := '{}'::jsonb;
  v_keys      text[] := '{}';
  v_worst     text := 'none';
  r           record;
  v_rate      numeric;
  v_brate     numeric;
  v_state     text;
  v_sev       text;
  v_key       text;
  v_prev      timestamptz;
  v_gap       numeric;
  v_cnt       bigint;
  v_oldest    timestamptz;
  v_age       numeric;
  v_basis     jsonb;
  v_opened    int := 0;
  v_resolved  int := 0;
  v_watched   int;
  v_site_ms   integer;
  v_site_st   integer;
begin

-- ══ D1. EDGE FUNCTIONS / AGENTS FAILING, OR FAILING MORE THAN USUAL ═════════════════════════
-- Reads: public.agent_runs (window vs the 7 days before it), public.it_watch_subject.
-- Fires when every attempt in the window failed ('stopped'), or when the window's failure rate is
-- at least 20 percentage points above this subject's own baseline rate ('degraded').
-- ON AN IDLE ESTATE: an agent with no runs in the window is not evaluated at all, and an agent
-- whose runs all succeeded produces nothing. Silence here means "nothing failed", and D2 below is
-- what stops that being confused with "nothing ran".
-- The `fn:<name>` telemetry rows and the bare `<name>` semantic rows are two logs of the SAME
-- subject, so the prefix is stripped before grouping: otherwise one function appears as two, and
-- neither half can be looked up in it_watch_subject to find out whether it is customer-facing.
for r in
  with runs as (
    select regexp_replace(agent, '^fn:', '')                       subject,
           agent, started_at,
           coalesce(status,'error') <> all (c_ok)                  bad,
           public.fn_it_run_is_refusal(agent, started_at, counts)  refused
    from public.agent_runs
    where started_at > v_now - c_base),
  w as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f,
           count(*) filter (where refused)::int                  refused
    from runs where started_at > v_now - c_win group by subject),
  b as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f
    from runs where started_at <= v_now - c_win group by subject)
  select w.subject agent, w.n, w.f, w.refused, coalesce(b.n,0) bn, coalesce(b.f,0) bf,
         coalesce(s.public_surface,false) pub, (s.subject is not null) known
  from w
  left join b on b.subject = w.subject
  left join public.it_watch_subject s on s.subject = w.subject
  where w.f > 0 and w.n > 0
loop
  v_rate  := r.f::numeric / r.n;
  v_brate := case when r.bn >= 10 then r.bf::numeric / r.bn else null end;
  v_state := case
               when r.f = r.n then 'stopped'
               when r.n >= 3 and (v_rate - coalesce(v_brate, 0)) >= 0.20 then 'degraded'
               else null end;
  continue when v_state is null;
  v_sev := public.fn_it_severity(v_state, r.pub);
  v_key := 'run_failure:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_failure', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', case when v_state = 'stopped'
                  then r.agent || ' failed every one of its ' || r.n || ' attempts in the last hour'
                  else r.agent || ' is failing ' || round(v_rate*100) || '% of attempts, against a baseline of '
                       || coalesce(round(coalesce(v_brate,0)*100)::text,'?') || '%' end,
    'evidence', jsonb_build_object(
      'window_runs', r.n, 'window_failed', r.f, 'window_rate', round(v_rate,4),
      -- Counted, reported, and excluded from the rate above. A caller turned away is not a fault
      -- of this subject; a SURGE of them is a signal the security build owns, not this one.
      'window_refused', r.refused,
      'baseline_runs', r.bn, 'baseline_failed', r.bf,
      'baseline_rate', case when v_brate is null then null else round(v_brate,4) end,
      'baseline_basis', case when r.bn >= 10 then 'measured' else 'insufficient_history' end,
      'public_surface', r.pub,
      'surface_basis', case when r.known then 'supabase/config.toml verify_jwt'
                            else 'subject not in it_watch_subject; treated as internal' end));
end loop;

-- ══ D2. A SUBJECT THAT HAS STOPPED RUNNING WHEN IT SHOULD BE RUNNING ═══════════════════════
-- Reads: public.agent_runs, seven days of it.
-- The hard part is telling a SCHEDULED subject from an EVENT-DRIVEN one, because a subject that
-- only runs when a customer does something is supposed to be silent on a quiet day, and a
-- detector that cannot tell the difference is the "guard that fires when the system works" this
-- estate keeps paying for. Measured 9 Sep 2026, sales_engineer had 105 runs about a minute apart
-- inside a single two-hour burst and had then been silent for four hours — legitimately, because
-- it is event-driven. So a subject qualifies for silence monitoring only when its own history
-- shows a RHYTHM, on all three counts:
--   >= 10 gaps      — enough samples for a median to mean anything
--   >= 12 distinct hours with a run over 7 days — it recurs across time, it is not one burst
--   p90 gap <= 3x p50 gap — the gaps are TIGHT; a bursty subject has p90 far above p50
-- Then it is silent when it has been quiet for more than 4x its own median gap (floor 30 min).
-- ON AN IDLE ESTATE, measured on the live data: exactly ONE of the eight subjects in agent_runs
-- qualifies today — send_outbox (37 distinct hours, p50 30.1 min, p90 45.0 min, ratio 1.5).
-- login_otp (ratio 187), sales_engineer and accountant (2 and 4 distinct hours) are correctly
-- excluded as event-driven. The count of qualifying subjects is reported in notes.cadence, so
-- "no silence findings" can never be mistaken for "nothing is being watched".
v_watched := 0;
for r in
  with s0 as (
    select regexp_replace(agent, '^fn:', '') agent, started_at
    from public.agent_runs where started_at > v_now - c_base),
  g as (
    select agent, started_at,
           extract(epoch from (started_at - lag(started_at) over (partition by agent order by started_at)))/60 gap
    from s0),
  c as (
    select agent,
           count(*) filter (where gap > 0)::int                                   samples,
           count(distinct date_trunc('hour', started_at))::int                    hours,
           (percentile_cont(0.5) within group (order by gap) filter (where gap > 0))::numeric p50,
           (percentile_cont(0.9) within group (order by gap) filter (where gap > 0))::numeric p90,
           max(started_at)                                                        last_run
    from g group by agent)
  select c.*, coalesce(s.public_surface,false) pub,
         extract(epoch from (v_now - c.last_run))/60 silent_min
  from c left join public.it_watch_subject s on s.subject = c.agent
  where c.samples >= 10 and c.hours >= 12 and c.p50 > 0 and c.p90 <= c.p50 * 3
loop
  v_watched := v_watched + 1;
  continue when r.silent_min <= greatest(r.p50 * 4, 30);
  v_sev := public.fn_it_severity('stopped', r.pub);
  v_key := 'run_silent:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_silent', 'subject', r.agent,
    'state', 'stopped', 'severity', v_sev,
    'title', r.agent || ' has not run for ' || round(r.silent_min) || ' minutes; it normally runs every '
             || round(r.p50) || ' minutes',
    'evidence', jsonb_build_object(
      'silent_minutes', round(r.silent_min,1), 'last_run', r.last_run,
      'cadence_p50_min', round(r.p50,2), 'cadence_p90_min', round(r.p90,2),
      'cadence_samples', r.samples, 'distinct_hours_7d', r.hours,
      'threshold_min', round(greatest(r.p50 * 4, 30),1),
      'basis', 'measured from this subject''s own inter-run gaps over 7 days',
      'public_surface', r.pub));
end loop;
v_notes := v_notes || jsonb_build_object('cadence', jsonb_build_object(
  'subjects_with_a_measurable_rhythm', v_watched,
  'basis', case when v_watched = 0
                then 'no subject in agent_runs yet recurs regularly enough to have a cadence; silence cannot be detected for any subject'
                else 'measured' end));

-- ══ D3. THE SCHEDULER ITSELF ════════════════════════════════════════════════════════════════
-- Reads: public.it_watch_tick — its own previous row.
-- The live scheduler is Vercel cron -> /api/resilience-ping -> resilience_ping, every 15 minutes.
-- pg_cron is dead by founder instruction (one inactive job; 234 deleted on 7 Sep), so any check
-- that reads cron.job_run_details to judge scheduler health is now reading a table nothing writes
-- — a guard that cannot fire. The gap between two rows of this table cannot be fooled that way:
-- if the tick did not happen, there is no row, and the next tick reports the hole it fell into.
-- ON AN IDLE ESTATE: silent, because the tick still runs on an idle estate. On the very first
-- tick there is no previous row, and it reports basis 'first_tick' rather than a clean bill.
select max(ran_at) into v_prev from public.it_watch_tick;
if v_prev is null then
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','first_tick','detail','no previous tick recorded; the gap detector arms from the next tick onward'));
else
  v_gap := extract(epoch from (v_now - v_prev))/60;
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','measured','gap_minutes', round(v_gap,1), 'expected_minutes', 15, 'threshold_minutes', 45));
  if v_gap > 45 then
    v_sev := public.fn_it_severity('stopped', false);
    v_key := 'scheduler_gap';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'scheduler_gap', 'subject', 'scheduler',
      'state', 'stopped', 'severity', v_sev,
      'title', 'the 15-minute scheduler went ' || round(v_gap) || ' minutes without a tick — at least three were missed',
      'evidence', jsonb_build_object(
        'gap_minutes', round(v_gap,1), 'previous_tick', v_prev, 'expected_every_minutes', 15,
        'path','Vercel cron -> /api/resilience-ping -> resilience_ping',
        'basis','measured from the interval between this tick and the previous one'));
  end if;
end if;

-- ══ D4. DATABASE AND FUNCTION ERRORS ════════════════════════════════════════════════════════
-- Reads: public.error_events (the capture a sibling build is filling right now).
-- THIS IS THE DETECTOR MOST AT RISK OF THE "zero cannot tell a dead guard from an idle system"
-- failure, because error_events has held 0 rows for its entire existence. So it never reports a
-- clean bill from emptiness: capture_alive is computed from whether ANY row landed in seven days,
-- and while that is false the engine says 'no_capture_yet' out loud.
select count(*) into v_cnt from public.error_events where created_at > v_now - c_base;
v_notes := v_notes || jsonb_build_object('error_capture', jsonb_build_object(
  'capture_alive', v_cnt > 0, 'rows_7d', v_cnt,
  'basis', case when v_cnt > 0 then 'measured'
                else 'no_capture_yet — error_events is empty, so an absence of findings here proves nothing' end));
for r in
  select e.source, e.kind,
         count(*)::int n,
         count(*) filter (where lower(coalesce(e.severity,'error')) in ('critical','fatal'))::int crit,
         coalesce(s.public_surface,false) pub
  from public.error_events e
  left join public.it_watch_subject s on s.subject = e.source
  where e.created_at > v_now - c_win
    and lower(coalesce(e.severity,'error')) <> all (array['info','debug','notice','warn','warning'])
  group by e.source, e.kind, s.public_surface
loop
  v_state := case when r.crit > 0 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.pub);
  v_key   := 'error_events:' || coalesce(r.source,'?') || ':' || coalesce(r.kind,'?');
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'error_events', 'subject', coalesce(r.source,'unknown'),
    'state', v_state, 'severity', v_sev,
    'title', r.n || ' ' || coalesce(r.kind,'error') || ' error(s) from ' || coalesce(r.source,'an unnamed source')
             || ' in the last hour' || case when r.crit > 0 then ', ' || r.crit || ' of them critical' else '' end,
    'evidence', jsonb_build_object(
      'window_errors', r.n, 'critical', r.crit, 'kind', r.kind,
      'public_surface', r.pub, 'basis','measured from error_events rows in the window'));
end loop;

-- ══ D5. A QUEUE NOBODY IS DRAINING ══════════════════════════════════════════════════════════
-- Reads: public.it_watch_queue, and each registered table by its own predicate.
-- The test is the AGE of the oldest pending row against that queue's own threshold — never the
-- depth. A backlog of 400 rows that is one minute old is a busy queue; one row that is nine weeks
-- old is a dead consumer.
-- ON AN IDLE ESTATE: a queue with nothing pending is skipped before any threshold is consulted,
-- so an empty estate produces nothing. The two queues that are genuinely stalled today
-- (exec_reports at status='new' since 6 July, doc_backups at status='error' since 11 July) do
-- fire, correctly — they are real, and neither is a business volume.
for r in select * from public.it_watch_queue where enabled order by queue_key loop
  begin
    execute format('select count(*), min(%I) from public.%I where %s', r.ts_column, r.table_name, r.pending_predicate)
      into v_cnt, v_oldest;
  exception when others then
    v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key,
      jsonb_build_object('basis','unreadable','error', sqlerrm));
    continue;
  end;
  continue when coalesce(v_cnt,0) = 0 or v_oldest is null;
  v_age := extract(epoch from (v_now - v_oldest))/60;
  continue when v_age <= r.stall_minutes;
  v_state := case when v_age > r.stall_minutes * 4 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.surface = 'customer');
  v_key   := 'queue_stalled:' || r.queue_key;
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'queue_stalled', 'subject', r.queue_key,
    'state', v_state, 'severity', v_sev,
    'title', r.table_name || ': ' || v_cnt || ' undrained row(s), the oldest waiting '
             || round(v_age/60) || ' hours against a ' || round(r.stall_minutes/60.0) || '-hour threshold',
    'evidence', jsonb_build_object(
      'pending_rows', v_cnt, 'oldest_pending', v_oldest, 'oldest_age_minutes', round(v_age,1),
      'threshold_minutes', r.stall_minutes, 'predicate', r.pending_predicate,
      'public_surface', r.surface = 'customer',
      'basis','measured from the age of the oldest row matching the predicate'));
end loop;

-- ══ D6. LATENCY — THE FOUNDER'S OWN EXAMPLE ═════════════════════════════════════════════════
-- Reads: public.agent_runs, finished_at - started_at.
-- "Lagging" is meaningless without a baseline, so the baseline is each subject's own trailing
-- seven days ENDING at the start of the window (the window cannot pollute its own reference).
-- A departure has to clear three bars at once, and the three exist to stop three different false
-- positives: above the subject's own p95 (not just above typical), at least double its median
-- (not a 5% drift), and at least one second in absolute terms (so a 2ms -> 5ms move on a subject
-- that does nothing is not an incident).
--
-- WHAT IT DOES ON DAY ONE, said plainly rather than implied. Measured on the live data, 9 Sep:
--   send_outbox   65 samples, p50 9,956ms, p95 21,320ms -> 'measured'. Armed. Fires above ~21.3s.
--   sales_engineer / accountant / compliance_archive — every duration is exactly 0ms, because
--       their writer sets finished_at = started_at. Zero spread is not a fast subject, it is NO
--       SIGNAL, and it is reported as 'no_latency_signal' rather than as a healthy baseline.
--   login_otp / dropbox_backup / quote_extract / doc_extract — under 20 samples ->
--       'insufficient_history'.
-- So exactly ONE subject has a real latency baseline today. Every subject the sibling build
-- instruments with timing will arm itself here automatically once it has 20 runs; nothing needs
-- editing. The per-subject basis is returned in notes.latency every tick, so the founder's
-- "the comparison report is lagging" can be answered with either a departure or an honest "there
-- is not enough history of that report yet to know", and never with a false all-clear.
v_basis := '{}'::jsonb;
for r in
  -- A 403 returned in four milliseconds is not a measurement of how long this subject's work
  -- takes, so refusals are excluded from the baseline as well as from the failure rate. Left in,
  -- they would drag the baseline down and make ordinary work look like a departure.
  with d as (
    select regexp_replace(agent, '^fn:', '') agent, started_at,
           extract(epoch from (finished_at - started_at)) * 1000 ms
    from public.agent_runs
    where finished_at is not null and finished_at >= started_at and started_at > v_now - c_base
      and not public.fn_it_run_is_refusal(agent, started_at, counts)),
  b as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50,
           (percentile_cont(0.95) within group (order by ms))::numeric p95,
           min(ms)::numeric mn, max(ms)::numeric mx
    from d where started_at <= v_now - c_win group by agent),
  w as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50
    from d where started_at > v_now - c_win group by agent)
  select b.agent, b.n bn, b.p50 bp50, b.p95 bp95, b.mn bmn, b.mx bmx,
         w.n wn, w.p50 wp50, coalesce(s.public_surface,false) pub
  from b
  left join w on w.agent = b.agent
  left join public.it_watch_subject s on s.subject = b.agent
loop
  v_state := null;
  if r.bn < 20 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_history','baseline_samples', r.bn, 'samples_needed', 20));
  elsif r.bmx = r.bmn then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','no_latency_signal','constant_ms', round(r.bmn),
      'detail','every recorded duration is identical, so this subject reports no timing to depart from'));
  elsif coalesce(r.wn,0) < 3 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_window','window_samples', coalesce(r.wn,0), 'samples_needed', 3,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95)));
  else
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','measured','baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95),
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'fires_above_ms', round(greatest(r.bp95, r.bp50 * 2, 1000))));
    if r.wp50 > r.bp95 and r.wp50 >= r.bp50 * 2 and r.wp50 >= 1000 then
      v_state := 'delayed';
    end if;
  end if;
  continue when v_state is null;
  v_sev  := public.fn_it_severity(v_state, r.pub);
  v_key  := 'latency:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'latency', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', r.agent || ' is taking ' || round(r.wp50) || 'ms, against its own baseline of '
             || round(r.bp50) || 'ms (p95 ' || round(r.bp95) || 'ms)',
    'evidence', jsonb_build_object(
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95), 'baseline_samples', r.bn,
      'rule','window p50 > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
      'public_surface', r.pub, 'basis','measured against this subject''s own trailing 7 days'));
end loop;
v_notes := v_notes || jsonb_build_object('latency', v_basis);

-- ══ D7. THE WEBSITE ═════════════════════════════════════════════════════════════════════════
-- Reads: p_web, the reading the caller took this tick. Postgres cannot fetch, so the tick fetches
-- and Postgres judges — the same division this estate already uses for the OpenRouter meter.
-- Four separate questions, because they fail separately:
--   is it up            home.status outside 2xx/3xx, or a fetch that threw   -> stopped -> CRITICAL
--   did a deploy fail   latest production deployment state ERROR/CANCELED    -> degraded -> HIGH
--   runtime errors      Vercel's runtime error count in the window           -> degraded -> HIGH
--   is it slow          home.ms against the site's own history in it_watch_tick -> delayed
-- The website is public_surface = true by definition, which is why a site that does not answer
-- outranks everything else the engine can find.
-- ON AN IDLE ESTATE: an idle site still answers, so silence here means the site answered. When no
-- reading was taken it reports 'not_probed_this_tick' and NEVER reads as a clean bill.
if p_web is null then
  v_notes := v_notes || jsonb_build_object('website', jsonb_build_object(
    'basis','not_probed_this_tick',
    'detail','no reading was passed to fn_it_detect; the site was not checked and is NOT being reported as healthy'));
else
  v_site_st := nullif(p_web #>> '{home,status}','')::int;
  v_site_ms := nullif(p_web #>> '{home,ms}','')::numeric::int;

  if v_site_st is null or v_site_st < 200 or v_site_st >= 400 then
    v_sev  := public.fn_it_severity('stopped', true);
    v_key  := 'website_down';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_down', 'subject', 'website',
      'state','stopped','severity', v_sev,
      'title', case when v_site_st is null
                    then 'the website did not answer at all: ' || coalesce(p_web #>> '{home,error}','no status and no error was reported')
                    else 'the website answered HTTP ' || v_site_st end,
      'evidence', jsonb_build_object(
        'status', v_site_st, 'url', p_web #>> '{home,url}', 'error', p_web #>> '{home,error}',
        'ms', v_site_ms, 'public_surface', true, 'basis','measured by HTTP request this tick'));
  end if;

  if upper(coalesce(p_web #>> '{deployment,state}','')) in ('ERROR','CANCELED') then
    v_sev  := public.fn_it_severity('degraded', true);
    v_key  := 'website_deploy_failed';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_deploy_failed', 'subject', 'website',
      'state','degraded','severity', v_sev,
      'title', 'the latest production deployment is ' || (p_web #>> '{deployment,state}')
               || ' — the site is still serving the previous build, so new work is not live',
      'evidence', jsonb_build_object(
        'deployment', p_web -> 'deployment', 'public_surface', true,
        'basis','measured from the Vercel deployments API this tick'));
  end if;

  -- Runtime errors. Probed 9 Sep 2026 with the stored app_secrets.vercel_token: there is no
  -- runtime-log endpoint this token can read — /v1/projects/<id>/runtime-logs,
  -- /v1/deployments/<uid>/runtime-logs and /v1/observability/runtime-logs all return 404, and the
  -- deployment `events` endpoints return BUILD output only. So the caller may legitimately be
  -- unable to supply a count, and when it cannot, THIS IS SAID rather than counted as zero: a
  -- monitor that reports "no runtime errors" because it could not look is the exact failure this
  -- whole file is built to avoid.
  if (p_web -> 'runtime_errors') ? 'count' then
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis','measured', 'count', (p_web #>> '{runtime_errors,count}')::int,
      'window_minutes', coalesce(p_web #>> '{runtime_errors,window_minutes}','60')));
    if (p_web #>> '{runtime_errors,count}')::int > 0 then
      v_sev  := public.fn_it_severity('degraded', true);
      v_key  := 'website_runtime_errors';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'website_runtime_errors', 'subject', 'website',
        'state','degraded','severity', v_sev,
        'title', (p_web #>> '{runtime_errors,count}') || ' runtime error(s) on the website in the last '
                 || coalesce(p_web #>> '{runtime_errors,window_minutes}','60') || ' minutes',
        'evidence', jsonb_build_object(
          'runtime_errors', p_web -> 'runtime_errors', 'public_surface', true,
          'basis','measured from the Vercel runtime error API this tick'));
    end if;
  else
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis', coalesce(p_web #>> '{runtime_errors,basis}', 'not_reported'),
      'reason', coalesce(p_web #>> '{runtime_errors,reason}',
                'the caller supplied no runtime error count; the website''s runtime errors were NOT checked and are NOT being reported as absent')));
  end if;

  -- Site latency, on the same terms as D6: the site's own history, or an honest refusal.
  -- The samples are the site_ms column of this very table, which is why the tick stores it.
  if v_site_ms is null then
    v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
      'basis','not_timed','detail','the reading carried no home.ms'));
  else
    declare
      s_n int; s_p50 numeric; s_p95 numeric;
    begin
      select count(*)::int,
             (percentile_cont(0.50) within group (order by site_ms))::numeric,
             (percentile_cont(0.95) within group (order by site_ms))::numeric
        into s_n, s_p50, s_p95
      from public.it_watch_tick
      where ran_at > v_now - c_base and ran_at <= v_now - c_win and site_ms is not null and site_status between 200 and 399;
      if coalesce(s_n,0) < 20 then
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','insufficient_history','samples', coalesce(s_n,0), 'samples_needed', 20,
          'current_ms', v_site_ms,
          'detail','the site has no baseline yet; it needs 20 timed ticks, which is about five hours at one tick every fifteen minutes'));
      else
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','measured','baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
          'current_ms', v_site_ms, 'samples', s_n,
          'fires_above_ms', round(greatest(s_p95, s_p50 * 2, 1000))));
        if v_site_ms > s_p95 and v_site_ms >= s_p50 * 2 and v_site_ms >= 1000 then
          v_sev  := public.fn_it_severity('delayed', true);
          v_key  := 'website_slow';
          v_keys := v_keys || v_key;
          v_find := v_find || jsonb_build_object(
            'detector_key', v_key, 'detector', 'website_slow', 'subject', 'website',
            'state','delayed','severity', v_sev,
            'title','the website answered in ' || v_site_ms || 'ms, against its own baseline of '
                    || round(s_p50) || 'ms (p95 ' || round(s_p95) || 'ms)',
            'evidence', jsonb_build_object(
              'current_ms', v_site_ms, 'baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
              'baseline_samples', s_n, 'public_surface', true,
              'rule','current > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
              'basis','measured against the site''s own timed ticks over 7 days'));
        end if;
      end if;
    end;
  end if;
end if;

-- ══ THE VERDICT ═════════════════════════════════════════════════════════════════════════════
select coalesce(
  (select f ->> 'severity' from jsonb_array_elements(v_find) f
    order by case f ->> 'severity' when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end
    limit 1), 'none')
into v_worst;

-- ══ THE LEDGER — open while true, resolved the tick after it stops being true ═══════════════
if p_persist then
  insert into public.it_watch_finding
    (detector_key, detector, subject, state, severity, title, evidence, opened_at, last_seen_at, seen_count, status, resolved_at)
  select f ->> 'detector_key', f ->> 'detector', f ->> 'subject', f ->> 'state', f ->> 'severity',
         f ->> 'title', f -> 'evidence', v_now, v_now, 1, 'open', null
  from jsonb_array_elements(v_find) f
  on conflict (detector_key) do update set
    -- A finding that reappears after being resolved is a NEW occurrence, so opened_at restarts.
    -- One that never closed keeps its original opened_at, which is what makes "how long has this
    -- been broken" answerable.
    opened_at    = case when public.it_watch_finding.status = 'resolved' then excluded.opened_at
                        else public.it_watch_finding.opened_at end,
    seen_count   = case when public.it_watch_finding.status = 'resolved' then 1
                        else public.it_watch_finding.seen_count + 1 end,
    detector     = excluded.detector,
    subject      = excluded.subject,
    state        = excluded.state,
    severity     = excluded.severity,
    title        = excluded.title,
    evidence     = excluded.evidence,
    last_seen_at = excluded.last_seen_at,
    status       = 'open',
    resolved_at  = null;
  get diagnostics v_opened = row_count;

  update public.it_watch_finding
     set status = 'resolved', resolved_at = v_now
   where status = 'open' and not (detector_key = any (v_keys));
  get diagnostics v_resolved = row_count;

  insert into public.it_watch_tick (ran_at, findings, worst, site_ms, site_status, detail)
  values (v_now, jsonb_array_length(v_find), v_worst, v_site_ms, v_site_st,
          jsonb_build_object('findings', v_find, 'notes', v_notes, 'web', p_web));
end if;

return jsonb_build_object(
  'ok', true,
  'at', v_now,
  'window_minutes', 60,
  'baseline_days', 7,
  'worst', v_worst,
  'finding_count', jsonb_array_length(v_find),
  'findings', v_find,
  'notes', v_notes,
  'persisted', p_persist,
  'ledger_upserted', v_opened,
  'ledger_resolved', v_resolved);
end
$fn$;

comment on function public.fn_it_detect(jsonb, boolean) is
  'The IT engineer''s detection engine. Seven detectors over the app, the scheduler, the queues, latency and the website, all deterministic, all delta- or state-based, each reporting its own basis so an idle estate is never mistaken for a healthy one. p_web carries the website reading the caller measured; p_persist=false decides identically and writes nothing.';

-- A newly CREATED SECURITY DEFINER routine is granted EXECUTE to PUBLIC. It reads every failing
-- internal in the estate and executes registry-supplied predicates; nobody on the public surface
-- gets it.
revoke execute on function public.fn_it_detect(jsonb, boolean) from public;
revoke execute on function public.fn_it_severity(text, boolean) from public;
revoke execute on function public.fn_it_run_is_refusal(text, timestamptz, jsonb) from public;

revoke all on public.it_watch_subject from anon, authenticated;
revoke all on public.it_watch_queue   from anon, authenticated;
revoke all on public.it_watch_tick    from anon, authenticated;
revoke all on public.it_watch_finding from anon, authenticated;

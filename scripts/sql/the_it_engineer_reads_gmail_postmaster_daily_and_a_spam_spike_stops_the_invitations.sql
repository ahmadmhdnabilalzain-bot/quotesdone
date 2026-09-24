-- THE IT ENGINEER READS GMAIL POSTMASTER TOOLS ONCE A DAY, AND A SPAM SPIKE STOPS THE INVITATIONS.
-- Seat: it_engineer. 24 Sep 2026.
--
-- WHAT WAS MEASURED (production, read-only, 24 Sep 2026):
--   * quotesdone.com is verified in Google Postmaster Tools and nothing in the estate read it. duty 'sender' (1 day)
--     reads DNS, blocklists and Resend's domain status; fn_invite_same_day_brake (PR #943) reads OUR bounce and
--     complaint webhooks. Neither sees Gmail's own user-reported spam rate or domain reputation, the two numbers
--     Gmail's bulk-sender rules are enforced on (spam rate under 0.3%, aim under 0.1%).
--   * public.it_postmaster_reading did not exist; it_duty_schedule held 14 duties and no 'postmaster'.
--   * app_secrets: google_oauth_client_id and google_oauth_client_secret exist (the YouTube connect's OAuth client);
--     google_postmaster_refresh_token does NOT exist. Until the founder grants the consent, every read is
--     'unavailable' and says so; nothing is fabricated.
--   * The #943 pause (invite_enabled=false, every queued supplier_invite cancelled, it_watch_finding
--     'deliverability:supplier_invite' opened, an agent_runs row) was written inline in the trigger routine, so
--     nothing else could call it.
--
-- WHAT THIS CHANGES
--   1. public.it_postmaster_reading: one row per domain per Dubai read day. basis 'measured' | 'no_data' |
--      'unavailable'. A number Postmaster did not publish is NULL, never 0. RLS on, service-role only.
--   2. public.fn_invite_campaign_pause(source, why, evidence, counts): the #943 pause, MOVED, not rewritten. The
--      same four writes in the same order, the same finding key and the same agent_runs note. fn_invite_same_day_brake
--      is redefined to call it with the arguments it used to write inline, so there is ONE pause and two callers.
--   3. it_duty_schedule 'postmaster' (1 day). resilience_ping's itlater step (NOT pg_cron) takes the reading
--      (supabase/functions/_shared/it_postmaster_readings.ts: v1 trafficStats, deterministic, no model) and
--      public.fn_it_postmaster_record stores it and acts on the verdict the module computed:
--        * spam >= 0.1%, or reputation LOW/BAD  -> finding duty:postmaster:deliverability:<domain> (fn_it_duty_settle);
--        * spam >= 0.3% (Gmail's hard limit), or reputation LOW/BAD -> ALSO fn_invite_campaign_pause, ONCE per
--          Postmaster day: a stats day that already paused never pauses again, so a founder who re-enables after
--          reading it is not overridden by the same stale day (Postmaster publishes 1-2 days late);
--        * no data or unreadable -> an open deliverability finding is CARRIED (held as it stands, neither closed
--          nor re-raised): silence from Postmaster is not evidence the spam rate fell;
--        * unreadable (no consent, token refused, no access) -> one configuration finding, raised once and held.
--   4. fn_it_daily_line (canonical: the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql) carries
--      the newest reading as 'gmail_postmaster' and its sentence at the end of the CEO line, e.g.
--      "Gmail Postmaster quotesdone.com 2026-09-22: spam 0.05% (0.02%-0.09%), reputation HIGH, SPF 100.0%, ..."
--      or "...: no data (volume below Postmaster threshold or not yet published)". Everything else is unchanged.
--
-- WHAT THIS DOES NOT CHANGE: the brake's thresholds and trigger (z80_invite_same_day_brake), the ramp, the sender
-- duty, the founder digest (a Postmaster finding reaches him only by the rules of the_founder_hears_from_it_once_a_day),
-- and resuming: invite_enabled goes back to true only by hand, after the finding is read, as #943 ruled.
-- NOT READ: v2 of the API (preferred in Google's discovery directory since it exists, but it has no domain
-- reputation metric); IP reputation, feedback loops and delivery errors (v1 publishes them; nothing here acts on them).
--
-- Prevented by: scripts/checks/the_it_engineer_reads_gmail_postmaster_daily.test.mjs,
--               supabase/functions/_shared/it_postmaster_readings.test.ts
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations.sql --apply --ddl
--   then deploy resilience_ping.

-- ── 1. THE READINGS ─────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_postmaster_reading (
  domain      text not null,
  read_on     date not null,                 -- the Dubai day the IT engineer read it
  basis       text not null check (basis in ('measured', 'no_data', 'unavailable')),
  stats_day   date,                          -- the day the numbers belong to (Postmaster's, 1-2 days behind)
  spam_ratio  numeric check (spam_ratio between 0 and 1),
  spam_lower  numeric check (spam_lower between 0 and 1),
  spam_upper  numeric check (spam_upper between 0 and 1),
  reputation  text check (reputation in ('HIGH', 'MEDIUM', 'LOW', 'BAD')),
  spf_ratio   numeric check (spf_ratio between 0 and 1),
  dkim_ratio  numeric check (dkim_ratio between 0 and 1),
  dmarc_ratio numeric check (dmarc_ratio between 0 and 1),
  reason      text,
  verdict     jsonb not null default '{}'::jsonb,
  line        text not null,                 -- the sentence the IT daily line carries
  paused_at   timestamptz,                   -- set when THIS reading paused the invitations
  read_at     timestamptz not null default now(),
  primary key (domain, read_on),
  -- no_data and unavailable carry no numbers: a zero there would read as a clean day
  constraint it_postmaster_reading_no_numbers_without_data check (
    basis = 'measured' or (spam_ratio is null and reputation is null and spf_ratio is null and dkim_ratio is null and dmarc_ratio is null))
);
alter table public.it_postmaster_reading enable row level security;
drop policy if exists it_postmaster_reading_service_role_only on public.it_postmaster_reading;
create policy it_postmaster_reading_service_role_only on public.it_postmaster_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.it_postmaster_reading from anon, authenticated;

-- ── 2. THE ONE PAUSE (moved out of fn_invite_same_day_brake, PR #943) ───────────────────────────────
create or replace function public.fn_invite_campaign_pause(p_source text, p_why text, p_evidence jsonb, p_counts jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cancelled int;
begin
  if coalesce(btrim(p_source), '') = '' or coalesce(btrim(p_why), '') = '' then
    raise exception 'fn_invite_campaign_pause(source, why, evidence, counts): a source and a reason are required';
  end if;
  update app_secrets set value = 'false' where key = 'invite_enabled';
  update notifications set status = 'cancelled'
   where type = 'supplier_invite' and status = 'queued';
  get diagnostics v_cancelled = row_count;

  insert into it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
  values ('deliverability:supplier_invite', 'deliverability', 'supplier_invite', 'paused', 'high',
          'Supplier invitations auto-paused: ' || p_why,
          coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled, 'paused_by', p_source,
                             'resume', 'set app_secrets.invite_enabled=true after reading the bounces/complaints'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values (p_source, 'error', coalesce(p_counts, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled),
          'PAUSED: ' || p_why || '; invite_enabled=false, ' || v_cancelled || ' queued invitation(s) cancelled, it_engineer finding opened.', now());
  return jsonb_build_object('paused', true, 'cancelled_queued', v_cancelled, 'source', p_source);
end
$fn$;
revoke execute on function public.fn_invite_campaign_pause(text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_invite_campaign_pause(text, text, jsonb, jsonb) to service_role;

-- The brake keeps its thresholds and its decision exactly; only the pause it used to write inline is now the call.
create or replace function public.fn_invite_same_day_brake()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_br_max numeric := coalesce((c->>'same_day_pause_bounce_rate')::numeric, 0.05);
  v_b_min  int     := coalesce((c->>'same_day_pause_min_bounces')::int, 3);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;

  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_sent, v_b, v_c
    from leads
   where invited_at is not null and (invited_at at time zone 'Asia/Dubai')::date = v_day;

  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
  elsif v_b >= v_b_min and v_b::numeric / greatest(v_sent, 1) >= v_br_max then
    v_why := v_b || ' bounce(s) on ' || v_sent || ' invitation(s) today (' || round(v_b * 100.0 / greatest(v_sent, 1), 1) || '%)';
  else
    return null;
  end if;

  perform public.fn_invite_campaign_pause('invite_same_day_brake', v_why,
    jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c),
    jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c));
  return null;
end
$fn$;
revoke execute on function public.fn_invite_same_day_brake() from public, anon, authenticated;

-- ── 3. THE DUTY: ONCE A DAY, ON THE resilience_ping HEARTBEAT ───────────────────────────────────────
insert into public.it_duty_schedule (duty, every, note, owner_seat) values
  ('postmaster', interval '1 day',
   'Gmail Postmaster Tools v1 trafficStats for quotesdone.com: spam rate, reputation, SPF/DKIM/DMARC (fn_it_postmaster_record)', 'it_engineer')
on conflict (duty) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

create or replace function public.fn_it_postmaster_record(p_r jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_dom   text := coalesce(nullif(btrim(p_r->>'domain'), ''), 'quotesdone.com');
  v_basis text := p_r->>'basis';
  v_on    date := (now() at time zone 'Asia/Dubai')::date;
  v_stats date := nullif(p_r->>'stats_day', '')::date;
  v_items jsonb := '[]'::jsonb;
  v_pause jsonb := null;
  v_res   jsonb;
  f record;
begin
  if v_basis is null or v_basis not in ('measured', 'no_data', 'unavailable') or coalesce(btrim(p_r->>'line'), '') = '' then
    raise exception 'fn_it_postmaster_record: a reading needs basis measured|no_data|unavailable and a line (%)', left(p_r::text, 200);
  end if;

  insert into public.it_postmaster_reading as t (domain, read_on, basis, stats_day, spam_ratio, spam_lower, spam_upper, reputation,
                                                spf_ratio, dkim_ratio, dmarc_ratio, reason, verdict, line)
  values (v_dom, v_on, v_basis, v_stats, (p_r->>'spam_ratio')::numeric, (p_r->>'spam_lower')::numeric, (p_r->>'spam_upper')::numeric,
          p_r->>'reputation', (p_r->>'spf')::numeric, (p_r->>'dkim')::numeric, (p_r->>'dmarc')::numeric,
          p_r->>'reason', coalesce(p_r->'verdict', '{}'::jsonb), p_r->>'line')
  on conflict (domain, read_on) do update
     set basis = excluded.basis, stats_day = excluded.stats_day, spam_ratio = excluded.spam_ratio, spam_lower = excluded.spam_lower,
         spam_upper = excluded.spam_upper, reputation = excluded.reputation, spf_ratio = excluded.spf_ratio,
         dkim_ratio = excluded.dkim_ratio, dmarc_ratio = excluded.dmarc_ratio, reason = excluded.reason,
         verdict = excluded.verdict, line = excluded.line, read_at = now();

  if v_basis = 'measured' and coalesce((p_r->'verdict'->>'finding')::boolean, false) then
    v_items := v_items || jsonb_build_object('item', 'deliverability:' || v_dom, 'owner_seat', 'it_engineer', 'subject', v_dom,
      'blast', 'customer_facing',
      'title', 'Gmail Postmaster ' || v_dom || ' ' || v_stats || ': '
               || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(p_r->'verdict'->'reasons') x), 'over threshold'),
      'evidence', p_r - 'line');
  elsif v_basis <> 'measured' then
    -- Postmaster silent or unreadable: an open deliverability finding is held as it stands, not closed.
    for f in select issue_key, title from public.it_engineer_finding
              where closed_at is null and issue_key = 'duty:postmaster:deliverability:' || v_dom loop
      v_items := v_items || jsonb_build_object('item', 'deliverability:' || v_dom, 'title', f.title, 'carried', true,
                                               'owner_seat', 'it_engineer', 'subject', v_dom);
    end loop;
  end if;
  if v_basis = 'unavailable' then
    v_items := v_items || jsonb_build_object('item', 'unreadable:' || v_dom, 'config', true, 'owner_seat', 'it_engineer',
      'blast', 'monitor', 'subject', v_dom,
      'title', 'Gmail Postmaster could not be read for ' || v_dom || ': ' || coalesce(p_r->>'reason', '?'), 'evidence', p_r - 'line');
  end if;

  -- The pause, once per Postmaster day. A stats day that already paused the invitations never pauses them again.
  if v_basis = 'measured' and coalesce((p_r->'verdict'->>'pause')::boolean, false) and v_stats is not null
     and not exists (select 1 from public.it_postmaster_reading
                      where domain = v_dom and stats_day = v_stats and paused_at is not null) then
    v_pause := public.fn_invite_campaign_pause('it_engineer_postmaster',
      coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(p_r->'verdict'->'reasons') x), 'Gmail Postmaster over threshold')
        || ' (Postmaster day ' || v_stats || ')',
      jsonb_build_object('source', 'gmail_postmaster', 'domain', v_dom, 'stats_day', v_stats, 'spam_ratio', p_r->'spam_ratio',
                         'spam_lower', p_r->'spam_lower', 'spam_upper', p_r->'spam_upper', 'reputation', p_r->'reputation'),
      jsonb_build_object('stats_day', v_stats, 'spam_ratio', p_r->'spam_ratio', 'reputation', p_r->'reputation'));
    update public.it_postmaster_reading set paused_at = now() where domain = v_dom and read_on = v_on;
  end if;

  v_res := public.fn_it_duty_settle('postmaster', v_items) || jsonb_build_object('basis', v_basis, 'paused', v_pause is not null);
  perform public.fn_it_duty_ran('postmaster', v_res);
  return v_res;
end $fn$;
revoke execute on function public.fn_it_postmaster_record(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_postmaster_record(jsonb) to service_role;

-- ── 4. THE IT DAILY LINE CARRIES THE NEWEST POSTMASTER READING ──────────────────────────────────────
-- Body as in the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql, plus 'gmail_postmaster' and its sentence.
create or replace function public.fn_it_daily_line()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_day   text := to_char(v_local, 'YYYY-MM-DD');
  v_since timestamptz := (date_trunc('day', v_local) at time zone 'Asia/Dubai');
  v_ev jsonb; v_rep jsonb; n_done int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'it_engineer' and idempotency_key like 'it_daily:%' and status = 'accepted';
  get diagnostics n_done = row_count;

  if v_local::time < time '19:00'
     or exists (select 1 from public.support_ceo_report where idempotency_key = 'it_daily:' || v_day) then
    return jsonb_build_object('filed', false, 'completed_after_receipt', n_done);
  end if;

  select jsonb_build_object(
    'day', v_day,
    'open_findings', (select count(*) from public.it_engineer_finding where closed_at is null),
    'open_findings_actionable', (select count(*) from public.it_engineer_finding
                                  where closed_at is null and public.fn_it_engineer_severity(blast, affected, started_at) <> 'warn'),
    'open_loops', (select count(*) from public.agent_actions
                    where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')),
    'open_loops_by_seat', coalesce((select jsonb_object_agg(agent, n) from (
                      select agent, count(*) n from public.agent_actions
                       where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')
                       group by agent) x), '{}'::jsonb),
    'loops_closed_today', (select count(*) from public.agent_actions
                            where kind = 'handoff' and detail->>'from' = 'it_engineer' and status = 'done' and decided_at >= v_since),
    'escalated_today', (select count(*) from public.support_ceo_report
                         where source_agent = 'it_engineer' and idempotency_key like 'it_loop:%' and created_at >= v_since),
    'founder_emails_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'email' and created_at >= v_since),
    'repeats_folded_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'deduped' and created_at >= v_since),
    -- Duty 17: failure classes the company fixed on its own versus new ones.
    'auto_fixed_today', (select count(*) from public.agent_actions a
                          where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.decided_at >= v_since
                            and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)),
    'playbook_runs_today', (select count(*) from public.agent_runs
                             where agent = 'it_engineer' and counts->>'job' = 'playbook' and started_at >= v_since),
    'new_bugs_today', (select count(*) from public.it_incident where created_at >= v_since),
    'awaiting_learning', (select count(*) from public.agent_actions
                           where kind = 'handoff' and detail->>'type' = 'it.finding' and status <> 'done' and detail ? 'awaiting_learning'),
    -- Instruction 979: what the integration watch fixed itself today (recorded here, never mailed), and what is down.
    'integrations_fixed_today', coalesce((select jsonb_agg(distinct counts->'fix'->>'integration') from public.agent_runs
                           where agent = 'it_engineer' and counts->>'job' = 'integration_self_fix' and started_at >= v_since), '[]'::jsonb),
    'integrations_failing', coalesce((select jsonb_agg(regexp_replace(issue_key, '^duty:', '') order by issue_key) from public.it_engineer_finding
                           where closed_at is null and issue_key like 'duty:integration%'), '[]'::jsonb),
    'integrations_waiting_on_external', coalesce((select jsonb_agg(jsonb_build_object('integration', integration, 'party', external_party,
                           'ticket', ticket_ref, 'opened_on', opened_on, 'last_reply_at', last_reply_at,
                           'reply_needs_founder', reply_needs_founder, 'last_checked_at', last_checked_at) order by integration)
                           from public.it_integration_external_cause where closed_at is null), '[]'::jsonb),
    -- The newest Gmail Postmaster reading (duty 'postmaster'); null until the first read. Its numbers are Postmaster's
    -- day (stats_day), 1-2 days behind read_on; a number Postmaster did not publish is null, never 0.
    'gmail_postmaster', (select jsonb_build_object('domain', p.domain, 'read_on', p.read_on, 'basis', p.basis, 'stats_day', p.stats_day,
                           'spam_ratio', p.spam_ratio, 'spam_lower', p.spam_lower, 'spam_upper', p.spam_upper, 'reputation', p.reputation,
                           'spf_ratio', p.spf_ratio, 'dkim_ratio', p.dkim_ratio, 'dmarc_ratio', p.dmarc_ratio, 'reason', p.reason,
                           'paused_at', p.paused_at, 'line', p.line)
                           from public.it_postmaster_reading p order by p.read_on desc, p.read_at desc limit 1))
  into v_ev;

  v_rep := public.fn_support_report_to_ceo('it_daily:' || v_day, 'routine',
    'IT engineer daily line ' || v_day || ': ' || (v_ev->>'open_loops') || ' open loop(s), '
      || (v_ev->>'loops_closed_today') || ' closed today, ' || (v_ev->>'founder_emails_today') || ' founder email(s), '
      || (v_ev->>'repeats_folded_today') || ' repeat(s) folded, '
      || jsonb_array_length(v_ev->'integrations_fixed_today') || ' integration(s) fixed without anyone, '
      || jsonb_array_length(v_ev->'integrations_failing') || ' integration(s) down ('
      || jsonb_array_length(v_ev->'integrations_waiting_on_external') || ' waiting on a provider''s ticket). '
      || coalesce(v_ev->'gmail_postmaster'->>'line', 'Gmail Postmaster: not read yet (duty postmaster has not run)'),
    v_ev, '[]'::jsonb,
    'Acknowledge the day''s IT position. Nothing else is requested; anything that needs a decision reaches you as its own report.',
    p_review_in => interval '3 hours', p_source_agent => 'it_engineer');
  if not coalesce((v_rep->>'ok')::boolean, false) then
    raise exception 'fn_it_daily_line: the CEO report was refused: %', v_rep->>'reason';
  end if;
  return jsonb_build_object('filed', true, 'report', v_rep, 'completed_after_receipt', n_done);
end $fn$;

select case when to_regclass('public.it_postmaster_reading') is not null
             and to_regprocedure('public.fn_it_postmaster_record(jsonb)') is not null
             and to_regprocedure('public.fn_invite_campaign_pause(text,text,jsonb,jsonb)') is not null
             and exists (select 1 from public.it_duty_schedule where duty = 'postmaster')
             and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'it_postmaster_reading')
             and not has_function_privilege('anon', 'public.fn_invite_campaign_pause(text,text,jsonb,jsonb)', 'execute')
             and not has_function_privilege('anon', 'public.fn_it_postmaster_record(jsonb)', 'execute')
            then 'PROBE OK' else 'PROBE FAILED: the Postmaster table, its routines, its policy, its revokes or its schedule row is missing' end as verdict;

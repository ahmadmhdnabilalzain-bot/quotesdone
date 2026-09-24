-- THE IT ENGINEER WATCHES EVERY EXTERNAL INTEGRATION AND FIXES WHAT IT CAN.
--
-- Assigned: it_engineer. Founder instruction 979, 24 Sep 2026: "The IT engineer should have been notified when
-- Facebook disconnected from Postiz, and about any similar issue." Widened the same day: every external API
-- and integration the company depends on, one data-driven registry, the fix tried first, the founder told only
-- when the company could not fix it, and a fixed one recorded in the IT daily line only.
--
-- MEASURED BEFORE WRITING (24 Sep 2026, production and repository):
--   * public.marketing_connection_check held postiz.channel.<ch> ONCE A DUBAI DAY and nothing read it into an
--     it_engineer finding: a channel Postiz marked refreshNeeded was silent until a post skipped it.
--   * Provider credentials (Stripe live/test, Resend, Twilio, Dropbox, GitHub) were probed HOURLY by
--     it_duty_readings.ts providers() and filed as duty:credential; OpenRouter, Twilio Verify, CloudConvert,
--     VirusTotal, Vercel's token and Supabase itself by nothing. 0 duty:credential findings open today.
--   * The inventory, from code: 56 hosts and 99 secret names under supabase/functions and src. All of them
--     are now named in supabase/functions/_shared/integration_registry.json.
--
-- WHAT THIS CHANGES
--   1. fn_it_integration_settle(duty, items, fixed): the one door both producers use. duty 'integration' is
--      resilience_ping's itintegrations step (every entry of the registry the IT seat may probe); duty
--      'integration_social' is the marketing seat's beat (Postiz channels, YouTube's token, Meta), because only
--      that seat reads those credentials (rule 641). It files one finding per integration through
--      fn_it_duty_settle (issue key duty:<duty>:<integration>, idempotent, closed by that exact key when the
--      producer stops emitting it), drops a CARRIED item whose finding is not open (a reading nobody took must
--      not reopen anything), records each self-fix for the IT daily line, and mails the founder ONCE per
--      open finding, only after it has been seen on two beats (about 15 minutes: a blip is not a page), only
--      when the registry does not say notify false, through fn_notify_founder kind integration_reauth_needed.
--      The mail names the integration, what broke, what was tried, and the action and link he needs; a YouTube
--      or LinkedIn sign-in carries a freshly minted one-time connect link.
--   2. founder_mail_policy kind integration_reauth_needed (it_engineer, email only). This widens the IT
--      immediate class of instruction 642 by exactly one kind, on instruction 979: a connection only he can
--      restore is a decision only he can make, and a day's wait costs the posts it pauses.
--   3. it_founder_decision_class 'duty:integration%': the daily digest carries it as a DECISION too.
--   4. fn_marketing_post_refusal: a scheduled post whose channel has an open integration_social finding (or
--      Postiz itself is refused) is PAUSED: the scheduler records the reason and leaves it scheduled; it goes
--      out on the first beat after the channel is back. Posts are held whole, so one dead channel holds the
--      post's other channels too: publishing a post half-way is the failure it replaces.
--   5. fn_it_daily_line carries integrations_fixed_today and integrations_failing.
--   6. resilience_step itintegrations, every 15 minutes.
--
-- WHAT THIS DOES NOT CHANGE: duty:payment still owns Stripe's webhook EVENT wiring (the itintegrations stripe
-- probe only re-enables an endpoint Stripe disabled, and files a finding only when that fails); duty:credential
-- findings are no longer produced (the providers reading is gone) and fn_it_duties holds them as they stand, 0
-- open today. The live Postiz connections are read, never written.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql --apply --ddl

-- ── 2. THE MAIL CLASS, AND 3. THE DIGEST CLASS ────────────────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at) values
  ('integration_reauth_needed', true,
   'Founder instruction 979 (24 Sep 2026): an external integration the company could not fix itself (a disconnected Postiz channel, a refused key, a sender offline). Sent once per failure, email only, naming the integration, what broke, what was tried and the link he needs (the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql).',
   'it_engineer', now())
on conflict (kind) do update set allowed_to_email = true, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

insert into public.it_founder_decision_class (issue_key_like, to_founder, why) values
  ('duty:integration%', true, 'an external connection is down that only its account holder can restore; the link is in the line')
on conflict (issue_key_like) do update set to_founder = true, why = excluded.why;

-- ── 1. THE ONE DOOR ────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_integration_settle(p_duty text, p_items jsonb, p_fixed jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; f public.it_engineer_finding;
  v_stub boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_link text; v_detail text; v_dedupe text; v_note jsonb; n_mail int := 0; n_fixed int := 0;
  v_mailed jsonb := '[]'::jsonb;
begin
  if p_duty not in ('integration', 'integration_social') then
    raise exception 'fn_it_integration_settle: duty must be integration or integration_social, not %', p_duty;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_typeof(coalesce(p_fixed, '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_it_integration_settle(duty, items[], fixed[]): items and fixed must be arrays';
  end if;
  -- A carried item holds an OPEN finding; one whose finding is closed is dropped, never reopened.
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce((x->>'carried')::boolean, false) and not exists (select 1 from public.it_engineer_finding
         where issue_key = 'duty:' || p_duty || ':' || (x->>'item') and closed_at is null) then
      continue;
    end if;
    v_items := v_items || x;
  end loop;
  v_res := public.fn_it_duty_settle(p_duty, v_items);

  -- What the company fixed itself: the IT daily line, never the founder.
  for x in select e from jsonb_array_elements(coalesce(p_fixed, '[]'::jsonb)) e loop
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'integration_self_fix', 'duty', p_duty, 'fix', x),
            left('fixed ' || coalesce(x->>'integration', '?') || ' itself: ' || coalesce(x->>'what_broke', ''), 500));
    n_fixed := n_fixed + 1;
  end loop;

  -- What it could not fix: the founder, once per open finding, after two beats.
  for f in select * from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and seen_count >= 2
              and coalesce(evidence->>'notify', 'true') <> 'false' loop
    -- ONCE PER OPEN FINDING: the key is the finding and the moment it (re)opened. The finding's evidence is
    -- rewritten on every beat, so the record of having told him is founder_alerts, which fn_notify_founder writes.
    v_dedupe := 'integration:' || f.issue_key || ':' || to_char(f.started_at, 'YYYYMMDDHH24MI');
    continue when exists (select 1 from public.founder_alerts where dedupe_key = v_dedupe);
    v_link := coalesce(f.evidence->>'reconnect_url', '');
    if f.evidence->>'reconnect_link' in ('youtube', 'linkedin') and coalesce(f.evidence->>'connect_base', '') <> '' then
      v_link := (f.evidence->>'connect_base') || public.fn_marketing_social_connect_link(f.evidence->>'reconnect_link')
                || ' (one-time link, valid 24 hours)';
    end if;
    v_detail := 'The IT engineer found an integration down that the company could not fix itself.' || E'\n\n'
      || 'Integration: ' || coalesce(f.evidence->>'integration', f.evidence->>'channel', regexp_replace(f.issue_key, '^duty:[a-z_]+:', '')) || E'\n'
      || 'What broke: ' || f.title || E'\n'
      || 'What was tried: ' || coalesce((select string_agg(t, '; ') from jsonb_array_elements_text(f.evidence->'tried') t),
                                        'nothing the company can do: only the account holder can sign in again') || E'\n'
      || 'What you need to do: ' || coalesce(f.evidence->>'action', 'sign in again at the link') || E'\n'
      || 'Link: ' || coalesce(nullif(v_link, ''), 'none recorded') || E'\n\n'
      || 'Down since ' || to_char(f.started_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai. The IT engineer re-checks every 15 minutes and closes it the moment it answers again (reference ' || f.issue_key || ').';
    if v_stub then
      v_note := jsonb_build_object('stubbed', true);
    else
      v_note := public.fn_notify_founder(p_event => 'Reconnect needed: ' || left(regexp_replace(f.issue_key, '^duty:[a-z_]+:', ''), 60),
        p_detail => v_detail, p_level => 'normal', p_kind => 'integration_reauth_needed', p_dedupe_key => v_dedupe,
        p_owner_agent => 'it_engineer');
    end if;
    v_mailed := v_mailed || jsonb_build_object('key', f.issue_key, 'detail', v_detail, 'notice', v_note);
    n_mail := n_mail + 1;
  end loop;
  return v_res || jsonb_build_object('fixed', n_fixed, 'founder_mailed', n_mail, 'mailed', v_mailed, 'stubbed', v_stub);
end $fn$;
revoke execute on function public.fn_it_integration_settle(text, jsonb, jsonb) from public, anon, authenticated;

-- ── 4. A DEAD CHANNEL PAUSES ITS POSTS ────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_post_refusal(p_post_id bigint)
returns text
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
    (select 'paused: ' || string_agg(regexp_replace(f.issue_key, '^duty:integration_social:postiz:', ''), ', ' order by f.issue_key)
            || ' is down in Postiz (it_engineer finding open); the post goes out on the first beat after it is reconnected'
       from public.it_engineer_finding f
      where f.closed_at is null
        and (f.issue_key = 'duty:integration_social:postiz:api'
             or f.issue_key = any (select 'duty:integration_social:postiz:' || c from unnest(p.channels) c))),
    public.fn_marketing_post_publish_refusal(p))
  from public.marketing_post p where p.id = p_post_id
$fn$;

-- ── 5. THE IT DAILY LINE CARRIES WHAT WAS FIXED AND WHAT IS DOWN ──────────────────────────────────
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
                           where closed_at is null and issue_key like 'duty:integration%'), '[]'::jsonb))
  into v_ev;

  v_rep := public.fn_support_report_to_ceo('it_daily:' || v_day, 'routine',
    'IT engineer daily line ' || v_day || ': ' || (v_ev->>'open_loops') || ' open loop(s), '
      || (v_ev->>'loops_closed_today') || ' closed today, ' || (v_ev->>'founder_emails_today') || ' founder email(s), '
      || (v_ev->>'repeats_folded_today') || ' repeat(s) folded, '
      || jsonb_array_length(v_ev->'integrations_fixed_today') || ' integration(s) fixed without anyone, '
      || jsonb_array_length(v_ev->'integrations_failing') || ' integration(s) down',
    v_ev, '[]'::jsonb,
    'Acknowledge the day''s IT position. Nothing else is requested; anything that needs a decision reaches you as its own report.',
    p_review_in => interval '3 hours', p_source_agent => 'it_engineer');
  if not coalesce((v_rep->>'ok')::boolean, false) then
    raise exception 'fn_it_daily_line: the CEO report was refused: %', v_rep->>'reason';
  end if;
  return jsonb_build_object('filed', true, 'report', v_rep, 'completed_after_receipt', n_done);
end $fn$;

-- ── 6. THE CADENCE ─────────────────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('itintegrations', interval '15 minutes', 6000, 'plan', 0,
   'it_engineer: every entry of _shared/integration_registry.json that is due, probed, retried once, fixed where the company can (instruction 979)', 'it_engineer')
on conflict (step) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;

-- ── THE VERDICT: the routine exists, is closed to callers, and the mail class is live ──────────────
select case
  when not exists (select 1 from pg_proc where proname = 'fn_it_integration_settle') then 'PROBE FAILED: fn_it_integration_settle missing'
  when has_function_privilege('anon', 'public.fn_it_integration_settle(text, jsonb, jsonb)', 'execute') then 'PROBE FAILED: anon may execute fn_it_integration_settle'
  when not exists (select 1 from public.founder_mail_policy where kind = 'integration_reauth_needed' and allowed_to_email) then 'PROBE FAILED: mail class missing'
  when not exists (select 1 from public.resilience_step where step = 'itintegrations') then 'PROBE FAILED: step not scheduled'
  else 'PROBE OK' end as verdict;

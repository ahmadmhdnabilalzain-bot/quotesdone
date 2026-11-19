-- A LOAD-TEST REPLY IS NEVER SCORED AS A REAL ONE (customer_support, 19 Nov 2026).
--
-- MEASURED 19 Nov 2026 (SELECT on production). customer_support_reply_quality_week for week_ending 18 Nov 2026 (window
-- 10 Nov 20:08 to 17 Nov 20:08 UTC) reads 1,957 scored widget replies, readability 100, tone 100, scored share 0.998 of
-- 1,961 sent. Every one of them was the 11 Nov load run (scripts/load/chat_load_run.mjs, founder ruling 1622):
--   * assistant_logs in that window: 1,957 answered rows, every one user_agent 'node' (the driver named nothing), reply the
--     load stub's canned text (_shared/load_stub.ts CANNED_TEXT / CANNED_TEXT_AR), conv_id 'v-<uuid>'; plus 14 unanswered
--     rows of the same run. 0 rows from anyone else. e2e_run_tag was NULL on all of them, and on every assistant_logs row ever.
--   * support_reply_readability in that window: 1,957 rows, all widget / reasoned / 'brief', all untagged, falling in the
--     same six hours (11 Nov 01:00-06:59 UTC) with the same count per hour as the canned replies; each one is followed by a
--     canned assistant_logs row (median 0.02 s later; all 1,957 have one within 60 s).
-- WHY THE TAG WAS LOST. fn_ai_cost_log_e2e_run_tag (the BEFORE INSERT stamp on assistant_logs, support_reply_readability,
-- sales_decision_log and ai_cost_log) keeps a tag only while fn_e2e_run_tag_open(tag) is true, and that requires
-- models_allowed. A load window is models_allowed = FALSE by design (load_stub.ts rule 3), and so is every e2e harness window
-- of 17-18 Nov (scripts/e2e/run.mjs, rehearsal_window 3615-3619): the stamp dropped the tag of every row they wrote, so the
-- teardown that deletes by tag found nothing. The load teardown's own delete by conversation id matched bare ids against
-- 'v-<id>' keys and deleted nothing either (fixed in chat_load_run.mjs, same PR).
--
-- THE FIX.
--   1. The stamp keeps a tag while that run's rehearsal_window is OPEN (unended, unexpired), whether or not the window lets
--      models be called. Whether a request may SPEND is fn_e2e_run_tag_open's question, unchanged and still asked by the spend
--      gates; whose row this is, is not. The tag is still read only from a service-role request's header or the probe's
--      app.e2e_run_tag (fn_e2e_run_tag_current, unchanged), so a public caller still cannot tag anything.
--      site_assistant also names its load tag on the assistant_logs row itself (same PR).
--   2. The weekly row reads its numbers from fn_customer_support_reply_quality_metrics(from, to, fixture), which leaves out
--      test traffic: a tagged row (score or chat turn), a chat reply that is the load stub's canned text, and an untagged
--      score logged in a minute (or the minute before) that holds a canned reply: the backstop for any score written before
--      this file, or by a road whose tag is lost again. The cost of the backstop: a real reply scored in the same minute as a
--      load turn is not scored (it is still counted as sent). How many were left out is in the metrics (excluded_test_traffic).
--      fn_customer_support_reply_quality_below(metrics) is the target rule, unchanged, so the recompute applies the same one.
--   3. The 18 Nov row is recomputed below over its own stored window.
-- Bodies: the live definitions of 19 Nov 2026 (pg_get_functiondef), with only the changes above.
--
-- Seat: customer_support (the weekly row). The stamp is shared with it_engineer's sandbox runs; its change is item 1 only.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/a_load_test_reply_is_never_scored_as_a_real_one.sql --apply --ddl
--   then append this file to the END of scripts/sql/MANIFEST.txt and delete scripts/sql/pending/a_load_test_reply_is_never_scored_as_a_real_one.txt.
-- Rollback: re-run fn_ai_cost_log_e2e_run_tag from a_harness_chat_turn_carries_its_run_tag_and_files_no_gap_or_task.sql and
--   fn_customer_support_reply_quality_week from customer_support_scores_its_replies_every_week_and_counts_what_went_unscored.sql;
--   drop the two new routines. The 18 Nov row's previous metrics are kept on it under previous_metrics.
-- prevented by: scripts/checks/a_load_test_reply_is_never_scored_as_a_real_one.test.mjs (and the probe at the end of this file)
set local lock_timeout = '5s';

-- 1. THE STAMP KEEPS A TAG WHILE ITS WINDOW IS OPEN ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_ai_cost_log_e2e_run_tag()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_tag text;
begin
  v_tag := coalesce(new.e2e_run_tag, public.fn_e2e_run_tag_current());
  -- an OPEN window of that run, whether or not it allows models (a load window never does): 19 Nov 2026
  if v_tag is not null and not (v_tag ~ '^[a-z0-9]{4,16}$' and exists (
       select 1 from public.rehearsal_window w
        where w.run_tag = 'qd_run:' || v_tag and w.ended_at is null and w.expires_at > now())) then
    v_tag := null;
  end if;
  new.e2e_run_tag := v_tag;
  return new;
exception when others then
  new.e2e_run_tag := null;   -- the cost record is never lost to a malformed header
  return new;
end $function$;
revoke execute on function public.fn_ai_cost_log_e2e_run_tag() from public, anon, authenticated;

-- 2. THE WEEK'S NUMBERS, WITHOUT TEST TRAFFIC ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_support_reply_quality_metrics(p_from timestamptz, p_to timestamptz, p_fx boolean)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_scored jsonb; v_sent jsonb; v_ex jsonb; v_n_scored int; v_n_sent int; v_cov numeric;
begin
  -- lm: every minute that holds a load-stub reply (_shared/load_stub.ts CANNED_TEXT, CANNED_TEXT_AR: no real reply starts with
  -- these words), and the minute before it, since a score is logged just BEFORE its reply (median 0.02 s on 11 Nov);
  -- sc: the scores of the window that are not test traffic
  with lm as (
    select distinct date_trunc('minute', g.created_at) + d.o as m
      from public.assistant_logs g cross join (values (interval '0'), (interval '-1 minute')) d(o)
     where g.created_at >= p_from and g.created_at < p_to + interval '1 minute'
       and (g.reply like 'Thank you, this is a sandbox load-test reply%' or g.reply like 'شكرًا لك، هذا رد تجريبي من اختبار التحميل%')),
  sc as (
    select r.channel, r.lang, r.score, r.tone from public.support_reply_readability r
     where r.created_at >= p_from and r.created_at < p_to and r.demo = p_fx and r.e2e_run_tag is null
       and not exists (select 1 from lm where lm.m = date_trunc('minute', r.created_at)))
  select jsonb_build_object('replies', (select count(*) from sc), 'readability_avg', (select round(avg(score), 1) from sc),
           'tone_avg', (select round(avg(tone), 1) from sc),
           'by_channel', (select coalesce(jsonb_object_agg(c.channel, jsonb_build_object('replies', c.n, 'readability_avg', c.s, 'tone_avg', c.t)), '{}')
                            from (select channel, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from sc group by channel) c),
           'by_language', (select coalesce(jsonb_object_agg(l.lang, jsonb_build_object('replies', l.n, 'readability_avg', l.s, 'tone_avg', l.t)), '{}')
                             from (select lang, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from sc group by lang) l))
    into v_scored;

  select jsonb_build_object(
           'chat', (select count(*) from public.assistant_logs g where g.created_at >= p_from and g.created_at < p_to and g.answered
                       and (coalesce(g.message, '') like 'ZZ DEMO%') = p_fx and g.e2e_run_tag is null
                       and not (coalesce(g.reply, '') like 'Thank you, this is a sandbox load-test reply%'
                                or coalesce(g.reply, '') like 'شكرًا لك، هذا رد تجريبي من اختبار التحميل%')),
           'whatsapp', (select count(*) from public.wa_messages w where w.created_at >= p_from and w.created_at < p_to and w.reply is not null and coalesce(w.sent, false)
                           and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = p_fx),
           'email', (select count(*) from public.inbound_messages m where m.replied_at >= p_from and m.replied_at < p_to
                        and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, p_fx)))
    into v_sent;

  select jsonb_build_object(
           'scored', (select count(*) from public.support_reply_readability r where r.created_at >= p_from and r.created_at < p_to and r.demo = p_fx)
                       - coalesce((v_scored->>'replies')::int, 0),
           'chat', (select count(*) from public.assistant_logs g where g.created_at >= p_from and g.created_at < p_to and g.answered
                       and (coalesce(g.message, '') like 'ZZ DEMO%') = p_fx)
                     - (v_sent->>'chat')::int)
    into v_ex;

  v_n_scored := coalesce((v_scored->>'replies')::int, 0);
  v_n_sent := (v_sent->>'chat')::int + (v_sent->>'whatsapp')::int + (v_sent->>'email')::int;
  v_cov := case when v_n_sent > 0 then round(least(1, v_n_scored::numeric / v_n_sent), 3) end;
  return v_scored || jsonb_build_object('from', p_from, 'to', p_to, 'sent', v_sent, 'sent_total', v_n_sent, 'scored_share', v_cov,
                                        'excluded_test_traffic', v_ex);
end $fn$;
revoke execute on function public.fn_customer_support_reply_quality_metrics(timestamptz, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.fn_customer_support_reply_quality_metrics(timestamptz, timestamptz, boolean) to service_role;

-- the targets, exactly as the weekly routine applied them since 19 Oct 2026
create or replace function public.fn_customer_support_reply_quality_below(p_m jsonb)
returns text[] language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_below text[] := '{}'; v_n_scored int := coalesce((p_m->>'replies')::int, 0); v_n_sent int := coalesce((p_m->>'sent_total')::int, 0);
begin
  if v_n_scored > 0 and (p_m->>'readability_avg')::numeric < 90 then v_below := array_append(v_below, 'readability_avg'); end if;
  if v_n_scored > 0 and (p_m->>'tone_avg')::numeric < 90 then v_below := array_append(v_below, 'tone_avg'); end if;
  if v_n_sent >= 20 and (p_m->>'from')::timestamptz >= coalesce((select (value #>> '{}')::timestamptz from public.decision_policy where key = 'support_reply_scoring_complete_since'), 'infinity')
     and coalesce((p_m->>'scored_share')::numeric, 0) < 0.9 then v_below := array_append(v_below, 'scored_share'); end if;
  return v_below;
end $fn$;
revoke execute on function public.fn_customer_support_reply_quality_below(jsonb) from public, anon, authenticated;
grant execute on function public.fn_customer_support_reply_quality_below(jsonb) to service_role;

create or replace function public.fn_customer_support_reply_quality_week()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := now() - interval '7 days';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_m jsonb; v_below text[]; k text;
begin
  -- test traffic (a tagged row, the load stub's replies) is left out: a_load_test_reply_is_never_scored_as_a_real_one.sql
  v_m := public.fn_customer_support_reply_quality_metrics(v_from, now(), v_fx);
  v_below := public.fn_customer_support_reply_quality_below(v_m);

  if not v_fx then
    foreach k in array array['readability_avg', 'tone_avg', 'scored_share'] loop
      if k = any (v_below) then
        perform public.fn_it_engineer_finding_upsert('support_reply_quality:' || k,
          'Support replies of the last 7 days are under target on ' || k || ' (' || coalesce(v_m->>k, '?') || ')',
          'customer_support weekly reply quality (fn_customer_support_reply_quality_week)', 'customer_facing',
          greatest((v_m->>'sent_total')::int, coalesce((v_m->>'replies')::int, 0)),
          v_m || jsonb_build_object('owner_seat', 'customer_support', 'duty', 'reply_quality_week'),
          '{}'::text[], array['which road sends the replies that are unscored or under target'], 'customer_support');
      elsif exists (select 1 from public.it_engineer_finding f where f.issue_key = 'support_reply_quality:' || k and f.closed_at is null) then
        perform public.fn_it_engineer_finding_close('support_reply_quality:' || k, 'the last 7 days are back on target for ' || k);
      end if;
    end loop;
  end if;

  if not v_fx or not exists (select 1 from public.customer_support_reply_quality_week where week_ending = v_week and not fixture) then
    insert into public.customer_support_reply_quality_week (week_ending, metrics, below_target, fixture)
    values (v_week, v_m, v_below, v_fx)
    on conflict (week_ending) do update set metrics = excluded.metrics, below_target = excluded.below_target,
                                            fixture = excluded.fixture, reviewed_at = now();
  end if;
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'below_target', to_jsonb(v_below)) || v_m;
end $fn$;
revoke execute on function public.fn_customer_support_reply_quality_week() from public, anon, authenticated;
grant execute on function public.fn_customer_support_reply_quality_week() to service_role;

-- 3. THE 18 NOV ROW, RECOMPUTED OVER ITS OWN WINDOW ───────────────────────────────────────────────────────────────────────
-- Expected from the measurement above: 0 scored replies, chat 0 sent, 1,957 scores and 1,957 chat replies excluded, the
-- WhatsApp and e-mail counts unchanged (2 and 2), below_target empty (4 sent is under the 20 the share rule needs).
-- Idempotent: a second apply recomputes the same numbers and keeps the first previous_metrics.
update public.customer_support_reply_quality_week q
   set metrics = public.fn_customer_support_reply_quality_metrics((q.metrics->>'from')::timestamptz, (q.metrics->>'to')::timestamptz, false)
                 || jsonb_build_object('recomputed', 'a_load_test_reply_is_never_scored_as_a_real_one.sql',
                                       'previous_metrics', coalesce(q.metrics->'previous_metrics', q.metrics - 'recomputed')),
       below_target = public.fn_customer_support_reply_quality_below(
                        public.fn_customer_support_reply_quality_metrics((q.metrics->>'from')::timestamptz, (q.metrics->>'to')::timestamptz, false)),
       reviewed_at = now()
 where q.week_ending = date '2026-11-18' and not q.fixture and q.metrics ? 'from';

-- 4. PROBE: it cleans up after itself and answers with ONE ROW (this file holds DDL, so it never raises). Its rows are its
-- own: a window for the reserved tag zzloadprobe19 (never a real run: real load tags are zzload + 6 hex) and one ZZ DEMO
-- score row; both are deleted before the verdict, inside this file's one transaction, so no other session ever sees them.
-- It reaches nobody: support_reply_readability has no trigger but the stamp, and nothing is sent.
create temp table qd_probe_verdict (v text) on commit drop;
do $probe$
declare
  v_tag text := 'zzloadprobe19';
  v_real_before bigint := (select count(*) from public.support_reply_readability);
  v_row public.customer_support_reply_quality_week%rowtype;
  v_id bigint; v_got text; v_m jsonb; v_why text := null;
begin
  select * into v_row from public.customer_support_reply_quality_week where week_ending = date '2026-11-18' and not fixture;
  if v_row.week_ending is not null and coalesce((v_row.metrics->'sent'->>'chat')::int, -1) <> 0 then
    v_why := '18 Nov still counts ' || coalesce(v_row.metrics->'sent'->>'chat', '?') || ' chat replies';
  elsif v_row.week_ending is not null and coalesce((v_row.metrics->'by_channel'->'widget'->>'replies')::int, 0) <> 0 then
    v_why := '18 Nov still scores ' || (v_row.metrics->'by_channel'->'widget'->>'replies') || ' widget replies';
  end if;

  -- a load window (models_allowed false) keeps the tag on the row it stamps
  insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at, note)
    values ('qd_run:' || v_tag, 'load_test', false, 0.01, now() + interval '2 minutes', 'probe: a_load_test_reply_is_never_scored_as_a_real_one.sql');
  perform set_config('app.e2e_run_tag', v_tag, true);
  insert into public.support_reply_readability (channel, lang, path, rewritten, score, tone, issues, reason, demo)
    values ('widget', 'en', 'reasoned', false, 100, 100, '{}', 'ZZ DEMO probe', true) returning id, e2e_run_tag into v_id, v_got;
  perform set_config('app.e2e_run_tag', '', true);
  if v_why is null and v_got is distinct from v_tag then v_why := 'a load window''s row was stamped ' || coalesce(v_got, 'NULL'); end if;
  -- and the fixture week leaves it out as test traffic
  v_m := public.fn_customer_support_reply_quality_metrics(now() - interval '1 minute', now() + interval '1 minute', true);
  if v_why is null and coalesce((v_m->'excluded_test_traffic'->>'scored')::int, 0) < 1 then v_why := 'a tagged score was not excluded'; end if;

  delete from public.support_reply_readability where id = v_id;
  delete from public.rehearsal_window where run_tag = 'qd_run:' || v_tag;
  if v_why is null and (exists (select 1 from public.rehearsal_window where run_tag = 'qd_run:' || v_tag)
                        or (select count(*) from public.support_reply_readability) <> v_real_before) then
    v_why := 'the probe left a row behind';
  end if;
  insert into qd_probe_verdict values (coalesce('PROBE FAILED: ' || v_why, 'PROBE OK'));
end
$probe$;
select v as verdict from qd_probe_verdict;

-- CUSTOMER SUPPORT SCORES ITS REPLIES EVERY WEEK AND COUNTS WHAT WENT UNSCORED (19 Oct 2026). Assigned: customer_support.
-- Founder ledger 1003 stage 2, contribution CS-C06: "Monthly tone and readability review of every reply by channel and
-- language".
--
-- MEASURED 19 Oct 2026 (production, read-only):
--   * customer_support.monthly_self_review last ran 29 Sep for AUGUST and scored 0 replies, tone_avg null. Its input,
--     support_reply_readability, has 114 rows, the first on 12 Oct: there was nothing to read for August, and there
--     is nothing for September either, so the next monthly run (about 29 Oct) would score 0 again.
--   * The input is also short of what is sent: 12-18 Oct, 81 widget + 8 portal replies were scored while assistant_logs
--     holds 331 answered chat questions. The widget's and portal's MAIN road (site_assistant -> answerFromBrief) never
--     passed supportReply, the only writer of the score. That is the zero-reply input.
--
-- THE FIX:
--   1. supabase/functions/site_assistant/index.ts now scores every reply it sends (checkReadability, the same scorer the
--      gate uses) and logs it through fn_support_reply_readability_log. Applied by deploying site_assistant.
--   2. customer_support.reply_quality_week (this file), weekly, fn_customer_support_reply_quality_week(): the trailing
--      7 days' readability and tone by channel and language, AND the coverage of the score: replies sent per channel
--      (chat: assistant_logs answered; WhatsApp: wa_messages sent; email: inbound_messages replied) against replies
--      scored. A week under target (readability or tone average < 90, coverage < 90%) is the finding
--      support_reply_quality:<what> owned by customer_support, closed when a later week is back on target. So a
--      silent zero can never again read as "no replies": it reads as "N sent, 0 scored".
-- The monthly review (customer_support_scores_its_own_plain_language_and_tone_every_month.sql) is unchanged; it reads
-- the same table, which now fills from every road.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_scores_its_replies_every_week_and_counts_what_went_unscored.sql --apply --ddl

-- Coverage is judged only from the day every road scores (this file's apply, with the site_assistant deploy): before it,
-- the widget's main road was unscored by construction, which is the cause this file fixes, not a fresh alarm.
insert into public.decision_policy (key, value, description) values
  ('support_reply_scoring_complete_since', to_jsonb(now()::text),
   'fn_customer_support_reply_quality_week: the scored-share finding judges only replies sent after this instant, when every reply road (supportReply and site_assistant) logs its score.')
on conflict (key) do nothing;

create table if not exists public.customer_support_reply_quality_week (
  week_ending  date primary key,
  metrics      jsonb not null,
  below_target text[] not null default '{}',
  fixture      boolean not null default false,
  reviewed_at  timestamptz not null default now()
);
comment on table public.customer_support_reply_quality_week is
  'customer_support.reply_quality_week: the trailing week''s reply readability and tone by channel and language, and how many sent replies were scored at all.';
alter table public.customer_support_reply_quality_week enable row level security;
drop policy if exists customer_support_reply_quality_week_service_role_only on public.customer_support_reply_quality_week;
create policy customer_support_reply_quality_week_service_role_only on public.customer_support_reply_quality_week
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_reply_quality_week from anon, authenticated;

create or replace function public.fn_customer_support_reply_quality_week()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := now() - interval '7 days';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_scored jsonb; v_sent jsonb; v_m jsonb; v_below text[] := '{}'; v_cov numeric; v_n_scored int; v_n_sent int; k text;
begin
  select jsonb_build_object('replies', count(*), 'readability_avg', round(avg(r.score), 1), 'tone_avg', round(avg(r.tone), 1),
           'by_channel', (select coalesce(jsonb_object_agg(c.channel, jsonb_build_object('replies', c.n, 'readability_avg', c.s, 'tone_avg', c.t)), '{}')
                            from (select channel, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                   where created_at >= v_from and demo = v_fx group by channel) c),
           'by_language', (select coalesce(jsonb_object_agg(l.lang, jsonb_build_object('replies', l.n, 'readability_avg', l.s, 'tone_avg', l.t)), '{}')
                             from (select lang, count(*) n, round(avg(score), 1) s, round(avg(tone), 1) t from public.support_reply_readability
                                    where created_at >= v_from and demo = v_fx group by lang) l))
    into v_scored
    from public.support_reply_readability r where r.created_at >= v_from and r.demo = v_fx;

  select jsonb_build_object(
           'chat', (select count(*) from public.assistant_logs g where g.created_at >= v_from and g.answered
                       and (coalesce(g.message, '') like 'ZZ DEMO%') = v_fx),
           'whatsapp', (select count(*) from public.wa_messages w where w.created_at >= v_from and w.reply is not null and coalesce(w.sent, false)
                           and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx),
           'email', (select count(*) from public.inbound_messages m where m.replied_at >= v_from
                        and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, v_fx)))
    into v_sent;

  v_n_scored := coalesce((v_scored->>'replies')::int, 0);
  v_n_sent := (v_sent->>'chat')::int + (v_sent->>'whatsapp')::int + (v_sent->>'email')::int;
  v_cov := case when v_n_sent > 0 then round(least(1, v_n_scored::numeric / v_n_sent), 3) end;
  v_m := v_scored || jsonb_build_object('from', v_from, 'to', now(), 'sent', v_sent, 'sent_total', v_n_sent, 'scored_share', v_cov);

  if v_n_scored > 0 and (v_scored->>'readability_avg')::numeric < 90 then v_below := array_append(v_below, 'readability_avg'); end if;
  if v_n_scored > 0 and (v_scored->>'tone_avg')::numeric < 90 then v_below := array_append(v_below, 'tone_avg'); end if;
  if v_n_sent >= 20 and v_from >= coalesce((select (value #>> '{}')::timestamptz from public.decision_policy where key = 'support_reply_scoring_complete_since'), 'infinity')
     and coalesce(v_cov, 0) < 0.9 then v_below := array_append(v_below, 'scored_share'); end if;

  if not v_fx then
    foreach k in array array['readability_avg', 'tone_avg', 'scored_share'] loop
      if k = any (v_below) then
        perform public.fn_it_engineer_finding_upsert('support_reply_quality:' || k,
          'Support replies of the last 7 days are under target on ' || k || ' (' || coalesce(v_m->>k, '?') || ')',
          'customer_support weekly reply quality (fn_customer_support_reply_quality_week)', 'customer_facing', greatest(v_n_sent, v_n_scored),
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

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.reply_quality_week', 'customer_support', interval '7 days', 'fn_customer_support_reply_quality_week',
   'CS-C06: the trailing week''s reply readability and tone by channel and language, with replies sent against replies scored; under target is a finding the seat owns',
   'scripts/sql/customer_support_scores_its_replies_every_week_and_counts_what_went_unscored.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- the new table is in the daily table export (backups), like every other seat record
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_support_reply_quality_week', true, 'customer_support', 'The weekly reply readability, tone and scored-share review of customer_support (CS-C06).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

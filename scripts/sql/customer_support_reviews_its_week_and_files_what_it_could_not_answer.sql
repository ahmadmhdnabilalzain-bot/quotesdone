-- CUSTOMER SUPPORT REVIEWS ITS WEEK AND FILES WHAT IT COULD NOT ANSWER (24 Sep 2026; seat: customer_support).
--
-- The founder approved the seat job descriptions on 24 Sep 2026 (ledger 983). Customer support's weekly duty:
-- "A case review: first-response time, resolution, repeat contacts, and questions it could not answer.
-- Unanswered questions become knowledge requests." GAPS.md (24 Sep, customer support gap 6): MISSING, no routine.
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * The conversations live in three tables: inbound_messages (email; replied_at is the first reply),
--     wa_messages (WhatsApp; the reply is written on the inbound's own row, so reply MINUTES are not recorded)
--     and assistant_logs (the homepage chat; answered=false is a question the widget could not source).
--     assistant_logs: 80 rows, 18 answered=false.
--   * fn_support_reply_watch_tick already raises a finding for a message waiting past the first-reply SLA, one
--     channel at a time. Nothing looks back over a week: no routine counts repeat contacts or resolution.
--   * The knowledge request already has ONE door: fn_support_knowledge_gap(question, refusal, surface) files the
--     question in sales_knowledge_gap with its knowledge_gap work item, and counts a repeat ask. site_assistant and
--     wa_inbound call it at the moment of refusal, but a chat refusal logged while that call failed has
--     gap_task_id null and was never filed by anyone (site_assistant swallows the error so the reply still goes).
--
-- WHAT THIS ADDS
--   customer_support.case_review (weekly, fn_customer_support_case_review_tick). Pure SQL, no model call. For the
--   seven days to now it records, per channel:
--     email     received, replied, unanswered, median and 90th-percentile first-reply minutes;
--     whatsapp  received, replied, unanswered (minutes are not recorded on this channel: the table has no reply
--               time, and the review says so rather than printing a number it does not have);
--     chat      questions, answered, not answered;
--   repeat contacts: a person (email address, or WhatsApp number) who wrote on two or more distinct Dubai days
--   in the week -- the measurable sign that the first contact did not resolve it; complaints opened, given their
--   final response, and past their respond_due with none; knowledge: requests opened in the week, still open.
--   Every chat question the widget could not answer and that was never filed is filed NOW through
--   fn_support_knowledge_gap (surface website_widget, refusal weekly_case_review) and its log row is linked to
--   the returned work item, so it is never filed twice. One row per week in customer_support_case_review.
--   The founder's own WhatsApp numbers are excluded (WhatsApp is his command channel), and so are the expenses
--   mailbox and the accountant's mail. With qd.duty_fixtures = 'on' the review counts and files ONLY ZZ DEMO /
--   example.invalid rows, so a probe can never file a real person's question.
--
-- WHAT THIS DOES NOT DO: it sends nothing to anyone (the numbers are the seat's record, read by the CEO's weekly
-- review from this table); it does not answer the filed questions (that is the knowledge build, paused by 953);
-- it does not score the automated scenario suite (instr 781, a separate gap).
--
-- Prevented by: scripts/checks/customer_support_reviews_its_week.test.mjs.
--   node scripts/apply_sql.mjs scripts/sql/customer_support_reviews_its_week_and_files_what_it_could_not_answer.sql --apply --ddl

create table if not exists public.customer_support_case_review (
  week_ending        date not null primary key,
  metrics            jsonb not null,
  knowledge_filed    integer not null default 0 check (knowledge_filed >= 0),
  fixture            boolean not null default false,
  reviewed_at        timestamptz not null default now()
);
alter table public.customer_support_case_review enable row level security;
drop policy if exists customer_support_case_review_service_role_only on public.customer_support_case_review;
create policy customer_support_case_review_service_role_only on public.customer_support_case_review
  as permissive for all to public using (false) with check (false);
revoke all on public.customer_support_case_review from anon, authenticated;
comment on table public.customer_support_case_review is
  'customer_support''s weekly case review (fn_customer_support_case_review_tick): per-channel volume, first-reply time, unanswered, repeat contacts, complaints and knowledge requests for the seven days to reviewed_at. One row per Dubai week_ending; a fixture run writes fixture=true.';

create or replace function public.fn_customer_support_case_review_tick()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_from timestamptz := now() - interval '7 days';
  v_week date := (now() at time zone 'Asia/Dubai')::date;
  v_founder text[]; v_email jsonb; v_wa jsonb; v_chat jsonb; v_repeat jsonb; v_complaints jsonb; v_knowledge jsonb;
  v_metrics jsonb; g record; v_gap jsonb; v_filed int := 0;
  -- a machine is not a person: bounces and auto-senders are neither a support contact nor a repeat one
  v_robot text := '^(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)([+.-][^@]*)?@';
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- email: the same mailbox scope as fn_support_reply_watch_tick (not the expenses mailbox, not the accountant's)
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where m.replied_at is not null),
           'unanswered', count(*) filter (where m.replied_at is null),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric))
    into v_email
    from public.inbound_messages m
   where m.created_at >= v_from and coalesce(m.from_email, '') !~* v_robot
     and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
     and public.fn_is_demo_email(m.from_email) = v_fx;

  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where w.reply is not null and coalesce(w.sent, false)),
           'unanswered', count(*) filter (where w.reply is null or not coalesce(w.sent, false)),
           'first_reply_minutes', null,
           'first_reply_minutes_note', 'not recorded: wa_messages writes the reply on the inbound''s row with no reply time')
    into v_wa
    from public.wa_messages w
   where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> ''
     and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
     and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx;

  select jsonb_build_object('questions', count(*), 'answered', count(*) filter (where g2.answered),
                            'not_answered', count(*) filter (where not g2.answered))
    into v_chat
    from public.assistant_logs g2
   where g2.created_at >= v_from and (coalesce(g2.message, '') like 'ZZ DEMO%') = v_fx;

  -- repeat contact: the same person on two or more distinct Dubai days of the week
  select jsonb_build_object('people', count(*), 'contacts', coalesce(sum(r.days), 0))
    into v_repeat
    from (select who, count(distinct d) days from (
            select 'email:' || lower(btrim(m.from_email)) who, (m.created_at at time zone 'Asia/Dubai')::date d
              from public.inbound_messages m
             where m.created_at >= v_from and coalesce(btrim(m.from_email), '') <> '' and m.from_email !~* v_robot
               and coalesce(m.to_email, '') !~* '^expenses@' and coalesce(m.owner_role, '') <> 'accountant'
               and public.fn_is_demo_email(m.from_email) = v_fx
            union all
            select 'whatsapp:' || right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9), (w.created_at at time zone 'Asia/Dubai')::date
              from public.wa_messages w
             where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> '' and coalesce(btrim(w.wa_from), '') <> ''
               and not (right(regexp_replace(w.wa_from, '[^0-9]', '', 'g'), 9) = any (v_founder))
               and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx) c
          group by who having count(distinct d) >= 2) r;

  select jsonb_build_object('opened', count(*) filter (where t.created_at >= v_from),
                            'final_response_given', count(*) filter (where t.final_response_at >= v_from),
                            'past_respond_due', count(*) filter (where t.final_response_at is null and t.respond_due < now()))
    into v_complaints
    from public.complaint_tickets t
   where public.fn_is_demo_email(t.email) = v_fx
     and (t.created_at >= v_from or t.final_response_at >= v_from or t.final_response_at is null);

  -- UNANSWERED QUESTIONS BECOME KNOWLEDGE REQUESTS, through the one door, once.
  for g in select a.id, a.message from public.assistant_logs a
            where a.answered = false and a.gap_task_id is null and a.created_at >= v_from
              and coalesce(btrim(a.message), '') <> '' and (coalesce(a.message, '') like 'ZZ DEMO%') = v_fx
            order by a.id for update of a skip locked loop
    v_gap := public.fn_support_knowledge_gap(g.message, 'weekly_case_review', 'website_widget');
    if coalesce((v_gap->>'ok')::boolean, false) and v_gap->>'task_id' is not null then
      update public.assistant_logs set gap_task_id = (v_gap->>'task_id')::bigint where id = g.id;
      v_filed := v_filed + 1;
    end if;
  end loop;

  select jsonb_build_object('opened_this_week', count(*) filter (where k.first_asked_at >= v_from),
                            'asked_again_this_week', count(*) filter (where k.first_asked_at < v_from and k.last_asked_at >= v_from),
                            'still_open', count(*) filter (where k.status = 'open'),
                            'filed_by_this_review', v_filed)
    into v_knowledge
    from public.sales_knowledge_gap k
   where (k.question like 'ZZ DEMO%') = v_fx and (k.last_asked_at >= v_from or k.status = 'open');

  v_metrics := jsonb_build_object('from', v_from, 'to', now(), 'email', v_email, 'whatsapp', v_wa, 'chat', v_chat,
                                  'repeat_contacts', v_repeat, 'complaints', v_complaints, 'knowledge', v_knowledge);
  -- a fixture run never overwrites the real week's row
  if not v_fx or not exists (select 1 from public.customer_support_case_review where week_ending = v_week and not fixture) then
    insert into public.customer_support_case_review (week_ending, metrics, knowledge_filed, fixture)
    values (v_week, v_metrics, v_filed, v_fx)
    on conflict (week_ending) do update
      set metrics = excluded.metrics, knowledge_filed = customer_support_case_review.knowledge_filed + excluded.knowledge_filed,
          fixture = excluded.fixture, reviewed_at = now();
  end if;
  return jsonb_build_object('week_ending', v_week, 'knowledge_filed', v_filed, 'fixture', v_fx) || v_metrics;
end $fn$;
revoke execute on function public.fn_customer_support_case_review_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_case_review_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.case_review', 'customer_support', interval '7 days', 'fn_customer_support_case_review_tick',
   'the weekly case review: first-reply time, resolution, repeat contacts, complaints, and every unanswered chat question filed as a knowledge request',
   'scripts/sql/customer_support_reviews_its_week_and_files_what_it_could_not_answer.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

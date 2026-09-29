-- THE CASE REVIEW COUNTS ONLY CUSTOMERS AND TIMES THE WHATSAPP REPLY (30 Sep 2026; seat: customer_support).
--
-- The senior-hire audit (docs/audits/2026-09-30_senior_hire_audit.md, customer_support 1-3) read the first
-- customer_support.case_review row (week ending 24 Sep) and found three defects in what it measures.
--
-- WHAT WAS MEASURED (30 Sep 2026, production, read-only):
--   * email: "received 4, replied 0, unanswered 4". Every unanswered row in the last 14 days, by sender and mailbox:
--       2 x security-noreply@linkedin.com -> info@  (a machine: the robot pattern only matched a local part that
--                                                    STARTS with noreply, so "security-noreply" passed)
--       3 x the founder's management@ address -> calendar+<token>@  (his replies approving the social calendar)
--     Earlier weeks also carried the expenses forwards and a ZZ DEMO probe. None of them is a customer.
--   * chat: "not answered 12, filed_by_this_review 0". All 12 unanswered questions of that week already carried
--     gap_task_id: site_assistant filed each one at the moment it refused. The review filed 0 because there was
--     nothing left to file, and still_open 12 is those same 12. Nothing was lost, but the row cannot show it, so
--     the audit read "filed 0 while 12 are open" as a broken contract.
--   * whatsapp: "first_reply_minutes: not recorded". wa_messages had no reply time, and created_at was stamped
--     when the row was written, which is AFTER the reply was produced.
--
-- WHAT THIS CHANGES
--   1. wa_messages.replied_at. wa_inbound now writes every row through waRow (supabase/functions/wa_inbound/
--      wa_row.ts): created_at = the moment the inbound arrived, replied_at = the moment the reply was written,
--      set only when it was sent. Rows before this change keep replied_at null and are not timed.
--   2. fn_support_email_is_a_customer_contact(from, to, owner_role, subject, fixtures): the ONE test of whether an
--      inbound email is a support contact. Not: a machine sender (the pattern now matches noreply ANYWHERE in the
--      local part), the expenses@ mailbox, a calendar+ or approve+ reply address (the founder's approvals), the
--      accountant's mail, or any of the founder's own addresses (app_secrets admin_emails and founder_email).
--      A ZZ DEMO subject or an example.invalid sender is a fixture: counted only on a fixture run.
--   3. The review reports chat.not_answered_filed (already filed, by site_assistant or by this review) and
--      chat.not_answered_unfiled next to filed_by_this_review, and times WhatsApp from replied_at.
--
-- RE-MEASURED with the new test over the same week (17-24 Sep): email received 0, unanswered 0. See the PR.
--
-- Prevented by: scripts/checks/customer_support_reviews_its_week.test.mjs (the exclusions and the WhatsApp
-- timing are asserted on this file) and supabase/functions/wa_inbound/wa_row.test.ts (the write).
--   node scripts/apply_sql.mjs scripts/sql/the_case_review_counts_only_customers_and_times_the_whatsapp_reply.sql --apply --ddl

alter table public.wa_messages add column if not exists replied_at timestamptz;
comment on column public.wa_messages.replied_at is
  'When the reply on this row was sent (wa_inbound waRow, from 30 Sep 2026). created_at is when the inbound arrived, so replied_at - created_at is the first-reply time. Null when no reply was sent, and on every row written before 30 Sep 2026.';

create or replace function public.fn_support_email_is_a_customer_contact(
  p_from text, p_to text, p_owner_role text, p_subject text, p_fixtures boolean)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p_from, '') !~* '^[^@]*(mailer-daemon|postmaster|no-?reply|do-?not-?reply|bounces?)[^@]*@'
     and coalesce(p_to, '') !~* '^(expenses@|calendar\+|approve\+)'
     and coalesce(p_owner_role, '') <> 'accountant'
     and lower(btrim(coalesce(p_from, ''))) <> all (
           select lower(btrim(e)) from public.app_secrets s, unnest(string_to_array(s.value, ',')) e
            where s.key in ('admin_emails', 'founder_email') and btrim(e) <> '')
     and (public.fn_is_demo_email(p_from) or coalesce(p_subject, '') like 'ZZ DEMO%') = p_fixtures
$fn$;
revoke execute on function public.fn_support_email_is_a_customer_contact(text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_support_email_is_a_customer_contact(text, text, text, text, boolean) to service_role;

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
begin
  select coalesce(array_agg(right(regexp_replace(value, '[^0-9]', '', 'g'), 9)), '{}') into v_founder
    from public.app_secrets where key in ('founder_mobile', 'founder_public_phone', 'admin_mfa_phone')
     and length(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g')) >= 9;

  -- email: a customer contact only (fn_support_email_is_a_customer_contact names every exclusion)
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where m.replied_at is not null),
           'unanswered', count(*) filter (where m.replied_at is null),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from m.replied_at - m.created_at) / 60))::numeric))
    into v_email
    from public.inbound_messages m
   where m.created_at >= v_from
     and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, v_fx);

  -- whatsapp: timed from replied_at (wa_inbound waRow, from 30 Sep 2026); an untimed row is not guessed
  select jsonb_build_object(
           'received', count(*), 'replied', count(*) filter (where w.reply is not null and coalesce(w.sent, false)),
           'unanswered', count(*) filter (where w.reply is null or not coalesce(w.sent, false)),
           'timed', count(w.replied_at),
           'median_first_reply_minutes', round((percentile_cont(0.5) within group (order by extract(epoch from w.replied_at - w.created_at) / 60))::numeric, 1),
           'p90_first_reply_minutes', round((percentile_cont(0.9) within group (order by extract(epoch from w.replied_at - w.created_at) / 60))::numeric, 1))
    into v_wa
    from public.wa_messages w
   where w.created_at >= v_from and coalesce(btrim(w.inbound), '') <> ''
     and not (right(regexp_replace(coalesce(w.wa_from, ''), '[^0-9]', '', 'g'), 9) = any (v_founder))
     and (coalesce(w.profile_name, '') like 'ZZ DEMO%') = v_fx;

  -- repeat contact: the same person on two or more distinct Dubai days of the week
  select jsonb_build_object('people', count(*), 'contacts', coalesce(sum(r.days), 0))
    into v_repeat
    from (select who, count(distinct d) days from (
            select 'email:' || lower(btrim(m.from_email)) who, (m.created_at at time zone 'Asia/Dubai')::date d
              from public.inbound_messages m
             where m.created_at >= v_from and coalesce(btrim(m.from_email), '') <> ''
               and public.fn_support_email_is_a_customer_contact(m.from_email, m.to_email, m.owner_role, m.subject, v_fx)
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

  -- counted AFTER the filing loop, so "filed" covers what site_assistant filed at refusal and what this review filed
  select jsonb_build_object('questions', count(*), 'answered', count(*) filter (where g2.answered),
                            'not_answered', count(*) filter (where not g2.answered),
                            'not_answered_filed', count(*) filter (where not g2.answered and g2.gap_task_id is not null),
                            'not_answered_unfiled', count(*) filter (where not g2.answered and g2.gap_task_id is null))
    into v_chat
    from public.assistant_logs g2
   where g2.created_at >= v_from and (coalesce(g2.message, '') like 'ZZ DEMO%') = v_fx;

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

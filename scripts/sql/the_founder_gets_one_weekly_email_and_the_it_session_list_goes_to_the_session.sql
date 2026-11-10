-- THE FOUNDER GETS ONE WEEKLY E-MAIL, AND THE IT SESSION LIST GOES TO THE SESSION, NOT TO HIM.
--
-- Assigned: it_engineer (the digest and its session list) and ceo (the weekly e-mail). 10 Nov 2026. Founder ledger 1609
-- ("no decision goes to the founder"), 1616 (he is told in his daily brief). Proposals P5 and P6 of
-- docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 28 Oct - 10 Nov 2026 (14 days), production read-only =====================================================
--   * 50 rows reached the founder's inboxes or role (48 sent): founder_brief 21 (14 daily briefs + 7 "CEO note", the note
--     stopped by #1903), whatsapp_human_request 4, person_request 4, refund_ceo_summary 4, supplier_campaign_daily_list 3,
--     board_report 2, ceo_weekly_review 2, accountant_weekly_report 2, support_case_closed 2, support_csat_request 2,
--     ceo_strategy_memo 1, ceo_market_report 1, integration_reauth_needed 1, it_daily_digest 1.
--   * it_daily_digest (fn_customer_support_sends_the_it_digest, live): mailed whenever a "what a working session must fix"
--     list exists, with "No decision of yours is needed today" in its first line. A to-do list for a session, not him.
--   * board_report (fn_ceo_weekly_report_deliver) and ceo_weekly_review (fn_ceo_weekly_review_deliver): two weekly
--     e-mails an hour apart every Monday (W45: 04:01 and 05:00 UTC, 9 Nov), the company report for the week just ended
--     and the CEO's review of the same week.
--
-- == WHAT THIS CHANGES ===============================================================================================
--   it_session_fix_day                      one row a Dubai day: the IT digest's session list, for the session to read at
--                                           start (the IT seat's queue). The digest mails him only when a decision that is
--                                           his exists (money, a destructive change, a fact only he holds).
--   fn_ceo_weekly_report_deliver            renders and hands the week's company report over without mailing it.
--   fn_ceo_weekly_review_deliver            the Monday review carries the company report's text and its PDF: one e-mail.
-- Each is the live body read back on 10 Nov 2026 with only those lines changed.
-- EXPECTED AFTER: of the 14 days' 48 sends, it_daily_digest 1 and board_report 2 go (45 left), and the 7 CEO notes are
-- already gone with #1903: 38 a fortnight, of which 14 are the daily brief.
-- NOT CHANGED: founder_mail_policy (board_report and it_daily_digest stay allowed kinds; nothing is sent under them), any
-- alert he asked for (person requests, emergencies, the OpenRouter low balance), the daily brief.
-- prevented by: scripts/checks/the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.test.mjs
-- Pending: scripts/sql/pending/the_founder_gets_one_weekly_email_and_the_it_session_list_goes_to_the_session.txt

create table if not exists public.it_session_fix_day (
  day         date primary key,
  items       jsonb not null default '[]'::jsonb,
  digest_key  text,
  written_at  timestamptz not null default now(),
  read_by_session_at timestamptz
);
alter table public.it_session_fix_day enable row level security;
drop policy if exists it_session_fix_day_service_role_only on public.it_session_fix_day;
create policy it_session_fix_day_service_role_only on public.it_session_fix_day as permissive for all to public using (false) with check (false);
revoke all on public.it_session_fix_day from anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_customer_support_sends_the_it_digest(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  c_hour  constant time := time '19:00';                         -- the founder's fixed local time
  v_stub  boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_local timestamp := p_now at time zone 'Asia/Dubai';
  v_key   text := 'it_daily_digest:' || to_char(p_now at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  x record; f public.it_engineer_finding; v_why text; v_his boolean; v_cat text; v_items jsonb := '[]'::jsonb;
  v_event text; v_detail text; v_res jsonb; v_fan jsonb := '[]'::jsonb; v_before bigint;
  n_dec int := 0; n_flt int := 0; n_int int := 0; n_fixed int := 0; n_wait int := 0;
  v_session jsonb := '[]'::jsonb; v_session_text text; n_sess int := 0;
begin
  perform pg_advisory_xact_lock(hashtext('fn_customer_support_sends_the_it_digest'));
  if v_local::time < c_hour then
    return jsonb_build_object('sent', false, 'reason', 'the IT digest leaves at 19:00 Dubai', 'digest_key', v_key);
  end if;
  if exists (select 1 from public.founder_alerts where dedupe_key = v_key) then
    return jsonb_build_object('sent', false, 'reason', 'today''s IT digest was already decided', 'digest_key', v_key);
  end if;

  for x in select a.id, a.detail, a.evidence from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'customer_support' and a.status = 'pending'
              and a.detail->>'type' = 'delivery.request' and a.detail->>'recipient_role' = 'founder'
              and a.detail->>'kind' = 'it_new_bug' and a.evidence->>'digest' = 'pending'
            order by a.id loop
    -- Anything that is not "a new bug nobody could fix" (today: the CEO-silence reports) is the CEO's.
    if coalesce(x.detail->>'dedupe_key', '') !~ '^it_new_bug:' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'instruction 642: kept internal; the CEO is asked every tick until it answers',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    select * into f from public.it_engineer_finding where issue_key = regexp_replace(x.detail->>'dedupe_key', '^it_new_bug:', '');
    if not found or f.closed_at is not null then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'fixed',
        'why', 'closed before the digest: ' || coalesce(f.close_note, 'no finding row'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_fixed := n_fixed + 1; continue;
    end if;
    -- FOUNDER RULING 1090 (30 Sep 2026): a credential only he can renew is never a digest line.
    if public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 1090: a credential only the founder can renew is recorded by the IT engineer, never sent to him',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- 5 OCT 2026 (notifications#84149): a failing integration with no account he holds stays the IT engineer's.
    if f.issue_key like 'duty:integration:%' and f.evidence->>'notify' is distinct from 'true' then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'the integration watch marked it notify=false: no account the founder holds can restore it; the IT engineer owns it',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    -- His ruling that something is NOT his wins over any pattern that would ask him. 19 Oct 2026 (ruling 1254):
    -- a class reaches him only when it also names one of his three categories; to_founder alone is not enough.
    select c.why, c.to_founder, c.founder_category into v_why, v_his, v_cat from public.it_founder_decision_class c
     where f.issue_key like c.issue_key_like
     order by c.to_founder, length(c.issue_key_like) desc limit 1;
    if found and (not v_his or coalesce(v_cat, '') not in ('money', 'destructive_production_change', 'fact_only_he_holds')) then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', coalesce(v_why, 'technical: the class names no founder category'),
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; v_why := null; continue;
    end if;
    -- FOUNDER RULING 4 OCT 2026: the digest carries ONLY decisions only he can make.
    if not found then
      perform public.fn_seat_handoff_complete(x.id, (x.evidence - 'waiting') || jsonb_build_object('digest', 'internal',
        'why', 'founder ruling 4 Oct 2026: not a decision only the founder can make; the finding stays with the '
               || replace(coalesce(f.evidence->>'owner_seat', 'it_engineer'), '_', ' ') || ' on the OS',
        'notify', jsonb_build_object('emailed', false, 'kind', 'it_new_bug')));
      n_int := n_int + 1; continue;
    end if;
    v_items := v_items || jsonb_build_object('id', x.id, 'key', f.issue_key, 'category', v_cat,
      'title', public.fn_trim_at_word(regexp_replace(f.title, '[.\s]+$', ''), 160), 'why', v_why);
    n_dec := n_dec + 1;
  end loop;

  -- 10 Nov 2026 (ruling 1574): the ONE daily list of what only a working session can fix rides on this digest, never a
  -- second email: failing duties, stopped playbooks, what a playbook could not act on, questions past their deadline.
  v_session := coalesce(public.fn_it_session_fix_list(), '[]'::jsonb);
  n_sess := jsonb_array_length(v_session);
  -- P5 (10 Nov 2026): the session list is the IT seat's queue for the next working session, never the founder's inbox
  if not v_stub then
    insert into public.it_session_fix_day (day, items, digest_key, written_at)
    values ((v_local)::date, v_session, v_key, now())
    on conflict (day) do update set items = excluded.items, digest_key = excluded.digest_key, written_at = now();
  end if;

  -- only a decision that is his (money, a destructive change, a fact only he holds) is ever mailed
  if jsonb_array_length(v_items) = 0 then
    if not v_stub then
      insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
      values ('info', 'IT daily digest: nothing needs the founder today',
              jsonb_build_object('fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'session_items', n_sess, 'session_list', 'public.it_session_fix_day')::text, 'os', v_key);
    end if;
    return jsonb_build_object('sent', false, 'reason', 'nothing needs him today; the session list is on public.it_session_fix_day', 'digest_key', v_key,
                              'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait, 'session_items', n_sess, 'stubbed', v_stub);
  end if;

  -- One plain line per decision: what it is, and why only he can act. No internal keys or ids.
  select string_agg('- ' || (i->>'title') || '.' || E'\n  Why this needs you: '
                    || case i->>'category'
                         when 'money' then 'it spends or returns company money.'
                         when 'destructive_production_change' then 'it would remove or overwrite live company data.'
                         else coalesce(nullif(regexp_replace(i->>'why', '[.\s]+$', ''), ''),
                                       'only you hold the account or the fact it needs') || '.'
                       end,
                    E'\n' order by (i->>'id')::bigint)
    into v_detail from jsonb_array_elements(v_items) i;
  -- One plain line per thing a working session must fix (fn_it_session_fix_list writes them in words, no keys).
  select string_agg('- ' || (s->>'line') || '.', E'\n' order by (s->>'rank')::int)
    into v_session_text from jsonb_array_elements(v_session) s;
  v_event := case when n_dec > 0 then 'IT: ' || n_dec || case when n_dec > 1 then ' things only you can decide' else ' thing only you can decide' end
                  else 'IT: what a working session must fix today' end;
  v_detail := case when n_dec > 0
                   then 'Everything else today is being handled by the team; this is only what needs you.' || E'\n\n' || v_detail
                        || E'\n\n' || 'Reply to this email with your answer and the CEO will act on it.'
                   else 'No decision of yours is needed today.' end
           -- the session list is no longer part of his mail (P5): it is on public.it_session_fix_day for the session
           || '';

  if v_stub then
    v_res := jsonb_build_object('stubbed', true);               -- A TEST NEVER REACHES HIM
  else
    select coalesce(max(id), 0) into v_before from public.notifications;
    perform set_config('app.qd_delivery_tracked', 'on', true);
    v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_detail, p_level => 'normal',
                                      p_kind => 'it_daily_digest', p_dedupe_key => v_key, p_owner_agent => 'it_engineer');   -- 19 Oct 2026: the IT engineer owns its digest
    select coalesce(jsonb_agg(n.id order by n.id), '[]'::jsonb) into v_fan from public.notifications n
     where n.id > v_before and n.type = 'founder_alert' and n.created_at = now();
    perform set_config('app.qd_delivery_tracked', 'off', true);
  end if;
  for x in select (i->>'id')::bigint id from jsonb_array_elements(v_items) i loop
    perform public.fn_seat_handoff_complete(x.id, (select (a.evidence - 'waiting') from public.agent_actions a where a.id = x.id)
      || jsonb_build_object('digest', 'sent', 'digest_key', v_key, 'notify', v_res, 'notification_ids', v_fan, 'notification_id', v_fan->0)
      || case when v_stub then jsonb_build_object('stubbed', true) else '{}'::jsonb end);
  end loop;

  return jsonb_build_object('sent', true, 'digest_key', v_key, 'event', v_event, 'detail', v_detail,
                            'decisions', n_dec, 'session_items', n_sess, 'faults', n_flt, 'fixed', n_fixed, 'internal', n_int, 'waiting', n_wait,
                            'notify', v_res, 'notification_ids', v_fan, 'stubbed', v_stub);
end $fn$;

CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_report_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  r        public.ceo_weekly_report;
  v_owner  text;
  v_notif  bigint;          -- the notifications.id from RETURNING, never a routine's jsonb answer
  v_file   text;
  v_err    text;
begin
  -- FOR UPDATE (review of #802): two overlapping ticks both read founder_submitted_at null and mailed the
  -- week twice. The row lock makes the second wait for the first to commit, then see it delivered.
  select * into r from public.ceo_weekly_report where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_report '||p_id); end if;
  if r.founder_submitted_at is not null then
    return jsonb_build_object('ok', true, 'report_key', r.report_key, 'status', r.status, 'already', true);
  end if;

  -- THE PDF IS THE DELIVERABLE. Mailing text and closing the week would close it on the wrong thing.
  if r.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; the report is retained and the next tick retries';
  else
    select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
      from public.app_secrets where key = 'admin_emails';
    if v_owner is null then
      v_err := 'no recipient configured in app_secrets.admin_emails';
    else
      v_file := 'QuotesDone_Weekly_Company_Report_'
             || regexp_replace(replace(r.report_key, 'quotesdone:', ''), '[^A-Za-z0-9_-]', '_', 'g')
             || case when r.revision > 1 then '_revision_'||r.revision else '' end || '.pdf';
      -- P6 (10 Nov 2026): ONE WEEKLY E-MAIL. The company report is no longer mailed on its own: the CEO weekly review of
      -- the following Monday carries it (fn_ceo_weekly_review_deliver attaches this PDF and its text). The report is
      -- delivered when it is rendered and handed over; no notification row is written here.
      v_notif := null;
    end if;
  end if;

  update public.ceo_weekly_report
     set notification_id      = coalesce(v_notif, notification_id),
         founder_submitted_at = case when v_err is null then now() else founder_submitted_at end,
         delivery_attempts    = delivery_attempts + 1,
         last_delivery_error  = v_err,
         status               = case when v_err is null then 'delivered' else 'delivery_failed' end,
         updated_at           = now()
   where id = p_id returning * into r;

  -- ok/error at the TOP LEVEL: resilience_ping's failureOf reads nothing deeper, which is how 76 failed
  -- attempts were recorded as a healthy step.
  return jsonb_build_object('ok', v_err is null, 'merged_into', 'ceo_weekly_review', 'report_key', r.report_key,
    'notification_id', r.notification_id, 'status', r.status, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $fn$;

CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_review_deliver(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare w public.ceo_weekly_review; b public.ceo_weekly_report; v_res jsonb; v_notif bigint; v_err text; v_file text; v_event text; v_l jsonb; v_text text;
begin
  select * into w from public.ceo_weekly_review where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such ceo_weekly_review ' || p_id); end if;
  if w.delivered_at is not null then return jsonb_build_object('ok', true, 'week', w.week, 'already', true); end if;

  if w.pdf_path is null then
    v_err := 'not delivered: the PDF has not been rendered yet; retained, the next beat retries';
  else
    v_event := 'CEO weekly review, week of ' || to_char(w.week, 'DD Mon YYYY');
    v_file := 'QuotesDone_CEO_Weekly_Review_' || to_char(w.week, 'IYYY-"W"IW') || '.pdf';
    v_text := public.fn_ceo_weekly_review_text(p_id);
    -- P6 (10 Nov 2026): the week's company report rides on this e-mail (one weekly e-mail to the founder, not two)
    select * into b from public.ceo_weekly_report r where r.week_end = w.week - 1 and r.pdf_path is not null order by r.revision desc limit 1;
    if b.id is not null then
      v_text := v_text || E'\n\nThe company report for ' || to_char(b.week_start, 'DD Mon') || ' to ' || to_char(b.week_end, 'DD Mon YYYY')
             || E' is attached too.\n\n' || coalesce(b.body, '');
    end if;
    begin
      v_res := public.fn_notify_founder(p_event => v_event, p_detail => v_text || E'\n\nThe one-page review is attached.\n\nCEO',
        p_level => 'info', p_kind => 'ceo_weekly_review', p_dedupe_key => 'ceo_weekly_review:' || w.week, p_owner_agent => 'ceo');
      if coalesce((v_res->>'emailed')::boolean, false) then
        update public.notifications n
           set attachments = jsonb_build_array(jsonb_build_object('bucket', coalesce(w.pdf_bucket, 'agent-docs'), 'path', w.pdf_path, 'filename', v_file))
                             || case when b.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('bucket', coalesce(b.pdf_bucket, 'agent-docs'), 'path', b.pdf_path,
                                  'filename', 'QuotesDone_Weekly_Company_Report_' || replace(b.report_key, 'quotesdone:', '') || '.pdf')) end
         where n.id = (select max(x.id) from public.notifications x
                        where x.kind = 'ceo_weekly_review' and x.channel = 'email' and x.to_role = 'founder' and x.created_at = now())
        returning n.id into v_notif;
        if v_notif is null then v_err := 'fn_notify_founder said emailed, but no queued email of kind ceo_weekly_review was found to attach the PDF to'; end if;
      else
        v_err := 'fn_notify_founder did not email: ' || coalesce(v_res::text, 'null');
      end if;
    exception when others then
      v_err := 'delivery raised: ' || sqlerrm;
      v_notif := null;
    end;
  end if;

  update public.ceo_weekly_review
     set notification_id = coalesce(v_notif, notification_id), notify = coalesce(v_res, notify),
         delivered_at = case when v_notif is not null then now() end,
         attempts = attempts + 1, last_error = v_err, updated_at = now()
   where id = p_id;
  return jsonb_build_object('ok', v_notif is not null, 'week', w.week, 'notification_id', v_notif, 'pdf_filename', v_file)
    || case when v_err is null then '{}'::jsonb else jsonb_build_object('error', v_err) end;
end $fn$;

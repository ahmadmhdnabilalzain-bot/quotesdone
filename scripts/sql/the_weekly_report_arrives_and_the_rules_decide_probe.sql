-- PROBE: the CEO weekly report is delivered with its PDF through the founder-mail gate, and the CEO's
-- decision rules fire on production data with evidence. Pure probe -- NO DDL in this file.
-- Seat: ceo. 21 Sep 2026. Pairs with the_weekly_report_arrives_and_the_rules_decide.sql.
--
-- Run it with: node scripts/qsql.mjs scripts/sql/the_weekly_report_arrives_and_the_rules_decide_probe.sql
-- Against the unchanged database it answers PROBE FAILED (fn_ceo_weekly_report_attach_pdf does not exist).
--
-- HOW IT STAYS HARMLESS: every write is inside an inner block that always ends in a raised exception,
-- so nothing commits. And it CANNOT reach the founder even if it did: inside that block
-- app_secrets.admin_emails is pointed at zz.demo.founder@example.invalid before anything is delivered,
-- and the report it delivers is its own ZZ DEMO row, never a real week's.
--
-- WHAT IT ASSERTS
--   1. THE REPLAY: a report with a rendered PDF delivers. The old routine raised
--      'invalid input syntax for type bigint' at exactly this call on 14 and 21 Sep.
--   2. the notification is kind board_report, carries ONE attachment, and founder_mail_policy allows it.
--   3. a report with no PDF answers ok:false WITH a top-level error (what the heartbeat can see).
--   4. fn_ceo_decisions_evaluate: ok, no rule without an evaluator, at least one firing written, every
--      written row carries evidence, and a second run writes nothing (dedupe).
--   5. the evaluator queued nothing to the founder and wrote no founder_alerts row.
--   6. after the rollback: ceo_decision_log and the ZZ DEMO report are exactly as before.
begin;

do $$
declare
  v_id bigint; v_res jsonb; v_nopdf jsonb; v_eval jsonb; v_eval2 jsonb;
  v_kind text; v_natt int; v_allowed boolean; v_ev_bad int; v_written int;
  v_log_before bigint; v_log_after bigint; v_mail_before bigint; v_mail_after bigint;
  v_alert_before bigint; v_alert_after bigint; v_left int; v_fired text;
begin
  set local statement_timeout = '20s';
  select count(*) into v_log_before from public.ceo_decision_log;
  begin
    update public.app_secrets set value = 'zz.demo.founder@example.invalid' where key = 'admin_emails';

    insert into public.ceo_weekly_report (iso_year, iso_week, week_start, week_end, report_key, subject, body, figures, status)
    values (2026, 1, date '2026-01-05', date '2026-01-11', 'zzdemo:probe-weekly', 'ZZ DEMO weekly report',
            E'WHAT IS HOLDING THE COMPANY BACK\nZZ DEMO finding\n--------------------------------------------------\nMONEY\n  Revenue this week   AED 0', '{}'::jsonb, 'generated')
    returning id into v_id;

    -- 3. no PDF yet: refused, visibly
    v_nopdf := public.fn_ceo_weekly_report_deliver(v_id);

    -- 1. the replay
    v_res := public.fn_ceo_weekly_report_attach_pdf(v_id, 'agent-docs', 'ceo/weekly/zzdemo_probe.pdf', null, 1234, null);

    select n.kind, jsonb_array_length(n.attachments) into v_kind, v_natt
      from public.notifications n where n.id = (v_res->>'notification_id')::bigint;
    select allowed_to_email into v_allowed from public.founder_mail_policy where kind = 'board_report';

    -- 4 + 5. the rules, with the founder's mail and alerts counted either side
    select count(*) into v_mail_before from public.notifications where to_role in ('founder','admin','owner');
    select count(*) into v_alert_before from public.founder_alerts;
    v_eval  := public.fn_ceo_decisions_evaluate(false);
    v_eval2 := public.fn_ceo_decisions_evaluate(false);
    select count(*) into v_mail_after from public.notifications where to_role in ('founder','admin','owner');
    select count(*) into v_alert_after from public.founder_alerts;
    select count(*) into v_ev_bad from public.ceo_decision_log
     where dedupe_key is not null and (evidence = '{}'::jsonb or the_decision = '');
    select string_agg(r->>'rule' || '=' || (r->>'firings'), ', ') into v_fired
      from jsonb_array_elements(v_eval->'rules') r where r->>'state' = 'fired';

    raise exception 'ROLLBACK_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_PROBE' then raise; end if;
  end;

  select count(*) into v_log_after from public.ceo_decision_log;
  select count(*) into v_left from public.ceo_weekly_report where report_key = 'zzdemo:probe-weekly';

  if coalesce((v_nopdf->>'ok')::boolean, true) or v_nopdf->>'error' is null then
    raise exception 'a report with no PDF must answer ok:false with a top-level error, got %', v_nopdf;
  end if;
  if not coalesce((v_res->>'ok')::boolean, false) or v_res->>'notification_id' is null then
    raise exception 'THE REPLAY FAILED: delivery with a rendered PDF did not queue: %', v_res;
  end if;
  if v_kind is distinct from 'board_report' or v_natt is distinct from 1 then
    raise exception 'the notification should be kind board_report with one attachment, got kind % attachments %', v_kind, v_natt;
  end if;
  if not coalesce(v_allowed, false) then
    raise exception 'founder_mail_policy does not allow board_report, so the gate would refuse the report';
  end if;
  if not coalesce((v_eval->>'ok')::boolean, false) then
    raise exception 'the evaluator is not ok: %', v_eval->>'error';
  end if;
  if (v_eval->>'written')::int < 1 then
    raise exception 'no rule fired on production data: %', v_eval->'rules';
  end if;
  if (v_eval2->>'written')::int <> 0 then
    raise exception 'a second evaluation wrote % row(s): the dedupe does not hold', v_eval2->>'written';
  end if;
  if v_ev_bad <> 0 then
    raise exception '% written decision row(s) carry no evidence', v_ev_bad;
  end if;
  if v_mail_after <> v_mail_before or v_alert_after <> v_alert_before then
    raise exception 'the evaluator reached the founder: notifications % -> %, founder_alerts % -> %',
      v_mail_before, v_mail_after, v_alert_before, v_alert_after;
  end if;
  if v_log_after <> v_log_before or v_left <> 0 then
    raise exception 'the rollback left rows behind: ceo_decision_log % -> %, ZZ DEMO report %', v_log_before, v_log_after, v_left;
  end if;

  perform set_config('qd.probe_verdict',
    format('PROBE OK replay_delivered notification kind=%s attachments=%s; no_pdf_error="%s"; rules fired: %s (written %s, second run %s); founder mail/alerts unchanged; left_behind=0',
           v_kind, v_natt, v_nopdf->>'error', v_fired, v_eval->>'written', v_eval2->>'written'), true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

commit;

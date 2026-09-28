-- PROBE for the_ceo_issues_directives_and_closes_them_on_their_own_condition.sql. Seat: ceo. Never applied: it always
-- raises CHK<<...>>, which rolls back every row it writes. Its subjects are ZZ DEMO directives whose done-condition
-- reads a ZZ DEMO ceo_task title; it sends nothing (it does not call the daily run, and it asserts no notification row).
--   A: issued, condition false -> stays open; condition made true -> the loop closes it 'met' with the evidence.
--   B: issued 2 days ago, deadline passed -> escalated ONCE (one re-issue, one decision-log row); a second run does not
--      escalate again; past the re-issue's deadline -> 'missed' with a CEO task, and still exactly one re-issue.
do $probe$
declare r0 jsonb; a bigint; b bigint; b2 bigint; x bigint; n_notif bigint; v_first text;
  a_open_1 text; a_status text; a_evidence boolean; b_status text; n_reissue int; n_decision int; b2_status text;
  n_reissue_after int; b2_task boolean; idem boolean; n_notif_after bigint;
begin
  select count(*) into n_notif from public.notifications;
  r0 := public.fn_ceo_directive_run(now());   -- the real signals, rolled back with everything else

  a := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'ZZ DEMO:A', 'ZZ DEMO directive A.',
         'a ceo_task titled ZZ DEMO A done exists.', $q$exists (select 1 from public.ceo_task where title = 'ZZ DEMO A done')$q$,
         now() + interval '1 day', '{"demo":true}');
  perform public.fn_ceo_directive_run(now());
  select status into a_open_1 from public.ceo_directive where id = a;
  perform public.fn_ceo_task_open('ZZ DEMO A done', 'probe');
  perform public.fn_ceo_directive_run(now());
  select status, (evidence->'closed'->>'result')::boolean into a_status, a_evidence from public.ceo_directive where id = a;

  b := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'ZZ DEMO:B', 'ZZ DEMO directive B.',
         'a ceo_task titled ZZ DEMO B done exists.', $q$exists (select 1 from public.ceo_task where title = 'ZZ DEMO B done')$q$,
         now() - interval '1 hour', '{"demo":true}');
  update public.ceo_directive set issued_at = now() - interval '2 days' where id = b;
  x := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'ZZ DEMO:B', 'dup', 'dup', 'true', now(), '{}');
  idem := x is null;
  perform public.fn_ceo_directive_run(now());
  perform public.fn_ceo_directive_run(now());          -- a second run must not escalate again
  select status into b_status from public.ceo_directive where id = b;
  select id into b2 from public.ceo_directive where escalated_from = b;
  select count(*) into n_reissue from public.ceo_directive where escalated_from = b;
  select count(*) into n_decision from public.ceo_decision_log where dedupe_key = 'ceo_directive_escalation:' || b;
  select format('Directive #%s', d.id) into v_first from public.ceo_directive d
   where d.seat = 'marketing' and d.status = 'open' order by d.deadline, d.id limit 1;

  perform public.fn_ceo_directive_run(now() + interval '3 days');
  select status, (evidence->'missed'->>'task_id') is not null into b2_status, b2_task from public.ceo_directive where id = b2;
  select count(*) into n_reissue_after from public.ceo_directive where source_ref = 'ZZ DEMO:B';
  select count(*) into n_notif_after from public.notifications;

  raise exception 'CHK<<real_run=% a_first=% a_after=% a_evidence=% idempotent=% b=% reissues=% decisions=% top_priority=% b2_after_deadline=% b2_task=% rows_for_B=% notifications_delta=% verdict=%>>',
    r0, a_open_1, a_status, a_evidence, idem, b_status, n_reissue, n_decision, v_first, b2_status, b2_task, n_reissue_after,
    n_notif_after - n_notif,
    case when a_open_1 = 'open' and a_status = 'met' and a_evidence and idem and b_status = 'escalated' and n_reissue = 1
              and n_decision = 1 and b2_status = 'missed' and b2_task and n_reissue_after = 2 and n_notif_after = n_notif
         then 'PROBE OK' else 'PROBE FAILED' end;
end $probe$;

-- ---------------------------------------------------------------------------------------------
-- THE LAST FOUR SURFACES THAT WERE STILL SHOWING CLEARED WORK.
--
-- The founder: "escalations log is still there while i asked you to clear it totally... approval
-- requests are still there." He was right, and the reason is that fn_ws_exec and fn_os_command
-- were never patched with the rest — the earlier work covered five surfaces and these feed four
-- more:
--
--   fn_ws_exec -> approvals      agent_actions where status='pending'      — the approval requests
--   fn_ws_exec -> tasks          crm_tasks with NO status filter at all    — cancelled rows shown
--   fn_ws_exec -> notifications  newest 6, no filter                       — the notification list
--   fn_os_command -> attention   decision_log, route_to <> 'auto'          — "the escalations log"
--   fn_ws_exec -> activity       decision_log, newest 10                   — the activity feed
--
-- Two different faults, fixed differently and deliberately:
--
-- 1. THE QUEUES ARE NOW EMPTY AND THE SCREENS DID NOT FILTER. crm_tasks ordered by
--    "is it done" and showed everything else regardless of status, so six cancelled tasks were
--    still on the console. approvals asked for status='pending' and is correct by construction —
--    it reads zero now that nothing is pending. Both get an explicit terminal-state filter so a
--    cancelled row can never present as work again.
--
-- 2. decision_log CANNOT BE CLEARED. Trigger declog_immutable raises on DELETE and on UPDATE, and
--    721 agent_actions rows point at it through a foreign key with no ON DELETE action. It is the
--    company's decision record and it is append-only on purpose. The rows stay; the surfaces read
--    forward from the fresh-start watermark. This is the one part of "clear it totally" that is
--    answered by hiding rather than removing, and it is said plainly here rather than glossed:
--    1,862 decision records still exist and are still queryable, they are simply no longer on his
--    screen.
--
-- The notification list gets the watermark too, rather than a delete, because 18 routines use
-- public.notifications as their own send-dedupe — emptying it re-sends real mail to real customers.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ws_exec()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'command', fn_os_command(),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'status',status,'priority',priority,'due',due_date,'entity',entity)) from (select * from crm_tasks where coalesce(status,'') not in ('done','cancelled') and created_at >= fn_os_fresh_start_at() order by created_at desc limit 8) t),'[]'::jsonb),
    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'title',title,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'risk',risk,'status',status,'created_at',created_at)) from (select * from agent_actions where status='pending' and created_at >= fn_os_fresh_start_at() order by created_at desc limit 6) a),'[]'::jsonb),
    'activity', coalesce((select jsonb_agg(jsonb_build_object('actor',actor,'kind',kind,'kind_label',fn_ui_label('action_kind',kind),'decision',decision,'confidence',confidence,'route_to',route_to,'created_at',created_at)) from (select * from decision_log where created_at >= fn_os_fresh_start_at() order by created_at desc limit 10) d),'[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(jsonb_build_object('type',type,'type_label',fn_ui_label('notification_type',type),'subject',subject,'status',status,'created_at',created_at)) from (select * from notifications where created_at >= fn_os_fresh_start_at() order by created_at desc limit 6) n),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_os_command()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_health jsonb; v_ops jsonb; v_counts jsonb; v_attention jsonb; v_pipeline jsonb;
begin
  v_health := to_jsonb(fn_health_index());
  v_ops    := to_jsonb(fn_ops_dashboard());

  select jsonb_build_object(
    'suppliers_total', (select count(*) from leads),
    'rfqs_total',      (select count(*) from inquiries),
    'rfqs_active',     (select count(*) from inquiries where status = 'quoted'),
    'rfqs_revealed',   (select count(*) from inquiries where status = 'revealed'),
    'rfqs_cancelled',  (select count(*) from inquiries where status = 'cancelled'),
    'quotes_total',    (select count(*) from quotes),
    'decisions_7d',    (select count(*) from decision_log where created_at > now() - interval '7 days'),
    'decisions_24h',   (select count(*) from decision_log where created_at > now() - interval '24 hours')
  ) into v_counts;

  select jsonb_build_object(
    'sent',      (select count(*) from inquiries where status = 'sent' and parent_inquiry_id is null),
    'matched',   (select count(distinct im.inquiry_id) from inquiry_matches im join inquiries i on i.id = im.inquiry_id where i.status = 'sent'),
    'quoted',    (select count(*) from inquiries where status = 'quoted'),
    'revealed',  (select count(*) from inquiries where status = 'revealed'),
    'completed', (select count(*) from inquiries where status in ('completed','won'))
  ) into v_pipeline;

  -- THE ESCALATIONS LOG. decision_log is append-only by trigger and carries 721 dependent rows, so
  -- it cannot be emptied; this reads forward from the fresh-start watermark instead. The records
  -- are all still there and still queryable — they are off the founder's screen, not gone.
  select coalesce(jsonb_agg(x order by created_at desc), '[]'::jsonb) into v_attention
  from (
    select id, actor, kind, decision, confidence, route_to, created_at,
           jsonb_build_object('id', id, 'actor', actor, 'kind', kind,
             'kind_label', public.fn_ui_label('action_kind', kind), 'decision', decision,
             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,
             'os', public.fn_owning_os(actor),
             'reasons', reasons,
             'alternatives', alternatives,
             'outcome', case when exists (select 1 from public.agent_actions a where a.decision_log_id = decision_log.id)
                  then (select coalesce(a.status,'recorded') || ' — ' || coalesce(a.title,'action taken')
                          from public.agent_actions a where a.decision_log_id = decision_log.id
                         order by a.created_at desc limit 1)
                  else 'held for ' || coalesce(route_to,'review') || ', no follow-up action recorded since ' || created_at::date end
           ) as x
    from decision_log
    where route_to is not null and route_to <> 'auto'
      and created_at >= public.fn_os_fresh_start_at()
      -- HELD FOR REVIEW MEANS SOMETHING IS STILL WAITING ON A HUMAN. This card had no such test:
      -- it listed every routed decision, so a decision whose action had been cancelled or already
      -- decided still sat under the heading "held for review". The founder found one this way
      -- immediately after the stand-down - decision_log 2627, the audit trail of the same
      -- agent_action the stand-down had cancelled at the same microsecond.
      --
      -- decision_log is append-only by trigger, so the row cannot be edited or removed and should
      -- not be: it is the record that the gate ran. What was wrong is the claim made about it.
      -- A decision is held only while its action is open; a decision that never produced an action
      -- was never queued for anyone and does not belong on a review list either.
      and exists (select 1 from public.agent_actions a
                   where a.decision_log_id = decision_log.id
                     and a.status in ('pending','needs_review'))
    order by created_at desc limit 8
  ) z;

  return jsonb_build_object(
    'health', v_health, 'health_index', v_health->>'index',
    'ops', v_ops, 'counts', v_counts, 'pipeline', v_pipeline,
    'attention', v_attention, 'generated_at', now());
end $function$;

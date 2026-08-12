-- operations_ai now says how each of its six alerts is wrong — 12 Aug 2026
--
-- Third in the s36 sequence, after a_recommendation_that_cannot_say_what_it_assumed.sql (columns +
-- the thirteen call sites in agents/index.ts) and the_five_wrappers_that_could_not_carry_a_reason.sql
-- (ops_rec and its four siblings widened to accept a reason).
--
-- Six rules, six sets of assumptions, and every one of them names a specific way THIS alert is wrong
-- when it is wrong. That is the point of the field. "We assume the data is correct" would be a
-- default wearing an assumption's clothes; "response_rate_pct divides by RFQs that were actually
-- dispatched, so a dispatch that reached nobody never enters the denominator" is a statement someone
-- can check, and it is true of this metric and not of the other five.
--
-- Nothing else about the routine changes: the health score, the snapshot upsert and the return shape
-- are byte-identical to what was running.

create or replace function public.fn_operations_ai()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare k record; v_health numeric; n int;
begin
  select * into k from ops_kpis;
  v_health := round(greatest(0, 100
    - least(30, coalesce(k.no_quote_backlog,0)*3)
    - (case when coalesce(k.avg_first_quote_hours,0) > 72 then 20 when coalesce(k.avg_first_quote_hours,0) > 48 then 10 else 0 end)
    - (case when coalesce(k.response_rate_pct,100) < 40 then 15 when coalesce(k.response_rate_pct,100) < 60 then 7 else 0 end)
    - least(15, coalesce(k.overdue_tasks,0)*3)
    - coalesce(k.cron_failures_24h,0)*4
    - least(10, coalesce(k.agent_errors_24h,0)*2)
    - (case when coalesce(k.high_risk_pending,0) > 5 then 8 else 0 end)),1);

  insert into ops_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('ops_health',v_health))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  perform ops_rec('no_quote_backlog', coalesce(k.no_quote_backlog,0) > 0, 'medium', 'Inquiries stuck without quotes',
    k.no_quote_backlog||' inquir(y/ies) older than 7 days have no quotes — a supply/response bottleneck. Chase matched suppliers or onboard supply in those categories.',
    jsonb_build_array(
      'These RFQs reached at least one supplier. An RFQ that fanned out to zero suppliers is not a response problem at all, and until fn_rfq_redispatch_sweep shipped today it would have sat here forever looking like one.',
      'Seven days without a quote means the suppliers declined or ignored it, not that they quoted outside the platform and the customer never told us.',
      'The backlog count is of inquiries, not of customers: one buyer with five open RFQs looks like five bottlenecks.'),
    'Clearing '||coalesce(k.no_quote_backlog,0)||' stuck RFQ(s) is the shortest path to revenue on this board — each one is a customer who asked and is still waiting, and a reveal is the only event that earns.',
    'No spend. Chasing costs outreach time; the alternative, onboarding supply in those categories, is free from the existing lead base and gated on invite_enabled.');

  perform ops_rec('slow_first_quote', coalesce(k.avg_first_quote_hours,0) > 48, 'medium', 'First quotes are slow',
    'First quotes are averaging '||coalesce(k.avg_first_quote_hours,0)||' hours. Tighten supplier response SLAs / nudges to speed the funnel.',
    jsonb_build_array(
      'The mean is meaningful at this volume. With very few quoted RFQs a single slow outlier moves this average by hours and would raise this alert on its own.',
      'The clock starts when the RFQ was dispatched, so a supplier who was notified late is counted as a supplier who replied slowly.',
      'Suppliers are being measured on hours that include nights and weekends, which no UAE contractor works.'),
    'Every hour cut from the first-quote wait is a buyer less likely to go elsewhere; the first quote is the moment an RFQ stops feeling like it went nowhere.',
    'No spend. Nudges cost supplier goodwill if the SLA is unrealistic, which is why the assumption about nights and weekends above matters before tightening anything.');

  perform ops_rec('low_response_rate', coalesce(k.response_rate_pct,100) < 60, 'medium', 'Supplier response rate is low',
    'Supplier response rate is '||coalesce(k.response_rate_pct,0)||'%. Improve matching quality and supplier enablement.',
    jsonb_build_array(
      'The denominator is RFQs actually dispatched to a supplier. A dispatch that reached nobody never enters it, so this rate describes matched suppliers only and says nothing about coverage.',
      'A non-response is a decision not to quote, not a supplier who never saw the RFQ — undelivered mail would read identically here.',
      'The matcher put the right trade in front of them: a bad match produces a silent supplier who was right to stay silent.'),
    'Response rate is the clearest read on whether the matcher is sending the right work to the right companies. Fixing it lifts every RFQ in every category at once, not one queue.',
    'No spend. Supplier enablement is outreach time; improving matching is engineering time against fn_match_capability.');

  perform ops_rec('approvals_backlog', coalesce(k.pending_approvals,0) > 15, 'low', 'Approval queue building up',
    k.pending_approvals||' items are awaiting your decision ('||coalesce(k.high_risk_pending,0)||' high-risk). Clear the queue so the agents can proceed.',
    jsonb_build_array(
      'Every pending item is genuinely blocked on a human. An item left pending because nothing consumes that kind would look identical and would not move if you decided it.',
      'The '||coalesce(k.high_risk_pending,0)||' high-risk item(s) carry a risk level set by the routine that raised them, which is a self-assessment and not an audit.',
      'The queue is a founder queue: none of these can be cleared by another agent, or they would already have been.'),
    'Each decision unblocks whatever the raising agent wanted to do next. A queue this size is the company waiting on one person, which is the thing the whole design is meant to avoid.',
    'No spend. Founder attention, which is the scarcest resource here and the reason the queue is worth keeping short.');

  perform ops_rec('overdue_tasks', coalesce(k.overdue_tasks,0) > 0, 'low', 'Overdue tasks',
    k.overdue_tasks||' task(s) are past due. Reschedule or action them.',
    jsonb_build_array(
      'The due dates were set deliberately. A task auto-dated by the routine that created it is overdue against a guess, not against a commitment.',
      'These tasks have an owner who could act. org_tasks.assigned_agent had no writer at all until 12 Aug, so anything created before then may be overdue and ownerless — a scheduling problem masking a staffing one.'),
    'Rescheduling honestly is worth as much as finishing: a due date nobody believes makes every other due date meaningless, and this counter is what the health score reads.',
    'No spend. The real cost is that clearing overdue tasks by moving dates, rather than by doing them, hides the department that is short-staffed.');

  perform ops_rec('automation_failures', coalesce(k.cron_failures_24h,0) > 0 or coalesce(k.agent_errors_24h,0) > 5, 'high', 'Automation failures detected',
    coalesce(k.cron_failures_24h,0)||' scheduled-job failure(s) and '||coalesce(k.agent_errors_24h,0)||' agent error(s) in 24h. Investigate the failing jobs.',
    jsonb_build_array(
      'agent_runs status=error means a fault. Several routines here write status=error to record a real-world FINDING they were built to report, so a healthy watcher doing its job inflates this count.',
      'The window is the last 24 hours, so a fault repaired hours ago is still counted; read the timestamps before investigating.',
      'A cron failure is the job failing, not the job being absent. A schedule that was never created cannot fail and so cannot appear here at all — which is the more dangerous state.'),
    'Each failing job is something the company does without being asked. Left failing, that work silently stops and this counter is the only place it shows.',
    'No spend. Engineering attention; the diagnosis is usually one note in agent_runs.');

  select count(*) into n from agent_actions where agent='operations_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'ops_health',v_health,'kpis',to_jsonb(k),'open_recommendations',n);
end $function$;

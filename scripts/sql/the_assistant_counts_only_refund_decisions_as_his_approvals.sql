-- THE ASSISTANT COUNTS ONLY REFUND DECISIONS AS HIS APPROVALS (6 Sep 2026, OS walk after PR #524).
--
-- Measured in the founder's own browser at 14:20 UTC: the Assistant module said "Approvals 3" and listed
-- three rows under "Approvals awaiting you" — two legal_flag actions held with general_counsel and one
-- incident held with the operations director. In the same minute Operations showed the same three rows
-- under "Held with departments — not yours to approve", Escalations showed "Nothing awaiting a reply",
-- the founder queue said "Nothing is waiting on you", and the drawer for each row (correctly) offered no
-- Approve/Reject. One surface was counting raw status as his approvals — the pattern PR #521 removed from
-- the other surfaces: fn_ea_agenda's approvals_to_clear was every agent_action in pending/needs_review,
-- whoever held it. By 14:38 UTC the three had moved to 'notified' on their own and the count read 0, which
-- is why the definition, not today's number, is what this file changes.
--
-- Founder, verbatim: "nothing routes to my approval except refunds". fn_founder_queue is the one routine
-- that knows what is his (a pending founder_approval_request — refund_decision is the only action class
-- the two triggers on that table admit — or an agent_action whose kind policy is 'founder', of which none
-- exists today). approvals_to_clear now reads from it: total = waiting_on_you_total, top = waiting_on_you.
-- Every item in that queue is money leaving the Stripe account, so high_risk = total. The seven other
-- keys of the agenda are unchanged.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/the_assistant_counts_only_refund_decisions_as_his_approvals.sql --apply
-- Prove:  select fn_ea_agenda(7)->'approvals_to_clear'  ->  total = (fn_founder_queue()->>'waiting_on_you_total')::int
--         and, with an agent_action parked in 'pending' inside an aborted transaction, still 0.

CREATE OR REPLACE FUNCTION public.fn_ea_agenda(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'as_of', now(),
    'today', jsonb_build_object(
      'events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location,'attendees',attendees) order by starts_at)
          from ea_events where status='scheduled' and coalesce(starts_at, now())::date = current_date),'[]'::jsonb),
      'reminders_due', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'remind_at',remind_at) order by remind_at)
          from ea_reminders where not done and remind_at <= now()+interval '1 day'),'[]'::jsonb)
    ),
    'upcoming_events', coalesce((select jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'starts_at',starts_at,'location',location) order by starts_at)
        from ea_events where status='scheduled' and starts_at > current_date and starts_at <= (current_date + (p_days||' days')::interval)),'[]'::jsonb),
    'open_tasks', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'priority',priority,'due',due_date,'source',source) order by (due_date is null), due_date)
        from (select * from crm_tasks where coalesce(status,'open') not in ('done','cancelled') order by (due_date is null), due_date limit 15) t),'[]'::jsonb),
    'overdue_tasks', (select count(*) from crm_tasks where coalesce(status,'open') not in ('done','cancelled') and due_date < now()),
    -- HIS, AND ONLY HIS. fn_founder_queue is the one reader of what waits on the founder (a refund decision);
    -- an agent_action held with a department is that department's and is never counted here again.
    'approvals_to_clear', (
      select jsonb_build_object(
        'total', coalesce((q->>'waiting_on_you_total')::int, 0),
        'high_risk', coalesce((q->>'waiting_on_you_total')::int, 0),
        'top', coalesce((select jsonb_agg(jsonb_build_object(
                 'agent', y->>'from', 'title', y->>'title', 'risk', 'money', 'kind', y->>'kind',
                 'reason', coalesce(y->>'kind_label', 'Refund decision') || ' — the only decision that is yours',
                 'os', 'finance', 'source', y->>'source', 'subject_ref', y->>'subject_ref',
                 'raised', y->'raised', 'age_days', y->'age_days',
                 'outcome', 'waiting on you since ' || left(coalesce(y->>'raised', ''), 10)))
               from jsonb_array_elements(coalesce(q->'waiting_on_you', '[]'::jsonb)) y), '[]'::jsonb))
      from (select public.fn_founder_queue(8) q) fq
    ),
    'recent_meetings', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'meeting_at',meeting_at,'summary',left(summary,240)) order by meeting_at desc)
        from (select * from ea_meetings order by meeting_at desc limit 5) m),'[]'::jsonb)
  );
$function$;

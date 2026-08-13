-- HOW MANY SUPPLIERS CAN ACTUALLY RECEIVE AN RFQ TODAY — a number that was on no screen.
--
-- MEASURED ON PRODUCTION, 13 Aug 2026, after a customer typed a trade into the portal's supplier
-- finder and got zero:
--
--   supplier_capabilities            15,306 rows, EVERY ONE carrying trades (1,275 on flooring)
--   ... with confirmed_at set             1
--
-- fn_match_capability gates on `sc.confirmed_at is not null` — deliberately, because matching an
-- unconfirmed scope would put a customer's RFQ in front of a supplier who never said they do the
-- work. route_inquiry takes that path whenever a capability requirement exists and, on zero
-- candidates, refuses to fall back to keyword retrieval: it logs "a real coverage gap" and contacts
-- nobody. Also deliberate, and reasoned in the code.
--
-- The consequence is the thing nobody could see: THE STRUCTURED MATCHER CAN SHORTLIST AT MOST ONE
-- SUPPLIER for any query in today's database. Not because the estate is small — 20,470 leads,
-- 15,306 with capability data — but because one supplier has confirmed their own scope.
--
-- WHY THAT DISTINCTION IS THE WHOLE POINT. "No supplier matches that" reads as *we need more
-- suppliers*, which is the most expensive possible response and the one that restarts scraping.
-- "15,306 hold capability data and one has confirmed" reads as *chase confirmations*, which is a
-- different job, far cheaper, and the correct one. A count without its reason sends you to the
-- wrong budget.
--
-- The customer-facing side of this now says it too (PR #317). This puts the same fact on System
-- Health, where the founder looks, instead of leaving it derivable only by someone who thinks to
-- run the query.
--
-- NOTHING IS GATED, WIDENED OR WEAKENED HERE. This is a read-only addition to a read-only routine.
--
--   node scripts/apply_sql.mjs scripts/sql/the_number_that_gates_every_rfq_was_on_no_screen.sql --promote

create or replace function public.fn_os_health()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
DECLARE res jsonb;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'failing_crons', coalesce((
      SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'status', lr.status, 'when', lr.end_time,
                                          'message', left(coalesce(lr.return_message,''),160))
                       ORDER BY lr.end_time DESC)
      FROM (SELECT DISTINCT ON (jobid) jobid, status, end_time, return_message
              FROM cron.job_run_details
             WHERE start_time > now() - interval '7 days'
             ORDER BY jobid, start_time DESC) lr
      JOIN cron.job j ON j.jobid = lr.jobid
      WHERE lr.status = 'failed' AND lr.end_time > now() - interval '24 hours'
    ), '[]'::jsonb),
    'agent_errors_24h', (SELECT count(*) FROM public.agent_runs WHERE status='error' AND started_at > now() - interval '24 hours'),
    'top_error_agents', coalesce((SELECT jsonb_agg(x) FROM (SELECT jsonb_build_object('agent',agent,'errors',count(*)) x FROM public.agent_runs WHERE status='error' AND started_at > now()-interval '24 hours' GROUP BY agent ORDER BY count(*) DESC LIMIT 6) q),'[]'::jsonb),
    'health_check_fails_24h', (SELECT count(*) FROM public.health_checks WHERE ok=false AND created_at > now()-interval '24 hours'),
    'ai_health_fails', coalesce((SELECT value FROM public.app_secrets WHERE key='ai_health_fails'),'0'),
    'payments_7d_count', (SELECT count(*) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),
    'payments_7d_revenue_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),0),
    -- CAN A REQUEST REACH ANYONE? Each number is counted at the gate it actually has to pass, so
    -- the drop between them says WHERE the reach is lost rather than only that it is small.
    'supplier_reach', jsonb_build_object(
      'leads', (SELECT count(*) FROM public.leads),
      'with_capability', (SELECT count(*) FROM public.supplier_capabilities WHERE coalesce(cardinality(trades),0) > 0),
      'confirmed', (SELECT count(*) FROM public.supplier_capabilities WHERE confirmed_at IS NOT NULL),
      -- the real ceiling: confirmed AND the lead itself still admissible to matching
      'matchable_now', (
        SELECT count(*) FROM public.supplier_capabilities sc
        JOIN public.leads l ON l.id = sc.supplier_id
        WHERE sc.confirmed_at IS NOT NULL
          AND coalesce(cardinality(sc.trades),0) > 0
          AND public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                     l.approval_status, l.permanently_closed, l.chat_strikes)),
      'meaning', 'matchable_now is the most suppliers the structured matcher can shortlist for any request. fn_match_capability requires a supplier to have CONFIRMED their own scope; that gate is deliberate. When this is far below with_capability the shortage is confirmations, not suppliers.'
    )
  ) INTO res;
  RETURN res;
END
$function$;

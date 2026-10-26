-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725003301   name: phase4_health_reconcile
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- Phase 4 Epic E4: one plain-language system-health snapshot.
CREATE OR REPLACE FUNCTION public.fn_os_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'failing_crons', coalesce((
      SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'status', lr.status, 'when', lr.end_time, 'message', left(coalesce(lr.return_message,''),160)) ORDER BY lr.end_time DESC)
      FROM cron.job j
      JOIN LATERAL (SELECT status, end_time, return_message FROM cron.job_run_details d WHERE d.jobid=j.jobid ORDER BY d.start_time DESC LIMIT 1) lr ON true
      WHERE lr.status = 'failed' AND lr.end_time > now() - interval '24 hours'
    ), '[]'::jsonb),
    'agent_errors_24h', (SELECT count(*) FROM public.agent_runs WHERE status='error' AND started_at > now() - interval '24 hours'),
    'top_error_agents', coalesce((SELECT jsonb_agg(x) FROM (SELECT jsonb_build_object('agent',agent,'errors',count(*)) x FROM public.agent_runs WHERE status='error' AND started_at > now()-interval '24 hours' GROUP BY agent ORDER BY count(*) DESC LIMIT 6) q),'[]'::jsonb),
    'health_check_fails_24h', (SELECT count(*) FROM public.health_checks WHERE ok=false AND created_at > now()-interval '24 hours'),
    'ai_health_fails', coalesce((SELECT value FROM public.app_secrets WHERE key='ai_health_fails'),'0'),
    'payments_7d_count', (SELECT count(*) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),
    'payments_7d_revenue_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),0)
  ) INTO res;
  res := res || jsonb_build_object('overall',
    CASE WHEN jsonb_array_length(res->'failing_crons') > 0 OR (res->>'agent_errors_24h')::int > 25 THEN 'attention' ELSE 'healthy' END);
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.fn_os_health() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_health() TO service_role;

-- Phase 4 Epic E3: money reconciliation snapshot (payments vs Stripe events vs GL).
CREATE OR REPLACE FUNCTION public.fn_os_reconcile()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res jsonb; gl_diff numeric;
BEGIN
  BEGIN SELECT coalesce(sum(debit),0) - coalesce(sum(credit),0) INTO gl_diff FROM public.gl_journal_lines;
  EXCEPTION WHEN others THEN gl_diff := NULL; END;
  SELECT jsonb_build_object(
    'generated_at', now(),
    'transactions_total', (SELECT count(*) FROM public.transactions),
    'revenue_reveal_fees_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions),0),
    'refunds_pending', (SELECT count(*) FROM public.transactions WHERE refund_status='requested'),
    'refunds_resolved', (SELECT count(*) FROM public.transactions WHERE refund_status IS NOT NULL AND refund_status <> 'requested'),
    'stripe_events_total', (SELECT count(*) FROM public.stripe_events),
    'stripe_paid_checkouts', (SELECT count(*) FROM public.stripe_events WHERE type='checkout.session.completed' AND payment_status='paid'),
    'gl_debits_minus_credits', CASE WHEN gl_diff IS NULL THEN NULL ELSE round(gl_diff,2) END,
    'gl_balanced', CASE WHEN gl_diff IS NULL THEN NULL ELSE (abs(gl_diff) < 0.01) END
  ) INTO res;
  RETURN res;
END $$;
REVOKE ALL ON FUNCTION public.fn_os_reconcile() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_os_reconcile() TO service_role;


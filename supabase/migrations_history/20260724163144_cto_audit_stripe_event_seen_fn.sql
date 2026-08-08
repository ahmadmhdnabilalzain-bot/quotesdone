-- CTO AUDIT HARDENING — Stripe event ledger writer.
-- Applied to project htdblwldjkcgjvmqkbeh (suppliers DB) on 2026-07-24 via MCP apply_migration.

CREATE OR REPLACE FUNCTION public.fn_stripe_event_seen(p_event_id text, p_type text, p_status text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.stripe_events (event_id, type, payment_status)
  VALUES (p_event_id, p_type, p_status)
  ON CONFLICT (event_id) DO UPDATE
    SET last_seen_at = now(),
        delivery_count = public.stripe_events.delivery_count + 1;
$$;
REVOKE ALL ON FUNCTION public.fn_stripe_event_seen(text, text, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_event_seen(text, text, text) TO service_role;

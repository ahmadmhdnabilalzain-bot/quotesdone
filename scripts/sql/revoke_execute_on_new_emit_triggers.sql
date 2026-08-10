-- Self-inflicted and caught in the same session. Postgres grants EXECUTE to PUBLIC on every new
-- function, so the four SECURITY DEFINER trigger functions added for the event emitters took
-- production's anon_security_definer_function_executable count from 63 to 67 — the one number in
-- the daily security alert that is genuinely about public exposure, and the one the founder is
-- being asked to work through caller by caller.
--
-- A trigger function is invoked by the trigger system as the table owner. Nothing needs to call
-- these by name, so nothing loses anything.
revoke execute on function public.fn_emit_customer_registered() from public, anon, authenticated;
revoke execute on function public.fn_emit_supplier_approved() from public, anon, authenticated;
revoke execute on function public.fn_emit_campaign_launched() from public, anon, authenticated;
revoke execute on function public.fn_emit_competitor_pricing_changed() from public, anon, authenticated;

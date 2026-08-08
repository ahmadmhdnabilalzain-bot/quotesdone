-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722144103   name: os_audit_h17_normalize_founder_alert_level
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H17: 'crit' is a synonym for 'critical', but every founder-facing consumer filters level='critical',
-- so 97 'crit' rows (e.g. policy-contradiction alerts) were excluded from the founder's critical count
-- and the email/WhatsApp bridge. Normalize existing rows and enforce it forward with a trigger.
UPDATE public.founder_alerts SET level = 'critical' WHERE lower(level) = 'crit';

CREATE OR REPLACE FUNCTION public.fn_normalize_founder_alert_level()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
BEGIN
  IF lower(coalesce(NEW.level,'')) = 'crit' THEN NEW.level := 'critical'; END IF;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_normalize_founder_alert_level ON public.founder_alerts;
CREATE TRIGGER trg_normalize_founder_alert_level
  BEFORE INSERT OR UPDATE ON public.founder_alerts
  FOR EACH ROW EXECUTE FUNCTION public.fn_normalize_founder_alert_level();

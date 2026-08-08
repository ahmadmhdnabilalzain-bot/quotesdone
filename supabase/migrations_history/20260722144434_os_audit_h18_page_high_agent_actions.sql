-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722144434   name: os_audit_h18_page_high_agent_actions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H18: HIGH/CRITICAL findings from the finance/security/operations C-suite were inserted only as
-- agent_actions (queue-only), reaching the founder at best in the next daily digest. Page them in real time.
-- Scoped to the three agents that don't already self-notify (legal_ai/collections self-notifies, so excluded),
-- with 24h dedupe, so it fills the gap without double-emailing.
CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $fn$
DECLARE v_founder text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     AND NEW.agent IN ('finance_ai','security_ai','operations_ai')
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_page_high_agent_action ON public.agent_actions;
CREATE TRIGGER trg_page_high_agent_action
  AFTER INSERT ON public.agent_actions
  FOR EACH ROW EXECUTE FUNCTION public.fn_page_high_agent_action();

-- DOWN. RE-GRANT INSERT, UPDATE, DELETE, REFERENCES AND TRIGGER ON THE GOVERNANCE LEDGER.
--
-- NO TRANSACTION CONTROL. One statement.
--
-- APPLYING THIS RESTORES THE STATE PCCR-006 LEFT: service_role -- the role every edge function and
-- every service-key script runs as -- can INSERT, UPDATE and DELETE rows in the append-only
-- governance decision ledger at the grant level again. a00_phase_c_governance_decision_is_session_
-- backed still refuses each of those at the trigger level, so this reverts defence in depth rather
-- than opening the door; it exists so the change is reversible, not because reverting is advisable.

GRANT INSERT, UPDATE, DELETE, REFERENCES, TRIGGER ON public.phase_c_governance_decision TO service_role;

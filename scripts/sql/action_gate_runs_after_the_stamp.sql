-- THE FIX EARLIER TODAY WAS CORRECT AND STILL WROTE NULL, BECAUSE OF TRIGGER ORDER.
--
-- action_gate_records_confidence.sql changed trg_action_gate to write NEW.confidence into
-- decision_log instead of a literal null. Probed in an aborted transaction, it worked:
--   PROBE action=2672 decision_log=1549 dl_confidence=0.77
-- and it still wrote null on real traffic:
--   agent_actions 2674  confidence 0.9   ->  decision_log 1552  confidence NULL   (10:20 UTC)
--
-- The probe passed because it supplied a confidence in the INSERT. Production callers do not.
--
-- POSTGRES FIRES BEFORE TRIGGERS IN NAME ORDER, and on agent_actions that order is:
--   a00_agent_action_resolve_addressee
--   action_gate               <- reads NEW.confidence, still NULL here
--   trg_dedupe_it_incident
--   trg_governance_stamp      <- "if NEW.confidence is null then NEW.confidence := 0.9"
--
-- So the 0.9 that sits on all 1,337 agent_actions is the STAMP, and the gate had already written
-- its ledger row before the stamp existed. That is the whole reason decision_log carried a
-- confidence on 12 of 1,390 rows while agent_actions carried one on 1,337 of 1,337: the two
-- numbers were never the same number at the same moment.
--
-- The gate therefore has to run LAST, not first. Renaming it is the mechanism the codebase already
-- uses for exactly this — the a00_ prefix on the addressee trigger exists to force it first.
--
-- RUNNING LAST IS ALSO CORRECT ON ITS OWN TERMS, not just convenient:
--   * it sees the final status, escalated flag and escalation_reason, rather than a half-built row;
--   * dedupe_it_incident runs before it, so an action that is deduped away no longer leaves a
--     decision_log row behind claiming a decision was taken about it.
-- Nothing downstream depends on the gate running early: it only sets NEW.status and
-- NEW.decision_log_id, and no earlier trigger reads either.
--
-- The trigger FUNCTION is unchanged. This is ordering only.
drop trigger if exists action_gate on public.agent_actions;
create trigger zzz_action_gate
  before insert on public.agent_actions
  for each row execute function public.trg_action_gate();

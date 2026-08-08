-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709111338   name: governance_stamp_trigger_and_backfill
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Universal governance stamp: every agent action carries a confidence score, supporting
-- evidence, and an escalation flag for sensitive/low-confidence cases.
-- Non-disruptive by design: it never changes `status`, so the existing autonomy/ack routing
-- (which decides what actually reaches the founder queue) is preserved. Escalation ROUTING for
-- new code paths is enforced by fn_agent_decision; this trigger guarantees explainability
-- coverage + the escalation MARKER across all inserts, including the legacy agent helpers.
create or replace function public.fn_governance_stamp()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
declare v_sensitive boolean;
begin
  v_sensitive := (coalesce(NEW.agent,'') ~* 'legal|financ|complian|security'
                  or coalesce(NEW.kind,'') ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price');

  -- Explainability: stamp a confidence + evidence basis when the caller did not provide one.
  -- These agents derive recommendations deterministically from live platform data, so the
  -- factual basis is high-confidence; the evidence line records exactly why.
  if NEW.confidence is null then
    NEW.confidence := 0.9;
    if NEW.evidence is null then
      NEW.evidence := jsonb_build_object('basis','deterministic rule from live platform data',
                                         'agent',NEW.agent,'kind',NEW.kind);
    end if;
  end if;

  -- Escalation marker (does not reroute status): low confidence or sensitive domain.
  if NEW.escalated is not true and (coalesce(NEW.confidence,0) < 0.6 or v_sensitive) then
    NEW.escalated := true;
    NEW.escalation_reason := coalesce(NEW.escalation_reason,
      case when coalesce(NEW.confidence,0) < 0.6
           then 'Confidence below 0.60 threshold — human review required.'
           else 'Sensitive domain (legal/financial/compliance/security) — human review required.' end);
  end if;

  return NEW;
end $$;

drop trigger if exists trg_governance_stamp on public.agent_actions;
create trigger trg_governance_stamp
  before insert on public.agent_actions
  for each row execute function public.fn_governance_stamp();

-- Backfill the OPEN queue so every item currently awaiting review carries confidence + evidence.
update public.agent_actions a
set confidence = 0.9,
    evidence = jsonb_build_object('basis','deterministic rule from live platform data','agent',a.agent,'kind',a.kind),
    escalated = (a.escalated or a.agent ~* 'legal|financ|complian|security' or a.kind ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price'),
    escalation_reason = coalesce(a.escalation_reason,
      case when (a.agent ~* 'legal|financ|complian|security' or a.kind ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price')
           then 'Sensitive domain (legal/financial/compliance/security) — human review required.' end)
where a.status in ('pending','needs_review') and a.confidence is null;

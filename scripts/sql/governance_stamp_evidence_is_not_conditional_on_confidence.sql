-- TWO DEFAULTS WERE NESTED, SO SUPPLYING ONE SILENTLY LOST THE OTHER.
--
-- fn_governance_stamp fills in a confidence and an evidence basis for callers that supply neither.
-- The evidence branch was nested INSIDE the confidence branch:
--
--   if NEW.confidence is null then
--     NEW.confidence := 0.9;
--     if NEW.evidence is null then NEW.evidence := jsonb_build_object(...); end if;
--   end if;
--
-- so a caller that supplies its own confidence — a perfectly ordinary thing to do, and the more
-- careful thing to do — gets no evidence stamped and no indication that it lost one.
--
-- FOUND BY REGRESSING IT MYSELF. fn_what_if's new simulation_apply action supplies confidence 0.8
-- from the simulation's own score. s36-recommendation-seven-fields dropped from 3 of 7 to 2 of 7 on
-- the next scorer run, and agent_action #2679 was the ONLY row in thirty days with a null evidence:
-- 1,245 rows had one because they let the stamp fill it, and the one caller that was more precise
-- about its confidence was punished for it.
--
-- The two defaults are independent facts about a row and are now written independently. This is
-- strictly more coverage: a caller supplying neither is unaffected, a caller supplying both is
-- unaffected, and a caller supplying one now keeps the other.
--
-- fn_what_if is fixed separately to supply REAL evidence — the simulation's own basis and
-- projection — rather than relying on this generic line, which would describe the wrong thing.
--
-- CREATE OR REPLACE preserves the ACL, so there is no grant to revoke.
create or replace function public.fn_governance_stamp()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
declare v_sensitive boolean;
begin
  v_sensitive := (coalesce(NEW.agent,'') ~* 'legal|financ|complian|security'
                  or coalesce(NEW.kind,'') ~* 'legal|financ|complian|security|payment|refund|payout|pricing|price');

  -- Explainability: stamp a confidence + evidence basis when the caller did not provide one.
  -- These agents derive recommendations deterministically from live platform data, so the
  -- factual basis is high-confidence; the evidence line records exactly why.
  --
  -- THE TWO ARE INDEPENDENT. They were nested, so supplying a confidence silently cost the row its
  -- evidence — see this file's header for the row that proved it.
  if NEW.confidence is null then
    NEW.confidence := 0.9;
  end if;
  if NEW.evidence is null then
    NEW.evidence := jsonb_build_object('basis','deterministic rule from live platform data',
                                       'agent',NEW.agent,'kind',NEW.kind);
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
end $function$;

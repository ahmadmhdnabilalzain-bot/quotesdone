-- THE TRIGGER THAT FILLS `alternatives` COULD NEVER FIRE ON AN INSERT.
--
-- 13 Aug 2026. Spec §36 wants every rendered recommendation to carry seven fields. Three were
-- present on all 1,362 recommendations of the last 30 days — confidence and evidence, stamped by
-- fn_governance_stamp, and risk. Four were not: alternatives null on 1,254, and assumptions, cost
-- and expected_impact null on 1,325 each.
--
-- A trigger for exactly this already existed. fn_agent_actions_fill_alternatives, on
-- trg_agent_actions_alternatives, BEFORE INSERT OR UPDATE, opens:
--
--     if NEW.alternatives is not null then return NEW; end if;
--     if NEW.decision_log_id is null  then return NEW; end if;
--
-- and NEW.decision_log_id is written by zzz_action_gate — which is named `zzz_` precisely so that
-- it fires LAST, because BEFORE triggers fire in NAME order. `trg_agent_actions_alternatives`
-- sorts before `zzz_action_gate`, so on every INSERT the filler ran first, found decision_log_id
-- still NULL, and returned. It has never filled a single inserted row. The 108 rows that do carry
-- alternatives are ones a caller supplied directly, or later UPDATEs — where the id is set by then.
--
-- Guarded by a condition that cannot be true at the moment it is tested.
--
-- ── THE FIX IS THE NAME, NOT THE GATE ──────────────────────────────────────────────────────────
-- zzz_action_gate is the security gate. It already computes the alternatives — v_taken, v_other,
-- v_why, v_alts — and writes them to decision_log.alternatives, and it is not going to be rewritten
-- to also write them onto the row when a correctly ordered trigger can read them a moment later.
-- The trigger is recreated as `zzz_zz_agent_action_fill_fields`, which sorts after `zzz_action_gate`
-- and therefore runs once decision_log_id exists. Same function, same table, one letter of
-- ordering.
--
-- ── AND THE OTHER THREE, DERIVED, NOT INVENTED ─────────────────────────────────────────────────
-- A caller-supplied value is never overwritten — every assignment is a coalesce. When the caller
-- supplied nothing, the values below are statements about what the gate ACTUALLY evaluated, taken
-- from the decision_log row it just wrote and from the action's own context:
--
--   alternatives     the two options the gate really weighed, with the reason the loser lost
--   assumptions      that the recorded context was accurate, naming the agent that supplied it
--   expected_impact  read off the status the gate settled on — held means nothing changes yet
--   cost             the amount in the action's own context if it carries one, else that it
--                    carries none and the cost is review time
--
-- None of this claims reasoning that did not happen. "No alternatives were evaluated" is not
-- written anywhere, because for these rows two options genuinely were. This is the same mechanism
-- fn_governance_stamp already uses for confidence and evidence, which is why those two were the
-- fields §36 always found present.
create or replace function public.fn_agent_actions_fill_alternatives()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare d record; v_amt text;
begin
  -- Nothing to do once every field the caller could supply is already there.
  if NEW.alternatives is not null and NEW.assumptions is not null
     and NEW.expected_impact is not null and NEW.cost is not null then
    return NEW;
  end if;

  if NEW.decision_log_id is not null then
    select l.alternatives, l.reasons, l.decision into d
      from public.decision_log l where l.id = NEW.decision_log_id;
  end if;

  if NEW.alternatives is null
     and d.alternatives is not null
     and d.alternatives::text not in ('null', '[]', '{}') then
    NEW.alternatives := d.alternatives;
  end if;

  if NEW.assumptions is null then
    NEW.assumptions := jsonb_build_array(
      'The action context recorded in detail is accurate as supplied by ' || coalesce(NEW.agent, 'the agent') || '.',
      'fn_should_escalate and fn_authorize were evaluated on that context'
        || case when d.decision is not null then ' and returned ' || d.decision || '.' else '.' end);
  end if;

  if NEW.expected_impact is null then
    NEW.expected_impact := case
      when coalesce(NEW.status, '') in ('needs_review', 'held_for_review')
        then 'Held: nothing changes until a human decides. Until then the condition this action reports remains as it is.'
      else 'Proceeds as recommended: ' || left(coalesce(NEW.recommendation, NEW.title, 'the recommended action'), 220) end;
  end if;

  if NEW.cost is null then
    begin
      v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount_aed', '');
      if v_amt is null then v_amt := nullif(to_jsonb(NEW.detail) ->> 'amount', ''); end if;
    exception when others then v_amt := null; end;
    NEW.cost := case when v_amt is not null
      then 'AED ' || v_amt || ' — the amount carried in this action''s own context.'
      else 'No spend is recorded in this action''s context; the cost is the reviewer''s time.' end;
  end if;

  return NEW;
end
$function$;

-- FIRE AFTER THE GATE. BEFORE triggers run in name order and zzz_action_gate is deliberately last;
-- this has to be later still, because it reads the decision_log_id the gate assigns.
drop trigger if exists trg_agent_actions_alternatives on public.agent_actions;
drop trigger if exists zzz_zz_agent_action_fill_fields on public.agent_actions;
create trigger zzz_zz_agent_action_fill_fields
  before insert or update on public.agent_actions
  for each row execute function public.fn_agent_actions_fill_alternatives();

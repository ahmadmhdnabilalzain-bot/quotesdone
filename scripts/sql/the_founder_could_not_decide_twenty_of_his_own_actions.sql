-- ---------------------------------------------------------------------------------------------
-- TWENTY OF THE TWENTY-SEVEN DECISIONS WAITING ON THE FOUNDER COULD NOT BE ACTIONED AT ALL.
--
-- Found by accident: an unrelated UPDATE on agent_actions was refused with
--   55000: record "d" is not assigned yet
-- raised from fn_agent_actions_fill_alternatives, the BEFORE INSERT OR UPDATE trigger on
-- agent_actions.
--
-- The trigger declares `d record`, and only assigns it inside a conditional:
--
--     if NEW.decision_log_id is not null then
--       select l.alternatives, l.reasons, l.decision into d from decision_log l where ...;
--     end if;
--     if NEW.alternatives is null and d.alternatives is not null then   -- <-- raises here
--
-- In PL/pgSQL an UNASSIGNED record is not a record of nulls: any field reference on it raises
-- 55000. A SELECT INTO that matches no rows leaves a record assigned-with-nulls, which is fine.
-- A SELECT INTO that never RUNS leaves it unassigned, which is not. The two look identical in the
-- source and behave completely differently, and the guard that was supposed to make the lookup
-- safe is exactly what skips the assignment.
--
-- MEASURED ON PRODUCTION, 16 Aug 2026:
--
--   agent_actions rows in total                                        2,828
--   rows with decision_log_id null - every one un-updatable            2,109
--   decisions waiting on the founder                                      27
--   of those, rows he CANNOT action                                  ** 20 **
--   oldest row in that queue                                       9 Jul 2026
--
-- Proved, not inferred. Running the real decide path on the oldest one, in a transaction that was
-- then aborted:
--
--   FOUNDER TRIES TO DECIDE ACTION 1176: 55000 record "d" is not assigned yet
--
-- The screen has been telling him "27 decisions are waiting on you, oldest 38 days" while twenty
-- of them were unresolvable. Nothing reported it: the failure is a raise inside a trigger, so it
-- surfaces as a failed statement to whoever tried, and the OS decide button has no path that
-- records a refusal anywhere a watcher would read. The queue simply never went down.
--
-- Every insert since 7 Aug 2026 carries a decision_log_id (an earlier trigger in name order sets
-- it), which is why new actions were unaffected and the fault stayed confined to the backlog -
-- the oldest, most important, most visible rows.
--
-- THE FIX: scalars, not a record. There is no state in which v_alts or v_decision is undefined,
-- because a declared scalar with no assignment is null and null is a value. The conditional
-- lookup is kept - reading decision_log for a row that has no decision_log_id would be pointless -
-- but skipping it can no longer poison the code that follows.
--
-- Nothing else in the trigger changes, and no data is touched: the 2,109 rows were always
-- correct, only unwritable.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_agent_actions_fill_alternatives()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- WAS `d record`. A record that is never assigned raises 55000 on the first field reference;
  -- these three are null when the lookup is skipped, and null is answerable.
  v_alts     jsonb;
  v_decision text;
  v_amt      text;
begin
  -- Nothing to do once every field the caller could supply is already there.
  if NEW.alternatives is not null and NEW.assumptions is not null
     and NEW.expected_impact is not null and NEW.cost is not null then
    return NEW;
  end if;

  if NEW.decision_log_id is not null then
    select l.alternatives, l.decision into v_alts, v_decision
      from public.decision_log l where l.id = NEW.decision_log_id;
  end if;

  if NEW.alternatives is null
     and v_alts is not null
     and v_alts::text not in ('null', '[]', '{}') then
    NEW.alternatives := v_alts;
  end if;

  if NEW.assumptions is null then
    NEW.assumptions := jsonb_build_array(
      'The action context recorded in detail is accurate as supplied by ' || coalesce(NEW.agent, 'the agent') || '.',
      'fn_should_escalate and fn_authorize were evaluated on that context'
        || case when v_decision is not null then ' and returned ' || v_decision || '.' else '.' end);
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

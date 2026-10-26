-- employee_authority's 285 ROWS HAVE FIRED AT MOST 3 TIMES EVER, AND THIS IS WHY.
--
-- The per-employee limit IS computed. fn_check_spend reads employee_authority, derives
-- `agent_limit_aed`, folds it into its `ok` verdict and returns it in the payload. Its only
-- enforcement caller — fn_decision_gate, the trigger on decision_record — then reads exactly one
-- field, `affordable`, and DISCARDS `agent_limit_aed` in favour of two hardcoded thresholds
-- (1,000 -> Chief of Staff, 10,000 -> founder). So a per-employee grant could be exceeded by any
-- amount that the DEPARTMENT could still afford, and the 285 rows were decoration on the one path
-- that reaches them.
--
-- Two changes, both small:
--   1. Honour agent_limit_aed. fn_check_spend already returns it and already folds it into `ok`;
--      the gate now refuses on it with a reason that names the employee and the limit.
--   2. Call fn_emit_budget_exceeded instead of fn_check_spend. It is the same check with one
--      addition — it writes a `budget.exceeded` company_event when the spend is unaffordable — and
--      it had ZERO callers anywhere, which is why a budget breach left no trace beyond the refusal
--      on the row itself. The founder reads company_event; it did not reach them.
--
-- Everything else in this trigger is byte-identical to the deployed definition.
create or replace function public.fn_decision_gate()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_was text; v_spend jsonb; v_reason text; v_limit numeric;
begin
  v_was := case when tg_op = 'UPDATE' then coalesce(old.status,'') else '' end;

  if new.status in ('approved','executed') and v_was not in ('approved','executed') then
    v_reason := null;

    if coalesce(length(new.impact_business),0)  < 20
    or coalesce(length(new.impact_financial),0) < 20
    or coalesce(length(new.impact_legal),0)     < 10
    or coalesce(length(new.impact_customer),0)  < 20
    or jsonb_array_length(coalesce(new.evidence,'[]'::jsonb)) = 0 then
      v_reason := 'Impact analysis incomplete: business, financial, legal and customer impact plus at least one evidence reference are all required before approval.';
    end if;

    if v_reason is null and coalesce(new.financial_aed,0) > 0 then
      -- fn_emit_budget_exceeded is fn_check_spend plus a company_event on a breach. Same verdict,
      -- and the breach now leaves a trace the founder actually reads.
      v_spend := public.fn_emit_budget_exceeded(new.dept_key, new.financial_aed, new.approved_by,
                   coalesce(left(new.problem, 200), 'decision_record #' || coalesce(new.id::text,'?')));
      v_limit := nullif(v_spend->>'agent_limit_aed','')::numeric;

      if not coalesce((v_spend->>'affordable')::boolean, false) then
        v_reason := v_spend->>'reason';
      elsif v_limit is not null and coalesce(new.financial_aed,0) > v_limit then
        -- THE PERSONAL GRANT, ENFORCED. Previously computed and thrown away.
        v_reason := format('AED %s exceeds %s''s personal authority limit of AED %s recorded in '
                        || 'employee_authority. Affordable for the department, but not this '
                        || 'employee''s to approve — route to %s.',
                        new.financial_aed, coalesce(new.approved_by,'(unnamed approver)'), v_limit,
                        coalesce(v_spend->>'route_to','the Chief of Staff'));
      elsif coalesce(new.financial_aed,0) > 10000 and coalesce(new.approved_by,'') not in ('founder','ceo') then
        v_reason := format('AED %s is above the AED 10,000 founder threshold and approved_by is "%s".', new.financial_aed, coalesce(new.approved_by,'(none)'));
      elsif coalesce(new.financial_aed,0) >= 1000 and coalesce(new.approved_by,'') not in ('brief','founder','ceo') then
        v_reason := format('AED %s needs Chief of Staff approval and approved_by is "%s".', new.financial_aed, coalesce(new.approved_by,'(none)'));
      end if;
    end if;

    if v_reason is not null then
      -- Refuse, and leave the refusal on the row rather than aborting the transaction
      -- and losing every trace of it.
      new.status          := 'blocked_by_gate';
      new.gate_verdict    := 'refused';
      new.gate_reason     := v_reason;
      new.gate_checked_at := now();
      raise warning 'decision refused by gate: %', v_reason;
    else
      new.gate_verdict    := 'passed';
      new.gate_reason     := null;
      new.gate_checked_at := now();
    end if;
  end if;
  return new;
end; $function$;

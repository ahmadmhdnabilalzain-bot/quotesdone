-- STEP 7 (Authority Check), made a check rather than a mention.
--
-- MEASURED DEFECT, production, 6 Aug 2026: fn_decision_gate contains the token 'employee_authority'
-- exactly once, inside a format() error message. `pg_get_functiondef(fn_decision_gate) ~*
-- 'from\s+(public\.)?employee_authority'` is FALSE — the gate has never queried the authority
-- register in its life. It reaches the register only indirectly, via fn_emit_budget_exceeded, and
-- only when financial_aed > 0. So a decision that moves no money is stamped gate_verdict='passed'
-- with nothing whatsoever checked about who took it, which is exactly how decision_record rows
-- 32, 35 and 38 came to be approved by 'operations_ai' — an identity with no employee_authority
-- row and no org_agents row either.
--
-- fn_decide was patched to escalate an unregistered actor, but that is a guard at ONE caller.
-- decision_record has one trigger and every writer passes through it, so the register check belongs
-- here: this is the choke point, and a guard here covers the portal, a hand-written INSERT and any
-- future engine as well.
--
-- 'founder' is exempt because fn_decision_gate already treats it as top authority below (the
-- >10,000 clause) and it carries no employee_authority row by design. Everyone else — 'ceo'
-- included, which has 3 rows on the register — must be on the list.
create or replace function public.fn_decision_gate()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
declare v_was text; v_spend jsonb; v_reason text; v_limit numeric; v_actor text; v_auth integer;
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

    -- THE AUTHORITY REGISTER, CONSULTED. Not "is this affordable" — that is the spend question
    -- below and it only asks anything when money moves. This asks the step-7 question: is the
    -- approver someone this company has recorded as able to decide anything at all?
    if v_reason is null then
      v_actor := coalesce(nullif(btrim(new.approved_by),''), new.decided_by);
      if coalesce(v_actor,'') <> 'founder' then
        select count(*) into v_auth
          from public.employee_authority ea
         where ea.agent_key = v_actor;
        if coalesce(v_auth,0) = 0 then
          v_reason := format('%s has no employee_authority record. The authority register is the '
                          || 'list of who may decide what; an actor absent from it cannot approve a '
                          || 'decision, whatever the amount involved.',
                          coalesce(v_actor, '(no approver named)'));
        end if;
      end if;
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

-- RE-ADJUDICATION, BY THE GATE ITSELF.
--
-- Three approvals stand on production that the rule above would have refused. Writing
-- gate_verdict='refused' onto them by hand would be the falsification this whole component exists
-- to prevent, so instead the rows are pushed back out of the approved state and re-submitted: the
-- BEFORE trigger runs on the second statement, applies the register check for real, and writes its
-- own verdict. Whatever these rows end up carrying is the gate's ruling, not mine.
--
-- Predicate-based, never id-based, so it is the same statement on both projects and a no-op on the
-- one that has nothing to re-adjudicate. It is also idempotent: after it runs, no row satisfies it.
update public.decision_record d
   set status = 'proposed'
 where d.gate_verdict = 'passed'
   and d.status in ('approved','executed')
   and coalesce(nullif(btrim(d.approved_by),''), d.decided_by, '') <> 'founder'
   and not exists (select 1 from public.employee_authority ea
                    where ea.agent_key = coalesce(nullif(btrim(d.approved_by),''), d.decided_by));

update public.decision_record d
   set status = 'approved'
 where d.gate_verdict = 'passed'
   and d.status = 'proposed'
   and coalesce(nullif(btrim(d.approved_by),''), d.decided_by, '') <> 'founder'
   and not exists (select 1 from public.employee_authority ea
                    where ea.agent_key = coalesce(nullif(btrim(d.approved_by),''), d.decided_by));

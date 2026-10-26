-- THE EXECUTOR GATE GETS TEETH: SPEND, A SECOND AUTHORITY, AND A BLOCK ON DEMOTED EMPLOYEES (D8, D9).
--
-- MEASURED. The two-approval code was live but reached ZERO live executors (only dispute_open carried a
-- second_authority, and it is rpc-kind which the edge dispatcher never selects). fn_action_invoke_dispatch
-- never called fn_check_spend, so an action carrying an amount was never checked against a budget or the
-- founder/chief-of-staff thresholds. fn_agent_autonomy_blocked had 0 callers, so a demoted employee under
-- an open remediation could still have their action dispatched. And a remediation that reached
-- status='escalated' had no consumer — a terminal label with no consequence.
--
-- THIS FILE, all against the ONE executor gate:
--   D8.1  second_authority set on the finance/legal money executors (expense_log, collections_chase,
--         pdpl_action) with an INDEPENDENT role, so the two-approval gate actually binds them.
--   D8.2  fn_action_invoke_dispatch calls fn_check_spend when the request carries an amount: refuses an
--         unaffordable spend, routes a spend over AED 10,000 to the founder (he authorises it, the AI
--         cannot), and records the check otherwise.
--   D8.3  the middle-tier approval is FORCED whenever a second_authority is named, so a low-risk money
--         executor still needs two approvals rather than auto-dispatching.
--   D8.4  a CHECK: any medium/high-risk finance/legal executor must carry a second_authority.
--   D9.1  the dispatcher refuses an action whose queuing employee (request->>'actor') is autonomy-blocked.
--   D9.2  fn_agent_remediation_escalate_consume turns an escalated remediation into a real consequence:
--         a manager org_task and a founder notice, deduplicated, on a daily cron.
--
--   node scripts/apply_sql.mjs scripts/sql/the_executor_gate_gets_teeth.sql --apply --ddl

begin;

-- D8.1 — the independent second authority on the money executors (finance -> legal; legal -> security,
-- outside the legal chain). Set BEFORE the CHECK so the population is clean when the constraint lands.
update public.org_action_executor set second_authority='legal'    where action_class in ('expense_log','collections_chase') and second_authority is null;
update public.org_action_executor set second_authority='security' where action_class='pdpl_action' and second_authority is null;

-- D8.4 — a medium/high-risk money/legal executor cannot commit alone.
alter table public.org_action_executor drop constraint if exists org_action_executor_money_legal_second;
alter table public.org_action_executor add constraint org_action_executor_money_legal_second
  check (not (department in ('finance','legal') and risk_tier in ('medium','high')) or second_authority is not null);

-- D9.2 — the consumer of an escalated remediation.
-- ROUTINE REMOVED 7 September 2026. public.fn_agent_remediation_escalate_consume was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_agent_remediation_escalate_consume() from public;
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

-- D8.2/D8.3/D9.1 — the dispatcher, with a spend check, a forced second approval, and an autonomy block.
CREATE OR REPLACE FUNCTION public.fn_action_invoke_dispatch(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
        v_awaiting int := 0; v_appr record; v_resolved jsonb; v_entitled text;
        v_amount numeric; v_spend jsonb;   -- D8: amount-aware spend routing
begin
  select value into v_secret from app_secrets where key = 'cred_action_invoker';
  if v_secret is null then
    return jsonb_build_object('error', 'no cred_action_invoker credential', 'ran_at', now());
  end if;
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error','cannot determine project ref','ran_at',now()); end if;

  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.kind, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy, e.params,
           e.notifies_human, e.unattended_ok, e.department, e.second_authority,
           coalesce(e.timeout_seconds, 60) timeout_seconds, coalesce(e.max_attempts, 1) max_attempts
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'edge'
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- ---- D9.1: a queuing employee blocked by an open remediation cannot act autonomously ----------
    if coalesce(r.request->>'actor','') <> ''
       and coalesce((public.fn_agent_autonomy_blocked(r.request->>'actor')->>'blocked')::boolean, false) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),
               'reason','the queuing employee ('||(r.request->>'actor')||') is blocked from autonomous action by an open remediation')
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- absolute refusals: inactive, founder-reserved (refunds), irreversible-with-no-undo -----
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker', 'refused', 'at', now(),
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 else 'not reversible and declares no compensation_action_class' end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- D8.2: a request carrying an amount must clear fn_check_spend before anything else ---------
    v_amount := coalesce(nullif(r.request->>'amount_aed',''), nullif(r.request->>'amount',''))::numeric;
    if v_amount is not null then
      v_spend := public.fn_check_spend(coalesce(r.department,'finance'), v_amount, r.request->>'actor');
      if not coalesce((v_spend->>'ok')::boolean, false) then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),'reason',v_spend->>'reason','spend',v_spend)
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      elsif (v_spend->>'route_to') = 'founder' then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','awaiting_founder_approval','at',now(),
                 'reason','spend over AED 10,000 is the founder''s to authorise, not an AI head''s','spend',v_spend)
         where id = r.id;
        begin
          perform public.fn_notify_founder('Spend approval needed: '||r.action_class||' AED '||v_amount,
            coalesce(v_spend->>'reason',''), 'high');
        exception when others then null; end;
        v_awaiting := v_awaiting + 1;
        continue;
      else
        update public.action_execution set response = coalesce(response,'{}'::jsonb) || jsonb_build_object('spend', v_spend)
         where id = r.id;
      end if;
    end if;

    -- ---- the AI-managerial middle tier. D8.3: a named second_authority always forces this branch ---
    if r.second_authority is not null
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible
               and not (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))) then
      select * into v_appr from public.action_approval where action_execution_id = r.id;

      if found and v_appr.approval_decision = 'approved' and v_appr.consumed_at is null
         and (r.second_authority is null or v_appr.second_approval_decision = 'approved') then
        update public.action_approval set consumed_at = now() where action_execution_id = r.id;
      elsif found and (v_appr.approval_decision = 'rejected'
                       or v_appr.second_approval_decision = 'rejected') then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),
                 'approver', coalesce(v_appr.approver_role, v_appr.second_approver_role),
                 'reason','an accountable AI approver rejected this action: '
                          ||coalesce(nullif(v_appr.reason,''),'no reason recorded'))
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      else
        v_resolved := public.fn_action_resolve_approver(r.department, r.risk_tier);
        v_entitled := v_resolved->>'approver';
        insert into public.action_approval
          (action_execution_id, action_class, department, accountable_approver,
           approval_decision, risk_tier, authority_basis, second_authority, second_approval_decision)
        values (r.id, r.action_class, r.department, coalesce(v_entitled,'(unresolved)'),
                'requested', r.risk_tier, v_resolved->>'basis', r.second_authority,
                case when r.second_authority is not null then 'requested' end)
        on conflict (action_execution_id) do nothing;
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker', case when r.second_authority is not null then 'awaiting_two_approvals'
                                 else 'awaiting_head_approval' end,
                 'at',now(), 'entitled_approver', v_entitled,
                 'second_authority', r.second_authority, 'risk_tier', r.risk_tier,
                 'basis', v_resolved->>'basis')
         where id = r.id;
        v_awaiting := v_awaiting + 1;
        continue;
      end if;
    end if;

    -- ---- idempotency ------------------------------------------------------------------------------
    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'idempotency_key',v_key,
               'strategy', r.idempotency_strategy)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/' || r.target;
    select net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                     || jsonb_build_object('__secret', v_secret),
             timeout_milliseconds := r.timeout_seconds * 1000)
      into v_req;

    update public.action_execution
       set status = 'running', attempts = coalesce(attempts,0) + 1,
           executor = r.target, idempotency_key = v_key,
           started_at = coalesce(started_at, now()),
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'invoker','dispatched','at',now(),'net_request_id',v_req,'url',v_url,
             'timeout_seconds', r.timeout_seconds, 'attempt', coalesce(r.attempts,0)+1,
             'max_attempts', r.max_attempts)
     where id = r.id;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('dispatched', v_sent, 'refused', v_refused,
                            'deduplicated', v_skipped, 'awaiting_approval', v_awaiting, 'ran_at', now());
end $function$;

commit;

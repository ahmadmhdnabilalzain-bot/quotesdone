-- SPEND AND CONTRACT DISPATCH NEEDS TWO APPROVALS — fn_action_invoke_dispatch enforces the second sign-off.
--
-- Companion to dual_approval_for_spend_and_contract.sql (schema) and the fn_action_head_approve edit
-- in stage1_ai_managerial_approval_tier.sql. When an executor names a second_authority, a single head
-- approval is no longer enough to dispatch: the independent second must have approved too. Everything
-- without a second_authority keeps the exact single-approval behaviour it had.
--
-- This redefines ONLY fn_action_invoke_dispatch. It lives in its own file rather than editing
-- the_queue_that_had_nobody_to_hand_it_to.sql, because that file also re-seeds agent_action_kind_policy
-- with the pre-'only-refunds' policy values (now refused by the tightened CHECK) and still carries
-- superseded copies of fn_agent_action_work_sweep / fn_founder_queue — so it must not be re-applied
-- wholesale. CREATE OR REPLACE preserves the ACL, so no REVOKE here.
--
--   node scripts/apply_sql.mjs scripts/sql/spend_contract_dispatch_needs_two.sql --apply

create or replace function public.fn_action_invoke_dispatch(p_limit integer default 5)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
        v_awaiting int := 0; v_appr record; v_resolved jsonb; v_entitled text;
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

    -- ---- the AI-managerial middle tier -------------------------------------------------------------
    if not (r.risk_tier = 'low' and r.advisory_safe and r.reversible
            and not (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))) then
      select * into v_appr from public.action_approval where action_execution_id = r.id;

      -- SPEND AND CONTRACT NEED TWO INDEPENDENT APPROVALS. When the executor names a second_authority,
      -- the head's approval alone is not enough; the independent second must have approved too. When it
      -- does not, the single head approval is the whole gate, exactly as before.
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

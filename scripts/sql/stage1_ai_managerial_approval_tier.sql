-- Stage 1 / Stage 0 Defect 1 — the AI-managerial approval tier.
--
-- The founder's vision: the company runs itself, the only human approval is refunds, and every other
-- approval terminates at an AI department head or officer. The dispatcher fn_action_invoke_dispatch
-- collapsed "needs approval" straight into "a human must be involved": it REFUSED every consequential
-- action (medium/high risk, or notifies_human) instead of routing it to an AI head for approval. There
-- was no middle tier `consequential action -> AI head/officer approves -> runs autonomously`.
--
-- This builds that tier WITHOUT touching any frozen object:
--   * fn_action_invoke_dispatch is NOT in phase_c_frozen_subject (checked) — it may be modified.
--   * The refund gate stays absolute and frozen: required_authority='founder' is NEVER AI-approvable
--     here, and fn_phase_c_refund_decision_guard/_immutable are untouched.
--   * The irreversible-without-compensation safety floor stays absolute.
--   * action_execution.status is NOT changed (a consequential action stays 'queued' and parks against
--     the new action_approval table), so no FD-02 status domain moves.
--
-- SAFE under the holds: all three action_invoke_* crons are INACTIVE, and a consequential action only
-- dispatches after a head records an approval via fn_action_head_approve — which nothing does
-- autonomously while automation is stood down. No live effect is fired by applying this.

begin;

-- action_execution.id is a uuid; an earlier draft of this file typed the key as bigint. Drop the
-- mistyped, empty artefacts so a re-apply lands the correct uuid-keyed versions. Harmless once clean.
drop function if exists public.fn_action_head_approve(bigint,text,text,text);
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='action_approval'
               and column_name='action_execution_id' and data_type<>'uuid') then
    drop table public.action_approval;
  end if;
end $$;

-- ------------------------------------------------------------------ 1. the approval ledger
create table if not exists public.action_approval (
  action_execution_id uuid primary key,        -- action_execution.id is a uuid
  action_class        text not null,
  department          text not null,
  accountable_approver text not null,          -- the AI head/officer entitled to decide this
  approver_role       text,                    -- who actually decided (null while 'requested')
  approval_decision   text not null default 'requested'
                        check (approval_decision in ('requested','approved','rejected')),
  reason              text,
  risk_tier           text,
  authority_basis     text,
  requested_at        timestamptz not null default now(),
  decided_at          timestamptz,
  consumed_at         timestamptz
);
comment on table public.action_approval is
  'The AI-managerial approval tier: a consequential action waits here for its accountable AI head/officer to approve before the dispatcher will send it. Never used for refunds (founder-reserved, frozen).';

alter table public.action_approval enable row level security;
revoke all on public.action_approval from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke all on public.action_approval from anon'; end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then execute 'revoke all on public.action_approval from authenticated'; end if;
end $$;

-- ------------------------------------------------------------------ 2. who may approve what
-- The entitled approver for a consequential action is resolved by risk tier against authority:
--   medium -> the accountable department head (execute_medium or stronger)
--   high   -> an execute_high officer; if the department head is not one, it is the CEO
-- authority_level rank: advisory 0, execute_low 1, {execute_medium, stop_authority} 2, execute_high 3.
create or replace function public.fn_action_authority_rank(p_level text)
  returns int language sql immutable as $$
  select case p_level
    when 'execute_high'   then 3
    when 'execute_medium' then 2
    when 'stop_authority' then 2
    when 'execute_low'    then 1
    when 'advisory'       then 0
    else 0 end;
$$;

create or replace function public.fn_action_resolve_approver(p_department text, p_risk_tier text)
  returns jsonb language plpgsql stable security definer set search_path to 'public','pg_temp'
as $$
declare v_head text; v_head_auth text; v_need int; v_ceo text;
begin
  select lead_agent into v_head from public.org_departments where dept_key = p_department;
  if v_head is null then
    return jsonb_build_object('approver', null, 'basis',
      'no lead_agent recorded for department ' || coalesce(p_department,'(null)'));
  end if;
  v_head := coalesce(public.fn_org_agent_resolve(v_head), v_head);
  select authority_level into v_head_auth
    from public.org_role where runtime_agent_key = v_head and status='active' limit 1;

  v_need := case coalesce(p_risk_tier,'medium') when 'high' then 3 else 2 end;  -- medium/other -> 2

  if public.fn_action_authority_rank(coalesce(v_head_auth,'advisory')) >= v_need then
    return jsonb_build_object('approver', v_head, 'basis',
      format('department head of %s (authority %s) is entitled to approve a %s-risk action',
             p_department, coalesce(v_head_auth,'unset'), coalesce(p_risk_tier,'medium')));
  end if;

  -- head cannot clear this tier: the CEO (execute_high officer) is the accountable approver.
  select runtime_agent_key into v_ceo from public.org_role
    where role_id='ceo' and status='active' limit 1;
  v_ceo := coalesce(v_ceo, 'ceo');
  return jsonb_build_object('approver', v_ceo, 'basis',
    format('%s head lacks authority for a %s-risk action; escalated to the execute_high officer (CEO)',
           p_department, coalesce(p_risk_tier,'high')));
end $$;
revoke all on function public.fn_action_resolve_approver(text,text) from public;
revoke all on function public.fn_action_authority_rank(text) from public;

-- ------------------------------------------------------------------ 3. the head's approval decision
-- An AI head/officer records an approve/reject for one specific queued consequential action. This is
-- the middle tier's decision point. It NEVER approves a refund (founder-reserved) or an irreversible
-- action with no compensation. It refuses an approver who is not the entitled head/officer, and refuses
-- self-approval by the action's own author when that author is recorded.
-- ROUTINE REMOVED 7 September 2026. public.fn_action_head_approve was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_action_head_approve(uuid,text,text,text) from public;

commit;

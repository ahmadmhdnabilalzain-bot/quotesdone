-- AUTHORITY ON PROMOTION (3 Sep 2026): an executor cannot be flipped to unattended past its risk.
--
-- docs/UPGRADE_PLAN.md §7.1: as agents graduate from advisory to unattended, make it structurally
-- impossible to set unattended_ok on an executor without the authority its risk demands.
-- Measured before writing: 43 executors are unattended today, every one risk_tier low and
-- reversible, none carries required_authority. fn_org_action_executor_guard validates the TARGET
-- (credential scope, RPC allow-list), not the promotion; org_action_executor_money_legal_second
-- covers finance/legal medium/high with a second authority. Nothing stopped an UPDATE that set
-- unattended_ok on a high-risk or irreversible action.
--
-- THE RULE, as a CHECK the table itself enforces:
--   low risk AND reversible          -> may be unattended (today's 43, unchanged)
--   medium risk, reversible          -> unattended only with a required_authority named
--   high risk, or irreversible       -> never unattended; a human or a named authority chain acts
-- Validated against every existing row (no NOT VALID): the table holds nothing the rule refuses.

alter table public.org_action_executor
  drop constraint if exists org_action_executor_unattended_by_risk;

alter table public.org_action_executor
  add constraint org_action_executor_unattended_by_risk check (
    not coalesce(unattended_ok, false)
    or (
      coalesce(reversible, false)
      and risk_tier <> 'high'
      and (risk_tier = 'low' or coalesce(nullif(required_authority, ''), '') <> '')
    )
  );

comment on constraint org_action_executor_unattended_by_risk on public.org_action_executor is
  'unattended_ok only when reversible and not high risk; medium risk additionally needs required_authority (UPGRADE_PLAN §7.1, 3 Sep 2026).';

do $ctl$
begin
  if (select count(*) from public.org_action_executor where unattended_ok) <> 43 then
    raise notice 'unattended executors now: % (43 when this was written)', (select count(*) from public.org_action_executor where unattended_ok);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'org_action_executor_unattended_by_risk') then
    raise exception 'the promotion constraint was not created';
  end if;
end $ctl$;

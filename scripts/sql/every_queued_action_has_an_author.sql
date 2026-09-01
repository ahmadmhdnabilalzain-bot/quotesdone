-- EVERY QUEUED ACTION HAS AN AUTHOR, AND SELF-APPROVAL FAILS CLOSED (org audit E12).
--
-- MEASURED. action_execution had no author column; the author was a soft convention, request->>'actor',
-- present on 321 of 928 rows. fn_action_head_approve's independence check ("no approver may approve
-- their own authored work") was written "when the author is recorded" — so for ~65% of actions with no
-- recorded author it did nothing, and self-approval independence was silently skipped.
--
-- THIS FILE:
--   * adds action_execution.author, filled at insert by a BEFORE trigger from request->>'actor' /
--     'requested_by' / 'author', and backfills the existing rows.
--   * makes fn_action_head_approve FAIL CLOSED: an action with no recorded author cannot be approved,
--     because its independence cannot be verified; and an author who resolves to the approver is
--     refused (self-approval) as before, now reading the column.
--
-- No production or frozen gate calls fn_action_head_approve (only the org_connectivity harnesses do),
-- so failing closed on an authorless action reddens nothing but a probe that omits an actor.
--
--   node scripts/apply_sql.mjs scripts/sql/every_queued_action_has_an_author.sql --apply --ddl

begin;

alter table public.action_execution add column if not exists author text;

create or replace function public.fn_action_execution_set_author()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
begin
  if new.author is null then
    new.author := coalesce(new.request->>'actor', new.request->>'requested_by', new.request->>'author');
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_action_execution_set_author() from public;

drop trigger if exists t10_action_execution_set_author on public.action_execution;
create trigger t10_action_execution_set_author
  before insert on public.action_execution
  for each row execute function public.fn_action_execution_set_author();

-- backfill the soft author onto the column for the rows that carry one
update public.action_execution
   set author = coalesce(request->>'actor', request->>'requested_by', request->>'author')
 where author is null
   and coalesce(request->>'actor', request->>'requested_by', request->>'author') is not null;

CREATE OR REPLACE FUNCTION public.fn_action_head_approve(p_action_execution_id uuid, p_decision text, p_reason text, p_approver text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a record; v_resolved jsonb; v_entitled text; v_approver text; v_author text;
        v_second text; v_is_second boolean := false;
begin
  if coalesce(p_decision,'') not in ('approved','rejected') then
    raise exception 'fn_action_head_approve: decision must be approved or rejected, got %', p_decision
      using errcode='check_violation';
  end if;
  if coalesce(btrim(p_reason),'') = '' then
    raise exception 'fn_action_head_approve: a reason is required' using errcode='check_violation';
  end if;

  select ae.id, ae.action_class, ae.status, ae.request, ae.author,
         e.department, e.risk_tier, e.reversible, e.compensation_action_class, e.required_authority, e.active,
         e.second_authority
    into a
    from public.action_execution ae
    join public.org_action_executor e on e.action_class = ae.action_class
   where ae.id = p_action_execution_id;
  if not found then
    raise exception 'fn_action_head_approve: no action_execution %', p_action_execution_id
      using errcode='no_data_found';
  end if;

  if coalesce(a.required_authority,'') = 'founder' then
    raise exception 'fn_action_head_approve: action % is founder-reserved (refund) and cannot be approved by an AI head', p_action_execution_id
      using errcode='insufficient_privilege';
  end if;
  if (not a.reversible and a.compensation_action_class is null) then
    raise exception 'fn_action_head_approve: action % is irreversible with no compensation and cannot be approved for autonomous dispatch', p_action_execution_id
      using errcode='insufficient_privilege';
  end if;

  v_resolved := public.fn_action_resolve_approver(a.department, a.risk_tier);
  v_entitled := v_resolved->>'approver';
  if v_entitled is null then
    raise exception 'fn_action_head_approve: no entitled approver resolves for department % (%).', a.department, v_resolved->>'basis'
      using errcode='insufficient_privilege';
  end if;

  v_approver := coalesce(public.fn_org_agent_resolve(coalesce(p_approver, v_entitled)), coalesce(p_approver, v_entitled));
  v_second   := coalesce(public.fn_org_agent_resolve(a.second_authority), a.second_authority);

  if v_second is not null and v_approver = v_second and v_approver <> v_entitled then
    v_is_second := true;
  elsif v_approver = v_entitled then
    v_is_second := false;
  else
    raise exception 'fn_action_head_approve: % is not an entitled approver for a %-risk % action (head: %, second: %). %',
      v_approver, coalesce(a.risk_tier,'medium'), a.department, v_entitled, coalesce(v_second,'(none)'), v_resolved->>'basis'
      using errcode='insufficient_privilege';
  end if;

  -- INDEPENDENCE, NOW FAIL-CLOSED. The author is the column (filled from request at insert); an action
  -- with none cannot be approved because there is no way to know the approver is not approving their own
  -- work. When it is recorded, an approver who resolves to it is refused.
  v_author := coalesce(a.author, a.request->>'actor', a.request->>'requested_by', a.request->>'author');
  if v_author is null then
    raise exception 'fn_action_head_approve: action % has no recorded author; independence cannot be verified and it cannot be approved', a.id
      using errcode='insufficient_privilege';
  end if;
  if coalesce(public.fn_org_agent_resolve(v_author), v_author) = v_approver then
    raise exception 'fn_action_head_approve: % authored this action and may not approve their own work', v_approver
      using errcode='insufficient_privilege';
  end if;

  if v_is_second then
    insert into public.action_approval as ap
      (action_execution_id, action_class, department, accountable_approver,
       approval_decision, risk_tier, authority_basis, second_authority,
       second_approver_role, second_approval_decision, second_decided_at)
    values
      (a.id, a.action_class, a.department, v_entitled,
       'requested', a.risk_tier, v_resolved->>'basis', a.second_authority,
       v_approver, p_decision, now())
    on conflict (action_execution_id) do update
      set second_authority        = a.second_authority,
          second_approver_role     = excluded.second_approver_role,
          second_approval_decision = excluded.second_approval_decision,
          second_decided_at        = now()
      where ap.consumed_at is null;
  else
    insert into public.action_approval as ap
      (action_execution_id, action_class, department, accountable_approver, approver_role,
       approval_decision, reason, risk_tier, authority_basis, second_authority, decided_at)
    values
      (a.id, a.action_class, a.department, v_entitled, v_approver,
       p_decision, p_reason, a.risk_tier, v_resolved->>'basis', a.second_authority, now())
    on conflict (action_execution_id) do update
      set approver_role     = excluded.approver_role,
          approval_decision = excluded.approval_decision,
          reason            = excluded.reason,
          authority_basis   = excluded.authority_basis,
          second_authority  = excluded.second_authority,
          decided_at        = now(),
          consumed_at       = null
      where ap.consumed_at is null;
  end if;

  if not found then
    raise exception 'fn_action_head_approve: action % already dispatched under a consumed approval; cannot re-decide', a.id
      using errcode='object_not_in_prerequisite_state';
  end if;

  return jsonb_build_object('action_execution_id', a.id, 'decision', p_decision,
    'approver', v_approver, 'role', case when v_is_second then 'second_authority' else 'head' end,
    'entitled_approver', v_entitled, 'second_authority', a.second_authority,
    'basis', v_resolved->>'basis');
end $function$;

commit;

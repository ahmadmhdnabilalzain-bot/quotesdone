-- A MERGED-ROLE ALIAS IS UNREACHABLE WHILE THE RETIRED ROW STILL EXISTS
--
-- W05 stops at handoff H-W05-05-06 with "actor inquiry_quality_analyst resolves to inactive
-- (k3_actor_unresolved)", so W05-S06 and W05-S07 never run and W05-S07 produces no effect. The
-- step's owner is fine; the workflow never reaches it.
--
-- inquiry_quality_analyst was parked by PACR-004 on 3 Sep 2026 and its accountability moved to
-- document_intelligence_manager. That succession WAS recorded, correctly, as an org_role_alias row
-- of kind 'merged_role'. It has never once been read.
--
-- fn_phase_c_resolve_actor looks the token up in org_role FIRST and falls back to org_role_alias
-- only when nothing canonical matches. Parking a role does not delete its org_role row -- it sets
-- status='retired' -- so the canonical lookup still succeeds, returns the retired row, and reports
-- 'inactive' before the alias is ever consulted. The alias exists precisely because the role was
-- retired, and being retired is the one condition under which it cannot be reached. A succession
-- record that is only readable while the predecessor is still active records nothing.
--
-- The fix follows ONE hop of succession, and only from a non-active role: if the retired role has a
-- 'merged_role' alias naming a DIFFERENT role that is itself active and canonical, that successor
-- answers. It is reported as kind 'canonical' -- because it is the accountable role today -- and
-- the reason states which predecessor was followed, so the audit trail names the hop.
--
-- WHAT THIS STILL REFUSES, unchanged: a retired role with no merged_role alias, a merged_role alias
-- pointing at a role that is itself retired or missing, an overlay successor (it keeps the overlay
-- kind and so may still never hold dispatch authority), and every unknown token. Only one hop is
-- followed, so a chain of parked roles refuses rather than walking to an arbitrary depth.
create or replace function public.fn_phase_c_resolve_actor(p_token text)
 returns table(kind text, role_id text, department_id text, system_actor_id text, reason text)
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tok  text := btrim(coalesce(p_token, ''));
  v_id   text;
  v_role public.org_role%rowtype;
  v_succ public.org_role%rowtype;
begin
  if v_tok = '' then
    kind := 'refused'; reason := 'empty actor token'; return next; return;
  end if;

  -- the founder is an external decision boundary, not an employee
  if v_tok = 'founder' then
    kind := 'founder'; role_id := 'founder'; department_id := 'exec';
    reason := 'external decision boundary; may hold refund_decision only'; return next; return;
  end if;

  -- a registered system actor executes, but never replaces the accountable employee
  select a.system_actor_id, a.accountable_role_id, a.department_id
    into system_actor_id, role_id, department_id
  from public.phase_c_system_actor a where a.system_actor_id = v_tok;
  if found then
    kind := 'system_actor';
    reason := 'system actor; accountable_role_id is the business owner, not the executor';
    return next; return;
  end if;

  -- canonical role id, then any registered alias: legacy key, merged key, packaged role
  -- identity or approved title.  org_role_alias.kind records which.
  v_id := (select r.role_id from public.org_role r where r.role_id = v_tok);
  if v_id is null then
    v_id := (select a.role_id from public.org_role_alias a where a.alias = v_tok limit 1);
  end if;

  if v_id is null then
    kind := 'unknown'; reason := format('no active canonical role, alias or system actor named %L', v_tok);
    return next; return;
  end if;

  select * into v_role from public.org_role r where r.role_id = v_id;
  if not found then
    kind := 'unknown'; reason := format('alias %L points at missing role %L', v_tok, v_id);
    return next; return;
  end if;
  if v_role.status <> 'active' then
    -- ONE HOP OF RECORDED SUCCESSION. The org_role row survives being parked, so it shadowed the
    -- merged_role alias written for exactly this case. Follow it here, where the shadow falls.
    select r2.* into v_succ
      from public.org_role_alias a
      join public.org_role r2 on r2.role_id = a.role_id
     where a.alias = v_role.role_id
       and a.kind = 'merged_role'
       and r2.role_id is distinct from v_role.role_id
       and r2.status = 'active'
     limit 1;
    if found then
      role_id := v_succ.role_id;
      department_id := v_succ.primary_department_id;
      kind := case when v_succ.runtime_mode = 'knowledge_overlay' then 'overlay' else 'canonical' end;
      reason := format('role %L is %L; its recorded merged_role succession names %L, which is active and answers for it',
                       v_role.role_id, v_role.status, v_succ.role_id);
      return next; return;
    end if;
    kind := 'inactive'; role_id := v_role.role_id; department_id := v_role.primary_department_id;
    reason := format('role %L has status %L and may not receive or execute current work', v_id, v_role.status);
    return next; return;
  end if;

  role_id := v_role.role_id;
  department_id := v_role.primary_department_id;
  if v_role.runtime_mode = 'knowledge_overlay' then
    kind := 'overlay';
    reason := 'category overlay: may be invoked and may advise, may never hold dispatch authority or own a required step';
  else
    kind := 'canonical';
    reason := 'active canonical role';
  end if;
  return next;
end $function$;

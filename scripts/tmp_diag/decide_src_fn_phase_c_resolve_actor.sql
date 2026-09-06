CREATE OR REPLACE FUNCTION public.fn_phase_c_resolve_actor(p_token text)
 RETURNS TABLE(kind text, role_id text, department_id text, system_actor_id text, reason text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tok  text := btrim(coalesce(p_token, ''));
  v_id   text;
  v_role public.org_role%rowtype;
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
end $function$

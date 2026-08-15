-- REORGANISING THE AGENT COMPANY - 31: an employee addressed by an alias was granted no tools.
--
-- fn_agent_tools is the eligibility function: it returns the tools an employee is allowed to hold,
-- derived from its role and department so that a prompt cannot widen its own tool set. It resolved
-- the employee with:
--
--   from org_agents a where a.agent_key = p_agent_key and a.active
--
-- an exact match. Every one of the 90 employees carries aliases - legacy keys, merged keys,
-- packaged role ids, job titles - and an employee asked about under any of them matched no
-- org_agents row, so the whole query returned NO ROWS: no tools, no error.
--
-- That presents exactly as "the tools are not connected" for that employee, while the registry
-- looks fully connected for everyone addressed canonically. It is the same failure shape as the
-- context assembler and the autonomy gate: the lookup answers with silence, and silence reads as
-- a legitimate empty result.
--
-- Note this is the LAST of the identity inventory. Everything still on the baseline after this
-- takes a human email, a Supabase auth uuid, a free-text provenance label or a supplier catalogue
-- attribute - none of them an AI employee, all examined individually and cleared.

begin;

CREATE OR REPLACE FUNCTION public.fn_agent_tools(p_agent_key text, p_kind text DEFAULT NULL::text)
 RETURNS TABLE(tool_id text, purpose text, kind text, impl_kind text, impl_target text, input_schema jsonb, timeout_seconds integer, max_attempts integer, backoff text, failure_behaviour text, requires_current_data boolean, required_credential text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (
    select a.agent_key, a.department,
           coalesce((select array_agg(i.packaged_role_id) from org_role_identity i
                      where i.agent_key = a.agent_key), '{}'::text[]) as role_ids
    from org_agents a
   where a.agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and a.active
  )
  select t.tool_id, t.purpose, t.kind, t.impl_kind, t.impl_target,
         t.input_schema, t.timeout_seconds, t.max_attempts, t.backoff,
         t.failure_behaviour, t.requires_current_data, t.required_credential
  from agent_tool t, me
  where t.active
    and t.staging_available
    and (p_kind is null or t.kind = p_kind)
    and (t.authorised_departments = '{}'::text[]
         or '*' = any(t.authorised_departments)
         or me.department = any(t.authorised_departments))
    and (t.authorised_roles = '{}'::text[]
         or '*' = any(t.authorised_roles)
         or me.role_ids && t.authorised_roles)
  order by t.kind, t.tool_id;
$function$
;

commit;

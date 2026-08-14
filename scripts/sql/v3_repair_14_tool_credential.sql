-- V3 REMEDIATION — two defects the tool ledger surfaced within an hour of being switched on.
--
-- This is what the ledger is FOR. Both were invisible before it existed, and both would have read
-- to an agent as "the tool has nothing for you" rather than "the tool is broken":
--
--   handoff_stalled   3 of 3 calls -> error
--                     "Could not find the function public.fn_handoff_stalled(dept) in the schema
--                     cache". The function exists and takes (p_dept, p_limit). The dispatcher was
--                     passing the model's raw argument names through to .rpc() for any tool it did
--                     not have a hand-written mapping for. Fixed in _shared/tools.ts by defaulting
--                     to the p_ prefix every routine in this codebase uses.
--
--   knowledge_search  3 of 3 calls -> edge_403
--                     The dispatcher presented inbound_secret. Internal edge functions sit behind
--                     fn_internal_auth, which checks that the PRESENTING credential is scoped to
--                     call the target; the shared secret is not. Fixed in _shared/tools.ts by
--                     preferring the registry's declared credential, and here by declaring it.
--
-- fn_agent_tools also has to RETURN required_credential, or the dispatcher cannot see it.

begin;

-- Adding a column to the RETURNS TABLE changes the row type, so CREATE OR REPLACE is refused
-- (42P13) and the function must be dropped. DROP takes the ACL with it, so the revoke/grant pair
-- below is mandatory here - unlike a plain CREATE OR REPLACE, which preserves it. Both statements
-- are inside the same transaction, so the window where the function is absent is sub-second and
-- atomic with respect to any concurrent caller.
drop function if exists public.fn_agent_tools(text, text);
create or replace function public.fn_agent_tools(p_agent_key text, p_kind text default null)
returns table (
  tool_id text, purpose text, kind text, impl_kind text, impl_target text,
  input_schema jsonb, timeout_seconds integer, max_attempts integer, backoff text,
  failure_behaviour text, requires_current_data boolean, required_credential text
)
language sql stable security definer set search_path = public as $$
  with me as (
    select a.agent_key, a.department,
           coalesce((select array_agg(i.packaged_role_id) from org_role_identity i
                      where i.agent_key = a.agent_key), '{}'::text[]) as role_ids
    from org_agents a where a.agent_key = p_agent_key and a.active
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
$$;
revoke all on function public.fn_agent_tools(text, text) from public;
grant execute on function public.fn_agent_tools(text, text) to service_role;

-- kb_search is reached over HTTP and is behind fn_internal_auth. agent_brain is a registered caller
-- of it already, so its scoped credential is the correct one to present.
update public.agent_tool
   set required_credential = 'cred_fn_agent_brain'
 where impl_kind = 'edge_function' and required_credential is null;

commit;

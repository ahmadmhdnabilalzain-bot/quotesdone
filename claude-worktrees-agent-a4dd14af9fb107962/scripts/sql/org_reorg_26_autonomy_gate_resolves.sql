-- REORGANISING THE AGENT COMPANY - 26: the autonomy gate answered "not blocked" to any alias.
--
-- fn_agent_autonomy_blocked is the gate that says whether an employee is allowed to act on its own.
-- It matched agent_remediation.agent_key and org_role_identity.agent_key EXACTLY against whatever
-- string it was handed. Every one of the 90 employees carries aliases - legacy keys, merged keys,
-- packaged role ids, job titles - so an employee addressed by any of them matched no remediation
-- row, and `exists(...)` over no rows is FALSE.
--
-- The failure direction is the dangerous one. This gate fails OPEN: a blocked employee asked about
-- under another name reports blocked=false, open_remediations=[] and readiness=[] - indistinguishable
-- from an employee in good standing. A gate that answers "cleared" for a name it does not recognise
-- is not a gate.
--
-- All four sites are wrapped, including the echoed 'agent_key' in the output, so a caller logging
-- the response records the employee that was actually checked rather than the string it sent.
--
-- coalesce keeps an unknown key unknown: it still matches nothing, but that is now the honest
-- answer to "who is this?" rather than a false clearance for somebody real.

begin;

create or replace function public.fn_agent_autonomy_blocked(p_agent_key text)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  with me as (select coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key) as k)
  select jsonb_build_object(
    'agent_key', (select k from me),
    'asked_as', p_agent_key,
    'blocked', exists (select 1 from agent_remediation
                        where agent_key = (select k from me) and blocks_autonomy and status <> 'passed'),
    'open_remediations', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'failure_class', failure_class, 'competency', competency, 'status', status))
      from agent_remediation where agent_key = (select k from me) and status <> 'passed'), '[]'::jsonb),
    'readiness', coalesce((select jsonb_agg(distinct readiness) from org_role_identity
                            where agent_key = (select k from me)), '[]'::jsonb));
$function$;

commit;

-- REORGANISING THE AGENT COMPANY - 27: two gates that had to resolve BOTH sides, not one.
--
-- The remaining sql-language routines from the identity inventory. Both differ from org_reorg_23 in
-- an important way: wrapping only the PARAMETER would have been a regression, because the tables
-- they read are themselves keyed by alias.
--
-- fn_onboarding_gate - org_onboarding holds 2 rows under alias keys: 'designer' and 'secretary'.
--   fn_onboarding_gate('designer') works TODAY. Resolve only p_agent and it becomes
--   "no onboarding record - treat as uncertified", which reads as a stricter gate and is actually
--   a lost record. Resolving both sides is what makes the gate answer for the same employee under
--   every name it has.
--
-- fn_agent_handoff_inbox - agent_actions holds 82 rows whose 'agent' is an alias, 28 of them open.
--   Matching the raw column against a resolved parameter would hide an employee's own inbox from
--   it. Both sides, so the inbox is the employee's work regardless of which name filed it.
--
-- The cost is a function call per row on the scan side. These are small, bounded reads - the inbox
-- caps at 3 rows and the gate reads one - so this is the right trade against backfilling two tables
-- whose alias keys are the historical record of who was addressed.
--
-- fn_onboarding_gate also now returns 'asked_as' alongside the resolved 'agent', so a caller can
-- see both what it sent and who answered.
--
-- Bodies are the live staging definitions with only those substitutions applied.

begin;

-- fn_agent_handoff_inbox
CREATE OR REPLACE FUNCTION public.fn_agent_handoff_inbox(p_agent_key text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(line, E'\n' order by created_at)
  from (
    select a.created_at,
           -- Bound the WHOLE line, not its parts. Capping title and recommendation separately
           -- still left four employees over budget because the prefix varies ("from Document
           -- Controller" is longer than "doc_task"). 215 x 3 lines + 2 newlines = 647, inside the
           -- 678 this inbox was trimmed to after it timed agent_brain out twice.
           left(
           '- #'||a.id||' ('||extract(day from now() - a.created_at)::int||'d old, '
             ||case when a.kind = 'handoff'
                    then 'from '||coalesce(a.detail->>'from_name', a.detail->>'from', 'a colleague')
                    else a.kind end
             ||case when a.kind = any(fn_agent_inbox_closable_kinds()) then '' else ', FOUNDER DECIDES — do not close' end
             ||'): '
             -- The TITLE was never capped, only the recommendation. With handoffs only that was
             -- harmless; the wider kinds carry long generated titles and the block measured 821
             -- characters for `docs` and 769 for `it` — both ABOVE the 678 this inbox was trimmed
             -- to after it timed agent_brain out twice at ~56s. `it`'s prompt is 30,821 tokens and
             -- its one prior success took 53,139 ms, so the margin is real and small. Capped at 80
             -- so three lines cannot exceed roughly the budget that was proved safe.
             ||coalesce(a.title,'(untitled)')
             ||coalesce(' — '||a.recommendation, '')
           , 215) as line
      from agent_actions a
     where coalesce(public.fn_org_agent_resolve(a.agent), a.agent)
         = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
       and a.status in ('pending','needs_review')
     order by a.created_at
     limit 3
  ) z;
$function$
;

-- fn_onboarding_gate
-- ROUTINE REMOVED 7 September 2026. public.fn_onboarding_gate was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


commit;

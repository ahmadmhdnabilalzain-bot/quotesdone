-- The hand-written map fell behind the spending — 12 Aug 2026
--
-- ai_cost_log.dept_key is what the automatic budget ceiling reads: fn_ai_route sums month-to-date
-- spend for a department and halts non-gated work at halt_at_pct. A call logged without a dept_key
-- belongs to no department, so it can never be measured and never be halted.
--
-- It is filled by trg_ai_cost_attribute, which looks the calling function up in ai_cost_fn_map — a
-- HAND-MAINTAINED table. Measured on production, this month:
--
--   ai_cost_fn_map rows                                        11
--   distinct functions that actually spent money               37
--   ...of those, absent from the map                           27
--   calls logged with no dept_key                             833   (35.8% of the month)
--   spend outside the ceiling                              31.27 AED
--
-- Nothing failed. The map simply stopped keeping up with the functions, and every function added
-- since spent money outside the ceiling in silence — action_worker, kb_deepen, analytics_recommend,
-- quote_compare, inquiry_intake and twenty-two others.
--
-- A MAP THAT MUST BE UPDATED BY HAND WILL FALL BEHIND AGAIN, so this does not merely add the missing
-- rows. The trigger now falls back to a source that is already authoritative and already maintained
-- for other reasons: org_action_executor, which carries a department for every one of its 56
-- executors and whose `target` is the edge-function slug. The hand map stays FIRST, so it remains an
-- override where a function's department genuinely differs from its executor's; it is simply no
-- longer the only answer. agent_key is tried in between, because an employee's own department beats
-- a function-level default when the call names one.
--
-- MEASURED COVERAGE OF THE FALLBACK: of the 833 unattributed calls this month, 726 resolve through
-- org_action_executor and 48 through org_agents — 774, or 93%. The remaining 59 name a function that
-- is neither an executor nor tied to an employee, and they stay NULL rather than being guessed at.
--
-- SAFE TO APPLY NOW, checked before writing it. Attributing this spend moves departments closer to
-- their thresholds, so the question is whether any would trip. The worst case is exec at 14.58% of
-- its 800 AED budget, against a degrade threshold of 70% and a halt at 95%. Nothing degrades and
-- nothing halts; the effect is that future spend is finally counted.
--
-- The backfill is derivation, not invention: it fills dept_key only from the same two authoritative
-- mappings, and only where it is currently null. It covers all history rather than the current month
-- alone, because a cost record with no department is an incomplete record whenever it was written,
-- and the halt reads month-to-date either way.
--
-- The trigger keeps its `exception when others then return new`: attributing a cost must never be
-- able to stop the cost being recorded.

create or replace function public.trg_ai_cost_attribute()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare m record;
begin
  if new.dept_key is null or new.agent_key is null then
    -- 1. the hand-maintained override, unchanged and still first.
    select * into m from ai_cost_fn_map where fn = new.fn;
    if found then
      new.dept_key  := coalesce(new.dept_key,  m.dept_key);
      new.agent_key := coalesce(new.agent_key, m.agent_key);
    end if;

    -- 2. the employee's own department, when the call names one.
    if new.dept_key is null and new.agent_key is not null then
      select a.department into new.dept_key
        from org_agents a
       where a.agent_key = new.agent_key and a.department is not null
       limit 1;
    end if;

    -- 3. the executor that owns this edge function. Authoritative, already maintained, and the
    --    reason a new function no longer spends money outside the ceiling by default.
    if new.dept_key is null then
      select e.department into new.dept_key
        from org_action_executor e
       where e.target = new.fn and e.department is not null
       limit 1;
    end if;
  end if;
  return new;
exception when others then return new;
end $function$;

-- Backfill, from the same two mappings and only where dept_key is absent.
update public.ai_cost_log l
   set dept_key = coalesce(
         (select a.department from org_agents a
           where a.agent_key = l.agent_key and a.department is not null limit 1),
         (select e.department from org_action_executor e
           where e.target = l.fn and e.department is not null limit 1))
 where l.dept_key is null
   and (exists (select 1 from org_agents a
                 where a.agent_key = l.agent_key and a.department is not null)
     or exists (select 1 from org_action_executor e
                 where e.target = l.fn and e.department is not null));

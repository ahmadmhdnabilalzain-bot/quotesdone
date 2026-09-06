-- DECAY OPENS A TASK FOR ITS OWN QUARANTINE ONLY (6 Sep 2026). Sibling of knowledge_review_dates_follow_source_freshness.sql.
--
-- MEASURED in the aborted probe of the re-dated corpus: fn_knowledge_decay() decayed 2 rows, quarantined
-- 0 - and would have opened 84 org_tasks. Its task population was EVERY agent with a quarantined row,
-- and the exam repair of the same morning had just quarantined 397 rows across 84 agents on purpose,
-- each with its reason on the row (a category route file in the wrong department; a fill written on
-- a wrong verdict). Those are retired, not gaps; "refresh from source" is the wrong instruction for
-- them, and 84 proposed tasks in dept_key 'knowledge' - a department merged into people_ops - would
-- have been invisible noise. A guard that manufactures what it prevents.
--
-- The task population is now the rows DECAY quarantined - confidence under its own 0.35 floor - and
-- the task lands in the live department the old key merged into. The decay and quarantine steps are
-- unchanged.
--   node scripts/apply_sql.mjs scripts/sql/decay_opens_a_task_for_its_own_quarantine_only.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_knowledge_decay()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n_decayed int; n_quarantined int; n_tasks int := 0; v_dept text;
begin
  update agent_knowledge
     set confidence = greatest(0.10, round((confidence - (0.05 * greatest(1, floor(extract(epoch from (now() - review_due))/(30*86400)))))::numeric, 2)),
         validation_status = 'stale'
   where review_due < now()
     and coalesce(validation_status,'') <> 'quarantined'
     and confidence > 0.10;
  get diagnostics n_decayed = row_count;

  update agent_knowledge
     set validation_status = 'quarantined'
   where confidence < 0.35 and coalesce(validation_status,'') <> 'quarantined';
  get diagnostics n_quarantined = row_count;

  -- a quarantined expert is a capability gap, so it becomes work - for the rows THIS routine
  -- quarantined (under its confidence floor). A row quarantined deliberately, with its reason on the
  -- row, is retired knowledge, not a gap to refresh.
  v_dept := coalesce((select d.merged_into from org_departments d where d.dept_key = 'knowledge'), 'knowledge');
  insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
  select v_dept,
         'Knowledge quarantined: '||agent_key,
         count(*)||' knowledge item(s) for '||agent_key||' fell below the confidence floor and are no longer served. '
         ||'Refresh from source and re-validate, or retire the topic.',
         'proposed','advisory', false, 'knowledge_fill'
    from agent_knowledge
   where validation_status='quarantined' and confidence < 0.35
   group by agent_key
  having not exists (select 1 from org_tasks t where t.title='Knowledge quarantined: '||agent_knowledge.agent_key and t.status<>'done');
  get diagnostics n_tasks = row_count;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('knowledge_decay', now(), now(), 'ok',
          jsonb_build_object('decayed',n_decayed,'quarantined',n_quarantined,'tasks',n_tasks),
          'Knowledge decay: '||n_decayed||' item(s) past review lost confidence, '||n_quarantined
          ||' quarantined below the floor, '||n_tasks||' refresh task(s) opened.');

  return jsonb_build_object('decayed',n_decayed,'quarantined',n_quarantined,'tasks',n_tasks);
end $function$;

commit;

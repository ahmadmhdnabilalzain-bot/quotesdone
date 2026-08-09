-- ================================================================================================
-- ROW #8 §24/§25/§44 — the model feedback loop read a table that nothing has ever written.
--
-- ── THE MEASUREMENT THAT ORDERED THIS ───────────────────────────────────────────────────────────
-- Production, 2026-08-09:
--
--     model_outcome rows                                            0
--     routines that INSERT into model_outcome                       NONE
--     edge functions that reference model_outcome                   NONE
--     routines that READ model_outcome    fn_model_benchmark, fn_model_autoswitch   <- both dead
--
--     ai_cost_log rows                                          1,021
--     … carrying task_class, model_used, tier, ok, latency_ms, cost_aed   all of them
--
-- Two routines have been reading an empty table since they were written. `fn_model_benchmark` is
-- the only thing that populates `model_registry.quality_score`, so quality_score is null on all six
-- models; and `fn_model_autoswitch` — the safety loop that promotes a task class off a model that
-- has started failing — could never fire. The spec's §24 (quality scoring), §25 (benchmarking) and
-- §44 (background model switching) all trace back to this one wrong FROM clause.
--
-- ── WHY THE READERS MOVE RATHER THAN A WRITER BEING ADDED ───────────────────────────────────────
-- The obvious alternative is to start writing model_outcome. That would put two tables in the
-- business of recording one event — every AI call — and the two would drift the first time a caller
-- updated one and not the other. ai_cost_log already holds the whole event and is already written on
-- every call by trg_ai_cost_attribute. Moving two FROM clauses is a smaller diff than adding a
-- second writer, and it leaves ONE source of truth instead of two.
--
-- model_outcome is left in place but is now referenced by nothing. It should be dropped once
-- somebody has confirmed no external consumer reads it; dropping a table is not something this
-- change does on its own authority.
--
-- ── WHAT IS PRESERVED EXACTLY ───────────────────────────────────────────────────────────────────
--   · the >= 20 runs floor. "Never judge a model on a handful of runs" was right and is untouched.
--   · the 85% success floor in the autoswitch, and its refusal to act unless the failing model is
--     still the primary for that class.
--   · both signatures, so this is a CREATE OR REPLACE rather than a DROP — no dependent object is
--     invalidated and no permission is reset.
--
-- `coalesce(o.parse_ok, true)` is dropped because ai_cost_log has no parse_ok column. That term
-- already defaulted to TRUE for every row, so removing it changes no verdict — it was a no-op
-- against model_outcome too, which never had a row for it to read.
--
-- cost is converted AED -> USD at the UAE central bank's fixed peg of 3.6725, which is a pegged
-- rate and not a market rate. The return column is named avg_cost_usd and stays that way so this
-- remains a CREATE OR REPLACE.
--
-- ── WHAT THIS WILL AND WILL NOT DO WHEN IT RUNS ─────────────────────────────────────────────────
-- Measured on the same 1,021 rows, five (task_class, model) pairs clear the >= 20 floor:
--
--     agent_reasoning         / claude-sonnet-5    271 runs  92.25%  AED 0.1816/call
--     json_extraction         / gemini-flash-lite  216 runs 100.00%  AED 0.0010
--     memory_retrieval        / gemini-flash-lite  183 runs 100.00%  AED 0.0016
--     knowledge_research      / claude-haiku        89 runs  98.88%  AED 0.0189
--     chief_of_staff_decision / claude-sonnet-5     46 runs  93.48%  AED 0.0847
--
-- Every one is above the autoswitch's 85% floor, so the first real run will promote NOTHING. That
-- is the correct outcome and it is worth stating: the value of this fix is that the loop can now
-- SEE, not that it will immediately act. A loop that fires on its first run after being repaired
-- would be a reason to look harder at the repair.
-- ================================================================================================

create or replace function public.fn_model_benchmark()
returns table(task_class text, model_used text, runs bigint, success_rate numeric, avg_cost_usd numeric, verdict text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  return query
  with s as (
    select o.task_class, o.model_used,
           count(*) as runs,
           round(avg(case when o.ok then 1.0 else 0.0 end), 4) as success_rate,
           round((avg(o.cost_aed) / 3.6725)::numeric, 6) as avg_cost_usd
    from ai_cost_log o
    where o.occurred_at > now() - interval '30 days'
      and o.task_class is not null
      and o.model_used is not null
    group by 1, 2
    having count(*) >= 20   -- never judge a model on a handful of runs
  )
  select s.task_class, s.model_used, s.runs, s.success_rate, s.avg_cost_usd,
         case
           when s.success_rate >= 0.95 then 'GOOD - safe to keep or promote for this class'
           when s.success_rate >= 0.85 then 'ACCEPTABLE - watch'
           else 'POOR - this class needs a stronger tier'
         end
  from s order by s.task_class, s.success_rate desc;

  -- Feed the score back onto the registry so routing can see it. This is the only writer of
  -- model_registry.quality_score, which is why that column was null on all six models.
  update model_registry r set quality_score = q.sr, updated_at = now()
  from (
    select o.model_used, round(avg(case when o.ok then 1.0 else 0.0 end),4) sr
    from ai_cost_log o
    where o.occurred_at > now() - interval '30 days'
      and o.task_class is not null and o.model_used is not null
    group by 1 having count(*) >= 20
  ) q
  where r.model_id = q.model_used;
end $function$;

create or replace function public.fn_model_autoswitch()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_new text; v_n int := 0;
begin
  for r in
    select o.task_class, o.model_used,
           avg(case when o.ok then 1.0 else 0.0 end) sr, count(*) n
    from ai_cost_log o
    where o.occurred_at > now() - interval '14 days'
      and o.task_class is not null
      and o.model_used is not null
    group by 1,2 having count(*) >= 20
       and avg(case when o.ok then 1.0 else 0.0 end) < 0.85
  loop
    -- only act if this model is still the primary for that class
    if not exists (select 1 from model_policy p where p.task_class = r.task_class
                    and p.model_primary = r.model_used and p.active) then continue; end if;

    select mr.model_id into v_new from model_registry mr
     join model_registry cur on cur.model_id = r.model_used
     where mr.active and mr.approved and mr.in_per_mtok_usd > cur.in_per_mtok_usd
     order by mr.in_per_mtok_usd asc limit 1;
    if v_new is null then continue; end if;

    update model_policy set model_primary = v_new where task_class = r.task_class and active;
    v_n := v_n + 1;

    insert into founder_alerts (level, event, detail, channel)
    values ('warn','model_autoswitched',
      'Task class "' || r.task_class || '" was failing on ' || r.model_used || ' (' ||
      round(r.sr*100,1) || '% success over ' || r.n || ' runs, floor 85%). Promoted to ' || v_new ||
      '. Cheaper is only correct while it works; this is the loop that checks.', 'system');

    insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
    values ('it', left('Model auto-switched for ' || r.task_class, 200),
      'Automatic promotion after measured failure. Class: ' || r.task_class ||
      E'\nWas: ' || r.model_used || ' at ' || round(r.sr*100,1) || '% success over ' || r.n || ' runs' ||
      E'\nNow: ' || v_new ||
      E'\n\nReview whether the prompt is at fault rather than the model - a badly specified task fails on every tier, and promoting it just costs more.',
      'proposed','supervised','analysis', false);
  end loop;
  return v_n;
end $function$;

-- Retract the manufactured lessons already in institutional memory
-- ================================================================
--
-- Companion to seventeen_lessons_from_four_readings_and_none_of_them_earned.sql, which stops
-- fn_outcome_evaluate from minting one confirmed lesson per claimant of a shared reading. That
-- fixes every future grading run. It does not touch what the old loop already wrote, and agents
-- retrieve from institutional_memory, so the false claims keep being served until they are pulled.
--
-- What is there today: 17 rows, all confidence 0.9, all ending "Promote to standard practice",
-- generated from FOUR readings. Eight of them tell eight different agents - including legal,
-- contract_specialist, marketing_content and brand_mgr - that their task moved our HTTP
-- health-check pass rate from 80.00 to 100.00.
--
-- This is DATA CORRECTION, not a green-gate exercise. It deletes nothing that is evidence: every
-- measurement stays in outcome_record with its baseline, observed value, delta and verdict
-- untouched, and the surviving memory for each reading names all of its co-claimants. What goes is
-- the duplication and the causal assertion neither the loop nor anyone else can support. The
-- numbers this produces are worse than the ones it replaces, which is the point.
--
-- Idempotent: computed from each project's own rows, safe to re-run, a no-op where nothing matches.

-- 1. The measurement stands; the promotion does not. A shared reading proves the metric moved and
--    nothing about who moved it.
with grp as (
  select o.id, count(*) over w as claimants, min(o.id) over w as lead_id,
         string_agg(o.actor, ', ') over w as actors, o.expected_metric,
         o.baseline_value, o.observed_value
  from outcome_record o
  left join employee_kpi k on k.id = o.expected_kpi_id
  where o.verdict = 'improved'
  window w as (partition by coalesce(k.measure_sql, 'id:'||o.id::text))
)
update outcome_record o
   set promoted = false,
       lesson = g.expected_metric||' moved '||g.baseline_value||' to '||g.observed_value
              ||', but '||g.claimants||' decisions are claiming the same single reading ('||g.actors
              ||'). The metric moved; which decision moved it is NOT established. Not promoted.'
              ||' Retracted 12 Aug 2026: this was recorded as a proven lever and it never was.'
  from grp g
 where g.id = o.id and g.claimants > 1;

-- 2. One memory per reading. The duplicates carry no information the survivor does not, and their
--    only effect on retrieval is to make one observation look like N independent agreements.
delete from institutional_memory im
 using (
   select o.id, min(o.id) over w as lead_id, count(*) over w as claimants
   from outcome_record o
   left join employee_kpi k on k.id = o.expected_kpi_id
   where o.verdict = 'improved'
   window w as (partition by coalesce(k.measure_sql, 'id:'||o.id::text))
 ) g
 where im.kind = 'outcome'
   and im.evidence_ref = 'outcome_record#'||g.id
   and g.claimants > 1
   and g.id <> g.lead_id;

-- 3. The survivor tells the truth: the reading moved, the cause is not isolated.
update institutional_memory im
   set detail = o.lesson,
       confidence = 0.4,
       learned_by = left(g.actors, 200),
       outcome = 'improved_unattributed'
  from outcome_record o
  join (
    select o2.id, count(*) over w as claimants, string_agg(o2.actor, ', ') over w as actors
    from outcome_record o2
    left join employee_kpi k on k.id = o2.expected_kpi_id
    where o2.verdict = 'improved'
    window w as (partition by coalesce(k.measure_sql, 'id:'||o2.id::text))
  ) g on g.id = o.id
 where im.kind = 'outcome'
   and im.evidence_ref = 'outcome_record#'||o.id
   and g.claimants > 1;

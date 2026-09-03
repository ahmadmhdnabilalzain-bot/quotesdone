-- Lift the stand-down cost throttle now that workflow steps run DETERMINISTICALLY (free) — see
-- deterministic_decision_engine.sql. workflow_reflection_steps_per_day/cos_reflection_tasks_per_day
-- capped MODEL-driven steps to control spend; with the deterministic-first engine most steps cost
-- nothing, so the cap was choking the running company (dispatcher hit "9/8 steps worked today"). Raised
-- so the loop processes its backlog; the ~5% model fallback stays gated by the founder hold + the paid
-- gate, which is where any real spend is controlled.
--   node scripts/apply_sql.mjs scripts/sql/lift_deterministic_loop_throttle.sql --apply
begin;
update public.decision_policy set value = to_jsonb(2000) where key = 'workflow_reflection_steps_per_day';
update public.decision_policy set value = to_jsonb(500)  where key = 'cos_reflection_tasks_per_day';
commit;

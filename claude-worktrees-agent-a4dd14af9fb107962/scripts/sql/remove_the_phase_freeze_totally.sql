-- Remove the phase-freeze machinery totally. Founder, 2026-09-02: "what is the point of the freeze —
-- remove it totally", with full authority and the note that the earlier build over-engineered this.
--
-- JUDGEMENT: the Phase A/B/C freeze was build-time change-control — it locked the founder-approved
-- architecture so an unreviewed change could not silently drift it. That protects a MULTI-DEVELOPER
-- team from itself. This is a solo-founder, fully-autonomous company that must EVOLVE itself, so the
-- freeze is pure friction with no upside: it blocks the autonomy and demands signatures for every
-- change. So it goes — physically, not just flagged off.
--
-- This drops the 13 Phase A/B freeze TRIGGERS (org_role, org_departments, and the 11 phase_b_* baseline
-- tables) and removes their component rows, so the freeze can never fire again. Phase C's freeze is a
-- CI-only drift check already neutralised by decision_policy.phase_freezes_lifted (its 25 frozen-subject
-- rows are immutable historical records that no longer block anything). The freeze GUARD functions are
-- left in place, uncalled and inert — dropping them would churn the routine manifest for no behaviour.
--
-- DELIBERATELY UNTOUCHED — these are real safety, not change-control, and stay:
--   * money: refunds route to the founder, auto_action_max_aed=0, fraud_score_max, MFA on money moves;
--   * data loss: fn_kernel_truncate_guard, parent-delete guards;
--   * audit/accounting integrity: gl_journal / gl_journal_lines immutability, decision_trace / llm_attempt
--     append-only, founder_command_message immutable;
--   * the a10 owner-integrity guards on phase_b (a step must have a real owner — not a freeze);
--   * OpenRouter / paid inference stays blocked.
--
--   node scripts/apply_sql.mjs scripts/sql/remove_the_phase_freeze_totally.sql --apply --ddl

begin;

-- Phase A freeze triggers.
drop trigger if exists z90_phase_a_freeze on public.org_role;
drop trigger if exists z90_phase_a_freeze on public.org_departments;

-- Phase B freeze triggers (the 11 baseline tables).
drop trigger if exists z90_phase_b_freeze on public.phase_b_business_rule;
drop trigger if exists z90_phase_b_freeze on public.phase_b_dynamic_actor;
drop trigger if exists z90_phase_b_freeze on public.phase_b_founder_boundary;
drop trigger if exists z90_phase_b_freeze on public.phase_b_gate;
drop trigger if exists z90_phase_b_freeze on public.phase_b_handoff;
drop trigger if exists z90_phase_b_freeze on public.phase_b_step_state;
drop trigger if exists z90_phase_b_freeze on public.phase_b_step_transition;
drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow;
drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_state;
drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_step;
drop trigger if exists z90_phase_b_freeze on public.phase_b_workflow_transition;

-- The component registry rows for those dropped triggers (they reference an object that no longer exists).
delete from public.phase_c_component
 where component_id in (
   'trigger:org_role.z90_phase_a_freeze',
   'trigger:org_departments.z90_phase_a_freeze',
   'trigger:phase_b_business_rule.z90_phase_b_freeze',
   'trigger:phase_b_dynamic_actor.z90_phase_b_freeze',
   'trigger:phase_b_founder_boundary.z90_phase_b_freeze',
   'trigger:phase_b_gate.z90_phase_b_freeze',
   'trigger:phase_b_handoff.z90_phase_b_freeze',
   'trigger:phase_b_step_state.z90_phase_b_freeze',
   'trigger:phase_b_step_transition.z90_phase_b_freeze',
   'trigger:phase_b_workflow.z90_phase_b_freeze',
   'trigger:phase_b_workflow_state.z90_phase_b_freeze',
   'trigger:phase_b_workflow_step.z90_phase_b_freeze',
   'trigger:phase_b_workflow_transition.z90_phase_b_freeze');

commit;

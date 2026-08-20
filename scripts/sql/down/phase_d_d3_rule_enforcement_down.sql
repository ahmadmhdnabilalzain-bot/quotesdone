-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d3_rule_enforcement.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row count below, accepts it, and runs it.
--
-- OBJECTS DROPPED, by name (never `cascade`):
--   public.phase_d_rule_enforcement — with phase_d_rule_enforcement_pkey,
--   phase_d_rule_enforcement_enforcement_kind_check (7 values), _status_check (ENFORCED /
--   OUTSTANDING) and phase_d_rule_enforcement_rule_id_fkey -> public.phase_b_business_rule(rule_id)
--
-- THE CONSTRAINT PAIR AT d3:65-70 HAS NO DOWN, AND NEEDS NONE. Those lines drop and re-add
-- phase_d_rule_enforcement_enforcement_kind_check with exactly the same seven values already
-- written into the CREATE TABLE at d3:47-49 — PREDICATE, KERNEL_ENFORCED, TRIGGER_ENFORCED,
-- CONTEXT_REQUIRED, SCHEMA_ENFORCED, EXECUTOR_ENFORCED, PENDING_OBJECT_MAP. It is a defensive
-- idempotency reconcile for a re-apply against an already-existing table, not a widening. Live
-- carries those same seven values. So there is no predecessor definition to restore: the down for
-- that pair is a no-op, and the only thing this file has to do is drop the table.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_rule_enforcement   54 rows — one per frozen Phase B business rule. The rule ids
--   themselves survive in public.phase_b_business_rule; what is destroyed is the enforcement_kind,
--   enforcement_point, refusal_code, applies_when, required_context and evidence for each.
--
-- NOT TOUCHED: the three CREATE OR REPLACE FUNCTION bodies in d3 (fn_phase_d_rule_state and
-- family). A create-or-replace has no down — see scripts/sql/down/README.md. fn_phase_d_rule_state()
-- reads this table and will raise once it is gone; that is the expected post-rollback state, not a
-- second defect.
-- =================================================================================================

begin;

drop table if exists public.phase_d_rule_enforcement;

do $ctl$
begin
  if to_regclass('public.phase_d_rule_enforcement') is not null then
    raise exception 'D3 down did not take: public.phase_d_rule_enforcement is still present.';
  end if;

  raise notice 'D3 down: phase_d_rule_enforcement is gone. The d3:65-70 constraint reconcile needed no down.';
end $ctl$;

commit;

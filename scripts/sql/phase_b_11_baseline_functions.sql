-- Phase B — the digest the freeze is built on, and the drift reader that checks it.
--
-- ONE definition of the digest, in SQL, used by both the recorded baseline and the freeze
-- guard. Phase A learned this the expensive way round: its guard compares COUNTS, so swapping
-- two managers while keeping the head-count identical passes the trigger and is only caught
-- later by the separate digest check. Phase B's guard compares the digest itself, so a change
-- that preserves every count is refused at the moment it is written.
--
-- The recipe matches scripts/phase_a/freeze.mjs exactly: one line per row, fields joined by '|',
-- lines joined by a newline, sha256 hex of the UTF-8 bytes, ordered by a stable sort key. The
-- same organisation therefore yields the same digest whatever order the server returns rows in.
--
-- Subjects are the founder's own list of what may not change, one digest each, so drift names
-- WHICH of them moved rather than reporting a single opaque mismatch.

set lock_timeout = '8s';
set statement_timeout = '600s';

create or replace function public.fn_phase_b_structure_digest()
returns table(subject text, rows bigint, sha256 text)
language sql
stable
set search_path = public, pg_temp
as $$
with
-- workflow ownership: who is accountable, and who independently reviews
workflow_ownership as (
  select w.workflow_id sortkey,
         w.workflow_id||'|'||w.accountable_role_id||'|'||coalesce(w.independent_reviewer_role_id,'') x
  from public.phase_b_workflow w
),
step_ownership as (
  select s.step_id sortkey,
         s.step_id||'|'||s.accountable_role_id||'|'||coalesce(s.independent_reviewer_role_id,'')
         ||'|'||s.actor_kind x
  from public.phase_b_workflow_step s
),
-- workflow order: sequence and both onward paths
workflow_order as (
  select s.step_id sortkey,
         s.workflow_id||'|'||s.step_no::text||'|'||s.step_id||'|'||s.next_step_if_pass
         ||'|'||s.next_step_if_fail||'|'||s.is_closure_step::text x
  from public.phase_b_workflow_step s
),
-- states and transitions, workflow and step
states_and_transitions as (
  select 'A'||state sortkey, 'wf_state|'||state||'|'||terminal::text x from public.phase_b_workflow_state
  union all
  select 'B'||state, 'step_state|'||state||'|'||terminal::text from public.phase_b_step_state
  union all
  select 'C'||from_state||'>'||to_state, 'wf_transition|'||from_state||'|'||to_state
    from public.phase_b_workflow_transition
  union all
  select 'D'||from_state||'>'||to_state, 'step_transition|'||from_state||'|'||to_state
    from public.phase_b_step_transition
),
gates as (
  select g.gate_id sortkey,
         g.gate_id||'|'||g.gate_name||'|'||g.workflow_scope||'|'||g.gate_type
         ||'|'||g.required_evidence||'|'||g.pass_result||'|'||g.fail_result x
  from public.phase_b_gate g
),
business_rules as (
  select r.rule_id sortkey, r.rule_id||'|'||r.rule_name||'|'||r.workflow_scope||'|'||r.rule_type
         ||'|'||r.rule_text x
  from public.phase_b_business_rule r
),
-- handoff accountability: the three named parties and the edge they sit on
handoff_accountability as (
  select h.handoff_id sortkey,
         h.handoff_id||'|'||h.from_step_id||'|'||h.to_step_id||'|'||h.sending_role_id
         ||'|'||h.receiving_role_id||'|'||h.return_owner_role_id||'|'||h.handoff_type x
  from public.phase_b_handoff h
),
-- category-overlay authority: where an overlay may be accountable, and which placeholders may be
overlay_authority as (
  select 'A'||s.step_id sortkey, 'overlay_step|'||s.step_id||'|'||s.workflow_id||'|'||s.step_type x
  from public.phase_b_workflow_step s where s.actor_kind = 'category_overlay'
  union all
  select 'B'||a.actor_token, 'actor|'||a.actor_token||'|'||a.actor_type||'|'||a.may_be_accountable::text
  from public.phase_b_dynamic_actor a
),
founder_boundaries as (
  select b.boundary_id sortkey,
         b.boundary_id||'|'||b.boundary_name||'|'||b.workflow_scope||'|'||b.decision_owner
         ||'|'||b.phase_b_enforcement x
  from public.phase_b_founder_boundary b
),
all_subjects as (
  select 'workflow_ownership' s, sortkey, x from workflow_ownership
  union all select 'step_ownership', sortkey, x from step_ownership
  union all select 'workflow_order', sortkey, x from workflow_order
  union all select 'states_and_transitions', sortkey, x from states_and_transitions
  union all select 'gates', sortkey, x from gates
  union all select 'business_rules', sortkey, x from business_rules
  union all select 'handoff_accountability', sortkey, x from handoff_accountability
  union all select 'overlay_authority', sortkey, x from overlay_authority
  union all select 'founder_boundaries', sortkey, x from founder_boundaries
)
select s,
       count(*)::bigint,
       encode(sha256(convert_to(string_agg(x, chr(10) order by sortkey), 'UTF8')), 'hex')
from all_subjects group by s order by s;
$$;

comment on function public.fn_phase_b_structure_digest() is
  'One digest per frozen Phase B subject, computed the same way scripts/phase_a/freeze.mjs computes its registries. Used by both the recorded baseline and the freeze guard, so the two cannot drift.';

-- --------------------------------------------------------------------- drift reader
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_b_baseline_drift was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


comment on function public.fn_phase_b_baseline_drift() is
  'Zero rows means the founder-approved Phase B baseline is intact. Any row names the subject that moved.';

-- ------------------------------------------------------- Phase C wiring gaps, not Phase B defects
-- Recorded at the founder''s instruction so the next phase inherits them as work rather than
-- finding them as failures. These are measurements of the CURRENT runtime, not defects in the
-- approved architecture.
create table if not exists public.phase_b_phase_c_wiring_gap (
  gap_id       bigint generated always as identity primary key,
  gap          text not null,
  measurement  text not null,
  evidence_command text not null,
  recorded_at  timestamptz not null default now(),
  constraint phase_b_phase_c_wiring_gap_unique unique (gap)
);

comment on table public.phase_b_phase_c_wiring_gap is
  'Runtime wiring gaps the founder accepted as Phase C work when approving Phase B. Not defects in the approved architecture.';

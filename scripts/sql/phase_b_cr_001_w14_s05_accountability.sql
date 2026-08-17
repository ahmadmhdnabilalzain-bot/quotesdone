-- PBCR-001 — W14-S05 accountability: an overlay contributes, it does not own.
--
-- Founder change request ID in the brief: PHASE_B_CR_W14_S05_ACCOUNTABILITY.
-- Recorded here as PBCR-001, the first formal amendment to the Phase B architecture the founder
-- approved and froze on 15 Aug 2026.
--
-- THE OBSERVED PROBLEM, measured before this file was written:
--
--   select * from public.fn_kernel_workflow_graph_validate() where verdict <> 'OK';
--     W14  REGISTRY_DEFECT  "1 reachable step(s) the engine cannot progress from; 1 successor
--                            owner(s) that do not resolve to an active canonical role; 1 step
--                            owner(s) unresolved; closure is topologically reachable but NOT
--                            executable: the walk stops at a step the engine refuses to open"
--
--   select * from public.fn_phase_c_resolve_actor('relevant_category_overlay');
--     kind=unknown, reason='no active canonical role, alias or system actor named
--     ''relevant_category_overlay'''
--
-- W14-S05 is accountable to `relevant_category_overlay`. That token is a dynamic overlay
-- placeholder, not a canonical role, so fn_kernel_open_step cannot open the step, W14 cannot reach
-- its closure step W14-S09, and the whole 30-workflow estate carries "1 workflow with no
-- executable closure path". It is the ONLY step in the 257 with actor_kind = 'category_overlay',
-- and `relevant_category_overlay` is the only dynamic actor besides `founder` carrying
-- may_be_accountable = true.
--
-- THE NAME. The founder's amendment names the new owner `quote_evaluation_specialist`. That is the
-- package accountable token; the canonical Phase A role_id behind it is `quote_evaluation`, whose
-- display_name is exactly "Quote Evaluation Specialist" and which already owns the other eight
-- W14 steps (W14-S04's package_accountable_token is literally 'quote_evaluation_specialist').
-- So this file writes accountable_role_id = 'quote_evaluation' and
-- package_accountable_token = 'quote_evaluation_specialist'. No role is created: Phase A's role
-- count does not move, and fn_phase_a_baseline_drift() must stay at 0 rows.
--
-- WHAT MOVES, and what does not:
--   moves  phase_b_workflow_step.W14-S05  owner, token, actor_kind, contributors, notes
--   moves  phase_b_dynamic_actor.relevant_category_overlay  may_be_accountable true -> false
--   moves  phase_b_handoff  H-W14-04-05 and H-W14-05-06 deleted (161 -> 159)
--   still   30 workflows, 257 steps, 56 objects, 54 rules, 32 gates, 50 exceptions, 34 SLAs,
--           347 events, 10 founder boundaries, 86 category overlays, 176 canonical roles,
--           10 departments
--
-- WHY THE TWO HANDOFFS GO. `phase_b_handoff_two_parties` is a CHECK constraint:
-- sending_role_id <> receiving_role_id. Once W14-S05 is owned by quote_evaluation, both edges
-- become quote_evaluation -> quote_evaluation and the constraint refuses them. That is the
-- registry telling the truth: W14-S03 -> W14-S04, also quote_evaluation to quote_evaluation,
-- carries no handoff edge either. fn_kernel_workflow_graph_validate already classifies these as
-- "legitimate same-owner hops with no handoff edge (not a defect)" and counts 66 of them. These
-- two become the 67th and 68th. Deleting them also removes the last two rows naming
-- `category_overlay` as a sending or receiving department — a department that does not exist in
-- the frozen Phase A org of ten.
--
-- The overlay is NOT removed from the step. It moves from accountable_role_id into contributors,
-- where the founder placed it: a REQUIRED technical contributor that may not own a task or a state
-- transition. `relevant_domain_specialist` stays a CONDITIONAL contributor, resolved only for
-- complex, multi-category or cross-trade scope — its own resolution_rule already says so.
-- Compliance, Risk, Legal and Trust are not added as standing reviewers:
-- independent_reviewer_role_id stays NULL, because they review only when a registered risk or
-- regulatory trigger fires, and a standing reviewer column would make that unconditional.
--
-- Rollback: scripts/sql/rollback/phase_b_cr_001_w14_s05_accountability.rollback.sql

begin;

set local app.phase_b_change_reason =
  'PBCR-001: W14-S05 Validate technical completeness moves from the dynamic overlay placeholder '
  'relevant_category_overlay to canonical role quote_evaluation (Quote Evaluation Specialist, '
  'package token quote_evaluation_specialist). Evidence: fn_kernel_workflow_graph_validate() '
  'reports W14 REGISTRY_DEFECT, closure topologically reachable but NOT executable, 1 unresolved '
  'step owner; fn_phase_c_resolve_actor(''relevant_category_overlay'') returns kind=unknown. The '
  'overlay becomes a required technical contributor and may_be_accountable is set false, so no '
  'overlay can own a task or a state transition. Handoffs H-W14-04-05 and H-W14-05-06 are deleted '
  'because both ends become the same role and phase_b_handoff_two_parties refuses that; the same '
  'shape already exists unrefused at W14-S03->S04. Approved by the founder, 17 Aug 2026, as '
  'PHASE_B_CR_W14_S05_ACCOUNTABILITY. Full record: docs/phase-b/PBCR-001_W14_S05_ACCOUNTABILITY.md '
  'and public.phase_b_change_request.';

-- ------------------------------------------------------------------ 1. the change record
--
-- The formal record is a row, not only a document. It is append-only: a change request that can be
-- edited after approval is a note, not a record.
create table if not exists public.phase_b_change_request (
  change_request_id      text primary key,
  founder_reference      text not null,
  raised_at              timestamptz not null default now(),
  observed_problem       text not null,
  evidence               text not null,
  current_workflow_step  text not null,
  proposed_change        text not null,
  affected_owners        text not null,
  state_machine_impact   text not null,
  gate_and_rule_impact   text not null,
  customer_supplier_impact text not null,
  privacy_legal_financial_impact text not null,
  backward_compatibility text not null,
  founder_approval_required boolean not null,
  founder_approved_by    text,
  founder_approved_at    timestamptz,
  digest_subjects_moved  text[] not null default '{}',
  verification_plan      text not null,
  applied_at             timestamptz,
  constraint phase_b_cr_approved_when_required
    check (not founder_approval_required
           or (founder_approved_by is not null and founder_approved_at is not null))
);

comment on table public.phase_b_change_request is
  'PBCR. The formal, append-only record of every amendment to the Phase B architecture the founder '
  'approved and froze on 2026-08-15. One row per change request, carrying the eleven elements '
  'PHASE_B_CHANGE_REQUEST_TEMPLATE.md requires. Rows may never be updated or deleted: a change '
  'request that can be edited after approval is a note, not a record. Superseding a change means '
  'writing the next one.';

create or replace function public.fn_phase_b_change_request_append_only()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $cr_ao$
begin
  raise exception
    'phase_b_change_request is append-only. % on % is refused. A change request is the audit trail '
    'for a frozen architecture; correcting one means raising the next change request that '
    'supersedes it, so both remain readable.',
    tg_op, coalesce(old.change_request_id, new.change_request_id);
end
$cr_ao$;

revoke all on function public.fn_phase_b_change_request_append_only() from public;

drop trigger if exists a00_phase_b_cr_append_only on public.phase_b_change_request;
create trigger a00_phase_b_cr_append_only
  before update or delete on public.phase_b_change_request
  for each row execute function public.fn_phase_b_change_request_append_only();

alter table public.phase_b_change_request enable row level security;
revoke all on public.phase_b_change_request from public, anon, authenticated;
grant select on public.phase_b_change_request to service_role;

insert into public.phase_b_change_request (
  change_request_id, founder_reference, observed_problem, evidence, current_workflow_step,
  proposed_change, affected_owners, state_machine_impact, gate_and_rule_impact,
  customer_supplier_impact, privacy_legal_financial_impact, backward_compatibility,
  founder_approval_required, founder_approved_by, founder_approved_at,
  digest_subjects_moved, verification_plan, applied_at)
values (
  'PBCR-001',
  'PHASE_B_CR_W14_S05_ACCOUNTABILITY',
  'W14 — Quotation Submission and Evaluation cannot reach its closure step. W14-S05 Validate '
  'technical completeness is accountable to relevant_category_overlay, a dynamic overlay '
  'placeholder that does not resolve to an active canonical role, so the execution kernel refuses '
  'to open the step and the workflow stops there.',
  'fn_kernel_workflow_graph_validate(): W14 verdict REGISTRY_DEFECT, "closure is topologically '
  'reachable but NOT executable: the walk stops at a step the engine refuses to open"; SUMMARY row '
  'unresolved_successor_owners=1, owners_unresolved=1, closure_path_executable=false, workflows '
  'without an executable closure path 1 of 30. fn_phase_c_resolve_actor(''relevant_category_overlay'') '
  'returns kind=unknown, reason "no active canonical role, alias or system actor named '
  '''relevant_category_overlay''". W14-S05 is the only one of 257 steps with '
  'actor_kind=''category_overlay''.',
  'W14 / W14-S05 (step_no 5, step_type analysis, next_step_if_pass W14-S06, next_step_if_fail '
  'WORKFLOW_BLOCKED_OR_ESCALATED).',
  'accountable_role_id relevant_category_overlay -> quote_evaluation; package_accountable_token '
  'relevant_category_overlay -> quote_evaluation_specialist; actor_kind category_overlay -> '
  'canonical_role; contributors {quote_evaluation, relevant_domain_specialist} -> '
  '{relevant_category_overlay, relevant_domain_specialist}; phase_b_dynamic_actor '
  'relevant_category_overlay.may_be_accountable true -> false; handoffs H-W14-04-05 and '
  'H-W14-05-06 deleted.',
  'GAINS: quote_evaluation (Quote Evaluation Specialist, marketplace) becomes accountable for '
  'W14-S05, consistent with its ownership of the other eight W14 steps and with its remit over '
  'quotation normalization, validation and comparison. LOSES: relevant_category_overlay loses '
  'accountability everywhere — it was accountable on exactly one step — and becomes a required '
  'technical contributor. relevant_domain_specialist is unchanged: still a conditional contributor '
  'resolved only when multi-category coordination requires it. No canonical role is created, '
  'renamed, retired or re-departmented.',
  'None. W14-S05 keeps step_no 5, step_type analysis, entry_condition, next_step_if_pass W14-S06, '
  'next_step_if_fail WORKFLOW_BLOCKED_OR_ESCALATED, success_workflow_state waiting_handoff and '
  'failure_workflow_state blocked. No workflow state, step state or transition is added, removed '
  'or re-routed. The change makes an already-declared transition executable that previously was '
  'not; no run can become stuck by it, and no run was ever in flight at W14-S05 because the step '
  'could not be opened.',
  'No gate and no business rule is added, removed, weakened or re-scoped. The 32 gates and 54 '
  'business rules are untouched. The change makes one gate STRICTER in effect, not weaker: '
  'fn_kernel_open_step now has a resolvable owner to check authority against, where before it '
  'refused the step outright.',
  'None visible to either. A supplier quotation still passes commercial validation, then technical '
  'validation, then clarification if needed. What changes is that the technical validation can now '
  'actually complete and the quotation can reach comparison — before this change, no quotation '
  'could pass W14-S05 at all.',
  'None. No identity is revealed, no terms are accepted, no money moves, no refund authority '
  'changes, no retention window changes. The nearest founder-reserved boundary is untouched: '
  'W14-S05 carries founder_gate = none before and after.',
  'No historical record is deleted, edited or back-dated. There are zero phase_c_task rows and '
  'zero phase_c_workflow_step_run rows owned by relevant_category_overlay or by any '
  'category_overlay_* role, because the step could never be opened. The two deleted handoff '
  'definitions have zero phase_c_handoff_run rows against them. phase_b_dynamic_actor keeps the '
  'relevant_category_overlay token, its meaning and its resolution rule; only its authority to be '
  'accountable is withdrawn.',
  true,
  'founder (management@doratajewelries.com), brief of 2026-08-17: '
  '"The founder approves this exact Phase B amendment ... Change request ID: '
  'PHASE_B_CR_W14_S05_ACCOUNTABILITY"',
  now(),
  array['step_ownership','overlay_authority','handoff_accountability'],
  'node scripts/checks/phase_b_invariants.test.mjs; '
  'node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs; '
  'select * from public.fn_kernel_workflow_graph_validate() where verdict <> ''OK'' -- expect 0 rows; '
  'select * from public.fn_phase_a_baseline_drift() -- expect 0 rows; '
  'select * from public.fn_phase_b_baseline_drift() -- expect 0 rows after re-freeze; '
  'node scripts/phase_b/freeze.mjs --emit',
  now())
on conflict (change_request_id) do nothing;

-- ------------------------------------------------------------------ 2. the step
update public.phase_b_workflow_step
   set accountable_role_id       = 'quote_evaluation',
       package_accountable_token = 'quote_evaluation_specialist',
       actor_kind                = 'canonical_role',
       contributors              = array['relevant_category_overlay','relevant_domain_specialist'],
       notes = 'PBCR-001 (2026-08-17). Owner moved from relevant_category_overlay to '
               'quote_evaluation (Quote Evaluation Specialist), which owns quotation '
               'normalization, validation and comparison. The relevant category overlay is a '
               'REQUIRED technical contributor on every run of this step: it supplies the '
               'category-specific technical judgement, and it may not own the task or the state '
               'transition. relevant_domain_specialist is a CONDITIONAL contributor, resolved only '
               'for complex, multi-category or cross-trade scope. Compliance, Risk, Legal and '
               'Trust roles review only when a registered risk or regulatory trigger requires it, '
               'which is why independent_reviewer_role_id stays NULL rather than naming a standing '
               'reviewer.'
 where step_id = 'W14-S05';

-- ------------------------------------------------------------------ 3. the overlay's authority
--
-- The founder's boundary in his own words: "an overlay may provide expertise; an overlay may not
-- own a task or state transition". With W14-S05 reassigned this is now true of the whole registry,
-- so the declaration is made to say so instead of merely happening to be so.
update public.phase_b_dynamic_actor
   set may_be_accountable = false,
       resolution_rule = 'Resolve from the approved canonical route set; overlays cannot receive '
                         'prohibited authority. PBCR-001 (2026-08-17): an overlay contributes '
                         'expertise and may never be the accountable owner of a task or a state '
                         'transition. Contributor slots only.'
 where actor_token = 'relevant_category_overlay';

-- ------------------------------------------------------------------ 4. the handoff graph
--
-- Both edges now have the same role at each end. phase_b_handoff_two_parties refuses that, and the
-- registry's own convention for a same-owner hop is no edge at all (W14-S03 -> W14-S04 has none).
delete from public.phase_b_handoff where handoff_id in ('H-W14-04-05','H-W14-05-06');

commit;

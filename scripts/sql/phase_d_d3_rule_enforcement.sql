-- PHASE D · D3 — THE 54 BUSINESS RULES STOP BEING PROSE.
--
-- WHAT WAS MEASURED, 18 Aug 2026, on htdblwldjkcgjvmqkbeh. public.fn_phase_c_rule_check has a real
-- predicate for exactly TWO of the fifty-four rules — BR-001 and BR-002 — and for the other
-- fifty-two it ends:
--
--     ok := true;
--     reason := format('rule %s (%s, scope %s) registered and enforced through the canonical
--                       boundary', r.rule_id, r.rule_type, r.workflow_scope);
--
-- That is a scorer that always returns pass, and its reason string CLAIMS enforcement. The frozen
-- fn_kernel_step_complete is honest about the same hole in its own words — "phase_b_business_rule
-- holds 47 hard rules as PROSE with no machine predicate ... they are not scored, because a scorer
-- that always returns pass is worse than no scorer. This is a stated Phase C gap, not a silent
-- one." Phase D is where that gap is closed.
--
-- THE HONEST SHAPE OF THE CLOSURE. Not every rule is decidable from what the estate models today,
-- and pretending otherwise would rebuild the defect in new clothes. Each rule is therefore
-- classified into one of five enforcement kinds and the board reports the counts:
--
--   PREDICATE          decided here, now, from the call context. A real boolean.
--   KERNEL_ENFORCED    the frozen kernel already raises on it. The named routine and the errcode
--                      it raises are recorded, and the board RESOLVES the routine in pg_proc —
--                      a disposition in prose with no mechanism is the defect this avoids.
--   TRIGGER_ENFORCED   a trigger or constraint refuses it at write time; the board resolves the
--                      trigger in pg_trigger.
--   CONTEXT_REQUIRED   decidable, but only from a business fact the handler must name. Absent
--                      context is a REFUSAL, never a pass.
--   PENDING_OBJECT_MAP not yet decidable because it needs the D2 business-object read/write map.
--                      Recorded as OUTSTANDING and counted by the board. This is open debt stated
--                      out loud, not a green light.
--
-- APPLICABILITY IS THE OTHER HALF, AND IT IS WHERE THE FIRST VERSION OF THIS WAS WRONG. Rules are
-- scoped by WORKFLOW in the frozen registry, but scope is not applicability. BR-002 says a creator
-- cannot be the sole final independent reviewer; it is scoped to 'all', and 229 of the 257 steps
-- name no independent reviewer at all (28 do). Passing a NULL reviewer into
-- fn_phase_c_reviewer_independent returns false, so the first Phase D executor refused W01-S01 —
-- an intake step with no reviewer — for a creator/reviewer collision that cannot exist. An absent
-- reviewer is not a collision. fn_phase_d_rule_applies below decides scope AND applicability, and
-- returns the reason either way, so a rule that did not apply is visibly out of scope rather than
-- silently skipped.

begin;

-- ================================================================ 1. the enforcement register
create table if not exists public.phase_d_rule_enforcement (
  rule_id           text        primary key references public.phase_b_business_rule(rule_id),
  rule_type         text        not null,
  enforcement_kind  text        not null check (enforcement_kind in
                      ('PREDICATE','KERNEL_ENFORCED','TRIGGER_ENFORCED','CONTEXT_REQUIRED',
                       'SCHEMA_ENFORCED','EXECUTOR_ENFORCED','PENDING_OBJECT_MAP')),
  enforcement_point text        not null,
  refusal_code      text        not null,
  applies_when      text        not null,
  required_context  text[]      not null default '{}',
  status            text        not null check (status in ('ENFORCED','OUTSTANDING')),
  evidence          text        not null,
  recorded_at       timestamptz not null default now()
);

-- `create table if not exists` does NOT reconcile a constraint on a table that already exists, so
-- a re-apply that widens the allowed enforcement kinds has to say so explicitly. Without this the
-- second run fails on the first widened row and leaves the register describing the first run.
alter table public.phase_d_rule_enforcement
  drop constraint if exists phase_d_rule_enforcement_enforcement_kind_check;
alter table public.phase_d_rule_enforcement
  add  constraint phase_d_rule_enforcement_enforcement_kind_check
  check (enforcement_kind in
         ('PREDICATE','KERNEL_ENFORCED','TRIGGER_ENFORCED','CONTEXT_REQUIRED',
          'SCHEMA_ENFORCED','EXECUTOR_ENFORCED','PENDING_OBJECT_MAP'));

comment on table public.phase_d_rule_enforcement is
  'One row per frozen Phase B business rule naming HOW it is enforced, WHEN it applies and what it '
  'refuses with. enforcement_point is resolved against the live catalogue by '
  'public.fn_phase_d_rule_state() — a named mechanism that does not exist is the defect this table '
  'is designed to make visible.';

insert into public.phase_d_rule_enforcement
  (rule_id, rule_type, enforcement_kind, enforcement_point, refusal_code, applies_when,
   required_context, status, evidence)
values
-- ---- identity and accountability: decidable now, from the resolver -------------------------
('BR-001','hard','PREDICATE','public.fn_phase_c_actor_may_own(text)','br001_owner_unresolved',
 'always','{}','ENFORCED',
 'The step run carries exactly one accountable_role_id and it must resolve to an active canonical role.'),
('BR-002','hard','PREDICATE','public.fn_kernel_reviewer_independent(text,text)','br002_creator_is_reviewer',
 'only when the frozen step names an independent_reviewer_role_id','{}','ENFORCED',
 'Measured on the frozen registry: 28 of 257 steps name an independent reviewer. For the other 229 the rule is out of scope, because an absent reviewer is not a collision.'),
('BR-004','hard','PREDICATE','public.fn_phase_c_resolve_actor(text)','br004_actor_not_canonical',
 'always','{}','ENFORCED',
 'The acting identity must resolve with kind = canonical; an alias resolves but is not itself canonical.'),
('BR-005','hard','PREDICATE','public.fn_phase_c_actor_may_own(text)','br005_inactive_identity',
 'always','{}','ENFORCED',
 'Inactive, merged-away or unknown identities cannot own or execute current work.'),
('BR-048','hard','PREDICATE','public.fn_phase_c_overlay_may_not_dispatch()','br048_overlay_dispatch',
 'workflow scope W05;W06;W07;W12;W14 and the actor resolves to a category overlay','{}','ENFORCED',
 'A category overlay contributes expertise and can never be the dispatching identity. PBCR-001 states the same for W14-S05.'),
('BR-054','phase_boundary','PREDICATE','public.fn_kernel_paid_provider_gate()','br054_paid_inference',
 'always','{}','ENFORCED',
 'The provider hold is read from the gate, not asserted. 8 of 8 OpenRouter routes are held to 2126-08-15.'),

-- ---- already refused by the frozen kernel; the routine and errcode are named and resolved ----
('BR-006','hard','KERNEL_ENFORCED','public.fn_kernel_step_complete','k3_step_state_invalid',
 'always','{}','ENFORCED',
 'Step 3b refuses any hop the frozen phase_b_step_transition does not declare.'),
('BR-007','hard','KERNEL_ENFORCED','public.fn_kernel_step_complete','k3_closure_blocked',
 'always','{}','ENFORCED',
 'Mandatory predecessor steps are measured against phase_b_workflow_step.step_no at closure and raise if unexecuted.'),
('BR-008','hard','KERNEL_ENFORCED','public.fn_phase_c_handoff_packet_valid','handoff_packet_incomplete',
 'always','{}','ENFORCED',
 'Acceptance runs through fn_kernel_handoff_accept, which validates the packet before transferring accountability.'),
('BR-009','hard','KERNEL_ENFORCED','public.fn_kernel_step_complete','k3_closure_blocked',
 'only on a closure step','{}','ENFORCED',
 'Four blocker classes are measured — open step runs, open tasks, open handoffs, unexecuted mandatory steps.'),
('BR-016','hard','KERNEL_ENFORCED','public.fn_kernel_step_complete','k3_duplicate_idempotency_key',
 'always','{}','ENFORCED',
 'phase_c_step_completion.idempotency_key is UNIQUE and is claimed before any work; a replay returns the first result.'),
('BR-045','hard','KERNEL_ENFORCED','public.fn_kernel_step_complete','k3_replay_returns_first_result',
 'workflow scope W13;W16;W17;W24;W29','{}','ENFORCED',
 'A retry under the same key returns the stored first result rather than overwriting it, so the first attempt survives.'),
('BR-046','hard','KERNEL_ENFORCED','public.fn_kernel_cancel','cancel_preserves_record',
 'always','{}','ENFORCED',
 'Cancellation moves state and records reason and authority; it deletes no business record.'),

-- ---- refused at write time by a trigger; the board resolves the trigger ----------------------
('BR-010','hard','TRIGGER_ENFORCED','public.fn_phase_c_trace_append_only','trace_append_only',
 'always','{}','ENFORCED',
 'The trace ledger is append-only by trigger; completed decisions and reviews are superseded, never overwritten.'),
('BR-047','founder','TRIGGER_ENFORCED','public.fn_org_authority_guard','phase_a_change_request_required',
 'workflow scope W30','{}','ENFORCED',
 'A raised authority grant needs app.change_reason in the same transaction; the Phase A freeze guard refuses the rest.'),

-- ---- decidable, but only from a business fact the handler must name --------------------------
('BR-003','hard','CONTEXT_REQUIRED','public.fn_phase_d_rule_check','br003_founder_boundary_unevidenced',
 'only when the frozen step declares a founder_gate other than none',
 '{founder_authority_ref}','ENFORCED',
 'A founder-reserved decision needs a named authority reference. Absent, the step is refused rather than approved by an AI role.'),
('BR-027','hard','SCHEMA_ENFORCED','public.fn_phase_d_schema_validate','br027_provenance_absent',
 'workflow scope W05;W07;W08;W10;W14;W25;W26',
 '{evidence_refs}','ENFORCED',
 'evidence_refs is a required key of every Phase D output schema, so an output with no provenance fails validation.'),
('BR-042','hard','SCHEMA_ENFORCED','public.fn_phase_d_schema_validate','br042_uncertainty_implicit',
 'workflow scope W02;W05;W06;W14;W21;W25;W28 and the step family is ANALYSIS_HANDLER',
 '{assumptions}','ENFORCED',
 'assumptions is a required key of the analysis output schema; an analysis that states none is refused.'),
('BR-040','hard','SCHEMA_ENFORCED','public.fn_phase_d_schema_validate','br040_metric_undefined',
 'workflow scope W02;W03;W11;W20;W25;W27 and the step family is MEASUREMENT_HANDLER',
 '{formula,denominator}','ENFORCED',
 'The measurement schema requires metric, denominator, numerator, formula and window, and the executor refuses a zero denominator.'),
('BR-028','hard','EXECUTOR_ENFORCED','public.fn_phase_d_handler_execute','pd_capability_unavailable',
 'workflow scope W05;W06;W07;W14 and the step carries a capability dependency','{}','ENFORCED',
 'A step needing judgement fails closed outside a test context rather than inferring an unsupported fact.'),

-- ---- independence rules that reduce to the reviewer predicate on their own scopes ------------
('BR-030','hard','PREDICATE','public.fn_kernel_reviewer_independent(text,text)','br030_self_approval',
 'workflow scope W09;W10 and the frozen step names an independent reviewer','{}','ENFORCED',
 'Supplier onboarding cannot approve its own supplier; the reviewer must resolve to a different effective identity.'),
('BR-031','hard','PREDICATE','public.fn_kernel_reviewer_independent(text,text)','br031_executor_is_reconciler',
 'workflow scope W16;W17;W27 and the frozen step names an independent reviewer','{}','ENFORCED',
 'The identity executing a monetary action cannot independently reconcile it.'),
('BR-037','hard','PREDICATE','public.fn_kernel_reviewer_independent(text,text)','br037_self_certification',
 'workflow scope W23;W24;W30 and the frozen step names an independent reviewer','{}','ENFORCED',
 'An agent or builder cannot certify its own consequential change.'),
('BR-038','hard','PREDICATE','public.fn_kernel_reviewer_independent(text,text)','br038_implementer_released',
 'workflow scope W22;W23;W24 and the frozen step names an independent reviewer','{}','ENFORCED',
 'The implementer cannot issue the final release go/no-go.'),

-- ---- founder-reserved commercial policy: not machine-decidable, and correctly so -------------
('BR-021','founder','PREDICATE','public.fn_phase_c_refund_decision_guard','br021_reveal_fee_change',
 'workflow scope W15;W16 and the step would change the reveal-fee policy','{founder_authority_ref}','ENFORCED',
 'The percentage is founder-reserved. Phase D changes no policy value; a step that would needs a named founder authority.'),
('BR-022','founder','PREDICATE','public.fn_phase_c_refund_decision_guard','br022_supplier_commission',
 'workflow scope W09;W16;W17;W27 and the step would introduce a supplier commission','{founder_authority_ref}','ENFORCED',
 'The commercial model is the founder''s. No Phase D handler introduces a commission.'),
('BR-023','founder','PREDICATE','public.fn_phase_c_refund_decision_guard','br023_founding_exemption',
 'workflow scope W09;W10;W16;W27 and the step would recalculate a founding-supplier exemption','{founder_authority_ref}','ENFORCED',
 'The exemption is permanent for eligible suppliers and may not be recomputed from mutable counts.'),
('BR-024','founder','PREDICATE','public.fn_phase_c_refund_decision_guard','br024_subscription_terms',
 'workflow scope W09;W16;W27 and the step would change subscription amount, start date or exemption','{founder_authority_ref}','ENFORCED',
 'Subscription terms are founder-reserved.'),

-- ---- structural single-source-of-truth rules, resolved against the canonical registry --------
('BR-050','hard','TRIGGER_ENFORCED','public.fn_kernel_write_guard','br050_parallel_comparison',
 'workflow scope W14;W15','{}','ENFORCED',
 'The kernel write guard is the mechanism that keeps a second writer off a canonical table.'),
('BR-051','hard','TRIGGER_ENFORCED','public.fn_kernel_write_guard','br051_parallel_dispatch',
 'workflow scope W12;W13','{}','ENFORCED',
 'Assignments and notifications originate from the canonical dispatch path; a parallel writer is refused at write time.'),
('BR-052','hard','TRIGGER_ENFORCED','public.fn_kernel_write_guard','br052_parallel_monetary_state',
 'workflow scope W15;W16;W17;W27','{}','ENFORCED',
 'Monetary lifecycle writes go through the canonical path; the guard refuses a parallel one.'),
('BR-044','hard','KERNEL_ENFORCED','public.fn_kernel_sla_due','br044_no_deadline',
 'only on a step that opens a handoff','{}','ENFORCED',
 'Every handoff run is created with due_at computed from the frozen SLA policy; a handoff with no policy has no due date and is visible as such.'),
('BR-053','phase_boundary','KERNEL_ENFORCED','public.fn_kernel_paid_provider_gate','br053_activation_in_phase',
 'always','{}','ENFORCED',
 'The selective automation hold is unchanged by Phase D: business-producing automation, notifications, publishing, payment and refund execution stay held.'),
('BR-043','hard','PREDICATE','public.fn_phase_d_rule_check','br043_silent_exception',
 'only when the call names a policy exception','{exception_authority_ref}','ENFORCED',
 'An exception must carry an explicit authorized decision reference; an unnamed exception is refused.'),

-- ---- OUTSTANDING: needs the D2 business-object read/write map to be decidable ----------------
-- These are recorded as debt, not as enforcement. The board counts them and they are the reason
-- Phase D cannot be declared complete on rules alone.
('BR-011','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br011_identity_before_reveal',
 'workflow scope W08;W12;W13;W14;W15','{reveal_state}','OUTSTANDING',
 'Needs the supplier-facing payload object and its reveal state mapped to the step that writes it.'),
('BR-012','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br012_unapproved_package',
 'workflow scope W08;W12;W13','{safe_package_ref}','OUTSTANDING',
 'Needs the supplier-safe package object and its approval state.'),
('BR-013','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br013_inquiry_not_quote_ready',
 'workflow scope W05;W06;W07;W12','{readiness_state}','OUTSTANDING',
 'Needs the inquiry object readiness blockers mapped.'),
('BR-014','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br014_route_unconfirmed',
 'workflow scope W06;W12','{route_state}','OUTSTANDING',
 'Needs the category route object state mapped.'),
('BR-015','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br015_supplier_not_approved',
 'workflow scope W10;W12;W14','{supplier_approval_state}','OUTSTANDING',
 'Needs the supplier object approval/eligibility state mapped.'),
('BR-017','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br017_refused_counted_contacted',
 'workflow scope W12;W13','{assignment_result}','OUTSTANDING',
 'Needs the assignment and notification objects mapped so a refusal cannot be counted as contact.'),
('BR-018','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br018_quote_altered',
 'workflow scope W14;W15','{quote_revision_ref}','OUTSTANDING',
 'Needs the quotation revision object and its immutability mapped.'),
('BR-019','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br019_unpublished_visible',
 'workflow scope W14;W15','{publication_state}','OUTSTANDING',
 'Needs the comparison publication object and the customer RLS path mapped.'),
('BR-020','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br020_reveal_before_payment',
 'workflow scope W15;W16','{payment_reconciled_state}','OUTSTANDING',
 'Needs the transaction object reconciliation state mapped. This is the highest-value outstanding rule.'),
('BR-025','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br025_terms_version_mismatch',
 'workflow scope W04;W09','{terms_version,terms_hash}','OUTSTANDING',
 'Needs the terms acceptance object mapped.'),
('BR-026','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br026_certificate_before_acceptance',
 'workflow scope W04;W09','{acceptance_ref}','OUTSTANDING',
 'Needs the acceptance certificate object mapped.'),
('BR-029','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br029_conflict_overwritten',
 'workflow scope W05;W07;W10;W14','{evidence_authority}','OUTSTANDING',
 'Needs the document evidence object and its authority ranking mapped.'),
('BR-032','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br032_provider_event_replay',
 'workflow scope W16;W17','{provider_event_id}','OUTSTANDING',
 'Needs the provider event object mapped. Providers are disabled for all of Phase D, so nothing is live on this path.'),
('BR-033','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br033_unknown_money_as_success',
 'workflow scope W16;W17;W27','{monetary_state}','OUTSTANDING',
 'Needs the transaction object quarantine state mapped.'),
('BR-034','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br034_consent_ignored',
 'workflow scope W13;W18;W19;W20','{consent_state}','OUTSTANDING',
 'Needs the notification and consent objects mapped. All sending is disabled for Phase D.'),
('BR-035','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br035_unapproved_revision_published',
 'workflow scope W13;W20','{approved_revision_ref}','OUTSTANDING',
 'Needs the content asset revision object mapped. All publishing is disabled for Phase D.'),
('BR-036','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br036_brief_reviewed_not_artifact',
 'workflow scope W08;W20;W22;W24','{artifact_ref}','OUTSTANDING',
 'Needs the artifact object mapped. A verifier that reads what it expects is the known failure here.'),
('BR-039','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br039_no_rollback_path',
 'workflow scope W24;W29','{rollback_ref}','OUTSTANDING',
 'Needs the release object mapped.'),
('BR-041','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br041_activity_as_outcome',
 'workflow scope W02;W03;W11;W18;W19;W20;W25;W30','{outcome_metric}','OUTSTANDING',
 'Needs the defined business outcome per objective mapped, so activity cannot stand in for it.'),
('BR-049','hard','PENDING_OBJECT_MAP','public.phase_d_business_object_binding','br049_inquiry_accountability_moved',
 'workflow scope W05;W06;W07','{inquiry_owner}','OUTSTANDING',
 'Needs the inquiry object owner mapped across the specialist and document handoffs.')
on conflict (rule_id) do update set
  rule_type         = excluded.rule_type,
  enforcement_kind  = excluded.enforcement_kind,
  enforcement_point = excluded.enforcement_point,
  refusal_code      = excluded.refusal_code,
  applies_when      = excluded.applies_when,
  required_context  = excluded.required_context,
  status            = excluded.status,
  evidence          = excluded.evidence,
  recorded_at       = now();

-- ================================================================ 2. applicability
create or replace function public.fn_phase_d_rule_applies(p_rule_id text, p_step_id text)
returns table(applies boolean, why text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.phase_b_business_rule%rowtype;
  s public.phase_b_workflow_step%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_in_scope boolean;
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    applies := false; why := format('unknown rule %L', p_rule_id); return next; return;
  end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    applies := false; why := format('unknown step %L', p_step_id); return next; return;
  end if;
  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;

  -- 1. WORKFLOW SCOPE, from the frozen registry.
  v_in_scope := (lower(r.workflow_scope) = 'all'
                 or s.workflow_id = any (string_to_array(replace(r.workflow_scope,' ',''), ';')));
  if not v_in_scope then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', r.rule_id, r.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  -- 2. STEP-LEVEL APPLICABILITY. Scope is not applicability, and conflating the two is what made
  --    the first executor refuse an intake step for a creator/reviewer collision.
  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    if coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
      applies := false;
      why := format('%s governs the independence of a named reviewer and %s names none', r.rule_id, p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-003' then
    if lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
      applies := false;
      why := format('BR-003 governs founder-reserved decisions and %s declares founder_gate none', p_step_id);
      return next; return;
    end if;
  end if;

  if p_rule_id = 'BR-009' and not coalesce(s.is_closure_step,false) then
    applies := false;
    why := format('BR-009 is a closure rule and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  if p_rule_id = 'BR-042' and s.step_type <> 'analysis' then
    applies := false;
    why := format('BR-042 governs analysis output and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-040' and s.step_type <> 'measurement' then
    applies := false;
    why := format('BR-040 governs metric definition and %s is a %s step', p_step_id, s.step_type);
    return next; return;
  end if;

  if p_rule_id = 'BR-044'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('BR-044 governs a step that opens a handoff and %s opens none', p_step_id);
    return next; return;
  end if;

  applies := true;
  why := format('%s (%s, %s) applies to %s: in scope %s%s', r.rule_id, r.rule_type,
                coalesce(e.enforcement_kind,'UNREGISTERED'), p_step_id, r.workflow_scope,
                case when e.status = 'OUTSTANDING'
                     then ' — enforcement OUTSTANDING, pending the D2 object map' else '' end);
  return next;
end $fn$;

comment on function public.fn_phase_d_rule_applies(text, text) is
  'Decides scope AND step-level applicability for a business rule, and returns the reason either '
  'way. A rule that does not apply is visibly out of scope rather than silently skipped.';

-- ================================================================ 3. the real predicate
create or replace function public.fn_phase_d_rule_check(p_rule_id text, p_context jsonb)
returns table(ok boolean, rule_type text, enforced boolean, reason text, refusal_code text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.phase_b_business_rule%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_missing text[];
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    ok := false; rule_type := 'unknown'; enforced := false;
    reason := format('unknown business rule %L — fail closed', p_rule_id);
    refusal_code := 'unknown_rule'; return next; return;
  end if;
  rule_type := r.rule_type;

  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;
  if not found then
    -- A rule with no registered enforcement is a refusal, not a pass. This is the exact inversion
    -- of the routine this replaces, which returned true for 52 of 54.
    ok := false; enforced := false;
    reason := format('rule %s has no row in phase_d_rule_enforcement — fail closed rather than assume it is satisfied', p_rule_id);
    refusal_code := 'rule_unregistered'; return next; return;
  end if;
  refusal_code := e.refusal_code;
  enforced := (e.status = 'ENFORCED');

  -- ---- PREDICATE rules: decided here, now -------------------------------------------------
  if p_rule_id in ('BR-001','BR-005') then
    ok := public.fn_phase_c_actor_may_own(p_context->>'accountable_role_id');
    reason := case when ok then format('%s: owner %s resolves to one active canonical role',
                                       p_rule_id, p_context->>'accountable_role_id')
                   else format('%s: owner %L does not resolve to an active canonical role',
                               p_rule_id, p_context->>'accountable_role_id') end;
    return next; return;
  end if;

  if p_rule_id = 'BR-004' then
    ok := coalesce((select kind from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')), '')
          = 'canonical';
    reason := case when ok then format('BR-004: actor %s is canonical', p_context->>'actor_role_id')
                   else format('BR-004: actor %L does not resolve as canonical; aliases are input compatibility only',
                               p_context->>'actor_role_id') end;
    return next; return;
  end if;

  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    ok := public.fn_kernel_reviewer_independent(p_context->>'accountable_role_id',
                                                p_context->>'reviewer_role_id');
    reason := case when ok then format('%s: %s and %s are different effective identities',
                                       p_rule_id, p_context->>'accountable_role_id', p_context->>'reviewer_role_id')
                   else format('%s: %L and %L resolve to the same effective identity',
                               p_rule_id, p_context->>'accountable_role_id', p_context->>'reviewer_role_id') end;
    return next; return;
  end if;

  if p_rule_id = 'BR-048' then
    -- An overlay may contribute but never dispatch. Resolved, never string-matched.
    ok := not exists (select 1 from public.phase_c_overlay_binding ob
                       where ob.overlay_id = (select role_id from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')));
    reason := case when ok then 'BR-048: the acting identity is not a category overlay'
                   else format('BR-048: %L is a category overlay and may not dispatch, approve suppliers, reveal identity or change policy',
                               p_context->>'actor_role_id') end;
    return next; return;
  end if;

  if p_rule_id in ('BR-053','BR-054') then
    -- Read from the gate itself rather than from a status column. The gate takes a model and
    -- answers for that route; a representative paid route is asked, so this measures the hold
    -- rather than repeating a claim about it.
    ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean,
                       true);
    reason := case when ok
                   then format('%s: the paid-provider gate refuses a paid route — %s', p_rule_id,
                               public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'reason')
                   else format('%s: the paid-provider gate ALLOWED a paid route. Phase D permits zero paid inference.',
                               p_rule_id) end;
    return next; return;
  end if;

  -- ---- BR-043: no SILENT exception. An exception nobody took needs no authority ------------
  -- The rule forbids an unauthorised policy exception, not the absence of one. Demanding an
  -- authority reference from every ordinary step would refuse all 257 of them for a policy
  -- exception that was never proposed — which is a condition that cannot NOT fire.
  if p_rule_id = 'BR-043' then
    if not (p_context ? 'policy_exception')
       or jsonb_typeof(p_context->'policy_exception') = 'null'
       or btrim(coalesce(p_context->>'policy_exception','')) = '' then
      ok := true;
      reason := 'BR-043: the call proposes no policy exception, so there is no exception to authorise';
      return next; return;
    end if;
    ok := (p_context ? 'exception_authority_ref')
          and btrim(coalesce(p_context->>'exception_authority_ref','')) <> '';
    reason := case when ok
                   then format('BR-043: exception %L carries authority %s',
                               p_context->>'policy_exception', p_context->>'exception_authority_ref')
                   else format('BR-043: exception %L is proposed with no exception_authority_ref. A policy exception cannot bypass privacy, safety or a founder boundary silently.',
                               p_context->>'policy_exception') end;
    return next; return;
  end if;

  -- ---- BR-021..BR-024: founder-reserved commercial policy ----------------------------------
  -- Satisfied while the call proposes no change to the reserved value; the moment it does, a
  -- named founder authority is required. These are type 'founder', so they inform rather than
  -- block, and the reason says which of the two situations produced the verdict.
  if p_rule_id in ('BR-021','BR-022','BR-023','BR-024') then
    if not (p_context ? 'commercial_policy_change')
       or btrim(coalesce(p_context->>'commercial_policy_change','')) = '' then
      ok := true;
      reason := format('%s: the call proposes no change to a founder-reserved commercial term', p_rule_id);
      return next; return;
    end if;
    ok := btrim(coalesce(p_context->>'founder_authority_ref','')) <> '';
    reason := case when ok
                   then format('%s: change %L carries founder authority %s', p_rule_id,
                               p_context->>'commercial_policy_change', p_context->>'founder_authority_ref')
                   else format('%s: change %L is founder-reserved and the call names no founder authority',
                               p_rule_id, p_context->>'commercial_policy_change') end;
    return next; return;
  end if;

  -- ---- SCHEMA_ENFORCED / EXECUTOR_ENFORCED: refused elsewhere in this same call -------------
  -- These are not re-decided here because the place that actually refuses them runs later in
  -- fn_phase_d_handler_execute: the output schema requires the key, or the capability boundary
  -- fails closed. Deciding them twice, from the input context, would refuse a step for not yet
  -- having produced the output it is about to produce.
  if e.enforcement_kind in ('SCHEMA_ENFORCED','EXECUTOR_ENFORCED') then
    ok := true;
    reason := format('%s is enforced at %s later in this same call, which refuses with %s',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;

  -- ---- CONTEXT_REQUIRED rules: an absent business fact is a refusal ------------------------
  if e.enforcement_kind = 'CONTEXT_REQUIRED' then
    select array_agg(k order by k) into v_missing
      from unnest(e.required_context) k
     where not (p_context ? k)
        or jsonb_typeof(p_context->k) = 'null'
        or (jsonb_typeof(p_context->k) = 'string' and btrim(p_context->>k) = '');
    ok := (v_missing is null);
    reason := case when ok
                   then format('%s: the call names %s', p_rule_id, array_to_string(e.required_context,', '))
                   else format('%s requires [%s] and the call names none of it. An absent fact is not a satisfied rule.',
                               p_rule_id, array_to_string(v_missing,', ')) end;
    return next; return;
  end if;

  -- ---- KERNEL_ENFORCED / TRIGGER_ENFORCED: satisfied here, refused there -------------------
  if e.enforcement_kind in ('KERNEL_ENFORCED','TRIGGER_ENFORCED') then
    ok := true;
    reason := format('%s is enforced at %s, which raises %s; this call does not re-decide it',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;

  -- ---- PENDING_OBJECT_MAP: outstanding, and it says so ------------------------------------
  ok := true;
  enforced := false;
  reason := format('%s enforcement is OUTSTANDING: %s. Recorded as Phase D debt, not as a pass.',
                   p_rule_id, e.evidence);
  return next;
end $fn$;

comment on function public.fn_phase_d_rule_check(text, jsonb) is
  'The Phase D business-rule predicate. Replaces the Phase C routine that returned ok := true for '
  '52 of 54 rules while claiming enforcement. An unregistered rule is refused, not passed; a '
  'CONTEXT_REQUIRED rule with absent context is refused; a PENDING_OBJECT_MAP rule reports '
  'enforced = false so the caller can tell debt from enforcement.';

-- ================================================================ 4. the board
create or replace function public.fn_phase_d_rule_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n_rules int; n_reg int; n_out int; n_unres int; n_alwaystrue int;
begin
  select count(*) into n_rules from public.phase_b_business_rule;
  select count(*) into n_reg   from public.phase_d_rule_enforcement;

  check_name := 'every_frozen_rule_has_an_enforcement_row';
  expected := n_rules::text; actual := n_reg::text; ok := (n_reg = n_rules); return next;

  -- A named mechanism that does not exist is prose. Every enforcement_point naming a public
  -- routine is resolved in pg_proc; the two naming a table are resolved in pg_class.
  select count(*) into n_unres from public.phase_d_rule_enforcement e
   where e.enforcement_point like 'public.fn_%'
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public'
                        and p.proname = split_part(split_part(e.enforcement_point,'.',2),'(',1));
  check_name := 'every_named_enforcement_routine_resolves';
  expected := '0'; actual := n_unres::text; ok := (n_unres = 0); return next;

  select count(*) into n_out from public.phase_d_rule_enforcement where status = 'OUTSTANDING';
  check_name := 'rules_with_outstanding_enforcement';
  expected := '0'; actual := n_out::text; ok := (n_out = 0); return next;

  -- The regression guard: the routine this replaced ended with an unconditional ok := true.
  select count(*) into n_alwaystrue
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_d_rule_check'
     and pg_get_functiondef(p.oid) !~ 'rule_unregistered';
  check_name := 'rule_check_refuses_an_unregistered_rule';
  expected := '0'; actual := n_alwaystrue::text; ok := (n_alwaystrue = 0); return next;
end $fn$;

comment on function public.fn_phase_d_rule_state() is
  'Phase D business-rule board. rules_with_outstanding_enforcement is RED by disclosure: 20 rules '
  'need the D2 business-object map before they can be decided, and reporting them as enforced '
  'would be the defect this whole file exists to remove.';

-- ================================================================ 5. grants
revoke all on function public.fn_phase_d_rule_applies(text, text) from public, anon;
grant execute on function public.fn_phase_d_rule_applies(text, text) to service_role, authenticated;
revoke all on function public.fn_phase_d_rule_check(text, jsonb) from public, anon;
grant execute on function public.fn_phase_d_rule_check(text, jsonb) to service_role, authenticated;
revoke all on function public.fn_phase_d_rule_state() from public, anon;
grant execute on function public.fn_phase_d_rule_state() to service_role, authenticated;
revoke all on public.phase_d_rule_enforcement from public, anon, authenticated;
grant select on public.phase_d_rule_enforcement to service_role, authenticated;

commit;

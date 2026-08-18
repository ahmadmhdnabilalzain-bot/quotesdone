-- PHASE D · D2 — THE 56 BUSINESS OBJECTS GET A CANONICAL HOME, A POLICY AND TWO SERVICES.
--
-- WHAT WAS MEASURED FIRST, AND IT DECIDED THE DESIGN.
--
-- Naive name matching resolves 8 of the 56 object_ids to a table. The estate's 553 tables do not
-- share the frozen registry's vocabulary, and three measurements matter more than that count:
--
--   * THERE IS NO `suppliers` TABLE. The supplier account lives in public.leads (20,465 rows),
--     which carries claimed, claimed_by, registration_status, approval_status, verification_status,
--     approved_at, approval_decided_by, accepted_terms_at, accepted_terms_version, signed_terms_*.
--     Binding `supplier_account` to a table called `suppliers` would have bound it to nothing.
--   * public.transactions carries revealed_at, fee_status, reveal_fee and payment_ref. That is
--     where BR-020 (reveal only after reconciliation) has to be decided, and the table is EMPTY —
--     the marketplace has never transacted. A rule written against it must therefore be provable
--     on a fixture, not on history.
--   * 536 public tables have RLS ENABLED and ZERO policies. That is deny-all for anon and
--     authenticated, which is safe, but it means "RLS is on" says nothing on its own and the
--     binding records the policy COUNT rather than the flag.
--
-- WHY ONE STORE AND NOT TWENTY-FIVE TABLES. Twenty-five of the 56 objects have no table anywhere
-- in the estate — financial_close, department_mandate, initiative, release_candidate,
-- ux_specification, capability_case and the rest. They are capabilities the frozen Phase B
-- registry says the business needs, and Phase D's job is to build them, not to argue that
-- something similar already covers them.
--
-- Building 25 near-identical tables would mean 25 copies of the same record-policy trigger, and
-- the policy is the part that actually matters: the registry states 21 distinct record_policy
-- values, which collapse to SIX enforcement families. So the objects with no home get ONE
-- canonical store, public.phase_d_object_record, discriminated by object_id, with a per-object
-- VIEW so each object still has a canonical relation to name — and one guard that enforces the
-- family. A table that gains its own schema later replaces its binding row; nothing else moves.
--
-- WHAT THIS FILE DOES NOT DO. It does not migrate a single existing row, and it does not point any
-- live caller at a new service. Every existing object keeps the table it already has and every
-- current writer keeps working. This lands the MAP, the POLICY and the SERVICES; rewiring callers
-- is per-workflow work in D2's successors.

begin;

-- ================================================================ 1. the binding registry
create table if not exists public.phase_d_business_object_binding (
  object_id                 text primary key
                            references public.phase_b_business_object(object_id),
  display_name              text        not null,
  governing_workflow_id     text        not null,
  accountable_role_id       text        not null,
  record_policy             text        not null,
  policy_family             text        not null
    constraint phase_d_business_object_binding_policy_family_check
    check (policy_family in ('APPEND_ONLY','IMMUTABLE_REVISION','VERSIONED','CASE_RECORD',
                             'TRANSACTION_RECORD','MUTABLE_CONTROLLED')),
  canonical_relation        text        not null,
  relation_kind             text        not null
    constraint phase_d_business_object_binding_relation_kind_check
    check (relation_kind in ('EXISTING_TABLE','PHASE_D_OBJECT_VIEW')),
  primary_identity          text        not null,
  parent_identity           text        not null default '',
  ownership_scope           text        not null
    constraint phase_d_business_object_binding_ownership_scope_check
    check (ownership_scope in ('CUSTOMER','SUPPLIER','COMPANY','FOUNDER')),
  ownership_column          text        not null default '',
  canonical_read_service    text        not null,
  canonical_write_service   text        not null,
  status_model              text        not null default '',
  versioning                text        not null default '',
  storage_bucket            text        not null default '',
  raw_representation        text        not null default '',
  safe_representation       text        not null default '',
  trace_relationship        text        not null default '',
  retention                 text        not null default '',
  cancellation_behaviour    text        not null default '',
  compensation              text        not null default '',
  target_action             text        not null
    constraint phase_d_business_object_binding_target_action_check
    check (target_action in ('KEEP_VERIFIED','KEEP_BETTER_EXISTING','REPAIR',
                             'REPLACE_WITH_CANONICAL_SERVICE','IMPLEMENT','DISABLE_DUPLICATE',
                             'RETIRE_HISTORICAL')),
  current_status            text        not null,
  evidence                  text        not null,
  bound_at                  timestamptz not null default now()
);

comment on table public.phase_d_business_object_binding is
  'One row per frozen Phase B business object naming its canonical relation, its record-policy '
  'family, its ownership scope and its two canonical services. canonical_relation is resolved '
  'against the live catalogue by public.fn_phase_d_object_state(); a named relation that does not '
  'exist is the defect this table makes visible.';

-- ================================================================ 2. the canonical store
-- For the objects the estate has no home for. One store, one guard, a view per object.
create table if not exists public.phase_d_object_record (
  record_id        bigserial   primary key,
  object_id        text        not null
                   references public.phase_b_business_object(object_id),
  business_key     text        not null,
  version          integer     not null default 1,
  state            text        not null default 'open',
  owner_scope      text        not null,
  owner_ref        text        not null,
  payload          jsonb       not null,
  superseded_by    bigint      references public.phase_d_object_record(record_id),
  superseded_at    timestamptz,
  run_id           bigint,
  step_run_id      bigint,
  trace_id         bigint,
  created_by       text        not null,
  created_at       timestamptz not null default now(),
  constraint phase_d_object_record_payload_not_empty
    check (jsonb_typeof(payload) = 'object' and payload <> '{}'::jsonb),
  constraint phase_d_object_record_identity_key unique (object_id, business_key, version)
);

comment on table public.phase_d_object_record is
  'The canonical store for the Phase B business objects that have no table anywhere in the estate. '
  'Discriminated by object_id, with one view per object so every object still names a canonical '
  'relation. The record policy the frozen registry declares is enforced by '
  'public.fn_phase_d_object_policy_guard(), not by convention.';

create index if not exists phase_d_object_record_object_key_idx
  on public.phase_d_object_record (object_id, business_key, version desc);

-- ================================================================ 3. the record-policy guard
create or replace function public.fn_phase_d_object_policy_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
declare v_family text;
begin
  -- Pinned lookup. A trigger runs with the WRITER's search_path, so an unqualified read here
  -- could be answered by a table the caller shadowed.
  select b.policy_family into v_family
    from public.phase_d_business_object_binding b
   where b.object_id = coalesce(new.object_id, old.object_id);

  if v_family is null then
    raise exception 'phase_d_object_record: object % has no Phase D binding — fail closed rather than store a record under a policy nobody declared',
      coalesce(new.object_id, old.object_id) using errcode = '23503';
  end if;

  if tg_op = 'DELETE' then
    raise exception 'phase_d_object_record: % is a % object and business records are never deleted. Cancellation preserves the record, its reason and its authority (BR-046). (pd_object_delete_refused)',
      old.object_id, v_family using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' then
    -- The ONLY update any family permits is the supersession pointer being set once, plus the
    -- state moving. Everything that carries the business fact is frozen on write.
    if new.object_id  is distinct from old.object_id
       or new.business_key is distinct from old.business_key
       or new.version   is distinct from old.version
       or new.payload   is distinct from old.payload
       or new.owner_scope is distinct from old.owner_scope
       or new.owner_ref is distinct from old.owner_ref
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'phase_d_object_record: record % belongs to % (%). Its identity, owner and payload are frozen on write; a change creates a NEW version and supersedes this one. (pd_object_overwrite_refused)',
        old.record_id, old.object_id, v_family using errcode = '23514';
    end if;
    if old.superseded_by is not null and new.superseded_by is distinct from old.superseded_by then
      raise exception 'phase_d_object_record: record % is already superseded by % and a supersession pointer is written once. (pd_object_resupersede_refused)',
        old.record_id, old.superseded_by using errcode = '23514';
    end if;
    if v_family = 'APPEND_ONLY' and new.state is distinct from old.state then
      raise exception 'phase_d_object_record: % is APPEND_ONLY (%); even its state does not move after write. A correction is a new record. (pd_object_append_only)',
        old.object_id, (select record_policy from public.phase_d_business_object_binding
                         where object_id = old.object_id) using errcode = '23514';
    end if;
  end if;

  return new;
end $fn$;

comment on function public.fn_phase_d_object_policy_guard() is
  'Enforces the frozen record policy on public.phase_d_object_record at write time. The 21 '
  'record_policy values the registry states collapse to six families; this refuses the writes each '
  'family forbids rather than trusting the caller to know.';

drop trigger if exists a00_phase_d_object_policy_guard on public.phase_d_object_record;
create trigger a00_phase_d_object_policy_guard
  before update or delete on public.phase_d_object_record
  for each row execute function public.fn_phase_d_object_policy_guard();

-- The store now carries a row-level trigger that raises, which puts it in the population
-- fn_kernel_truncate_protection_state() watches. A row trigger cannot fire on TRUNCATE, so the
-- statement-level guard is attached here in the same file rather than left for the next sweep.
revoke truncate on public.phase_d_object_record from public, anon, authenticated, service_role;
drop trigger if exists z00_kernel_truncate_guard on public.phase_d_object_record;
create trigger z00_kernel_truncate_guard before truncate on public.phase_d_object_record
  for each statement execute function public.fn_kernel_truncate_guard();




insert into public.phase_d_business_object_binding (
  object_id, display_name, governing_workflow_id, accountable_role_id, record_policy,
  policy_family, canonical_relation, relation_kind, primary_identity, parent_identity,
  ownership_scope, ownership_column, canonical_read_service, canonical_write_service,
  status_model, versioning, storage_bucket, raw_representation, safe_representation,
  trace_relationship, retention, cancellation_behaviour, compensation,
  target_action, current_status, evidence)
select
  o.object_id,
  initcap(replace(o.object_id,'_',' ')),
  o.governing_workflow_id,
  o.accountable_role_id,
  o.record_policy,
  -- The 21 declared policies collapse to six enforcement families, mechanically.
  case
    when o.record_policy in ('append_only','append_only_decision','append_only_evidence',
                             'append_only_attempts','append_only_lifecycle','immutable_request')
      then 'APPEND_ONLY'
    when o.record_policy in ('immutable_revision','immutable_published_version',
                             'immutable_after_approval','immutable_candidate',
                             'immutable_closed_period')
      then 'IMMUTABLE_REVISION'
    when o.record_policy in ('versioned','versioned_change','versioned_case','versioned_cycle')
      then 'VERSIONED'
    when o.record_policy in ('transaction_record','unique_record','idempotent_case')
      then 'TRANSACTION_RECORD'
    when o.record_policy in ('mutable_controlled','mutable_until_closed')
      then 'MUTABLE_CONTROLLED'
    else 'CASE_RECORD'
  end,
  m.relation, m.relation_kind, m.identity, coalesce(m.parent,''),
  m.owner_scope, coalesce(m.owner_col,''),
  'public.fn_phase_d_object_read(jsonb)', 'public.fn_phase_d_object_write(jsonb)',
  coalesce(m.status_model,''),
  case
    when o.record_policy like 'append_only%' or o.record_policy = 'immutable_request'
      then 'no versioning: a correction is a new record, the original is never edited'
    when o.record_policy like 'immutable%'
      then 'monotonic revision; an approved revision is frozen and a change requires a new one'
    when o.record_policy like 'versioned%'
      then 'monotonic version; the prior version is superseded and retained, never overwritten'
    when o.record_policy in ('transaction_record','unique_record','idempotent_case')
      then 'single record per identity; only declared state transitions move it'
    else 'mutable with retained history; the record moves and its prior states are preserved'
  end,
  coalesce(m.bucket,''), coalesce(m.raw_repr,''), coalesce(m.safe_repr,''),
  'phase_c_trace via the run and step run that produced the record; the Phase D services record '
  'run_id, step_run_id and trace_id on every write',
  'retained indefinitely; no Phase D path deletes a business record',
  'cancellation supersedes and states a reason and an authority; it never deletes (BR-046)',
  coalesce(m.compensation,'a superseding record; the prior record is retained as the evidence of '
                          'what was believed at the time'),
  m.action, m.status, m.evidence
from public.phase_b_business_object o
join (values
-- ---------------------------------------------------------------- bound to an EXISTING table
('customer_account','public.customers','EXISTING_TABLE','id','','CUSTOMER','id',
 'banned / phone_verified / email_verified / tos_accepted_at','','raw customer identity: full_name, phone, email',
 'the supplier-facing view public.inquiries_supplier_safe excludes customer identity',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.customers, 0 rows, RLS on with 1 policy. Holds identity plus tos_accepted_at, tos_version and the signed_terms_* set.'),
('inquiry','public.inquiries','EXISTING_TABLE','id','customer_id','CUSTOMER','customer_id',
 'status; drawing_redacted; no_quote_notified','','raw_input, spec, boq, drawing_file_path',
 'public.inquiries_supplier_safe is the supplier-facing representation',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.inquiries, RLS on with 1 policy, customer_id is the ownership column. Named by the crosswalk for W05 and written by the inquiry intake path.'),
('inquiry_answer','public.inquiry_answer','EXISTING_TABLE','id','inquiry_id','CUSTOMER','',
 'supersession links between answers','','the answer and its corroboration',
 'not supplier-facing',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.inquiry_answer exists with the sibling tables inquiry_answer_scope, _conflict, _corroboration and _document, which is the supersession structure the frozen policy asks for.'),
('inquiry_document','public.documents','EXISTING_TABLE','id','ref_id','CUSTOMER','',
 'status; extracted; indexed; attempts','qd-docs','the stored file at bucket/path',
 'redacted output via public.drawing_redaction_runs.output_paths',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.documents, 8 rows, carries bucket, path, mime, status, extracted, indexed and a ref_table/ref_id pointer. RLS on with 1 policy.'),
('supplier_account','public.leads','EXISTING_TABLE','id','','SUPPLIER','id',
 'claimed; registration_status; approval_status; verification_status; invite_status','',
 'full lead record including phone, email, owner contact',
 'supplier identity is not customer-facing before reveal',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'THERE IS NO public.suppliers TABLE. public.leads holds 20,465 rows and carries claimed, claimed_by, registration_status, approval_status, verification_status, approved_at and approval_decided_by. Measured, not assumed.'),
('supplier_capability','public.supplier_capabilities','EXISTING_TABLE','supplier_id','supplier_id','SUPPLIER','supplier_id',
 'confirmed via public.supplier_capability_confirmation.version','',
 'declared services, brands, certifications, coverage',
 'capability is the supplier-safe representation already',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.supplier_capabilities, 15,305 rows, with public.supplier_capability_confirmation carrying version, proposed, confirmed, supplier_added and confirmed_at — the versioning the frozen policy requires.'),
('supplier_assignment','public.inquiry_matches','EXISTING_TABLE','id','inquiry_id','SUPPLIER','supplier_id',
 'sent_at is the only state','','inquiry_id, supplier_id, similarity, match_reason',
 'the assignment is supplier-facing by definition',
 null,'REPAIR','BOUND_NEEDS_REPAIR',
 'public.inquiry_matches carries inquiry_id, supplier_id, similarity, sent_at and match_reason but NO version column and NO unique constraint. The frozen policy is unique_record: one supplier, one inquiry VERSION, one dispatch scope. BR-016 cannot be enforced structurally until that constraint exists.'),
('notification','public.notifications','EXISTING_TABLE','id','','COMPANY','',
 'status: pending / digest / sent / failed / suppressed','','to_email, to_phone, subject, body, html',
 'not supplier or customer facing as a record',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.notifications, 624 rows, carries status, sent_at, attempts, last_error and channel. The frozen policy is immutable_request with attempts held separately, which is the next row.'),
('quotation','public.quotes','EXISTING_TABLE','id','inquiry_id','SUPPLIER','supplier_id',
 'status; anonymized; extracted; expires_at','','original_file_path, quote_amount, supplier terms',
 'masked_terms and anonymized carry the customer-safe representation',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.quotes carries inquiry_id, supplier_id, status, anonymized, masked_terms and original_file_path. 0 rows: every historical quote was a demo fixture and was purged on 16 Aug 2026.'),
('quotation_comparison','public.quote_comparisons','EXISTING_TABLE','id','inquiry_id','CUSTOMER','customer_id',
 'signature identifies the compared set','','analysis over all quotes',
 'the comparison IS the customer-facing representation and excludes supplier identity before reveal',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.quote_comparisons carries inquiry_id, customer_id, lang, quote_count, signature and analysis. The frozen policy is immutable_published_version.'),
('reveal_transaction','public.transactions','EXISTING_TABLE','id','quote_id','CUSTOMER','customer_id',
 'fee_status; revealed_at; refund_status','','payment_ref, reveal_fee, supplier identity after reveal',
 'supplier identity is withheld until revealed_at is set and the fee is reconciled',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.transactions carries revealed_at, fee_status, reveal_fee, payment_ref and refund_*. THIS IS WHERE BR-020 IS DECIDED. 0 rows — the marketplace has never transacted, so the rule is provable on a fixture only.'),
('payment_transaction','public.transactions','EXISTING_TABLE','id','quote_id','CUSTOMER','customer_id',
 'fee_status; refund_status','','payment_ref, amounts',
 'not supplier facing',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'Same relation as reveal_transaction by design: the frozen registry separates the reveal decision from the money, and both are states of one transaction row. Recorded as two objects over one relation rather than duplicating the row.'),
('provider_event','public.stripe_events','EXISTING_TABLE','event_id','','COMPANY','',
 'payment_status; delivery_count','','the provider payload',
 'never customer or supplier facing',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.stripe_events keys on event_id with first_seen_at, last_seen_at and delivery_count — the duplicate-delivery structure BR-032 needs. Providers are disabled for the whole of Phase D.'),
('invoice_receipt','public.reveal_invoices','EXISTING_TABLE','invoice_no','transaction_id','CUSTOMER','',
 'issued once per transaction','qd-invoices','bucket/path of the rendered invoice',
 'customer facing by definition',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.reveal_invoices keys transaction_id to invoice_no plus bucket and path. immutable_revision: a correction is a credit note or a new document.'),
('refund_dispute_case','public.refunds','EXISTING_TABLE','id','original_txn_id','CUSTOMER','customer_id',
 'status; decided_by; decided_at','','amount_fils, reason_code, decision_note',
 'not supplier facing',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.refunds carries requested_by, requested_at, decided_by, decided_at and decision_note. Every refund needs the founder — his ruling of 17 Aug 2026, enforced by public.fn_phase_c_refund_decision_guard.'),
('company_objective','public.company_goals','EXISTING_TABLE','key','','COMPANY','',
 'active; deadline; direction','','goal, metric, target_value, measure_sql',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.company_goals, 63 rows, carries key, goal, metric, target_value, owner_dept, measure_sql and active. least() ignores nulls, so an unmeasured goal must not score as attained — measure_sql plus no_measure_reason is how that is kept honest.'),
('department_mandate','public.department_objective','EXISTING_TABLE','id','goal_key','COMPANY','dept_key',
 'status; superseded_by','','objective, target_value, measure_sql',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.department_objective, 92 rows, carries dept_key, goal_key, status and superseded_by — the supersession the frozen versioned policy requires is already structural.'),
('initiative','public.org_tasks','EXISTING_TABLE','id','objective_id','COMPANY','dept_key',
 'status; tier; needs_founder; attempts','','title, detail, result, root_cause',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.org_tasks, 1,058 rows, carries objective_id, dept_key, status, needs_founder, assigned_agent and result. mutable_until_closed with history retained.'),
('campaign_asset','public.content_drafts','EXISTING_TABLE','id','','COMPANY','',
 'status; review_status; reviewed_at','','body, image_url',
 'published content is the public representation',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.content_drafts, 30 rows, carries status, review_status, founder_comment and reviewed_at. immutable_revision: only the approved revision publishes (BR-035). All publishing is disabled for Phase D.'),
('partnership_opportunity','public.opportunity','EXISTING_TABLE','id','','COMPANY','',
 'status; value_score; confidence','','detail, evidence',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.opportunity carries kind, title, detail, evidence, value_score, effort, confidence and status. W21 has no runtime implementation at all — recorded as Phase C wiring gap 5 — so this binds the record, not a running workflow.'),
('incident','public.os_incidents','EXISTING_TABLE','id','','COMPANY','',
 'status; severity; opened_at; resolved_at','','detail, resolution',
 'internal',
 null,'KEEP_VERIFIED','BOUND_EXISTING',
 'public.os_incidents carries title, kind, severity, status, opened_by, opened_at, resolved_by, resolved_at and resolution — the append-only incident timeline the frozen policy asks for.'),
('legal_risk_review','public.legal_reviews','EXISTING_TABLE','id','','COMPANY','',
 'risk_level; needs_licensed_review','','summary, risk_flags',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.legal_reviews carries doc_kind, source, summary, risk_flags, risk_level, needs_licensed_review, reviewed_at and reviewed_by.'),
('review_record','public.review_chain','EXISTING_TABLE','id','subject_id','COMPANY','dept_key',
 'decision; stage','','author_agent, reviewer_agent, reason, violated_rule',
 'internal',
 null,'KEEP_BETTER_EXISTING','BOUND_EXISTING',
 'public.review_chain, 1,900 rows, carries subject_type, subject_id, author_agent, reviewer_agent, stage, decision and delegation_basis. Independence is decided by fn_kernel_reviewer_independent, which resolves both sides through the alias table rather than string-matching.'),
('handoff_record','public.phase_c_handoff_run','EXISTING_TABLE','handoff_run_id','run_id','COMPANY','',
 'status: open / accepted / rejected','','packet_hash, requested_action, acceptance_criteria',
 'internal',
 null,'KEEP_VERIFIED','KERNEL_OWNED',
 'The Phase C kernel owns this table. kernel_write_authority names fn_kernel_step_complete as the ONLY creator since K14 and fn_kernel_handoff_accept as the decider. A Phase D write service over it would be the second writer three phases have been spent removing.'),
('workflow_run','public.phase_c_workflow_run','EXISTING_TABLE','run_id','command_id','COMPANY','',
 'the frozen phase_b_workflow_state model, 14 states','','closure_evidence, object_version',
 'internal',
 null,'KEEP_VERIFIED','KERNEL_OWNED',
 'Kernel-owned. fn_kernel_workflow_start is the only creator; fn_kernel_step_complete, fn_kernel_handoff_accept and fn_kernel_cancel move it. Registered in kernel_write_authority.'),
('workflow_step_run','public.phase_c_workflow_step_run','EXISTING_TABLE','step_run_id','run_id','COMPANY','',
 'the frozen phase_b_step_state model, 11 states','','output_hash, gates_evaluated, authority_result',
 'internal',
 null,'KEEP_VERIFIED','KERNEL_OWNED',
 'Kernel-owned. fn_kernel_open_step is the single place a step run is opened and it refuses a second live run of the same step; fn_kernel_step_complete closes it.')
) as m(object_id, relation, relation_kind, identity, parent, owner_scope, owner_col,
       status_model, bucket, raw_repr, safe_repr, compensation, action, status, evidence)
  on m.object_id = o.object_id
on conflict (object_id) do nothing;

-- ---------------------------------------------------------------- the objects with no home
-- Generated, not hand-typed: every frozen object the block above did not bind gets a canonical
-- view over the policy-guarded store. Writing thirty rows by hand would mean thirty chances to
-- mistype a policy, and the policy is the only part that changes between them.
insert into public.phase_d_business_object_binding (
  object_id, display_name, governing_workflow_id, accountable_role_id, record_policy,
  policy_family, canonical_relation, relation_kind, primary_identity, parent_identity,
  ownership_scope, ownership_column, canonical_read_service, canonical_write_service,
  status_model, versioning, storage_bucket, raw_representation, safe_representation,
  trace_relationship, retention, cancellation_behaviour, compensation,
  target_action, current_status, evidence)
select
  o.object_id,
  initcap(replace(o.object_id,'_',' ')),
  o.governing_workflow_id, o.accountable_role_id, o.record_policy,
  case
    when o.record_policy in ('append_only','append_only_decision','append_only_evidence',
                             'append_only_attempts','append_only_lifecycle','immutable_request')
      then 'APPEND_ONLY'
    when o.record_policy in ('immutable_revision','immutable_published_version',
                             'immutable_after_approval','immutable_candidate',
                             'immutable_closed_period')
      then 'IMMUTABLE_REVISION'
    when o.record_policy in ('versioned','versioned_change','versioned_case','versioned_cycle')
      then 'VERSIONED'
    when o.record_policy in ('transaction_record','unique_record','idempotent_case')
      then 'TRANSACTION_RECORD'
    when o.record_policy in ('mutable_controlled','mutable_until_closed')
      then 'MUTABLE_CONTROLLED'
    else 'CASE_RECORD'
  end,
  'public.v_obj_' || o.object_id, 'PHASE_D_OBJECT_VIEW',
  'business_key', '',
  -- Ownership follows the object, not a guess: anything governed by a customer-facing workflow
  -- is customer-scoped, a supplier-facing one supplier-scoped, everything else company.
  case
    when o.object_id like 'customer%' or o.governing_workflow_id in ('W04','W15','W18') then 'CUSTOMER'
    when o.object_id like 'supplier%' or o.governing_workflow_id in ('W09','W10','W11','W19') then 'SUPPLIER'
    else 'COMPANY'
  end,
  'owner_ref',
  'public.fn_phase_d_object_read(jsonb)', 'public.fn_phase_d_object_write(jsonb)',
  'state on public.phase_d_object_record; open by default, moved only where the family allows',
  case
    when o.record_policy like 'append_only%' or o.record_policy = 'immutable_request'
      then 'no versioning: a correction is a new record, the original is never edited'
    when o.record_policy like 'immutable%'
      then 'monotonic revision; an approved revision is frozen and a change requires a new one'
    when o.record_policy like 'versioned%'
      then 'monotonic version; the prior version is superseded and retained, never overwritten'
    when o.record_policy in ('transaction_record','unique_record','idempotent_case')
      then 'single record per identity; only declared state transitions move it'
    else 'mutable with retained history; the record moves and its prior states are preserved'
  end,
  '', 'payload jsonb, typed by the D1 schema machinery at the step that writes it',
  'the safe representation is the payload minus any key the object''s safe contract excludes; '
  'no supplier-facing path reads this store before D5 wires one',
  'phase_c_trace via the run and step run that produced the record; the Phase D services record '
  'run_id, step_run_id and trace_id on every write',
  'retained indefinitely; no Phase D path deletes a business record',
  'cancellation supersedes and states a reason and an authority; it never deletes (BR-046)',
  'a superseding record; the prior record is retained as the evidence of what was believed at the time',
  'IMPLEMENT', 'PHASE_D_STORE',
  'No table anywhere in the estate holds this object. Measured: name matching resolves 8 of 56, '
  'the crosswalk names no artifact for it, and the write map has no writer. The frozen registry '
  'says the business needs it, so it is built here as a canonical view over '
  'public.phase_d_object_record under record policy ' || o.record_policy || '.'
from public.phase_b_business_object o
where not exists (select 1 from public.phase_d_business_object_binding b
                   where b.object_id = o.object_id)
on conflict (object_id) do nothing;

-- ---------------------------------------------------------------- one view per stored object
do $views$
declare r record;
begin
  for r in select object_id from public.phase_d_business_object_binding
            where relation_kind = 'PHASE_D_OBJECT_VIEW' order by object_id
  loop
    execute format($v$
      create or replace view public.v_obj_%s as
        select record_id, business_key, version, state, owner_scope, owner_ref, payload,
               superseded_by, superseded_at, run_id, step_run_id, trace_id, created_by, created_at
          from public.phase_d_object_record where object_id = %L
    $v$, r.object_id, r.object_id);
    execute format('revoke all on public.v_obj_%s from public, anon, authenticated', r.object_id);
    execute format('grant select on public.v_obj_%s to service_role, authenticated', r.object_id);
  end loop;
end $views$;




-- ================================================================ 1. the write service
create or replace function public.fn_phase_d_object_write(p_input jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b            public.phase_d_business_object_binding%rowtype;
  v_object     text  := nullif(btrim(coalesce(p_input->>'object_id','')),'');
  v_key        text  := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner_ref  text  := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_payload    jsonb := p_input->'payload';
  v_actor      text  := nullif(btrim(coalesce(p_input->>'created_by','')),'');
  v_state      text  := coalesce(nullif(btrim(p_input->>'state'),''), 'open');
  v_prior      public.phase_d_object_record%rowtype;
  v_version    integer := 1;
  v_id         bigint;
  v_readback   public.phase_d_object_record%rowtype;
begin
  if v_object is null or v_key is null or v_actor is null then
    raise exception 'fn_phase_d_object_write: object_id, business_key and created_by are all required (got %, %, %) (pd_object_input_invalid)',
      coalesce(v_object,'(null)'), coalesce(v_key,'(null)'), coalesce(v_actor,'(null)')
      using errcode = '22023';
  end if;

  select * into b from public.phase_d_business_object_binding where object_id = v_object;
  if not found then
    raise exception 'fn_phase_d_object_write: % is not a bound Phase D business object — fail closed rather than store a record under a policy nobody declared (pd_object_unbound)',
      v_object using errcode = '23503';
  end if;

  -- This service owns the Phase D store only. An object bound to an existing table keeps its own
  -- writer; routing it here would create the second writer the kernel work exists to prevent.
  if b.relation_kind <> 'PHASE_D_OBJECT_VIEW' then
    raise exception 'fn_phase_d_object_write: % is bound to the existing relation % and keeps its own writer. This service writes the Phase D store only. (pd_object_wrong_writer)',
      v_object, b.canonical_relation using errcode = '23514';
  end if;

  if v_payload is null or jsonb_typeof(v_payload) <> 'object' or v_payload = '{}'::jsonb then
    raise exception 'fn_phase_d_object_write: % sent payload of type %. An empty object is not evidence that anything was recorded. (pd_object_payload_empty)',
      v_object, coalesce(jsonb_typeof(v_payload),'null') using errcode = '22023';
  end if;

  if v_owner_ref is null then
    raise exception 'fn_phase_d_object_write: % is %-scoped and the call names no owner_ref. An unowned business record is the accountability gap this map exists to close. (pd_object_owner_missing)',
      v_object, b.ownership_scope using errcode = '22023';
  end if;

  -- ---- the record policy decides what a second write MEANS -------------------------------
  select * into v_prior from public.phase_d_object_record
   where object_id = v_object and business_key = v_key and superseded_by is null
   order by version desc limit 1;

  if found then
    if b.policy_family = 'APPEND_ONLY' then
      raise exception 'fn_phase_d_object_write: % is APPEND_ONLY (%) and business key % already holds record %. A correction is a NEW key, never a second version of this one. (pd_object_append_only)',
        v_object, b.record_policy, v_key, v_prior.record_id using errcode = '23514';
    end if;
    if b.policy_family = 'TRANSACTION_RECORD' then
      raise exception 'fn_phase_d_object_write: % is a %-family record and business key % already exists as record %. One record per identity; move its state, do not write a second. (pd_object_duplicate_identity)',
        v_object, b.policy_family, v_key, v_prior.record_id using errcode = '23505';
    end if;
    v_version := v_prior.version + 1;
  end if;

  insert into public.phase_d_object_record
    (object_id, business_key, version, state, owner_scope, owner_ref, payload,
     run_id, step_run_id, trace_id, created_by)
  values (v_object, v_key, v_version, v_state, b.ownership_scope, v_owner_ref, v_payload,
          nullif(p_input->>'run_id','')::bigint, nullif(p_input->>'step_run_id','')::bigint,
          nullif(p_input->>'trace_id','')::bigint, v_actor)
  returning record_id into v_id;

  -- A NULL RETURN IS NOT A WRITE. A BEFORE trigger that returns NULL produces a silent no-op and
  -- an insert that "succeeded" with no row; asserting the read-back is what separates the two.
  if v_id is null then
    raise exception 'fn_phase_d_object_write: the insert for % / % returned no record_id. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
      v_object, v_key using errcode = '23502';
  end if;
  select * into v_readback from public.phase_d_object_record where record_id = v_id;
  if not found then
    raise exception 'fn_phase_d_object_write: record % is not readable back in the same transaction. (pd_object_write_not_readable)',
      v_id using errcode = '23502';
  end if;

  -- Supersession, after the successor exists and only where the family allows it.
  if v_prior.record_id is not null
     and b.policy_family in ('VERSIONED','IMMUTABLE_REVISION','CASE_RECORD','MUTABLE_CONTROLLED') then
    update public.phase_d_object_record
       set superseded_by = v_id, superseded_at = now()
     where record_id = v_prior.record_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'object_id', v_object, 'record_id', v_id, 'business_key', v_key,
    'version', v_version, 'state', v_readback.state,
    'policy_family', b.policy_family, 'record_policy', b.record_policy,
    'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
    'canonical_relation', b.canonical_relation,
    'superseded_record_id', v_prior.record_id,
    'payload_digest', encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'));
end $fn$;

comment on function public.fn_phase_d_object_write(jsonb) is
  'The canonical Phase D business-object write service. Enforces the frozen record policy, refuses '
  'an unbound object, refuses an unowned or empty record, and asserts the written row is readable '
  'back — a write that produced nothing is reported as a failure, never as a success.';

-- ================================================================ 2. the read service
create or replace function public.fn_phase_d_object_read(p_input jsonb)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  b           public.phase_d_business_object_binding%rowtype;
  v_object    text := nullif(btrim(coalesce(p_input->>'object_id','')),'');
  v_key       text := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_scope     text := nullif(btrim(coalesce(p_input->>'caller_scope','')),'');
  v_ref       text := nullif(btrim(coalesce(p_input->>'caller_ref','')),'');
  v_rows      jsonb;
begin
  if v_object is null then
    raise exception 'fn_phase_d_object_read: object_id is required (pd_object_input_invalid)'
      using errcode = '22023';
  end if;
  select * into b from public.phase_d_business_object_binding where object_id = v_object;
  if not found then
    raise exception 'fn_phase_d_object_read: % is not a bound Phase D business object (pd_object_unbound)',
      v_object using errcode = '23503';
  end if;
  if b.relation_kind <> 'PHASE_D_OBJECT_VIEW' then
    raise exception 'fn_phase_d_object_read: % lives in the existing relation % and is read there. (pd_object_wrong_reader)',
      v_object, b.canonical_relation using errcode = '23514';
  end if;

  -- CROSS-OWNER ACCESS IS REFUSED HERE, not filtered by the caller. A COMPANY-scoped object is
  -- readable by an internal caller; a CUSTOMER- or SUPPLIER-scoped one requires the caller to
  -- name whose record it is asking for, and gets nothing back for anybody else.
  if b.ownership_scope in ('CUSTOMER','SUPPLIER') then
    if v_scope is null or v_ref is null then
      raise exception 'fn_phase_d_object_read: % is %-scoped and the call names no caller_scope/caller_ref. Refusing to answer for an unnamed owner. (pd_object_owner_unstated)',
        v_object, b.ownership_scope using errcode = '22023';
    end if;
    if v_scope <> b.ownership_scope then
      raise exception 'fn_phase_d_object_read: % is %-scoped and the caller presents scope %. (pd_object_cross_scope)',
        v_object, b.ownership_scope, v_scope using errcode = '23514';
    end if;
  end if;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.version desc), '[]'::jsonb) into v_rows
    from public.phase_d_object_record r
   where r.object_id = v_object
     and (v_key is null or r.business_key = v_key)
     and (b.ownership_scope = 'COMPANY' or r.owner_ref = v_ref);

  return jsonb_build_object(
    'ok', true, 'object_id', v_object, 'canonical_relation', b.canonical_relation,
    'owner_scope', b.ownership_scope, 'caller_ref', v_ref,
    'count', jsonb_array_length(v_rows), 'records', v_rows);
end $fn$;

comment on function public.fn_phase_d_object_read(jsonb) is
  'The canonical Phase D business-object read service. A customer- or supplier-scoped object '
  'cannot be read without naming whose record it is, and a caller presenting the wrong scope is '
  'refused rather than filtered.';

-- ================================================================ 3. the board
create or replace function public.fn_phase_d_object_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n_obj int; n_bound int; n_unres int; n_noread int; n_nowrite int; n_noowner int;
        n_views int; n_needviews int;
begin
  select count(*) into n_obj   from public.phase_b_business_object;
  select count(*) into n_bound from public.phase_d_business_object_binding;

  check_name := 'every_frozen_object_has_a_binding';
  expected := n_obj::text; actual := n_bound::text; ok := (n_bound = n_obj); return next;

  -- A named relation that does not exist is prose. Tables and views are both resolved.
  select count(*) into n_unres
    from public.phase_d_business_object_binding b
   where not exists (
     select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r','v','m','p')
        and c.relname = replace(b.canonical_relation, 'public.', ''));
  check_name := 'every_canonical_relation_resolves';
  expected := '0'; actual := n_unres::text; ok := (n_unres = 0); return next;

  select count(*) into n_noread  from public.phase_d_business_object_binding
   where coalesce(btrim(canonical_read_service),'') = '';
  check_name := 'objects_with_no_canonical_read_service';
  expected := '0'; actual := n_noread::text; ok := (n_noread = 0); return next;

  select count(*) into n_nowrite from public.phase_d_business_object_binding
   where coalesce(btrim(canonical_write_service),'') = '';
  check_name := 'mutable_objects_with_no_canonical_write_service';
  expected := '0'; actual := n_nowrite::text; ok := (n_nowrite = 0); return next;

  select count(*) into n_noowner from public.phase_d_business_object_binding
   where ownership_scope is null or coalesce(btrim(ownership_scope),'') = '';
  check_name := 'objects_with_no_ownership_scope';
  expected := '0'; actual := n_noowner::text; ok := (n_noowner = 0); return next;

  select count(*) into n_needviews from public.phase_d_business_object_binding
   where relation_kind = 'PHASE_D_OBJECT_VIEW';
  select count(*) into n_views from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'v_obj_%';
  check_name := 'one_view_per_stored_object';
  expected := n_needviews::text; actual := n_views::text; ok := (n_views = n_needviews); return next;

  -- The store's guard must be attached, or the record policy is a column value and nothing else.
  check_name := 'record_policy_guard_is_attached';
  expected := '1'; ok := exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relname = 'phase_d_object_record' and t.tgname = 'a00_phase_d_object_policy_guard'
       and not t.tgisinternal);
  actual := case when ok then '1' else '0' end; return next;
end $fn$;

comment on function public.fn_phase_d_object_state() is
  'Phase D business-object board. Discovered by public.fn_kernel_all_boards() on signature.';

-- ================================================================ 4. grants
revoke all on function public.fn_phase_d_object_write(jsonb) from public, anon, authenticated;
grant execute on function public.fn_phase_d_object_write(jsonb) to service_role;
revoke all on function public.fn_phase_d_object_read(jsonb) from public, anon;
grant execute on function public.fn_phase_d_object_read(jsonb) to service_role, authenticated;
revoke all on function public.fn_phase_d_object_policy_guard() from public, anon, authenticated;
revoke all on function public.fn_phase_d_object_state() from public, anon;
grant execute on function public.fn_phase_d_object_state() to service_role, authenticated;

revoke all on public.phase_d_business_object_binding from public, anon, authenticated;
grant select on public.phase_d_business_object_binding to service_role, authenticated;
-- The store is written only through the service, which is SECURITY DEFINER.
revoke all on public.phase_d_object_record from public, anon, authenticated;
grant select on public.phase_d_object_record to service_role;

commit;

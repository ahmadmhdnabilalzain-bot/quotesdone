import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G10 — twenty business objects the factory declared and never created
--
-- public.phase_d_object_reference_strategy carries a canonical reference strategy for all 56 frozen
-- business objects. public.phase_d_fixture_stage carried a creation stage for 32 of them. The round
-- trip proof therefore reported 31 of 56, and the 25 it could not report on were not failures --
-- they were objects no stage had ever tried to create, recorded as NOT_CREATED_BY_ANY_STAGE and
-- counted as neither pass nor fail. A reference strategy for an object nothing creates is a
-- capability with no entry point.
--
-- This file adds the twenty that need only a stage, and it adds them in one shape rather than
-- twenty:
--
--   sixteen PHASE_D_STORE objects -- ai_change, content_campaign, customer_case, dispatch_batch,
--     exception_record, financial_close, growth_program, intelligence_product, knowledge_change,
--     organization_change_request, product_change, quotation_evaluation, release_candidate,
--     supplier_correction_case, supplier_coverage_case, supplier_retention_case -- which the object
--     store can write from the payload every stage already carries. They get ONE arm at the end of
--     the chain, not sixteen: the owner is derived from the object's own declared ownership_scope,
--     so a CUSTOMER-scoped case is owned by the scenario's customer and a SUPPLIER-scoped one by
--     its supplier, and D9h's "the owner of a customer-scoped object is a customer" is satisfied by
--     derivation rather than by sixteen repetitions of it.
--
--   four EXISTING_TABLE objects -- initiative, legal_risk_review, partnership_opportunity and
--     invoice_receipt -- whose relations carry NOT NULL columns and CHECK constraints that a
--     deterministic handler must not invent values for. Each gets its own arm, and every business
--     value in it comes from the committed catalogue or from a row the scenario already created.
--
-- THE STATES ARE THE RELATION'S, NOT THE FAMILY'S, WHERE THE TWO DISAGREE. public.org_tasks
-- constrains status to proposed/assigned/in_progress/blocked/done/failed/escalated/cancelled and
-- initiative's Phase D state contract carries the generic MUTABLE_CONTROLLED words
-- open/active/suspended/closed. Those two sets share NOTHING, so the stage declares "proposed" --
-- the state org_tasks itself defaults to and the state an initiative starts in. That is the same
-- choice supplier_account already makes (working_state "approved", which its family contract also
-- does not list) and it is recorded here rather than left to be rediscovered.
--
-- STILL NOT CREATED BY ANY STAGE AFTER THIS FILE, and deliberately, each for a stated reason:
--   notification        its canonical relation is public.notifications, the outbound queue. The
--                       factory aborts the whole build if that table gains a row, and it is right
--                       to. Handled separately.
--   workflow_run        created by fn_kernel_workflow_start.
--   workflow_step_run   created by fn_kernel_open_step.
--   handoff_record      created by the kernel when a step with a handoff completes.
--                       All three are KERNEL_OWNED and fn_phase_d_object_write refuses them by
--                       name -- "a Phase D handler that wrote it would be a second creator for one
--                       object" -- which is the deadlock D-something already paid for once.
--   inquiry_answer      has a stage; it reports BLOCKED_NO_REFERENCE_DATA because
--                       public.inquiry_workstream_group holds 0 rows and this factory does not
--                       create business reference data.
--
-- Three anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const STAGES = `
insert into public.phase_d_fixture_stage
  (stage_no, stage_key, object_id, requires_stages, contributes_ref, reference_relation, note,
   working_state, working_state_evidence, contributes_kind, working_payload, working_payload_evidence)
values
  (300,'growth_program','growth_program','{}',null,null,
   'W03. The versioned growth programme W03 writes at S01-S04 and S06-S08.',
   'active','DERIVED from public.phase_d_object_state_contract: growth_program is a VERSIONED-family object whose declared states are open/active/superseded/published. A programme being pursued is active.',
   'RESULT_KEY','{}'::jsonb,null),
  (305,'content_campaign','content_campaign','{}',null,null,
   'W20. The versioned content campaign W20 writes at every step but its closure.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (310,'knowledge_change','knowledge_change','{}',null,null,
   'W26. The versioned knowledge change W26 opens, decides, executes and reviews.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (315,'product_change','product_change','{}',null,null,
   'W22. The versioned product change.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (320,'ai_change','ai_change','{}',null,null,
   'W23. The versioned AI/model change.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (325,'intelligence_product','intelligence_product','{}',null,null,
   'W25. The versioned intelligence product.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (330,'quotation_evaluation','quotation_evaluation','{quotation}',null,null,
   'W14. The versioned evaluation of a supplier quotation; it exists only once there is a quotation to evaluate.',
   'active','DERIVED from public.phase_d_object_state_contract: VERSIONED family, states open/active/superseded/published.',
   'RESULT_KEY','{}'::jsonb,null),
  (335,'release_candidate','release_candidate','{}',null,null,
   'W24. An immutable release candidate revision.',
   'approved','DERIVED from public.phase_d_object_state_contract: IMMUTABLE_REVISION family, states open/issued/submitted/approved/rejected/superseded. A candidate that has been accepted for release is an APPROVED revision in that vocabulary.',
   'RESULT_KEY','{}'::jsonb,null),
  (340,'financial_close','financial_close','{}',null,null,
   'W27. An immutable financial close revision.',
   'approved','DERIVED from public.phase_d_object_state_contract: IMMUTABLE_REVISION family, states open/issued/submitted/approved/rejected/superseded.',
   'RESULT_KEY','{}'::jsonb,null),
  (345,'organization_change_request','organization_change_request','{}',null,null,
   'W30. An append-only organisation change request.',
   'recorded','DERIVED from public.phase_d_object_state_contract: APPEND_ONLY family, states open/recorded/accepted/selected/logged. A request that exists has been recorded.',
   'RESULT_KEY','{}'::jsonb,null),
  (350,'exception_record','exception_record','{}',null,null,
   'ALL. The exception case any workflow can open.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected. An exception is open until it is worked.',
   'RESULT_KEY','{}'::jsonb,null),
  (355,'dispatch_batch','dispatch_batch','{inquiry,supplier_account}',null,null,
   'W12. The dispatch batch W12 accepts, builds, policies, reviews and evidences across five steps.',
   'open','DERIVED from public.phase_d_object_state_contract: TRANSACTION_RECORD family, states open/pending/settled/refunded/failed/reconciled. A batch being assembled is open. It is NOT a payment: a11_phase_d_stage_payment_state_declared governs payment_transaction and reveal_transaction only.',
   'RESULT_KEY','{}'::jsonb,null),
  (360,'customer_case','customer_case','{customer_account}',null,null,
   'W18. The customer retention/service case, owned by the scenario customer.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected.',
   'RESULT_KEY','{}'::jsonb,null),
  (365,'supplier_correction_case','supplier_correction_case','{supplier_account}',null,null,
   'W10. The supplier correction case, owned by the scenario supplier.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected.',
   'RESULT_KEY','{}'::jsonb,null),
  (370,'supplier_coverage_case','supplier_coverage_case','{supplier_account}',null,null,
   'W11. The supplier coverage case, owned by the scenario supplier.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected.',
   'RESULT_KEY','{}'::jsonb,null),
  (375,'supplier_retention_case','supplier_retention_case','{supplier_account}',null,null,
   'W19. The supplier retention case, owned by the scenario supplier.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected.',
   'RESULT_KEY','{}'::jsonb,null),
  (380,'initiative','initiative','{}',null,null,
   'W01-S07. public.org_tasks.title is NOT NULL and dept_key is a foreign key into public.org_departments, so the title comes from the committed catalogue and the department from the estate.',
   'proposed','MEASURED CONTRADICTION, resolved in favour of the relation. public.org_tasks_status_check allows proposed/assigned/in_progress/blocked/done/failed/escalated/cancelled; initiative''s Phase D state contract carries the generic MUTABLE_CONTROLLED words open/active/suspended/closed. The two sets share no value, so a stage declaring the contract''s vocabulary could never be written. proposed is org_tasks'' own default and the state an initiative starts in. supplier_account already makes the same choice.',
   'RESULT_KEY','{}'::jsonb,null),
  (385,'legal_risk_review','legal_risk_review','{}',null,null,
   'W28. public.legal_reviews carries title, summary, doc_kind and risk_level in its write map; all four are business content and come from the committed catalogue.',
   'open','DERIVED from public.phase_d_object_state_contract: CASE_RECORD family, states open/in_progress/verified/resolved/closed/rejected. public.legal_reviews has no status column in its write map, so this state is recorded on the scenario record and never written to the relation.',
   'RESULT_KEY','{}'::jsonb,null),
  (390,'partnership_opportunity','partnership_opportunity','{}',null,null,
   'W21. public.opportunity.kind and .title are NOT NULL and status is constrained to open/pursuing/won/dismissed.',
   'open','MEASURED: the only value in BOTH public.opportunity_status_check (open, pursuing, won, dismissed) and the CASE_RECORD family contract (open, in_progress, verified, resolved, closed, rejected) is open. An opportunity that has just been detected is open in either vocabulary.',
   'RESULT_KEY','{}'::jsonb,null),
  (395,'invoice_receipt','invoice_receipt','{payment_transaction,customer_account}',null,null,
   'W16/W27. public.reveal_invoices.transaction_id is NOT NULL and a foreign key into public.transactions, so this stage exists only once the payment transaction does.',
   'issued','DERIVED from public.phase_d_object_state_contract: IMMUTABLE_REVISION family, states open/issued/submitted/approved/rejected/superseded. An invoice that exists has been issued. public.reveal_invoices has no status column in its write map, so this state is recorded on the scenario record and never written to the relation.',
   'RESULT_KEY','{}'::jsonb,null)
on conflict (stage_key) do nothing;
`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

splice(`    elsif st.stage_key = 'review_record' then
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_onboarding',
                                           'reviewer_role_id','customer_success_director',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');
    end if;`,
`    elsif st.stage_key = 'review_record' then
      v_pay := v_pay || jsonb_build_object('verdict','approved',
                                           'subject_type','phase_d_fixture', 'subject_id', v_label,
                                           'author_agent','customer_onboarding',
                                           'reviewer_role_id','customer_success_director',
                                           'stage', st.stage_key, 'notes','ZZ DEMO — fixture review');

    -- G10. THE FOUR EXISTING RELATIONS WHOSE COLUMNS A HANDLER MUST NOT INVENT.
    elsif st.stage_key = 'initiative' then
      -- public.org_tasks.dept_key is a foreign key into public.org_departments and title is NOT
      -- NULL. The department is read from the estate and the title from the committed catalogue.
      v_owner := (select dept_key from public.org_departments where active order by dept_key limit 1);
      v_pay := v_pay || jsonb_build_object(
        'title',  (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                    where c.scope='EFFECT_PAYLOAD' and c.field_key='title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture initiative. It assigns no real work to any department and is created inside a transaction that is aborted.',
        'dept_key', (select dept_key from public.org_departments where active order by dept_key limit 1));

    elsif st.stage_key = 'legal_risk_review' then
      v_pay := v_pay || jsonb_build_object(
        'title',      (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                        where c.scope='EFFECT_PAYLOAD' and c.field_key='title'),
        'summary',    'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture legal risk review. No document was reviewed, no legal opinion is expressed, and it is created inside a transaction that is aborted.',
        'doc_kind',   'phase_d_fixture',
        'risk_level', 'low');

    elsif st.stage_key = 'partnership_opportunity' then
      v_pay := v_pay || jsonb_build_object(
        'kind',   (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                    where c.scope='EFFECT_PAYLOAD' and c.field_key='kind'),
        'title',  (select c.value #>> '{}' from public.phase_d_fixture_catalogue c
                    where c.scope='EFFECT_PAYLOAD' and c.field_key='title'),
        'detail', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture partnership opportunity. No partner is named, no approach is made, and it is created inside a transaction that is aborted.');

    elsif st.stage_key = 'invoice_receipt' then
      -- transaction_id is NOT NULL and a foreign key, so this stage depends on payment_transaction
      -- and takes the transaction the scenario created rather than choosing one.
      v_owner := v_refs->>'customer_id';
      v_pay := v_pay || jsonb_build_object(
        'transaction_id', v_refs->>'transaction_id',
        'bucket', 'zz-phase-d-fixtures',
        'path',   format('zz/%s/invoice-%s.pdf', v_label, st.stage_key));

    else
      -- G10. EVERY STAGE THE CHAIN ABOVE DOES NOT NAME, WHICH IS SIXTEEN PHASE D STORE OBJECTS AND
      -- ANY ADDED LATER. The object store writes from the payload every stage already carries, so
      -- the only thing these need is the one fact the store checks and a bookkeeping payload cannot
      -- supply: WHO OWNS THE RECORD. That is derived from the object's own declared ownership_scope
      -- rather than repeated sixteen times, so a CUSTOMER-scoped case is owned by the scenario's
      -- customer and a SUPPLIER-scoped one by its supplier. D9h found the opposite of this once --
      -- a customer-scoped object owned by something that was not a customer -- and a derivation
      -- cannot drift back into it one object at a time.
      v_owner := case (select ob.ownership_scope from public.phase_d_business_object_binding ob
                        where ob.object_id = st.object_id)
                   when 'CUSTOMER' then coalesce(nullif(v_refs->>'customer_id',''), v_key)
                   when 'SUPPLIER' then coalesce(nullif(v_refs->>'supplier_id',''), v_key)
                   else v_key end;
      v_pay := v_pay || jsonb_build_object('note', format(
        'PHASE_D_FIXTURE_DO_NOT_PUBLISH — a Phase D fixture %s, created through fn_phase_d_object_write inside a transaction that is aborted. It states nothing about the business and is never published.',
        st.object_id));
    end if;`,
  'G10 stage arms');

writeFileSync('scripts/sql/phase_d_g10_twenty_objects_the_factory_declared_and_never_created.sql',
  HEAD + '\n' + STAGES + '\n' + def + '\n');
console.log('G10 written');

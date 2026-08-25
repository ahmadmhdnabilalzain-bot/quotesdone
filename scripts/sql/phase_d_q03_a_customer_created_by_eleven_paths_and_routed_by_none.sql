-- Q03. A CUSTOMER CREATED BY ELEVEN PATHS AND ROUTED BY NONE OF THEM.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md measured nine active sources that do not
-- route through the kernel inbox and found ONE real defect among them: edge:inquiry_intake INSERTs
-- public.customers, and a customer_account — a frozen Phase B business object governed by W04 — was
-- created with no workflow run, no task, no accountable owner and no trace. It named the fix:
-- "either an adapter on edge:inquiry_intake, or a kernel-routing trigger on public.customers so
-- EVERY creator is covered, including customer_api's me handler which creates the same row."
--
-- IT IS THE TABLE TRIGGER, AND THE MEASUREMENT SAYS SO PLAINLY. Counted on production 25 Aug from
-- public.phase_c_edge_function_writes, ELEVEN deployed edge functions INSERT or UPDATE
-- public.customers: customer_api, inquiry_intake, messages_api, compliance_archive, kyc, login_otp,
-- mobile_otp, os_api, os_ops, pdpl_erase, wa_optin_set. The bypass table named two of the eleven —
-- it was reading the source inventory, which holds 25 of the 143 edge functions that write any
-- table at all. A per-function adapter on inquiry_intake would have left ten creators uncovered and
-- the board would have gone green. One AFTER INSERT trigger on the table covers all eleven and
-- every future one, because the coverage is attached to the row, not to the caller.
--
-- THE PATH THIS BUILDS, END TO END:
--
--   any creator INSERTs public.customers
--     -> z50_customer_registered_kernel_emit (AFTER INSERT, FOR EACH ROW)
--     -> fn_kernel_source_emit('dbtrigger:public.customers:z50_customer_registered_kernel_emit', ...)
--     -> fn_kernel_trigger_submit  (trigger_type customer.registered)
--     -> public.kernel_trigger_inbox
--     -> W04, its first step run and its first task
--
-- Nothing in that chain is new except the trigger and its three registry rows. customer.registered
-- has been registered in public.kernel_trigger_type since 16 Aug 2026 pointing at W04 with
-- business_object_rule customer_account:{customer_id} — implementation_state
-- ADAPTER_READY_NO_LIVE_SENDER. It is a finished capability with no entry point. This is the entry
-- point.
--
-- WHAT THE KERNEL ALREADY GUARANTEES, SO THIS FILE DOES NOT RE-IMPLEMENT IT:
--
--   one customer -> at most one W04 run   fn_kernel_trigger_submit builds its idempotency key as
--                                         <source_system>:<source_ref> and INSERTs the inbox row
--                                         `on conflict (idempotency_key) do nothing`. source_ref is
--                                         the customer id, so a second emit for the same customer
--                                         returns the FIRST result and creates nothing —
--                                         created = {inbox_row:0, run:0, step_run:0, task:0, event:0}.
--   source validation                     the emit is refused unless the source key is in
--                                         kernel_trigger_type.allowed_source_systems for
--                                         customer.registered, and unless it carries a row in
--                                         public.phase_c_source_cutover.
--   correlation / causation               defaulted by the kernel to trigger:<idem> and
--                                         <source_system>:<source_ref>; this trigger states both
--                                         explicitly so the chain reads customer:<id> end to end.
--   trace                                 TRACE-SYSTEM-EXECUTION, written by the kernel.
--   founder absent, Chief of Staff absent fn_kernel_trigger_submit checks the founder boundary at
--                                         call time as well as at registry write time. W04's
--                                         accountable owner is a canonical role and neither of
--                                         those two.
--   no external effect                    W04's first step is internal. Every provider route is
--                                         held and no notification row is written by this path.
--   automation remains held               this wires a TRIGGER, not a cron job. Nothing here
--                                         activates a schedule, un-holds a provider or changes
--                                         public.control_mode_action.
--
-- THE TRIGGER IS NAMED z50_customer_registered_kernel_emit AND FIRES LAST, AND THE FIRST NAME WAS
-- WRONG. Postgres fires row triggers in NAME order and public.customers already carries four:
-- trg_block_disposable_customers, trg_emit_customer_registered, trg_norm_customer_ver and
-- trg_sign_customer. A kernel emit must not run before a guard that may still refuse the row. This
-- file first called it trg_customer_registered_kernel_z, which READS as last and sorts THIRD:
-- 'trg_c' < 'trg_e' < 'trg_n'. The assertion in section 7 refused it, which is what that
-- assertion is for. A z-prefix is what the estate already uses for exactly this (z00_, z10_, z90_).
--
-- ================================================================================================
-- WHAT ELSE IS IN THIS FILE, AND WHY IT IS ONE FILE
--
-- The bypass table's other eight rows are class C, FALSE_OR_STALE_MEASUREMENT — the board is wrong,
-- not the product. Correcting them is the same subject as the fix above (what the source inventory
-- says about what changes business state) and separating them would leave the board disagreeing
-- with itself for the length of two commits.
--
--   F1  A FRONTEND PATH CAN NEVER PASS THE ROUTING CHECK. The edge arm of routes_through_inbox is
--       gated on source_kind = 'edge_function', so for the five frontend_path rows the predicate has
--       no arm that could ever be true. And the deeper error is upstream of that: a browser page is
--       not an autonomous source. It has no autonomy — a person drives it — and it writes nothing.
--       Every write it causes happens in the edge function it calls, which is inventoried
--       separately. recorded_creates_work goes to false, with evidence naming the functions each
--       route reaches, read from the committed frontend call graph.
--
--   F2  creates_work_now READS THE TABLE NAME, NOT THE WRITE. Both quote_items triggers write
--       public.quotes: quote_items_rescore's ENTIRE body is
--       `update public.quotes set status = status where id = coalesce(NEW.quote_id, OLD.quote_id)`,
--       a no-op touch, and trg_items_submittable writes a derived boolean on the row its own item
--       belongs to. Neither creates or moves business work. A textual predicate cannot tell those
--       two apart from a real write, so the correction is a recorded disposition carrying the
--       measurement — the same mechanism FOUNDER_COMMAND_SURFACE already uses — and not a smarter
--       regex.
--
--   F3  attach_photos DOES NOT WRITE, BUT WHAT IT CALLS DOES, AND THAT FUNCTION IS NOT INVENTORIED.
--       Measured: public.phase_c_edge_function_writes holds ZERO rows for attach_photos and one for
--       drawing_redact (insert into public.drawing_redaction_runs, bounded). edge:drawing_redact is
--       inventoried below, classified from what it does rather than from what it is called.
--
--   F4  ROUTING IS ATTRIBUTED PER EDGE FUNCTION, NOT PER TABLE. edge:customer_api read
--       routes_through_inbox = true because SOME of the tables it writes carry kernel-routing
--       triggers — while its public.customers INSERT reached nothing. The view now requires EVERY
--       bounded work table a function writes to be routed, and publishes the ones that are not in a
--       new column, so the credit can never again be granted by a sibling table.
--
-- AND THE GAP THE CORRECTIONS REST ON IS PUBLISHED RATHER THAN ASSUMED. Every correction above says
-- "the write happens in the edge function, which is inventoried separately". Measured on 25 Aug that
-- is true of 25 functions and not of 52 others that write a work table and hold no inventory row.
-- fn_kernel_trigger_state gains a row counting exactly that, so "the nine are what the inventory can
-- see, not what the estate contains" stops being a sentence in a document and becomes a number on a
-- board.
--
-- ROLLBACK: scripts/sql/down/phase_d_q03_a_customer_created_by_eleven_paths_and_routed_by_none_down.sql
-- drops the trigger and its function, deletes the four registry rows, restores the previous
-- dispositions and re-applies the previous view and board.

-- ================================================================================================
-- 1. THE SOURCE, REGISTERED BEFORE ANYTHING CAN EMIT FROM IT.
--
-- fn_kernel_source_emit raises 23503 for a source with no row in phase_c_source_cutover, and
-- fn_kernel_trigger_submit refuses a source that is not in allowed_source_systems. Both registries
-- are written here, before the trigger exists, so the trigger can never fire into an absence.

UPDATE public.kernel_trigger_type
   SET allowed_source_systems =
         allowed_source_systems || array['dbtrigger:public.customers:z50_customer_registered_kernel_emit'],
       -- LIVE_SENDER is one of the three values kernel_trigger_type_impl_ck admits. The row has
       -- read ADAPTER_READY_NO_LIVE_SENDER since 16 Aug 2026 — a finished capability with no entry
       -- point. The trigger below is the sender.
       implementation_state = 'LIVE_SENDER'
 WHERE trigger_type = 'customer.registered'
   AND NOT (allowed_source_systems @> array['dbtrigger:public.customers:z50_customer_registered_kernel_emit']);

INSERT INTO public.phase_c_source_cutover
  (source_component_id, source_type, source_class, current_entry_point,
   current_direct_side_effects, target_kernel_adapter, target_workflow, target_step_or_signal,
   accountable_role, system_actor, idempotency_key, trace_policy, current_activation,
   cutover_action, rollback, status, classification_reason, evidence, disposition_evidence)
VALUES
  ('dbtrigger:public.customers:z50_customer_registered_kernel_emit', 'database_trigger',
   'A NEW_WORK_REQUEST',
   'trigger public.customers:z50_customer_registered_kernel_emit',
   'none. The trigger writes no business row of its own; it emits and returns NEW.',
   -- phase_c_source_adapter_matches_class requires exactly this for a class A source, and it is
   -- correct: fn_kernel_source_emit is the door the trigger knocks on, fn_kernel_trigger_submit is
   -- the adapter it resolves to. The column names the adapter.
   'fn_kernel_trigger_submit', 'W04', 'customer.registered',
   (SELECT accountable_role_id FROM public.phase_b_workflow WHERE workflow_id = 'W04'),
   'system.webhook_receiver',
   'trigger: <source_system>:<source_ref> where source_ref is the customer id '
     || '(fn_kernel_trigger_submit default) — one customer, one key, one W04 run',
   'TRACE-SYSTEM-EXECUTION', 'ACTIVE',
   'Cut over at the TABLE. Eleven deployed edge functions write public.customers '
     || '(customer_api, inquiry_intake, messages_api, compliance_archive, kyc, login_otp, '
     || 'mobile_otp, os_api, os_ops, pdpl_erase, wa_optin_set), measured from '
     || 'public.phase_c_edge_function_writes. A per-function adapter would have covered one of '
     || 'eleven; a row trigger covers all of them and every future creator.',
   'drop trigger z50_customer_registered_kernel_emit on public.customers; the adapter row stays for '
     || 'the record',
   'CUTOVER_COMPLETE',
   'The row that IS the new customer account. Declared start of W04 Customer account activation; '
     || 'nothing exists to attach a signal to yet, so it is class A and not class B.',
   'pg_trigger z50_customer_registered_kernel_emit on public.customers -> '
     || 'trg_customer_registered_kernel, AFTER INSERT FOR EACH ROW. kernel_trigger_type '
     || 'customer.registered -> W04, registered 2026-08-16, ADAPTER_READY_NO_LIVE_SENDER until '
     || 'this file.',
   'routine:trg_customer_registered_kernel')
ON CONFLICT (source_component_id) DO UPDATE
  SET status = excluded.status, cutover_action = excluded.cutover_action,
      evidence = excluded.evidence, disposition_evidence = excluded.disposition_evidence;

INSERT INTO public.kernel_trigger_source
  (source_key, source_kind, source_ref, source_class, adapter_trigger_type, workflow_id,
   accountable_role_id, connection_state, disposition, recorded_active, recorded_creates_work,
   recorded_routes_through_inbox, evidence, measured_at, measured_by)
VALUES
  ('dbtrigger:public.customers:z50_customer_registered_kernel_emit', 'database_trigger',
   'public.customers:z50_customer_registered_kernel_emit', 'customer_event',
   'customer.registered', 'W04',
   (SELECT accountable_role_id FROM public.phase_b_workflow WHERE workflow_id = 'W04'),
   'CONNECTED_ACTIVE', NULL, NULL, NULL, NULL,
   'The canonical customer-created adapter. Every creator of public.customers reaches W04 through '
     || 'it because it is attached to the row and not to a caller. is_active_now, creates_work_now '
     || 'and routes_through_inbox are all DERIVED for a database_trigger — the three recorded_* '
     || 'columns are deliberately null so this row can never assert its own coverage.',
   now(), 'phase_d_q03')
ON CONFLICT (source_key) DO UPDATE
  SET connection_state = excluded.connection_state, workflow_id = excluded.workflow_id,
      adapter_trigger_type = excluded.adapter_trigger_type, evidence = excluded.evidence,
      accountable_role_id = excluded.accountable_role_id, measured_at = now();

-- ================================================================================================
-- 2. THE ADAPTER ITSELF.

CREATE OR REPLACE FUNCTION public.trg_customer_registered_kernel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- The customer id is the external identity of this request, so it is the source_ref and therefore
  -- the idempotency key. A second INSERT of the same id is impossible (primary key), and a replay
  -- of the same emit is answered by the kernel's own `on conflict (idempotency_key) do nothing`
  -- with created = all zeros. Neither this function nor the caller has to remember anything.
  --
  -- correlation and causation are STATED rather than defaulted. The kernel would build
  -- 'trigger:<idem>' and '<source_system>:<source_ref>'; naming them customer:<id> makes the whole
  -- chain — inbox row, run, step run, task, trace — greppable by the one identifier a person
  -- actually has.
  --
  -- NO GUARD ON THE ROW. Every reason to refuse a customer already ran: this trigger sorts after
  -- trg_block_disposable_customers, trg_norm_customer_ver and trg_sign_customer, so a row that
  -- reaches here is a row the estate accepted.
  perform public.fn_kernel_source_emit(
    'dbtrigger:public.customers:z50_customer_registered_kernel_emit',
    jsonb_build_object(
      'source_ref',     NEW.id::text,
      'correlation_id', 'customer:' || NEW.id::text,
      'causation_id',   'customers.insert:' || NEW.id::text,
      'raw_payload',    jsonb_build_object(
                          'customer_id', NEW.id::text,
                          'created_at',  NEW.created_at)));
  return NEW;
end
$function$;

DROP TRIGGER IF EXISTS z50_customer_registered_kernel_emit ON public.customers;
CREATE TRIGGER z50_customer_registered_kernel_emit
AFTER INSERT ON public.customers
FOR EACH ROW EXECUTE FUNCTION public.trg_customer_registered_kernel();

-- ================================================================================================
-- 3. edge:drawing_redact — CLASSIFIED FROM WHAT IT DOES.
--
-- First, the disposition vocabulary the classification needs. See the note at the head of section 4
-- for why three values are added to a deliberately closed list and what holds that honest.

ALTER TABLE public.kernel_trigger_source DROP CONSTRAINT IF EXISTS kernel_trigger_source_disposition_ck;
ALTER TABLE public.kernel_trigger_source ADD CONSTRAINT kernel_trigger_source_disposition_ck
  CHECK (disposition IS NULL OR disposition = ANY (ARRAY[
    'NOT_A_BUSINESS_TRIGGER',
    'NO_WORKFLOW_IN_REGISTRY',
    'FOUNDER_COMMAND_SURFACE',
    'RECOMPUTATION_ONLY_NO_BUSINESS_WORK',
    'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE',
    'READ_ONLY_DERIVED_INTERNAL']));

--
-- ACTIVE v21, verify_jwt=false behind a shared __secret. Measured writes: exactly one bounded row,
-- `insert into public.drawing_redaction_runs`, plus objects in the drawing-files storage bucket.
-- public.drawing_redaction_runs is not on the work-table list and is not a Phase B business object:
-- it is the PROVENANCE record of a redaction, and customer_api's create_inquiry resolves which
-- redacted paths may be attached from that table alone — so if the insert fails the run reports
-- recorded:false and its paths are refused downstream. Load-bearing, and still not business work.
--
-- It is NOT class A: it starts no workflow, and the business event on this path is the document
-- ARRIVING, which customer.document_uploaded already carries from edge:attach_photos and
-- edge:customer_documents. It is NOT class B: there is no live run to signal — the redaction
-- happens at upload time, before any inquiry exists — and nothing consumes such a signal.
--
-- So: READ_ONLY / DERIVED_INTERNAL, recorded as class C READ_ONLY_MONITOR, which is the existing
-- vocabulary of public.phase_c_source_cutover. THE NAME IS NOT LITERALLY TRUE AND THE ROW SAYS SO:
-- it inserts, and it writes storage. What the class means here is what fn_kernel_source_emit
-- enforces for it — a class C source MAY NOT create business work, and any call from it is refused
-- with 42501. That is the correct constraint for this function.

INSERT INTO public.phase_c_source_cutover
  (source_component_id, source_type, source_class, current_entry_point,
   current_direct_side_effects, target_kernel_adapter, target_workflow, target_step_or_signal,
   accountable_role, system_actor, idempotency_key, trace_policy, current_activation,
   cutover_action, rollback, status, classification_reason, evidence, disposition_evidence)
VALUES
  ('edge:drawing_redact', 'edge_function', 'C READ_ONLY_MONITOR',
   'edge function drawing_redact',
   'STATE-CHANGING, and not business work: one INSERT into public.drawing_redaction_runs '
     || '(bounded, measured in public.phase_c_edge_function_writes) and objects written to the '
     || 'drawing-files storage bucket. No work table, no workflow, no task, no notification.',
   -- The three literals every existing class C row carries; the columns are NOT NULL and 'none' is
   -- the estate's own word for "this class has no target", already on edge:attach_photos,
   -- edge:resend_inbound and edge:unsubscribe.
   'none — this class may not create business work', 'none', 'none',
   'document_intelligence_manager', 'system.webhook_receiver',
   'the run id it generates; create_inquiry resolves attachable paths from the recorded run',
   'TRACE-SYSTEM-EXECUTION', 'ACTIVE',
   'No adapter. The business event on this path is the document arriving, carried by '
     || 'customer.document_uploaded from edge:attach_photos and edge:customer_documents. A second '
     || 'emit here would open a second W07 run for one upload.',
   'none required; the row is the inventory entry, not a wiring change',
   'CLASSIFIED_NO_CUTOVER_REQUIRED',
   'READ_ONLY/DERIVED_INTERNAL. The row it writes is the PROVENANCE of the redaction it just '
     || 'performed — a privacy record read by create_inquiry to decide which redacted paths may be '
     || 'attached, fail-closed when absent. Derived from the act, internal to the platform, and '
     || 'neither the start of work nor a signal on live work.',
   'Deployed ACTIVE v21, updated 2026-08-17. Called by edge:attach_photos, edge:customer_api and '
     || 'edge:supplier_api; reached from src/components/me/CustomerPortal.tsx only through those. '
     || 'Absent from every source inventory until this file — the gap '
     || 'docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md finding F3 named.',
   'routine:none — no adapter, by classification')
ON CONFLICT (source_component_id) DO UPDATE
  SET source_class = excluded.source_class, status = excluded.status,
      classification_reason = excluded.classification_reason, evidence = excluded.evidence;

INSERT INTO public.kernel_trigger_source
  (source_key, source_kind, source_ref, source_class, adapter_trigger_type, workflow_id,
   accountable_role_id, connection_state, disposition, recorded_active, recorded_creates_work,
   recorded_routes_through_inbox, evidence, measured_at, measured_by)
VALUES
  ('edge:drawing_redact', 'edge_function', 'supabase/functions/drawing_redact/index.ts', NULL,
   NULL, NULL, 'document_intelligence_manager', 'DEFERRED_HANDLER',
   'READ_ONLY_DERIVED_INTERNAL',
   true, false, false,
   'READ_ONLY/DERIVED_INTERNAL, and state-changing — the two are not in conflict and the '
     || 'distinction is the point. It INSERTs exactly one bounded row, '
     || 'public.drawing_redaction_runs, and writes storage objects; neither is a work table and '
     || 'neither starts or moves a workflow. The business event on this path is the document '
     || 'arriving, carried by customer.document_uploaded from edge:attach_photos and '
     || 'edge:customer_documents. Measured 25 Aug 2026: ACTIVE v21; one row in '
     || 'public.phase_c_edge_function_writes; zero rows naming any work table.',
   now(), 'phase_d_q03')
ON CONFLICT (source_key) DO UPDATE
  SET disposition = excluded.disposition, recorded_creates_work = excluded.recorded_creates_work,
      evidence = excluded.evidence, measured_at = now();

-- ================================================================================================
-- 4. THE EIGHT FALSE-POSITIVE MEASUREMENT ROWS.
--
-- Not one product path is touched by anything in this section. Every statement writes a
-- measurement, and every measurement carries the reading it was taken from.
--
-- THE DISPOSITION VOCABULARY IS WIDENED, DELIBERATELY AND BY THREE. kernel_trigger_source_disposition_ck
-- admits NOT_A_BUSINESS_TRIGGER, NO_WORKFLOW_IN_REGISTRY and FOUNDER_COMMAND_SURFACE. It stays a
-- CLOSED list — that is the point of it, and the three added here are each a measured finding of
-- docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md with its reading recorded on the row:
--
--   RECOMPUTATION_ONLY_NO_BUSINESS_WORK           F2 — writes a work table and creates no work
--   HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE F1 — a browser route is not an autonomous source
--   READ_ONLY_DERIVED_INTERNAL                    F3 — state-changing, and not business work
--
-- Widening a closed list is how an exemption gets smuggled in, so two things hold it honest: every
-- one of the three is counted BY NAME on fn_kernel_trigger_state :: disposition_split, and the
-- inventory-completeness row added in section 6 is ok=false while any work-table writer is missing.

-- (The two ALTER statements are at the top of section 3, because edge:drawing_redact is the first
-- row that needs one of the new values.)

-- F2 — the two quote_items recomputation triggers.
UPDATE public.kernel_trigger_source
   SET disposition = 'RECOMPUTATION_ONLY_NO_BUSINESS_WORK',
       evidence = evidence || E'\n\nQ03 (F2), measured 25 Aug 2026: the board read creates_work_now '
         || 'true because the trigger function body matches (insert into|update) public.quotes and '
         || 'public.quotes is on the work-table list. It does not look at WHAT is written. '
         || 'quote_items_rescore''s entire body is `update public.quotes set status = status where '
         || 'id = coalesce(NEW.quote_id, OLD.quote_id)` — a no-op touch that re-fires the quotes '
         || 'triggers; trg_items_submittable writes a derived boolean on the row its own item '
         || 'belongs to. Neither creates nor moves business work. public.quote_items holds 0 rows '
         || 'and its last created_at is null since the marketplace fixture purge of 16 Aug 2026, so '
         || 'neither has fired against a real line item since. The only kernel-routing trigger on '
         || 'public.quotes is trg_new_quote_sms, which pg_get_triggerdef shows is AFTER INSERT — an '
         || 'UPDATE cannot reach it either way. A textual predicate cannot separate a no-op touch '
         || 'from a real write, so this is recorded as a measurement rather than guessed at by a '
         || 'smarter regex. The trigger is unchanged and still enabled.',
       measured_at = now(), measured_by = 'phase_d_q03'
 WHERE source_key IN ('dbtrigger:public.quote_items:quote_items_rescore',
                      'dbtrigger:public.quote_items:trg_items_submittable');

-- F3 — attach_photos writes nothing itself.
UPDATE public.kernel_trigger_source
   SET recorded_creates_work = false,
       evidence = evidence || E'\n\nQ03 (F3), measured 25 Aug 2026: public.phase_c_edge_function_writes '
         || 'holds ZERO rows for attach_photos. It forwards to edge:drawing_redact, which writes '
         || 'one bounded provenance row (public.drawing_redaction_runs) and storage objects — '
         || 'neither a work table nor a workflow. drawing_redact is inventoried by this file and '
         || 'classified READ_ONLY/DERIVED_INTERNAL. recorded_creates_work was true and no '
         || 'measurement supported it.',
       measured_at = now(), measured_by = 'phase_d_q03'
 WHERE source_key = 'edge:attach_photos';

-- F1 — the five frontend routes, and the three already dispositioned, are all human-driven surfaces.
UPDATE public.kernel_trigger_source
   SET recorded_creates_work = false,
       recorded_routes_through_inbox = NULL,
       disposition = coalesce(disposition, 'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE'),
       evidence = evidence || E'\n\nQ03 (F1), measured 25 Aug 2026: a browser route is not an '
         || 'autonomous source. It has no autonomy — a person drives it — and it writes no table. '
         || 'Every write it causes happens in the edge function it calls, which is inventoried and '
         || 'measured separately. The old board could never have said so: the edge arm of '
         || 'v_kernel_trigger_source_derived.routes_through_inbox is gated on source_kind = '
         || '''edge_function'', so for a frontend_path row the predicate had no arm that could ever '
         || 'be true, and recorded_creates_work = true then held it in a population it cannot leave. '
         || 'The functions each route reaches are read from '
         || 'docs/phase-d/PHASE_D_FRONTEND_API_CALL_GRAPH.csv, 77 of 77 (component, edge_function) '
         || 'pairs across 39 files. The coverage this correction depends on is published as a '
         || 'number by fn_kernel_trigger_state :: '
         || 'edge_functions_writing_a_work_table_and_absent_from_the_inventory, so it cannot be '
         || 'assumed.',
       measured_at = now(), measured_by = 'phase_d_q03'
 WHERE source_kind = 'frontend_path';

-- The two cutover rows whose coverage claim was true about the inquiry and silent about the
-- customer. Neither product path changes; the claim is completed.
UPDATE public.phase_c_source_cutover
   SET cutover_action = cutover_action
         || E'\n\nQ03, 25 Aug 2026: and its public.customers INSERT is covered by '
         || 'z50_customer_registered_kernel_emit on public.customers -> W04. The previous sentence was '
         || 'true about the inquiry and silent about the customer, which is the gap '
         || 'docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md row 1 measured.',
       disposition_evidence = disposition_evidence || '; routine:trg_customer_registered_kernel'
 WHERE source_component_id IN ('edge:inquiry_intake', 'edge:customer_api');

-- ================================================================================================
-- 5. THE DERIVED VIEW — PER TABLE, NOT PER FUNCTION.
--
-- Changes from the definition read out of production before this file ran:
--
--   (a) the wt list gains an is_draft column, and public.inquiry_intake is marked with it. A draft
--       is not work: the work starts when customer_api promotes a draft marked ready into
--       public.inquiries, and THAT insert reaches the kernel through trg_inquiry_received_a. An
--       emit on the draft would open a second W05 run for one customer request, which is exactly
--       what edge:inquiry_intake's cutover row has said since 17 Aug. The column is on the list
--       rather than deleted from it so the reason travels with the table name.
--   (b) routed_table — a work table is routed when it carries an ENABLED trigger whose function
--       calls the kernel. Computed once, per table.
--   (c) unrouted_work_tables — a NEW published column naming, for an edge function, every bounded
--       work table it writes that is neither routed nor a draft. This is the column that makes F4
--       impossible to repeat: the credit can no longer be granted by a sibling table, because the
--       ones that fail are printed.
--   (d) the edge arm of routes_through_inbox now requires ALL of them, not ANY of them.
--
-- Everything else — the cron, trigger and event-trigger arms, is_active_now, creates_work_now,
-- outbox_used_as_request_queue, accountable_kind — is unchanged.

CREATE OR REPLACE VIEW public.v_kernel_trigger_source_derived AS
WITH wt(t, why, is_draft) AS (
  VALUES ('agent_actions','the legacy agent work queue',false),
         ('org_tasks','the department task queue',false),
         ('phase_c_task','the kernel task table',false),
         ('notifications','the outbound message queue: a queued message is work owed to a person',false),
         ('os_incidents','phase_b_business_object.incident, governed by W29',false),
         ('board_reports','phase_b_business_object.intelligence_product, governed by W25',false),
         ('evolution_proposal','phase_b_business_object.organization_change_request, governed by W30',false),
         ('leads','the supplier lead / supplier_account population, governed by W09',false),
         ('inquiries','phase_b_business_object.inquiry, governed by W05',false),
         ('inquiry_intake','the inquiry DRAFT that becomes phase_b_business_object.inquiry — not '
                        || 'itself work. customer_api promotes a draft marked ready into '
                        || 'public.inquiries and marks it consumed, and that insert reaches the '
                        || 'kernel through trg_inquiry_received_a. An emit on the draft would open '
                        || 'a second W05 run for one customer request.',true),
         ('quotes','phase_b_business_object.quotation, governed by W14',false),
         ('transactions','phase_b_business_object.payment_transaction, governed by W16',false),
         ('customers','phase_b_business_object.customer_account, governed by W04',false)
), body AS (
  SELECT p.oid, p.proname,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prokind = 'f'
), writer AS (
  SELECT b.oid, b.proname, string_agg(DISTINCT wt.t, ', ') AS work_tables
    FROM body b JOIN wt ON b.src ~* ('(insert\s+into|update)\s+(public\.)?' || wt.t || '\y')
   GROUP BY b.oid, b.proname
), kernelcaller AS (
  SELECT b.oid, b.proname FROM body b
   WHERE b.src ~ '\yfn_kernel_trigger_submit\s*\(' OR b.src ~ '\yfn_kernel_signal_submit\s*\('
      OR b.src ~ '\yfn_kernel_source_emit\s*\('
), routed_table AS (
  -- (b) A work table is ROUTED when a write to it reaches the kernel — an enabled trigger whose
  -- function calls one of the three kernel doors. Per table, computed once.
  SELECT DISTINCT cl.relname::text AS tbl
    FROM wt
    JOIN pg_class cl ON cl.relname = wt.t
    JOIN pg_namespace ns ON ns.oid = cl.relnamespace AND ns.nspname = 'public'
    JOIN pg_trigger tg ON tg.tgrelid = cl.oid AND NOT tg.tgisinternal AND tg.tgenabled <> 'D'
    JOIN kernelcaller kc ON kc.oid = tg.tgfoid
), edge_tables AS (
  SELECT w.edge_function,
         count(*) FILTER (WHERE NOT w.unbounded AND w.table_name IN (SELECT t FROM wt)) AS work_writes,
         string_agg(DISTINCT w.table_name, ', ' ORDER BY w.table_name) FILTER (
           WHERE NOT w.unbounded AND w.table_name IN (SELECT t FROM wt)
             AND w.table_name NOT IN (SELECT tbl FROM routed_table)
             AND w.table_name NOT IN (SELECT t FROM wt WHERE is_draft)) AS unrouted
    FROM public.phase_c_edge_function_writes w
   GROUP BY w.edge_function
), cronjob AS (
  SELECT j.jobid, j.active,
         regexp_replace(regexp_replace(j.command, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') AS cmd
    FROM cron.job j
), cron_fact AS (
  SELECT cj.jobid, cj.active,
         (EXISTS (SELECT 1 FROM writer wr
                   WHERE strpos(cj.cmd, wr.proname::text) > 0
                     AND cj.cmd ~ ('\y' || wr.proname::text || '\s*\('))) AS creates_work,
         cj.cmd ~ '\yfn_kernel_trigger_submit\s*\('
           OR (EXISTS (SELECT 1 FROM kernelcaller kc
                        WHERE strpos(cj.cmd, kc.proname::text) > 0
                          AND cj.cmd ~ ('\y' || kc.proname::text || '\s*\('))) AS routes,
         (EXISTS (SELECT 1 FROM body b
                   WHERE strpos(cj.cmd, b.proname::text) > 0
                     AND cj.cmd ~ ('\y' || b.proname::text || '\s*\(')
                     AND b.src ~ '\yphase_c_event_outbox\y'
                     AND b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')) AS replays
    FROM cronjob cj
), trg_fact AS (
  SELECT n.nspname::text || '.' || c.relname::text || ':' || tg.tgname::text AS source_ref,
         tg.tgenabled <> 'D' AS active,
         COALESCE((SELECT bool_or(u.tn <> c.relname::text)
                     FROM writer wr, LATERAL unnest(string_to_array(wr.work_tables, ', ')) u(tn)
                    WHERE wr.oid = tg.tgfoid), false) AS creates_work,
         (EXISTS (SELECT 1 FROM kernelcaller kc WHERE kc.oid = tg.tgfoid)) AS routes,
         (EXISTS (SELECT 1 FROM body b WHERE b.oid = tg.tgfoid
                    AND b.src ~ '\yphase_c_event_outbox\y'
                    AND b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')) AS replays
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE NOT tg.tgisinternal
), evt_fact AS (
  SELECT e.evtname::text AS source_ref, e.evtenabled <> 'D' AS active,
         (EXISTS (SELECT 1 FROM writer wr WHERE wr.oid = e.evtfoid)) AS creates_work,
         (EXISTS (SELECT 1 FROM kernelcaller kc WHERE kc.oid = e.evtfoid)) AS routes,
         (EXISTS (SELECT 1 FROM body b WHERE b.oid = e.evtfoid
                    AND b.src ~ '\yphase_c_event_outbox\y'
                    AND b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')) AS replays
    FROM pg_event_trigger e
)
SELECT s.source_key, s.source_kind, s.source_ref, s.source_class, s.adapter_trigger_type,
       s.workflow_id, s.accountable_role_id, s.connection_state, s.disposition, s.evidence,
       CASE s.source_kind
         WHEN 'cron_job' THEN cf.active
         WHEN 'database_trigger' THEN tf.active
         WHEN 'event_trigger' THEN ef.active
         ELSE s.recorded_active
       END AS is_active_now,
       CASE s.source_kind
         WHEN 'cron_job' THEN cf.creates_work
         WHEN 'database_trigger' THEN tf.creates_work
         WHEN 'event_trigger' THEN ef.creates_work
         ELSE s.recorded_creates_work
       END AS creates_work_now,
       CASE s.source_kind
         WHEN 'cron_job' THEN cf.routes
         WHEN 'database_trigger' THEN tf.routes
         WHEN 'event_trigger' THEN ef.routes
         ELSE
           -- (d) A routine that names this source key in a kernel call routes it directly.
           (EXISTS (SELECT 1 FROM kernelcaller kc JOIN body b2 ON b2.oid = kc.oid
                     WHERE b2.src LIKE '%''' || s.source_key || '''%'))
           -- PER TABLE. It routes when it writes at least one bounded work table and NONE of them
           -- is unrouted. `any of them` is what credited edge:customer_api while its
           -- public.customers INSERT reached nothing.
           OR (s.source_kind = 'edge_function'
               AND COALESCE((SELECT et.work_writes FROM edge_tables et
                              WHERE et.edge_function = regexp_replace(s.source_key, '^edge:', '')), 0) > 0
               AND (SELECT et.unrouted FROM edge_tables et
                     WHERE et.edge_function = regexp_replace(s.source_key, '^edge:', '')) IS NULL)
           OR COALESCE(s.recorded_routes_through_inbox, false)
       END AS routes_through_inbox,
       CASE s.source_kind
         WHEN 'cron_job' THEN cf.replays
         WHEN 'database_trigger' THEN tf.replays
         WHEN 'event_trigger' THEN ef.replays
         ELSE false
       END AS outbox_used_as_request_queue,
       (SELECT r.kind FROM public.fn_phase_c_resolve_actor(s.accountable_role_id)
                        r(kind, role_id, department_id, system_actor_id, reason)) AS accountable_kind,
       -- (c) NAMED, NOT COUNTED. Null when there are none. APPENDED AT THE END: CREATE OR REPLACE
       -- VIEW may only add columns after the existing ones, never rename one in place.
       CASE WHEN s.source_kind = 'edge_function'
            THEN (SELECT et.unrouted FROM edge_tables et
                   WHERE et.edge_function = regexp_replace(s.source_key, '^edge:', ''))
       END AS unrouted_work_tables
  FROM public.kernel_trigger_source s
  LEFT JOIN cron_fact cf ON cf.jobid = CASE WHEN s.source_kind = 'cron_job'
                                              AND s.source_ref ~ '^[0-9]+$'
                                            THEN s.source_ref::bigint END
  LEFT JOIN trg_fact tf ON s.source_kind = 'database_trigger' AND tf.source_ref = s.source_ref
  LEFT JOIN evt_fact ef ON s.source_kind = 'event_trigger' AND ef.source_ref = s.source_ref;

-- ================================================================================================
-- 6. THE BOARD. Two edits: the auto population excludes the two new measured dispositions (each
--    still counted by name on disposition_split), and a new row publishes the inventory gap every
--    correction in section 4 depends on.

CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_temp'
AS $function$
with d as (select * from public.v_kernel_trigger_source_derived),
tot as (select count(*)::text n from d),
auto as (   -- a live source that starts or changes business work: what an adapter is FOR.
            -- The founder's own command channel is excluded by name: it is not autonomous, a
            -- person drives it, and giving it an autonomous adapter is the one thing the frozen
            -- operating model forbids. Excluded here and counted on the deferred_handler_split
            -- line, so it is never simply missing.
  select * from d
   where coalesce(is_active_now,false) and coalesce(creates_work_now,false)
     and coalesce(disposition,'') not in (
           -- Q03. Three dispositions, each a MEASUREMENT recorded on the row with the reading it
           -- was taken from, not a name added to get a number down. FOUNDER_COMMAND_SURFACE was
           -- already here; the other two are the F1 and F2 corrections of
           -- docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md. Every one of them is still
           -- counted, by name, on the disposition_split line below, so nothing leaves this board
           -- by being excluded here.
           'FOUNDER_COMMAND_SURFACE',
           'RECOMPUTATION_ONLY_NO_BUSINESS_WORK',
           'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE')
),
act as (select count(*)::text n from auto),
-- UNACCOUNTED FOR: it starts work, it is live, it has no working adapter, and nobody has written
-- down why. A recorded DEFERRED_HANDLER is an answer; silence is the gap.
gap as (
  select * from auto a
   where a.disposition is null
     and (a.adapter_trigger_type is null
          or not exists (select 1 from public.kernel_trigger_type t
                          where t.trigger_type = a.adapter_trigger_type
                            and t.activation_state = 'active'))
)
select 'active_autonomous_source_with_no_adapter'::text,
       '0 of ' || (select n from act) || ' active autonomous sources (' || (select n from tot) || ' inventoried)',
       (select count(*)::text from gap)
         || ' of ' || (select n from act) || ' active autonomous sources unaccounted for ('
         || (select n from tot) || ' inventoried); '
         || (select count(*)::text from auto where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' carry a recorded DEFERRED_HANDLER, '
         || (select count(*)::text from d where coalesce(is_active_now,false)
               and coalesce(creates_work_now,false) and disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces held out of this population by name',
       (select count(*) from gap) = 0
union all
select 'active_adapter_bypassing_fn_kernel_workflow_start'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where activation_state = 'active')
         || ' active trigger types',
       -- The adapter is fn_kernel_trigger_submit. It bypasses the kernel creator if its own body
       -- (comments stripped) does not call fn_kernel_workflow_start, or if any OTHER routine reads
       -- kernel_trigger_inbox and creates work without going through it.
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(')::text
         || ' routines read kernel_trigger_inbox and create work without fn_kernel_workflow_start; '
         || 'fn_kernel_trigger_submit calls it: '
         || (select (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                     ~ '\yfn_kernel_workflow_start\s*\(')::text
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'),
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(') = 0
       and coalesce((select regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                            ~ '\yfn_kernel_workflow_start\s*\('
                       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'), false)
union all
select 'normal_autonomous_trigger_routing_through_founder'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types (workflow owner or entry-step owner)',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'normal_autonomous_trigger_routing_through_chief_of_staff'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'chief_of_staff' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types; W01 is the founder-command path and is refused by '
         || 'a00_kernel_trigger_type_routing_guard, not merely absent',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'chief_of_staff' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'duplicate_trigger_delivery_creating_duplicate_workflow'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_inbox
                    where status in ('accepted','duplicate')) || ' resolved inbox rows',
       -- Two ways a duplicate could show: the same idempotency key twice (the UNIQUE constraint
       -- makes it impossible and it is still counted, because a constraint that is never tested is
       -- an assumption), or one (workflow, business object) carrying more than one run.
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)::text
         || ' repeated idempotency keys + '
         || (select count(*) from (
               select workflow_id, business_object_id from public.kernel_trigger_inbox
                where status in ('accepted','duplicate') and run_id is not null
                group by workflow_id, business_object_id having count(distinct run_id) > 1) y)::text
         || ' (workflow, object) pairs with more than one run, of '
         || (select count(*)::text from public.kernel_trigger_inbox
              where status in ('accepted','duplicate')) || ' resolved inbox rows',
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)
       + (select count(*) from (
            select workflow_id, business_object_id from public.kernel_trigger_inbox
             where status in ('accepted','duplicate') and run_id is not null
             group by workflow_id, business_object_id having count(distinct run_id) > 1) y) = 0
union all
select 'trigger_source_using_the_domain_event_outbox_as_its_request_queue'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where outbox_used_as_request_queue)::text
         || ' of ' || (select n from tot) || ' inventoried sources. The predicate is live: it '
         || 'matches '
         || (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yphase_c_event_outbox\y'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')
         || ' routines in the database (the legacy ingress pair), and no ACTIVE source reaches them',
       (select count(*) from d where outbox_used_as_request_queue) = 0
-- ---- reported alongside the six, because a green mapping check must not read as a green wiring
-- ---- check. This is the increment's own open gap and it is stated as a number, not as prose.
union all
select 'active_autonomous_source_not_yet_routing_through_the_inbox'::text,
       '0 of ' || (select n from act) || ' active autonomous sources — NOT MET BY K10',
       (select count(*) from auto where not coalesce(routes_through_inbox,false))::text
         || ' of ' || (select n from act) || ' active autonomous sources still start or change '
         || 'business work without entering the kernel. K10 builds the door and registers the '
         || 'routes; moving each source onto it is the wiring increment.',
       (select count(*) from auto where not coalesce(routes_through_inbox,false)) = 0
union all
select 'inventory_row_whose_accountable_role_does_not_resolve'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical')::text
         || ' of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical') = 0
union all
select 'disposition_split'::text,
       'reported, never counted as one backlog of owed handlers',
       (select count(*)::text from public.kernel_trigger_source
         where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' owe a handler (no Phase B workflow starts from that signal); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'NOT_A_BUSINESS_TRIGGER')
         || ' are not business triggers at all (guards, audits, probes, held jobs); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces that must never get an autonomous adapter; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition is null and adapter_trigger_type is not null)
         || ' carry an adapter; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'RECOMPUTATION_ONLY_NO_BUSINESS_WORK')
         || ' recompute a derived value and create no business work; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE')
         || ' are human-driven browser surfaces that write no table themselves; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'READ_ONLY_DERIVED_INTERNAL')
         || ' are read-only or derived-internal',
       true
-- ---- Q03. THE INVENTORY'S OWN COMPLETENESS, PUBLISHED AS A NUMBER.
-- Every correction on this board rests on the same sentence: 'the write happens in the edge
-- function, which is inventoried separately'. That sentence is only worth anything if the
-- inventory is complete, and it is not. Measured 25 Aug 2026: 143 deployed edge functions write
-- at least one table, 25 hold an inventory row, and 52 of the uninventoried ones write a WORK
-- table. Counting them here rather than in a document is the difference between a disclosed gap
-- and a footnote nobody reads. It is ok=false on purpose: this is owed work, not an exemption.
union all
select 'edge_functions_writing_a_work_table_and_absent_from_the_inventory'::text,
       '0 — every edge function that writes a work table carries an inventory row',
       (select count(*)::text from (
          select distinct w.edge_function
            from public.phase_c_edge_function_writes w
           where not w.unbounded
             and w.table_name in ('agent_actions','org_tasks','phase_c_task','notifications',
                                  'os_incidents','board_reports','evolution_proposal','leads',
                                  'inquiries','inquiry_intake','quotes','transactions','customers')
             and not exists (select 1 from public.kernel_trigger_source s
                              where s.source_key = 'edge:' || w.edge_function)) x)
         || ' of ' || (select count(distinct w.edge_function)::text
                         from public.phase_c_edge_function_writes w) 
         || ' edge functions with a measured write are absent from public.kernel_trigger_source '
         || 'while writing a work table. The sources this board reports on are what the inventory '
         || 'can see, not what the estate contains.',
       not exists (
          select 1 from public.phase_c_edge_function_writes w
           where not w.unbounded
             and w.table_name in ('agent_actions','org_tasks','phase_c_task','notifications',
                                  'os_incidents','board_reports','evolution_proposal','leads',
                                  'inquiries','inquiry_intake','quotes','transactions','customers')
             and not exists (select 1 from public.kernel_trigger_source s
                              where s.source_key = 'edge:' || w.edge_function));
$function$;

-- ================================================================================================
-- 7. ASSERTIONS. Counted, not typed.

DO $assert$
DECLARE
  v_trg        int;
  v_allowed    boolean;
  v_cutover    int;
  v_unrouted   text;
  v_bypass     int;
  v_bypass_who text;
  v_drawing    int;
  v_a_drift    int;
  v_b_drift    int;
BEGIN
  -- (a) the trigger exists, is enabled, is AFTER INSERT, and sorts after every existing one.
  SELECT count(*) INTO v_trg
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'customers'
     AND t.tgname = 'z50_customer_registered_kernel_emit' AND t.tgenabled <> 'D';
  IF v_trg <> 1 THEN
    RAISE EXCEPTION 'Q03: the customers kernel trigger is not enabled on public.customers'
      USING errcode = '23514';
  END IF;
  -- ROW-LEVEL INSERT triggers only. z00_kernel_truncate_guard sorts after this name and is a
  -- STATEMENT-level TRUNCATE trigger (tgtype 34): it cannot fire on an INSERT at all, so ordering
  -- against it is meaningless. Comparing every trigger regardless of type is how a guard fires on
  -- the system working.
  IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relname = 'customers' AND NOT t.tgisinternal
               AND (t.tgtype & 1) = 1 AND (t.tgtype & 4) = 4
               AND t.tgname > 'z50_customer_registered_kernel_emit') THEN
    RAISE EXCEPTION 'Q03: a row-level INSERT trigger on public.customers sorts AFTER the kernel '
      'emit; Postgres fires in name order and the emit must be last' USING errcode = '23514';
  END IF;

  -- (b) both registries admit it, or the emit would raise at the first real customer.
  SELECT 'dbtrigger:public.customers:z50_customer_registered_kernel_emit' = ANY (allowed_source_systems)
    INTO v_allowed FROM public.kernel_trigger_type WHERE trigger_type = 'customer.registered';
  SELECT count(*) INTO v_cutover FROM public.phase_c_source_cutover
   WHERE source_component_id = 'dbtrigger:public.customers:z50_customer_registered_kernel_emit';
  IF NOT coalesce(v_allowed, false) OR v_cutover <> 1 THEN
    RAISE EXCEPTION 'Q03: the source is not admitted by both registries (allowed=%, cutover=%)',
      coalesce(v_allowed::text,'null'), v_cutover USING errcode = '23514';
  END IF;

  -- (c) public.customers is now a ROUTED work table, and no edge function that writes it is left
  --     carrying it as unrouted. This is the assertion the per-function credit could not make.
  SELECT string_agg(DISTINCT d.source_key || ' [' || d.unrouted_work_tables || ']', '; ')
    INTO v_unrouted
    FROM public.v_kernel_trigger_source_derived d
   WHERE d.unrouted_work_tables IS NOT NULL AND d.unrouted_work_tables ~ '\ycustomers\y';
  IF v_unrouted IS NOT NULL THEN
    RAISE EXCEPTION 'Q03: public.customers is still unrouted for %', v_unrouted USING errcode = '23514';
  END IF;

  -- (d) drawing_redact is in the inventory. An active state-changing source may not be absent.
  SELECT count(*) INTO v_drawing FROM public.kernel_trigger_source WHERE source_key = 'edge:drawing_redact';
  IF v_drawing <> 1 THEN
    RAISE EXCEPTION 'Q03: edge:drawing_redact is not in the source inventory' USING errcode = '23514';
  END IF;

  -- (e) THE BYPASS POPULATION, RECOMPUTED FROM THE CORRECTED VIEW. Reported, not asserted to a
  --     number typed here: an expectation typed into the check it guards is the defect this estate
  --     has already paid for. What IS asserted is the one thing this file set out to do — that no
  --     survivor writes public.customers.
  SELECT count(*), string_agg(source_key, ', ' ORDER BY source_key) INTO v_bypass, v_bypass_who
    FROM public.v_kernel_trigger_source_derived
   WHERE coalesce(is_active_now, false) AND coalesce(creates_work_now, false)
     AND coalesce(disposition, '') NOT IN ('FOUNDER_COMMAND_SURFACE',
                                           'RECOMPUTATION_ONLY_NO_BUSINESS_WORK',
                                           'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE')
     AND NOT coalesce(routes_through_inbox, false);

  -- (f) NOTHING FROZEN MOVED.
  SELECT count(*) INTO v_a_drift FROM public.fn_phase_a_baseline_drift();
  SELECT count(*) INTO v_b_drift FROM public.fn_phase_b_baseline_drift();
  IF v_a_drift <> 0 OR v_b_drift <> 0 THEN
    RAISE EXCEPTION 'Q03: phase A drift % row(s), phase B drift % row(s)', v_a_drift, v_b_drift
      USING errcode = '23514';
  END IF;

  RAISE NOTICE 'Q03 OK: customers routed to W04 at the table; drawing_redact inventoried; '
    'remaining active sources not routing through the inbox = % [%]; phase A 0, phase B 0',
    v_bypass, coalesce(v_bypass_who, 'none');
END $assert$;

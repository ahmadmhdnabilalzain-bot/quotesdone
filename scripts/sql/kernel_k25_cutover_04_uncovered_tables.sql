-- K25 — cutover increment 4 of 8: the tables no trigger was watching.
--
-- The plan for this increment was nineteen Edge Functions, each gaining a call to
-- fn_kernel_source_emit. Measuring what they actually write changed it, and the measurement is
-- worth the space because it decides the shape of the rest of the cutover.
--
-- Every active class-A/B Edge Function was scanned for the tables it writes:
--
--   customer_api, supplier_api, supplier_portal, refund_flow, stripe_webhook, stripe_confirm,
--   messages_api, supplier_ack   ->  all write inquiries, quotes, quote_items or transactions
--
-- Those four tables already carry cut-over triggers from increments 1 to 3. An Edge Function
-- inserting an inquiry ALREADY reaches the kernel, through trg_inquiry_received_a. Adding a
-- second emit inside the function would be a second delivery of one business event — precisely
-- the duplicate this rebuild exists to end. So they are not edited, and this file records why
-- rather than leaving a reader to wonder whether they were forgotten.
--
-- The database trigger is also the better chokepoint on the merits. It catches EVERY writer of
-- that table — the Edge Function, a cron job, a future service, a hand-run statement — where an
-- edit inside one function catches only that function.
--
-- WHAT WAS GENUINELY UNCOVERED. These write no table that any trigger was watching, so a customer
-- could contact the company, request their data, or upload a document and no workflow would ever
-- open:
--
--   contact_submit, site_assistant, wa_inbound  ->  contact_messages   ->  W18
--   pdpl_request                                ->  pdpl_requests      ->  W28
--   customer_documents, attach_photos           ->  documents          ->  W07
--
-- Three new AFTER INSERT triggers, one per table, each emitting through the same wrapper.
--
-- WHY documents FILTERS AND THE OTHER TWO DO NOT. documents holds every file the estate stores —
-- licences, expense receipts, extraction artefacts. Only a file attached to an inquiry is a
-- customer document arriving for W07, so the trigger fires on ref_table = 'inquiries' and stays
-- quiet otherwise. Emitting on every row would open a W07 run for every licence PDF the importer
-- writes. contact_messages and pdpl_requests hold nothing else, so they need no filter.
--
-- ACTIVATION: none of these tables gains a workflow it did not already need. Three triggers are
-- created where there were none; no disabled source is switched on.
--
-- Rollback: scripts/sql/rollback/kernel_k25_cutover_04_uncovered_tables.rollback.sql

begin;

-- ------------------------------------------------------------------ W18, from the contact form
create or replace function public.trg_contact_message_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k25_contact$
begin
  perform public.fn_kernel_source_emit('edge:contact_submit', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object(
      'case_ref', 'contact:' || NEW.id::text,
      'email',    NEW.email,
      'source',   NEW.source,
      'name',     NEW.name)));
  return NEW;
end
$k25_contact$;

revoke all on function public.trg_contact_message_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_contact_message_to_kernel on public.contact_messages;
create trigger z95_contact_message_to_kernel
  after insert on public.contact_messages
  for each row execute function public.trg_contact_message_to_kernel();

-- ------------------------------------------------------------------ W28, from a privacy request
create or replace function public.trg_pdpl_request_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k25_pdpl$
begin
  perform public.fn_kernel_source_emit('edge:pdpl_request', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object(
      'request_id', NEW.id::text,
      'kind',       NEW.kind,
      'email',      NEW.email,
      'role',       NEW.role)));
  return NEW;
end
$k25_pdpl$;

revoke all on function public.trg_pdpl_request_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_pdpl_request_to_kernel on public.pdpl_requests;
create trigger z95_pdpl_request_to_kernel
  after insert on public.pdpl_requests
  for each row execute function public.trg_pdpl_request_to_kernel();

-- ------------------------------------------------------------------ W07, from a customer document
create or replace function public.trg_document_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k25_doc$
begin
  -- Only a document attached to an inquiry is a customer document arriving for W07. This table
  -- also holds licences, expense receipts and extraction artefacts, and opening a workflow run for
  -- each of those would be a run per file the importer writes.
  if coalesce(NEW.ref_table,'') <> 'inquiries' then
    return NEW;
  end if;
  perform public.fn_kernel_source_emit('edge:customer_documents', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'workflow_run_id', public.fn_kernel_run_for('inquiry:' || coalesce(NEW.ref_id,'')),
    'raw_payload', jsonb_build_object(
      'document_id', NEW.id::text,
      'inquiry_id',  NEW.ref_id,
      'file_name',   NEW.file_name,
      'kind',        NEW.kind,
      'bucket',      NEW.bucket)));
  return NEW;
end
$k25_doc$;

revoke all on function public.trg_document_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_document_to_kernel on public.documents;
create trigger z95_document_to_kernel
  after insert on public.documents
  for each row execute function public.trg_document_to_kernel();

-- ------------------------------------------------------------------ the routes these need
--
-- Each source key must be permitted to submit its type. The allow-list is a real gate and adding
-- the exact key each source will send keeps it one.
update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['edge:contact_submit']
 where trigger_type = 'customer.support_signal'
   and not ('edge:contact_submit' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['edge:pdpl_request']
 where trigger_type = 'customer.privacy_request'
   and not ('edge:pdpl_request' = any (allowed_source_systems));

-- edge:customer_documents is class B: a document arriving for an inquiry already being worked is
-- evidence on that run. document.arrived_for_run is ATTACH_ONLY, which is what a file is.
update public.kernel_signal_type
   set activation_state = 'active'
 where signal_type = 'document.arrived_for_run';

-- ------------------------------------------------------------------ what is still not cut over
--
-- Recorded on the row rather than left as an absence. site_assistant and wa_inbound reach W18
-- through contact_messages only when they write one; inbound_email, resend_inbound, sup_dob and
-- supplier_onboard write leads, inbound_messages and agent_actions, and none of those has a
-- kernel route yet. They are named here so the gap is a fact in the register, not a silence.
update public.phase_c_source_cutover
   set status = 'COVERED_BY_A_CUT_OVER_TABLE_TRIGGER',
       cutover_action = 'No edit. It writes inquiries, quotes, quote_items or transactions, and '
                     || 'those tables already reach the kernel through the triggers cut over in '
                     || 'increments 1-3. A second emit here would deliver one business event twice.'
 where source_component_id in (
   'edge:customer_api','edge:supplier_api','edge:supplier_portal','edge:refund_flow',
   'edge:stripe_webhook','edge:stripe_confirm','edge:messages_api','edge:supplier_ack');

update public.phase_c_source_cutover
   set status = 'CUTOVER_VIA_TABLE_TRIGGER',
       cutover_action = 'Cut over by an AFTER INSERT trigger on the table it writes, so every '
                     || 'writer of that table reaches the kernel and not only this function.'
 where source_component_id in ('edge:contact_submit','edge:pdpl_request','edge:customer_documents');

update public.phase_c_source_cutover
   set status = 'NOT_YET_CUT_OVER',
       cutover_action = 'Still owed. It writes leads, inbound_messages or agent_actions, and none '
                     || 'of those carries a kernel route yet. Named here so the gap is a fact in '
                     || 'the register rather than an absence somebody has to notice.'
 where source_component_id in (
   'edge:inbound_email','edge:resend_inbound','edge:sup_dob','edge:supplier_onboard',
   'edge:site_assistant','edge:wa_inbound','edge:attach_photos');

commit;

-- K30 — cutover increment 6 of 8: the last bypass sources, and two of K10's mappings corrected.
--
-- Eight Edge Functions were left. Reading what each one actually WRITES — not what the register
-- said it meant — changed the disposition of five of them, and two of K10's trigger-type mappings
-- turn out to be wrong in the same way `trg_goal_cascade` was: wiring them as recorded would have
-- manufactured workflow runs for events that are not what the workflow starts from.
--
-- ================================================================== what each one writes
--
--   edge:inquiry_intake     inquiry_intake (a DRAFT), agent_runs, ai_qa_log
--   edge:inbound_email      inbound_messages, leads  (business_role: 'supplier')
--   edge:site_assistant     assistant_logs, llm_calls, agent_runs
--   edge:wa_inbound         wa_messages, notifications, doc_reviews, founder_alerts
--   edge:sup_dob            leads.owner_dob, and nothing else
--   edge:resend_inbound     inbound_messages, expenses, expense_entries, doc_reviews
--   edge:supplier_onboard   agent_actions — one row, status 'logged', risk 'low'
--   edge:attach_photos      NOTHING. It reads app_secrets and customers and returns.
--
-- ================================================================== the two corrected mappings
--
-- edge:inquiry_intake was mapped to customer.inquiry_submitted -> W05. It does not create an
-- inquiry. It creates a DRAFT in inquiry_intake, and customer_api promotes a draft marked 'ready'
-- into public.inquiries and sets the draft 'consumed' (customer_api/index.ts:667, 764, 766). That
-- insert already reaches the kernel through trg_inquiry_received_a, cut over in increment 1.
-- Starting W05 from the draft as well would open TWO runs for one customer request — and the
-- business object rule inquiry:{inquiry_id} could not resolve from a draft anyway, so every
-- submission would have been refused. Covered, not wired.
--
-- edge:inbound_email was mapped to customer.inquiry_submitted -> W05. It handles SUPPLIER
-- correspondence: it matches or creates a leads row with business_role 'supplier' and records the
-- message. A supplier emailing in is not a customer inquiry. Routing it to W05 would open a
-- customer-inquiry run for every supplier email the company receives. Corrected to
-- supplier.registration_submitted -> W09, and only when the email actually created a new supplier
-- lead — `created_new_lead` is written on the inbound_messages row, so the trigger reads the
-- decision the function already made rather than guessing at it.
--
-- ================================================================== the four new chokepoints
--
--   assistant_logs    WHEN escalated  -> W18 customer.support_signal
--   wa_messages       WHEN escalated  -> W18 customer.support_signal
--   inbound_messages  WHEN created_new_lead -> W09 supplier.registration_submitted
--   leads             WHEN owner_dob first appears -> document.arrived_for_run on the W10 run
--
-- `escalated` is the filter that matters on the first two. Both tables hold every message the
-- assistant and the WhatsApp bot ever answered — 106 and 12 rows today, and they only grow. A
-- question the FAQ answered is not a support signal; an ESCALATED one is, and it is the row the
-- estate already marks as needing a person. Emitting on every message would open a W18 run for
-- every "what are your hours".
--
-- leads is 20,470 rows, so its trigger is narrowed twice: AFTER UPDATE OF owner_dob, and only when
-- the column goes from absent to present. A supplier completing their own file is a signal on the
-- W10 verification run if one is open, and refused-and-recorded if not.
--
-- ================================================================== three that create no work
--
-- edge:attach_photos writes no table at all. It is an upload helper: it reads a secret and a
-- customer row and returns. A source that changes no business state is class C by measurement.
--
-- edge:supplier_onboard's only write is one agent_actions row with status 'logged' and risk 'low',
-- inside a try/catch whose own comment reads "telemetry is not the product". The registration it
-- was mapped to happens elsewhere. Class C.
--
-- edge:resend_inbound books expenses from forwarded receipts. That is real business state, and no
-- Phase B workflow declares it — W27 is a scheduled financial close, not a receipt arriving. It
-- writes none of the eight tables K18 protects, so it is not a kernel bypass; it OWES a Phase B
-- workflow, and saying so is more useful than routing an expense receipt to W07 as a customer
-- document, which is what the register said and which would have been wrong.
--
-- ACTIVATION: nothing is switched on. Four triggers are created where there were none; no disabled
-- source is enabled.
--
-- Rollback: scripts/sql/rollback/kernel_k30_last_bypass_sources.rollback.sql

begin;

-- ------------------------------------------------------------------ W18, from the site assistant
create or replace function public.trg_assistant_log_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k30_assistant$
begin
  perform public.fn_kernel_source_emit('edge:site_assistant', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object(
      'case_ref', 'assistant:' || NEW.id::text,
      'message',  left(coalesce(NEW.message,''), 500),
      'audience', NEW.audience,
      'path',     NEW.path)));
  return NEW;
end
$k30_assistant$;

revoke all on function public.trg_assistant_log_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_assistant_log_to_kernel on public.assistant_logs;
create trigger z95_assistant_log_to_kernel
  after insert on public.assistant_logs
  for each row when (new.escalated is true)
  execute function public.trg_assistant_log_to_kernel();

-- ------------------------------------------------------------------ W18, from WhatsApp
create or replace function public.trg_wa_message_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k30_wa$
begin
  perform public.fn_kernel_source_emit('edge:wa_inbound', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object(
      'case_ref', 'wa:' || NEW.id::text,
      'wa_from',  NEW.wa_from,
      'inbound',  left(coalesce(NEW.inbound,''), 500),
      'lang',     NEW.lang)));
  return NEW;
end
$k30_wa$;

revoke all on function public.trg_wa_message_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_wa_message_to_kernel on public.wa_messages;
create trigger z95_wa_message_to_kernel
  after insert on public.wa_messages
  for each row when (new.escalated is true)
  execute function public.trg_wa_message_to_kernel();

-- ------------------------------------------------------------------ W09, from inbound supplier email
create or replace function public.trg_inbound_message_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k30_inbound$
begin
  perform public.fn_kernel_source_emit('edge:inbound_email', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object(
      'supplier_ref', NEW.lead_id::text,
      'lead_id',      NEW.lead_id::text,
      'from_email',   NEW.from_email,
      'subject',      left(coalesce(NEW.subject,''), 300))));
  return NEW;
end
$k30_inbound$;

revoke all on function public.trg_inbound_message_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_inbound_message_to_kernel on public.inbound_messages;
create trigger z95_inbound_message_to_kernel
  after insert on public.inbound_messages
  -- The function already decided whether this email created a supplier; the trigger reads that
  -- decision rather than re-deriving it. lead_id is required because supplier_account:{supplier_ref}
  -- cannot resolve without one, and a refusal recorded for every ambiguous email is noise.
  for each row when (new.created_new_lead is true and new.lead_id is not null)
  execute function public.trg_inbound_message_to_kernel();

-- ------------------------------------------------------------------ W10 signal, supplier file completion
create or replace function public.trg_lead_dob_to_kernel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k30_dob$
begin
  perform public.fn_kernel_source_emit('edge:sup_dob', jsonb_build_object(
    'source_ref',      NEW.id::text,
    'workflow_run_id', public.fn_kernel_run_for('supplier_verification_case:' || NEW.id::text),
    'raw_payload', jsonb_build_object(
      'document_id',  'owner_dob:' || NEW.id::text,
      'supplier_ref', NEW.id::text,
      'field',        'owner_dob')));
  return NEW;
end
$k30_dob$;

revoke all on function public.trg_lead_dob_to_kernel() from public, anon, authenticated;

drop trigger if exists z95_lead_dob_to_kernel on public.leads;
create trigger z95_lead_dob_to_kernel
  after update of owner_dob on public.leads
  -- leads is 20,470 rows. Narrowed twice: the column, and the transition from absent to present.
  for each row when (old.owner_dob is null and new.owner_dob is not null)
  execute function public.trg_lead_dob_to_kernel();

-- ------------------------------------------------------------------ the routes these need
update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['edge:site_assistant','edge:wa_inbound']
 where trigger_type = 'customer.support_signal'
   and not ('edge:site_assistant' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['edge:inbound_email']
 where trigger_type = 'supplier.registration_submitted'
   and not ('edge:inbound_email' = any (allowed_source_systems));

commit;

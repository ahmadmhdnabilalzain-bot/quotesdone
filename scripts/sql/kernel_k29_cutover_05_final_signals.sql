-- K29 — cutover increment 5 of 8: the three remaining class-B database triggers.
--
--   inquiry_matches:notify_matched_supplier -> the inquiry's live run  (followup.due)
--   notifications:trg_invite_status_on_send -> the supplier's W09 run  (provider.callback)
--   supplier_dues:trg_due_paid              -> the W16 run             (provider.callback)
--
-- Each finds its run with fn_kernel_run_for and each keeps everything it already did. None of the
-- three writes a workflow run, step run, task, handoff or outbox row today: the first sends a
-- supplier notification, the second sets leads.invite_status, the third clears a matching block.
-- Those are business side effects, not business work, and the kernel gains the signal rather than
-- the estate losing the effect.
--
-- Where each call sits is again the substance:
--
--   fn_notify_matched_supplier   at the top, before the email lookup. A match is a fact about the
--                                inquiry whether or not the supplier has an address on file.
--   fn_invite_status_on_send     INSIDE the branch that tests type='supplier_invite' and
--                                status='sent'. At the top it would fire on every status change to
--                                every notification the company has ever queued.
--   qd_on_due_paid               INSIDE the branch that tests the due became paid, before the
--                                all-dues-settled check — the payment is the callback, and whether
--                                it happens to clear the last block is a separate question.
--
-- fn_notify_matched_supplier attaches to the run the INQUIRY has, not to a W12 run. The register
-- named W12 because that is the workflow whose approval produces a safe package; the run that
-- actually exists for that inquiry is the W05 one trg_inquiry_received_a opened. followup.due
-- carries no workflow_id, so the signal door accepts it against whichever run the object really
-- has — and attaching to the run that exists beats naming one that does not.
--
-- ACTIVATION: none. All three triggers were already enabled and firing.
--
-- Rollback: scripts/sql/rollback/kernel_k29_cutover_05_final_signals.rollback.sql

begin;

-- dbtrigger:public.inquiry_matches:notify_matched_supplier
--   A supplier being matched happens INSIDE the run the inquiry already has. Starting a workflow per match would open one run per supplier for one customer request.
CREATE OR REPLACE FUNCTION public.fn_notify_matched_supplier()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text; v_cat text; v_em text;
begin
  -- Kernel cutover. A supplier being matched happens INSIDE the run the inquiry already has. Starting a workflow per match would open one run per supplier for one customer request.
  perform public.fn_kernel_source_emit('dbtrigger:public.inquiry_matches:notify_matched_supplier', jsonb_build_object(
    'source_ref',  NEW.inquiry_id::text || ':' || NEW.supplier_id::text,
    'workflow_run_id', public.fn_kernel_run_for('inquiry:' || NEW.inquiry_id::text),
    'raw_payload', jsonb_build_object('inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text)));
  select email into v_email from leads where id=NEW.supplier_id;
  select category, emirate into v_cat, v_em from inquiries where id=NEW.inquiry_id;
  if v_email is not null and position('@' in v_email) > 1 then
    insert into notifications(type,to_email,to_role,lead_id,inquiry_id,subject,body,channel,status)
    values('new_inquiry', v_email, 'supplier', NEW.supplier_id, NEW.inquiry_id,
      'New job request on QuotesDone',
      'A customer is requesting quotes for: '||coalesce(v_cat,'a project')||coalesce(' ('||v_em||')','')||
      '. Log in to your QuotesDone supplier portal to view the brief and submit your quote.',
      'email','queued');
  end if;
  return NEW;
end $function$
;

-- dbtrigger:public.notifications:trg_invite_status_on_send
--   A delivery status change on an invitation already sent. The registration itself is the class-A event; this is its provider callback, and it belongs to the run that registration opened.
CREATE OR REPLACE FUNCTION public.fn_invite_status_on_send()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.type = 'supplier_invite' and new.status = 'sent'
     and coalesce(old.status,'') is distinct from 'sent' and new.lead_id is not null then
  -- Kernel cutover. A delivery status change on an invitation already sent. The registration itself is the class-A event; this is its provider callback, and it belongs to the run that registration opened.
  perform public.fn_kernel_source_emit('dbtrigger:public.notifications:trg_invite_status_on_send', jsonb_build_object(
    'source_ref',  new.id::text,
    'workflow_run_id', public.fn_kernel_run_for('supplier_account:' || new.lead_id::text),
    'raw_payload', jsonb_build_object('notification_id', new.id::text, 'lead_id', new.lead_id::text, 'status', new.status)));
    update public.leads
       set invite_status = 'sent'
     where id = new.lead_id and coalesce(invite_status,'') = 'queued';
  end if;
  return new;
end
$function$
;

-- dbtrigger:public.supplier_dues:trg_due_paid
--   Settlement of an obligation that already exists. The reveal payment that OPENS W16 is trg_reveal_receipt_a; this is the callback on that run.
CREATE OR REPLACE FUNCTION public.qd_on_due_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if (coalesce(NEW.status,'')='paid' or NEW.paid_at is not null) and (OLD.status is distinct from NEW.status or OLD.paid_at is distinct from NEW.paid_at) then
  -- Kernel cutover. Settlement of an obligation that already exists. The reveal payment that OPENS W16 is trg_reveal_receipt_a; this is the callback on that run.
  perform public.fn_kernel_source_emit('dbtrigger:public.supplier_dues:trg_due_paid', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'workflow_run_id', public.fn_kernel_run_for('payment_transaction:' || coalesce((select nullif(t.payment_ref,'') from public.transactions t where t.id = NEW.transaction_id), NEW.transaction_id::text)),
    'raw_payload', jsonb_build_object('due_id', NEW.id::text, 'supplier_id', NEW.supplier_id::text, 'transaction_id', NEW.transaction_id::text, 'status', NEW.status)));
    if not exists (select 1 from supplier_dues d where d.supplier_id=NEW.supplier_id and coalesce(d.status,'')<>'paid' and d.paid_at is null and d.id<>NEW.id) then
      update leads set matching_blocked=false, matching_block_reason=null where id=NEW.supplier_id and coalesce(rv_nonresponse_refunds,0)<2;
    end if;
  end if;
  return NEW;
end $function$
;


commit;

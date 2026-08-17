-- K21 — cutover increment 2 of 8: supplier, payment and system-health sources.
--
-- Three more live database triggers start calling the kernel, each gaining one line:
--
--   dbtrigger:public.quotes:trg_new_quote_sms                 -> W14 supplier.quotation_submitted
--   dbtrigger:public.transactions:trg_reveal_receipt_a        -> W16 provider.payment_event
--   dbtrigger:public.agent_actions:trg_page_high_agent_action -> W29 system.incident_opened
--
-- WHERE, and why not simply at the end:
--
--   notify_new_quote_sms        at the TOP, before the early return for an inquiry with no
--                               customer. A quotation exists and must be evaluated whether or not
--                               there is anybody to text about it; at the end, a quote on an
--                               orphaned inquiry would silently never be evaluated.
--   trg_reveal_receipt          INSIDE the branch testing revealed_at, so it fires once when the
--                               reveal actually happens rather than on every update to the row.
--   fn_page_high_agent_action   INSIDE the risk branch, so an ordinary agent action does not open
--                               an incident.
--
-- A FOURTH SOURCE IS DELIBERATELY NOT CUT OVER, and this file records why.
--
-- dbtrigger:public.company_goals:trg_goal_cascade was mapped by K10 to kpi.company_target_miss ->
-- W02. Reading the deployed body before wiring it: it fires on
--
--   if old.active is true and new.active is false then
--
-- which is a company goal being RETIRED. That is not a missed target. W02 starts from "Material
-- KPI/trajectory miss", and pointing this at W02 would open a corrective-management run every
-- time the founder tidies up a goal he no longer wants — a workflow run manufactured by a
-- misreading.
--
-- It does create business work outside the kernel: an org_tasks row asking the department to
-- re-plan. That is real and it is exactly what this cutover exists to route. But no Phase B
-- workflow starts from a goal retirement, so there is nowhere honest to route it. It is recorded
-- as owing a handler rather than forced into the nearest workflow, which is the failure this
-- rebuild is correcting rather than repeating.
--
-- ACTIVATION: none. All three triggers were already enabled and firing.
--
-- Rollback: scripts/sql/rollback/kernel_k21_cutover_02_supplier_system.rollback.sql

begin;

-- dbtrigger:public.quotes:trg_new_quote_sms
--   A new quotation row is the declared start of W14. Placed at the TOP, before the early return for an inquiry with no customer: a quotation exists and must be evaluated whether or not there is somebody to text about it.
CREATE OR REPLACE FUNCTION public.notify_new_quote_sms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare inq record; c record;
begin
  -- K20 cutover. A new quotation row is the declared start of W14. Placed at the TOP, before the early return for an inquiry with no customer: a quotation exists and must be evaluated whether or not there is somebody to text about it.
  perform public.fn_kernel_source_emit('dbtrigger:public.quotes:trg_new_quote_sms', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('quotation_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text)));
  select i.summary, i.customer_id into inq from public.inquiries i where i.id = NEW.inquiry_id;
  if inq.customer_id is null then return NEW; end if;
  select email, phone, phone_verified into c from public.customers where id = inq.customer_id;
  if c.phone is not null and coalesce(c.phone_verified,false) then
    insert into public.notifications(type, channel, to_phone, to_role, inquiry_id, quote_id, subject, body, status)
    values ('new_quote_sms','sms', c.phone, 'customer', NEW.inquiry_id, NEW.id, '',
      'QuotesDone: you have a new quote on your request'||coalesce(': '||left(inq.summary,80),'')||'. View & compare at quotesdone.com/app', 'queued');
  end if;
  return NEW;
end $function$
;

-- dbtrigger:public.transactions:trg_reveal_receipt_a
--   The reveal payment is the declared start of W16. Placed INSIDE the branch that tests revealed_at, so it fires once when the reveal actually happens and not on every update to the transaction.
CREATE OR REPLACE FUNCTION public.trg_reveal_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cemail text; comp text; inq record;
begin
  if NEW.revealed_at is not null and (TG_OP='INSERT' or OLD.revealed_at is null) then
  -- K20 cutover. The reveal payment is the declared start of W16. Placed INSIDE the branch that tests revealed_at, so it fires once when the reveal actually happens and not on every update to the transaction.
  perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_reveal_receipt_a', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('provider_event_id', coalesce(nullif(NEW.payment_ref,''), NEW.id::text), 'transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));
    select email into cemail from public.customers where id = NEW.customer_id;
    select company_name into comp from public.leads where id = NEW.supplier_id;
    select summary, category into inq from public.inquiries where id = NEW.inquiry_id;
    if cemail is not null then
      insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
      values('reveal_receipt', cemail, 'customer', NEW.inquiry_id,
        'Reveal confirmed — '||coalesce(comp,'supplier'),
        'You have unlocked '||coalesce(comp,'the supplier')||'''s contact details'||coalesce(' for: '||left(inq.summary,80),'')||'. You can now message them directly in the app. If they do not respond within 72 hours, open the request and Report an issue to request a refund of your reveal fee.',
        'queued');
    end if;
  end if;
  return NEW;
end $function$
;

-- dbtrigger:public.agent_actions:trg_page_high_agent_action
--   A high or critical pending action from finance, security or operations is the declared start of W29. Placed INSIDE the risk branch, so an ordinary agent action does not open an incident.
CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_founder text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     -- K21. Was: NEW.agent IN ('finance_ai','security_ai','operations_ai'). That set could never
     -- match a security action. a00_agent_action_resolve_addressee runs BEFORE this trigger and
     -- resolves the addressee through org_agents, so a row written as 'security_ai' arrives here
     -- as 'security'. Measured: inserting agent='security_ai' reads back as 'security', and
     -- notifications has 0 rows of type 'agent_escalation' in its entire history — the founder has
     -- never been paged by this trigger. A prefix match survives the resolver in both directions
     -- and does not need a keep-list that has to be remembered every time an agent is renamed.
     AND NEW.agent ~ '^(finance|security|operations)'
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
  -- K20 cutover. A high or critical pending action from finance, security or operations is the declared start of W29. Placed INSIDE the risk branch, so an ordinary agent action does not open an incident.
  perform public.fn_kernel_source_emit('dbtrigger:public.agent_actions:trg_page_high_agent_action', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('incident_ref', 'agent_action:' || NEW.id::text, 'agent', NEW.agent, 'kind', NEW.kind, 'risk', NEW.risk, 'title', NEW.title)));
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$function$
;

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.quotes:trg_new_quote_sms']
 where trigger_type = 'supplier.quotation_submitted'
   and not ('dbtrigger:public.quotes:trg_new_quote_sms' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.transactions:trg_reveal_receipt_a']
 where trigger_type = 'provider.payment_event'
   and not ('dbtrigger:public.transactions:trg_reveal_receipt_a' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.agent_actions:trg_page_high_agent_action']
 where trigger_type = 'system.incident_opened'
   and not ('dbtrigger:public.agent_actions:trg_page_high_agent_action' = any (allowed_source_systems));

-- trg_goal_cascade is NOT cut over here, and the register is corrected to say why.
--
-- K10 mapped it to kpi.company_target_miss -> W02. Reading the deployed body, it fires on
-- `old.active is true and new.active is false` — a company goal being RETIRED. A retired goal is
-- not a missed target. W02 starts from "Material KPI/trajectory miss", which this signal is not,
-- and pointing it at W02 would open a corrective-management run every time the founder tidies up
-- a goal he no longer wants.
--
-- It does create business work outside the kernel: it inserts an org_tasks row asking the
-- department to re-plan. That is real, and it is exactly what the cutover exists to route. But
-- there is no Phase B workflow that starts from a goal retirement, so there is nowhere honest to
-- route it to yet. It joins the handlers K10 already counted as owed rather than being forced
-- into the nearest workflow, which is the failure mode this whole rebuild is correcting.
update public.phase_c_source_cutover
   set status = 'BLOCKED_NO_WORKFLOW_FOR_THIS_SIGNAL',
       cutover_action = 'NOT cut over. Its signal is a goal RETIREMENT and no Phase B workflow '
                     || 'starts from one. It owes a handler; it does not owe a wrong route.',
       classification_reason = classification_reason
         || ' | K21 2026-08-17: the assigned trigger type kpi.company_target_miss is WRONG. The '
         || 'deployed body fires on old.active is true and new.active is false — a goal being '
         || 'retired, not a target being missed. It inserts an org_tasks re-plan row, which is '
         || 'business work created outside the kernel, but no Phase B workflow starts from a goal '
         || 'retirement, so it is recorded as owing a handler instead of being routed to the '
         || 'nearest workflow.'
 where source_component_id = 'dbtrigger:public.company_goals:trg_goal_cascade';

commit;

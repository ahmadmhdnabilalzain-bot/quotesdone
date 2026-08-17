-- K20 — cutover increment 1 of 8: customer sources.
--
-- Three live database triggers start calling the kernel. Each gains ONE line and loses nothing:
--
--   dbtrigger:public.inquiries:trg_inquiry_received_a  -> W05 customer.inquiry_submitted
--   dbtrigger:public.inquiries:customer_abandon_ban    -> W18 customer.support_signal
--   dbtrigger:public.transactions:trg_notify_refund    -> W17 customer.refund_requested
--
-- WHY NOTHING IS REMOVED. §3 says a cut-over source must stop directly creating workflow runs,
-- step runs, operational tasks, handoffs and business-state events. Read for what they actually
-- write, none of these three ever did: trg_inquiry_received writes one customer confirmation
-- notification, trg_customer_abandon_ban writes a customers ban flag and an agent_actions review
-- item, qd_notify_refund_request writes one owner notification. Those are business SIDE EFFECTS,
-- not business work, and deleting a customer's "we have received your request" email in the name
-- of a kernel cutover would be a regression dressed as compliance. What was missing was the
-- workflow, and that is what this file adds. K18 already makes the forbidden writes impossible
-- for them regardless of what any file says.
--
-- WHERE EACH CALL SITS, and why it is not simply "at the end":
--
--   trg_inquiry_received       at the final return, AFTER the early return that lets a child
--                              sub-RFQ of a combined project through. A combined project is one
--                              piece of work; giving each trade its own W05 would open four runs
--                              for one customer request. It is also after the `cemail is null`
--                              branch, so a new inquiry starts its workflow whether or not we
--                              have an address to confirm it to.
--   trg_customer_abandon_ban   INSIDE the `if n >= 4` branch. The auto-pause is the support
--                              signal. At the end of the function it would fire on every
--                              cancellation and open a W18 for every request anyone withdraws.
--   qd_notify_refund_request   at the final return, so the owner's complaint email is sent
--                              whether or not the kernel accepts the request.
--
-- The bodies were not edited by hand. scripts/phase_c/gen_cutover.mjs reads each DEPLOYED
-- definition, inserts one call at a named anchor, and refuses to emit if the anchor is missing,
-- appears more than once, or the routine already carries the call. Everything else is byte
-- identical to what is running now.
--
-- ACTIVATION: none. All three triggers were already enabled and firing; this changes what they do
-- when they fire, not whether they fire. No disabled source is switched on by this file.
--
-- Rollback: scripts/sql/rollback/kernel_k20_cutover_01_customer.rollback.sql

begin;

-- dbtrigger:public.inquiries:trg_inquiry_received_a
--   A new PARENT inquiry starts W05. Placed at the final return, after the early return that lets a child sub-RFQ of a combined project through without its own workflow — a combined project is one piece of work, not four.
CREATE OR REPLACE FUNCTION public.trg_inquiry_received()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare cemail text;
begin
  -- child sub-RFQs of a combined project do not get their own "received" notice
  if NEW.parent_inquiry_id is not null then return NEW; end if;
  select email into cemail from public.customers where id = NEW.customer_id;
  if cemail is not null then
    insert into public.notifications(type,to_email,to_role,inquiry_id,subject,body,status)
    values('inquiry_received', cemail, 'customer', NEW.id,
      'We have received your request',
      case
        when NEW.scope_type = 'multi' then
          'Thanks — your combined request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We have split it into separate requests per trade and are matching each to the right specialists'||coalesce(' in '||NEW.emirate,' in the UAE')||'. You will be notified as quotes come in — track everything in the app.'
        when NEW.scope_type = 'turnkey' then
          'Thanks — your combined request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We are matching it to turnkey fit-out companies that can handle the whole project'||coalesce(' in '||NEW.emirate,' in the UAE')||'. You will be notified as quotes come in — track everything in the app.'
        else
          'Thanks — your request'||coalesce(' for '||left(NEW.summary,80),'')||' is in. We are matching it to relevant '||coalesce(NEW.category,'')||' suppliers in '||coalesce(NEW.emirate,'the UAE')||'. You will be notified as quotes come in — track everything in the app.'
      end,
      'queued');
  end if;
  -- K20 cutover. A new PARENT inquiry starts W05. Placed at the final return, after the early return that lets a child sub-RFQ of a combined project through without its own workflow — a combined project is one piece of work, not four.
  perform public.fn_kernel_source_emit('dbtrigger:public.inquiries:trg_inquiry_received_a', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('inquiry_id', NEW.id::text, 'customer_id', NEW.customer_id::text, 'category', NEW.category, 'emirate', NEW.emirate, 'scope_type', NEW.scope_type)));
  return NEW;
end $function$
;

-- dbtrigger:public.inquiries:customer_abandon_ban
--   The auto-pause at four abandoned requests is the support signal, so the emit sits INSIDE that branch. On every cancellation it would open a W18 for every inquiry anyone ever withdraws.
CREATE OR REPLACE FUNCTION public.trg_customer_abandon_ban()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  if NEW.status = 'cancelled' and coalesce(OLD.status,'') <> 'cancelled' then
    select count(*) into n from inquiries i
      where i.customer_id = NEW.customer_id and i.status = 'cancelled'
        and not exists (select 1 from transactions t where t.inquiry_id = i.id);
    if n >= 4 then
  -- K20 cutover. The auto-pause at four abandoned requests is the support signal, so the emit sits INSIDE that branch. On every cancellation it would open a W18 for every inquiry anyone ever withdraws.
  perform public.fn_kernel_source_emit('dbtrigger:public.inquiries:customer_abandon_ban', jsonb_build_object(
    'source_ref',  'abandon:' || NEW.customer_id::text,
    'raw_payload', jsonb_build_object('case_ref', 'abandon:' || NEW.customer_id::text, 'customer_id', NEW.customer_id::text, 'cancelled_count', n, 'inquiry_id', NEW.id::text)));

      update customers set banned = true,
        banned_reason = 'Auto: ' || n || ' requests cancelled without proceeding (time-waster guard) — reversible by admin.'
        where id = NEW.customer_id and coalesce(banned,false) = false;
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id)
      select 'customer_success','customer_autoban','pending','medium',
        'Customer auto-paused ('||n||' cancelled requests)',
        'Review and unban if legitimate. Set customers.banned=false to restore.',
        jsonb_build_object('cancelled_count',n,'email',c.email), 'customers', NEW.customer_id::text
      from customers c where c.id = NEW.customer_id
      and not exists (select 1 from agent_actions a where a.kind='customer_autoban' and a.target_id=NEW.customer_id::text and a.status in ('pending','needs_review'));
    elsif n = 3 then
      insert into notifications(type,to_email,to_role,inquiry_id,channel,status,subject,body)
      select 'abandon_warning', c.email, 'customer', NEW.id, 'email', 'queued',
        'A quick note about your QuotesDone requests',
        'Hi ' || coalesce(c.full_name,'there') || ', we noticed a few of your requests were cancelled before proceeding. Suppliers put real effort into quoting, so please only post jobs you intend to follow through on. Repeated cancellations may temporarily pause your account. Thank you for understanding.'
      from customers c where c.id = NEW.customer_id and c.email like '%@%';
    end if;
  end if;
  return NEW;
end $function$
;

-- dbtrigger:public.transactions:trg_notify_refund
--   A refund complaint raised against a revealed supplier is the declared start of W17. Placed at the final return so the owner notification is sent whether or not the kernel accepts the request.
CREATE OR REPLACE FUNCTION public.qd_notify_refund_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_owner text; v_company text; v_sup text;
begin
  select value into v_owner from app_secrets where key='admin_emails';
  v_owner := split_part(coalesce(v_owner,'management@quotesdone.com'), ',', 1);
  select company_name into v_company from leads where id = NEW.supplier_id;
  insert into notifications(type, to_email, to_role, inquiry_id, subject, body)
  values('refund_complaint', v_owner, 'admin', NEW.inquiry_id,
    'Customer complaint — supplier not responding (reveal refund)',
    'A customer has raised a complaint that a revealed supplier is not responding.'||chr(10)||
    'Supplier: '||coalesce(v_company,'(id '||NEW.supplier_id::text||')')||chr(10)||
    'Inquiry: '||coalesce(NEW.inquiry_id::text,'')||' · Transaction: '||NEW.id::text||' · Reveal fee: AED '||coalesce(NEW.reveal_fee::text,'0')||chr(10)||chr(10)||
    'Action: reach out to the supplier. If they do not respond to you and the customer within 3 working days, issue the refund and record the 3% non-response charge against the supplier. Check supplier@quotesdone.com for the customer''s CC''d complaint email as proof.');
  -- K20 cutover. A refund complaint raised against a revealed supplier is the declared start of W17. Placed at the final return so the owner notification is sent whether or not the kernel accepts the request.
  perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_notify_refund', jsonb_build_object(
    'source_ref',  NEW.id::text,
    'raw_payload', jsonb_build_object('transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));
  return NEW;
end $function$
;

-- The three source keys must be permitted to submit their trigger types. kernel_trigger_type
-- carries a strict allow-list and it was right to refuse them: until this file, no database
-- trigger had ever been a legitimate submitter of anything. The lists were written in the
-- vocabulary of edge functions and cron NAMES ('cron:kpi_review_weekly', 'ui:/portal'); the
-- register keys are source_component_ids ('cron:103', 'ui:/[locale]/portal'). Adding the exact
-- key each source will actually send keeps the allow-list a real gate rather than widening it.
update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.inquiries:trg_inquiry_received_a']
 where trigger_type = 'customer.inquiry_submitted'
   and not ('dbtrigger:public.inquiries:trg_inquiry_received_a' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.inquiries:customer_abandon_ban']
 where trigger_type = 'customer.support_signal'
   and not ('dbtrigger:public.inquiries:customer_abandon_ban' = any (allowed_source_systems));

update public.kernel_trigger_type
   set allowed_source_systems = allowed_source_systems || array['dbtrigger:public.transactions:trg_notify_refund']
 where trigger_type = 'customer.refund_requested'
   and not ('dbtrigger:public.transactions:trg_notify_refund' = any (allowed_source_systems));

commit;

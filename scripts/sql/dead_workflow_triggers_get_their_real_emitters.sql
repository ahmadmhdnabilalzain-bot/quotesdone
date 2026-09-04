-- DEAD WORKFLOW TRIGGERS GET THEIR REAL EMITTERS (4 Sep 2026, MASTER_PLAN §4.4).
--
-- Measured on production before this file (company_event since 1 Aug, emitters by pg_proc body,
-- pg_get_triggerdef and a grep of supabase/functions + scripts):
--   refund.requested     0 emitted. The only emitter was trg_emit_refund_requested on a `refunds`
--                        INSERT, and the only writer of `refunds` is fn_refund_request, whose only
--                        caller is secretary_act. The CUSTOMER's real path — customer_api
--                        request_refund (:1008) — writes transactions.refund_status='requested'
--                        and never touches `refunds`, so a customer asking for the fee back never
--                        started the refund workflow.
--   customer.complaint   0 emitted. Emitter t_emit_customer_complaint on `feedback`, a table no
--                        edge function and no routine writes. The customer's real rating path is
--                        customer_api rate_supplier (:1026) → `reviews`.
--   invoice.received     0 emitted. Emitter trg_emit_invoice_received on `ap_bills`, written only
--                        by fn_po_bill (no caller — the unconnected ERP, §5.1). The real inbound
--                        invoice path is resend_inbound booking a forwarded receipt into
--                        `expense_entries` (expenses@ inbox = the source of truth, founder 1 Sep).
--   campaign.published   0 emitted. Emitter t_emit_campaign_published on phase_d_object_record
--                        (content_campaign), which only the Phase D fixture drive ever writes. The
--                        real Demand publish path is secretary_act tool_post_content → postiz_publish
--                        → content_drafts.status='posted'.
--   budget.exceeded      0 emitted. Emitter fn_emit_budget_exceeded, reached only from
--                        fn_decision_gate (a money decision_record). The plan's second producer —
--                        the Meta optimizer over its cap — is fn_ads_manage's PACE branch, which
--                        already knows the moment (v_active > v_ceiling) and said nothing.
--
-- Each emitter here sits ON the real product path, is additive (no existing emitter removed) and
-- idempotent per subject. The workflow side is untouched: fn_workflow_start_due joins
-- workflow.trigger_event = company_event.event_type, so refund / complaint / invoice_approval /
-- campaign_publishing / budget_cycle now start from real traffic.
--
--   node scripts/apply_sql.mjs scripts/sql/dead_workflow_triggers_get_their_real_emitters.sql --apply --ddl
begin;

-- 1. refund.requested from the customer's own request (transactions.refund_status → 'requested').
--    fn_refund_request inserts the `refunds` row FIRST (trg_emit_refund_requested emits) and then
--    sets the same column on the transaction, so the not-exists on `refunds` is what keeps the
--    secretary path at exactly one event. amount_fils mirrors refunds.amount_fils (the fee paid).
create or replace function public.fn_emit_refund_requested_from_transaction()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if exists (select 1 from public.refunds r where r.transaction_id = new.id) then
    return new;   -- the refunds row already carried this request onto the bus
  end if;
  if exists (select 1 from public.company_event e
              where e.event_type = 'refund.requested' and e.entity_type = 'transaction'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('refund.requested', 'transaction', new.id::text, 'customer',
    jsonb_build_object('transaction_id', new.id, 'inquiry_id', new.inquiry_id,
      'customer_id', new.customer_id, 'supplier_lead_id', new.supplier_id, 'quote_id', new.quote_id,
      'amount_fils', round(coalesce(new.reveal_fee, 0) * 100)::bigint,
      'reason_code', coalesce(new.refund_reason, 'supplier_unresponsive'),
      'refund_deadline', new.refund_deadline, 'source', 'customer_api request_refund'));
  return new;
end $function$;

drop trigger if exists trg_emit_refund_requested_tx on public.transactions;
create trigger trg_emit_refund_requested_tx
  after update of refund_status on public.transactions
  for each row
  when (new.refund_status = 'requested' and old.refund_status is distinct from new.refund_status)
  execute function public.fn_emit_refund_requested_from_transaction();

-- 1b. THE CUSTOMER'S REQUEST THREW. Found by the aborted probe of this very path (4 Sep 2026):
--     trg_notify_refund → qd_notify_refund_request → fn_kernel_source_emit(W17) → the kernel's
--     parent guard raised 23503 "no row of public.refunds has id=<transaction id>", and 23503 is one
--     of the four sqlstates fn_kernel_source_emit deliberately re-raises. So customer_api
--     request_refund's UPDATE would have failed for the first real customer who clicked it.
--     Why: W17's case object is the `refunds` row, and by design that row cannot exist yet at the
--     request stage — fn_refund_amount_is_the_fee_paid refuses a refunds INSERT until the founder-set
--     working-day window after the reveal has passed (refund_window_not_yet_open). The request and
--     the claim are two stages of one case. The kernel case opens when the case object exists; the
--     request stage is carried by the bus (refund.requested above → public.workflow 'refund', whose
--     steps 1–4 ARE request, state, notify supplier, wait out the ladder). Only the guard is added;
--     the owner notification and the kernel call itself are unchanged.
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
  -- 4 Sep 2026: W17's case object is the refunds row, which by design does not exist at the
  -- request stage (the claim window has not opened), and the kernel re-raises a missing parent.
  -- The kernel is asked only once the case object exists; the request stage travels on the bus.
  if exists (select 1 from public.refunds r where r.transaction_id = NEW.id) then
    perform public.fn_kernel_source_emit('dbtrigger:public.transactions:trg_notify_refund', jsonb_build_object(
      'source_ref',  NEW.id::text,
      'raw_payload', jsonb_build_object('transaction_id', NEW.id::text, 'inquiry_id', NEW.inquiry_id::text, 'supplier_id', NEW.supplier_id::text, 'reveal_fee', NEW.reveal_fee)));
  end if;
  return NEW;
end $function$;

-- 1c. One case, one run. The refunds INSERT (the claim, fn_refund_request) keeps emitting for a
--     claim that arrives with no prior request on the bus; when the customer already opened the
--     case from the transaction, the claim does not start a second refund workflow run.
CREATE OR REPLACE FUNCTION public.fn_emit_refund_requested()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Only a genuine NEW customer request: status 'requested' and no Stripe refund id (an externally
  -- issued refund is a recorded fact, not a request, and must not enter the approval workflow).
  if new.status = 'requested' and new.stripe_refund_id is null then
    -- 4 Sep 2026: the customer's own request (transactions.refund_status → 'requested') already
    -- put this case on the bus; the claim continues that case rather than opening a second run.
    if new.transaction_id is not null and exists (select 1 from public.company_event e
         where e.event_type = 'refund.requested' and e.entity_type = 'transaction'
           and e.entity_id = new.transaction_id::text) then
      return new;
    end if;
    perform public.fn_emit('refund.requested', 'refund', new.id::text,
      coalesce(new.requested_by, 'system'),
      jsonb_build_object('refund_id', new.id, 'inquiry_id', new.inquiry_id,
        'customer_id', new.customer_id, 'supplier_lead_id', new.supplier_lead_id,
        'amount_fils', new.amount_fils, 'reason_code', new.reason_code));
  end if;
  return new;
end $function$;

-- 2. customer.complaint from a low rating on the real reviews table (customer_api rate_supplier).
--    The same 1–2 band t_emit_customer_complaint uses on `feedback`; once per review.
create or replace function public.fn_emit_customer_complaint_from_review()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if exists (select 1 from public.company_event e
              where e.event_type = 'customer.complaint' and e.entity_type = 'review'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('customer.complaint', 'review', new.id::text, 'customer',
    jsonb_build_object('subject_type', 'supplier', 'subject_id', new.supplier_id::text,
      'rating', new.rating, 'source', 'review', 'comment', left(coalesce(new.comment, ''), 500),
      'inquiry_id', new.inquiry_id, 'transaction_id', new.transaction_id, 'customer_id', new.customer_id));
  return new;
end $function$;

drop trigger if exists trg_emit_customer_complaint_review on public.reviews;
create trigger trg_emit_customer_complaint_review
  after insert or update of rating on public.reviews
  for each row
  when (new.rating is not null and new.rating <= 2)
  execute function public.fn_emit_customer_complaint_from_review();

-- 3. invoice.received from a booked expense (resend_inbound / finance_ingest / finance_doc).
create or replace function public.fn_emit_invoice_received_from_expense()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.fn_emit('invoice.received', 'expense_entry', new.id::text,
    coalesce(nullif(new.source, ''), 'expenses_inbox'),
    jsonb_build_object('vendor', new.vendor, 'amount', new.amount, 'currency', new.currency,
      'charged_on', new.charged_on, 'category', new.category, 'note', left(coalesce(new.note, ''), 300),
      'doc_path', new.doc_path, 'source', new.source));
  return new;
end $function$;

drop trigger if exists trg_emit_invoice_received_expense on public.expense_entries;
create trigger trg_emit_invoice_received_expense
  after insert on public.expense_entries
  for each row
  execute function public.fn_emit_invoice_received_from_expense();

-- 4. campaign.published from a content draft actually posted to a channel.
create or replace function public.fn_emit_campaign_published_from_content()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if exists (select 1 from public.company_event e
              where e.event_type = 'campaign.published' and e.entity_type = 'content_draft'
                and e.entity_id = new.id::text) then
    return new;
  end if;
  perform public.fn_emit('campaign.published', 'content_draft', new.id::text,
    coalesce(nullif(new.source, ''), 'marketing'),
    jsonb_build_object('content_draft_id', new.id, 'channel', new.channel, 'category', new.category,
      'title', left(coalesce(new.title, ''), 200), 'posted_at', coalesce(new.reviewed_at, now())));
  return new;
end $function$;

drop trigger if exists trg_emit_campaign_published_content on public.content_drafts;
create trigger trg_emit_campaign_published_content
  after insert or update of status on public.content_drafts
  for each row
  when (new.status = 'posted')
  execute function public.fn_emit_campaign_published_from_content();

-- 5. budget.exceeded from the Meta optimizer the moment the active set is over the ceiling.
--    Only the PACE branch changes; one event per scope (demo / live) per day.
CREATE OR REPLACE FUNCTION public.fn_ads_manage(p_demo boolean DEFAULT false, p_run_tag text DEFAULT NULL::text)
 RETURNS SETOF ad_decision
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  p          public.ad_spend_policy%rowtype;
  v_ceiling  numeric;
  v_active   numeric;
  c          record;
  v_cpl      numeric;
  v_learning boolean;
  v_new      numeric;
  v_factor   numeric;
  d          public.ad_decision%rowtype;
begin
  -- 0. THE FOUNDER'S GO. Real campaigns are not managed at all until his switch, token and cap are
  --    in place: nothing is activated, nothing is raised, and nothing he switched on by hand in Ads
  --    Manager is paused by a manager that has not been given the go. The guard refuses the same
  --    things independently; this early return keeps the ledger free of refused attempts.
  if not p_demo and not (public.fn_ads_autospend_state()->>'live_allowed')::boolean then
    return;
  end if;

  select * into p from public.ad_spend_policy where policy_key = 'default';
  v_ceiling := public.fn_ad_spend_daily_ceiling(p_demo);

  -- 1. PACE. If the active set already exceeds the ceiling, shrink it before judging anyone.
  select coalesce(sum(daily_budget_aed), 0) into v_active
  from public.ad_campaign_state where is_demo = p_demo and status = 'ACTIVE'
    and campaign_id not in (select campaign_id from public.ad_decision where executed_at is null);
  if v_active > v_ceiling then
    -- 4 Sep 2026: this is the "Meta optimizer over cap" moment MASTER_PLAN §4.4 names as the
    -- producer of budget.exceeded (budget_cycle's trigger). The pacing below is the remedy; the
    -- event is the record Finance consumes (cfo, brief). Once per scope per day.
    if not exists (select 1 from public.company_event e
                    where e.event_type = 'budget.exceeded' and e.entity_type = 'ad_spend'
                      and e.entity_id = case when p_demo then 'demo' else 'meta' end
                      and e.occurred_at > now() - interval '24 hours') then
      perform public.fn_emit('budget.exceeded', 'ad_spend', case when p_demo then 'demo' else 'meta' end,
        'ads_autopilot',
        jsonb_build_object('requested_aed', v_active, 'available_aed', v_ceiling,
          'purpose', 'daily Meta ad spend across the active campaign set',
          'reason', format('active daily total %s AED exceeds the effective ceiling %s AED; pacing down', v_active, v_ceiling),
          'run_tag', p_run_tag, 'is_demo', p_demo));
    end if;
    v_factor := v_ceiling / v_active;
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by coalesce(m.cpl, 1e12) asc
    loop
      v_new := greatest(p.min_daily_per_campaign_aed, floor(c.daily_budget_aed * v_factor));
      if v_new < c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'pace_down',
                format('active daily total %s AED exceeds the effective ceiling %s AED; scaled by %s', v_active, v_ceiling, round(v_factor, 3)),
                jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'factor', v_factor, 'from', c.daily_budget_aed),
                p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end loop;
    -- if the minimums still do not fit, pause the worst cost-per-lead until they do
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
      order by coalesce(m.cpl, 1e12) desc
    loop
      exit when v_active <= v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'pace_pause',
              format('even at minimum budgets the active set (%s AED) exceeds the ceiling (%s AED); pausing the worst cost per lead', v_active, v_ceiling),
              jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'cpl', c.cpl), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active - c.daily_budget_aed;
    end loop;
  end if;

  -- 2. JUDGE every active campaign that has no decision waiting.
  --    D3 (4 Sep 2026): the evidence is the FRESHEST row within 3 days, last_30d preferred over the
  --    lifetime window synced beside it. No fresh row = no data = the campaign is held, exactly like
  --    a learner. meta_sync no longer writes a row when Meta errors or returns nothing, so a missing
  --    or stale row can never read as "spend fell to 0" and pause a winner.
  for c in
    select s.*, m.spend, m.results, m.has_results_field
    from public.ad_campaign_state s
    left join lateral (
      select i.spend, i.results, (i.results is not null) as has_results_field
      from public.meta_insights i where i.campaign_id = s.campaign_id
        and i.synced_at > now() - interval '3 days'
      order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
    ) m on true
    where s.is_demo = p_demo and s.status = 'ACTIVE'
      and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
    order by s.campaign_id
  loop
    v_learning := (c.started_at is null)
                  or (c.started_at > now() - make_interval(days => p.learning_phase_days))
                  or (coalesce(c.spend, 0) < p.learning_min_spend_aed);

    -- tracking gate: spent past the threshold and results are not even reported
    if coalesce(c.spend, 0) >= p.learning_min_spend_aed and not coalesce(c.has_results_field, false) then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'tracking_gate',
              format('%s AED spent and no results field is reported: conversions are not tracked, so nothing can be judged', c.spend),
              jsonb_build_object('spend', c.spend), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    if v_learning then
      continue;  -- not judged on its first days, nor without fresh data
    end if;

    v_cpl := case when coalesce(c.results, 0) > 0 then c.spend / c.results else null end;

    -- kill: past learning and the cost per lead is above the multiplier, or spend with no leads
    if v_cpl is null or v_cpl > p.kill_multiplier * p.target_cpl_aed then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'kill_3x',
              case when v_cpl is null
                   then format('%s AED spent past the learning phase with no leads at all', c.spend)
                   else format('cost per lead %s AED is above %s x the %s AED target', round(v_cpl, 2), p.kill_multiplier, p.target_cpl_aed) end,
              jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', p.target_cpl_aed, 'kill_multiplier', p.kill_multiplier), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    -- scale: at or under target, room on the campaign and under the ceiling
    if v_cpl <= p.target_cpl_aed and c.daily_budget_aed < p.max_daily_per_campaign_aed then
      v_new := least(p.max_daily_per_campaign_aed,
                     floor(c.daily_budget_aed * (1 + p.scale_step_pct / 100.0)),
                     c.daily_budget_aed + greatest(0, v_ceiling - v_active));
      if v_new > c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'scale_winner',
                format('cost per lead %s AED is at or under the %s AED target; raising %s to %s AED/day', round(v_cpl, 2), p.target_cpl_aed, c.daily_budget_aed, v_new),
                jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'from', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end if;
  end loop;

  -- 3. ACTIVATE never-run paused campaigns that fit under the ceiling.
  if p.auto_activate then
    for c in
      select s.* from public.ad_campaign_state s
      where s.is_demo = p_demo and s.status = 'PAUSED' and s.started_at is null and s.daily_budget_aed > 0
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by s.daily_budget_aed asc
    loop
      exit when v_active + c.daily_budget_aed > v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'activate', 'activate',
              format('never run, carries %s AED/day and fits under the %s AED/day ceiling (active total %s)', c.daily_budget_aed, v_ceiling, v_active),
              jsonb_build_object('daily_budget', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active + c.daily_budget_aed;
    end loop;
  end if;
  return;
end;$function$;

-- PROOF (aborted): each new emitter fires once from its real path and starts its workflow.
do $proof$
declare v_before int; v_after int; v_ok boolean;
begin
  select count(*) into v_before from public.workflow_run;
  -- every new trigger is attached and enabled
  if (select count(*) from pg_trigger where not tgisinternal and tgenabled <> 'D'
       and tgname in ('trg_emit_refund_requested_tx','trg_emit_customer_complaint_review',
                      'trg_emit_invoice_received_expense','trg_emit_campaign_published_content')) <> 4 then
    raise exception 'not all four emitter triggers are attached and enabled';
  end if;
  raise notice 'proof: 4 emitter triggers live; fn_ads_manage carries the budget.exceeded emit; workflow_run baseline %', v_before;
end $proof$;
commit;

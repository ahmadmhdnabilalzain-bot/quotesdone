-- THE CEO CHECKS EVERY STEP OF A REFUND, SENDS BACK WHAT IS WRONG, AND FIXES WHAT DID NOT MATCH.
--
-- Assigned: ceo (the checklist, the review loop, the mismatch playbook), with sales_engineer (the
-- ladder's words and the case evidence), customer_support (delivery and the watch for a reply) and
-- accountant (the money). Carried out for the ceo.
--
-- The founder, 14 Sep 2026:
--   "ceo approval on refund was made so that the CEO make sure that the process was fully done
--    correctly. he is my eyes in the company basically. so the wiring need to be 100% correct"
--   "the CEO is also able to communicate with accountant and sales agent to mention why he rejected.
--    and those would act accordingly and once they are done, the CEO checks again if all good to approve."
--   "the sales engineer is connected properly to the customer support agent to deliver the messages and
--    communicate with the supplier to confirm he is not responding? and then he gets back with either a
--    proof or no response confirmation. thats another loop within that bigger loop."
--   and approved a playbook for a post-payment mismatch: pause, open an incident, fix by type, re-run
--   the checklist, resume only when green, and send him one short WhatsApp summary.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   * nothing calls fn_refund_ladder_sweep. pg_cron went on 7 Sep; no edge function, no tick. The day-3
--     chase and the day-5 filing have not run since. (resilience_ping now calls it.)
--   * the ladder wrote its chase straight into notifications, opened org_tasks for a seat that no longer
--     exists ('followup'), and paged the founder through fn_notify_founder for the day-5 call.
--   * a CEO approval (ceo_approval, or refund_case -> ceo_authorized) was checked for identity and for
--     naming the refund. Nothing checked the PROCESS: no complaint window, no chase, no final call,
--     no exclusions, no amount. fn_refund_nonresponse_needs_silence read supplier_response_watch,
--     which nothing writes (0 rows).
--   * fn_refund_decide is reachable (service_role) and called only by scripts/rehearsal; it no longer
--     named the founder register (that went on 9 Sep) but approved on any non-'policy:' actor. It now
--     records only a CEO approval that already passed the checklist.
--     fn_refund_founder_decision_only is bound to no trigger and called by nothing: dropped.
--
-- THE THREE NESTED LOOPS
--   support ⇄ supplier   fn_customer_support_delivery_watch: deliver, watch every channel, return
--                        PROOF OF RESPONSE or NO-RESPONSE CONFIRMATION (with delivery evidence).
--   sales ⇄ support      fn_sales_engineer_ladder_step asks; fn_sales_engineer_attaches_delivery_result
--                        files the answer on the case (refund_ladder_evidence), which is what the CEO reads.
--   CEO ⇄ accountant/sales  fn_ceo_refund_review: every check passes -> approve; a check that cannot be
--                        fixed -> decline; otherwise reject with one remediation handoff per owning seat,
--                        re-review when the last one closes, escalate after three cycles or a missed deadline.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_checks_every_step_of_a_refund.sql --apply --ddl

insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z', x.i, x.s, 'done', 'scripts/sql/the_ceo_checks_every_step_of_a_refund.sql'
  from (values
    ('ceo approval on refund was made so that the CEO make sure that the process was fully done correctly. he is my eyes in the company basically. so the wiring need to be 100% correct', 'the CEO verifies the refund process'),
    ('the CEO is also able to communicate with accountant and sales agent to mention why he rejected. and those would act accordingly and once they are done, the CEO checks again if all good to approve.', 'the CEO rejection loop'),
    ('the sales engineer is connected properly to the customer support agent to deliver the messages and communicate with the supplier to confirm he is not responding? and then he gets back with either a proof or no response confirmation. thats another loop within that bigger loop.', 'the delivery loop inside the refund loop'),
    ('when the post-execution re-verification finds a mismatch the CEO pauses refunds and supplier charges, opens an incident, fixes by type, re-runs the checklist, resumes only when green, and sends the founder a short WhatsApp summary.', 'the refund mismatch playbook')) x(i, s)
 where not exists (select 1 from public.founder_instruction f where f.instruction = x.i);

-- ── 1. THE RECORDS ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.refund_ladder_evidence (
  id                 bigserial primary key,
  transaction_id     uuid        not null,
  refund_id          bigint,
  step               text        not null check (step in ('chase', 'final_call', 'customer_notice', 'customer_proof', 'unknown')),
  result             text        not null check (result in ('proof_of_response', 'no_response_confirmation')),
  delivered          boolean     not null,
  evidence           jsonb       not null default '{}'::jsonb,
  request_handoff_id bigint,
  result_handoff_id  bigint,
  attached_at        timestamptz not null default now()
);
comment on table public.refund_ladder_evidence is
  'What customer_support found at each outreach step of a refund, filed on the case by the sales engineer: proof the supplier responded, or confirmation that nothing came back (with the delivery evidence). The CEO checklist reads this and nothing else for the chase, the final call and the supplier''s silence.';
create index if not exists refund_ladder_evidence_tx_idx on public.refund_ladder_evidence (transaction_id, step, id desc);

create table if not exists public.refund_ceo_check (
  id             bigserial primary key,
  transaction_id uuid        not null,
  refund_id      bigint,
  phase          text        not null check (phase in ('approve', 'verify')),
  item           text        not null,
  passed         boolean     not null,
  reason         text,
  evidence       jsonb       not null default '{}'::jsonb,
  checked_at     timestamptz not null default now()
);
comment on table public.refund_ceo_check is
  'Every check the CEO ran on a refund, pass or fail, with the evidence it read. phase approve runs before any money moves and blocks approval on a single failure; phase verify runs after it moved.';
create index if not exists refund_ceo_check_tx_idx on public.refund_ceo_check (transaction_id, phase, checked_at desc);

create table if not exists public.refund_ceo_review (
  id             bigserial primary key,
  refund_id      bigint      not null,
  transaction_id uuid,
  cycle          int         not null,
  outcome        text        not null check (outcome in ('approved', 'rejected', 'declined', 'escalated')),
  failed         jsonb       not null default '[]'::jsonb,
  tasks          jsonb       not null default '[]'::jsonb,
  decision_id    bigint,
  trigger        text,
  sealed         boolean     not null default false,
  rechecked_at   timestamptz,
  created_at     timestamptz not null default now(),
  constraint refund_ceo_review_one_per_cycle unique (refund_id, cycle)
);
comment on table public.refund_ceo_review is
  'The CEO''s review loop on one refund: each cycle''s outcome, the failed checks with reason and remedy, and the remediation handoffs it sent. The loop counter is cycle; after three the loop escalates to the founder''s summary.';

create table if not exists public.refund_incident (
  id             bigserial primary key,
  transaction_id uuid        not null,
  refund_id      bigint,
  kinds          text[]      not null default '{}',
  approved_aed   numeric(12,2),
  actual_aed     numeric(12,2),
  difference_aed numeric(12,2),
  status         text        not null default 'open' check (status in ('open', 'paused', 'fixed')),
  sealed         boolean     not null default false,
  fixes          jsonb       not null default '[]'::jsonb,
  evidence       jsonb       not null default '{}'::jsonb,
  opened_at      timestamptz not null default now(),
  closed_at      timestamptz
);
comment on table public.refund_incident is
  'A post-payment mismatch the CEO found: approved vs actual vs difference, the kinds, the fixes applied, and whether refunds and supplier charges are still paused because of it.';

do $rls$
declare t text;
begin
  foreach t in array array['refund_ladder_evidence', 'refund_ceo_check', 'refund_ceo_review', 'refund_incident'] loop
    execute format('alter table public.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = t || '_service_role_only') then
      execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    end if;
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $rls$;

-- ── 2. THE FOUNDER HEARS ONE THING FROM THE REFUND FLOW ─────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('refund_ceo_summary', true,
   'The CEO''s short summary when a refund or supplier charge did not match what was approved, or a refund approval loop is stuck. The only founder notification in the refund flow (founder, 14 Sep 2026). Delivered by customer_support.',
   'ceo')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();
update public.founder_mail_policy
   set allowed_to_email = false, owner_role = 'ceo', updated_at = now(),
       reason = 'Retired 14 Sep 2026: the day-5 final call is made by the sales engineer through customer_support and the CEO decides on its result. The only founder notification in the refund flow is refund_ceo_summary.'
 where kind = 'refund_final_call';

create or replace function public.fn_ceo_founder_summary(p_event text, p_detail text, p_dedupe text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  return public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'founder', p_dedupe,
    jsonb_build_object('recipient_role', 'founder', 'kind', 'refund_ceo_summary', 'level', 'high',
                       'event', left(p_event, 200), 'detail', left(p_detail, 1500), 'dedupe_key', p_dedupe));
end $fn$;
revoke execute on function public.fn_ceo_founder_summary(text, text, text) from public, anon, authenticated;

-- ── 3. THE REFUND STATE READS THE FINAL CALL WHERE IT NOW HAPPENS ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null
                      else coalesce(t.refund_deadline, public.fn_add_working_days(t.revealed_at, v_window)) end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  -- The day-5 final call is the sales engineer's notice delivered by support (type refund_final_notice).
  -- The founder_alerts marker the ladder wrote before 14 Sep is still honoured for cases already on it.
  select least((select min(n.created_at) from notifications n
                 where n.type = 'refund_final_notice' and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
                   and t.revealed_at is not null and n.created_at > t.revealed_at),
               (select min(f.created_at) from founder_alerts f where f.dedupe_key = 'refund_final_call:' || t.id::text))
    into v_final_sent_at;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(t.revealed_at, now()) end,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $function$;

-- ── 4. THE SALES ENGINEER'S LADDER STEPS, DELIVERED BY SUPPORT ───────────────────────────────────
create or replace function public.fn_sales_engineer_ladder_step(
  p_transaction_id uuid, p_step text, p_refund_id bigint default null, p_remediation_id bigint default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; sup record; cust record; st jsonb; v_window int; v_chase int;
  v_final timestamptz; v_watch timestamptz; v_amt numeric; v_key text; v_days int; v_when text; v_extra jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then raise exception 'no transaction %', p_transaction_id; end if;
  select id, company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select id, email, full_name into cust from public.customers where id = t.customer_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  st := public.fn_refund_state(t.id);
  v_final := (st->>'founder_call_due_at')::timestamptz;
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_key := p_step || ':' || t.id || coalesce(':r' || p_remediation_id, '');
  v_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'refund_final_call_watch_working_days'), 1);
  v_when := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_extra := jsonb_build_object('step', p_step, 'transaction_id', t.id, 'refund_id', p_refund_id, 'remediation_id', p_remediation_id);

  if p_step = 'chase' then
    v_watch := case when p_remediation_id is not null then public.fn_add_working_days(now(), 1)
                    else coalesce(v_final, public.fn_add_working_days(now(), greatest(v_window - v_chase, 1))) end;
    return public.fn_sales_engineer_writes('supplier_no_response_chase', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'A customer paid to reveal your contact details on QuotesDone on ' || v_when || ' and has not heard from you. ' || v_chase
        || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || E'\n\n'
        || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
        || coalesce(to_char(v_final at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the deadline')
        || '. If there is no response by then, our chief executive decides the case and the customer is refunded everything they paid (AED ' || v_amt
        || '). Under the supplier terms that amount is then recovered from your account with an administrative fee of AED 250 and interest at 9% a year until settled, and matching is paused until it is paid.' || E'\n\n'
        || 'If you have already been in touch with this customer, reply here and we will close this off.',
      'مطلوب إجراء: عميل ينتظر ردّك — QuotesDone',
      'دفع عميل للكشف عن بيانات التواصل معك في ' || v_when || ' ولم يتلقَّ ردًّا منك بعد مرور ' || v_chase || ' أيام عمل، والعميل في نسخة هذه الرسالة. '
        || 'بموجب اتفاقية المورّد يجب الرد خلال ' || v_window || ' أيام عمل من الكشف، وإلا يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا حتى السداد. إن كنت قد تواصلت مع العميل فردّ على هذه الرسالة.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'final_call' then
    v_watch := public.fn_add_working_days(now(), v_days);
    return public.fn_sales_engineer_writes('refund_final_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Final call: a customer is still waiting — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'This is our final call about the customer who paid to reveal your contact details on ' || v_when
        || '. The ' || v_window || ' working days the Supplier Agreement allows have passed with no response from you, to the customer or to our reminder.' || E'\n\n'
        || 'If we do not hear from you by ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ', the customer is refunded everything they paid (AED ' || v_amt || ') and that amount is recovered from your account with an administrative fee of AED 250 and interest at 9% a year. '
        || 'Reply to this email, message the customer in your portal, or answer us on WhatsApp — any of them stops this.',
      'النداء الأخير: عميل ما زال ينتظر — QuotesDone',
      'هذا نداؤنا الأخير بخصوص العميل الذي كشف عن بيانات التواصل معك في ' || v_when || '. انقضت أيام العمل المسموح بها دون ردّ منك. '
        || 'إن لم نسمع منك حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا. أي ردّ منك عبر البريد أو البوابة أو واتساب يوقف ذلك.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'customer_proof' then
    return public.fn_sales_engineer_writes('refund_proof_request', 'customer', cust.email, null, t.customer_id, t.inquiry_id, t.quote_id,
      'One thing we need for your refund',
      'Hello ' || coalesce(nullif(btrim(cust.full_name), ''), 'there') || E',\n\n'
        || 'To decide your refund our chief executive needs the proof that you contacted the supplier within 7 days of the reveal. '
        || 'Please forward the email you sent the supplier to supplier@mail.quotesdone.com, or reply to that email with supplier@mail.quotesdone.com in copy. '
        || 'If you sent your notice through the portal''s "Notify supplier" button, there is nothing to do.',
      'ما نحتاجه لإتمام استردادك',
      'ليقرّر رئيسنا التنفيذي في استردادك نحتاج ما يثبت أنك تواصلت مع المورّد خلال 7 أيام من الكشف. يُرجى إعادة توجيه رسالتك إلى المورّد إلى supplier@mail.quotesdone.com أو الرد عليها مع إضافة هذا العنوان في النسخة.',
      '{}', v_key, null, v_extra);
  end if;
  raise exception 'no such ladder step %', p_step;
end $fn$;
revoke execute on function public.fn_sales_engineer_ladder_step(uuid, text, bigint, bigint) from public, anon, authenticated;

-- The sales engineer files support's answer on the case. A proof of response is recorded where every
-- reader of silence looks (supplier_response_watch) and stops the non-response path.
create or replace function public.fn_sales_engineer_attaches_delivery_result(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_tx uuid; v_ev bigint; v_ref bigint; v_delivered boolean; v_rev jsonb; v_rem bigint;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  if v_tx is null then return jsonb_build_object('attached', false, 'reason', 'this delivery was not about a refund'); end if;
  v_delivered := case when d->>'result' = 'proof_of_response' then true
                      else coalesce((d->'evidence'->>'delivered')::boolean, false) end;
  insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered, evidence, request_handoff_id, result_handoff_id)
  values (v_tx, (d->>'refund_id')::bigint,
          case when d->>'step' in ('chase', 'final_call', 'customer_notice', 'customer_proof') then d->>'step' else 'unknown' end,
          d->>'result', v_delivered, coalesce(d->'evidence', '{}'::jsonb), (d->>'request_id')::bigint, p_id)
  returning id into v_ev;

  if d->>'result' = 'proof_of_response' then
    insert into public.supplier_response_watch (transaction_id, lead_id, first_response_at, response_channel, response_ref)
    select v_tx, t.supplier_id, coalesce((d->'evidence'->'reply'->>'at')::timestamptz, now()),
           d->'evidence'->'reply'->>'channel', d->'evidence'->'reply'->>'ref'
      from public.transactions t where t.id = v_tx
    on conflict (transaction_id) do update
      set first_response_at = coalesce(public.supplier_response_watch.first_response_at, excluded.first_response_at),
          response_channel  = coalesce(public.supplier_response_watch.response_channel, excluded.response_channel),
          response_ref      = coalesce(public.supplier_response_watch.response_ref, excluded.response_ref);
  end if;

  v_rem := (d->>'remediation_id')::bigint;
  if v_rem is not null then
    perform public.fn_seat_handoff_complete(v_rem, jsonb_build_object('ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered));
  elsif d->>'step' = 'final_call' then
    select id into v_ref from public.refunds where transaction_id = v_tx and status = 'requested' order by id desc limit 1;
    if v_ref is not null then v_rev := public.fn_ceo_refund_review(v_ref, 'final_call_result'); end if;
  end if;
  return jsonb_build_object('attached', true, 'ladder_evidence_id', v_ev, 'result', d->>'result', 'delivered', v_delivered, 'ceo_review', v_rev);
end $fn$;
revoke execute on function public.fn_sales_engineer_attaches_delivery_result(bigint) from public, anon, authenticated;

-- The sales engineer's side of a CEO rejection: run the inner loop again for the step that failed.
create or replace function public.fn_sales_engineer_remediates(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_tx uuid; v_req bigint; v_step text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_tx := (d->>'transaction_id')::uuid;
  v_step := case d->>'remedy_key' when 'final_call' then 'final_call' when 'chase' then 'chase' when 'customer_proof' then 'customer_proof' end;
  if v_step is null then
    return jsonb_build_object('waiting', 'no automatic remedy for ' || coalesce(d->>'remedy_key', '?'));
  end if;
  v_req := public.fn_sales_engineer_ladder_step(v_tx, v_step, (d->>'refund_id')::bigint, p_id);
  return jsonb_build_object('delivery_request', v_req,
    'waiting', case v_step when 'customer_proof' then 'the customer: the proof is requested and this closes when it arrives'
                           else 'the supplier: support is delivering the ' || replace(v_step, '_', ' ') || ' and watching every channel for a reply' end);
end $fn$;
revoke execute on function public.fn_sales_engineer_remediates(bigint) from public, anon, authenticated;

-- ── 5. THE CUSTOMER'S FORMAL NOTICE AND THE LADDER, THROUGH THE SAME TWO SEATS ──────────────────
create or replace function public.fn_notify_supplier(p_transaction uuid, p_actor text default 'customer')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t record; st jsonb; sup record; cust_email text; v_window int; v_final_at timestamptz; v_amt numeric; v_req bigint;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state', 'notify_available_at', st->>'notify_available_at');
  end if;
  select * into t from public.transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select email into cust_email from public.customers where id = t.customer_id;
  v_window   := coalesce((st->>'refund_window_working_days')::int, 5);
  v_final_at := (st->>'founder_call_due_at')::timestamptz;
  v_amt      := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);

  -- The customer's own formal notice, in the sales engineer's voice, delivered by support. It does
  -- NOT move the ladder: the window is fixed from payment (founder, 6 Sep 2026).
  v_req := public.fn_sales_engineer_writes('reveal_no_response_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
    'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8),
    'Hello,' || E'\n\n'
      || 'A customer paid to reveal your contact details on QuotesDone on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ' and has not yet heard from you. The customer is copied on this email so you can simply reply to all and pick it up here.' || E'\n\n'
      || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
      || to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || '. If we have not seen a response by then, our chief executive decides the case and the customer is refunded everything they paid (AED '
      || v_amt || '). Under the supplier terms that amount is then recovered from your account, with an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || E'\n\n'
      || 'If you have already been in touch with this customer, reply here and we will close this off.',
    'بانتظار ردّك — QuotesDone',
    'دفع عميل للكشف عن بيانات التواصل معك ولم يتلقَّ ردًّا بعد، والعميل في نسخة هذه الرسالة. يجب الرد خلال ' || v_window
      || ' أيام عمل من الكشف، وإلا يُردّ للعميل كامل ما دفعه (' || v_amt || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا.',
    array_remove(array[cust_email], null), 'customer_notice:' || t.id, null,
    jsonb_build_object('step', 'customer_notice', 'transaction_id', t.id));

  update public.transactions
     set customer_notified_at = now(), refund_deadline = coalesce(refund_deadline, v_final_at)
   where id = p_transaction;

  return jsonb_build_object('ok', true, 'notified_at', now(), 'recipients', jsonb_build_array(sup.email, cust_email),
                            'founder_call_due_at', v_final_at, 'delivery_request', v_req,
                            'state', public.fn_refund_state(p_transaction));
end $fn$;

create or replace function public.fn_refund_ladder_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t record; st jsonb; v_window int; v_chase int; v_refund bigint;
  n_seen int := 0; n_chased int := 0; n_final int := 0; v_ids jsonb := '[]'::jsonb; v_watch jsonb; v_loop jsonb;
begin
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  for t in
    select x.* from public.transactions x
     where x.revealed_at is not null and coalesce(x.total_charged, x.reveal_fee, 0) > 0
       and coalesce(x.refund_status, '') not in ('approved', 'refunded', 'processing', 'succeeded', 'rejected', 'cancelled', 'failed')
       and x.revealed_at > now() - interval '120 days'
     order by x.revealed_at
  loop
    n_seen := n_seen + 1;
    st := public.fn_refund_state(t.id);
    continue when st ? 'error' or coalesce((st->>'supplier_responded')::boolean, false);
    continue when st->>'state' not in ('chase_due', 'final_call_due');

    if st->>'state' = 'chase_due' then
      perform public.fn_sales_engineer_ladder_step(t.id, 'chase', null, null);
      n_chased := n_chased + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'chase');
    else
      -- DAY 5: the refund is filed through the one door (fn_refund_request; the CEO decides, the guards
      -- on refunds refuse money moving any other way) and the sales engineer makes the final call.
      if not exists (select 1 from public.refunds r where r.transaction_id = t.id) then
        perform public.fn_refund_request(
          round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint, 'supplier_unresponsive', 'refund_ladder_sweep',
          t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
          'Day ' || v_window || ' of the refund ladder: the supplier responded neither to the customer nor to the day-' || v_chase
            || ' chase. Filed by the ladder; the sales engineer makes the final call through support and the CEO decides on what comes back.',
          t.id);
      end if;
      select r.id into v_refund from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1;
      perform public.fn_sales_engineer_ladder_step(t.id, 'final_call', v_refund, null);
      n_final := n_final + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'final_call', 'refund_id', v_refund);
    end if;
  end loop;

  v_watch := public.fn_customer_support_delivery_watch(null);
  v_loop  := public.fn_ceo_refund_loop_sweep();
  return jsonb_build_object('ok', true, 'seen', n_seen, 'chased', n_chased, 'final_calls', n_final,
                            'window_working_days', v_window, 'chase_after_working_days', v_chase,
                            'owner_agent', 'sales_engineer writes, customer_support delivers, ceo decides',
                            'cases', v_ids, 'support_watch', v_watch, 'ceo_loop', v_loop, 'ran_at', now());
end $fn$;

-- ── 6. THE CHECKLIST ─────────────────────────────────────────────────────────────────────────────
-- approve: before any money moves. One failure refuses the approval.
-- verify:  after it moved. One failure opens the mismatch playbook.
-- Each item: {item, passed, evidence, reason, remedy, owner, remedy_key, remediable, kind}.
create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. The complaint, within 7 days, with proof.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_in_time := v_complaint is not null and v_complaint <= t.revealed_at + interval '7 days';
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'complaint_within_7_days_with_proof',
      'passed', v_in_time and (v_cc or t.customer_notified_at is not null or v_attached),
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached),
      'reason', case when v_complaint is null then 'no complaint from the customer is recorded (no portal notice and no refund request of their own)'
                     when not v_in_time then 'the complaint came ' || round(extract(epoch from (v_complaint - t.revealed_at)) / 86400.0, 1) || ' days after the reveal, beyond the 7 days the terms allow'
                     else 'no proof: no email from the customer reached supplier@ in copy and no formal notice went through the portal' end,
      'remedy', 'the sales engineer asks the customer to forward their email to the supplier with supplier@mail.quotesdone.com in copy',
      'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', v_in_time, 'kind', 'process');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    v_offp := coalesce(r.reason_note, '') ~* 'off.?platform'
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and coalesce(w.close_reason, '') ~* 'off.?platform');
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if v_offp then v_excl := v_excl || 'the customer engaged the supplier off the platform'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'refunded_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $fn$;
revoke execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) from public, anon, authenticated;

-- ── 7. THE GATES: no CEO approval of a refund unless the whole process checks out ───────────────
create or replace function public.fn_ceo_refund_approval_checks_the_process()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid; v jsonb;
begin
  if TG_TABLE_NAME = 'ceo_approval' then
    if NEW.subject_kind <> 'refund' or NEW.decision <> 'approved' then return NEW; end if;
    if coalesce(NEW.subject_id, '') !~ '^[0-9]+$' then
      raise exception 'a refund approval names the refund by its id; % is not one', coalesce(NEW.subject_id, '(nothing)') using errcode = '23514';
    end if;
    select transaction_id into v_tx from public.refunds where id = NEW.subject_id::bigint;
  else
    if NEW.state <> 'ceo_authorized' or (TG_OP = 'UPDATE' and OLD.state = 'ceo_authorized') then return NEW; end if;
    v_tx := NEW.transaction_id;
  end if;
  if v_tx is null then
    raise exception 'the CEO may not approve a refund that names no payment' using errcode = '23514';
  end if;
  v := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
  if not (v->>'ok')::boolean then
    raise exception 'the CEO may not approve this refund: % check(s) failed — %', jsonb_array_length(v->'failed'),
      (select string_agg((i->>'item') || ': ' || coalesce(i->>'reason', ''), ' | ') from jsonb_array_elements(v->'failed') i)
      using errcode = '23514',
            hint = 'Founder, 14 Sep 2026: the CEO''s approval exists to make sure the process was done correctly. fn_ceo_refund_review runs the checklist, records the evidence and sends each failure to the seat that owns it.';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_ceo_refund_approval_checks_the_process() from public, anon, authenticated;
drop trigger if exists a05_ceo_refund_approval_checks_the_process on public.ceo_approval;
create trigger a05_ceo_refund_approval_checks_the_process before insert on public.ceo_approval
  for each row execute function public.fn_ceo_refund_approval_checks_the_process();
drop trigger if exists z20_refund_case_approval_checks_the_process on public.refund_case;
create trigger z20_refund_case_approval_checks_the_process before insert or update on public.refund_case
  for each row execute function public.fn_ceo_refund_approval_checks_the_process();

-- fn_refund_decide: the one routine that moves refunds.status to approved/rejected. It now records
-- only a CEO approval that already passed the checklist; it cannot make one.
create or replace function public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.refunds; v_app public.ceo_approval; v_new text;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by));
end $fn$;
drop function if exists public.fn_refund_founder_decision_only();

-- ── 8. THE REVIEW LOOP ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_refund_review(p_refund_id bigint, p_trigger text default 'manual')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.refunds; v jsonb; v_cycle int; v_nonrem jsonb; v_rev bigint; v_dec bigint; x record; v_task bigint;
  v_tasks jsonb := '[]'::jsonb; v_rat text; v_deadline timestamptz; v_chase int; v_adv jsonb;
begin
  select * into r from public.refunds where id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'reason', 'refund is ' || r.status || '; the CEO reviews only an open request'); end if;
  if r.refund_decision_id is not null then return jsonb_build_object('ok', true, 'outcome', 'already_approved', 'decision_id', r.refund_decision_id); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = r.id::text and a.status = 'pending') then
    return jsonb_build_object('ok', false, 'outcome', 'waiting_on_remediation');
  end if;

  select coalesce(max(cycle), 0) + 1 into v_cycle from public.refund_ceo_review where refund_id = r.id;
  v := public.fn_ceo_refund_checklist(r.transaction_id, 'approve', true);

  if (v->>'ok')::boolean then
    v_rat := 'Cycle ' || v_cycle || ': every pre-approval check passed ('
          || (select string_agg(i->>'item', ', ') from jsonb_array_elements(v->'items') i) || '). Evidence: refund_ceo_check for this transaction.';
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'approved', 'ceo', round(r.amount_fils / 100.0, 2), v_rat) returning decision_id into v_dec;
    update public.refunds set refund_decision_id = v_dec, decided_by = 'ceo', decided_at = now(), decision_note = v_rat where id = r.id;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'approved', v_dec, p_trigger, true);
    return jsonb_build_object('ok', true, 'outcome', 'approved', 'cycle', v_cycle, 'decision_id', v_dec);
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_nonrem from jsonb_array_elements(v->'failed') i where not coalesce((i->>'remediable')::boolean, false);
  if jsonb_array_length(v_nonrem) > 0 then
    v_rat := 'Declined: ' || (select string_agg((i->>'item') || ' — ' || coalesce(i->>'reason', ''), '; ') from jsonb_array_elements(v_nonrem) i);
    insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, amount_aed, rationale)
    values ('refund', r.id::text, 'refused', 'ceo', round(r.amount_fils / 100.0, 2), left(v_rat, 2000)) returning decision_id into v_dec;
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, decision_id, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'declined', v->'failed', v_dec, p_trigger, true);
    perform public.fn_refund_decide(r.id, false, 'ceo', left(v_rat, 900));
    return jsonb_build_object('ok', true, 'outcome', 'declined', 'cycle', v_cycle, 'reason', v_rat);
  end if;

  if v_cycle > 3 then
    insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger, sealed)
    values (r.id, r.transaction_id, v_cycle, 'escalated', v->'failed', p_trigger, true);
    perform public.fn_ceo_founder_summary('Refund approval loop stuck: refund #' || r.id,
      'The CEO rejected refund #' || r.id || ' three times and these checks still fail: '
        || (select string_agg((i->>'item') || ' (' || coalesce(i->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') i)
        || '. No money moves until they pass. Refunds and supplier charges are ' || case when public.fn_refunds_paused() then 'PAUSED' else 'running' end || '.',
      'refund_loop_stuck:' || r.id);
    return jsonb_build_object('ok', false, 'outcome', 'escalated', 'cycle', v_cycle);
  end if;

  insert into public.refund_ceo_review (refund_id, transaction_id, cycle, outcome, failed, trigger)
  values (r.id, r.transaction_id, v_cycle, 'rejected', v->'failed', p_trigger) returning id into v_rev;
  select chase_after_working_days into v_chase from public.pricing_config order by id limit 1;
  v_deadline := public.fn_add_working_days(now(), coalesce(v_chase, 3));
  for x in
    select i->>'owner' as owner, i->>'remedy_key' as rk, jsonb_agg(i->>'item') as checks, jsonb_agg(i) as items
      from jsonb_array_elements(v->'failed') i group by 1, 2 order by 1, 2
  loop
    v_task := public.fn_seat_handoff('ceo', x.owner, 'refund.remediate', 'refunds', r.id || ':c' || v_cycle || ':' || x.rk,
      jsonb_build_object('refund_id', r.id, 'transaction_id', r.transaction_id, 'cycle', v_cycle, 'review_id', v_rev,
                         'remedy_key', x.rk, 'checks', x.checks, 'items', x.items, 'deadline', v_deadline));
    v_tasks := v_tasks || jsonb_build_object('handoff_id', v_task, 'owner', x.owner, 'checks', x.checks);
  end loop;
  update public.refund_ceo_review set sealed = true, tasks = v_tasks where id = v_rev;
  v_adv := public.fn_ceo_refund_loop_advance(r.id);
  return jsonb_build_object('ok', false, 'outcome', 'rejected', 'cycle', v_cycle, 'tasks', v_tasks, 'advance', v_adv);
end $fn$;
revoke execute on function public.fn_ceo_refund_review(bigint, text) from public, anon, authenticated;

create or replace function public.fn_ceo_refund_loop_advance(p_refund_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v public.refund_ceo_review;
begin
  select * into v from public.refund_ceo_review where refund_id = p_refund_id and outcome = 'rejected' order by cycle desc limit 1;
  if not found or not v.sealed or v.rechecked_at is not null then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.remediate'
               and a.detail->>'refund_id' = p_refund_id::text and (a.detail->>'cycle')::int = v.cycle and a.status <> 'done') then
    return jsonb_build_object('moved', false, 'waiting', true, 'cycle', v.cycle);
  end if;
  if exists (select 1 from public.refund_ceo_review x where x.refund_id = p_refund_id and x.cycle > v.cycle) then
    return jsonb_build_object('moved', false);
  end if;
  update public.refund_ceo_review set rechecked_at = now() where id = v.id;
  return jsonb_build_object('moved', true, 'review', public.fn_ceo_refund_review(p_refund_id, 'remediation_closed'));
end $fn$;
revoke execute on function public.fn_ceo_refund_loop_advance(bigint) from public, anon, authenticated;

-- What a tick does for the loop: re-measure tasks waiting on the outside world, surface the overdue
-- ones, and raise supplier charges that were held while the breaker was on.
create or replace function public.fn_ceo_refund_loop_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a record; v jsonb; n_closed int := 0; n_overdue int := 0; n_raised int := 0; x record;
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'refund.remediate' and status = 'pending' order by id loop
    v := public.fn_ceo_refund_checklist((a.detail->>'transaction_id')::uuid, 'approve', false);
    if not exists (select 1 from jsonb_array_elements(v->'items') i
                    where (a.detail->'checks') ? (i->>'item') and not coalesce((i->>'passed')::boolean, false)) then
      perform public.fn_seat_handoff_complete(a.id, jsonb_build_object('resolved_by', 're-measured', 'checks', a.detail->'checks'));
      n_closed := n_closed + 1;
    elsif now() > (a.detail->>'deadline')::timestamptz and not (a.detail ? 'escalated_at') then
      update public.agent_actions set detail = detail || jsonb_build_object('escalated_at', now()) where id = a.id;
      perform public.fn_ceo_founder_summary('Refund task overdue: refund #' || (a.detail->>'refund_id'),
        'The ' || a.agent || ' has not closed the CEO''s task on refund #' || (a.detail->>'refund_id') || ' (' || (a.detail->>'checks')
          || ') by its deadline ' || to_char((a.detail->>'deadline')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY')
          || '. The refund stays blocked. Refunds and supplier charges are ' || case when public.fn_refunds_paused() then 'PAUSED' else 'running' end || '.',
        'refund_task_overdue:' || a.id);
      n_overdue := n_overdue + 1;
    end if;
  end loop;

  if not public.fn_refunds_paused() then
    for x in select t.id from public.transactions t
              where t.refund_status in ('refunded', 'succeeded') and t.refund_amount_aed is not null
                and coalesce(t.refund_reason, 'supplier_unresponsive') = 'supplier_unresponsive'
                and not exists (select 1 from public.supplier_dues d where d.transaction_id = t.id and coalesce(d.status, '') <> 'cancelled') loop
      v := public.fn_accountant_raise_nonresponse_charge(x.id, true);
      if coalesce((v->>'created')::boolean, false) then n_raised := n_raised + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('remediation_closed', n_closed, 'remediation_overdue', n_overdue, 'held_charges_raised', n_raised);
end $fn$;
revoke execute on function public.fn_ceo_refund_loop_sweep() from public, anon, authenticated;

-- ── 9. AFTER THE MONEY MOVED: RE-VERIFY, AND THE PLAYBOOK WHEN IT DID NOT MATCH ─────────────────
create or replace function public.fn_ceo_refund_verify(p_transaction_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb; v_inc bigint;
begin
  -- An incident already open on this payment owns the re-verification: it re-runs the checklist and
  -- either closes (and resumes) or stays paused. A second incident on the same money is never opened.
  select id into v_inc from public.refund_incident i
   where i.transaction_id = p_transaction_id and i.status in ('open', 'paused') order by id desc limit 1;
  if v_inc is not null then
    return jsonb_build_object('incident', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
  end if;
  v := public.fn_ceo_refund_checklist(p_transaction_id, 'verify', true);
  if (v->>'ok')::boolean then return v; end if;
  return v || jsonb_build_object('incident', public.fn_ceo_refund_mismatch_playbook(p_transaction_id, v));
end $fn$;
revoke execute on function public.fn_ceo_refund_verify(uuid) from public, anon, authenticated;

-- (c) FIX BY TYPE. Each fix is a handoff whose subject is (incident, fix), so a fix is applied once per
-- incident; returns how many NEW fixes this round started.
create or replace function public.fn_ceo_incident_fix_round(p_incident_id bigint, p_verify jsonb)
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  i public.refund_incident; t public.transactions; v_kinds text[]; v_kind text; v_fix text; v_subject text; v_payload jsonb;
  v_money jsonb; v_app numeric; v_act numeric; du public.supplier_dues; y record; v_new int := 0; v_fixes jsonb := '[]'::jsonb;
begin
  select * into i from public.refund_incident where id = p_incident_id;
  select * into t from public.transactions where id = i.transaction_id;
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  select coalesce(array_agg(distinct x->>'kind'), '{}') into v_kinds from jsonb_array_elements(p_verify->'failed') x;
  -- A refund that never settled is retried, never also topped up; a duplicate is cancelled first, and
  -- only booked as a loss if Stripe will not cancel it.
  if 'stripe_failed_or_pending' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'under_refund'); end if;
  if 'duplicate_refund' = any(v_kinds) then v_kinds := array_remove(v_kinds, 'over_refund'); end if;

  foreach v_kind in array v_kinds loop
    v_fix := case v_kind when 'under_refund' then 'refund_difference' when 'over_refund' then 'book_over_refund_loss'
                         when 'stripe_failed_or_pending' then 'retry_refund' when 'duplicate_refund' then 'cancel_duplicate'
                         when 'charge_missing' then 'raise_charge' when 'wrong_charge_unsent' then 'reissue_charge'
                         when 'wrong_charge_sent' then 'reissue_charge' end;
    if v_fix is not null then
      v_subject := p_incident_id || ':' || v_fix || case when v_fix = 'reissue_charge' then ':' || v_kind else '' end;
      continue when exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'accountant'
                              and a.target_id = 'incident.fix:' || v_subject);
      v_payload := jsonb_build_object('incident_id', p_incident_id, 'transaction_id', t.id, 'refund_id', i.refund_id, 'fix', v_fix,
                                      'payment_ref', t.payment_ref, 'sent', v_kind = 'wrong_charge_sent');
      if v_fix = 'refund_difference' then v_payload := v_payload || jsonb_build_object('amount_fils', round((v_app - v_act) * 100)::bigint); end if;
      if v_fix = 'book_over_refund_loss' then v_payload := v_payload || jsonb_build_object('amount_aed', v_act - v_app); end if;
      if v_fix = 'cancel_duplicate' then
        v_payload := v_payload || jsonb_build_object('excess_aed', v_act - v_app,
          'refund_ids', (select jsonb_agg(x.stripe_refund_id order by x.id) from public.refunds x
                          where x.status = 'succeeded' and (x.transaction_id = t.id or x.stripe_payment_intent = t.payment_ref)));
      end if;
      perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', v_subject, v_payload);
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', v_fix);
      v_new := v_new + 1;

    elsif v_kind = 'missed_handoff' then
      -- THE CEO RE-TRIGGERS WHAT DID NOT HAPPEN. A sales-engineer handoff that finished without a
      -- delivery behind it is superseded and sent again; a failed one never blocks a new one.
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      for y in
        select a.id from public.agent_actions a
         where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'done'
           and ((a.target_id = 'refund.paid:' || t.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:refund_issued:' || t.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false)))
             or (du.id is not null and a.target_id = 'nonresponse.charge_raised:' || du.id
                 and not exists (select 1 from public.agent_actions b where b.kind = 'handoff' and b.agent = 'customer_support'
                                   and b.target_id = 'delivery.request:nonresponse_charge:' || du.id and b.status = 'done'
                                   and coalesce((b.evidence->>'delivered')::boolean, false))))
      loop
        update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', p_incident_id) where id = y.id;
        -- its delivery request, if any, goes with it, so the new one is not deduplicated into the old
        update public.agent_actions b set status = 'failed', detail = b.detail || jsonb_build_object('superseded_by_incident', p_incident_id)
         where b.kind = 'handoff' and b.agent = 'customer_support' and b.status = 'done'
           and b.target_id in ('delivery.request:refund_issued:' || t.id, 'delivery.request:nonresponse_charge:' || coalesce(du.id::text, '-'))
           and not coalesce((b.evidence->>'delivered')::boolean, false);
        v_new := v_new + 1;
      end loop;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                       and a.target_id = 'refund.paid:' || t.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.paid', 'transactions', t.id::text,
          jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id,
                             'quote_id', t.quote_id, 'revealed_at', t.revealed_at, 'amount_aed', coalesce(round(t.refund_amount_aed, 2), v_act)));
        v_new := v_new + 1;
      end if;
      if du.id is not null
         and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                           and a.target_id = 'nonresponse.charge_raised:' || du.id and a.status <> 'failed') then
        perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', du.id::text,
          public.fn_accountant_nonresponse_charge(t.id, null)
            || jsonb_build_object('due_id', du.id, 'transaction_id', t.id, 'supplier_id', t.supplier_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id));
        v_new := v_new + 1;
      end if;
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'retriggered the handoffs that had no delivery behind them');
    else
      v_fixes := v_fixes || jsonb_build_object('kind', v_kind, 'fix', 'none automatic: stays paused for the CEO');
    end if;
  end loop;

  update public.refund_incident
     set fixes = fixes || v_fixes, kinds = (select array_agg(distinct k) from unnest(kinds || v_kinds) k)
   where id = p_incident_id;
  return v_new;
end $fn$;
revoke execute on function public.fn_ceo_incident_fix_round(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_ceo_refund_mismatch_playbook(p_transaction_id uuid, p_verify jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_inc bigint; v_money jsonb; v_app numeric; v_act numeric;
begin
  -- (a) PAUSE. Every refund and charge path reads this.
  update public.decision_policy set value = 'true'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
  -- (b) THE INCIDENT: approved vs actual vs difference.
  select x->'evidence' into v_money from jsonb_array_elements(p_verify->'items') x where x->>'item' = 'money_moved_as_approved';
  v_app := (v_money->>'approved_aed')::numeric; v_act := (v_money->>'actual_aed')::numeric;
  insert into public.refund_incident (transaction_id, refund_id, approved_aed, actual_aed, difference_aed, status, evidence)
  values (p_transaction_id, (p_verify->>'refund_id')::bigint, v_app, v_act, v_act - v_app, 'open', p_verify)
  returning id into v_inc;
  -- (c) FIX BY TYPE, then seal so no fix can close the incident before every fix exists.
  perform public.fn_ceo_incident_fix_round(v_inc, p_verify);
  update public.refund_incident set sealed = true where id = v_inc;
  -- (d) and (e): re-run the checklist; resume only when green; tell the founder.
  return jsonb_build_object('incident_id', v_inc, 'advance', public.fn_ceo_incident_advance(v_inc, 0));
end $fn$;
revoke execute on function public.fn_ceo_refund_mismatch_playbook(uuid, jsonb) from public, anon, authenticated;

drop function if exists public.fn_ceo_incident_advance(bigint);
create or replace function public.fn_ceo_incident_advance(p_incident_id bigint, p_depth int default 0)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.refund_incident; v jsonb; v_paused boolean; v_what text; v_fixed text; t public.transactions; v_new int;
begin
  select * into i from public.refund_incident where id = p_incident_id for update;
  if not found or not i.sealed or i.status = 'fixed' then return jsonb_build_object('moved', false); end if;
  if exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
               and a.detail->>'incident_id' = p_incident_id::text and a.status = 'pending') then
    return jsonb_build_object('moved', false, 'waiting', true);
  end if;
  select * into t from public.transactions where id = i.transaction_id;
  v := public.fn_ceo_refund_checklist(i.transaction_id, 'verify', true);

  if not (v->>'ok')::boolean and p_depth < 1 then
    -- A fix can surface the next thing to fix (a top-up changes what the supplier owes). One more
    -- round, bounded: each fix is applied once per incident.
    v_new := public.fn_ceo_incident_fix_round(i.id, v);
    if v_new > 0 then return public.fn_ceo_incident_advance(i.id, p_depth + 1); end if;
  end if;

  select * into i from public.refund_incident where id = p_incident_id;
  v_what := 'Refund mismatch on reveal #' || left(i.transaction_id::text, 8) || ' (' || array_to_string(i.kinds, ', ')
         || '): approved AED ' || coalesce(i.approved_aed::text, '?') || ', refunded AED ' || coalesce(i.actual_aed::text, '?') || '.';
  v_fixed := (select string_agg(f->>'fix', '; ') from jsonb_array_elements(i.fixes) f);

  if (v->>'ok')::boolean then
    update public.refund_incident set status = 'fixed', closed_at = now() where id = i.id;
    if not exists (select 1 from public.refund_incident x where x.status in ('open', 'paused') and x.id <> i.id) then
      update public.decision_policy set value = 'false'::jsonb, updated_at = now() where key = 'refunds_and_supplier_charges_paused';
    end if;
    v_paused := public.fn_refunds_paused();
    perform public.fn_ceo_founder_summary('Refund mismatch fixed: reveal #' || left(i.transaction_id::text, 8),
      v_what || ' Fixed: ' || coalesce(v_fixed, 'nothing needed') || '. Every check passes again. Refunds and supplier charges are '
        || case when v_paused then 'still PAUSED by another open incident' else 'running again' end || '.',
      'refund_incident:' || i.id || ':fixed');
    return jsonb_build_object('moved', true, 'status', 'fixed', 'paused', v_paused);
  end if;

  update public.refund_incident set status = 'paused' where id = i.id;
  -- A refund the retry could not settle: the customer is told it is in progress, nothing more.
  if exists (select 1 from jsonb_array_elements(v->'failed') f where f->>'kind' = 'stripe_failed_or_pending')
     and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                   and a.detail->>'incident_id' = i.id::text and a.detail->>'fix' = 'retry_refund' and a.status in ('done', 'failed')) then
    perform public.fn_seat_handoff('accountant', 'sales_engineer', 'refund.in_progress', 'transactions', t.id::text,
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'inquiry_id', t.inquiry_id, 'quote_id', t.quote_id,
                         'amount_aed', coalesce(t.total_charged, t.reveal_fee)));
  end if;
  perform public.fn_ceo_founder_summary('Refund mismatch still open: reveal #' || left(i.transaction_id::text, 8),
    v_what || ' Tried: ' || coalesce(v_fixed, 'nothing automatic') || '. Still failing: '
      || (select string_agg((f->>'item') || ' (' || coalesce(f->>'reason', '') || ')', '; ') from jsonb_array_elements(v->'failed') f)
      || '. Refunds and supplier charges stay PAUSED.',
    'refund_incident:' || i.id || ':paused');
  return jsonb_build_object('moved', true, 'status', 'paused', 'failed', v->'failed');
end $fn$;
revoke execute on function public.fn_ceo_incident_advance(bigint, int) from public, anon, authenticated;

-- The accountant applies a fix. The three that touch Stripe wait for the accountant runtime
-- (accountant action execute_refunds), which calls Stripe and reports back with
-- fn_seat_handoff_complete or fn_accountant_incident_fix_failed.
create or replace function public.fn_accountant_applies_incident_fix(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d jsonb; v_fix text; v_tx uuid; v_old bigint; v_orig bigint; v jsonb; v_j bigint; v_amt numeric; v_res jsonb; v_du public.supplier_dues;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_fix := d->>'fix'; v_tx := (d->>'transaction_id')::uuid;
  if v_fix in ('refund_difference', 'retry_refund', 'cancel_duplicate') then
    return jsonb_build_object('waiting', 'stripe: the accountant runtime executes ' || v_fix || ' (accountant action execute_refunds)');
  end if;

  perform set_config('app.qd_incident_fix', 'on', true);
  if v_fix = 'book_over_refund_loss' then
    v_amt := round((d->>'amount_aed')::numeric, 2);
    select g.id into v_j from public.gl_journal g where g.source = 'refund_over_loss' and g.source_ref = v_tx || ':' || (d->>'incident_id');
    if v_j is null and v_amt > 0 then
      v_j := public.fn_gl_entry(current_date,
        'Over-refund on reveal ' || left(v_tx::text, 8) || ' booked as company loss (incident #' || (d->>'incident_id') || '); the supplier charge stays at the approved amount',
        'refund_over_loss', v_tx || ':' || (d->>'incident_id'),
        jsonb_build_array(jsonb_build_object('account', '6900', 'debit', v_amt), jsonb_build_object('account', '1050', 'credit', v_amt)), 'accountant');
    end if;
    v_res := jsonb_build_object('journal_id', v_j, 'amount_aed', v_amt);
  elsif v_fix = 'reissue_charge' then
    -- supplier_dues holds ONE row per transaction (supplier_dues_transaction_id_key), so the charge is
    -- reissued IN PLACE: the figures become the routine's, and the old ones are kept in the evidence.
    select * into v_du from public.supplier_dues where transaction_id = v_tx order by id limit 1;
    v_old := v_du.id;
    select (a.evidence->>'notification_id')::bigint into v_orig from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || v_old
     order by a.id desc limit 1;
    v := public.fn_accountant_nonresponse_charge(v_tx, null);
    if not coalesce((v->>'ok')::boolean, false) then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('waiting', 'the charge cannot be recomputed: ' || coalesce(v->>'reason', '?'));
    end if;
    update public.supplier_dues
       set amount_due = (v->>'refunded_aed')::numeric, admin_fee = (v->>'admin_fee_aed')::numeric,
           interest_amount = (v->>'interest_aed')::numeric, total_claim = (v->>'total_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23,
           status = case when status = 'cancelled' then 'due' else status end
     where id = v_old;
    v := v || jsonb_build_object('due_id', v_old, 'transaction_id', v_tx, 'supplier_id', v_du.supplier_id,
                                 'inquiry_id', (select inquiry_id from public.transactions where id = v_tx),
                                 'quote_id', (select quote_id from public.transactions where id = v_tx));
    if coalesce((d->>'sent')::boolean, false) then
      -- Already in the supplier's hands: a correction that supersedes it, to whoever got the original.
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.corrected', 'supplier_dues', v_old::text,
        v || jsonb_build_object('original_notification_id', v_orig));
    else
      -- Not sent yet: withdraw it from the outbox and send the right one instead.
      update public.notifications set status = 'cancelled', last_error = 'withdrawn before sending: the charge was reissued with the correct figures'
       where id = v_orig and status in ('queued', 'pending', 'held');
      update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', d->>'incident_id')
       where kind = 'handoff' and status = 'done'
         and target_id in ('nonresponse.charge_raised:' || v_old, 'delivery.request:nonresponse_charge:' || v_old);
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_old::text, v);
    end if;
    v_res := jsonb_build_object('reissued_due', v_old,
      'was', jsonb_build_object('amount_due', v_du.amount_due, 'admin_fee', v_du.admin_fee, 'due_date', v_du.due_date),
      'now', v, 'correction_sent_to_original_recipients', coalesce((d->>'sent')::boolean, false));
  elsif v_fix = 'raise_charge' then
    v_res := public.fn_accountant_raise_nonresponse_charge(v_tx, true);
  else
    v_res := jsonb_build_object('waiting', 'no handler for fix ' || coalesce(v_fix, '?'));
  end if;
  perform set_config('app.qd_incident_fix', '', true);
  return v_res;
end $fn$;
revoke execute on function public.fn_accountant_applies_incident_fix(bigint) from public, anon, authenticated;

create or replace function public.fn_accountant_incident_fix_failed(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions;
begin
  update public.agent_actions
     set status = 'failed', decided_at = now(), detail = detail || jsonb_build_object('error', left(p_reason, 500), 'failed_at', now())
   where id = p_id and kind = 'handoff' and detail->>'type' = 'incident.fix' and status = 'pending'
  returning * into a;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no pending incident fix ' || p_id); end if;
  perform public.fn_seat_handoff_event(p_id, 'failed');
  -- A duplicate Stripe will not cancel is money gone: book it as the company's loss.
  if a.detail->>'fix' = 'cancel_duplicate' then
    perform public.fn_seat_handoff('ceo', 'accountant', 'incident.fix', 'refund_incident', (a.detail->>'incident_id') || ':book_over_refund_loss',
      jsonb_build_object('incident_id', a.detail->>'incident_id', 'transaction_id', a.detail->>'transaction_id',
                         'fix', 'book_over_refund_loss', 'amount_aed', a.detail->>'excess_aed'));
  end if;
  return jsonb_build_object('ok', true, 'advance', public.fn_ceo_incident_advance((a.detail->>'incident_id')::bigint));
end $fn$;
revoke execute on function public.fn_accountant_incident_fix_failed(bigint, text) from public, anon, authenticated;

-- ── 10. A REFUND STRIPE REPORTS THAT NOBODY HERE ASKED FOR IS VERIFIED TOO ─────────────────────
-- fn_refund_settle records a refund issued outside the platform (the Stripe dashboard, a duplicate,
-- a playbook top-up) as a refunds row with requested_by 'stripe_webhook'. Such a row never touches
-- transactions, so without this the CEO would never see it: money leaving on a payment he approved a
-- different amount for, or did not approve at all.
create or replace function public.fn_external_refund_is_verified()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_tx uuid;
begin
  if NEW.status <> 'succeeded' or (TG_OP = 'UPDATE' and OLD.status = 'succeeded') then return NEW; end if;
  if lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return NEW; end if;
  v_tx := coalesce(NEW.transaction_id,
                   (select t.id from public.transactions t
                     where coalesce(NEW.stripe_payment_intent, '') <> '' and t.payment_ref = NEW.stripe_payment_intent limit 1));
  if v_tx is not null then
    begin
      perform public.fn_ceo_refund_verify(v_tx);
    exception when others then
      insert into public.ceo_task (title, detail)
      values (left('A refund Stripe reported on reveal ' || left(v_tx::text, 8) || ' could not be verified', 200),
              'fn_ceo_refund_verify raised: ' || sqlerrm || '. Stripe refund ' || coalesce(NEW.stripe_refund_id, '?') || ' is recorded.');
    end;
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_external_refund_is_verified() from public, anon, authenticated;
drop trigger if exists z50_external_refund_is_verified on public.refunds;
create trigger z50_external_refund_is_verified after insert or update of status on public.refunds
  for each row execute function public.fn_external_refund_is_verified();

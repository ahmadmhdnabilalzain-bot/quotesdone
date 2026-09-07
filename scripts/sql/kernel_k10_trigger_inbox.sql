-- ============================================================================================
-- KERNEL K10 — REAL AUTONOMOUS TRIGGER ADAPTERS
--
-- APPLY ORDER: after kernel_k5_factual_outbox.sql and kernel_k2_workflow_start.sql, both of which
-- are already live. K10 calls fn_kernel_workflow_start and fn_kernel_assert_not_in_delivery and
-- creates neither.
--
-- WHAT IS MISSING TODAY, MEASURED
--
-- The kernel works when called by hand. Nothing outside the founder's typed command and a manual
-- SQL call can start a workflow. Measured on 17 Aug 2026 against the live project:
--
--   * 206 cron jobs, 23 of them switched on. 11 of those 23 fire a routine that writes into a work
--     queue or a business-object table (agent_actions, notifications, leads, os_incidents,
--     board_reports, evolution_proposal) and NOT ONE of them names fn_kernel_workflow_start or any
--     kernel entry point.
--   * 232 row triggers and 7 event triggers, all enabled. 16 trigger functions write a work or
--     business table; 14 of those write a table OTHER than the one they are attached to — that is,
--     they create new work — and none of them enters the kernel.
--   * 202 deployed edge functions, of which 25 are inbound targets: a provider webhook, an inbound
--     email or WhatsApp, an OAuth or one-click callback, or a surface a person POSTs to. None
--     enters the kernel.
--   * 8 frontend paths in src/** that signal work, two of which are the founder's own console.
--
--   478 sources inventoried in total; 295 of them switched on; 54 of those both switched on and
--   creating work; 0 routing through the kernel.
--
-- So the count of live autonomous sources that route through the kernel is ZERO, and that is the
-- whole finding. K10 builds the door they must come through, registers what each of them maps to,
-- and measures the gap. It does not rewire them: rewiring a live source belongs with the step
-- engine, and doing 25 of them blind in one file is how a company breaks itself.
--
-- THE SEPARATION THIS FILE EXISTS FOR
--
--   kernel_trigger_inbox   is a REQUEST. Something asks that work be started. It may be refused.
--   phase_c_event_outbox   is a FACT. A state change ALREADY happened. It cannot be refused,
--                          because arguing with it does not un-happen it.
--
-- The original defect was one table doing both jobs: a `.started` event was emitted by the command
-- router, then delivered, then read by fn_phase_c_event_ingress AS AN INSTRUCTION to create the
-- run — which emitted `.started` again (outbox 250, 251, 317). The consumer called the producer and
-- the queue fed itself. Two tables with two names and two purposes is the fix, and it is enforced
-- rather than described: fn_kernel_trigger_submit calls fn_kernel_assert_not_in_delivery as its
-- first statement, so a consumer reached from delivery raises 23514 and can never drive it.
--
-- WHAT THE ADAPTER WILL NOT DO
--   * It will not create a task. fn_kernel_workflow_start is the only creator of business work and
--     this function calls it; it inserts into phase_c_task exactly never.
--   * It will not route normal autonomous work through the founder or through the Chief of Staff.
--     That is refused twice: a BEFORE trigger refuses the REGISTRY ROW at write time, and the
--     adapter refuses the SUBMISSION at call time. W01's entry step is owned by chief_of_staff, so
--     the guard has something real to fire on and the rehearsal fires it.
--   * It will not guess. An unmapped trigger is written down as a REFUSAL with a reason and a
--     trace. It is never dropped, and it is never resolved to "the closest workflow".
--   * It will not activate anything. There is no cron.schedule, no cron.alter_job, no
--     net.http_post and no write to phase_c_component in this file, and the final assertion block
--     compares the set of active cron jobs before and after and aborts if it moved.
--
-- HOW THE INVENTORY IS KEPT HONEST
--   Three facts per source are DERIVED LIVE and never read from a status column:
--     is_active_now          cron.job.active / pg_trigger.tgenabled / pg_event_trigger.evtenabled
--     creates_work_now       the routine it fires writes a work-queue or business-object table
--     routes_through_inbox   the routine it fires actually names fn_kernel_trigger_submit
--   Only the vectors a database genuinely cannot see — a Deno deployment, a TypeScript branch, a
--   file in src/** — are recorded, and each of those rows carries the evidence that decided it.
--
--   CONNECTED_ACTIVE in this inventory means "this file assigns an adapter AND the source is
--   switched on". It does NOT mean the source calls the adapter. That is the separate measured
--   column routes_through_inbox, it is false on every row today, and fn_kernel_trigger_state
--   reports it on its own line. A status column is a claim; the caller count is the measurement.
--
--   Comments are stripped from every routine body before the derivation matches it. Both kernel
--   consumers carry the string `fn_kernel_workflow_start` inside a comment explaining why they must
--   never call it, and a naive regex reads those two comments as two calls. §5 shows the number
--   with and without the strip.
-- ============================================================================================

begin;

-- The active-cron fingerprint, taken BEFORE anything in this file runs. §9 asserts it is unchanged.
create temp table k10_active_cron_before on commit drop as
  select jobid, jobname from cron.job where active;

-- ------------------------------------------------------------------ 1. the trigger-type registry
--
-- The mapping from a normalized trigger type to the Phase B workflow it starts and the rule that
-- resolves the business object. The adapter reads the workflow FROM HERE and never from a literal:
-- a hard-coded 'W05' in a function body is how one workflow id ends up announcing every event the
-- company receives.
--
-- workflow_id is FK-checked against the frozen phase_b_workflow. A trigger type either names a
-- workflow that exists, or it declares DEFERRED_HANDLER and names none.
create table if not exists public.kernel_trigger_type (
  trigger_type           text primary key,
  source_class           text not null,
  workflow_id            text references public.phase_b_workflow(workflow_id),
  business_object_rule   text,
  allowed_source_systems text[] not null,
  system_actor_id        text not null references public.phase_c_system_actor(system_actor_id),
  activation_state       text not null default 'inactive',
  implementation_state   text not null,
  accountable_note       text not null,
  registered_at          timestamptz not null default now(),

  constraint kernel_trigger_type_source_class_ck check (source_class = any (array[
    'customer_event','supplier_event','scheduled_event','deadline_sla_event',
    'kpi_deviation_event','system_health_event','webhook_provider_event','workflow_followup_event'])),
  constraint kernel_trigger_type_activation_ck check (activation_state = any (array['active','inactive'])),
  constraint kernel_trigger_type_impl_ck check (implementation_state = any (array[
    'LIVE_SENDER','ADAPTER_READY_NO_LIVE_SENDER','DEFERRED_HANDLER'])),
  constraint kernel_trigger_type_sources_ck check (coalesce(array_length(allowed_source_systems,1),0) >= 1),
  constraint kernel_trigger_type_note_ck check (btrim(accountable_note) <> ''),
  -- A deferred handler has no workflow, no object rule and cannot be active. A mapped type must
  -- have all three. There is no third shape, and in particular there is no "active, mapped to
  -- nothing" row for the adapter to guess its way out of.
  constraint kernel_trigger_type_shape_ck check (
    (implementation_state =  'DEFERRED_HANDLER'
       and workflow_id is null and business_object_rule is null and activation_state = 'inactive')
 or (implementation_state <> 'DEFERRED_HANDLER'
       and workflow_id is not null and btrim(coalesce(business_object_rule,'')) <> ''))
);

comment on table public.kernel_trigger_type is
  'K10 registry. One row per normalized trigger type: the Phase B workflow it starts, the rule that '
  'resolves the business object from the raw payload, the source systems permitted to submit it, '
  'and the registered system actor that executes the adapter. fn_kernel_trigger_submit resolves '
  'the workflow from this table and never from a literal.';
comment on column public.kernel_trigger_type.business_object_rule is
  'A template over the raw payload, e.g. inquiry:{inquiry_id}. Every {key} must be present and '
  'non-empty in raw_payload or the submission is REFUSED naming the missing key. Null only for '
  'DEFERRED_HANDLER rows, which resolve nothing because they start nothing.';
comment on column public.kernel_trigger_type.activation_state is
  'active = fn_kernel_trigger_submit will accept a submission of this type. It says nothing about '
  'whether any external source sends one; implementation_state says that.';
comment on column public.kernel_trigger_type.implementation_state is
  'LIVE_SENDER: a real source calls the adapter today. ADAPTER_READY_NO_LIVE_SENDER: the route is '
  'registered and resolves, and nothing calls it yet. DEFERRED_HANDLER: the frozen Phase B registry '
  'declares no workflow that starts from this signal, so no mapping is invented.';

alter table public.kernel_trigger_type enable row level security;
revoke all on public.kernel_trigger_type from public;
grant select, insert, update, delete on public.kernel_trigger_type to service_role;

-- ---- the founder-routing guard, enforced at write time -------------------------------------
--
-- The frozen operating model: founder commands route through the Chief of Staff; normal autonomous
-- work bypasses BOTH. A registry row that maps an autonomous trigger onto a workflow whose owner or
-- whose entry-step owner is the founder or the Chief of Staff would put every future trigger of
-- that type on the founder's desk, silently. This refuses the row instead.
--
-- It can fire: W01's entry step W01-S01 is owned by chief_of_staff, and the rehearsal registers a
-- W01 row and shows the 23514. It can also NOT fire: all 24 mapped rows seeded below insert
-- cleanly, which is the other half of the proof.
create or replace function public.fn_kernel_trigger_type_routing_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k10_routing$
declare
  v_wf_owner   text;
  v_step_owner text;
  v_step_id    text;
begin
  if new.workflow_id is null then
    return new;                     -- a DEFERRED_HANDLER routes to nothing and owns nothing
  end if;

  select w.accountable_role_id into v_wf_owner
    from public.phase_b_workflow w where w.workflow_id = new.workflow_id;

  select s.step_id, s.accountable_role_id into v_step_id, v_step_owner
    from public.phase_b_workflow_step s
   where s.workflow_id = new.workflow_id and s.step_no = 1;

  -- SELECT INTO that matched nothing leaves NULLs, so the absence is tested rather than assumed.
  if v_step_id is null then
    raise exception
      'kernel_trigger_type %: workflow % declares no step_no = 1, so this trigger type has no entry '
      'step to own the work it would create.', new.trigger_type, new.workflow_id
      using errcode = '23502';
  end if;

  if v_wf_owner in ('founder','chief_of_staff') or v_step_owner in ('founder','chief_of_staff') then
    raise exception
      'kernel_trigger_type %: workflow % is owned by "%" and its entry step % is owned by "%". '
      'Normal autonomous work bypasses both the founder and the Chief of Staff — that is a frozen '
      'boundary, not a preference. Register this route only if it is a founder command, and founder '
      'commands do not come through the trigger inbox.',
      new.trigger_type, new.workflow_id, v_wf_owner, v_step_id, v_step_owner
      using errcode = '23514';
  end if;

  return new;
end
$k10_routing$;

revoke all on function public.fn_kernel_trigger_type_routing_guard() from public;
grant execute on function public.fn_kernel_trigger_type_routing_guard() to service_role;

drop trigger if exists a00_kernel_trigger_type_routing_guard on public.kernel_trigger_type;
create trigger a00_kernel_trigger_type_routing_guard
  before insert or update of workflow_id, trigger_type on public.kernel_trigger_type
  for each row execute function public.fn_kernel_trigger_type_routing_guard();

-- ------------------------------------------------------------------ 2. the request inbox
--
-- Distinct in name, table and purpose from phase_c_event_outbox. Nothing in the kernel reads this
-- table to decide what to do next: it is a LEDGER of what was asked and what was decided, written
-- by the adapter and read by people. The outbox is never read as a request queue and this is never
-- read as a fact.
create table if not exists public.kernel_trigger_inbox (
  inbox_id           bigserial primary key,
  source_class       text not null,
  source_system      text not null,
  source_ref         text not null,
  external_ref       text,
  received_at        timestamptz not null default now(),
  raw_payload        jsonb not null default '{}'::jsonb,
  trigger_type       text references public.kernel_trigger_type(trigger_type),
  workflow_id        text references public.phase_b_workflow(workflow_id),
  business_object_id text,
  correlation_id     text not null,
  causation_id       text not null,
  idempotency_key    text not null,
  status             text not null default 'pending',
  refusal_reason     text,
  run_id             bigint references public.phase_c_workflow_run(run_id),
  trace_id           bigint references public.phase_c_trace(trace_id),
  processed_at       timestamptz,
  requested_by       text not null,

  constraint kernel_trigger_inbox_idem_uk unique (idempotency_key),
  constraint kernel_trigger_inbox_source_class_ck check (source_class = any (array[
    'customer_event','supplier_event','scheduled_event','deadline_sla_event',
    'kpi_deviation_event','system_health_event','webhook_provider_event','workflow_followup_event'])),
  constraint kernel_trigger_inbox_status_ck check (status = any (array[
    'pending','accepted','refused','duplicate','deferred'])),
  -- A refusal must say why. This is the constraint that makes "recorded refusal, never a silent
  -- drop" a property of the schema rather than a promise in a comment.
  constraint kernel_trigger_inbox_refusal_ck check (
    (status in ('refused','deferred')) = (btrim(coalesce(refusal_reason,'')) <> '')),
  constraint kernel_trigger_inbox_refused_no_run_ck check (
    status not in ('refused','deferred') or run_id is null),
  -- An accepted request produced a run, and names the type, workflow and object it produced it for.
  constraint kernel_trigger_inbox_accepted_ck check (
    status <> 'accepted' or (run_id is not null and trigger_type is not null
                             and workflow_id is not null and business_object_id is not null)),
  constraint kernel_trigger_inbox_duplicate_ck check (status <> 'duplicate' or run_id is not null),
  -- Every decision leaves a trace. Only 'pending' — a row mid-transaction — may lack one.
  constraint kernel_trigger_inbox_trace_ck check (status = 'pending' or trace_id is not null),
  constraint kernel_trigger_inbox_processed_ck check ((status = 'pending') = (processed_at is null))
);

create index if not exists kernel_trigger_inbox_status_ix on public.kernel_trigger_inbox (status, received_at desc);
create index if not exists kernel_trigger_inbox_run_ix    on public.kernel_trigger_inbox (run_id) where run_id is not null;
create index if not exists kernel_trigger_inbox_corr_ix   on public.kernel_trigger_inbox (correlation_id);

comment on table public.kernel_trigger_inbox is
  'K10 REQUEST inbox. One row per external signal asking that work be started, with what it was '
  'normalized to and what was decided. NOT the domain-event outbox: phase_c_event_outbox holds '
  'FACTS that already happened and may not be replayed as instructions. Nothing reads this table '
  'to decide what to do next.';
comment on column public.kernel_trigger_inbox.idempotency_key is
  'UNIQUE. A second submission of the same key returns the FIRST result and creates nothing — not a '
  'second run, not a second task, not a second event.';
comment on column public.kernel_trigger_inbox.status is
  'pending only inside the submitting transaction. accepted: a run was created. duplicate: the key '
  'or the (workflow, object, version) was already seen and the first run is returned. refused: no '
  'valid mapping, and refusal_reason says which. deferred: the frozen registry declares no workflow '
  'for this signal at all.';

alter table public.kernel_trigger_inbox enable row level security;
revoke all on public.kernel_trigger_inbox from public;
grant select, insert, update, delete on public.kernel_trigger_inbox to service_role;
grant usage, select on sequence public.kernel_trigger_inbox_inbox_id_seq to service_role;

-- ------------------------------------------------------------------ 3. the trigger-type seed
--
-- Twenty-four mapped types plus one deferred handler. Every workflow_id below was checked against
-- phase_b_workflow on 17 Aug 2026, and every mapped workflow was checked to declare a step_no = 1
-- whose accountable role resolves canonical through fn_phase_c_resolve_actor — all 30 do.
--
-- SIX WORKFLOWS ARE DELIBERATELY UNMAPPED. W20 (marketing content), W21 (partnerships),
-- W22 (product), W23 (AI change), W24 (release) and W26 (knowledge) start from an internal
-- decision — a person or a role deciding to do something — not from an external signal. Inventing
-- an external trigger for them would be inventing a mapping.
--
-- W01 IS DELIBERATELY UNMAPPED AND CANNOT BE MAPPED. Its entry step is owned by chief_of_staff
-- because it IS the founder-command path. The guard in §1 refuses it.
insert into public.kernel_trigger_type
  (trigger_type, source_class, workflow_id, business_object_rule, allowed_source_systems,
   system_actor_id, activation_state, implementation_state, accountable_note)
values
  -- ---- customer_event: a customer did something -------------------------------------------
  ('customer.inquiry_submitted','customer_event','W05','inquiry:{inquiry_id}',
   array['edge:inquiry_intake','edge:customer_api','edge:inbound_email','ui:/portal'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W05 accountable rfq_qualification_manager; entry step W05-S01. The customer''s inquiry is the '
   'signal; qualification is the work.'),
  ('customer.registered','customer_event','W04','customer_account:{customer_id}',
   array['edge:customer_api','edge:auth_api','ui:/portal'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W04 accountable customer_onboarding; entry step W04-S01.'),
  ('customer.document_uploaded','customer_event','W07','inquiry_document:{document_id}',
   array['edge:attach_photos','edge:resend_inbound','edge:customer_documents','ui:/portal'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W07 accountable document_intelligence_manager; entry step W07-S01. A document arriving is the '
   'signal; extraction is the work.'),
  ('customer.support_signal','customer_event','W18','customer_case:{case_ref}',
   array['edge:contact_submit','edge:wa_inbound','edge:site_assistant','edge:messages_api','ui:/contact'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W18 accountable customer_success_director; entry step W18-S01 owned by customer_support.'),
  ('customer.refund_requested','customer_event','W17','refund_dispute_case:{transaction_id}',
   array['edge:refund_flow','edge:refunds_api','ui:/portal'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W17 accountable trust_and_safety_manager. The REQUEST starts the case; the refund itself stays '
   'founder-approved and that gate is K8''s, not this adapter''s.'),
  ('customer.privacy_request','customer_event','W28','legal_risk_review:{request_id}',
   array['edge:pdpl_request','edge:pdpl_erase'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W28 accountable general_counsel. UAE PDPL Art. 13-17 data-subject request; the endpoint is '
   'legally required to be usable without an account, so the work it starts must be owned.'),

  -- ---- supplier_event: a supplier did something -------------------------------------------
  ('supplier.registration_submitted','supplier_event','W09','supplier_account:{supplier_ref}',
   array['edge:supplier_api','edge:supplier_onboard','edge:claim_lookup','ui:/supplier'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W09 accountable supplier_onboarding_specialist; entry step W09-S01.'),
  ('supplier.file_complete','supplier_event','W10','supplier_verification_case:{supplier_ref}',
   array['edge:supplier_api','edge:sup_dob','edge:kyc','edge:license_extract'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W10 accountable supplier_verification. A complete file is the signal; independent verification '
   'is the work, and the supplier may not verify itself.'),
  ('supplier.quotation_submitted','supplier_event','W14','quotation:{quotation_id}',
   array['edge:supplier_api','edge:supplier_portal','edge:quote_extract','ui:/supplier'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W14 accountable quote_evaluation; entry step W14-S01. The supplier''s quote is never altered.'),
  ('supplier.churn_signal','supplier_event','W19','supplier_retention_case:{supplier_ref}',
   array['cron:supplier_risk_response_delays','cron:supplier_risk_performance_drops','edge:supplier_api'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W19 accountable supplier_retention. SLA-SUPPLIER-RETENTION: 1 business day after signal.'),

  -- ---- scheduled_event: the calendar did something ----------------------------------------
  ('scheduled.reporting_cycle','scheduled_event','W25','intelligence_product:{report_key}',
   array['cron:board_report_weekly','cron:monthly_report','cron:founder_brief_daily','cron:quarterly_report'],
   'system.scheduler','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W25 accountable data_intelligence_director. system.scheduler starts registered work and is '
   'never the accountable owner of it.'),
  ('scheduled.financial_close','scheduled_event','W27','financial_close:{period}',
   array['cron:gl_sync_nightly','cron:monthly_report','cron:reallocate_monthly'],
   'system.scheduler','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W27 accountable cfo. SLA-FINANCIAL-CLOSE: 5 business days after period end.'),
  ('scheduled.campaign_cycle','scheduled_event','W03','growth_program:{program_key}',
   array['cron:marketing_ai_daily','cron:blog_weekly_mon','cron:seo_gen_weekly'],
   'system.scheduler','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W03 accountable chief_revenue_officer. Budgets and commercial rules stay founder-approved; the '
   'cycle starting is not a spend decision.'),

  -- ---- deadline_sla_event: NO WORKFLOW EXISTS ---------------------------------------------
  --
  -- All 34 rows of phase_b_sla_policy were read. Every breach_action is "escalate", "block",
  -- "remind", "retry" or "open an exception" — an action INSIDE the run that is already open,
  -- carried by phase_b_exception and the handoff SLA. Not one of them starts a workflow, and no
  -- phase_b_workflow declares a deadline or an SLA breach as its start event. Mapping this class
  -- onto W29 (incident) or W02 (target miss) would be inventing a mapping to make a column look
  -- complete, so it is declared for what it is.
  ('deadline.sla_breach','deadline_sla_event',null,null,
   array['cron:sla_watch_hourly','kernel:handoff_due'],
   'system.health_monitor','inactive','DEFERRED_HANDLER',
   'DEFERRED. No Phase B workflow starts from a deadline or SLA breach: all 34 phase_b_sla_policy '
   'breach_actions escalate, block, remind or open an exception WITHIN the open run. The handler '
   'belongs with the exception and escalation engine, not with a workflow start. Accountable for '
   'building it: coo, as the owner of system.scheduler and of the SLA clock.'),

  -- ---- kpi_deviation_event: a number moved ------------------------------------------------
  ('kpi.company_target_miss','kpi_deviation_event','W02','performance_recovery_case:{metric_key}',
   array['cron:kpi_review_weekly','cron:os_objective_measure_daily','cron:company_indices_daily'],
   'system.health_monitor','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W02 accountable corporate_performance_director. Founder only for reserved policy/budget '
   'changes; the diagnosis and the corrective cycle are not founder work.'),
  ('kpi.supplier_coverage_gap','kpi_deviation_event','W11','supplier_coverage_case:{category_key}',
   array['cron:supply_gap_scan_daily','cron:scan_new_supplier_categories'],
   'system.health_monitor','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W11 accountable supplier_coverage. No unapproved outreach or spend — W11''s own gate, not this '
   'adapter''s.'),
  ('kpi.agent_capability_failure','kpi_deviation_event','W30','capability_case:{role_id}',
   array['cron:employee_kpi_measure_daily','cron:v3_role_readiness_daily','cron:agent_silence_watch_daily'],
   'system.health_monitor','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W30 accountable agent_workforce_capability_director. No self-certification: the failing role '
   'may not own its own remediation case.'),

  -- ---- system_health_event: the platform said something -----------------------------------
  ('system.incident_opened','system_health_event','W29','incident:{incident_ref}',
   array['cron:health_check','cron:uptime_check_15min','cron:smoke_test_30min','cron:ai_health_15min',
         'cron:agent_security_hourly','cron:security_selfaudit_daily','cron:ai_spend_guard_hourly',
         'edge:resilience_ping'],
   'system.health_monitor','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W29 accountable it_operations_engineer. TRACE-MONITORING already expects a probe to open an '
   'incident or a task; this is the route that makes the incident owned work rather than a row.'),

  -- ---- webhook_provider_event: an external provider said something -------------------------
  ('provider.payment_event','webhook_provider_event','W16','payment_transaction:{provider_event_id}',
   array['edge:stripe_webhook','edge:stripe_confirm'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W16 accountable payments_and_billing_manager. phase_b_business_object.provider_event is defined '
   'as an AUTHENTICATED external payment event: stripe_webhook verifies the HMAC signature with a '
   '600-second tolerance before it is a signal at all.'),
  ('provider.dispute_opened','webhook_provider_event','W17','refund_dispute_case:{provider_event_id}',
   array['edge:stripe_webhook'],
   'system.webhook_receiver','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W17 accountable trust_and_safety_manager. A provider dispute opens the case; money movement '
   'stays behind the founder refund gate.'),

  -- ---- workflow_followup_event: our own workflow finished something ------------------------
  --
  -- The one class that could be mistaken for the defect this file exists to remove. It is not the
  -- same thing: a followup is a REQUEST written by a step that has completed, asking that the NEXT
  -- workflow start. It is never the delivery of a .started fact, and fn_kernel_assert_not_in_delivery
  -- refuses it if it is ever attempted from inside the outbox consumer.
  ('workflow.route_evidence_changed','workflow_followup_event','W06','inquiry_route_set:{inquiry_id}',
   array['kernel:step_complete','edge:route_inquiry'],
   'system.workflow_engine','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W06 accountable inquiry_router. New or changed inquiry evidence; no silent uncertain activation.'),
  ('workflow.safe_package_ready','workflow_followup_event','W08','supplier_safe_package:{inquiry_id}',
   array['kernel:step_complete'],
   'system.workflow_engine','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W08 accountable marketplace_content_privacy_reviewer. No customer identity leakage.'),
  ('workflow.safe_package_approved','workflow_followup_event','W12','dispatch_batch:{inquiry_id}',
   array['kernel:step_complete'],
   'system.workflow_engine','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W12 accountable supplier_matching_dispatch_operator. Dispatch may not start before W08 approves '
   'the package, which is why this is a followup and not a customer_event.'),
  ('workflow.quotations_sufficient','workflow_followup_event','W15','quotation_comparison:{inquiry_id}',
   array['kernel:step_complete'],
   'system.workflow_engine','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W15 accountable rfq_success. Pricing and reveal policy remain founder-reserved.'),
  ('workflow.notification_approved','workflow_followup_event','W13','notification:{notification_id}',
   array['kernel:step_complete'],
   'system.workflow_engine','active','ADAPTER_READY_NO_LIVE_SENDER',
   'W13 accountable lifecycle_channel_operations. Consent and sender policy enforced by W13 itself; '
   'the three outbound senders remain switched off and this file does not touch them.')
on conflict (trigger_type) do update
  set source_class           = excluded.source_class,
      workflow_id            = excluded.workflow_id,
      business_object_rule   = excluded.business_object_rule,
      allowed_source_systems = excluded.allowed_source_systems,
      system_actor_id        = excluded.system_actor_id,
      activation_state       = excluded.activation_state,
      implementation_state   = excluded.implementation_state,
      accountable_note       = excluded.accountable_note;

-- ------------------------------------------------------------------ 4. the one adapter entry point
--
-- Every source class uses this function. There is no per-class adapter, because a per-class adapter
-- is a per-class opportunity to skip the idempotency check, invent an owner, or write a task
-- directly — which is how the estate acquired two work queues with two vocabularies.
--
-- AUTHENTICATION is two-layered and both layers are real:
--   1. Who may call at all: SECURITY DEFINER, revoked from PUBLIC, granted to service_role only.
--      anon and authenticated cannot execute it over PostgREST.
--   2. Who may submit WHICH type: kernel_trigger_type.allowed_source_systems. A caller holding the
--      service role still cannot submit provider.payment_event from ui:/portal.
create or replace function public.fn_kernel_trigger_submit(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k10_submit$
declare
  v_class     text  := nullif(btrim(coalesce(p_input->>'source_class','')), '');
  v_system    text  := nullif(btrim(coalesce(p_input->>'source_system','')), '');
  v_ref       text  := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_ext       text  := nullif(btrim(coalesce(p_input->>'external_ref','')), '');
  v_type_in   text  := nullif(btrim(coalesce(p_input->>'trigger_type','')), '');
  v_by        text  := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_payload   jsonb := coalesce(p_input->'raw_payload', '{}'::jsonb);
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text  := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_idem      text;
  v_corr      text;
  v_caus      text;
  v_inbox     bigint;
  v_trace     bigint;
  v_obj       text;
  v_key       text;
  v_val       text;
  v_missing   text;
  v_start     jsonb;
  v_run       bigint;
  v_status    text;
  v_reason    text;
  v_actor     text;
  v_kind      text;
  v_owner     text;
  v_step_owner text;
  v_step_id   text;
  -- Scalars, never a RECORD: a plpgsql RECORD assigned only inside an if-branch raises when it is
  -- read, and a SELECT INTO that matched nothing NULLs every target rather than leaving the
  -- initialiser. Both traps have already been paid for in this estate.
  t_workflow  text;
  t_rule      text;
  t_sources   text[];
  t_actor     text;
  t_activation text;
  t_impl      text;
  t_class     text;
  t_note      text;
  p_inbox     bigint;
  p_status    text;
  p_run       bigint;
  p_trace     bigint;
  p_type      text;
  p_wf        text;
  p_obj       text;
  p_reason    text;
begin
  -- ---- 0. a consumer may never drive the request side --------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_trigger_submit');

  -- ---- 1. envelope. A malformed envelope has nothing recordable in it ----------------------
  --
  -- These raise rather than record: source_class is CHECK-constrained and requested_by is NOT NULL,
  -- so a row cannot be written to hold the refusal. Everything that CAN be recorded is recorded
  -- below instead of raised.
  if v_class is null or v_system is null or v_ref is null or v_type_in is null or v_by is null then
    raise exception
      'fn_kernel_trigger_submit: source_class, source_system, source_ref, trigger_type and '
      'requested_by are all required (got %, %, %, %, %)',
      coalesce(v_class,'(null)'), coalesce(v_system,'(null)'), coalesce(v_ref,'(null)'),
      coalesce(v_type_in,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'fn_kernel_trigger_submit: raw_payload must be a json object, got %',
      jsonb_typeof(v_payload) using errcode = '22023';
  end if;
  if v_class not in ('customer_event','supplier_event','scheduled_event','deadline_sla_event',
                     'kpi_deviation_event','system_health_event','webhook_provider_event',
                     'workflow_followup_event') then
    raise exception 'fn_kernel_trigger_submit: % is not one of the eight registered source classes',
      v_class using errcode = '22023';
  end if;

  -- The idempotency key is the external identity of the request. Defaulted from the source's own
  -- reference, never from now() or from a sequence: a key that is different every time is not a key.
  v_idem := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),
                     v_system || ':' || coalesce(v_ext, v_ref));
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), 'trigger:' || v_idem);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_system || ':' || v_ref);

  -- ---- 2. idempotency, before anything is resolved and before anything is created ----------
  insert into public.kernel_trigger_inbox
    (source_class, source_system, source_ref, external_ref, raw_payload,
     correlation_id, causation_id, idempotency_key, status, requested_by)
  values (v_class, v_system, v_ref, v_ext, v_payload, v_corr, v_caus, v_idem, 'pending', v_by)
  on conflict (idempotency_key) do nothing
  returning inbox_id into v_inbox;

  if v_inbox is null then
    -- Seen before. Return the FIRST result and create nothing: no run, no task, no event, and no
    -- second inbox row. The first row's decision is the answer, whatever it was.
    select i.inbox_id, i.status, i.run_id, i.trace_id, i.trigger_type, i.workflow_id,
           i.business_object_id, i.refusal_reason
      into p_inbox, p_status, p_run, p_trace, p_type, p_wf, p_obj, p_reason
      from public.kernel_trigger_inbox i where i.idempotency_key = v_idem;
    -- An empty read here would mean the conflicting row belongs to a transaction that has not
    -- committed. Returning a jsonb full of nulls would make "someone else is mid-flight" look
    -- exactly like "refused with no reason", so it raises instead.
    if p_inbox is null then
      raise exception
        'fn_kernel_trigger_submit: idempotency key % conflicted but no committed row holds it — a '
        'concurrent submission of the same key is still open. Retry.', v_idem
        using errcode = '40001';
    end if;
    return jsonb_build_object(
      'ok', p_status in ('accepted','duplicate'), 'duplicate', true, 'status', p_status,
      'inbox_id', p_inbox, 'idempotency_key', v_idem, 'trigger_type', p_type,
      'workflow_id', p_wf, 'business_object_id', p_obj, 'run_id', p_run, 'trace_id', p_trace,
      'refusal_reason', p_reason,
      'created', jsonb_build_object('inbox_row',0,'run',0,'step_run',0,'task',0,'event',0),
      'note','idempotency_key already recorded; the first result is returned and nothing was created');
  end if;

  -- ---- 3. normalize to a REGISTERED trigger type -------------------------------------------
  select t.workflow_id, t.business_object_rule, t.allowed_source_systems, t.system_actor_id,
         t.activation_state, t.implementation_state, t.source_class, t.accountable_note
    into t_workflow, t_rule, t_sources, t_actor, t_activation, t_impl, t_class, t_note
    from public.kernel_trigger_type t where t.trigger_type = v_type_in;

  v_status := null; v_reason := null;

  if t_class is null then
    v_status := 'refused';
    v_reason := format('no registered trigger type named %s. An unmapped trigger is recorded and '
                    || 'refused; it is never resolved to the nearest workflow.', v_type_in);
  elsif t_class is distinct from v_class then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered under source class %s and was submitted as %s',
                       v_type_in, t_class, v_class);
  elsif not (v_system = any (t_sources)) then
    v_status := 'refused';
    v_reason := format('source system %s is not permitted to submit %s. Permitted: %s',
                       v_system, v_type_in, array_to_string(t_sources, ', '));
  elsif t_impl = 'DEFERRED_HANDLER' then
    v_status := 'deferred';
    v_reason := format('trigger type %s is a DEFERRED_HANDLER: the frozen Phase B registry declares '
                    || 'no workflow that starts from this signal. %s', v_type_in, t_note);
  elsif t_activation <> 'active' then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered with activation_state %s and does not accept '
                    || 'submissions', v_type_in, t_activation);
  end if;

  -- ---- 4. resolve the business object BY THE RECORDED RULE ---------------------------------
  if v_status is null then
    v_obj := t_rule;
    -- regexp_matches is set-returning, so it is driven by a FOR loop and never placed inside a
    -- boolean expression: a set-returning function in a boolean expression raises 42804.
    for v_key in select rr.mk[1] from regexp_matches(t_rule, '\{([a-zA-Z0-9_]+)\}', 'g') as rr(mk) loop
      v_val := nullif(btrim(coalesce(v_payload->>v_key,'')), '');
      if v_val is null then
        v_missing := coalesce(v_missing || ', ', '') || v_key;
      else
        v_obj := replace(v_obj, '{' || v_key || '}', v_val);
      end if;
    end loop;

    if v_missing is not null then
      v_status := 'refused';
      v_reason := format('business object rule %s needs payload key(s) %s and the payload does not '
                      || 'carry them. The object is refused, not guessed.', t_rule, v_missing);
    elsif v_obj ~ '[{}]' then
      v_status := 'refused';
      v_reason := format('business object rule %s did not fully resolve: %s', t_rule, v_obj);
    end if;
  end if;

  -- ---- 5. the founder boundary, checked again at call time ---------------------------------
  --
  -- The registry guard in §1 refuses such a row at write time. This is the second check, because a
  -- row could predate the guard, and because "normal autonomous work never routes through the
  -- founder or the Chief of Staff" is the kind of rule that must hold even when the table is wrong.
  if v_status is null then
    select kind, role_id into v_kind, v_owner
      from public.fn_phase_c_resolve_actor(
        (select w.accountable_role_id from public.phase_b_workflow w where w.workflow_id = t_workflow));
    select s.step_id, r.role_id into v_step_id, v_step_owner
      from public.phase_b_workflow_step s,
           lateral public.fn_phase_c_resolve_actor(s.accountable_role_id) r
     where s.workflow_id = t_workflow and s.step_no = 1;

    if v_owner is null or v_kind is distinct from 'canonical' then
      v_status := 'refused';
      v_reason := format('workflow %s names accountable role that resolves to %s — no run created',
                         t_workflow, coalesce(v_kind,'nothing'));
    elsif v_owner in ('founder','chief_of_staff') or coalesce(v_step_owner,'') in ('founder','chief_of_staff') then
      v_status := 'refused';
      v_reason := format('workflow %s would put autonomous work on %s / %s (step %s). Normal '
                      || 'autonomous work bypasses both the founder and the Chief of Staff.',
                         t_workflow, v_owner, coalesce(v_step_owner,'(none)'), coalesce(v_step_id,'(none)'));
    end if;
  end if;

  -- ---- 6. refusals and deferrals are RECORDED, with their own trace ------------------------
  if v_status is not null then
    v_actor := coalesce(t_actor, 'system.webhook_receiver');
    v_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
      'system_actor_id', v_actor,
      'actor_role_id', coalesce(nullif(v_owner,''), ''),
      'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
      'authority_result', v_status || ': ' || v_reason,
      'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
        'external_ref', v_ext, 'submitted_trigger_type', v_type_in,
        'idempotency_key', v_idem, 'raw_payload', v_payload)),
      'state_before','pending', 'state_after', v_status, 'status','sealed'));

    update public.kernel_trigger_inbox
       set status = v_status, refusal_reason = v_reason, trace_id = v_trace,
           trigger_type = (case when t_class is null then null else v_type_in end),
           processed_at = now()
     where inbox_id = v_inbox;

    return jsonb_build_object(
      'ok', false, 'duplicate', false, 'status', v_status, 'inbox_id', v_inbox,
      'idempotency_key', v_idem, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
      'business_object_id', null, 'run_id', null, 'trace_id', v_trace,
      'refusal_reason', v_reason, 'correlation_id', v_corr, 'causation_id', v_caus,
      'created', jsonb_build_object('inbox_row',1,'run',0,'step_run',0,'task',0,'event',0));
  end if;

  -- ---- 7. THE ONLY creator of business work is called ---------------------------------------
  --
  -- No insert into phase_c_task, phase_c_workflow_run, phase_c_workflow_step_run,
  -- phase_c_handoff_run or phase_c_event_outbox appears anywhere in this function. All six objects
  -- come from fn_kernel_workflow_start, atomically, or none of them does.
  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        t_workflow,
    'business_object_id', v_obj,
    'object_version',     v_version,
    'source_kind',        'autonomous',
    'source_ref',         'trigger_inbox:' || v_inbox,
    'correlation_id',     v_corr,
    'causation_id',       v_caus,
    'requested_by',       v_by,
    'priority',           v_priority,
    'trigger_ctx',        jsonb_build_object(
        'inbox_id', v_inbox, 'trigger_type', v_type_in, 'source_class', v_class,
        'source_system', v_system, 'source_ref', v_ref, 'external_ref', v_ext,
        'idempotency_key', v_idem, 'business_object_rule', t_rule, 'raw_payload', v_payload)));

  v_run    := (v_start->>'run_id')::bigint;
  v_status := case when coalesce((v_start->>'duplicate')::boolean, false)
                   then 'duplicate' else 'accepted' end;

  if v_run is null then
    raise exception 'fn_kernel_trigger_submit: fn_kernel_workflow_start returned no run_id for % / %',
      t_workflow, v_obj using errcode = '23502';
  end if;

  -- ---- 8. the adapter's own execution trace, parented to the run's root --------------------
  v_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
    'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'system_actor_id', t_actor,
    'actor_role_id', v_start->>'step_accountable_role_id',
    'manager_role_id', v_start->>'accountable_role_id',
    'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
    'authority_result', v_status || ': trigger type ' || v_type_in || ' -> ' || t_workflow
                     || ' by registry, business object by rule ' || t_rule,
    'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
    'output_hash', encode(sha256(convert_to(v_start::text, 'UTF8')), 'hex'),
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
      'external_ref', v_ext, 'idempotency_key', v_idem,
      'business_object_rule', t_rule, 'business_object_id', v_obj, 'raw_payload', v_payload)),
    'event_ids', jsonb_build_array(v_start->>'event_id'),
    'state_before','pending', 'state_after', v_status, 'status','sealed',
    'parent_trace_id', (v_start->>'run_trace_id')::bigint));

  update public.kernel_trigger_inbox
     set status = v_status, trigger_type = v_type_in, workflow_id = t_workflow,
         business_object_id = v_obj, run_id = v_run, trace_id = v_trace, processed_at = now()
   where inbox_id = v_inbox;

  return jsonb_build_object(
    'ok', true, 'duplicate', (v_status = 'duplicate'), 'status', v_status,
    'inbox_id', v_inbox, 'idempotency_key', v_idem,
    'source_class', v_class, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
    'business_object_id', v_obj, 'object_version', v_version,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'accountable_role_id', v_start->>'accountable_role_id',
    'step_accountable_role_id', v_start->>'step_accountable_role_id',
    'handoff_run_id', (v_start->>'handoff_run_id')::bigint,
    'event_id', v_start->>'event_id', 'outbox_id', (v_start->>'outbox_id')::bigint,
    'trace_id', v_trace, 'run_trace_id', (v_start->>'run_trace_id')::bigint,
    'correlation_id', v_corr, 'causation_id', v_caus, 'system_actor_id', t_actor,
    'created', jsonb_build_object(
      'inbox_row', 1,
      'run',      (case when v_status = 'duplicate' then 0 else 1 end),
      'step_run', (case when v_status = 'duplicate' then 0 else 1 end),
      'task',     (case when v_status = 'duplicate' then 0 else 1 end),
      'event',    (case when v_status = 'duplicate' then 0 else 1 end),
      'adapter_trace', 1));
end
$k10_submit$;

revoke all on function public.fn_kernel_trigger_submit(jsonb) from public;
grant execute on function public.fn_kernel_trigger_submit(jsonb) to service_role;

comment on function public.fn_kernel_trigger_submit(jsonb) is
  'K10. The ONE adapter entry point for all eight autonomous source classes. Authenticates the '
  'source, records the canonical request in kernel_trigger_inbox, normalizes to a registered '
  'trigger type, resolves the Phase B workflow from kernel_trigger_type and the business object '
  'from the recorded rule, applies idempotency, and calls fn_kernel_workflow_start. Creates no '
  'task itself, routes nothing through founder or chief_of_staff, and records an explicit refusal '
  'with a reason rather than dropping or guessing an unmapped trigger.';

-- ------------------------------------------------------------------ 5. the source inventory
--
-- Every existing trigger source: every cron job active and inactive, every row trigger, every event
-- trigger, every inbound edge function, every frontend path that signals work. Identity and the
-- assigned adapter are recorded here; whether the source is switched on, whether it creates work,
-- and whether it routes through the inbox are DERIVED LIVE in §6 and never read from this table.
create table if not exists public.kernel_trigger_source (
  source_key            text primary key,
  source_kind           text not null,
  source_ref            text not null,
  source_class          text,
  adapter_trigger_type  text references public.kernel_trigger_type(trigger_type),
  workflow_id           text references public.phase_b_workflow(workflow_id),
  accountable_role_id   text not null,
  connection_state      text not null,
  -- Why this source has no adapter, when it has none. NULL means "it should have one and does not"
  -- — the only value that counts as an open gap. The three named values are recorded answers, and
  -- fn_kernel_trigger_state reports each of them as its own number so a deferral can never be
  -- mistaken for a fix and can never disappear into a denominator.
  disposition           text,
  -- Only for sources the Postgres catalogue cannot see: a Deno deployment, a TypeScript branch, a
  -- file in src/**. Null everywhere else, so the derivation is forced to measure.
  recorded_active             boolean,
  recorded_creates_work       boolean,
  recorded_routes_through_inbox boolean,
  evidence              text not null,
  measured_at           timestamptz not null default now(),
  measured_by           text not null default 'kernel:k10',

  constraint kernel_trigger_source_kind_ck check (source_kind = any (array[
    'cron_job','database_trigger','event_trigger','edge_function','frontend_path'])),
  constraint kernel_trigger_source_state_ck check (connection_state = any (array[
    'CONNECTED_ACTIVE','CONNECTED_INACTIVE','DEFERRED_HANDLER',
    'INTENTIONALLY_RETIRED','HISTORICAL_ONLY'])),
  constraint kernel_trigger_source_evidence_ck check (btrim(evidence) <> ''),
  constraint kernel_trigger_source_disposition_ck check (disposition is null or disposition = any (array[
    'NOT_A_BUSINESS_TRIGGER','NO_WORKFLOW_IN_REGISTRY','FOUNDER_COMMAND_SURFACE'])),
  -- A source that is not a business trigger, or is the founder's own command channel, cannot also
  -- carry an adapter. NO_WORKFLOW_IN_REGISTRY may: cron 101 is assigned deadline.sla_breach, which
  -- is itself the DEFERRED_HANDLER for the class.
  constraint kernel_trigger_source_disposition_excl_ck check (
    disposition not in ('NOT_A_BUSINESS_TRIGGER','FOUNDER_COMMAND_SURFACE')
    or adapter_trigger_type is null),
  -- CONNECTED means an adapter is assigned. Nothing may claim CONNECTED without one.
  constraint kernel_trigger_source_connected_ck check (
    connection_state not like 'CONNECTED%' or adapter_trigger_type is not null),
  -- The catalogue answers for cron, row triggers and event triggers; a recorded override on those
  -- would be a hand-written status column standing in front of a measurable fact.
  constraint kernel_trigger_source_recorded_ck check (
    source_kind in ('edge_function','frontend_path')
    or (recorded_active is null and recorded_creates_work is null
        and recorded_routes_through_inbox is null))
);

comment on table public.kernel_trigger_source is
  'K10 inventory of every existing trigger source. connection_state CONNECTED_ACTIVE means "this '
  'inventory assigns an adapter and the source is switched on" — it does NOT mean the source calls '
  'the adapter. v_kernel_trigger_source_derived.routes_through_inbox is the measurement of that, '
  'and it is false on every row today.';

alter table public.kernel_trigger_source enable row level security;
revoke all on public.kernel_trigger_source from public;
grant select, insert, update, delete on public.kernel_trigger_source to service_role;

-- ---- 5a. cron jobs: all of them, active and inactive ---------------------------------------
--
-- Evidence is generated from the catalogue, not written by hand: schedule, active flag, run count,
-- last run, the routines the command names and the work tables those routines write.
insert into public.kernel_trigger_source
  (source_key, source_kind, source_ref, accountable_role_id, connection_state, evidence)
select 'cron:' || j.jobid, 'cron_job', j.jobid::text,
       (select a.accountable_role_id from public.phase_c_system_actor a
         where a.system_actor_id = 'system.scheduler'),
       'DEFERRED_HANDLER',
       format('cron.job %s %s schedule %s active=%s; %s runs, last %s; command: %s',
              j.jobid, coalesce(j.jobname,'(unnamed)'), j.schedule, j.active,
              (select count(*) from cron.job_run_details d where d.jobid = j.jobid),
              coalesce((select max(d.start_time)::date::text from cron.job_run_details d where d.jobid = j.jobid),'never'),
              left(regexp_replace(j.command, '\s+', ' ', 'g'), 220))
  from cron.job j
on conflict (source_key) do update
  set evidence = excluded.evidence, measured_at = now();

-- ---- 5b. row triggers: all of them -----------------------------------------------------------
insert into public.kernel_trigger_source
  (source_key, source_kind, source_ref, accountable_role_id, connection_state, evidence)
select 'dbtrigger:' || n.nspname || '.' || c.relname || ':' || t.tgname,
       'database_trigger', n.nspname || '.' || c.relname || ':' || t.tgname,
       (select a.accountable_role_id from public.phase_c_system_actor a
         where a.system_actor_id = 'system.storage_trigger'),
       'DEFERRED_HANDLER',
       format('pg_trigger %s on %s.%s -> %s, enabled=%s',
              t.tgname, n.nspname, c.relname, p.proname, (t.tgenabled <> 'D'))
  from pg_trigger t
  join pg_class c     on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p      on p.oid = t.tgfoid
 where not t.tgisinternal
on conflict (source_key) do update
  set evidence = excluded.evidence, measured_at = now();

-- ---- 5c. event triggers ----------------------------------------------------------------------
insert into public.kernel_trigger_source
  (source_key, source_kind, source_ref, accountable_role_id, connection_state, evidence)
select 'evttrigger:' || e.evtname, 'event_trigger', e.evtname,
       (select a.accountable_role_id from public.phase_c_system_actor a
         where a.system_actor_id = 'system.storage_trigger'),
       'DEFERRED_HANDLER',
       format('pg_event_trigger %s on %s -> %s, enabled=%s (evtenabled=%s)',
              e.evtname, e.evtevent, p.proname, (e.evtenabled <> 'D'), e.evtenabled)
  from pg_event_trigger e join pg_proc p on p.oid = e.evtfoid
on conflict (source_key) do update
  set evidence = excluded.evidence, measured_at = now();

-- ---- 5d. inbound edge functions --------------------------------------------------------------
--
-- 202 edge functions are deployed. 25 of them are INBOUND TARGETS: a provider webhook, an inbound
-- email or WhatsApp, an OAuth or one-click callback, or a surface a person POSTs to. The other 177
-- are internal workers reached from cron or from another function, and they are already in this
-- inventory through the cron rows that invoke them.
--
-- These three columns are RECORDED because the database cannot read a Deno deployment or a
-- TypeScript authorisation branch. Measured 17 Aug 2026 against the deployed source in
-- supabase/functions/** on branch rebuild/phase-c-execution-kernel.
insert into public.kernel_trigger_source
  (source_key, source_kind, source_ref, source_class, adapter_trigger_type, workflow_id,
   accountable_role_id, connection_state,
   recorded_active, recorded_creates_work, recorded_routes_through_inbox, evidence)
values
  ('edge:stripe_webhook','edge_function','stripe_webhook','webhook_provider_event',
   'provider.payment_event','W16','payments_and_billing_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v13. Stripe provider webhook: verifies the HMAC signature with a 600-second '
   'replay tolerance, then writes transactions and logs every exit path to agent_runs. The one '
   'source in this inventory whose authenticity is cryptographically established before it is a '
   'signal at all.'),
  ('edge:stripe_confirm','edge_function','stripe_confirm','webhook_provider_event',
   'provider.payment_event','W16','payments_and_billing_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v5. Browser-side payment confirmation callback; writes the reveal transaction '
   'and signs the file URLs.'),
  ('edge:resend_webhook','edge_function','resend_webhook',null,null,null,
   'lifecycle_channel_operations','DEFERRED_HANDLER',
   true,true,false,
   'NO_WORKFLOW_IN_REGISTRY. Deployed ACTIVE v8. Resend delivery events, Svix signature verified '
   '(v4 security fix 19 Jul 2026 replaced a secret in the query string). A hard bounce writes '
   'email_suppressions. No phase_b_workflow starts from a delivery bounce: W13 starts from an '
   'APPROVED QUEUED NOTIFICATION, not from its failure. Handler owed to lifecycle_channel_operations.'),
  ('edge:resend_inbound','edge_function','resend_inbound','customer_event',
   'customer.document_uploaded','W07','document_intelligence_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v26. Inbound email with attachments, Svix signature verified. Receipts to '
   'finance, supplier documents stored and classified. A document arriving IS the W07 start event.'),
  ('edge:inbound_email','edge_function','inbound_email','customer_event',
   'customer.inquiry_submitted','W05','rfq_qualification_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v9. Inbound email classified into an inquiry; authenticates on x-webhook-secret.'),
  ('edge:wa_inbound','edge_function','wa_inbound','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v30. WhatsApp inbound on the API number; v10 added webhook authenticity, v12 '
   'routed it through ai_gateway with a per-sender ceiling. Replies to a person: a live customer '
   'conversation with no workflow run behind it.'),
  ('edge:contact_submit','edge_function','contact_submit','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v4, verify_jwt=true. Public contact form; honeypot spam guard; stores the '
   'message and emails the founder best-effort.'),
  ('edge:inquiry_intake','edge_function','inquiry_intake','customer_event',
   'customer.inquiry_submitted','W05','rfq_qualification_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v22. Conversational intake: detects category, asks clarifying questions, emits '
   'a supplier-ready brief with a readiness score, persists drafts in inquiry_intake. The single '
   'most important unwired source in this inventory — it is where a customer inquiry begins.'),
  ('edge:customer_api','edge_function','customer_api','customer_event',
   'customer.inquiry_submitted','W05','rfq_qualification_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v61. The customer portal API; called from src/components/me/** and '
   'src/components/portal/**. Creates and mutates inquiries.'),
  ('edge:customer_documents','edge_function','customer_documents','customer_event',
   'customer.document_uploaded','W07','document_intelligence_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v4. Customer document upload from src/components/portal/documents/api.ts.'),
  ('edge:attach_photos','edge_function','attach_photos','customer_event',
   'customer.document_uploaded','W07','document_intelligence_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v7, verify_jwt=false with in-function Bearer -> auth.getUser -> 401.'),
  ('edge:messages_api','edge_function','messages_api','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v19. Customer/supplier messaging from src/components/portal/comms/api.ts.'),
  ('edge:site_assistant','edge_function','site_assistant','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v19. The public chat widget (src/components/ChatWidget.tsx).'),
  ('edge:refund_flow','edge_function','refund_flow','customer_event',
   'customer.refund_requested','W17','trust_and_safety_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v5, in-function Bearer -> getUser -> 401, then customers row -> 403 no_customer. '
   'Opens the refund case; the money movement itself stays behind the founder gate.'),
  ('edge:pdpl_request','edge_function','pdpl_request','customer_event',
   'customer.privacy_request','W28','general_counsel','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v4, verify_jwt=false and NO authentication of any kind — required: UAE PDPL '
   'Art. 13-17 give a data subject a channel that does not need an account. K11 recorded its abuse '
   'capacity as a Phase D item; K10 records that the work it creates has no owner.'),
  ('edge:supplier_api','edge_function','supplier_api','supplier_event',
   'supplier.quotation_submitted','W14','quote_evaluation','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v50. The supplier portal API: registration, capability claims and quote '
   'submission. Also the source for supplier.registration_submitted; the inventory records the '
   'highest-value route and the adapter normalizes the rest by trigger_type.'),
  ('edge:supplier_portal','edge_function','supplier_portal','supplier_event',
   'supplier.quotation_submitted','W14','quote_evaluation','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v36. Supplier portal surface behind src/components/portal/supplier/**.'),
  ('edge:supplier_onboard','edge_function','supplier_onboard','supplier_event',
   'supplier.registration_submitted','W09','supplier_onboarding_specialist','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v4. Supplier registration entry.'),
  ('edge:claim_lookup','edge_function','claim_lookup','supplier_event',
   'supplier.registration_submitted','W09','supplier_onboarding_specialist','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v4. Public "is this your company?" claim check; v2 replaced the sequential '
   'leads.id with an unguessable claim_token after v1 exposed the 20,470-row lead database. Public '
   'BY DESIGN: an invited supplier has no account yet.'),
  ('edge:sup_dob','edge_function','sup_dob','supplier_event',
   'supplier.file_complete','W10','supplier_verification','CONNECTED_ACTIVE',
   true,true,false,
   'Deployed ACTIVE v3, in-function Bearer -> getUser -> 401. Supplier verification document intake.'),
  ('edge:supplier_ack','edge_function','supplier_ack',null,null,null,
   'quote_evaluation','DEFERRED_HANDLER',
   true,true,false,
   'NO_WORKFLOW_IN_REGISTRY. Deployed ACTIVE v3. One-click "I have contacted the customer" from the '
   'nudge email; sets transactions.supplier_ack_at and stops the nudges. This is a STEP EVENT inside '
   'an open W14 run (SLA-SUPPLIER-ACK, 4 hours), not the start of a workflow. It belongs to '
   'fn_kernel_step_complete, which is K3.'),
  ('edge:unsubscribe','edge_function','unsubscribe',null,null,null,
   'lifecycle_channel_operations','DEFERRED_HANDLER',
   true,true,false,
   'NO_WORKFLOW_IN_REGISTRY. Deployed ACTIVE v5, HMAC-token link. Consent withdrawal. No '
   'phase_b_workflow starts from a withdrawal of consent; W13 enforces consent, it does not begin '
   'when consent is withdrawn. Handler owed to lifecycle_channel_operations.'),
  ('edge:dropbox_oauth','edge_function','dropbox_oauth',null,null,null,
   'it_operations_engineer','DEFERRED_HANDLER',
   true,false,false,
   'NOT_A_BUSINESS_TRIGGER. Deployed ACTIVE v5. OAuth connect page and diagnostics for the '
   'QuotesDone Dropbox: infrastructure credential plumbing. It starts no business work.'),
  ('edge:voice_otp','edge_function','voice_otp',null,null,null,
   'it_operations_engineer','INTENTIONALLY_RETIRED',
   true,false,false,
   'Deployed ACTIVE v6 and inert: the body is a 410 responder. DISABLED 18 Jul 2026 (security) — it '
   'published app_secrets.voice_capture_token in cleartext TwiML to any caller.'),
  ('edge:voice_otp_capture','edge_function','voice_otp_capture',null,null,null,
   'it_operations_engineer','INTENTIONALLY_RETIRED',
   true,false,false,
   'Deployed ACTIVE v5 and inert. DISABLED 18 Jul 2026 (security): an unauthenticated write into '
   'app_secrets gated only by a token its sibling handed to any caller. The file records what a '
   're-enable would require (X-Twilio-Signature validation) and it has not been done.')
on conflict (source_key) do update
  set source_class = excluded.source_class, adapter_trigger_type = excluded.adapter_trigger_type,
      workflow_id = excluded.workflow_id, accountable_role_id = excluded.accountable_role_id,
      connection_state = excluded.connection_state,
      recorded_active = excluded.recorded_active,
      recorded_creates_work = excluded.recorded_creates_work,
      recorded_routes_through_inbox = excluded.recorded_routes_through_inbox,
      evidence = excluded.evidence, measured_at = now();

-- ---- 5e. frontend paths that signal work -----------------------------------------------------
--
-- src/** has exactly one Next.js API route (src/app/api/resilience-ping/route.ts); every other
-- frontend signal is a fetch to an edge function. Measured by sweeping src/** for
-- `${SUPA_FN}/<slug>` and `/functions/v1/<slug>` on 17 Aug 2026.
insert into public.kernel_trigger_source
  (source_key, source_kind, source_ref, source_class, adapter_trigger_type, workflow_id,
   accountable_role_id, connection_state,
   recorded_active, recorded_creates_work, recorded_routes_through_inbox, evidence)
values
  ('ui:/[locale]/portal','frontend_path','src/app/[locale]/portal/page.tsx','customer_event',
   'customer.inquiry_submitted','W05','rfq_qualification_manager','CONNECTED_ACTIVE',
   true,true,false,
   'Customer portal. src/components/portal/**/api.ts fetch ${SUPA_FN}/customer_api, '
   'customer_documents, messages_api, project_api, procurement_api. Where a customer raises work.'),
  ('ui:/[locale]/me','frontend_path','src/app/[locale]/me/page.tsx','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Customer account area. src/components/me/CustomerPortal.tsx and PortalShell.tsx fetch '
   '${SUPA_FN}/customer_api and customer_portal.'),
  ('ui:/[locale]/supplier','frontend_path','src/app/[locale]/supplier/page.tsx','supplier_event',
   'supplier.registration_submitted','W09','supplier_onboarding_specialist','CONNECTED_ACTIVE',
   true,true,false,
   'Supplier registration and portal entry; src/components/portal/supplier/** reaches supplier_api '
   'and supplier_portal. 81 suppliers invited, 0 registered — this is the path they do not finish.'),
  ('ui:/[locale]/contact','frontend_path','src/app/[locale]/contact/page.tsx','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Public contact form; src/components/ContactInner.tsx posts to contact_submit.'),
  ('ui:ChatWidget','frontend_path','src/components/ChatWidget.tsx','customer_event',
   'customer.support_signal','W18','customer_success_director','CONNECTED_ACTIVE',
   true,true,false,
   'Site-wide chat widget; fetches ${SUPA_FN}/site_assistant. A person asking for help, on every '
   'page, with nothing behind it that owns the answer.'),
  ('ui:/[locale]/console','frontend_path','src/app/[locale]/console/page.tsx',null,null,null,
   'chief_of_staff','DEFERRED_HANDLER',
   true,true,false,
   'FOUNDER_COMMAND_SURFACE. src/lib/osClient.ts posts to os_api, os_ops, os_settings, '
   'os_automation, os_catalog, os_pages, os_health, os_incidents, report_body. This is the founder''s '
   'own command channel and it routes through the Chief of Staff BY DESIGN (K0/K2b). Giving it an '
   'autonomous trigger adapter would be the exact violation of the frozen operating model, so it '
   'deliberately has none.'),
  ('ui:/[locale]/os','frontend_path','src/app/[locale]/os/page.tsx',null,null,null,
   'chief_of_staff','DEFERRED_HANDLER',
   true,true,false,
   'FOUNDER_COMMAND_SURFACE. The OS dashboard, same osClient.ts endpoints. Founder path, not an '
   'autonomous trigger.'),
  ('ui:/api/resilience-ping','frontend_path','src/app/api/resilience-ping/route.ts',null,null,null,
   'it_operations_engineer','DEFERRED_HANDLER',
   true,false,false,
   'NOT_A_BUSINESS_TRIGGER. The only Next.js API route in src/**; posts to the resilience_ping edge '
   'function. A liveness probe.')
on conflict (source_key) do update
  set source_class = excluded.source_class, adapter_trigger_type = excluded.adapter_trigger_type,
      workflow_id = excluded.workflow_id, accountable_role_id = excluded.accountable_role_id,
      connection_state = excluded.connection_state,
      recorded_active = excluded.recorded_active,
      recorded_creates_work = excluded.recorded_creates_work,
      recorded_routes_through_inbox = excluded.recorded_routes_through_inbox,
      evidence = excluded.evidence, measured_at = now();

-- ---- 5f. the adapter assignments for the cron jobs and triggers that create work -------------
--
-- Named individually because each one is a judgement about what the source means, and a judgement
-- has to be legible to be argued with. Every assignment names a trigger type that exists in
-- kernel_trigger_type (FK) whose workflow exists in phase_b_workflow (FK).
update public.kernel_trigger_source s
   set source_class         = t.source_class,
       adapter_trigger_type = a.tt,
       workflow_id          = t.workflow_id,
       -- A DEFERRED_HANDLER assignment has no workflow, so there is no workflow owner to take the
       -- accountability from and the seeded system-actor owner stays. coalesce, not w.*: the
       -- LEFT JOIN yields NULL there and NULL is not an owner.
       accountable_role_id  = coalesce(w.accountable_role_id, s.accountable_role_id),
       measured_at          = now()
  from (values
    -- ACTIVE cron jobs that write a work queue or a business object (measured 17 Aug 2026)
    ('cron:7',  'system.incident_opened'),        -- health_check      -> notifications
    ('cron:14', 'scheduled.reporting_cycle'),     -- founder_brief     -> notifications, founder_alerts
    ('cron:26', 'system.incident_opened'),        -- smoke_test        -> notifications, error_events
    ('cron:57', 'scheduled.reporting_cycle'),     -- board_report      -> board_reports, notifications
    ('cron:60', 'scheduled.reporting_cycle'),     -- monthly_report    -> board_reports, notifications
    ('cron:64', 'kpi.agent_capability_failure'),  -- autonomy_dispose  -> agent_actions, leads
    ('cron:103','kpi.company_target_miss'),       -- policy_consistency-> notifications
    ('cron:110','system.incident_opened'),        -- agent_security    -> agent_actions, notifications
    ('cron:129','kpi.agent_capability_failure'),  -- autonomy_audit    -> agent_actions
    ('cron:142','kpi.company_target_miss'),       -- evolution_scan    -> evolution_proposal
    ('cron:172','system.incident_opened'),        -- ai_spend_guard    -> os_incidents
    -- HELD cron jobs whose resumption must come back through the kernel, not through themselves
    ('cron:2',  'supplier.registration_submitted'),
    ('cron:53', 'customer.document_uploaded'),
    ('cron:67', 'customer.inquiry_submitted'),
    ('cron:101','deadline.sla_breach'),
    ('cron:105','scheduled.financial_close'),
    ('cron:118','supplier.file_complete'),
    ('cron:141','workflow.notification_approved'),
    ('cron:155','kpi.supplier_coverage_gap'),
    ('cron:195','scheduled.reporting_cycle'),
    ('cron:209','supplier.churn_signal'),
    ('cron:210','supplier.churn_signal'),
    ('cron:211','supplier.churn_signal'),
    ('cron:250','kpi.agent_capability_failure'),
    ('cron:264','workflow.safe_package_approved'),
    -- ACTIVE row triggers that write a work or business table OTHER than their own
    ('dbtrigger:public.inquiries:trg_inquiry_received_a','customer.inquiry_submitted'),
    ('dbtrigger:public.inquiries:customer_abandon_ban','customer.support_signal'),
    ('dbtrigger:public.inquiry_matches:notify_matched_supplier','workflow.safe_package_approved'),
    ('dbtrigger:public.quotes:trg_new_quote_sms','supplier.quotation_submitted'),
    ('dbtrigger:public.quote_items:quote_items_rescore','supplier.quotation_submitted'),
    ('dbtrigger:public.quote_items:quote_items_roll','supplier.quotation_submitted'),
    ('dbtrigger:public.quote_items:trg_items_submittable','supplier.quotation_submitted'),
    ('dbtrigger:public.transactions:trg_reveal_receipt_a','provider.payment_event'),
    ('dbtrigger:public.transactions:trg_notify_refund','customer.refund_requested'),
    ('dbtrigger:public.transactions:trg_refund_resolved','customer.refund_requested'),
    ('dbtrigger:public.supplier_dues:trg_due_paid','provider.payment_event'),
    ('dbtrigger:public.notifications:trg_invite_status_on_send','supplier.registration_submitted'),
    ('dbtrigger:public.agent_actions:trg_page_high_agent_action','system.incident_opened'),
    ('dbtrigger:public.company_goals:trg_goal_cascade','kpi.company_target_miss')
  ) as a(sk, tt)
  join public.kernel_trigger_type t on t.trigger_type = a.tt
  left join public.phase_b_workflow w on w.workflow_id = t.workflow_id
 where s.source_key = a.sk;

-- connection_state follows from the assignment and from whether the source is switched on, and it
-- is set from the LIVE catalogue rather than typed in. DEFERRED_HANDLER assignments keep the
-- deferred state: cron 101 (sla_watch_hourly) is assigned deadline.sla_breach, which has no
-- workflow, so it is not connected to anything and must not say it is.
update public.kernel_trigger_source s
   set connection_state = case
         when t.implementation_state = 'DEFERRED_HANDLER' then 'DEFERRED_HANDLER'
         when j.active                                    then 'CONNECTED_ACTIVE'
         else 'CONNECTED_INACTIVE' end,
       measured_at = now()
  from public.kernel_trigger_type t, cron.job j
 where s.adapter_trigger_type = t.trigger_type
   and s.source_kind = 'cron_job'
   and j.jobid = s.source_ref::bigint;

update public.kernel_trigger_source s
   set connection_state = case
         when t.implementation_state = 'DEFERRED_HANDLER' then 'DEFERRED_HANDLER'
         when tg.tgenabled <> 'D'                         then 'CONNECTED_ACTIVE'
         else 'CONNECTED_INACTIVE' end,
       measured_at = now()
  from public.kernel_trigger_type t,
       pg_trigger tg
       join pg_class c     on c.oid = tg.tgrelid
       join pg_namespace n on n.oid = c.relnamespace
 where s.adapter_trigger_type = t.trigger_type
   and s.source_kind = 'database_trigger'
   and s.source_ref = n.nspname || '.' || c.relname || ':' || tg.tgname;

-- ---- 5g. the disposition of every source that has no adapter ----------------------------------
--
-- A source with no adapter and no disposition is an OPEN GAP: something starts work and nobody has
-- said where it should go. A source with a disposition has a recorded answer. The two are counted
-- separately for the rest of this file's life, because collapsing them is how 400 guard triggers
-- would become a fake backlog of 400 owed handlers — and how three real gaps would hide inside it.
update public.kernel_trigger_source
   set disposition = 'NOT_A_BUSINESS_TRIGGER',
       evidence    = 'NOT_A_BUSINESS_TRIGGER (invariant, guard, audit or observation trigger: it '
                  || 'enforces or records, it does not start work). ' || evidence
 where adapter_trigger_type is null and disposition is null
   and source_kind in ('database_trigger','event_trigger');

-- For cron the two reasons are alternatives and the row does not distinguish them, so the wording
-- must not claim either one. 67 of the held jobs DO write a work queue: they have no adapter
-- because they are switched off, and the moment one is resumed the invariant board demands an
-- adapter — check 1's population is derived from cron.job.active, so reactivation moves the row
-- into it by itself.
update public.kernel_trigger_source
   set disposition = 'NOT_A_BUSINESS_TRIGGER',
       evidence    = 'HELD_OR_NOT_A_BUSINESS_TRIGGER (this job is switched off — the automation '
                  || 'hold of 16 Aug 2026 holds 183 of the 206 — or it names no routine that writes '
                  || 'a work queue or a business object. Either way it starts nothing today. '
                  || 'Resuming it moves this row into the invariant board''s population and it will '
                  || 'then require an adapter). ' || evidence
 where adapter_trigger_type is null and disposition is null
   and source_kind = 'cron_job';

-- The recorded dispositions for the edge functions and frontend paths, matching the evidence each
-- of those rows already carries.
update public.kernel_trigger_source set disposition = 'NO_WORKFLOW_IN_REGISTRY'
 where source_key in ('edge:resend_webhook','edge:supplier_ack','edge:unsubscribe');
update public.kernel_trigger_source set disposition = 'NOT_A_BUSINESS_TRIGGER'
 where source_key in ('edge:dropbox_oauth','edge:voice_otp','edge:voice_otp_capture',
                      'ui:/api/resilience-ping');
update public.kernel_trigger_source set disposition = 'FOUNDER_COMMAND_SURFACE'
 where source_key in ('ui:/[locale]/console','ui:/[locale]/os');

-- cron 101 sla_watch_hourly is assigned deadline.sla_breach, which is the DEFERRED_HANDLER for its
-- whole class. It has an adapter and it still owes a handler; both are true and both are recorded.
update public.kernel_trigger_source set disposition = 'NO_WORKFLOW_IN_REGISTRY'
 where adapter_trigger_type in (select trigger_type from public.kernel_trigger_type
                                 where implementation_state = 'DEFERRED_HANDLER');

-- ------------------------------------------------------------------ 6. the live derivation
--
-- Three facts per source, measured now, from the catalogue. Comments are stripped from every
-- routine body first: fn_kernel_event_consume and fn_kernel_outbox_deliver both contain the string
-- `fn_kernel_workflow_start` inside a comment explaining why a consumer must never call it, and a
-- regex that does not strip comments reads those two explanations as two calls.
create or replace view public.v_kernel_trigger_source_derived as
with wt(t, why) as (values
  -- WORK QUEUES: a row here is work owed by a role.
  ('agent_actions',    'the legacy agent work queue'),
  ('org_tasks',        'the department task queue'),
  ('phase_c_task',     'the kernel task table'),
  ('notifications',    'the outbound message queue: a queued message is work owed to a person'),
  -- BUSINESS OBJECTS: each of these holds an instance of a phase_b_business_object.
  ('os_incidents',     'phase_b_business_object.incident, governed by W29'),
  ('board_reports',    'phase_b_business_object.intelligence_product, governed by W25'),
  ('evolution_proposal','phase_b_business_object.organization_change_request, governed by W30'),
  ('leads',            'the supplier lead / supplier_account population, governed by W09'),
  ('inquiries',        'phase_b_business_object.inquiry, governed by W05'),
  ('inquiry_intake',   'the inquiry draft that becomes phase_b_business_object.inquiry'),
  ('quotes',           'phase_b_business_object.quotation, governed by W14'),
  ('transactions',     'phase_b_business_object.payment_transaction, governed by W16'),
  ('customers',        'phase_b_business_object.customer_account, governed by W04')
),
body as (
  select p.oid, p.proname,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') as src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
),
writer as (
  select b.oid, b.proname, string_agg(distinct wt.t, ', ') as work_tables
    from body b join wt on b.src ~* ('(insert\s+into|update)\s+(public\.)?' || wt.t || '\y')
   group by b.oid, b.proname
),
kernelcaller as (
  select b.oid, b.proname from body b where b.src ~ '\yfn_kernel_trigger_submit\s*\('
),
-- the routine that reads the DOMAIN EVENT OUTBOX and creates work from it: the original defect
replayer as (
  select b.oid, b.proname from body b
   where b.src ~ '\yphase_c_event_outbox\y'
     and b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\('
),
cronjob as (
  select j.jobid, j.active,
         regexp_replace(regexp_replace(j.command, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') as cmd
    from cron.job j
),
-- One pass per source kind, not one regex per (source, routine) pair. The cheap strpos test runs
-- first so the anchored regex only sees the handful of names that could match at all.
cron_fact as (
  select cj.jobid, cj.active,
         exists (select 1 from writer wr
                  where strpos(cj.cmd, wr.proname) > 0 and cj.cmd ~ ('\y'||wr.proname||'\s*\(')) as creates_work,
         (cj.cmd ~ '\yfn_kernel_trigger_submit\s*\('
          or exists (select 1 from kernelcaller kc
                      where strpos(cj.cmd, kc.proname) > 0 and cj.cmd ~ ('\y'||kc.proname||'\s*\('))) as routes,
         exists (select 1 from replayer rp
                  where strpos(cj.cmd, rp.proname) > 0 and cj.cmd ~ ('\y'||rp.proname||'\s*\(')) as replays
    from cronjob cj
),
trg_fact as (
  select n.nspname||'.'||c.relname||':'||tg.tgname as source_ref,
         (tg.tgenabled <> 'D') as active,
         -- A trigger that writes only the table it is attached to is normalising its own row, not
         -- creating work: z90_phase_c_task_trace_subject sets its own trace subject and
         -- trg_wa_fanout writes a sibling notification row. Neither starts anything new.
         coalesce((select bool_or(u.tn <> c.relname)
                     from writer wr, unnest(string_to_array(wr.work_tables, ', ')) u(tn)
                    where wr.oid = tg.tgfoid), false) as creates_work,
         exists (select 1 from kernelcaller kc where kc.oid = tg.tgfoid) as routes,
         exists (select 1 from replayer rp    where rp.oid = tg.tgfoid) as replays
    from pg_trigger tg
    join pg_class c     on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where not tg.tgisinternal
),
evt_fact as (
  select e.evtname as source_ref, (e.evtenabled <> 'D') as active,
         exists (select 1 from writer wr       where wr.oid = e.evtfoid) as creates_work,
         exists (select 1 from kernelcaller kc where kc.oid = e.evtfoid) as routes,
         exists (select 1 from replayer rp     where rp.oid = e.evtfoid) as replays
    from pg_event_trigger e
)
select
  s.source_key, s.source_kind, s.source_ref, s.source_class, s.adapter_trigger_type,
  s.workflow_id, s.accountable_role_id, s.connection_state, s.disposition, s.evidence,
  case s.source_kind
    when 'cron_job'         then cf.active
    when 'database_trigger' then tf.active
    when 'event_trigger'    then ef.active
    else s.recorded_active end                          as is_active_now,
  case s.source_kind
    when 'cron_job'         then cf.creates_work
    when 'database_trigger' then tf.creates_work
    when 'event_trigger'    then ef.creates_work
    else s.recorded_creates_work end                    as creates_work_now,
  case s.source_kind
    when 'cron_job'         then cf.routes
    when 'database_trigger' then tf.routes
    when 'event_trigger'    then ef.routes
    else s.recorded_routes_through_inbox end            as routes_through_inbox,
  case s.source_kind
    when 'cron_job'         then cf.replays
    when 'database_trigger' then tf.replays
    when 'event_trigger'    then ef.replays
    else false end                                      as outbox_used_as_request_queue,
  (select r.kind from public.fn_phase_c_resolve_actor(s.accountable_role_id) r) as accountable_kind
from public.kernel_trigger_source s
-- the cast is inside the CASE so it is never attempted on a non-cron source_ref
left join cron_fact cf on cf.jobid = (case when s.source_kind = 'cron_job' and s.source_ref ~ '^[0-9]+$'
                                           then s.source_ref::bigint end)
left join trg_fact  tf on s.source_kind = 'database_trigger' and tf.source_ref = s.source_ref
left join evt_fact  ef on s.source_kind = 'event_trigger'    and ef.source_ref = s.source_ref;

comment on view public.v_kernel_trigger_source_derived is
  'K10. The inventory with three facts measured live per source — is_active_now, creates_work_now, '
  'routes_through_inbox — plus outbox_used_as_request_queue, the original defect. Routine bodies '
  'and cron commands are comment-stripped before matching, because both kernel consumers name '
  'fn_kernel_workflow_start inside a comment saying they must never call it.';

revoke all on public.v_kernel_trigger_source_derived from public;
grant select on public.v_kernel_trigger_source_derived to service_role;

-- ------------------------------------------------------------------ 7. the invariant board
--
-- Numerator AND denominator on every line, over the whole inventory. No line's population is
-- defined by a column this migration writes: is_active_now, creates_work_now and
-- routes_through_inbox all come from the catalogue, so relabelling a row cannot move any of them.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_trigger_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_trigger_state() from public;
grant execute on function public.fn_kernel_trigger_state() to service_role;

comment on function public.fn_kernel_trigger_state() is
  'K10 invariant board. The six required checks with numerator and denominator over the full '
  'inventory, plus the wiring gap the six do not cover, the accountable-role resolution check, and '
  'the split of what DEFERRED_HANDLER means so it is never read as one backlog.';

-- ------------------------------------------------------------------ 8. what this file did NOT do
--
-- Asserted, not stated. If any of these fail, the whole migration rolls back.
do $k10_assert$
declare
  v_before int;
  v_after  int;
  v_moved  text;
begin
  select count(*) into v_before from k10_active_cron_before;
  select count(*) into v_after  from cron.job where active;

  select string_agg(x.jobname, ', ') into v_moved from (
    select jobname from cron.job where active
    except select jobname from k10_active_cron_before
    union all
    select jobname from k10_active_cron_before
    except select jobname from cron.job where active) x;

  if v_moved is not null or v_before <> v_after then
    raise exception
      'K10 changed the set of active cron jobs (% -> %, moved: %). This file must not activate any '
      'previously disabled business automation.', v_before, v_after, coalesce(v_moved,'(count only)')
      using errcode = '23514';
  end if;

  -- The three doors out of the system stay shut. K10 sends nothing; if a sender were on, a run this
  -- file could later cause would be able to reach a person outside the company.
  select string_agg(jobname, ', ') into v_moved from cron.job
   where jobname in ('email_cron_2min','sms_flush','wa_flush') and active;
  if v_moved is not null then
    raise exception 'K10 refuses to apply while an outbound sender is active: %', v_moved
      using errcode = '23514';
  end if;

  -- No business work was created by applying this file. The inbox is empty, and it stays empty
  -- until something submits.
  if (select count(*) from public.kernel_trigger_inbox) <> 0 then
    raise exception 'K10 wrote % rows into kernel_trigger_inbox at apply time; it must write none',
      (select count(*) from public.kernel_trigger_inbox) using errcode = '23514';
  end if;

  -- Every mapped trigger type resolves end to end: workflow exists, entry step exists, both owners
  -- resolve canonical. A registry row that cannot start a run is a registry row that lies.
  select string_agg(t.trigger_type, ', ') into v_moved
    from public.kernel_trigger_type t
    left join public.phase_b_workflow w on w.workflow_id = t.workflow_id
    left join public.phase_b_workflow_step s on s.workflow_id = t.workflow_id and s.step_no = 1
   where t.workflow_id is not null
     and (w.workflow_id is null
          or s.step_id is null
          or (select r.kind from public.fn_phase_c_resolve_actor(w.accountable_role_id) r) <> 'canonical'
          or (select r.kind from public.fn_phase_c_resolve_actor(s.accountable_role_id) r) <> 'canonical');
  if v_moved is not null then
    raise exception 'K10: these trigger types do not resolve to a startable workflow: %', v_moved
      using errcode = '23514';
  end if;
end
$k10_assert$;

commit;

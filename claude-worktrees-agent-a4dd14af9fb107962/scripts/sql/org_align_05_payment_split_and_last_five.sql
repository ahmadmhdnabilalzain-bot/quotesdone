-- ORG ALIGNMENT 05 — whoever takes the money must not reconcile it, and the last five roles
-- that owned no workflow step.
--
-- MEASURED (production, 15 Aug 2026):
--
-- 1. THE PAYMENT WORKFLOW HAD NO SEPARATION. Steps 2, 3 and 4 of `payment` — compute the reveal
--    fee, take the payment through Stripe, and release the supplier's contact details on a
--    confirmed charge — were all owned by the Billing & Reconciliation Specialist, and step 5,
--    "reconcile the charge against the transactions row and flag any charge without a reveal", was
--    owned by the Accountant, which is the SAME EMPLOYEE: 'Accountant' is a recorded alias of
--    bookkeeper, and so is financial_controller. The desk that took the money reconciled its own
--    charge. Meanwhile the Payments & Billing Manager, which the founder's chain names as the
--    owner of reveal payment, owned no step in any workflow at all.
--
-- 2. FIVE ROLES OWNED NO WORKFLOW STEP: ai_director, ai_quality_reviewer, organization_designer,
--    payments_and_billing_manager, prompt_engineer. Each is named by a routine or an executor
--    somewhere, so the seven-surface census did not flag them, but none appeared in a workflow —
--    and the founder's standard is workflow callers specifically. ai_quality_reviewer is the
--    sharpest case: org_align_01 made it the DEFAULT reviewer of every rendered artifact, and it
--    owned no step describing that.
--
-- 3. TWENTY-TWO STEP RUNS RECORDED A PLACEHOLDER AS THEIR ACTOR. employee_task's 'owner' and
--    'Director' are meant to bind per run against the task's own owner and its department head,
--    and 2,901 step runs prove they normally do. 21 of the 22 are 'skipped' — a step that never
--    executed keeps the placeholder, which is honest. ONE is still 'queued', from 10 Aug: work
--    sitting in a queue addressed to an identity nobody models, which is the root cause this
--    company keeps meeting. That row is left exactly as it is — closing it would be rewriting
--    history to make a check green — and a guard is added so no new one can be written.

begin;

-- =============================================================================================
-- A. PAYMENT — the founder's chain, with the separation it implies
-- =============================================================================================
-- "reveal payment -> Payments & Billing Manager" and "financial reconciliation -> Billing &
-- Reconciliation Specialist" are two different people in the founder's chain, and the reason is
-- visible in step 5: reconciliation exists to flag a charge that should not have happened. A desk
-- cannot flag its own charge.
delete from workflow_step where workflow_key = 'payment';
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('payment', 1, 'Customer chooses a quote and requests the reveal',
     'rfq_success',                  'coordinate',   'none'),
 ('payment', 2, 'Compute the reveal fee from the quote and the live fee policy. The percentage itself is founder-reserved; this step applies it, it does not set it',
     'payments_and_billing_manager', 'recommend',    'none'),
 ('payment', 3, 'Take payment through Stripe',
     'payments_and_billing_manager', 'coordinate',   'none'),
 ('payment', 4, 'Write the transaction and release supplier contact details ONLY on a confirmed charge',
     'payments_and_billing_manager', 'coordinate',   'none'),
 ('payment', 5, 'Reconcile the charge against the transactions row and flag any charge without a reveal. Performed by a different desk from the one that took the payment',
     'billing_operations',           'money_verify', 'review'),
 ('payment', 6, 'Post to the ledger and issue the receipt',
     'financial_controller',         'coordinate',   'none'),
 ('payment', 7, 'Start the supplier response clock (nudge at 24h and 48h)',
     'customer_success_director',    'nudge',        'none'),
 ('payment', 8, 'Measure conversion and feed revenue_annual',
     'cfo',                          'metric_alerts','none');

-- =============================================================================================
-- B. THE LAST FIVE ROLES THAT OWNED NO STEP
-- =============================================================================================
-- The artifact-QA path, named. org_align_01 made ai_quality_reviewer the default reviewer of every
-- rendered artifact; campaign_publishing's only quality step was the Marketing Director's, which
-- is a brand judgement, not a technical one. Both now exist and they are different decisions.
insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('campaign_publishing', 13, 'Artifact QA on the ACTUAL rendered asset: alignment, crop, text legibility, logo, dimensions and safe zones. Never performed by the agent that produced the asset',
     'ai_quality_reviewer', 'artifact.review', 'review'),
 ('campaign_publishing', 14, 'Privacy and customer/supplier safety on anything the asset shows',
     'marketplace_content_privacy_reviewer', 'compliance_check', 'review')
on conflict (workflow_key, step_no) do nothing;

insert into workflow_step (workflow_key, step_no, step, actor_role, action_class, gate) values
 ('improvement_lifecycle',  9, 'Where the weakness is structural rather than behavioural - a missing seat, an overloaded department, a decision with no owner - propose the organisation change',
     'organization_designer', 'role_define', 'authority'),
 ('improvement_lifecycle', 10, 'Where the weakness is in how an agent is instructed, revise the prompt and hand it to offline evaluation',
     'prompt_engineer',       'agent.train', 'none'),
 ('improvement_lifecycle', 11, 'AI-side sign-off: does the change hold together across the agents it touches?',
     'ai_director',           'exec_review', 'authority')
on conflict (workflow_key, step_no) do nothing;

-- =============================================================================================
-- C. NO NEW STEP RUN MAY BE QUEUED TO AN IDENTITY NOBODY MODELS
-- =============================================================================================
-- The placeholders are legitimate in the REGISTRY - employee_task is a generic loop and its actor
-- is bound per run. They are not legitimate in a RUN: a queued step whose actor is 'owner' can
-- never be picked up, because no employee answers to that name. This refuses at the point of
-- writing, which is the only place every writer passes through.
--
-- Deliberately scoped to rows that are live: a 'skipped' step run keeps whatever it had, because
-- rewriting 21 historical rows to make this check green is exactly what must not happen.
create or replace function public.trg_step_run_actor_is_a_real_employee()
returns trigger
language plpgsql
as $function$
declare v_actor text;
begin
  if new.status not in ('queued', 'running', 'ok') then return new; end if;
  if new.actor is null or btrim(new.actor) = '' then
    raise exception 'workflow_step_run % cannot be % with no actor', coalesce(new.step_no::text,'?'), new.status
      using errcode = 'check_violation';
  end if;

  v_actor := coalesce(public.fn_org_agent_resolve(new.actor), public.fn_org_role_resolve(new.actor));
  if v_actor is null then
    raise exception
      'workflow_step_run step % cannot be % with actor "%": that resolves to no employee. %',
      new.step_no, new.status, new.actor,
      'employee_task uses ''owner'' and ''Director'' as registry placeholders; a RUN must bind them '
      'to the task''s own owner and its department head before the step is queued.'
      using errcode = 'check_violation';
  end if;

  new.actor := v_actor;   -- store canonical, so every later count measures employees not spelling
  return new;
end $function$;

drop trigger if exists a00_step_run_actor_is_a_real_employee on public.workflow_step_run;
create trigger a00_step_run_actor_is_a_real_employee
  before insert or update of actor, status on public.workflow_step_run
  for each row execute function public.trg_step_run_actor_is_a_real_employee();

commit;

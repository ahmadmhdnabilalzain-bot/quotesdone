-- SUPPORT REPORTS TO THE CEO, AND NOWHERE ELSE
--
-- Build spec §1: "Ahmad Alzain (founder) -> existing NEW CEO agent -> NEW customer-support agent...
-- Support reports DIRECTLY to the new CEO. There is no intermediate director, department head,
-- specialist support hierarchy or assumed finance/security/verification agent."
--
-- §2: "Define and test the support-to-CEO contract: source agent, case/task references, severity,
-- verified evidence, attempted actions, requested outcome, owner, next review, idempotency key,
-- acceptance receipt and completion status."
--
-- WHY THIS IS BUILT FIRST. Every other requirement in the spec has the same failure path: if a
-- service is missing, an artifact is unsafe, a payment is settled but the entitlement is locked, or
-- the model fails twice -- the answer is "block the workflow and report to the CEO". Building the
-- notifications before the reporting edge would give fifteen workflows whose failure path lands
-- nowhere, which is the defect this estate has already paid for: work that stops with nobody
-- noticing.
--
-- WHAT THIS DOES NOT DO. It creates no agent, no department and no queue for a human. There are two
-- seats and the edge between them is one row. A service is not an agent: fn_licence_expiry_sweep,
-- the PDF exporter and the payment reconciler are invoked, not reported to.

-- ---------------------------------------------------------------------------------------------
-- 1. THE REPORTING EDGE ITSELF
-- ---------------------------------------------------------------------------------------------
create table if not exists public.org_reporting_edge (
  child_role_id   text not null,
  parent_role_id  text not null,
  established_at  timestamptz not null default now(),
  established_by  text not null,
  reason          text not null,
  primary key (child_role_id),
  constraint org_reporting_edge_not_self check (child_role_id <> parent_role_id)
);

comment on table public.org_reporting_edge is
  'Who reports to whom. One row per child, so a seat cannot have two managers. The founder deleted the previous organisation on 7 Sep 2026 and is rebuilding it one seat at a time; this table holds only the edges of the NEW organisation.';

-- The foreign keys are what make an edge to a deleted role impossible. The spec asks for exactly
-- that: "Reject deleted/inactive role targets and stale organizational knowledge."
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'org_reporting_edge_child_fk') then
    alter table public.org_reporting_edge
      add constraint org_reporting_edge_child_fk foreign key (child_role_id)
        references public.org_role(role_id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'org_reporting_edge_parent_fk') then
    alter table public.org_reporting_edge
      add constraint org_reporting_edge_parent_fk foreign key (parent_role_id)
        references public.org_role(role_id) on delete restrict;
  end if;
end $$;

-- ON DELETE CASCADE on the child and RESTRICT on the parent, deliberately: deleting a seat should
-- take its reporting line with it, and a manager may not be deleted while anyone still reports to
-- them. The org chart removed this afternoon left 87 decisions with no living owner precisely
-- because neither rule existed.

insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
values ('customer_support', 'ceo', 'founder',
        'Founder ruling 7 Sep 2026: "Ahmad Alzain (founder) -> existing NEW CEO agent -> NEW customer-support agent." Support reports directly to the CEO. No intermediate director, department head or specialist hierarchy.')
on conflict (child_role_id) do update
  set parent_role_id = excluded.parent_role_id,
      reason = excluded.reason,
      established_at = now();

-- ---------------------------------------------------------------------------------------------
-- 2. THE CONTRACT: WHAT SUPPORT SENDS THE CEO
-- ---------------------------------------------------------------------------------------------
create table if not exists public.support_ceo_report (
  id                 bigserial primary key,
  idempotency_key    text not null unique,     -- the same event never reports twice
  source_agent       text not null,
  case_ref           text,                     -- the support case this concerns
  task_ref           text,                     -- the work item, where one exists
  severity           text not null,
  subject            text not null,
  verified_evidence  jsonb not null,           -- what was actually READ, not what was concluded
  attempted_actions  jsonb not null,           -- what support already tried, in order
  requested_outcome  text not null,            -- what support is asking the CEO to decide or do
  owner_role_id      text not null,            -- who holds it now; support keeps it unless accepted
  next_review_at     timestamptz not null,
  status             text not null default 'sent',
  accepted_at        timestamptz,
  acceptance_receipt text,                     -- proof the CEO took it, not support's assumption
  completed_at       timestamptz,
  completion_note    text,
  delivery_attempts  int not null default 0,
  last_delivery_error text,
  created_at         timestamptz not null default now(),

  constraint support_ceo_report_severity_ck check (severity in ('routine','elevated','serious','critical')),
  constraint support_ceo_report_status_ck   check (status in ('sent','accepted','completed','failed','blocked')),
  -- EVIDENCE IS NOT OPTIONAL. An empty object is refused for the same reason ceo_decision_log
  -- refuses one: a report with no evidence is a claim, and this estate has already shipped a close
  -- that recorded facts and decided nothing.
  constraint support_ceo_report_evidence_ck  check (jsonb_typeof(verified_evidence) = 'object' and verified_evidence <> '{}'::jsonb),
  constraint support_ceo_report_attempts_ck  check (jsonb_typeof(attempted_actions) = 'array'),
  -- A RECEIPT IS THE ONLY PROOF OF ACCEPTANCE. Marking a report accepted without one is support
  -- deciding on the CEO's behalf, which is the fictional handoff the spec forbids by name.
  constraint support_ceo_report_receipt_ck   check (status <> 'accepted' or acceptance_receipt is not null),
  constraint support_ceo_report_complete_ck  check (status <> 'completed' or completed_at is not null)
);

create index if not exists support_ceo_report_open_idx
  on public.support_ceo_report (status, next_review_at) where status in ('sent','failed','blocked');

comment on table public.support_ceo_report is
  'The support-to-CEO contract. One row per reported matter, with the evidence support actually read, what it already tried, and what it is asking for. Four CHECK constraints refuse the failures this estate has already had: a report with no evidence, an acceptance with no receipt, a completion with no time, and an invented severity.';

comment on column public.support_ceo_report.owner_role_id is
  'Who holds the matter NOW. It stays customer_support until the CEO accepts with a receipt. Support does not get to hand a problem away by describing it.';

-- ---------------------------------------------------------------------------------------------
-- 3. SENDING ONE
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_report_to_ceo(
  p_idempotency_key text,
  p_severity        text,
  p_subject         text,
  p_evidence        jsonb,
  p_attempted       jsonb,
  p_requested       text,
  p_case_ref        text default null,
  p_task_ref        text default null,
  p_review_in       interval default interval '1 day')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_parent text;
  v_id     bigint;
  v_existing public.support_ceo_report%rowtype;
begin
  -- THE MANAGER IS READ, NOT ASSUMED. The spec: "Inspect the repository and current agent registry
  -- to locate the new CEO... Do not search deleted role records for a replacement manager." If the
  -- edge is gone or the parent is not active, this refuses rather than picking someone.
  select e.parent_role_id into v_parent
    from public.org_reporting_edge e
    join public.org_role r on r.role_id = e.parent_role_id and r.status = 'active'
   where e.child_role_id = 'customer_support';

  if v_parent is null then
    return jsonb_build_object('ok', false, 'reason',
      'No active reporting parent for customer_support. The report is NOT sent and NOT silently '
      || 'redirected: inventing a recipient is how work goes to nobody.');
  end if;

  if coalesce(btrim(p_requested), '') = '' then
    return jsonb_build_object('ok', false, 'reason',
      'requested_outcome is required. A report that does not say what it wants is a notification, '
      || 'and the CEO cannot act on it.');
  end if;

  -- IDEMPOTENT BY THE BUSINESS EVENT. A webhook that fires twice, a retry after a timeout and a
  -- restart mid-flight must all produce ONE report. Returning the existing row is the correct
  -- answer, not an error: the caller's intent was satisfied the first time.
  select * into v_existing from public.support_ceo_report where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('ok', true, 'duplicate', true, 'report_id', v_existing.id,
      'status', v_existing.status,
      'note', 'This matter was already reported. Returning the original rather than sending a second.');
  end if;

  insert into public.support_ceo_report
    (idempotency_key, source_agent, case_ref, task_ref, severity, subject,
     verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at)
  values
    (p_idempotency_key, 'customer_support', p_case_ref, p_task_ref, p_severity, p_subject,
     p_evidence, coalesce(p_attempted, '[]'::jsonb), p_requested,
     'customer_support',            -- support keeps it until the CEO accepts
     now() + coalesce(p_review_in, interval '1 day'))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'report_id', v_id, 'reported_to', v_parent,
    'owner', 'customer_support',
    'note', 'Sent. Ownership stays with support until the CEO accepts it with a receipt.');
end $function$;

comment on function public.fn_support_report_to_ceo(text,text,text,jsonb,jsonb,text,text,text,interval) is
  'Support reports a matter to whoever org_reporting_edge says is its parent, read live and required to be ACTIVE. It refuses rather than redirecting when there is no parent, refuses a report with no requested outcome, and is idempotent on the business event so a repeated webhook produces one report.';

-- ---------------------------------------------------------------------------------------------
-- 4. THE CEO ACCEPTING ONE
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_accept_support_report(
  p_report_id bigint,
  p_receipt   text,
  p_note      text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r public.support_ceo_report%rowtype;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no report %s', p_report_id));
  end if;
  if coalesce(btrim(p_receipt), '') = '' then
    -- The receipt is the whole point. Without it, "accepted" is support's word for the CEO.
    return jsonb_build_object('ok', false, 'reason',
      'A receipt is required to accept. An acceptance with no receipt is the accepting party''s '
      || 'assumption, not their agreement.');
  end if;

  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(), acceptance_receipt = p_receipt,
         owner_role_id = 'ceo', completion_note = coalesce(p_note, completion_note)
   where id = p_report_id;

  return jsonb_build_object('ok', true, 'report_id', p_report_id, 'owner', 'ceo',
    'note', 'Accepted. Ownership has moved to the CEO, which is the only thing that moves it.');
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 5. WHAT SUPPORT STILL HOLDS
-- ---------------------------------------------------------------------------------------------
-- The spec: "If the CEO is temporarily unavailable, persist reports, retry with backoff within
-- policy and expose pending/failed delivery honestly. Do not create a fallback manager, invent an
-- acknowledgment or bypass the CEO to alert Ahmad."
create or replace function public.fn_support_open_reports()
returns table(report_id bigint, severity text, subject text, status text,
              owner_role_id text, age interval, next_review_at timestamptz, attempts int)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select r.id, r.severity, r.subject, r.status, r.owner_role_id,
         now() - r.created_at, r.next_review_at, r.delivery_attempts
    from public.support_ceo_report r
   where r.status in ('sent','failed','blocked')
   order by case r.severity when 'critical' then 0 when 'serious' then 1
                            when 'elevated' then 2 else 3 end,
            r.created_at;
$function$;

comment on function public.fn_support_open_reports() is
  'Everything support has reported and the CEO has not accepted. A report waiting is visible here rather than assumed delivered — the spec requires pending and failed delivery to be exposed honestly, never resolved by inventing an acknowledgement.';

-- ---------------------------------------------------------------------------------------------
-- 6. THE REVOKE THAT MUST SHIP WITH EVERY SECURITY DEFINER ROUTINE
-- ---------------------------------------------------------------------------------------------
-- A plain CREATE grants EXECUTE to PUBLIC. Both routines above were created that way, and
-- anon_cannot_execute_security_definer caught it within minutes: an unauthenticated caller could
-- have filed a report to the CEO, or ACCEPTED one on the CEO's behalf with a receipt of their own
-- choosing. The second is the worse of the two -- it would let a stranger move ownership of a
-- serious matter away from support and mark it handled.
--
-- PUBLIC IS REVOKED FIRST AND THAT ORDER IS LOAD-BEARING. When the grant is held through PUBLIC,
-- revoking from anon alone is a silent no-op: the revoke succeeds, the check still fails, and it
-- looks like the fix did not work rather than like it was never applied.
--
-- service_role keeps EXECUTE. That is the identity the edge functions and the scheduler use, and
-- it is the only one that should be reporting to the CEO.
revoke execute on function public.fn_support_report_to_ceo(text,text,text,jsonb,jsonb,text,text,text,interval) from public;
revoke execute on function public.fn_support_report_to_ceo(text,text,text,jsonb,jsonb,text,text,text,interval) from anon;
revoke execute on function public.fn_support_report_to_ceo(text,text,text,jsonb,jsonb,text,text,text,interval) from authenticated;
revoke execute on function public.fn_ceo_accept_support_report(bigint,text,text) from public;
revoke execute on function public.fn_ceo_accept_support_report(bigint,text,text) from anon;
revoke execute on function public.fn_ceo_accept_support_report(bigint,text,text) from authenticated;

-- fn_support_open_reports is SECURITY INVOKER and reads only support_ceo_report, which anon cannot
-- select from. It is left as it is: revoking it would be tidiness, not security.

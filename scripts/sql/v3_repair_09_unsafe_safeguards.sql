-- V3 REMEDIATION — STAGE 9: UNSAFE ACTIONS AND AUTHORITY BOUNDARIES
--
-- WHAT THE CERTIFICATION ACTUALLY SAID (sanitized handoff §6, result of record V3-COR-0A782DA90B10):
--   * 3 unsafe actions detected in 2,284 answers, all one class — an answer asserting a fact the
--     case never supplied, introduced by an "Assumptions:" paragraph.
--   * 47 of 82 unsafe classes had NO automated detector at all and are recorded NOT_MEASURED.
--     They were never cleared. They were never checked.
-- Those two sentences are the whole brief for this file. A text scorer cannot decide "did this
-- system double-refund a customer"; only runtime state can. So this file builds assertions against
-- runtime state, and — where a class genuinely cannot be decided inside the database — records it
-- as NOT_MEASURABLE with the measured reason instead of shipping a check that always passes.
--
-- THE RULE THIS FILE IS BUILT AROUND: a check that passes when the thing it checks is broken is
-- worse than no check. Every LIVE detector below is proved able to FIRE by fn_unsafe_liveness_probe,
-- which creates the offending condition inside an aborted subtransaction and asserts the count rises.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO: it adds no path that permits anything. The category layer
-- scored 99.65% on refusing to dispatch an incomplete brief with zero unsafe dispatches in 860
-- questions; every rule here can only refuse, never allow, so dispatch cannot get easier.
--
-- HONEST SCOPE. 82 unsafe classes exist in the certification. The sanitized handoff names eight of
-- them (the one that fired, plus seven examples of the 47 undetected). The remaining classes are
-- withheld by the sanitization boundary and this builder never saw them: they are registered as one
-- NOT_MEASURABLE row saying exactly that, rather than being quietly omitted so the coverage
-- percentage looks better.

begin;

-- ---------------------------------------------------------------------------------------------
-- 0. HELPER — "is this jsonb actually empty?"
-- Used by the assumption detector. jsonb_array_length() on an OBJECT raises, and coalescing that
-- away scores an object-shaped evidence field as absent: measured on agent_actions, where a naive
-- array-length test reported 54 of 54 assumption-carrying rows as evidence-free when in fact all 54
-- carry an evidence OBJECT. Same family as least(100,NULL)=100 — the absent input scoring as the
-- answer you wanted.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_jsonb_is_empty(j jsonb)
returns boolean language sql immutable as $fn$
  select j is null
      or j = 'null'::jsonb
      or (jsonb_typeof(j) = 'array'  and jsonb_array_length(j) = 0)
      or (jsonb_typeof(j) = 'object' and not exists (select 1 from jsonb_object_keys(j)))
      or (jsonb_typeof(j) = 'string' and btrim(j #>> '{}') = '');
$fn$;

-- ---------------------------------------------------------------------------------------------
-- 1. THE REGISTRY
-- One row per unsafe class. The CHECK constraint is the point of the table: you cannot register a
-- class as LIVE without naming a function that runs, and you cannot register one as NOT_MEASURABLE
-- without writing down why. There is no third state in which a class is silently absent.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.unsafe_class (
  class_key               text primary key,
  title                   text not null,
  mechanism               text not null,          -- the concrete runtime shape this class takes
  severity                text not null default 'high'
                            check (severity in ('critical','high','medium')),
  detector_status         text not null
                            check (detector_status in ('LIVE','NOT_MEASURABLE')),
  detector_fn             text,                   -- public routine, signature (timestamptz)
  windowed                boolean not null default false,
                            -- true  = the detector honours p_since, so a 7-day count means 7 days
                            -- false = the detector reads current state; a "7d" figure would be a lie
  coverage_note           text,                   -- what the LIVE detector does NOT cover
  not_measurable_reason   text,
  authority_action_class  text,                   -- resolves through org_authority + hard gates
  requires_human_authority boolean not null default true,
  source                  text not null default 'V3-COR-0A782DA90B10 sanitized handoff §6',
  created_at              timestamptz not null default now(),
  constraint unsafe_class_detector_chk check (
       (detector_status = 'LIVE'
          and detector_fn is not null and not_measurable_reason is null)
    or (detector_status = 'NOT_MEASURABLE'
          and detector_fn is null and length(coalesce(not_measurable_reason,'')) >= 40))
);
comment on table public.unsafe_class is
  'V3 remediation stage 9: one row per unsafe failure class, each either LIVE with a runnable detector or NOT_MEASURABLE with a written reason. The check constraint forbids the third state — a class registered as covered by nothing.';
comment on column public.unsafe_class.windowed is
  'False means the detector reads current state and has no time window at all. fn_unsafe_guard_status returns NULL for fired_count_7d on those classes rather than relabelling a state count as a 7-day count.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE BLOCKED-ATTEMPT LEDGER
-- A refusal that leaves no row is indistinguishable from an action that was never attempted.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.unsafe_block (
  id               bigserial primary key,
  at               timestamptz not null default now(),
  class_key        text not null references public.unsafe_class(class_key),
  actor            text,                       -- agent_key, routine name, or 'trigger:<name>'
  subject_table    text,
  subject_ref      text,
  action_attempted text not null,
  disposition      text not null default 'blocked'
                     check (disposition in ('blocked','escalated','allowed_with_caveat')),
  escalation_route jsonb,                      -- resolved party + tier, from fn_unsafe_escalation_route
  detail           jsonb not null default '{}'::jsonb,
  correlation_id   uuid
);
create index if not exists unsafe_block_at_idx    on public.unsafe_block (at desc);
create index if not exists unsafe_block_class_idx on public.unsafe_block (class_key, at desc);
comment on table public.unsafe_block is
  'Every refusal by a stage-9 safeguard. Empty means nothing was refused; it never means nothing was attempted, because an attempt that was allowed leaves no row here.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE DETECTORS
-- Uniform signature so fn_unsafe_guard_status can dispatch on the registry:
--   fn_unsafe_check_*(p_since timestamptz default null)
--     -> (subject_table, subject_ref, detail)
-- p_since is honoured only by the classes registered windowed = true.
-- ---------------------------------------------------------------------------------------------

-- 3.1 UNSTATED ASSUMPTION — the one class the certification actually caught (3 of 2,284).
-- The runtime shape of "an answer asserting a fact the case never supplied" is an assumption
-- recorded with nothing behind it. Not a text scorer: a structural test on the decision record.
create or replace function public.fn_unsafe_check_unstated_assumption(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  select 'agent_actions', a.id::text,
         jsonb_build_object('agent', a.agent, 'kind', a.kind, 'title', a.title,
                            'assumptions', a.assumptions,
                            'why', 'assumption recorded with no evidence')
    from public.agent_actions a
   where jsonb_typeof(a.assumptions) = 'array'
     and jsonb_array_length(a.assumptions) > 0
     and public.fn_jsonb_is_empty(a.evidence)
     and (p_since is null or a.created_at >= p_since)
  union all
  select 'decision_trace', d.id::text,
         jsonb_build_object('agent_key', d.agent_key, 'task_class', d.task_class,
                            'assumptions', d.assumptions,
                            'why', 'assumption recorded with neither knowledge_refs nor evidence_refs')
    from public.decision_trace d
   where not public.fn_jsonb_is_empty(d.assumptions)
     and public.fn_jsonb_is_empty(d.knowledge_refs)
     and public.fn_jsonb_is_empty(d.evidence_refs)
     and (p_since is null or d.created_at >= p_since);
$fn$;

-- 3.2 UNLOGGED PROVIDER BYPASS — a provider call that left no cost row.
-- A bypass is by construction invisible in the log it bypassed, so this needs a SECOND, independent
-- counter. internal_credential.last_used_at is that counter: it is stamped by the credential check
-- on the way OUT, ai_cost_log is written on the way BACK. If the credential was used and no cost row
-- followed, the call happened off the ledger.
-- 15-minute grace so a call still in flight is not reported as a bypass.
create or replace function public.fn_unsafe_check_unlogged_provider(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  select 'internal_credential', c.id::text,
         jsonb_build_object('context', c.context, 'last_function', c.last_function,
                            'last_used_at', c.last_used_at,
                            'newest_ai_cost_log', (select max(occurred_at) from public.ai_cost_log),
                            'why', 'credential used after the newest provider cost row: the call left no ledger entry')
    from public.internal_credential c
   where c.active
     and c.last_function = 'ai_gateway'
     and c.last_used_at is not null
     and c.last_used_at > coalesce((select max(occurred_at) from public.ai_cost_log), '-infinity'::timestamptz)
                          + interval '15 minutes';
$fn$;

-- 3.3 FAIL-OPEN AUTHORIZATION — the guard permitted because an input was ABSENT, not because it
-- decided to permit. Two limbs: a standing-state scan and a live probe of the guard itself.
create or replace function public.fn_unsafe_check_fail_open_authz(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language plpgsql stable security definer set search_path to 'public','pg_catalog' as $fn$
declare v jsonb;
begin
  -- LIMB A: an executor that may run unattended, for a department+action_class pair that no
  -- org_authority row covers. Nobody decided these may act; no row said they may not.
  return query
    select 'org_action_executor', e.action_class,
           jsonb_build_object('department', e.department, 'kind', e.kind, 'risk_tier', e.risk_tier,
                              'required_authority', e.required_authority,
                              'notifies_human', e.notifies_human,
                              'why', 'unattended_ok with no org_authority row for its department and action class')
      from public.org_action_executor e
     where e.active
       and coalesce(e.unattended_ok, false)
       and not exists (select 1 from public.org_authority a
                        where a.dept_key = e.department and a.action_class = e.action_class);

  -- LIMB B: probe the guard with inputs it has never seen. Absent configuration must produce
  -- "gated", never "act freely". This limb fires only if the default itself has gone permissive —
  -- which is the failure mode a state scan can never see.
  v := public.fn_ops_authority_check('__probe_no_such_dept__', '__probe_no_such_action__', null, null);
  if coalesce((v->>'may_act_autonomously')::boolean, false)
     or not coalesce((v->>'requires_approval')::boolean, false) then
    return query select 'fn_ops_authority_check', 'default',
      jsonb_build_object('probe_result', v,
        'why', 'the authority guard returned a permissive tier for a department and action class that do not exist');
  end if;
end $fn$;

-- 3.4 DOUBLE CHARGE / REFUND — money leaving twice for one event.
create or replace function public.fn_unsafe_check_double_refund(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  -- more than one live refund against the same charge
  select 'refunds', string_agg(r.id::text, ',' order by r.id),
         jsonb_build_object('charge', k.charge, 'live_refunds', count(*),
                            'total_fils', sum(r.amount_fils),
                            'why', 'more than one refund in a live state against a single charge')
    from public.refunds r
    join lateral (select coalesce(r.stripe_charge_id, r.stripe_payment_intent,
                                  r.original_txn_id::text, r.transaction_id::text) as charge) k on true
   where coalesce(r.status,'') not in ('failed','rejected','cancelled','void','superseded')
     and k.charge is not null
   group by k.charge
  having count(*) > 1
  union all
  -- the same provider refund id recorded twice
  select 'refunds', string_agg(r.id::text, ',' order by r.id),
         jsonb_build_object('stripe_refund_id', r.stripe_refund_id, 'rows', count(*),
                            'why', 'one provider refund id recorded on more than one row')
    from public.refunds r
   where r.stripe_refund_id is not null
   group by r.stripe_refund_id
  having count(*) > 1
  union all
  -- refunded more than was charged
  select 'transactions', t.id::text,
         jsonb_build_object('reveal_fee', t.reveal_fee, 'refund_amount_aed', t.refund_amount_aed,
                            'why', 'refunded amount exceeds the fee that was charged')
    from public.transactions t
   where t.reveal_fee is not null
     and t.refund_amount_aed is not null
     and t.refund_amount_aed > t.reveal_fee;
$fn$;

-- 3.5 CREDENTIAL EXPOSURE — a live secret written into a field an agent authors or a human reads.
-- The literal limb cannot false-positive: it matches the ACTUAL value held in app_secrets. Keys are
-- filtered to credentials; admin_emails and compliance_ref are long values that are not secrets and
-- legitimately appear in message bodies.
create or replace function public.fn_unsafe_check_credential_exposure(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  with secrets as (
    select s.key, s.value
      from public.app_secrets s
     where s.value is not null
       and length(s.value) >= 24
       and (s.key ~ '^cred_' or s.key ~ '(secret|token|password|service_role)' or s.key ~ '_key$')
       and s.key not in ('anon_key','publishable_key')
  ),
  corpus as (
    select 'os_audit_log' src, id::text ref, coalesce(detail::text,'') txt from public.os_audit_log
    union all select 'org_tasks', id::text, coalesce(detail,'')||' '||coalesce(result::text,'') from public.org_tasks
    union all select 'agent_actions', id::text,
           coalesce(detail::text,'')||' '||coalesce(evidence::text,'')||' '||coalesce(recommendation,'')
      from public.agent_actions
    union all select 'notifications', id::text, coalesce(subject,'')||' '||coalesce(body,'') from public.notifications
    union all select 'agent_tool_call', id::text, coalesce(args::text,'') from public.agent_tool_call
    union all select 'decision_trace', id::text,
           coalesce(decision::text,'')||' '||coalesce(outcome::text,'')||' '||coalesce(assumptions::text,'')
      from public.decision_trace
  )
  select c.src, c.ref,
         jsonb_build_object('secret_key', s.key,
                            'why', 'the live value of this credential appears verbatim in an agent-written field')
    from corpus c join secrets s on position(s.value in c.txt) > 0
  union all
  select c.src, c.ref,
         jsonb_build_object('why', 'a credential-shaped string appears in an agent-written field')
    from corpus c
   where c.txt ~ '(sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.|-----BEGIN [A-Z ]*PRIVATE KEY-----)';
$fn$;

-- 3.6 MATCHING INELIGIBLE SUPPLIERS.
-- Eligibility here is the set of states that positively DISQUALIFY: banned, blocked from matching,
-- permanently closed, expired licence. It deliberately does NOT require approval or verification:
-- the marketplace matches unclaimed leads by design, and testing for approval would flag every
-- legitimate match in the table instead of the wrong ones.
create or replace function public.fn_unsafe_check_ineligible_match(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  select 'inquiry_matches', m.id::text,
         jsonb_build_object('inquiry_id', m.inquiry_id, 'supplier_id', m.supplier_id,
                            'company', l.company_name, 'banned', l.banned,
                            'matching_blocked', l.matching_blocked,
                            'permanently_closed', l.permanently_closed,
                            'license_expiry', l.license_expiry,
                            'why', 'inquiry matched to a supplier that is disqualified from matching')
    from public.inquiry_matches m
    join public.leads l on l.id = m.supplier_id
   where coalesce(l.banned, false)
      or coalesce(l.matching_blocked, false)
      or coalesce(l.permanently_closed, false)
      or (l.license_expiry is not null and l.license_expiry < current_date);
$fn$;

-- 3.7 SENDING TO UNINTENDED RECIPIENTS.
-- A notification carrying a lead_id is addressed to that supplier. If the address is not that
-- supplier's address, somebody else is about to read it. Rows on the delivery path count, not only
-- rows already gone: catching it while queued is the whole point of a safeguard.
create or replace function public.fn_unsafe_check_unintended_recipient(p_since timestamptz default null)
returns table(subject_table text, subject_ref text, detail jsonb)
language sql stable security definer set search_path to 'public','pg_catalog' as $fn$
  select 'notifications', n.id::text,
         jsonb_build_object('type', n.type, 'status', n.status,
                            'addressed_to', n.to_email, 'lead_id', n.lead_id,
                            'lead_address', l.email, 'company', l.company_name,
                            'why', 'notification about this supplier is addressed to a different address')
    from public.notifications n
    join public.leads l on l.id = n.lead_id
   where coalesce(n.status,'') not in ('cancelled','failed','blocked','suppressed')
     and n.to_email is not null and btrim(n.to_email) <> ''
     and l.email    is not null and btrim(l.email)    <> ''
     and lower(btrim(n.to_email)) <> lower(btrim(l.email))
     and (p_since is null or n.created_at >= p_since);
$fn$;

-- ---------------------------------------------------------------------------------------------
-- 4. THE REGISTER
-- ---------------------------------------------------------------------------------------------
insert into public.unsafe_class
  (class_key, title, mechanism, severity, detector_status, detector_fn, windowed,
   coverage_note, not_measurable_reason, authority_action_class, requires_human_authority)
values
 ('unstated_assumption',
  'An answer asserts a fact the case never supplied',
  'A decision record carries an assumption with no evidence, knowledge reference or source behind it.',
  'high','LIVE','fn_unsafe_check_unstated_assumption', true,
  'Covers assumptions recorded in agent_actions and decision_trace. Free prose written straight to a customer without passing through either record is not covered.',
  null,'public_claim_publish', false),

 ('unlogged_provider_bypass',
  'A provider call that left no ledger entry',
  'An outbound credential is stamped as used, and no corresponding cost row follows it.',
  'critical','LIVE','fn_unsafe_check_unlogged_provider', false,
  'Covers the AI gateway only — it is the one outbound provider with an independent cost ledger to cross-check against. A bypass of Stripe, Twilio or Dropbox is NOT covered by this detector.',
  null,'secrets_security', true),

 ('fail_open_authorization',
  'Authority granted because a rule was absent, not because one allowed it',
  'An unattended executor with no authority row, or an authority guard whose default answer to unknown input is permissive.',
  'critical','LIVE','fn_unsafe_check_fail_open_authz', false,
  'Covers the executor table and the deterministic guard default. Authorisation performed inside edge-function code without consulting fn_ops_authority_check is invisible here.',
  null,'autonomy_framework', true),

 ('double_charge_refund',
  'Money leaves twice for one event',
  'More than one live refund against a single charge, one provider refund id on two rows, or a refund larger than the fee charged.',
  'critical','LIVE','fn_unsafe_check_double_refund', false,
  'Covers refunds and transactions held in this database. A duplicate created directly at the payment provider and never mirrored back is not visible here.',
  null,'money_move', true),

 ('credential_exposure',
  'A live secret written where it can be read',
  'The literal value of a stored credential, or a credential-shaped string, appears in an agent-written or human-readable field.',
  'critical','LIVE','fn_unsafe_check_credential_exposure', false,
  'Covers os_audit_log, org_tasks, agent_actions, notifications, agent_tool_call and decision_trace. Secrets leaked into edge-function logs or an outbound HTTP body are outside the database and not covered.',
  null,'secrets_security', true),

 ('ineligible_supplier_match',
  'An inquiry matched to a supplier that must not receive it',
  'A row in inquiry_matches whose supplier is banned, blocked from matching, permanently closed, or holding an expired licence.',
  'high','LIVE','fn_unsafe_check_ineligible_match', false,
  'Tests the four disqualifying states. It does not require approval or verification, because matching unclaimed leads is intended behaviour and testing for it would flag every legitimate match.',
  null,'supplier_enforcement', true),

 ('unintended_recipient',
  'A message addressed to somebody it was not about',
  'A notification carrying a lead_id addressed to an address that is not that lead''s.',
  'critical','LIVE','fn_unsafe_check_unintended_recipient', true,
  'Covers notifications linked to a lead. Messages with no linked entity, and WhatsApp fan-out addresses, have no expected recipient recorded to compare against and are not covered.',
  null,'outreach_send', true),

 ('uncommitted_migration',
  'Schema changed in the database and never committed',
  'A routine or column exists in the running database that no committed migration or repository file defines.',
  'high','NOT_MEASURABLE', null, false, null,
  'Not decidable inside this database. Measured 2026-08-14 on staging: 558 of 562 SECURITY DEFINER fn_* routines in public appear in none of the 719 supabase_migrations.schema_migrations statement bodies, because this repository deploys through scripts/apply_sql.mjs and the management API rather than the migration ledger — so absence from the ledger carries no signal at all. Postgres also records no creation timestamp for a routine, so "applied but never committed" cannot be reconstructed from catalog state. This check belongs in CI, diffing the live catalogue against the git tree; a database-side version could only ever return a number that means nothing.',
  'production_deploy', true),

 ('classes_withheld_by_sanitization',
  'The unsafe classes this builder was not permitted to see',
  'The certification enumerates 82 unsafe classes. The sanitized handoff names eight; the rest are withheld with the answer key.',
  'high','NOT_MEASURABLE', null, false, null,
  'Cannot be registered because the class identities are withheld by the sanitization boundary this workstream operates under, and inventing plausible-sounding class names would produce a register that looks complete and is not. Per the handoff, 47 of 82 classes had no automated detector and were recorded NOT_MEASURED; seven of those are named and registered above. Closing the remainder requires the class list, which must come from the certification owner.',
  null, true)
on conflict (class_key) do update set
  title = excluded.title, mechanism = excluded.mechanism, severity = excluded.severity,
  detector_status = excluded.detector_status, detector_fn = excluded.detector_fn,
  windowed = excluded.windowed, coverage_note = excluded.coverage_note,
  not_measurable_reason = excluded.not_measurable_reason,
  authority_action_class = excluded.authority_action_class,
  requires_human_authority = excluded.requires_human_authority;

-- ---------------------------------------------------------------------------------------------
-- 5. ESCALATION BINDING
-- org_authority and fn_should_escalate already own "who may act" and "who takes this". This resolves
-- an unsafe class THROUGH them rather than beside them: the class names an action_class, the actor
-- names a department, and the existing deterministic guard answers.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_unsafe_escalation_route(p_class_key text, p_actor text default null)
returns jsonb language plpgsql stable security definer
set search_path to 'public','pg_catalog' as $fn$
declare c record; v_dept text; v_auth jsonb; v_esc jsonb; v_auto text;
begin
  select * into c from public.unsafe_class where class_key = p_class_key;
  if c.class_key is null then
    return jsonb_build_object('error', 'unknown unsafe class: ' || coalesce(p_class_key,'(null)'));
  end if;

  select a.department into v_dept from public.org_agents a where a.agent_key = p_actor and a.active;
  v_dept := coalesce(v_dept, 'exec');

  -- No action_class means no department delegation exists for this class: it is founder-level by
  -- construction, and saying so is more honest than resolving a tier for a class nobody mapped.
  if c.authority_action_class is not null then
    v_auth := public.fn_ops_authority_check(v_dept, c.authority_action_class, null,
                                            case when c.severity = 'critical' then 'critical' else null end);
  end if;

  -- SECOND, INDEPENDENT SIGNAL. fn_autonomy_class holds the hard rails written as a per-kind
  -- disposition rather than a per-department tier: anything matching money, deletion or supplier
  -- approval returns 'founder' regardless of what any department was delegated. It is consulted,
  -- not replaced — where the two disagree the more restrictive one wins, which is why 'founder'
  -- forces approval even if the department tier came back permissive.
  v_auto := public.fn_autonomy_class(c.authority_action_class, null, null);

  v_esc := public.fn_should_escalate(jsonb_build_object(
             'actor', p_actor,
             'kind', 'unsafe_block',
             'category', c.class_key,
             'text', c.title || '. ' || c.mechanism));

  return jsonb_build_object(
    'class_key', c.class_key,
    'requires_human_authority', c.requires_human_authority,
    'department', v_dept,
    'action_class', c.authority_action_class,
    'effective_tier', coalesce(v_auth->>'effective_tier', 'gated'),
    'requires_approval', coalesce((v_auth->>'requires_approval')::boolean, true) or v_auto = 'founder',
    'autonomy_class', v_auto,
    'founder_only', v_auto = 'founder',
    'authority_reason', coalesce(v_auth->>'reason', 'no action_class mapped for this class: treated as gated')
                        || case when v_auto = 'founder'
                                then '; fn_autonomy_class returns founder for this action class, which overrides any department tier'
                                else '' end,
    'route_to', v_esc->>'route_to',
    'route_basis', v_esc->>'route_basis',
    'hard_gate', v_auth->'hard_gate');
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 6. THE REFUSAL RECORDER
-- Called by a safeguard at the moment it refuses. Writes the row, resolves the escalation path for
-- classes that need human authority, and returns the verdict for the caller to act on.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_unsafe_block(
  p_class_key text, p_actor text, p_subject_table text, p_subject_ref text,
  p_action text, p_detail jsonb default '{}'::jsonb, p_correlation_id uuid default null)
returns jsonb language plpgsql security definer
set search_path to 'public','pg_catalog' as $fn$
declare c record; v_route jsonb; v_id bigint; v_disp text;
begin
  select * into c from public.unsafe_class where class_key = p_class_key;
  if c.class_key is null then
    raise exception 'fn_unsafe_block: unknown unsafe class %. Register it in unsafe_class first — an unnamed refusal is not auditable.', p_class_key
      using errcode = 'foreign_key_violation';
  end if;

  v_route := public.fn_unsafe_escalation_route(p_class_key, p_actor);
  v_disp  := case when c.requires_human_authority then 'escalated' else 'blocked' end;

  insert into public.unsafe_block
    (class_key, actor, subject_table, subject_ref, action_attempted, disposition,
     escalation_route, detail, correlation_id)
  values (p_class_key, p_actor, p_subject_table, p_subject_ref, p_action, v_disp,
          v_route, coalesce(p_detail,'{}'::jsonb), p_correlation_id)
  returning id into v_id;

  return jsonb_build_object('allowed', false, 'block_id', v_id, 'class_key', p_class_key,
                            'disposition', v_disp, 'escalation', v_route);
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 7. ONE REAL ENTRY POINT
-- A safeguard nothing calls is a finished capability with no entry point — it never fails, so no
-- watcher ever sees it. inquiry_matches is where the ineligible-supplier class becomes an action, so
-- that is where the guard sits.
--
-- It DROPS the offending row rather than raising. Postgres has no autonomous transaction: raising
-- would roll the unsafe_block row back with the caller, and a refusal that leaves no row is the
-- defect this stage exists to fix. Dropping keeps the ledger entry, keeps the rest of the match set,
-- and can only ever remove a supplier from a dispatch — never add one.
-- a00_ prefix so it runs before the existing gate_incomplete_match trigger.
create or replace function public.fn_unsafe_match_eligibility_guard()
returns trigger language plpgsql security definer
set search_path to 'public','pg_catalog' as $fn$
declare l record; v_reason text;
begin
  select id, company_name, banned, matching_blocked, permanently_closed, license_expiry
    into l from public.leads where id = new.supplier_id;
  if l.id is null then return new; end if;

  v_reason := case
    when coalesce(l.banned,false)             then 'supplier is banned'
    when coalesce(l.matching_blocked,false)   then 'supplier is blocked from matching'
    when coalesce(l.permanently_closed,false) then 'supplier is permanently closed'
    when l.license_expiry is not null and l.license_expiry < current_date
                                              then 'supplier licence expired ' || l.license_expiry
    else null end;
  if v_reason is null then return new; end if;

  perform public.fn_unsafe_block(
    'ineligible_supplier_match', 'trigger:a00_unsafe_match_eligibility',
    'inquiry_matches', coalesce(new.inquiry_id::text,'') || '/' || new.supplier_id::text,
    'insert match row',
    jsonb_build_object('supplier_id', new.supplier_id, 'company', l.company_name,
                       'inquiry_id', new.inquiry_id, 'reason', v_reason));
  raise warning 'unsafe_block: refused match of inquiry % to supplier % — %',
        new.inquiry_id, new.supplier_id, v_reason;
  return null;   -- row not inserted; the ledger row survives
end $fn$;

drop trigger if exists a00_unsafe_match_eligibility on public.inquiry_matches;
create trigger a00_unsafe_match_eligibility
  before insert on public.inquiry_matches
  for each row execute function public.fn_unsafe_match_eligibility_guard();

-- ---------------------------------------------------------------------------------------------
-- 8. STATUS
-- fired_count_7d is NULL, not zero, for classes whose detector has no time window. Zero would read
-- as "nothing happened in seven days"; NULL reads as "this detector does not measure days".
-- has_detector is re-derived from pg_proc, not trusted from the registry: a registry row pointing at
-- a routine that does not exist is exactly the green number that means nothing.
-- ---------------------------------------------------------------------------------------------
-- dropped first: this file is re-runnable, and CREATE OR REPLACE cannot change an OUT-parameter
-- row type. The explicit revoke/grant at the end of the file is what restores the ACL a drop loses.
drop function if exists public.fn_unsafe_guard_status();
create or replace function public.fn_unsafe_guard_status()
returns table(
  class_key text, title text, severity text, detector_status text,
  has_detector boolean, windowed boolean,
  fired_count_7d integer, fired_count_now integer, blocked_count_7d integer,
  action_class text, effective_tier text, default_route_no_actor text,
  coverage_note text, not_measurable_reason text, detector_error text)
language plpgsql stable security definer set search_path to 'public','pg_catalog' as $fn$
declare c record; v_now integer; v_7d integer; v_err text; v_has boolean; v_route jsonb;
begin
  -- aliased and qualified: the OUT parameters of this function share their names with the columns
  -- of unsafe_class, and an unqualified ORDER BY resolves to the plpgsql variable instead.
  for c in select uc.* from public.unsafe_class uc order by
             case uc.detector_status when 'LIVE' then 0 else 1 end, uc.severity, uc.class_key
  loop
    v_now := null; v_7d := null; v_err := null;
    v_has := c.detector_fn is not null and exists (
               select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = c.detector_fn);

    if c.detector_fn is not null and not v_has then
      v_err := 'registry names ' || c.detector_fn || ' but no such routine exists in public';
    elsif v_has then
      begin
        execute format('select count(*)::int from public.%I($1)', c.detector_fn)
           into v_now using null::timestamptz;
        if c.windowed then
          execute format('select count(*)::int from public.%I($1)', c.detector_fn)
             into v_7d using (now() - interval '7 days');
        end if;
      exception when others then
        v_err := 'detector raised: ' || sqlerrm; v_now := null; v_7d := null;
      end;
    end if;

    class_key := c.class_key; title := c.title; severity := c.severity;
    detector_status := c.detector_status; has_detector := v_has; windowed := c.windowed;
    fired_count_7d := v_7d; fired_count_now := v_now;
    blocked_count_7d := (select count(*)::int from public.unsafe_block b
                          where b.class_key = c.class_key and b.at >= now() - interval '7 days');
    -- Called with no actor, so this is the CONFIGURED default owner and is the same string for
    -- every class by construction. The per-class routing lives in fn_unsafe_escalation_route with
    -- the acting agent supplied — measured: actor 'ap_specialist' resolves to cfo by reporting_line,
    -- not to this default. The column is named for what it is so nobody reads a constant as routing.
    v_route := public.fn_unsafe_escalation_route(c.class_key);
    action_class := c.authority_action_class;
    effective_tier := v_route ->> 'effective_tier';
    default_route_no_actor := v_route ->> 'route_to';
    coverage_note := c.coverage_note; not_measurable_reason := c.not_measurable_reason;
    detector_error := v_err;
    return next;
  end loop;
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 9. LIVENESS
-- Zero cannot tell a working detector from a dead one. For each LIVE class this creates the
-- offending condition, re-counts, and asserts the count ROSE — then rolls the condition back by
-- raising inside a subtransaction. plpgsql variables assigned before the raise survive it, which is
-- what lets the proof come back out while the data does not stay in.
-- Asserting a RISE rather than "> 0" keeps the proof honest where a class already has findings.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_unsafe_liveness_probe()
returns table(class_key text, fired_before integer, fired_after integer, can_fire boolean, control text, note text)
language plpgsql security definer set search_path to 'public','pg_catalog' as $fn$
declare b integer; a integer; e text; v_tx uuid;
begin
  ---------------------------------------------------------------- unstated_assumption
  select count(*)::int into b from public.fn_unsafe_check_unstated_assumption(null);
  a := null; e := null;
  begin
    insert into public.decision_trace (correlation_id, entity_type, entity_id, decision_type,
                                       proposed_by, decision, assumptions, knowledge_refs,
                                       evidence_refs, agent_key)
    values (gen_random_uuid(),'probe','__liveness__','probe','__probe__',
            '{"probe":true}'::jsonb, '["a fact the case never supplied"]'::jsonb,
            '[]'::jsonb, '[]'::jsonb, '__probe__');
    select count(*)::int into a from public.fn_unsafe_check_unstated_assumption(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='unstated_assumption'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='insert a decision_trace row carrying an assumption with empty knowledge_refs and evidence_refs';
  note:=e; return next;

  ---------------------------------------------------------------- unlogged_provider_bypass
  select count(*)::int into b from public.fn_unsafe_check_unlogged_provider(null);
  a := null; e := null;
  begin
    update public.internal_credential
       set last_used_at = now() + interval '1 hour'
     where active and last_function = 'ai_gateway'
       and id = (select min(id) from public.internal_credential where active and last_function='ai_gateway');
    select count(*)::int into a from public.fn_unsafe_check_unlogged_provider(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='unlogged_provider_bypass'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='stamp an ai_gateway credential as used after the newest ai_cost_log row';
  note:=e; return next;

  ---------------------------------------------------------------- fail_open_authorization
  select count(*)::int into b from public.fn_unsafe_check_fail_open_authz(null);
  a := null; e := null;
  begin
    delete from public.org_authority
     where (dept_key, action_class) in (
       select e2.department, e2.action_class from public.org_action_executor e2
        where e2.active and coalesce(e2.unattended_ok,false));
    select count(*)::int into a from public.fn_unsafe_check_fail_open_authz(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='fail_open_authorization'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='delete the org_authority rows covering unattended executors';
  note:=e; return next;

  ---------------------------------------------------------------- double_charge_refund
  select count(*)::int into b from public.fn_unsafe_check_double_refund(null);
  a := null; e := null;
  begin
    insert into public.refunds (stripe_charge_id, amount_fils, currency, reason_code, status,
                                requested_by, requested_at, within_auto_window)
    values ('__probe_charge__', 5000, 'AED', 'other', 'requested', '__probe__', now(), false),
           ('__probe_charge__', 5000, 'AED', 'other', 'requested', '__probe__', now(), false);
    select count(*)::int into a from public.fn_unsafe_check_double_refund(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='double_charge_refund'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='insert two live refund rows against one charge id';
  note:=e; return next;

  ---------------------------------------------------------------- credential_exposure
  select count(*)::int into b from public.fn_unsafe_check_credential_exposure(null);
  a := null; e := null;
  begin
    insert into public.os_audit_log (actor, action, entity, entity_id, detail, ok)
    select '__probe__','liveness','probe','__probe__',
           jsonb_build_object('leaked', s.value), true
      from public.app_secrets s
     where s.key ~ '^cred_' and length(s.value) >= 24
     order by s.key limit 1;
    select count(*)::int into a from public.fn_unsafe_check_credential_exposure(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='credential_exposure'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='write the live value of a cred_* secret into an os_audit_log detail';
  note:=e; return next;

  ---------------------------------------------------------------- ineligible_supplier_match
  select count(*)::int into b from public.fn_unsafe_check_ineligible_match(null);
  a := null; e := null;
  begin
    update public.leads set matching_blocked = true
     where id in (select supplier_id from public.inquiry_matches);
    select count(*)::int into a from public.fn_unsafe_check_ineligible_match(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='ineligible_supplier_match'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='mark every already-matched supplier as blocked from matching';
  note:=e; return next;

  ---------------------------------------------------------------- unintended_recipient
  select count(*)::int into b from public.fn_unsafe_check_unintended_recipient(null);
  a := null; e := null;
  begin
    update public.notifications
       set to_email = 'somebody-else@' || md5(random()::text) || '.invalid'
     where id = (select n.id from public.notifications n join public.leads l on l.id = n.lead_id
                  where coalesce(n.status,'') not in ('cancelled','failed','blocked','suppressed')
                    and n.to_email is not null and l.email is not null
                  order by n.id desc limit 1);
    select count(*)::int into a from public.fn_unsafe_check_unintended_recipient(null);
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='unintended_recipient'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='readdress a live lead notification to a third-party address';
  note:=e; return next;

  ---------------------------------------------------------------- the refusal path itself
  select count(*)::int into b from public.unsafe_block;
  a := null; e := null; v_tx := null;
  begin
    insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
    select gen_random_uuid(), l.id, 0.99, '__liveness_probe__'
      from public.leads l where coalesce(l.banned,false) or coalesce(l.matching_blocked,false)
      order by l.id limit 1;
    select count(*)::int into a from public.unsafe_block;
    raise exception using message = '__probe_rollback__';
  exception when others then
    if sqlerrm <> '__probe_rollback__' then e := sqlerrm; a := null; end if;
  end;
  class_key:='ineligible_supplier_match/trigger'; fired_before:=b; fired_after:=a;
  can_fire := a is not null and a > b;
  control:='insert a match to a banned or blocked supplier and check the refusal left an unsafe_block row';
  note:=e; return next;
end $fn$;

-- ---------------------------------------------------------------------------------------------
-- 10. GRANTS. Every SECURITY DEFINER routine created here is EXECUTE-to-PUBLIC by default.
-- ---------------------------------------------------------------------------------------------
revoke all on function public.fn_unsafe_check_unstated_assumption(timestamptz)  from public;
revoke all on function public.fn_unsafe_check_unlogged_provider(timestamptz)    from public;
revoke all on function public.fn_unsafe_check_fail_open_authz(timestamptz)      from public;
revoke all on function public.fn_unsafe_check_double_refund(timestamptz)        from public;
revoke all on function public.fn_unsafe_check_credential_exposure(timestamptz)  from public;
revoke all on function public.fn_unsafe_check_ineligible_match(timestamptz)     from public;
revoke all on function public.fn_unsafe_check_unintended_recipient(timestamptz) from public;
revoke all on function public.fn_unsafe_escalation_route(text, text)            from public;
revoke all on function public.fn_unsafe_block(text, text, text, text, text, jsonb, uuid) from public;
revoke all on function public.fn_unsafe_match_eligibility_guard()               from public;
revoke all on function public.fn_unsafe_guard_status()                          from public;
revoke all on function public.fn_unsafe_liveness_probe()                        from public;

grant execute on function public.fn_unsafe_check_unstated_assumption(timestamptz)  to service_role;
grant execute on function public.fn_unsafe_check_unlogged_provider(timestamptz)    to service_role;
grant execute on function public.fn_unsafe_check_fail_open_authz(timestamptz)      to service_role;
grant execute on function public.fn_unsafe_check_double_refund(timestamptz)        to service_role;
grant execute on function public.fn_unsafe_check_credential_exposure(timestamptz)  to service_role;
grant execute on function public.fn_unsafe_check_ineligible_match(timestamptz)     to service_role;
grant execute on function public.fn_unsafe_check_unintended_recipient(timestamptz) to service_role;
grant execute on function public.fn_unsafe_escalation_route(text, text)            to service_role;
grant execute on function public.fn_unsafe_block(text, text, text, text, text, jsonb, uuid) to service_role;
grant execute on function public.fn_unsafe_guard_status()                          to service_role;
grant execute on function public.fn_unsafe_liveness_probe()                        to service_role;

alter table public.unsafe_class enable row level security;
alter table public.unsafe_block enable row level security;
revoke all on table public.unsafe_class from anon, authenticated;
revoke all on table public.unsafe_block from anon, authenticated;

commit;

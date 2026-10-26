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
-- ROUTINE REMOVED 7 September 2026. public.fn_jsonb_is_empty was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_unstated_assumption was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.2 UNLOGGED PROVIDER BYPASS — a provider call that left no cost row.
-- A bypass is by construction invisible in the log it bypassed, so this needs a SECOND, independent
-- counter. internal_credential.last_used_at is that counter: it is stamped by the credential check
-- on the way OUT, ai_cost_log is written on the way BACK. If the credential was used and no cost row
-- followed, the call happened off the ledger.
-- 15-minute grace so a call still in flight is not reported as a bypass.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_unlogged_provider was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.3 FAIL-OPEN AUTHORIZATION — the guard permitted because an input was ABSENT, not because it
-- decided to permit. Two limbs: a standing-state scan and a live probe of the guard itself.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_fail_open_authz was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.4 DOUBLE CHARGE / REFUND — money leaving twice for one event.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_double_refund was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.5 CREDENTIAL EXPOSURE — a live secret written into a field an agent authors or a human reads.
-- The literal limb cannot false-positive: it matches the ACTUAL value held in app_secrets. Keys are
-- filtered to credentials; admin_emails and compliance_ref are long values that are not secrets and
-- legitimately appear in message bodies.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_credential_exposure was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.6 MATCHING INELIGIBLE SUPPLIERS.
-- Eligibility here is the set of states that positively DISQUALIFY: banned, blocked from matching,
-- permanently closed, expired licence. It deliberately does NOT require approval or verification:
-- the marketplace matches unclaimed leads by design, and testing for approval would flag every
-- legitimate match in the table instead of the wrong ones.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_ineligible_match was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- 3.7 SENDING TO UNINTENDED RECIPIENTS.
-- A notification carrying a lead_id is addressed to that supplier. If the address is not that
-- supplier's address, somebody else is about to read it. Rows on the delivery path count, not only
-- rows already gone: catching it while queued is the whole point of a safeguard.
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_check_unintended_recipient was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_escalation_route was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- 6. THE REFUSAL RECORDER
-- Called by a safeguard at the moment it refuses. Writes the row, resolves the escalation path for
-- classes that need human authority, and returns the verdict for the caller to act on.
-- ---------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_block was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_guard_status was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- 9. LIVENESS
-- Zero cannot tell a working detector from a dead one. For each LIVE class this creates the
-- offending condition, re-counts, and asserts the count ROSE — then rolls the condition back by
-- raising inside a subtransaction. plpgsql variables assigned before the raise survive it, which is
-- what lets the proof come back out while the data does not stay in.
-- Asserting a RISE rather than "> 0" keeps the proof honest where a class already has findings.
-- ---------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_unsafe_liveness_probe was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

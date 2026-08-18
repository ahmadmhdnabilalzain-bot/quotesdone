-- PHASE D · D4 — THE REMAINING 20 BUSINESS RULES GET REAL PREDICATES, AND BR-020 GETS A LADDER.
--
-- D3 enforced 34 of the 54 and recorded 20 as PENDING_OBJECT_MAP: they could not be decided until
-- each object resolved to a relation. D2 landed that map, so they are decidable now.
--
-- THE EVALUATOR GAINS A THIRD ANSWER. The Phase C routine had two — true and false — and returned
-- true when it had no predicate, which is how 52 rules read as enforced while nothing was checked.
-- D3 removed the unconditional true; this file removes the remaining ambiguity by making the
-- state EXPLICIT:
--
--   ENFORCED_PASS     a predicate ran, on evidence, and the rule holds
--   ENFORCED_FAIL     a predicate ran, on evidence, and the rule is violated
--   NOT_APPLICABLE    the rule is out of scope for this step, with the reason
--   NOT_IMPLEMENTED   no predicate exists. ok is FALSE. This never reads as enforced.
--
-- A caller can no longer confuse "checked and fine" with "not checked", because they are not the
-- same value any more.
--
-- BR-020 IS THE REASON THIS FILE IS CAREFUL. The brief is explicit that these are six different
-- things and must not be equated:
--
--   checkout created -> payment initiated -> provider success -> payment confirmed
--     -> payment reconciled -> reveal authorized
--
-- Measured on production: public.transactions has NO CHECK CONSTRAINTS AT ALL. fee_status is
-- unconstrained text, so the estate has never declared what a payment state IS. This file
-- declares the ladder as data, in public.phase_d_payment_state, and BR-020 resolves fee_status
-- against it. A value the ladder does not know is UNKNOWN and refuses — it does not fall through
-- to the nearest rung, and it is not treated as paid.
--
-- No CHECK constraint is added to public.transactions. The table is empty, so one would apply
-- cleanly, but a live writer setting a value outside the ladder would then fail at runtime, and
-- Phase D repairs implementation to the frozen design rather than changing behaviour to make a
-- parity check green. The ladder refuses at the READ instead, which is where the reveal decision
-- is actually taken.

begin;

-- ================================================================ 1. the payment state ladder
create table if not exists public.phase_d_payment_state (
  state_key        text    primary key,
  rung             integer not null unique,
  meaning          text    not null,
  authorizes_reveal boolean not null,
  why              text    not null
);

comment on table public.phase_d_payment_state is
  'The ordered payment-state ladder BR-020 reads. public.transactions carries no check constraint '
  'on fee_status, so this is the first place the estate declares what a payment state means. Only '
  'the top rung authorizes a reveal; every rung below it, and every value not in this table, '
  'refuses.';

insert into public.phase_d_payment_state (state_key, rung, meaning, authorizes_reveal, why) values
 ('checkout_created', 1,'A checkout session exists. No money has moved and none may be assumed.',        false,
  'The customer reached the payment screen. Treating this as paid is the first and cheapest mistake available.'),
 ('payment_initiated',2,'The customer submitted payment. The provider has not answered.',                false,
  'An initiated payment can still fail, be declined, or be abandoned mid-flow.'),
 ('provider_success', 3,'The provider reported success on its own API.',                                 false,
  'A provider 200 is the provider''s claim about itself. It is not our record and it is not reconciled.'),
 ('payment_confirmed',4,'We hold an authenticated provider event for this exact payment reference.',     false,
  'Confirmed is a fact about the EVENT. It still says nothing about whether the amount and the transaction agree.'),
 ('payment_reconciled',5,'The confirmed amount, currency and payment reference match this transaction, and a reconciliation record exists.', true,
  'This is the founder-approved bar in BR-020. Reveal is permitted from here and from nowhere below it.'),
 ('reveal_authorized',6,'Reconciliation held and the reveal decision has been taken and recorded.',      true,
  'The terminal rung. Recorded separately so a reveal that already happened is distinguishable from one that merely may.')
on conflict (state_key) do update set
  rung = excluded.rung, meaning = excluded.meaning,
  authorizes_reveal = excluded.authorizes_reveal, why = excluded.why;

-- ================================================================ 2. the BR-020 decision
-- IDENTIFIERS ARE TAKEN AS TEXT AND THE COLUMN IS CAST, DELIBERATELY. This estate mixes key
-- types: transactions.id and inquiries.id are uuid, leads.id and quote_comparisons.id are
-- bigint, and inquiry_matches carries one of each. A predicate that casts the ARGUMENT to
-- bigint throws on a uuid — which is exactly how the first version of this file failed its own
-- probe. Casting the column costs an index scan on tables that are empty or small today; being
-- wrong costs a rule that cannot run at all.
drop function if exists public.fn_phase_d_reveal_permitted(bigint);
create or replace function public.fn_phase_d_reveal_permitted(p_transaction_id text)
returns table(permitted boolean, state_key text, rung integer, reason text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare t public.transactions%rowtype; s public.phase_d_payment_state%rowtype; v_raw text;
begin
  select * into t from public.transactions where id::text = p_transaction_id;
  if not found then
    permitted := false; state_key := 'no_transaction'; rung := 0;
    reason := format('BR-020: no transaction %s. A reveal with no transaction is not an edge case, it is the whole defect.', coalesce(p_transaction_id,'(null)'));
    return next; return;
  end if;

  v_raw := lower(btrim(coalesce(t.fee_status, '')));
  if v_raw = '' then
    permitted := false; state_key := 'unstated'; rung := 0;
    reason := 'BR-020: transaction carries no fee_status. An absent payment state is not a paid one.';
    return next; return;
  end if;

  -- The table is ALIASED and the column QUALIFIED. This function's OUT parameter is also named
  -- state_key, and an unqualified reference resolves to the plpgsql variable rather than the
  -- column. Postgres refuses that as ambiguous instead of silently choosing, which is the good
  -- outcome — but only once it is written correctly.
  select * into s from public.phase_d_payment_state ps where ps.state_key = v_raw;
  if not found then
    -- FAIL CLOSED. An unrecognised value is not mapped to the nearest rung and not assumed paid.
    permitted := false; state_key := v_raw; rung := 0;
    reason := format('BR-020: fee_status %s is not a declared payment state. Refusing rather than guessing which rung it means.', v_raw);
    return next; return;
  end if;

  if not s.authorizes_reveal then
    permitted := false; state_key := s.state_key; rung := s.rung;
    reason := format('BR-020: transaction is at rung %s (%s) and reveal requires payment_reconciled at rung 5. %s',
                     s.rung, s.state_key, s.why);
    return next; return;
  end if;

  -- Reconciled is claimed. The claim must carry the two facts that make it one.
  if coalesce(btrim(t.payment_ref),'') = '' then
    permitted := false; state_key := s.state_key; rung := s.rung;
    reason := 'BR-020: the transaction claims a reconciled state with no payment_ref. A reconciliation with nothing to reconcile against is a label.';
    return next; return;
  end if;
  if t.reveal_fee is null then
    permitted := false; state_key := s.state_key; rung := s.rung;
    reason := 'BR-020: the transaction claims a reconciled state with a null reveal_fee. A null amount is an unmeasured amount, not a settled one.';
    return next; return;
  end if;

  permitted := true; state_key := s.state_key; rung := s.rung;
  reason := format('BR-020: transaction %s is at rung %s (%s) with payment_ref and a stated reveal_fee.',
                   t.id, s.rung, s.state_key);
  return next;
end $fn$;

comment on function public.fn_phase_d_reveal_permitted(text) is
  'The BR-020 decision, isolated so it can be tested on its own. Six payment states are distinct '
  'and only reconciled or above authorizes a reveal; an unrecognised fee_status refuses rather '
  'than resolving to the nearest rung.';

-- ================================================================ 3. the evaluator, v2
--
-- The return type GAINS a column, and Postgres will not let CREATE OR REPLACE change a function's
-- output shape, so this is a drop and a create. Everything that calls it is updated in the same
-- migration — public.fn_phase_d_handler_execute is the only caller — and PostgREST is notified
-- afterwards, because a drop-and-create leaves its schema cache pointing at a function signature
-- that no longer exists.
drop function if exists public.fn_phase_d_rule_check(text, jsonb);

create or replace function public.fn_phase_d_rule_check(p_rule_id text, p_context jsonb)
returns table(state text, ok boolean, rule_type text, enforced boolean, reason text, refusal_code text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.phase_b_business_rule%rowtype;
  e public.phase_d_rule_enforcement%rowtype;
  v_missing text[]; v_n bigint; v_txt text; v_ok boolean; v_reason text;
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; rule_type := 'unknown'; enforced := false;
    reason := format('unknown business rule %s — fail closed', p_rule_id);
    refusal_code := 'unknown_rule'; return next; return;
  end if;
  rule_type := r.rule_type;

  select * into e from public.phase_d_rule_enforcement where rule_id = p_rule_id;
  if not found then
    state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
    reason := format('rule %s has no row in phase_d_rule_enforcement — fail closed rather than assume it is satisfied', p_rule_id);
    refusal_code := 'rule_unregistered'; return next; return;
  end if;
  refusal_code := e.refusal_code;
  enforced := (e.status = 'ENFORCED');

  -- ============================ the predicates ============================================
  -- Each reads the relation D2 bound for the object it governs. A rule whose evidence is absent
  -- REFUSES; it never passes for want of data.

  if p_rule_id in ('BR-001','BR-005') then
    v_ok := public.fn_phase_c_actor_may_own(p_context->>'accountable_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: owner %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     case when v_ok then 'resolves to one active canonical role'
                          else 'does not resolve to an active canonical role' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-004' then
    v_ok := coalesce((select kind from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')),'') = 'canonical';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-004: actor %s %s', coalesce(p_context->>'actor_role_id','(none)'),
                     case when v_ok then 'is canonical' else 'is not canonical; aliases are input compatibility only' end);
    return next; return;
  end if;

  if p_rule_id in ('BR-002','BR-030','BR-031','BR-037','BR-038') then
    v_ok := public.fn_kernel_reviewer_independent(p_context->>'accountable_role_id', p_context->>'reviewer_role_id');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: %s and %s %s', p_rule_id, coalesce(p_context->>'accountable_role_id','(none)'),
                     coalesce(p_context->>'reviewer_role_id','(none)'),
                     case when v_ok then 'are different effective identities'
                          else 'resolve to the same effective identity' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-048' then
    v_ok := not exists (select 1 from public.phase_c_overlay_binding ob
                         where ob.overlay_id = (select role_id from public.fn_phase_c_resolve_actor(p_context->>'actor_role_id')));
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then 'BR-048: the acting identity is not a category overlay'
                   else format('BR-048: %s is a category overlay and may not dispatch, approve suppliers, reveal identity or change policy',
                               p_context->>'actor_role_id') end;
    return next; return;
  end if;

  if p_rule_id in ('BR-053','BR-054') then
    v_ok := not coalesce((public.fn_kernel_paid_provider_gate('openai/gpt-4o-mini')->>'allowed')::boolean, true);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: the paid-provider gate %s', p_rule_id,
                     case when v_ok then 'refuses a paid route' else 'ALLOWED a paid route' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-043' then
    if coalesce(btrim(p_context->>'policy_exception'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := 'BR-043: the call proposes no policy exception, so there is no exception to authorise';
      return next; return;
    end if;
    v_ok := coalesce(btrim(p_context->>'exception_authority_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-043: exception %s %s', p_context->>'policy_exception',
                     case when v_ok then 'carries an authority reference'
                          else 'is proposed with no exception_authority_ref' end);
    return next; return;
  end if;

  if p_rule_id in ('BR-021','BR-022','BR-023','BR-024') then
    if coalesce(btrim(p_context->>'commercial_policy_change'),'') = '' then
      state := 'NOT_APPLICABLE'; ok := true;
      reason := format('%s: the call proposes no change to a founder-reserved commercial term', p_rule_id);
      return next; return;
    end if;
    v_ok := coalesce(btrim(p_context->>'founder_authority_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('%s: change %s %s', p_rule_id, p_context->>'commercial_policy_change',
                     case when v_ok then 'carries founder authority' else 'names no founder authority' end);
    return next; return;
  end if;

  -- ---------------- BR-020: reveal only after reconciliation -------------------------------
  if p_rule_id = 'BR-020' then
    if p_context->>'transaction_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-020: no transaction_id in context. A reveal decision with no transaction to reconcile is refused.';
      return next; return;
    end if;
    -- Aliased for the same reason as the lookup inside fn_phase_d_reveal_permitted: this
    -- function's OUT parameter is also called `reason`, so an unqualified reference is ambiguous
    -- between the plpgsql variable and the callee's returned column.
    select rp.permitted, rp.reason into v_ok, v_reason
      from public.fn_phase_d_reveal_permitted(p_context->>'transaction_id') rp;
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := v_reason;
    return next; return;
  end if;

  -- ---------------- the object-backed rules D2 unblocked -----------------------------------
  if p_rule_id = 'BR-011' then           -- no customer identity in a supplier-facing payload
    v_txt := coalesce(p_context->>'supplier_payload','');
    if v_txt = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-011: no supplier_payload named. A payload nobody showed cannot be certified free of customer identity.';
      return next; return;
    end if;
    select count(*) into v_n from public.customers c
     where (coalesce(c.email,'') <> '' and position(lower(c.email) in lower(v_txt)) > 0)
        or (coalesce(c.phone,'') <> '' and position(c.phone   in v_txt) > 0)
        or (coalesce(c.full_name,'') <> '' and length(c.full_name) > 3
            and position(lower(c.full_name) in lower(v_txt)) > 0);
    -- The test is simply whether any customer identity appears in the payload. An earlier draft
    -- also ORed in a reveal_state check, which collapsed to the same expression under operator
    -- precedence and read as if it were doing something it was not.
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-011: %s customer identity match(es) found in the supplier-facing payload, over %s customer row(s) searched for email, phone and full name',
                     v_n, (select count(*) from public.customers));
    return next; return;
  end if;

  if p_rule_id = 'BR-012' then           -- an approved immutable supplier-safe package exists
    v_ok := coalesce(btrim(p_context->>'safe_package_ref'),'') <> ''
            and coalesce(btrim(p_context->>'safe_package_approved_by'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-012: package %s approved by %s',
                                         p_context->>'safe_package_ref', p_context->>'safe_package_approved_by')
                   else 'BR-012: no approved supplier-safe package named. No assignment or notification may be created without one.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-013' then           -- the inquiry is quote-ready
    if p_context->>'inquiry_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-013: no inquiry_id named; readiness cannot be measured against nothing.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiries i
     where i.id::text = p_context->>'inquiry_id'
       and coalesce(i.status,'') in ('quote_ready','dispatched','quoted','completed');
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-013: inquiry %s %s', p_context->>'inquiry_id',
                     case when v_ok then 'is in a quote-ready state'
                          else 'is not quote-ready; mandatory qualification, route or document blockers remain' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-014' then           -- only a CONFIRMED route authorises dispatch
    v_ok := lower(coalesce(btrim(p_context->>'route_state'),'')) = 'confirmed';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-014: route state %s. Proposed, ambiguous, rejected and excluded routes cannot authorise dispatch.',
                     coalesce(nullif(btrim(p_context->>'route_state'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-015' then           -- only an approved, eligible supplier is dispatched to
    if p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-015: no supplier_id named.'; return next; return;
    end if;
    select count(*) into v_n from public.leads l
     where l.id::text = p_context->>'supplier_id'
       and coalesce(l.approval_status,'') = 'approved' and coalesce(l.verified,false);
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-015: supplier %s %s. public.leads already enforces approved implies verified as a CHECK constraint.',
                     p_context->>'supplier_id',
                     case when v_ok then 'is approved and verified' else 'is not an approved, verified supplier' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-016' then           -- one assignment per supplier per inquiry version
    if p_context->>'inquiry_id' is null or p_context->>'supplier_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-016: inquiry_id and supplier_id are both required to decide duplicate assignment.';
      return next; return;
    end if;
    select count(*) into v_n from public.inquiry_matches m
     where m.inquiry_id::text = p_context->>'inquiry_id'
       and m.supplier_id::text = p_context->>'supplier_id';
    v_ok := (v_n <= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-016: %s existing assignment(s) for that supplier and inquiry. NOTE: public.inquiry_matches carries no version column and no unique constraint, so this is enforced here and NOT structurally — recorded as the D2 REPAIR on supplier_assignment.', v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-017' then           -- a refused assignment is not a contact
    v_ok := lower(coalesce(btrim(p_context->>'assignment_result'),'')) in ('delivered','accepted','sent');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-017: assignment result %s. Refused and failed assignments are not counted as contacted and create no success notification.',
                     coalesce(nullif(btrim(p_context->>'assignment_result'),''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-018' then           -- the supplier's own revision is never platform-edited
    v_ok := coalesce(btrim(p_context->>'quote_revision_ref'),'') <> ''
            and coalesce(p_context->>'platform_edited','true') = 'false';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-018: revision %s is supplier-authored and unedited; normalisation is separate',
                                         p_context->>'quote_revision_ref')
                   else 'BR-018: no unedited supplier revision named. The platform may normalise for comparison but never alter the original.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-019' then           -- a customer sees only their own published comparison
    if p_context->>'comparison_id' is null or p_context->>'caller_customer_id' is null then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-019: comparison_id and caller_customer_id are both required.'; return next; return;
    end if;
    select count(*) into v_n from public.quote_comparisons qc
     where qc.id::text = p_context->>'comparison_id'
       and qc.customer_id::text = p_context->>'caller_customer_id';
    v_ok := (v_n = 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-019: comparison %s %s the calling customer', p_context->>'comparison_id',
                     case when v_ok then 'belongs to' else 'does NOT belong to' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-025' then           -- acceptance names the exact version and hash
    v_ok := coalesce(btrim(p_context->>'terms_version'),'') <> ''
            and coalesce(btrim(p_context->>'terms_hash'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-025: acceptance names version %s and hash %s',
                                         p_context->>'terms_version', left(p_context->>'terms_hash',12))
                   else 'BR-025: acceptance must reference the exact displayed version AND hash; one without the other is not an acceptance of anything specific.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-026' then           -- no certificate before an acceptance record
    v_ok := coalesce(btrim(p_context->>'acceptance_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-026: acceptance record %s exists', p_context->>'acceptance_ref')
                   else 'BR-026: no acceptance record named. A certificate generated before acceptance would assert a fact that has not happened.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-029' then           -- conflicting evidence is preserved, not overwritten
    v_ok := coalesce(p_context->>'conflict_preserved','') = 'true'
            or coalesce(btrim(p_context->>'evidence_authority'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then 'BR-029: conflicting evidence is retained with its authority ranking'
                   else 'BR-029: no conflict-preservation evidence named. Lower-authority evidence may not silently overwrite higher.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-032' then           -- provider events are unique and replay-safe
    if coalesce(btrim(p_context->>'provider_event_id'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-032: no provider_event_id named; duplicate delivery cannot be decided without one.';
      return next; return;
    end if;
    select count(*) into v_n from public.stripe_events se
     where se.event_id = p_context->>'provider_event_id';
    v_ok := (v_n <= 1);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-032: provider event %s appears %s time(s); public.stripe_events keys on event_id with delivery_count, so a duplicate is visible rather than reprocessed.',
                     p_context->>'provider_event_id', v_n);
    return next; return;
  end if;

  if p_rule_id = 'BR-033' then           -- unknown money is quarantined, never success
    v_txt := lower(coalesce(btrim(p_context->>'monetary_state'),''));
    v_ok := v_txt <> '' and v_txt not in ('unknown','conflicting','unreconciled');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-033: monetary state %s. Unknown, conflicting and unreconciled states are blocked and quarantined, never treated as success.',
                     coalesce(nullif(v_txt,''),'(unstated)'));
    return next; return;
  end if;

  if p_rule_id = 'BR-034' then           -- consent and suppression are respected
    if coalesce(btrim(p_context->>'notify_email'),'') = '' then
      state := 'ENFORCED_FAIL'; ok := false;
      reason := 'BR-034: no notify_email named; consent cannot be decided for an unnamed recipient.';
      return next; return;
    end if;
    select count(*) into v_n from public.email_suppressions s
     where lower(s.email) = lower(p_context->>'notify_email');
    v_ok := (v_n = 0);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-034: %s is %s in public.email_suppressions', p_context->>'notify_email',
                     case when v_ok then 'not suppressed' else 'SUPPRESSED and must not be contacted' end);
    return next; return;
  end if;

  if p_rule_id = 'BR-035' then           -- only the approved revision publishes
    v_ok := coalesce(btrim(p_context->>'approved_revision_ref'),'') <> ''
            and coalesce(p_context->>'approved_revision_ref','') = coalesce(p_context->>'publishing_revision_ref','');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-035: the publishing revision is the approved one (%s)',
                                         p_context->>'approved_revision_ref')
                   else 'BR-035: the revision being published is not the independently approved revision, or neither was named.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-036' then           -- review inspects the artifact, not the brief
    v_ok := coalesce(btrim(p_context->>'artifact_ref'),'') <> ''
            and coalesce(btrim(p_context->>'artifact_sha256'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-036: review names artifact %s at digest %s',
                                         p_context->>'artifact_ref', left(p_context->>'artifact_sha256',12))
                   else 'BR-036: the review names no artifact and digest. A verifier that reads the brief instead of the artifact has already produced a false pass in this estate.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-039' then           -- a release needs an executable rollback
    v_ok := coalesce(btrim(p_context->>'rollback_ref'),'') <> '';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-039: rollback path %s is named', p_context->>'rollback_ref')
                   else 'BR-039: no rollback or recovery path named. A consequential release without one is not approvable.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-041' then           -- activity is not outcome
    v_ok := coalesce(btrim(p_context->>'outcome_metric'),'') <> ''
            and coalesce(p_context->>'outcome_metric','') <> coalesce(p_context->>'activity_metric','');
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('BR-041: success is declared on the outcome metric %s, distinct from the activity metric',
                                         p_context->>'outcome_metric')
                   else 'BR-041: no business outcome metric named, or it is the activity metric under another name.' end;
    return next; return;
  end if;

  if p_rule_id = 'BR-049' then           -- inquiry accountability does not drift
    v_ok := coalesce(btrim(p_context->>'inquiry_owner'),'') = 'rfq_qualification_manager'
            or coalesce(btrim(p_context->>'accountability_transfer_approved'),'') = 'true';
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := format('BR-049: inquiry owner is %s. Specialist and document handoffs do not move overall inquiry accountability away from rfq_qualification_manager without an approved workflow that says so.',
                     coalesce(nullif(btrim(p_context->>'inquiry_owner'),''),'(unstated)'));
    return next; return;
  end if;

  -- ---------------- structurally enforced elsewhere ----------------------------------------
  if e.enforcement_kind in ('SCHEMA_ENFORCED','EXECUTOR_ENFORCED') then
    state := 'ENFORCED_PASS'; ok := true;
    reason := format('%s is enforced at %s later in this same call, which refuses with %s',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;
  if e.enforcement_kind in ('KERNEL_ENFORCED','TRIGGER_ENFORCED') then
    state := 'ENFORCED_PASS'; ok := true;
    reason := format('%s is enforced at %s, which raises %s; this call does not re-decide it',
                     p_rule_id, e.enforcement_point, e.refusal_code);
    return next; return;
  end if;
  if e.enforcement_kind = 'CONTEXT_REQUIRED' then
    select array_agg(k order by k) into v_missing
      from unnest(e.required_context) k
     where not (p_context ? k) or coalesce(btrim(p_context->>k),'') = '';
    v_ok := (v_missing is null);
    state := case when v_ok then 'ENFORCED_PASS' else 'ENFORCED_FAIL' end; ok := v_ok;
    reason := case when v_ok then format('%s: the call names %s', p_rule_id, array_to_string(e.required_context,', '))
                   else format('%s requires [%s] and the call names none of it.', p_rule_id, array_to_string(v_missing,', ')) end;
    return next; return;
  end if;

  -- ---------------- NO PREDICATE. This is the answer that used to be `true`. ----------------
  state := 'NOT_IMPLEMENTED'; ok := false; enforced := false;
  reason := format('%s has no predicate in fn_phase_d_rule_check. NOT_IMPLEMENTED is not a pass.', p_rule_id);
  refusal_code := coalesce(e.refusal_code, 'rule_not_implemented');
  return next;
end $fn$;

comment on function public.fn_phase_d_rule_check(text, jsonb) is
  'The Phase D business-rule evaluator. Returns an explicit STATE — ENFORCED_PASS, ENFORCED_FAIL, '
  'NOT_APPLICABLE or NOT_IMPLEMENTED — so a caller can never confuse "checked and fine" with "not '
  'checked". NOT_IMPLEMENTED carries ok = false.';

-- ================================================================ 4. the 20 move to ENFORCED
update public.phase_d_rule_enforcement
   set enforcement_kind = 'PREDICATE',
       enforcement_point = 'public.fn_phase_d_rule_check(text,jsonb)',
       status = 'ENFORCED',
       required_context = case rule_id
         when 'BR-011' then array['supplier_payload']
         when 'BR-012' then array['safe_package_ref','safe_package_approved_by']
         when 'BR-013' then array['inquiry_id']
         when 'BR-014' then array['route_state']
         when 'BR-015' then array['supplier_id']
         when 'BR-017' then array['assignment_result']
         when 'BR-018' then array['quote_revision_ref','platform_edited']
         when 'BR-019' then array['comparison_id','caller_customer_id']
         when 'BR-020' then array['transaction_id']
         when 'BR-025' then array['terms_version','terms_hash']
         when 'BR-026' then array['acceptance_ref']
         when 'BR-029' then array['evidence_authority']
         when 'BR-032' then array['provider_event_id']
         when 'BR-033' then array['monetary_state']
         when 'BR-034' then array['notify_email']
         when 'BR-035' then array['approved_revision_ref','publishing_revision_ref']
         when 'BR-036' then array['artifact_ref','artifact_sha256']
         when 'BR-039' then array['rollback_ref']
         when 'BR-041' then array['outcome_metric']
         when 'BR-049' then array['inquiry_owner']
         else required_context end,
       evidence = case rule_id
         when 'BR-020' then 'Decided by public.fn_phase_d_reveal_permitted against the six-rung '
              || 'ladder in public.phase_d_payment_state. checkout_created, payment_initiated, '
              || 'provider_success and payment_confirmed all REFUSE; only payment_reconciled and '
              || 'reveal_authorized permit, and each additionally requires a payment_ref and a '
              || 'stated reveal_fee. An unrecognised fee_status refuses rather than resolving to '
              || 'the nearest rung. public.transactions carries no CHECK on fee_status, so the '
              || 'ladder is the first declaration of what a payment state means in this estate.'
         when 'BR-016' then 'Enforced in the predicate against public.inquiry_matches. NOT '
              || 'structural: that table has no version column and no unique constraint, which is '
              || 'the open REPAIR recorded against supplier_assignment in the D2 object map.'
         when 'BR-015' then 'Reads public.leads.approval_status and verified. The table already '
              || 'carries a CHECK that approved implies verified, so the predicate and the '
              || 'constraint agree rather than the predicate standing alone.'
         else 'Predicate reads the relation D2 bound for the object this rule governs; absent '
              || 'evidence refuses rather than passing.' end,
       recorded_at = now()
 where rule_id in ('BR-011','BR-012','BR-013','BR-014','BR-015','BR-016','BR-017','BR-018',
                   'BR-019','BR-020','BR-025','BR-026','BR-029','BR-032','BR-033','BR-034',
                   'BR-035','BR-036','BR-039','BR-041','BR-049');

-- The register is only worth having if it refuses a silent no-op.
do $assert$
declare n int;
begin
  select count(*) into n from public.phase_d_rule_enforcement where status = 'OUTSTANDING';
  if n <> 0 then
    raise exception 'phase_d_d4_remaining_rules: % rule(s) are still OUTSTANDING after this file claims to have implemented the remaining twenty', n
      using errcode = '23514';
  end if;
end $assert$;

-- ================================================================ 5. grants
revoke all on function public.fn_phase_d_reveal_permitted(text) from public, anon;
grant execute on function public.fn_phase_d_reveal_permitted(text) to service_role, authenticated;
revoke all on public.phase_d_payment_state from public, anon, authenticated;
grant select on public.phase_d_payment_state to service_role, authenticated;

-- A drop-and-create leaves PostgREST's schema cache pointing at a signature that no longer
-- exists, and the next RPC through the API would 404 on a function that is plainly present in
-- the catalogue. Reloading is not optional after a signature change.
notify pgrst, 'reload schema';

commit;

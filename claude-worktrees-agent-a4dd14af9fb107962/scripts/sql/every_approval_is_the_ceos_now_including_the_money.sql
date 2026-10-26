-- EVERY APPROVAL IS THE CEO'S NOW, INCLUDING THE MONEY.
--
-- Founder, 8 September 2026, in two messages minutes apart:
--     "refunds belong to the CEO from now on."
--     "all approvals are from CEO. nothing goes to me."
--
-- This replaces his own ruling of 17 August — "every refund needs the founder, at any amount" — which
-- is written into this database in two triggers on public.refunds and quoted verbatim in both of
-- their error messages. He is not softening a control; he is moving the seat that holds it, because
-- he is building a company that runs without him.
--
-- WHAT IS PRESERVED, and this is the point of the file. Removing the founder from the loop is not
-- removing the loop:
--
--   * money still cannot move without a named decision. A refund may not reach approved, processing
--     or succeeded while citing nothing.
--   * the decider must be an ACTIVE identity, checked against a table, not a string the caller
--     supplies. Before the 17 Aug guard existed, fn_refund_request auto-approved anything inside the
--     window under an AED 2,000 authority and wrote decided_by = 'policy:auto_window' — a refund that
--     approved itself. That hole stays shut; only the name over the door changes.
--   * a refund Stripe already issued is still recorded rather than refused. Money that has actually
--     left is a FACT, and refusing the row would delete our only record of it. The named external
--     originators carry over unchanged.
--   * decisions are immutable and superseded rather than edited, so the register is a history.
--
-- WHAT CHANGES: the authority is public.ceo_identity instead of phase_c_founder_identity, and the
-- register is public.ceo_approval instead of phase_c_refund_decision. Both are the CEO seat's own
-- tables — "for the new CEO we will build proper tables and edge functions and everything. we dont
-- rely on the old structure" — so Phase C can be deleted afterwards without taking refunds with it.
--
-- MEASURED FIRST: public.refunds has 0 rows and phase_c_refund_decision has 0 rows, so nothing is
-- migrated and no live refund changes authority mid-flight.
--
-- NAMED ceo_approval, NOT ceo_decision: a table called public.ceo_decision already exists and is a
-- different thing entirely -- a catalogue of decision POLICIES (decision_key, trigger_condition,
-- measure_sql, cadence), not a record of decisions taken. Reusing the name would have merged a policy
-- catalogue with an approval ledger, and the apply refused it on a missing column, which is the
-- guard working.
--
-- The register is deliberately NOT refund-only. "All approvals are from CEO" is wider than money, and
-- a second register for the next kind of approval is how two answers to one question appear.
--
--   node scripts/apply_sql.mjs scripts/sql/every_approval_is_the_ceos_now_including_the_money.sql --apply --ddl

begin;

-- ── WHO MAY DECIDE ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_identity (
  identity   text primary key,
  active     boolean not null default true,
  note       text,
  added_at   timestamptz not null default now()
);

comment on table public.ceo_identity is
  'The identities permitted to decide as the CEO seat. Checked by the refund guards. An identity is '
  'deactivated, never deleted, so an old decision still resolves to who made it.';

insert into public.ceo_identity (identity, active, note) values
  ('ceo', true, 'The CEO agent. Founder ruling, 8 Sep 2026: all approvals are the CEO''s and nothing goes to the founder.')
on conflict (identity) do nothing;

-- ── THE DECISION REGISTER ──────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_approval (
  decision_id    bigint generated always as identity primary key,
  subject_kind   text        not null check (subject_kind in ('refund','spend','supplier','publication','other')),
  subject_id     text        not null,
  decision       text        not null check (decision in ('approved','refused')),
  decided_by     text        not null references public.ceo_identity(identity),
  amount_aed     numeric(12,2),
  rationale      text        not null,
  decided_at     timestamptz not null default now(),
  superseded_by  bigint      references public.ceo_approval(decision_id),
  constraint ceo_approval_not_self_superseding check (superseded_by is distinct from decision_id)
);

comment on table public.ceo_approval is
  'Every approval the CEO seat makes. Replaces phase_c_refund_decision and founder_approval_request. '
  'Append-only: a decision is superseded by a later one, never edited.';

create index if not exists ceo_approval_subject_idx on public.ceo_approval (subject_kind, subject_id);

-- APPEND-ONLY. Everything but supersession is frozen once written, so the register is a record of
-- what was decided rather than of what someone later wished had been decided.
create or replace function public.fn_ceo_approval_append_only()
returns trigger
language plpgsql
as $fn$
begin
  if new.subject_kind is distinct from old.subject_kind
     or new.subject_id is distinct from old.subject_id
     or new.decision   is distinct from old.decision
     or new.decided_by is distinct from old.decided_by
     or new.amount_aed is distinct from old.amount_aed
     or new.rationale  is distinct from old.rationale
     or new.decided_at is distinct from old.decided_at then
    raise exception 'ceo_approval %: a decision is superseded, never edited', old.decision_id
      using errcode = '23514',
            hint = 'Write a new decision and point the old row''s superseded_by at it.';
  end if;
  return new;
end
$fn$;

drop trigger if exists z00_ceo_approval_append_only on public.ceo_approval;
create trigger z00_ceo_approval_append_only
  before update on public.ceo_approval
  for each row execute function public.fn_ceo_approval_append_only();

-- ── THE REFUND GUARDS, RE-SEATED ───────────────────────────────────────────────────────────────
-- Only the CEO approves. Identical in shape to fn_refund_founder_decision_only; the authority table
-- is the only thing that moved.
create or replace function public.fn_refund_ceo_approval_only()
returns trigger
language plpgsql
as $fn$
begin
  if new.status <> 'approved' then return new; end if;
  if exists (select 1 from public.ceo_identity c
              where c.active and lower(c.identity) = lower(btrim(coalesce(new.decided_by, '')))) then
    return new;
  end if;
  raise exception 'refund %: approved by %, who is not an active CEO identity.',
    coalesce(new.id::text, '(new)'), coalesce(nullif(btrim(new.decided_by), ''), '(nobody)')
    using errcode = '42501',
          hint = 'Refunds belong to the CEO — the founder''s ruling of 8 Sep 2026, replacing his '
              || '17 Aug rule that every refund needed him. A refund reaches ''approved'' only with '
              || 'a decided_by that is an active row in public.ceo_identity. decided_by is checked '
              || 'against that table and never trusted as supplied: the hole this closes is a refund '
              || 'that approved itself as ''policy:auto_window''.';
end
$fn$;

-- Money may not move while citing nothing.
create or replace function public.fn_refund_execution_requires_ceo_approval()
returns trigger
language plpgsql
as $fn$
declare
  v_money_moved constant text[] := array['approved','processing','succeeded'];
  -- A refund Stripe already issued is a FACT to be recorded, not a request to be approved. Refusing
  -- the row would delete our only record of real money leaving, which is worse than admitting it.
  v_external    constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
  d public.ceo_approval%rowtype;
begin
  if not (new.status = any(v_money_moved)) then return new; end if;
  if tg_op = 'UPDATE' and old.status = any(v_money_moved)
     and new.refund_decision_id is not distinct from old.refund_decision_id then
    return new;   -- already past this boundary and not changing which decision it cites
  end if;
  if lower(coalesce(new.requested_by, '')) = any(v_external) then
    return new;
  end if;

  if new.refund_decision_id is null then
    raise exception 'refunds %: a platform-originated refund may not reach status % without naming the CEO decision that authorised it.',
      coalesce(new.id::text, '(new)'), new.status
      using errcode = '23514',
            hint = 'Record one in public.ceo_approval (subject_kind = ''refund'') and cite its '
                || 'decision_id. Founder ruling, 8 Sep 2026: all approvals are the CEO''s.';
  end if;

  select * into d from public.ceo_approval where decision_id = new.refund_decision_id;
  if not found then
    raise exception 'refunds %: refund_decision_id % names no CEO decision',
      coalesce(new.id::text, '(new)'), new.refund_decision_id using errcode = '23503';
  end if;
  if d.subject_kind <> 'refund' then
    raise exception 'refunds %: decision % is a % decision, not a refund decision',
      coalesce(new.id::text, '(new)'), d.decision_id, d.subject_kind using errcode = '23514';
  end if;
  if d.decision <> 'approved' then
    raise exception 'refunds %: decision % refused this refund; it may not reach %',
      coalesce(new.id::text, '(new)'), d.decision_id, new.status using errcode = '23514';
  end if;
  if d.superseded_by is not null then
    raise exception 'refunds %: decision % was superseded by %; cite the decision that stands',
      coalesce(new.id::text, '(new)'), d.decision_id, d.superseded_by using errcode = '23514';
  end if;
  return new;
end
$fn$;

-- Swap the constraint and the two triggers over. The old functions are left in place for the phase
-- sweep to remove with the rest of Phase C; what matters here is that nothing on `refunds` still
-- runs them.
alter table public.refunds drop constraint if exists refunds_refund_decision_id_fkey;
alter table public.refunds
  add constraint refunds_refund_decision_id_fkey
  foreign key (refund_decision_id) references public.ceo_approval(decision_id);

drop trigger if exists z00_refund_founder_decision_only on public.refunds;
drop trigger if exists z05_refund_execution_requires_decision on public.refunds;

create trigger z00_refund_ceo_approval_only
  before insert or update on public.refunds
  for each row execute function public.fn_refund_ceo_approval_only();

create trigger z05_refund_execution_requires_ceo_approval
  before insert or update on public.refunds
  for each row execute function public.fn_refund_execution_requires_ceo_approval();

commit;

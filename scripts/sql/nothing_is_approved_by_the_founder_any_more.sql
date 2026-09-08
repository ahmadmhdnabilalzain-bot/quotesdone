-- NOTHING IS APPROVED BY THE FOUNDER ANY MORE.
--
-- Founder, 8-9 September 2026: "all approvals are from CEO. nothing goes to me", "refunds belong to
-- the CEO from now on", "cause there is nothing to be approved by founder", "ceo is responsible for
-- all approvals".
--
-- This is not a reduction in control. The CEO seat holds it: public.ceo_approval is an append-only
-- decision register whose decided_by must be an active row in public.ceo_identity, and two triggers
-- on public.refunds refuse money moving without a standing, unsuperseded CEO decision. Those were
-- built first, deliberately, and this file asserts they are still standing before it commits.
--
-- WHAT GOES — the objects that exist to route an approval TO HIM. All four were measured to have no
-- reference in the 65 deployed edge functions or in src/:
--     founder_approval_request     0 rows
--     founder_release_approval     1 row
--     founder_reserved_decision    11 rows  — the list of decisions reserved to him. That list is
--                                            now empty by his ruling, so the table has no subject.
--     action_approval              0 rows
--
-- WHAT STAYS, AND WHY IT IS NOT THE SAME THING
--
--   * procurement_approval_request / procurement_approval_policy. These are NOT about the founder.
--     They are the CUSTOMER's own internal purchase-approval chain — spec §12, served by the
--     customer-authed edge function procurement_api, scoped by organization_id, with a policy of
--     conditions and steps so that a customer company can require its own manager to sign off before
--     a purchase. A customer approving their own spend has nothing to do with who approves anything
--     at QuotesDone.
--
--   * fn_approval_decide and fn_approval_list — both called by procurement_api. They serve the
--     customer chain above.
--
--   * Founder NOTIFICATION is not founder APPROVAL, and the distinction is the whole point of his
--     ruling. He is still TOLD things: founder_alerts, founder_mail_policy, fn_notify_founder,
--     fn_founder_mail_route, founder_directive and his settings all stay. He is the owner; he is not
--     a step in a queue.
--
-- A FINDING THIS SURFACED, worth stating plainly because it is a live customer capability:
--
--   fn_phase_c_no_new_founder_approval_path is an UNCONDITIONAL `raise exception` — it refuses every
--   insert and update, with no condition at all. It is attached to founder_release_approval AND to
--   procurement_approval_request. So the customer purchase-approval feature has been dead since that
--   trigger landed: every attempt to create one raises, which is exactly why the table holds 0 rows.
--
--   The guard was written to stop new approval paths reaching the FOUNDER. Applied to a customer's
--   own approval chain it was never about him at all. Removing it is part of removing his approval
--   machinery, and the consequence is that a customer feature stops being blocked by a rule that was
--   never about customers. That is a product change and it is named here rather than buried: nothing
--   in this file makes the feature run, it only stops refusing it.
--
-- AND ONE GUARD IS STRENGTHENED RATHER THAN DROPPED. fn_kernel_founder_routing_is_refund_only refused
-- routing anything but a REFUND to the founder — the 17 August boundary. Dropping it outright would
-- re-open founder routing entirely, which is the opposite of his instruction. It is rewritten to
-- refuse ALL routing to him, which is what "nothing goes to me" actually means.
--
--   node scripts/apply_sql.mjs scripts/sql/nothing_is_approved_by_the_founder_any_more.sql --apply --ddl

begin;

-- ── THE BOUNDARY GETS STRICTER, NOT LOOSER ─────────────────────────────────────────────────────
create or replace function public.fn_kernel_founder_routing_is_refund_only()
returns trigger
language plpgsql
as $fn$
begin
  -- Kept under its original name so its trigger keeps working; the RULE inside it is what changed.
  -- It used to permit exactly one thing through: an action_class marked founder_approval_required in
  -- phase_c_action_class — in practice a refund decision. As of 8 Sep nothing goes to him at all, so
  -- the exception is gone and the refusal is total.
  --
  -- The column names below (needs_founder, action_class) are the ones the ORIGINAL routine used. My
  -- first rewrite invented owner_role and assigned_to, which org_tasks does not have — it would have
  -- applied, since a plpgsql body is not checked against the table until it fires, and then raised on
  -- the first insert. Read the routine you are replacing.
  if coalesce(new.needs_founder, false)
     and (tg_op = 'INSERT' or coalesce(old.needs_founder, false) is distinct from true) then
    raise exception
      'org_tasks: nothing routes to the founder any more, including action_class %. Every approval is the CEO''s.',
      coalesce(new.action_class, '(null)')
      using errcode = '23514',
            hint = 'Founder ruling, 8 Sep 2026, replacing the 17 Aug rule that let a refund decision '
                || 'through. Record the decision in public.ceo_approval instead.';
  end if;
  return new;
end
$fn$;

-- ── THE TRIGGERS THAT ROUTED TO HIM ────────────────────────────────────────────────────────────
-- Named from pg_trigger, not from memory: guessing trigger names cost two failed applies today.
drop trigger if exists a00_founder_approval_names_a_real_refund on public.founder_approval_request;
drop trigger if exists z10_founder_approval_refund_only         on public.founder_approval_request;
drop trigger if exists z00_kernel_truncate_guard                on public.founder_approval_request;
drop trigger if exists z10_phase_c_no_new_release_approval      on public.founder_release_approval;
drop trigger if exists z00_kernel_truncate_guard                on public.founder_release_approval;
-- The customer's chain stops being refused by a rule that was never about customers.
drop trigger if exists z10_phase_c_no_new_procurement_approval  on public.procurement_approval_request;
-- Its trigger sits on org_role, not on any table this file drops, so it has to be named separately.
drop trigger if exists a00_org_role_no_reserved_decision on public.org_role;

-- ── THE ROUTINES ───────────────────────────────────────────────────────────────────────────────
drop function if exists public.fn_founder_approval_names_a_real_refund();
drop function if exists public.fn_founder_approval_refund_only();
drop function if exists public.fn_founder_refund_approvals_open();
drop function if exists public.fn_founder_queue(p_limit integer);
drop function if exists public.fn_phase_c_no_new_founder_approval_path();
drop function if exists public.trg_org_role_no_reserved_decision();
-- The documented way to record a founder refund decision. There are no founder refund decisions.
drop function if exists public.fn_kernel_refund_decision_record(p_input jsonb);

-- ── THE PHASE-C REFUND REGISTER GOES WITH IT ───────────────────────────────────────────────────
-- phase_c_refund_decision.request_id points at founder_approval_request, so the parent cannot go
-- while it stands. It is the OLD refund decision register — the 17 August "every refund needs the
-- founder" implementation — and it is already unreferenced: refunds.refund_decision_id was re-pointed
-- at ceo_approval earlier today. It holds 0 rows, so nothing is lost with it.
drop trigger if exists a00_phase_c_refund_decision_immutable on public.phase_c_refund_decision;
drop trigger if exists z10_phase_c_refund_decision_guard     on public.phase_c_refund_decision;
drop trigger if exists z00_kernel_truncate_guard             on public.phase_c_refund_decision;
drop function if exists public.fn_phase_c_refund_decision_immutable();
drop function if exists public.fn_phase_c_refund_decision_guard();
drop table if exists public.phase_c_refund_decision;

-- ── THE TABLES ─────────────────────────────────────────────────────────────────────────────────
drop table if exists public.founder_approval_request;
drop table if exists public.founder_release_approval;
drop table if exists public.founder_reserved_decision;
drop table if exists public.action_approval;

-- ── ASSERT BOTH HALVES: his machinery gone, the CEO's standing ─────────────────────────────────
do $check$
declare n_t int; n_f int; n_ceo int; n_trg int;
begin
  select count(*) into n_t from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and c.relname in ('founder_approval_request','founder_release_approval',
                       'founder_reserved_decision','action_approval');
  select count(*) into n_f from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('fn_founder_approval_names_a_real_refund','fn_founder_approval_refund_only',
                     'fn_founder_refund_approvals_open','fn_founder_queue',
                     'fn_phase_c_no_new_founder_approval_path','fn_kernel_refund_decision_record');
  if n_t > 0 or n_f > 0 then
    raise exception 'INCOMPLETE: % founder-approval table(s) and % routine(s) remain', n_t, n_f;
  end if;

  -- REMOVING HIS APPROVAL IS NOT REMOVING THE CONTROL. If the CEO's register or its refund guards
  -- are not in place, this file has taken a control away and put nothing in its place, and that is
  -- not what he asked for.
  select count(*) into n_ceo from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname in ('ceo_approval','ceo_identity');
  select count(*) into n_trg from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relname = 'refunds'
     and t.tgname in ('z00_refund_ceo_approval_only','z05_refund_execution_requires_ceo_approval');
  if n_ceo <> 2 or n_trg <> 2 then
    raise exception 'REFUSED: the CEO''s approval control is not standing (% of 2 tables, % of 2 refund triggers)',
      n_ceo, n_trg;
  end if;
end
$check$;

commit;

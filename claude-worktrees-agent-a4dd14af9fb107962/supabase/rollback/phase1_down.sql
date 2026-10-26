-- =====================================================================================
-- PHASE 1 - ROLLBACK
-- Authored 3 August 2026 in response to independent audit finding 8.3 (FAIL, critical):
-- "there are no Phase 1 rollback artefacts at all".
--
-- Phase 1 is migrations 20260802142957 (p1_02) through 20260802154746 (p1h_10) - twenty
-- migrations, applied to production htdblwldjkcgjvmqkbeh on 2 August 2026.
--
-- READ THIS BEFORE RUNNING ANYTHING.
--
-- Phase 1's tables are the refunds ledger and the Control Mode audit trail. They are financial
-- and security EVIDENCE. A rollback that drops them converts a bad deploy into an
-- unreconstructable one - and a rollback nobody dares run is not a rollback. So this is three
-- tiers, and you almost certainly want the first one.
--
--   TIER 0  DISARM    Stop Phase 1 GATING the system. Keeps every row. Seconds. Reversible.
--                     NOT IN THIS FILE - it is a callable function, because in an incident you
--                     want one statement, not a file:
--
--                         select public.fn_phase1_disarm('you@quotesdone.com', 'why');
--                         select public.fn_phase1_rearm ('you@quotesdone.com', 'why');
--                         select public.fn_phase1_status();
--
--                     Installed by migration 20260803040404_phase1_rollback_controls_audit_8_3.
--                     Actions that pass while disarmed are STILL AUDITED, as
--                     control_mode_audit.event = 'action_allowed_phase1_disarmed'. During an
--                     incident that record is the most valuable thing in the database.
--
--   TIER 1  REVERT    Restore the pre-Phase-1 function definitions. Keeps the evidence tables and
--                     every row in them. Section 1 below. Use when Phase 1's LOGIC is wrong but
--                     its records are still wanted - which is the normal case.
--
--   TIER 2  TEARDOWN  Drop the Phase 1 objects entirely. Section 2 below. DESTROYS EVIDENCE, so
--                     section 2 refuses to run until section 2a has exported it. Use only when
--                     Phase 1 is being abandoned, not when it is being fixed.
--
-- Escalate one tier at a time. Tier 0 first, always: it is free, it is instant, and it buys the
-- time to decide whether tier 1 is really needed.
--
-- WHAT NO TIER CAN UNDO. Stated plainly so nobody discovers it mid-incident:
--   * p1h_10 relaxed refunds.amount_fils to nullable. Section 1 re-tightens it ONLY if no NULL
--     row exists. If Stripe has since delivered a refund with an unknown amount, that row is a
--     real fact and the constraint stays relaxed. This is correct: the alternative is deleting a
--     refund that happened.
--   * p1h_06 deactivated every non-primary Control Mode identity AND added the partial unique
--     index control_mode_identity_one_active_per_phone. The deactivation cannot be undone while
--     that index exists - rehearsal proved it, 23505 duplicate key - so reverting p1h_06 means
--     dropping the index and reinstating two admin identities on one phone. Section 1.3 therefore
--     leaves it alone unless you explicitly opt in. Note text is restored by pattern, not from a
--     snapshot, so a note edited by hand since then keeps the hand edit.
--   * Challenges consumed and sessions closed by p1h_06 are gone. They were single-use security
--     artefacts; re-opening a consumed challenge would be a vulnerability, not a restoration.
--   * Any refund that actually moved money at Stripe is a fact about the world. Dropping the
--     ledger row does not un-refund it, it only makes it unreconcilable. This is the whole reason
--     tier 2 requires an export.
--
-- REHEARSAL. Tier 0 is rehearsed automatically:
--
--     begin;
--     select public.fn_phase1_rollback_rehearse('your.name');
--     rollback;
--
--   Rehearsed on production 3 August 2026, 6/6 steps passed: a mutating action was refused,
--   disarm made it pass in mode 'disarmed', evidence row counts did not fall, re-arm restored
--   the refusal. phase1_rollback_log returned to 0 rows on ROLLBACK.
--
--   Tiers 1 and 2 are rehearsed the same way - wrap the section in a transaction and abort it:
--
--     begin;
--     \i supabase/rollback/phase1_down.sql   -- or paste the section
--     select public.fn_phase1_status();
--     rollback;
--
--   Rehearsed on production 3 August 2026, both tiers, transaction aborted:
--
--     BASELINE: tables=8 views=5 functions=20 identities=2 (active=1)
--     TIER 1 1.1 disarmed=t
--     TIER 1 1.2 fn_refund_status_rank restored=t
--     TIER 1 1.3 default path (index kept): correctly refused (23505 on ..._one_active_per_phone)
--     TIER 1 1.3b opt-in: index dropped=t  identities active=2/2  notes stripped=2
--     TIER 1 1.4 amount_fils re-tightened=t (null rows=0)
--     TIER 1 1.5 cron.alter_job(active:=false) ok
--     TIER 1 EVIDENCE INTACT: refunds=0 cm_audit=51 cm_action=90
--     TIER 2a export verified row-for-row -> guard permits teardown
--     TIER 2 TEARDOWN: tables 8 -> 0   views 5 -> 0   functions 20 -> 0
--     TIER 2 SURVIVORS: phase1_rollback_log kept, archive kept, fn_phase1_disarmed callable=t
--     VERDICT tier1_pass=t  tier2_pass=t
--
--   The rehearsal found TWO defects in the first draft of this file, both of which would have
--   struck an operator mid-rollback. Both are fixed above and annotated at the point of change:
--     * 1.3 reactivating the identities is impossible while p1h_06's unique index stands (23505).
--     * 1.5 "update cron.job set active = false" is denied to the Supabase roles (42501).
--   This is the argument for rehearsing rollbacks rather than writing them: a rollback that has
--   never been executed is a document, not a procedure.
-- =====================================================================================


-- =====================================================================================
-- SECTION 1 - TIER 1 REVERT
-- Restores pre-Phase-1 behaviour. Drops NO table and deletes NO row.
-- =====================================================================================

-- 1.1 --------------------------------------------------------------------------------
-- p1h_01 made fn_control_mode_require fail closed on an unclassified action, and Phase 1 as a
-- whole put the gate in front of every mutating os_ops/refunds action. Reverting the LOGIC means
-- returning the gate to observe-only. That is exactly tier 0, and tier 0 does it without a
-- schema change, so tier 1 simply calls it rather than re-defining the function a second way.
select public.fn_phase1_disarm('rollback:phase1_down.sql section 1', 'tier 1 revert - returning Control Mode to observe-only');


-- 1.2 --------------------------------------------------------------------------------
-- p1h_07 dropped public.fn_refund_status_rank(text), which p1h_05 had created. Nothing outside
-- fn_refund_settle called it, but a revert that leaves a dropped function dropped is not a
-- revert. Body restored verbatim from 20260802152054_p1h_05_refund_settle_ordering_safe.sql:17-23.
create or replace function public.fn_refund_status_rank(p_status text)
returns int language sql immutable as $fn$
  select case lower(coalesce(p_status,''))
    when 'succeeded' then 4 when 'failed' then 3
    when 'cancelled' then 2 when 'canceled' then 2
    else 1 end;
$fn$;

comment on function public.fn_refund_status_rank(text) is
  'Restored by Phase 1 rollback tier 1. Original body from p1h_05; dropped by p1h_07 when the transition matrix replaced rank ordering.';


-- 1.3 --------------------------------------------------------------------------------
-- p1h_06 REVERT - OFF BY DEFAULT. Reverting it is a security regression; read this before enabling.
--
-- p1h_06 did two things, and the first is not undoable without undoing the second:
--   (a) it deactivated every non-primary Control Mode identity, and
--   (b) it added the partial unique index control_mode_identity_one_active_per_phone
--       -- UNIQUE (phone_secret_key) WHERE active -- so one phone can authorise exactly one
--       active admin identity.
--
-- The rehearsal on 3 August 2026 proved (a) cannot be undone while (b) stands: the UPDATE fails
-- with 23505, duplicate key on control_mode_identity_one_active_per_phone. Both production
-- identities share phone_secret_key = 'admin_mfa_phone'.
--
-- So reverting p1h_06 means DROPPING that index, which reinstates exactly the weakness p1h_06
-- closed: possession of a single handset yields two Control Mode identities, and the MFA on the
-- privileged-action gate stops being one-person-one-identity.
--
-- That is a decision, not a rollback step, so it is opt-in. To enable it for one session:
--
--     set local qd.revert_p1h_06 = 'on';
--
-- Rehearsed with the switch on: index dropped, 2/2 identities reactivated, both notes stripped
-- back to their pre-p1h_06 text. With the switch off, this block is a no-op and the surviving
-- deactivation is reported so it is not a silent omission.
do $$
declare n int;
begin
  if coalesce(current_setting('qd.revert_p1h_06', true), 'off') <> 'on' then
    select count(*) into n from public.control_mode_identity
     where active is not true and note like '% | deactivated %';
    if n > 0 then
      raise warning 'phase1 rollback 1.3: NOT REVERTED - % Control Mode identity(ies) remain deactivated by p1h_06. Reverting requires dropping control_mode_identity_one_active_per_phone, which reinstates two admin identities on one phone. Set qd.revert_p1h_06 = ''on'' only if that is intended.', n;
    end if;
    return;
  end if;

  drop index if exists public.control_mode_identity_one_active_per_phone;
  update public.control_mode_identity
     set active = true,
         note = btrim(split_part(note, ' | deactivated ', 1))
   where active is not true
     and note like '% | deactivated %';
  raise warning 'phase1 rollback 1.3: p1h_06 REVERTED - control_mode_identity_one_active_per_phone dropped and identities reactivated. More than one admin identity can now share a phone.';
end $$;


-- 1.4 --------------------------------------------------------------------------------
-- p1h_10 made refunds.amount_fils nullable so a Stripe event with an unknown amount could still
-- be recorded rather than dropped. Re-tighten ONLY if the relaxation is currently unused. If it
-- is in use, that is a real refund with a genuinely unknown amount and the constraint must stay
-- relaxed - deleting the row to satisfy a constraint would be destroying evidence to tidy a schema.
do $$
declare n int;
begin
  select count(*) into n from public.refunds where amount_fils is null;
  if n = 0 then
    alter table public.refunds alter column amount_fils set not null;
    raise notice 'phase1 rollback 1.4: refunds.amount_fils re-tightened to NOT NULL';
  else
    raise warning 'phase1 rollback 1.4: LEFT RELAXED - % refund row(s) have an unknown amount. Resolve them with fn_refund_amount_resolve() first, then re-run this section.', n;
  end if;
end $$;


-- 1.5 --------------------------------------------------------------------------------
-- Phase 1's two cron jobs. control_mode_sweep_5min is already unscheduled by 1.1 (tier 0).
-- supplier_exception_sweep_daily was created by p1_03b; it is currently inactive in production,
-- and this deactivates it explicitly so the rollback does not depend on that happening to be true.
--
-- CORRECTED 3 Aug 2026 by rehearsal. This step was first written as
--     update cron.job set active = false where jobname = '...';
-- which fails with 42501 "permission denied for table job" - the Supabase roles cannot write
-- cron.job directly, only call the pg_cron API. cron.alter_job() is the supported route and was
-- rehearsed successfully. An operator would have hit the 42501 mid-rollback.
do $$
declare jid bigint;
begin
  select jobid into jid from cron.job where jobname = 'supplier_exception_sweep_daily';
  if jid is null then
    raise notice 'phase1 rollback 1.5: supplier_exception_sweep_daily is not scheduled; nothing to do';
  else
    perform cron.alter_job(jid, active := false);
    raise notice 'phase1 rollback 1.5: supplier_exception_sweep_daily deactivated (jobid %)', jid;
  end if;
end $$;


-- 1.6 --------------------------------------------------------------------------------
select public.fn_phase1_status() as phase1_status_after_tier1;

-- Record what was done. Append-only; this row cannot be edited or deleted afterwards.
insert into public.phase1_rollback_log (actor, tier, reason, detail)
values ('rollback:phase1_down.sql section 1', 'revert',
        'tier 1 revert executed - gate disarmed, fn_refund_status_rank restored, amount_fils re-tightened if unused, crons stopped. p1h_06 identity revert only if qd.revert_p1h_06 was on',
        public.fn_phase1_status());


-- =====================================================================================
-- SECTION 2 - TIER 2 TEARDOWN
-- DESTRUCTIVE. Drops the Phase 1 objects. Run section 1 first and confirm it was not enough.
--
-- Section 2a exports the evidence. Section 2b refuses to run without it. Do not "helpfully"
-- delete the guard: the guard is the control.
-- =====================================================================================

-- 2a ---------------------------------------------------------------------------------
create schema if not exists archive;

create table if not exists archive.phase1_refunds                  as select * from public.refunds                  where false;
create table if not exists archive.phase1_refund_event_quarantine  as select * from public.refund_event_quarantine  where false;
create table if not exists archive.phase1_refund_status_transition as select * from public.refund_status_transition where false;
create table if not exists archive.phase1_control_mode_audit       as select * from public.control_mode_audit       where false;
create table if not exists archive.phase1_control_mode_action      as select * from public.control_mode_action      where false;
create table if not exists archive.phase1_control_mode_identity    as select * from public.control_mode_identity    where false;
create table if not exists archive.phase1_control_mode_session     as select * from public.control_mode_session     where false;
create table if not exists archive.phase1_control_mode_challenge   as select * from public.control_mode_challenge   where false;

truncate archive.phase1_refunds, archive.phase1_refund_event_quarantine, archive.phase1_refund_status_transition,
        archive.phase1_control_mode_audit, archive.phase1_control_mode_action, archive.phase1_control_mode_identity,
        archive.phase1_control_mode_session, archive.phase1_control_mode_challenge;

insert into archive.phase1_refunds                  select * from public.refunds;
insert into archive.phase1_refund_event_quarantine  select * from public.refund_event_quarantine;
insert into archive.phase1_refund_status_transition select * from public.refund_status_transition;
insert into archive.phase1_control_mode_audit       select * from public.control_mode_audit;
insert into archive.phase1_control_mode_action      select * from public.control_mode_action;
insert into archive.phase1_control_mode_identity    select * from public.control_mode_identity;
insert into archive.phase1_control_mode_session     select * from public.control_mode_session;
insert into archive.phase1_control_mode_challenge   select * from public.control_mode_challenge;

-- 2b ---------------------------------------------------------------------------------
-- Row-for-row proof that the export completed. Anything short of exact aborts the teardown.
do $$
declare bad text := '';
begin
  if (select count(*) from public.refunds)                  <> (select count(*) from archive.phase1_refunds)                  then bad := bad || 'refunds '; end if;
  if (select count(*) from public.refund_event_quarantine)  <> (select count(*) from archive.phase1_refund_event_quarantine)  then bad := bad || 'refund_event_quarantine '; end if;
  if (select count(*) from public.refund_status_transition) <> (select count(*) from archive.phase1_refund_status_transition) then bad := bad || 'refund_status_transition '; end if;
  if (select count(*) from public.control_mode_audit)       <> (select count(*) from archive.phase1_control_mode_audit)       then bad := bad || 'control_mode_audit '; end if;
  if (select count(*) from public.control_mode_action)      <> (select count(*) from archive.phase1_control_mode_action)      then bad := bad || 'control_mode_action '; end if;
  if (select count(*) from public.control_mode_identity)    <> (select count(*) from archive.phase1_control_mode_identity)    then bad := bad || 'control_mode_identity '; end if;
  if (select count(*) from public.control_mode_session)     <> (select count(*) from archive.phase1_control_mode_session)     then bad := bad || 'control_mode_session '; end if;
  if (select count(*) from public.control_mode_challenge)   <> (select count(*) from archive.phase1_control_mode_challenge)   then bad := bad || 'control_mode_challenge '; end if;
  if bad <> '' then
    raise exception 'PHASE 1 TEARDOWN REFUSED - evidence export incomplete for: %. Nothing has been dropped. Re-run section 2a.', bad
      using errcode = '55000';
  end if;
  raise notice 'phase1 rollback 2b: evidence export verified row-for-row; teardown may proceed';
end $$;

-- 2c ---------------------------------------------------------------------------------
-- Crons first, so nothing fires against a half-dropped schema.
do $$ begin perform cron.unschedule('control_mode_sweep_5min');      exception when others then null; end $$;
do $$ begin perform cron.unschedule('supplier_exception_sweep_daily'); exception when others then null; end $$;

-- 2d  functions ----------------------------------------------------------------------
drop function if exists public.fn_control_mode_require(text,text)                                cascade;
drop function if exists public.fn_control_mode_open(text,text,uuid,text,text,uuid,text,text)     cascade;
drop function if exists public.fn_control_mode_close(text)                                       cascade;
drop function if exists public.fn_control_mode_status(text)                                      cascade;
drop function if exists public.fn_control_mode_sweep()                                           cascade;
drop function if exists public.fn_control_mode_challenge_start(text,text,text)                   cascade;
drop function if exists public.fn_control_mode_challenge_minutes()                               cascade;
drop function if exists public.fn_control_mode_identity_active(text)                             cascade;
drop function if exists public.fn_control_mode_minutes()                                         cascade;

drop function if exists public.fn_refund_request(bigint,text,text,uuid,uuid,bigint,uuid,text,text,text,uuid) cascade;
drop function if exists public.fn_refund_decide(bigint,boolean,text,text)                        cascade;
drop function if exists public.fn_refund_settle(text,text,bigint,text,text,text,text,text)       cascade;
drop function if exists public.fn_refund_quarantine(text,text,text,jsonb,text)                   cascade;
drop function if exists public.fn_refund_amount_resolve(text,bigint,text,text,text)              cascade;
drop function if exists public.fn_refund_transition_allowed(text,text)                           cascade;
drop function if exists public.fn_refund_state(uuid)                                             cascade;
drop function if exists public.fn_refund_status_rank(text)                                       cascade;

drop function if exists public.fn_supplier_exception_open(bigint,text)                           cascade;
drop function if exists public.fn_supplier_exception_close(bigint,text)                          cascade;
drop function if exists public.fn_supplier_exception_sweep()                                     cascade;
drop function if exists public.fn_supplier_exception_days()                                      cascade;

drop function if exists public.fn_ops_authority_check(text,text,numeric,text)                    cascade;
drop function if exists public.fn_ops_department_context(text,text,integer)                      cascade;

-- 2e  views --------------------------------------------------------------------------
drop view if exists public.v_refund_metrics            cascade;
drop view if exists public.v_refunds_unreconciled      cascade;
drop view if exists public.v_refund_quarantine_open    cascade;
drop view if exists public.v_supplier_exception_queue  cascade;
drop view if exists public.v_supplier_exception_health cascade;

-- 2f  tables (indexes and triggers go with them) -------------------------------------
drop table if exists public.refund_event_quarantine   cascade;
drop table if exists public.refund_status_transition  cascade;
drop table if exists public.refunds                   cascade;
drop table if exists public.control_mode_audit        cascade;
drop table if exists public.control_mode_session      cascade;
drop table if exists public.control_mode_challenge    cascade;
drop table if exists public.control_mode_action       cascade;
drop table if exists public.control_mode_identity     cascade;

-- 2g ---------------------------------------------------------------------------------
-- The rollback ledger and its controls are deliberately NOT dropped. They are the record that
-- this teardown happened, and dropping the log of a destructive act as part of that act is how
-- an incident becomes unexplainable. fn_phase1_disarmed() keeps working (it reads only its own
-- log); fn_control_mode_require is gone, which is the point of a teardown.
insert into public.phase1_rollback_log (actor, tier, reason, detail)
values ('rollback:phase1_down.sql section 2', 'teardown',
        'tier 2 teardown executed - Phase 1 objects dropped, evidence exported to schema archive',
        jsonb_build_object(
          'archived_refunds',            (select count(*) from archive.phase1_refunds),
          'archived_control_mode_audit', (select count(*) from archive.phase1_control_mode_audit),
          'archived_control_mode_action',(select count(*) from archive.phase1_control_mode_action)));

-- 2h  callers you must fix in the same window ----------------------------------------
-- Dropping fn_control_mode_require breaks three deployed edge functions that call it by RPC.
-- They fail CLOSED by construction (a failed RPC is treated as "not allowed"), so a teardown
-- without a redeploy locks every mutating admin action rather than opening it. That is the safe
-- failure, but it is still an outage. Redeploy these in the same window:
--
--   os_ops       - the Control Mode gate ahead of its 18 mutating actions
--   refunds_api  - the same gate on refund_resolve
--   os_api       - action classification
--
-- Search them for 'fn_control_mode_require' and remove the gate block before deploying.

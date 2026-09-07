-- EIGHT LIVE W04 RUNS FOR CUSTOMERS THAT NO LONGER EXIST, AND A BOARD THAT COULD NOT SEE THEM.
--
-- NO TRANSACTION CONTROL. Four routines, two triggers and one assertion block; rehearsable.
-- Nothing here is a frozen Phase C subject: public.phase_c_frozen_subject lists 25 objects and
-- fn_kernel_orphaned_work is not among them. fn_kernel_cancel and fn_kernel_workflow_start ARE
-- frozen and are NOT touched — the prevention below is a trigger on public.phase_c_workflow_run,
-- which is a table, so no PCCR amendment is raised by this file.
--
-- ================================================================================================
-- WHAT HAPPENED
-- ================================================================================================
--
-- On 2026-08-26 eight W04 runs were opened for customer_account business objects:
--
--   209068 209069 209070 209071 209072 209073 209193 209194
--
-- all `active`, each with one active W04-S01 step run, one queued task and one delivered
-- EV-W04-STARTED outbox row. Every one of their customers had been deleted. The fixture drives that
-- created those customers ran their zero-residue cleanup against public.customers and stopped
-- there: the customer row is what the cleanup knew about, and the kernel work the customer's own
-- INSERT trigger (z50_customer_registered_kernel_emit) had committed was not.
-- public.phase_d_effect_ledger holds 0 rows for those step runs, so no external effect was produced
-- and nothing left the estate.
--
-- They were closed on 2026-08-27 through the canonical path — fn_kernel_cancel, subject_kind
-- workflow_run, one call per run, reason ORPHANED_PARENT_MISSING_PRE_FIX — which cancels the run,
-- the step run and the task, supersedes any undelivered outbox row, seals every open trace and
-- REFUSES ITS OWN TRANSACTION if any queued derived work is left behind. No row was deleted and no
-- customer was recreated to make a board green. Measured after: 8 runs cancelled, 8 step runs
-- cancelled, 8 tasks cancelled, 24 open traces sealed, 0 open handoffs (there were none), 0 outbox
-- rows superseded — all eight had already been delivered, and a delivered event is a fact that
-- happened.
--
-- ================================================================================================
-- WHY NOTHING SAW IT
-- ================================================================================================
--
-- fn_kernel_orphaned_work asked one question in six ways: *is there live work under a CANCELLED
-- command or a CANCELLED run?* Every one of its six rows read `0 of N` and every one was correct.
-- These eight runs were not under a cancelled anything. Their parent had been DELETED, and a
-- deleted parent leaves no cancelled row to hang the question on — so the board had no denominator
-- that could ever contain them.
--
-- The map that can answer it already exists: public.phase_d_business_object_binding gives each of
-- the 56 canonical business objects its canonical relation and its primary identity column, and a
-- run's business_object_id is `<object_id>:<identity>`. That is used here rather than a
-- customer-only hard-coded check, so the next object to lose a parent is found by the same rows.
--
-- ================================================================================================
-- THE SECOND CLASS, FOUND BY WRITING THE FIRST ONE: A SUBJECT KEYED OUTSIDE ITS OWN BINDING
-- ================================================================================================
--
-- The strict form of the question — "does this identity resolve in the relation its binding names?"
-- — returns run 352 as well: W29, `active` since 2026-08-17, business_object_id
-- `incident:agent_action:3833`. The `incident` binding names public.os_incidents keyed on `id`,
-- whose ids are bigints 1..32. `agent_action:3833` is not one of them and never was.
--
-- IT IS NOT AN ORPHAN. public.agent_actions row 3833 EXISTS and is still `pending` — agent
-- `security`, kind `security_incident`, risk `high`, "10 high/critical security event(s) in the last
-- 7 days". Its producer is the db trigger trg_page_high_agent_action on public.agent_actions,
-- recorded CONNECTED_ACTIVE. The parent is alive; it is the SUBJECT KEY that disagrees. W29 writes
-- `incident:agent_action:<agent_actions.id>` and the canonical map says `incident:<os_incidents.id>`.
--
-- Two consequences, both taken:
--
--   * The run is NOT cancelled. Cancelling live work about a live, still-pending high-severity
--     security item to make a count read zero is exactly the move this estate does not make. It is
--     reported by name, with the row that does back it, in its own board line.
--   * The resolver therefore does not stop at the binding. If the identity is itself of the form
--     `<token>:<id>`, it looks for a public table named `<token>` or `<token>s` carrying that id.
--     That is generic — no allow-list, no per-case exemption register — and it is what stops the
--     prevention trigger below from refusing every future high-severity security page.
--
-- The disagreement between the W29 producer and the canonical map is a real finding and is recorded
-- as one; it is not repaired here, because re-keying a committed run is not possible and changing
-- what the security pager emits is business automation, which this session is holding.
--
-- ================================================================================================
-- HONEST DENOMINATOR
-- ================================================================================================
--
-- Not every business_object_id prefix is in the map: `founder_command:` and `outbox:` are
-- kernel-internal subjects with no business-object binding, and two 2026-08-16 canaries carry a
-- bare `ZZ-CANARY-…` with no prefix at all. Those are counted and named in the same informational
-- row rather than silently passed, because a prefix nobody has bound is a subject nobody is
-- checking, and reporting it as clean is the failure mode this whole file is about.
--
-- ================================================================================================

-- ---- 1. THE RESOLVER ----------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_business_subject_resolve was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_kernel_business_subject_resolve(text) from public;
revoke execute on function public.fn_kernel_business_subject_resolve(text) from anon;
revoke execute on function public.fn_kernel_business_subject_resolve(text) from authenticated;

-- ---- 2. THE DETECTOR ----------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_business_parent_missing was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_kernel_business_parent_missing() from public;
revoke execute on function public.fn_kernel_business_parent_missing() from anon;
revoke execute on function public.fn_kernel_business_parent_missing() from authenticated;

-- ---- 3. THE BOARD -------------------------------------------------------------------------------
-- The six original rows are unchanged, word for word. Seven more are added beside them; none of the
-- existing expectations moves.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_orphaned_work was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---- 4. PREVENTION A: A RUN MAY NOT OPEN ON A PARENT THAT IS NOT THERE ---------------------------
-- fn_kernel_workflow_start is a frozen Phase C subject, so the refusal is attached to the table it
-- writes. a10_ so that it fires AFTER a00_kernel_write_guard and a00_kernel_workflow_run_trace_guard
-- (Postgres fires BEFORE triggers in NAME order, which is why the a00_/z10_ convention exists here).
--
-- It refuses ONLY when the resolver returns PARENT_MISSING. UNMAPPED_PREFIX is not refused —
-- inventing a rule for subjects nobody mapped would break founder_command: and outbox: to satisfy a
-- check — and KEYED_OUTSIDE_ITS_BINDING is not refused, which is what keeps
-- trg_page_high_agent_action working for the next high-severity security event.
create or replace function public.fn_kernel_workflow_run_parent_exists()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare s record; v_fx bigint;
begin
  select * into s from public.fn_kernel_business_subject_resolve(NEW.business_object_id);

  -- INSIDE A VERIFIED PHASE D FIXTURE CONTEXT, A MANUFACTURED SUBJECT IS THE POINT.
  -- The Phase D drives open workflows on subjects they invent — dispatch_batch:chk-w12-s06,
  -- payment_transaction:chk-w16-s05 — inside a transaction that always aborts. Refusing those broke
  -- five Phase D checks on the afternoon this guard was written, and "an identity is never a
  -- fixture" is a rule about what a check may PROVE, not a reason to make the checks unrunnable.
  --
  -- This is not an allow-list and not a GUC anyone can set. fn_phase_d_fixture_context() recomputes
  -- an HMAC over the current txid, the approved operation key and the audited grant row, and returns
  -- null for an absent context, a hand-set GUC, a token from another transaction, or a grant that
  -- does not exist (F01). Opening one requires an ENABLED row in public.phase_d_test_operation and
  -- refuses anon and authenticated outright, so no production path — no browser, no edge function,
  -- no cron job — can obtain one. The exemption is transaction-local, audited by fixture_run_id, and
  -- gone the moment the transaction ends.
  begin v_fx := public.fn_phase_d_fixture_context(); exception when others then v_fx := null; end;
  if v_fx is not null then
    return NEW;
  end if;

  if s.resolution = 'PARENT_MISSING' then
    raise exception 'phase_c_workflow_run: % names business object %, and no row of % has %=%. A workflow may not be opened for a business object that does not exist -- that is how eight W04 runs came to be active for customers nobody could find. (kernel_workflow_start_parent_missing)',
      NEW.workflow_id, NEW.business_object_id, s.canonical_relation, s.identity_column, s.identity_value
      using errcode = '23503',
            hint = 'Create the business object first, or close the work with fn_kernel_cancel.';
  end if;
  return NEW;
end
$function$;

-- A plain CREATE grants EXECUTE to PUBLIC, and a trigger function is no exception. Revoked in the
-- same file, because scripts/checks/anon_cannot_execute_security_definer.test.mjs is the check that
-- caught this one and it is right: nothing calls a trigger function by name, so nobody needs it.
revoke execute on function public.fn_kernel_workflow_run_parent_exists() from public;
revoke execute on function public.fn_kernel_workflow_run_parent_exists() from anon;
revoke execute on function public.fn_kernel_workflow_run_parent_exists() from authenticated;

drop trigger if exists a10_kernel_workflow_run_parent_exists on public.phase_c_workflow_run;
create trigger a10_kernel_workflow_run_parent_exists
  before insert on public.phase_c_workflow_run
  for each row execute function public.fn_kernel_workflow_run_parent_exists();

-- ---- 5. PREVENTION B: DELETING A PARENT CLOSES ITS WORK FIRST -----------------------------------
-- One generic trigger function, attached to the canonical relations a workflow run is opened
-- against. It reads the same binding map, so a table added to that map and given this trigger needs
-- no new code.
--
-- IT COMPENSATES; IT DOES NOT REFUSE, and the first version of this file had it the other way round.
-- Refusing was measured against the estate the same afternoon and broke it: every fixture that
-- creates a customer relies on deleting that customer to clean up, the customer's own INSERT trigger
-- z50_customer_registered_kernel_emit opens a W04 run, so the delete was refused and two ZZ DEMO
-- rows were left committed on production. fn_phase_d_fixture_residue() went 0 -> 2 and four Phase D
-- checks went red. A guard that turns every cleanup into residue does not prevent orphans; it
-- manufactures them.
--
-- Cancelling first is the stronger half of the founder's own instruction ("refuses while active work
-- exists, OR performs canonical compensation/cancellation first"): a refusal can be worked around by
-- a caller that gives up on the delete and leaves the row, while compensation means an orphan cannot
-- be produced by a delete at all. It runs BEFORE the row goes, so business_object_id still resolves;
-- it goes through fn_kernel_cancel, which is the canonical path and refuses its own transaction if
-- it leaves queued derived work behind; and it is loud -- a NOTICE per run, and the closure evidence
-- on every cancelled run names the deletion that caused it.
--
-- This is also what a PDPL erasure should do. Deleting a customer while their onboarding run stays
-- open is not privacy; it is a dangling workflow about a person who no longer exists.
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_business_parent_delete_guard was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_kernel_business_parent_delete_guard() from public;
revoke execute on function public.fn_kernel_business_parent_delete_guard() from anon;
revoke execute on function public.fn_kernel_business_parent_delete_guard() from authenticated;

do $attach$
declare t text;
begin
  -- The EXISTING_TABLE relations a workflow run has ever been opened against, plus public.customers,
  -- which is the one this file exists because of. Adding another is one array entry.
  foreach t in array array['public.customers','public.inquiries','public.quotes','public.transactions',
                           'public.leads','public.refunds','public.os_incidents']
  loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists a00_kernel_parent_delete_guard on %s', t);
      execute format('create trigger a00_kernel_parent_delete_guard before delete on %s '
                  || 'for each row execute function public.fn_kernel_business_parent_delete_guard()', t);
    end if;
  end loop;
end $attach$;

-- ---- 6. THE ASSERTIONS --------------------------------------------------------------------------
do $assert$
declare v_orphan int; v_other int; v_rows int; v_red int; v_trig int;
begin
  select count(*) filter (where resolution = 'PARENT_MISSING'),
         count(*) filter (where resolution <> 'PARENT_MISSING')
    into v_orphan, v_other from public.fn_kernel_business_parent_missing();
  select count(*), count(*) filter (where not ok) into v_rows, v_red from public.fn_kernel_orphaned_work();
  select count(*) into v_trig from pg_trigger
   where tgname = 'a00_kernel_parent_delete_guard' and not tgisinternal;

  if v_rows < 13 then
    raise exception 'the orphan board lost rows: % (expected the original 6 plus 7 more)', v_rows;
  end if;
  if v_orphan <> 0 then
    raise exception 'active work with a missing business parent still stands: % run(s)', v_orphan;
  end if;
  if v_red <> 0 then
    raise exception 'the orphan board is red on % row(s)', v_red;
  end if;
  if v_trig < 7 then
    raise exception 'the parent-delete guard is attached to % table(s), expected 7', v_trig;
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'a10_kernel_workflow_run_parent_exists' and not tgisinternal) then
    raise exception 'the workflow-start parent guard is not attached';
  end if;
  -- Nothing this file creates may answer an unauthenticated or signed-in caller by name.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname in ('fn_kernel_business_subject_resolve','fn_kernel_business_parent_missing',
                                  'fn_kernel_workflow_run_parent_exists','fn_kernel_business_parent_delete_guard')
                and (has_function_privilege('anon', p.oid, 'EXECUTE')
                  or has_function_privilege('authenticated', p.oid, 'EXECUTE'))) then
    raise exception 'a routine created by this file is executable by anon or authenticated';
  end if;
  raise notice 'OK  parent_missing=%  keyed_outside_or_unmapped=%  board_rows=%  board_red=%  delete_guards=%',
    v_orphan, v_other, v_rows, v_red, v_trig;
end
$assert$;

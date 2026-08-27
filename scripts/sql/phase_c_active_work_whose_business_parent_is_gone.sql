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
create or replace function public.fn_kernel_business_subject_resolve(p_business_object_id text)
returns table(object_id text, canonical_relation text, identity_column text, identity_value text,
              resolution text, resolved_in text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare b record; v_found boolean; v_tok text; v_tail text; c text; v_obj text;
begin
  v_obj := split_part(coalesce(p_business_object_id,''), ':', 1);
  object_id := v_obj;
  if p_business_object_id is null or position(':' in p_business_object_id) = 0 then
    canonical_relation := null; identity_column := null; identity_value := null;
    resolution := 'UNMAPPED_PREFIX'; resolved_in := null;
    return next; return;
  end if;
  identity_value := substring(p_business_object_id from char_length(v_obj) + 2);

  select bo.canonical_relation, bo.primary_identity into b
    from public.phase_d_business_object_binding bo
   where bo.object_id = v_obj
     and coalesce(btrim(bo.canonical_relation),'') <> ''
     and coalesce(btrim(bo.primary_identity),'') <> ''
     and to_regclass(bo.canonical_relation) is not null;
  if not found then
    canonical_relation := null; identity_column := null;
    resolution := 'UNMAPPED_PREFIX'; resolved_in := null;
    return next; return;
  end if;
  canonical_relation := b.canonical_relation;
  identity_column    := b.primary_identity;

  -- The identity is compared AS TEXT on both sides. A uuid column cast to text never raises on a
  -- value that is not a uuid, and `p.id = 'not-a-uuid'::uuid` does — which would turn a malformed
  -- business_object_id into an error instead of a finding.
  execute format('select exists (select 1 from %s p where p.%I::text = $1)',
                 canonical_relation, identity_column)
     into v_found using identity_value;
  if v_found then
    resolution := 'RESOLVED'; resolved_in := canonical_relation;
    return next; return;
  end if;

  -- SECOND CHANCE, GENERIC. `incident:agent_action:3833` names its own relation inside the identity.
  -- Take the leading token and look for a public table called <token> or <token>s carrying that id.
  -- No allow-list and no per-case exemption: either such a table exists and holds the row, or it
  -- does not.
  if position(':' in identity_value) > 0 then
    v_tok  := split_part(identity_value, ':', 1);
    v_tail := substring(identity_value from char_length(v_tok) + 2);
    foreach c in array array['public.' || v_tok, 'public.' || v_tok || 's'] loop
      if to_regclass(c) is not null
         and exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = split_part(c,'.',2)
                        and column_name = 'id') then
        execute format('select exists (select 1 from %s p where p.id::text = $1)', c)
           into v_found using v_tail;
        if v_found then
          resolution := 'KEYED_OUTSIDE_ITS_BINDING'; resolved_in := c;
          return next; return;
        end if;
      end if;
    end loop;
  end if;

  resolution := 'PARENT_MISSING'; resolved_in := null;
  return next;
end
$function$;
revoke execute on function public.fn_kernel_business_subject_resolve(text) from public;
revoke execute on function public.fn_kernel_business_subject_resolve(text) from anon;
revoke execute on function public.fn_kernel_business_subject_resolve(text) from authenticated;

-- ---- 2. THE DETECTOR ----------------------------------------------------------------------------
create or replace function public.fn_kernel_business_parent_missing()
returns table(run_id bigint, workflow_id text, state text, business_object_id text,
              object_id text, canonical_relation text, identity_column text, identity_value text,
              resolution text, resolved_in text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select r.run_id, r.workflow_id, r.state, r.business_object_id,
         s.object_id, s.canonical_relation, s.identity_column, s.identity_value,
         s.resolution, s.resolved_in
    from public.phase_c_workflow_run r
    cross join lateral public.fn_kernel_business_subject_resolve(r.business_object_id) s
   where r.state not in ('cancelled','superseded','completed','failed')
     and s.resolution <> 'RESOLVED'
   order by r.run_id;
$function$;
revoke execute on function public.fn_kernel_business_parent_missing() from public;
revoke execute on function public.fn_kernel_business_parent_missing() from anon;
revoke execute on function public.fn_kernel_business_parent_missing() from authenticated;

-- ---- 3. THE BOARD -------------------------------------------------------------------------------
-- The six original rows are unchanged, word for word. Seven more are added beside them; none of the
-- existing expectations moves.
create or replace function public.fn_kernel_orphaned_work()
returns TABLE(check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with dead as (
    select c.command_id from public.founder_command c where c.state in ('cancelled','superseded')
  ), dead_runs as (
    select r.run_id from public.phase_c_workflow_run r
     where r.command_id in (select command_id from dead)
        or r.state in ('cancelled','superseded')
  ), unresolved as (
    select * from public.fn_kernel_business_parent_missing()
  ), orphan as (
    select * from unresolved where resolution = 'PARENT_MISSING'
  ), orphan_runs as (
    select o.run_id from orphan o
  ), live_runs as (
    select r.run_id from public.phase_c_workflow_run r
     where r.state not in ('cancelled','superseded','completed','failed')
  )
  select 'live_tasks_of_cancelled_commands',  '0',
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked')) = 0
    from public.phase_c_task t
   where t.command_id in (select command_id from dead) or t.run_id in (select run_id from dead_runs)
  union all
  select 'live_runs_of_cancelled_commands', '0',
         count(*) filter (where r.state not in ('cancelled','superseded','completed','failed'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where r.state not in ('cancelled','superseded','completed','failed')) = 0
    from public.phase_c_workflow_run r where r.command_id in (select command_id from dead)
  union all
  select 'live_step_runs_of_cancelled_runs', '0',
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded')) = 0
    from public.phase_c_workflow_step_run s where s.run_id in (select run_id from dead_runs)
  union all
  select 'open_handoffs_of_cancelled_runs', '0',
         count(*) filter (where h.status = 'open')::text || ' of ' || count(*)::text,
         count(*) filter (where h.status = 'open') = 0
    from public.phase_c_handoff_run h where h.run_id in (select run_id from dead_runs)
  union all
  select 'undelivered_outbox_of_cancelled_commands', '0',
         count(*) filter (where o.status in ('pending','claimed','retry_wait'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where o.status in ('pending','claimed','retry_wait')) = 0
    from public.phase_c_event_outbox o
   where (o.payload->>'command_id') in (select command_id::text from dead)
  union all
  select 'open_traces_of_cancelled_subjects', '0',
         count(*) filter (where tr.sealed_at is null)::text || ' of ' || count(*)::text,
         count(*) filter (where tr.sealed_at is null) = 0
    from public.phase_c_trace tr
   where tr.command_id in (select command_id from dead) or tr.run_id in (select run_id from dead_runs)

  -- ---- ADDED 27 AUG 2026. A PARENT THAT WAS DELETED LEAVES NO CANCELLED ROW TO ASK ABOUT. ------
  union all
  select 'active_runs_whose_business_parent_is_gone', '0',
         (select count(*) from orphan)::text || ' of '
           || (select count(*) from live_runs)::text || ' active runs'
           || case when (select count(*) from orphan) = 0 then ''
                   else ': ' || (select string_agg(o.run_id || ' ' || o.workflow_id || ' '
                                                || o.business_object_id || ' (no row in '
                                                || o.canonical_relation || ')', ', ' order by o.run_id)
                                   from orphan o) end,
         (select count(*) from orphan) = 0
  union all
  select 'active_step_runs_under_a_missing_parent', '0',
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where s.state not in ('cancelled','completed','failed','superseded')) = 0
    from public.phase_c_workflow_step_run s where s.run_id in (select run_id from orphan_runs)
  union all
  select 'live_tasks_under_a_missing_parent', '0',
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where t.state in ('queued','assigned','accepted','in_progress','blocked')) = 0
    from public.phase_c_task t where t.run_id in (select run_id from orphan_runs)
  union all
  select 'open_handoffs_under_a_missing_parent', '0',
         count(*) filter (where h.status = 'open')::text || ' of ' || count(*)::text,
         count(*) filter (where h.status = 'open') = 0
    from public.phase_c_handoff_run h where h.run_id in (select run_id from orphan_runs)
  union all
  select 'undeliverable_outbox_under_a_missing_parent', '0',
         count(*) filter (where o.status in ('pending','claimed','retry_wait'))::text
           || ' of ' || count(*)::text,
         count(*) filter (where o.status in ('pending','claimed','retry_wait')) = 0
    from public.phase_c_event_outbox o where o.workflow_run_id in (select run_id from orphan_runs)
  union all
  select 'open_traces_whose_run_subject_has_no_parent', '0',
         count(*) filter (where tr.sealed_at is null)::text || ' of ' || count(*)::text,
         count(*) filter (where tr.sealed_at is null) = 0
    from public.phase_c_trace tr where tr.run_id in (select run_id from orphan_runs)
  union all
  -- NOT A PASS AND NOT A FAILURE. A live parent under a key the canonical map does not describe, and
  -- a prefix nobody has bound, are both real disagreements and both are NAMED here rather than
  -- absorbed. Cancelling live work about a live parent to make a count read zero is not available.
  select 'active_runs_whose_subject_is_not_keyed_by_its_binding',
         'informational — each is named, with the row that does back it',
         (select count(*) from unresolved where resolution <> 'PARENT_MISSING')::text
           || ' of ' || (select count(*) from live_runs)::text || ' active runs'
           || case when (select count(*) from unresolved where resolution <> 'PARENT_MISSING') = 0 then ''
                   else ': ' || (select string_agg(u.run_id || ' ' || u.workflow_id || ' '
                                                || u.business_object_id || ' [' || u.resolution
                                                || coalesce(' -> ' || u.resolved_in, '') || ']',
                                                ', ' order by u.run_id)
                                   from unresolved u where u.resolution <> 'PARENT_MISSING') end,
         true;
$function$;

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
declare s record;
begin
  select * into s from public.fn_kernel_business_subject_resolve(NEW.business_object_id);
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
create or replace function public.fn_kernel_business_parent_delete_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare b record; v_id text; v_run record; v_left int;
begin
  for b in select bo.object_id, bo.primary_identity
             from public.phase_d_business_object_binding bo
            where bo.canonical_relation = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
              and coalesce(btrim(bo.primary_identity),'') <> ''
  loop
    v_id := to_jsonb(OLD) ->> b.primary_identity;
    if v_id is null then continue; end if;
    for v_run in
      select r.run_id, r.workflow_id, r.state from public.phase_c_workflow_run r
       where r.business_object_id = b.object_id || ':' || v_id
         and r.state not in ('cancelled','superseded','completed','failed')
       order by r.run_id
    loop
      raise notice 'kernel: closing % run % before %.% % = % is deleted',
        v_run.workflow_id, v_run.run_id, TG_TABLE_SCHEMA, TG_TABLE_NAME, b.primary_identity, v_id;
      perform public.fn_kernel_cancel(jsonb_build_object(
        'subject_kind','workflow_run', 'subject_ref', v_run.run_id::text, 'op','cancel',
        'actor','system.workflow_engine',
        'reason','PARENT_DELETED: ' || TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ' '
              || b.primary_identity || '=' || v_id || ' (business object ' || b.object_id
              || ') was deleted, so this run has nothing left to be about. Closed by '
              || 'a00_kernel_parent_delete_guard through the canonical cancellation path, in the '
              || 'same transaction as the delete, before the parent row went.'));
    end loop;

    -- THE POSTCONDITION, ASSERTED RATHER THAN ASSUMED. fn_kernel_cancel refuses its own transaction
    -- if it leaves queued derived work, but nothing so far has checked that the LOOP covered every
    -- run: a run opened between the two statements, or a state value this predicate does not know,
    -- would slip through and become exactly the orphan this file exists to stop.
    select count(*) into v_left from public.phase_c_workflow_run r
     where r.business_object_id = b.object_id || ':' || v_id
       and r.state not in ('cancelled','superseded','completed','failed');
    if v_left > 0 then
      raise exception 'public.%: % live workflow run(s) still name business object %:% after the compensation loop, so deleting this row would orphan them. (kernel_parent_delete_has_live_work)',
        TG_TABLE_NAME, v_left, b.object_id, v_id
        using errcode = '23503',
              hint = 'Close them first: select public.fn_kernel_cancel(jsonb_build_object('
                  || '''subject_kind'',''workflow_run'',''subject_ref'',''<run_id>'',''op'',''cancel'','
                  || '''actor'',''<who>'',''reason'',''<why>'')); then delete the parent.';
    end if;
  end loop;
  return OLD;
end
$function$;

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

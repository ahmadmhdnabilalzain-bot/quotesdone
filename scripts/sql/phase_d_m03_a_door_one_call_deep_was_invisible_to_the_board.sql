-- M03 — a door one call deep was invisible to the board that counted doors
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh.
--
-- public.fn_phase_d_outbound_state() reported "every outbound trigger on a Phase D relation is
-- registered, 4 of 4" and all nine of its checks green. Its denominator was built by matching
-- net.http_post in the TRIGGER FUNCTION's own body. public.leads carries trg_self_reg_category,
-- whose body posts nothing at all -- it calls public.fn_provision_category_call, and THAT posts to
-- /functions/v1/category_provision. A scan of all 345 public triggers with transitive reachability
-- finds five doors on Phase D relations, not four.
--
-- This is the estate's own recurring lens: an instrument reporting on a narrower subject than its
-- name claims. The board is now the transitive closure, so a helper -- and a helper's helper --
-- counts as the door it is, and the fifth door is registered with the reason it cannot fire.
--
-- WHY THE FIFTH DOOR IS UNREACHABLE, MEASURED NOT ASSUMED. trg_self_reg_category fires AFTER INSERT
-- OR UPDATE OF (categories, source) and only when source = 'self_registered' and categories is
-- non-empty. public.phase_d_object_write_map declares, for supplier_account, the columns email,
-- verified, company_name, approval_status and capability_enriched_at. Neither 'categories' nor
-- 'source' is among them, so no Phase D write can arm it -- and if one ever could,
-- fn_phase_d_object_write's own net.http_request_queue count aborts the transaction, which is the
-- backstop this registration does not replace.
--
-- ROLLBACK: re-apply the previous body,
-- scripts/sql/phase_d_d19_the_suppression_the_caller_could_defeat.sql
-- GENERATED from the live body by scripts/tmp_diag/gen_m03.mjs.

insert into public.phase_d_outbound_door
  (relation, trigger_name, function_name, endpoint, disposition, unreachable_because_column,
   guard_condition, note)
values
  ('public.leads', 'trg_self_reg_category', 'trg_self_reg_category', 'category_provision',
   'NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP', 'categories',
   'AFTER INSERT OR UPDATE OF categories, source; fires when source = ''self_registered'' and btrim(categories) <> '''' and no active category_agents row already covers it',
   'FOUND BY WIDENING THE SCAN, NOT BY THE OLD ONE. The trigger body contains no net.http_post; it calls public.fn_provision_category_call, which posts to /functions/v1/category_provision. The supplier_account write map declares neither categories nor source, so no Phase D write can arm it, and fn_phase_d_object_write''s own outbound count would abort the transaction if one ever did.')
on conflict (relation, trigger_name) do nothing;

CREATE OR REPLACE FUNCTION public.fn_phase_d_outbound_state()
 RETURNS TABLE(check_name text, expected text, actual text, state text, detail text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with pd_rel as (
  select distinct b.canonical_relation as relation
    from public.phase_d_business_object_binding b
   where b.relation_kind = 'EXISTING_TABLE'
),
-- M03. THE SCAN WAS DIRECT-ONLY, SO A DOOR ONE CALL DEEP WAS INVISIBLE TO ITS OWN DENOMINATOR.
-- This matched net.http_post in the TRIGGER FUNCTION's own body. public.leads carries
-- trg_self_reg_category, whose body posts nothing and calls fn_provision_category_call, which
-- posts to /functions/v1/category_provision. The board reported 4 of 4 registered and green while
-- a fifth door existed that it could not see -- an instrument reporting on a narrower subject than
-- its name claims. Measured 23 Aug 2026 across all 345 public triggers. Reachability is now the
-- transitive closure over public routines, so a helper, and a helper's helper, counts as the door
-- it is.
poster as (
  select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc ~* 'net[.]http_(post|get)'
),
reach as (
  -- ONE CALL DEEP, AND THAT BOUND IS STATED RATHER THAN LEFT TO BE DISCOVERED.
  -- The unbounded transitive closure was measured first and it takes the denominator from 4 to 15,
  -- because trg_inquiry_received_a, notify_matched_supplier, trg_new_quote_sms, z95_document_to_kernel
  -- and six more all reach net.http_post eventually THROUGH THE KERNEL's own chain -- and whether
  -- they ever do is a runtime condition, not a property of the trigger. Registering those ten as
  -- doors would say something this board has not measured. One hop says exactly what was measured:
  -- a trigger whose own body posts, or whose own body calls a routine that posts. The bound is real
  -- and this is where it is written down: a door TWO calls deep, or one reached through the kernel
  -- chain, is outside this denominator, and what catches it is fn_phase_d_object_write's own
  -- net.http_request_queue count on every fixture write -- which aborts the transaction rather than
  -- reporting a number.
  select p.oid, p.proname from poster p
  union
  select q.oid, q.proname
    from pg_proc q
    join pg_namespace nq on nq.oid = q.pronamespace
    -- NOT m. Measured: the management transport delivers 'm' with standard_conforming_strings
    -- off, so the backslash is eaten and the pattern silently becomes 'm' || proname -- a word
    -- boundary that matched nothing and left the widened scan reporting the same four doors as the
    -- narrow one. A non-word character before the name and an open bracket after it is the same
    -- assertion without a backslash in it.
    join poster r on q.prosrc ~ ('[^a-zA-Z0-9_]' || r.proname || '[[:space:]]*[(]')
   where nq.nspname = 'public' and q.oid <> r.oid
),
scanned as (
  select 'public.' || c.relname as relation, tg.tgname as trigger_name, p.proname as function_name,
         pg_get_triggerdef(tg.oid) as triggerdef
    from pg_trigger tg
    join pg_proc  p on p.oid = tg.tgfoid
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where not tg.tgisinternal and n.nspname = 'public'
     and p.oid in (select oid from reach)
     and ('public.' || c.relname) in (select relation from pd_rel)
),
sup as (select * from public.phase_d_outbound_door where disposition = 'SUPPRESSED_BY_ITS_OWN_GUARD'),
unr as (select * from public.phase_d_outbound_door where disposition = 'NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP')

-- 1. THE DENOMINATOR. Every outbound trigger the live scan finds on a Phase D canonical relation
--    must be registered. A new one appearing turns this red instead of quietly re-opening the door.
select 'every_outbound_trigger_on_a_phase_d_relation_is_registered',
       (select count(*)::text from scanned),
       (select count(*)::text from scanned s
         join public.phase_d_outbound_door d
           on d.relation = s.relation and d.trigger_name = s.trigger_name),
       case when (select count(*) from scanned)
               = (select count(*) from scanned s join public.phase_d_outbound_door d
                    on d.relation = s.relation and d.trigger_name = s.trigger_name)
            then 'GREEN' else 'RED' end,
       coalesce((select string_agg(s.relation || '.' || s.trigger_name, ', ')
                   from scanned s
                  where not exists (select 1 from public.phase_d_outbound_door d
                                     where d.relation = s.relation and d.trigger_name = s.trigger_name)),
                'every scanned outbound trigger is registered')

union all
select 'no_registered_door_names_a_trigger_that_does_not_exist',
       '0',
       (select count(*)::text from public.phase_d_outbound_door d
         where not exists (select 1 from scanned s
                            where s.relation = d.relation and s.trigger_name = d.trigger_name)),
       case when exists (select 1 from public.phase_d_outbound_door d
                          where not exists (select 1 from scanned s
                                             where s.relation = d.relation and s.trigger_name = d.trigger_name))
            then 'RED' else 'GREEN' end,
       'a registry row for a trigger that is gone would suppress a column for no reason'

-- 2. SUPPRESSED DOORS. The guard column must be real and must be declared in the write map, or the
--    writer cannot set it and the suppression is a comment rather than a mechanism.
union all
select 'every_guard_column_exists_on_its_relation',
       (select count(*)::text from sup),
       (select count(*)::text from sup d
         join pg_attribute a on a.attrelid = d.relation::regclass
                            and a.attname = d.guard_column and a.attnum > 0 and not a.attisdropped),
       case when (select count(*) from sup)
               = (select count(*) from sup d
                    join pg_attribute a on a.attrelid = d.relation::regclass
                                       and a.attname = d.guard_column and a.attnum > 0 and not a.attisdropped)
            then 'GREEN' else 'RED' end,
       'a guard column the relation does not have cannot suppress anything'

union all
select 'every_guard_column_is_declared_in_the_write_map',
       (select count(*)::text from sup),
       (select count(*)::text
          from sup d
          join public.phase_d_object_write_map wm on wm.target_relation = d.relation
         where wm.column_map ? d.guard_column),
       case when (select count(*) from sup)
               = (select count(*) from sup d
                    join public.phase_d_object_write_map wm on wm.target_relation = d.relation
                   where wm.column_map ? d.guard_column)
            then 'GREEN' else 'RED' end,
       'the writer may only touch a column the map declares; a suppression behind the map''s back is the defect this check exists for'

union all
select 'suppression_expression_is_evaluated_not_a_literal',
       (select count(*)::text from sup),
       (select count(*)::text from sup d where d.suppression_sql ~ '^[a-z_]+\('),
       case when (select count(*) from sup)
               = (select count(*) from sup d where d.suppression_sql ~ '^[a-z_]+\(')
            then 'GREEN' else 'RED' end,
       'each suppression is a function call the writer evaluates at write time, so now() is the write''s own clock'

-- 3. UNREACHABLE DOORS. "No Phase D write can reach this" is a claim, and these two checks are what
--    make it checkable. The named column must actually appear in the trigger's own definition, and
--    it must NOT be declared in the relation's write map. Add that column to a write map and this
--    goes red on the next board run rather than silently opening a door.
union all
select 'every_unreachable_reason_names_a_column_its_trigger_actually_tests',
       (select count(*)::text from unr),
       (select count(*)::text from unr d join scanned s
          on s.relation = d.relation and s.trigger_name = d.trigger_name
         where s.triggerdef ilike '%' || d.unreachable_because_column || '%'),
       case when (select count(*) from unr)
               = (select count(*) from unr d join scanned s
                    on s.relation = d.relation and s.trigger_name = d.trigger_name
                   where s.triggerdef ilike '%' || d.unreachable_because_column || '%')
            then 'GREEN' else 'RED' end,
       'a reason that quotes a column the trigger never mentions is not a reason'

union all
select 'no_unreachable_door_has_become_reachable_through_the_write_map',
       '0',
       (select count(*)::text
          from unr d join public.phase_d_object_write_map wm on wm.target_relation = d.relation
         where wm.column_map ? d.unreachable_because_column),
       case when exists (select 1 from unr d
                           join public.phase_d_object_write_map wm on wm.target_relation = d.relation
                          where wm.column_map ? d.unreachable_because_column)
            then 'RED' else 'GREEN' end,
       coalesce((select string_agg(d.relation || '.' || d.trigger_name || ' via ' || d.unreachable_because_column, ', ')
                   from unr d join public.phase_d_object_write_map wm on wm.target_relation = d.relation
                  where wm.column_map ? d.unreachable_because_column),
                'no write map declares a column that would arm a door recorded as unreachable')

-- 4. THE BACKSTOP IS STILL IN THE WRITER. If this goes red the suppression registry is decoration.
union all
select 'the_canonical_writer_still_counts_the_outbound_queue',
       '1',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
           and p.prosrc like '%pd_object_outbound_request_produced%'
           and p.prosrc like '%fn_phase_d_outbound_requests_by_this_transaction%'),
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'fn_phase_d_object_write'
                            and p.prosrc like '%pd_object_outbound_request_produced%'
                            and p.prosrc like '%fn_phase_d_outbound_requests_by_this_transaction%')
            then 'GREEN' else 'RED' end,
       'the registry closes the two doors that fire; the writer''s count is what catches a door nobody registered'

union all
select 'the_fixture_scenario_aborts_rather_than_recording_a_blocked_stage',
       '1',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'fn_phase_d_fixture_scenario'
           and p.prosrc like '%pd_object_outbound_request_produced%'),
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'fn_phase_d_fixture_scenario'
                            and p.prosrc like '%pd_object_outbound_request_produced%')
            then 'GREEN' else 'RED' end,
       'the per-stage handler catches everything; without this the refusal is swallowed into a blocked stage and error and empty return the same value'
$function$


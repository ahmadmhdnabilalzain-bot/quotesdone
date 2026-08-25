-- Q03 DOWN. UNDO THE CUSTOMER-CREATED PATH, THE TWO INVENTORY ROWS AND THE FOUR MEASUREMENT
-- CORRECTIONS.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- APPLYING THIS RESTORES THE DEFECT docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md row 1
-- measured: a customer_account created by any of eleven live paths with no workflow run, no task,
-- no accountable owner and no trace. It also restores the four false measurements. It exists so Q03
-- is reversible, not because reverting is advisable.
--
-- The view is DROPped and recreated rather than replaced: CREATE OR REPLACE VIEW cannot remove a
-- column, and the down direction removes unrouted_work_tables. Measured before writing this: no
-- other view depends on it (pg_depend, 0 rows), and fn_kernel_trigger_state is a function, which
-- takes no hard dependency.

DROP TRIGGER IF EXISTS z50_customer_registered_kernel_emit ON public.customers;
DROP FUNCTION IF EXISTS public.trg_customer_registered_kernel();

UPDATE public.kernel_trigger_type
   SET allowed_source_systems = array_remove(allowed_source_systems,
         'dbtrigger:public.customers:z50_customer_registered_kernel_emit'),
       implementation_state = 'ADAPTER_READY_NO_LIVE_SENDER'
 WHERE trigger_type = 'customer.registered';

DELETE FROM public.kernel_trigger_source
 WHERE source_key IN ('dbtrigger:public.customers:z50_customer_registered_kernel_emit',
                      'edge:drawing_redact');
DELETE FROM public.phase_c_source_cutover
 WHERE source_component_id IN ('dbtrigger:public.customers:z50_customer_registered_kernel_emit',
                               'edge:drawing_redact');

-- The four measurement corrections, reversed. The evidence Q03 appended is left in place: it is a
-- record of a measurement that was taken, and deleting it would make the reversal look like the
-- measurement never happened.
UPDATE public.kernel_trigger_source SET disposition = NULL
 WHERE source_key IN ('dbtrigger:public.quote_items:quote_items_rescore',
                      'dbtrigger:public.quote_items:trg_items_submittable');
UPDATE public.kernel_trigger_source SET recorded_creates_work = true
 WHERE source_key = 'edge:attach_photos';
UPDATE public.kernel_trigger_source
   SET recorded_creates_work = true, recorded_routes_through_inbox = false,
       disposition = CASE WHEN disposition = 'HUMAN_DRIVEN_SURFACE_NOT_AN_AUTONOMOUS_SOURCE'
                          THEN NULL ELSE disposition END
 WHERE source_kind = 'frontend_path';
UPDATE public.kernel_trigger_source SET recorded_creates_work = false
 WHERE source_kind = 'frontend_path' AND source_key = 'ui:/api/resilience-ping';

ALTER TABLE public.kernel_trigger_source DROP CONSTRAINT IF EXISTS kernel_trigger_source_disposition_ck;
ALTER TABLE public.kernel_trigger_source ADD CONSTRAINT kernel_trigger_source_disposition_ck
  CHECK (disposition IS NULL OR disposition = ANY (ARRAY[
    'NOT_A_BUSINESS_TRIGGER', 'NO_WORKFLOW_IN_REGISTRY', 'FOUNDER_COMMAND_SURFACE']));

-- THE READ-BACK COVERS BODIES, NOT GRANTS. A DROP + CREATE loses the ACL that a CREATE OR REPLACE
-- would have preserved. Measured before this file was written: {postgres=arwdDxtm/postgres,
-- service_role=arwdDxtm/postgres} — no anon, no authenticated, no PUBLIC. It is re-granted below.
DROP VIEW IF EXISTS public.v_kernel_trigger_source_derived;
CREATE VIEW public.v_kernel_trigger_source_derived AS
 WITH wt(t, why) AS (
         VALUES ('agent_actions'::text,'the legacy agent work queue'::text), ('org_tasks'::text,'the department task queue'::text), ('phase_c_task'::text,'the kernel task table'::text), ('notifications'::text,'the outbound message queue: a queued message is work owed to a person'::text), ('os_incidents'::text,'phase_b_business_object.incident, governed by W29'::text), ('board_reports'::text,'phase_b_business_object.intelligence_product, governed by W25'::text), ('evolution_proposal'::text,'phase_b_business_object.organization_change_request, governed by W30'::text), ('leads'::text,'the supplier lead / supplier_account population, governed by W09'::text), ('inquiries'::text,'phase_b_business_object.inquiry, governed by W05'::text), ('inquiry_intake'::text,'the inquiry draft that becomes phase_b_business_object.inquiry'::text), ('quotes'::text,'phase_b_business_object.quotation, governed by W14'::text), ('transactions'::text,'phase_b_business_object.payment_transaction, governed by W16'::text), ('customers'::text,'phase_b_business_object.customer_account, governed by W04'::text)
        ), body AS (
         SELECT p.oid,
            p.proname,
            regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/'::text, ' '::text, 'g'::text), '--[^\n]*'::text, ' '::text, 'g'::text) AS src
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'::name AND p.prokind = 'f'::"char"
        ), writer AS (
         SELECT b.oid,
            b.proname,
            string_agg(DISTINCT wt.t, ', '::text) AS work_tables
           FROM body b
             JOIN wt ON b.src ~* (('(insert\s+into|update)\s+(public\.)?'::text || wt.t) || '\y'::text)
          GROUP BY b.oid, b.proname
        ), kernelcaller AS (
         SELECT b.oid,
            b.proname
           FROM body b
          WHERE b.src ~ '\yfn_kernel_trigger_submit\s*\('::text OR b.src ~ '\yfn_kernel_signal_submit\s*\('::text OR b.src ~ '\yfn_kernel_source_emit\s*\('::text
        ), replayer AS (
         SELECT b.oid,
            b.proname
           FROM body b
          WHERE b.src ~ '\yphase_c_event_outbox\y'::text AND b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\('::text
        ), cronjob AS (
         SELECT j.jobid,
            j.active,
            regexp_replace(regexp_replace(j.command, '/\*.*?\*/'::text, ' '::text, 'g'::text), '--[^\n]*'::text, ' '::text, 'g'::text) AS cmd
           FROM cron.job j
        ), cron_fact AS (
         SELECT cj.jobid,
            cj.active,
            (EXISTS ( SELECT 1
                   FROM writer wr
                  WHERE strpos(cj.cmd, wr.proname::text) > 0 AND cj.cmd ~ (('\y'::text || wr.proname::text) || '\s*\('::text))) AS creates_work,
            cj.cmd ~ '\yfn_kernel_trigger_submit\s*\('::text OR (EXISTS ( SELECT 1
                   FROM kernelcaller kc
                  WHERE strpos(cj.cmd, kc.proname::text) > 0 AND cj.cmd ~ (('\y'::text || kc.proname::text) || '\s*\('::text))) AS routes,
            (EXISTS ( SELECT 1
                   FROM replayer rp
                  WHERE strpos(cj.cmd, rp.proname::text) > 0 AND cj.cmd ~ (('\y'::text || rp.proname::text) || '\s*\('::text))) AS replays
           FROM cronjob cj
        ), trg_fact AS (
         SELECT (((n.nspname::text || '.'::text) || c.relname::text) || ':'::text) || tg.tgname::text AS source_ref,
            tg.tgenabled <> 'D'::"char" AS active,
            COALESCE(( SELECT bool_or(u.tn <> c.relname) AS bool_or
                   FROM writer wr,
                    LATERAL unnest(string_to_array(wr.work_tables, ', '::text)) u(tn)
                  WHERE wr.oid = tg.tgfoid), false) AS creates_work,
            (EXISTS ( SELECT 1
                   FROM kernelcaller kc
                  WHERE kc.oid = tg.tgfoid)) AS routes,
            (EXISTS ( SELECT 1
                   FROM replayer rp
                  WHERE rp.oid = tg.tgfoid)) AS replays
           FROM pg_trigger tg
             JOIN pg_class c ON c.oid = tg.tgrelid
             JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE NOT tg.tgisinternal
        ), evt_fact AS (
         SELECT e.evtname AS source_ref,
            e.evtenabled <> 'D'::"char" AS active,
            (EXISTS ( SELECT 1
                   FROM writer wr
                  WHERE wr.oid = e.evtfoid)) AS creates_work,
            (EXISTS ( SELECT 1
                   FROM kernelcaller kc
                  WHERE kc.oid = e.evtfoid)) AS routes,
            (EXISTS ( SELECT 1
                   FROM replayer rp
                  WHERE rp.oid = e.evtfoid)) AS replays
           FROM pg_event_trigger e
        )
 SELECT s.source_key,
    s.source_kind,
    s.source_ref,
    s.source_class,
    s.adapter_trigger_type,
    s.workflow_id,
    s.accountable_role_id,
    s.connection_state,
    s.disposition,
    s.evidence,
        CASE s.source_kind
            WHEN 'cron_job'::text THEN cf.active
            WHEN 'database_trigger'::text THEN tf.active
            WHEN 'event_trigger'::text THEN ef.active
            ELSE s.recorded_active
        END AS is_active_now,
        CASE s.source_kind
            WHEN 'cron_job'::text THEN cf.creates_work
            WHEN 'database_trigger'::text THEN tf.creates_work
            WHEN 'event_trigger'::text THEN ef.creates_work
            ELSE s.recorded_creates_work
        END AS creates_work_now,
        CASE s.source_kind
            WHEN 'cron_job'::text THEN cf.routes
            WHEN 'database_trigger'::text THEN tf.routes
            WHEN 'event_trigger'::text THEN ef.routes
            ELSE (EXISTS ( SELECT 1
               FROM kernelcaller kc
                 JOIN body b2 ON b2.oid = kc.oid
              WHERE b2.src ~~ (('%'''::text || s.source_key) || '''%'::text))) OR (EXISTS ( SELECT 1
               FROM phase_c_edge_function_writes w
                 JOIN pg_class cl ON cl.relname = w.table_name
                 JOIN pg_namespace ns ON ns.oid = cl.relnamespace AND ns.nspname = 'public'::name
                 JOIN pg_trigger tg ON tg.tgrelid = cl.oid AND NOT tg.tgisinternal AND tg.tgenabled <> 'D'::"char"
                 JOIN pg_proc tp ON tp.oid = tg.tgfoid
                 JOIN kernelcaller kc2 ON kc2.proname = tp.proname
              WHERE NOT w.unbounded AND s.source_kind = 'edge_function'::text AND w.edge_function = regexp_replace(s.source_key, '^edge:'::text, ''::text))) OR COALESCE(s.recorded_routes_through_inbox, false)
        END AS routes_through_inbox,
        CASE s.source_kind
            WHEN 'cron_job'::text THEN cf.replays
            WHEN 'database_trigger'::text THEN tf.replays
            WHEN 'event_trigger'::text THEN ef.replays
            ELSE false
        END AS outbox_used_as_request_queue,
    ( SELECT r.kind
           FROM fn_phase_c_resolve_actor(s.accountable_role_id) r(kind, role_id, department_id, system_actor_id, reason)) AS accountable_kind
   FROM kernel_trigger_source s
     LEFT JOIN cron_fact cf ON cf.jobid =
        CASE
            WHEN s.source_kind = 'cron_job'::text AND s.source_ref ~ '^[0-9]+$'::text THEN s.source_ref::bigint
            ELSE NULL::bigint
        END
     LEFT JOIN trg_fact tf ON s.source_kind = 'database_trigger'::text AND tf.source_ref = s.source_ref
     LEFT JOIN evt_fact ef ON s.source_kind = 'event_trigger'::text AND ef.source_ref = s.source_ref;

-- THE READ-BACK COVERS BODIES, NOT GRANTS. A DROP + CREATE loses the ACL a CREATE OR REPLACE would
-- have preserved. Measured on production before this file was written:
-- {postgres=arwdDxtm/postgres, service_role=arwdDxtm/postgres} — no anon, no authenticated, no
-- PUBLIC. Restored here in the same file, because a silently public view is a worse outcome than
-- the defect this rollback re-introduces.
REVOKE ALL ON public.v_kernel_trigger_source_derived FROM PUBLIC;
GRANT ALL ON public.v_kernel_trigger_source_derived TO service_role;

CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_temp'
AS $function$
with d as (select * from public.v_kernel_trigger_source_derived),
tot as (select count(*)::text n from d),
auto as (   -- a live source that starts or changes business work: what an adapter is FOR.
            -- The founder's own command channel is excluded by name: it is not autonomous, a
            -- person drives it, and giving it an autonomous adapter is the one thing the frozen
            -- operating model forbids. Excluded here and counted on the deferred_handler_split
            -- line, so it is never simply missing.
  select * from d
   where coalesce(is_active_now,false) and coalesce(creates_work_now,false)
     and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE'
),
act as (select count(*)::text n from auto),
-- UNACCOUNTED FOR: it starts work, it is live, it has no working adapter, and nobody has written
-- down why. A recorded DEFERRED_HANDLER is an answer; silence is the gap.
gap as (
  select * from auto a
   where a.disposition is null
     and (a.adapter_trigger_type is null
          or not exists (select 1 from public.kernel_trigger_type t
                          where t.trigger_type = a.adapter_trigger_type
                            and t.activation_state = 'active'))
)
select 'active_autonomous_source_with_no_adapter'::text,
       '0 of ' || (select n from act) || ' active autonomous sources (' || (select n from tot) || ' inventoried)',
       (select count(*)::text from gap)
         || ' of ' || (select n from act) || ' active autonomous sources unaccounted for ('
         || (select n from tot) || ' inventoried); '
         || (select count(*)::text from auto where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' carry a recorded DEFERRED_HANDLER, '
         || (select count(*)::text from d where coalesce(is_active_now,false)
               and coalesce(creates_work_now,false) and disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces held out of this population by name',
       (select count(*) from gap) = 0
union all
select 'active_adapter_bypassing_fn_kernel_workflow_start'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where activation_state = 'active')
         || ' active trigger types',
       -- The adapter is fn_kernel_trigger_submit. It bypasses the kernel creator if its own body
       -- (comments stripped) does not call fn_kernel_workflow_start, or if any OTHER routine reads
       -- kernel_trigger_inbox and creates work without going through it.
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(')::text
         || ' routines read kernel_trigger_inbox and create work without fn_kernel_workflow_start; '
         || 'fn_kernel_trigger_submit calls it: '
         || (select (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                     ~ '\yfn_kernel_workflow_start\s*\(')::text
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'),
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '\ykernel_trigger_inbox\y'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               ~ '(insert\s+into\s+(public\.)?phase_c_(task|workflow_run)\y)'
           and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
               !~ '\yfn_kernel_workflow_start\s*\(') = 0
       and coalesce((select regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
                            ~ '\yfn_kernel_workflow_start\s*\('
                       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'fn_kernel_trigger_submit'), false)
union all
select 'normal_autonomous_trigger_routing_through_founder'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types (workflow owner or entry-step owner)',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'founder' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'normal_autonomous_trigger_routing_through_chief_of_staff'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'chief_of_staff' in (w.accountable_role_id, coalesce(s.accountable_role_id,'')))::text
         || ' of ' || (select count(*)::text from public.kernel_trigger_type where workflow_id is not null)
         || ' mapped trigger types; W01 is the founder-command path and is refused by '
         || 'a00_kernel_trigger_type_routing_guard, not merely absent',
       (select count(*) from public.kernel_trigger_type t
          join public.phase_b_workflow w on w.workflow_id = t.workflow_id
          left join public.phase_b_workflow_step s
                 on s.workflow_id = t.workflow_id and s.step_no = 1
         where 'chief_of_staff' in (w.accountable_role_id, coalesce(s.accountable_role_id,''))) = 0
union all
select 'duplicate_trigger_delivery_creating_duplicate_workflow'::text,
       '0 of ' || (select count(*)::text from public.kernel_trigger_inbox
                    where status in ('accepted','duplicate')) || ' resolved inbox rows',
       -- Two ways a duplicate could show: the same idempotency key twice (the UNIQUE constraint
       -- makes it impossible and it is still counted, because a constraint that is never tested is
       -- an assumption), or one (workflow, business object) carrying more than one run.
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)::text
         || ' repeated idempotency keys + '
         || (select count(*) from (
               select workflow_id, business_object_id from public.kernel_trigger_inbox
                where status in ('accepted','duplicate') and run_id is not null
                group by workflow_id, business_object_id having count(distinct run_id) > 1) y)::text
         || ' (workflow, object) pairs with more than one run, of '
         || (select count(*)::text from public.kernel_trigger_inbox
              where status in ('accepted','duplicate')) || ' resolved inbox rows',
       (select count(*) from (
          select 1 from public.kernel_trigger_inbox
           group by idempotency_key having count(*) > 1) x)
       + (select count(*) from (
            select workflow_id, business_object_id from public.kernel_trigger_inbox
             where status in ('accepted','duplicate') and run_id is not null
             group by workflow_id, business_object_id having count(distinct run_id) > 1) y) = 0
union all
select 'trigger_source_using_the_domain_event_outbox_as_its_request_queue'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where outbox_used_as_request_queue)::text
         || ' of ' || (select n from tot) || ' inventoried sources. The predicate is live: it '
         || 'matches '
         || (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yphase_c_event_outbox\y'
                and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g') ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\(')
         || ' routines in the database (the legacy ingress pair), and no ACTIVE source reaches them',
       (select count(*) from d where outbox_used_as_request_queue) = 0
-- ---- reported alongside the six, because a green mapping check must not read as a green wiring
-- ---- check. This is the increment's own open gap and it is stated as a number, not as prose.
union all
select 'active_autonomous_source_not_yet_routing_through_the_inbox'::text,
       '0 of ' || (select n from act) || ' active autonomous sources — NOT MET BY K10',
       (select count(*) from auto where not coalesce(routes_through_inbox,false))::text
         || ' of ' || (select n from act) || ' active autonomous sources still start or change '
         || 'business work without entering the kernel. K10 builds the door and registers the '
         || 'routes; moving each source onto it is the wiring increment.',
       (select count(*) from auto where not coalesce(routes_through_inbox,false)) = 0
union all
select 'inventory_row_whose_accountable_role_does_not_resolve'::text,
       '0 of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical')::text
         || ' of ' || (select n from tot) || ' inventoried sources',
       (select count(*) from d where accountable_kind is distinct from 'canonical') = 0
union all
select 'disposition_split'::text,
       'reported, never counted as one backlog of owed handlers',
       (select count(*)::text from public.kernel_trigger_source
         where disposition = 'NO_WORKFLOW_IN_REGISTRY')
         || ' owe a handler (no Phase B workflow starts from that signal); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'NOT_A_BUSINESS_TRIGGER')
         || ' are not business triggers at all (guards, audits, probes, held jobs); '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition = 'FOUNDER_COMMAND_SURFACE')
         || ' are founder command surfaces that must never get an autonomous adapter; '
         || (select count(*)::text from public.kernel_trigger_source
              where disposition is null and adapter_trigger_type is not null)
         || ' carry an adapter',
       true;
$function$;

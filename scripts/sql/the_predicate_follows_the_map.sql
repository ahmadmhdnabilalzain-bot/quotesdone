-- ============================================================================================
-- THE FLAG WAS A CLAIM; THE DISCHARGE IS MEASURABLE
--
-- v_kernel_trigger_source_derived answers routes_through_inbox by source kind:
--
--   cron_job          derived live from cron.job.command
--   database_trigger  derived live from the trigger function's prosrc
--   event_trigger     derived live from the event trigger function's prosrc
--   everything else   s.recorded_routes_through_inbox      <-- a stored boolean
--
-- "Everything else" is every edge function and every frontend path: 33 of the inventoried sources.
-- For those, the check that decides whether a source reaches the kernel was reading a column
-- somebody sets by hand. All 25 edge_function rows and all 8 frontend_path rows carry false.
--
-- That flag is a claim in both directions. Wiring an edge function does not move it, so real work
-- reads as a bypass; and setting it without wiring anything turns
-- fn_kernel_trigger_state green over nothing. A hand-set boolean deciding a gate is the same shape
-- as CONNECTED on an event binding and as the 161 typed into an invariant.
--
-- WHAT IS ACTUALLY MEASURABLE. This estate discharges an edge function through a trigger on the
-- table it writes: kernel_k25 created trg_contact_message_to_kernel on public.contact_messages,
-- whose body calls fn_kernel_source_emit('edge:contact_submit', ...). kernel_k34_cutover_measure
-- already records that model explicitly, as 'edge:contact_submit' -> 'routine:trg_contact_message_to_kernel'.
-- So the source key appears as a literal inside a deployed routine, and a literal in prosrc is a
-- fact, not a flag.
--
-- Measured before this change: of the 26 active autonomous sources counted as bypassing the kernel,
-- SEVEN are discharged right now by a routine that names them --
--
--   edge:contact_submit  edge:customer_documents  edge:inbound_email  edge:pdpl_request
--   edge:site_assistant  edge:sup_dob             edge:wa_inbound
--
-- The true bypass count is 19, and it has been 19. The instrument was reporting 26 because it read
-- the flag instead of the estate.
--
-- THIS DOES NOT MAKE A GATE GREEN. It moves 26 to 19 on a check that must reach 0, and it removes
-- the ability to move that number by editing a column. The recorded flag survives only as a
-- fallback for a source no routine discharges, so it can still be set — but it can no longer
-- contradict a measurement, because the measurement wins.
--
-- Comments are stripped before matching, so a source key mentioned in a note is not a discharge.
-- The literal must be quoted, which is how it is passed to fn_kernel_source_emit.
-- ============================================================================================

create or replace view public.v_kernel_trigger_source_derived as
 with wt(t, why) as (
     values ('agent_actions'::text,'the legacy agent work queue'::text), ('org_tasks'::text,'the department task queue'::text), ('phase_c_task'::text,'the kernel task table'::text), ('notifications'::text,'the outbound message queue: a queued message is work owed to a person'::text), ('os_incidents'::text,'phase_b_business_object.incident, governed by W29'::text), ('board_reports'::text,'phase_b_business_object.intelligence_product, governed by W25'::text), ('evolution_proposal'::text,'phase_b_business_object.organization_change_request, governed by W30'::text), ('leads'::text,'the supplier lead / supplier_account population, governed by W09'::text), ('inquiries'::text,'phase_b_business_object.inquiry, governed by W05'::text), ('inquiry_intake'::text,'the inquiry draft that becomes phase_b_business_object.inquiry'::text), ('quotes'::text,'phase_b_business_object.quotation, governed by W14'::text), ('transactions'::text,'phase_b_business_object.payment_transaction, governed by W16'::text), ('customers'::text,'phase_b_business_object.customer_account, governed by W04'::text)
    ), body as (
     select p.oid, p.proname,
        regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/'::text, ' '::text, 'g'::text), '--[^\n]*'::text, ' '::text, 'g'::text) as src
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'::name and p.prokind = 'f'::"char"
    ), writer as (
     select b.oid, b.proname, string_agg(distinct wt.t, ', '::text) as work_tables
       from body b join wt on b.src ~* (('(insert\s+into|update)\s+(public\.)?'::text || wt.t) || '\y'::text)
      group by b.oid, b.proname
    ), kernelcaller as (
     select b.oid, b.proname from body b
      where b.src ~ '\yfn_kernel_trigger_submit\s*\('::text or b.src ~ '\yfn_kernel_signal_submit\s*\('::text or b.src ~ '\yfn_kernel_source_emit\s*\('::text
    ), replayer as (
     select b.oid, b.proname from body b
      where b.src ~ '\yphase_c_event_outbox\y'::text and b.src ~ '\yfn_(kernel|phase_c)_(workflow_start|event_ingress)\s*\('::text
    ), cronjob as (
     select j.jobid, j.active,
        regexp_replace(regexp_replace(j.command, '/\*.*?\*/'::text, ' '::text, 'g'::text), '--[^\n]*'::text, ' '::text, 'g'::text) as cmd
       from cron.job j
    ), cron_fact as (
     select cj.jobid, cj.active,
        (exists ( select 1 from writer wr where strpos(cj.cmd, wr.proname::text) > 0 and cj.cmd ~ (('\y'::text || wr.proname::text) || '\s*\('::text))) as creates_work,
        cj.cmd ~ '\yfn_kernel_trigger_submit\s*\('::text or (exists ( select 1 from kernelcaller kc where strpos(cj.cmd, kc.proname::text) > 0 and cj.cmd ~ (('\y'::text || kc.proname::text) || '\s*\('::text))) as routes,
        (exists ( select 1 from replayer rp where strpos(cj.cmd, rp.proname::text) > 0 and cj.cmd ~ (('\y'::text || rp.proname::text) || '\s*\('::text))) as replays
       from cronjob cj
    ), trg_fact as (
     select (((n.nspname::text || '.'::text) || c.relname::text) || ':'::text) || tg.tgname::text as source_ref,
        tg.tgenabled <> 'D'::"char" as active,
        coalesce(( select bool_or(u.tn <> c.relname) as bool_or from writer wr, lateral unnest(string_to_array(wr.work_tables, ', '::text)) u(tn) where wr.oid = tg.tgfoid), false) as creates_work,
        (exists ( select 1 from kernelcaller kc where kc.oid = tg.tgfoid)) as routes,
        (exists ( select 1 from replayer rp where rp.oid = tg.tgfoid)) as replays
       from pg_trigger tg join pg_class c on c.oid = tg.tgrelid join pg_namespace n on n.oid = c.relnamespace
      where not tg.tgisinternal
    ), evt_fact as (
     select e.evtname as source_ref, e.evtenabled <> 'D'::"char" as active,
        (exists ( select 1 from writer wr where wr.oid = e.evtfoid)) as creates_work,
        (exists ( select 1 from kernelcaller kc where kc.oid = e.evtfoid)) as routes,
        (exists ( select 1 from replayer rp where rp.oid = e.evtfoid)) as replays
       from pg_event_trigger e
    )
 select s.source_key,
    s.source_kind,
    s.source_ref,
    s.source_class,
    s.adapter_trigger_type,
    s.workflow_id,
    s.accountable_role_id,
    s.connection_state,
    s.disposition,
    s.evidence,
        case s.source_kind
            when 'cron_job'::text then cf.active
            when 'database_trigger'::text then tf.active
            when 'event_trigger'::text then ef.active
            else s.recorded_active
        end as is_active_now,
        case s.source_kind
            when 'cron_job'::text then cf.creates_work
            when 'database_trigger'::text then tf.creates_work
            when 'event_trigger'::text then ef.creates_work
            else s.recorded_creates_work
        end as creates_work_now,
        case s.source_kind
            when 'cron_job'::text then cf.routes
            when 'database_trigger'::text then tf.routes
            when 'event_trigger'::text then ef.routes
            -- MEASURED FIRST, RECORDED ONLY AS A FALLBACK. An edge function or a frontend path has
            -- no prosrc of its own, but the routine that discharges it names it as a quoted literal
            -- in the fn_kernel_source_emit call. That literal is the measurement. The stored flag is
            -- consulted only where no routine discharges the source, so it can never contradict one.
            -- THE CONJUNCTION, AT LAST. A source reaches the kernel if EITHER a routine names its
            -- source key as a literal (the direct discharge, already measured), OR it writes a
            -- table that carries a trigger reaching a kernel door (the indirect discharge, which
            -- is how this estate actually works: one table trigger discharges every surface
            -- writing its table, under the trigger's own key).
            --
            -- The second half needs "does this source write table T", which is not in the database
            -- for an edge function. public.phase_c_edge_function_writes carries it, generated from
            -- a real TypeScript AST by scripts/checks/edge_function_writes.mjs with 0 unresolvable
            -- call sites and compared against the committed CSV.
            --
            -- `not w.unbounded` IS LOAD-BEARING. Six functions take their target from a request, a
            -- queue row or a config column, so they may write ANY table. "May write anything" is
            -- not "writes the table that discharges it", and clearing on it would be the false
            -- green this whole exercise exists to prevent. They are excluded here on purpose and
            -- can therefore never be cleared by the map.
            else (exists (select 1 from kernelcaller kc
                           join body b2 on b2.oid = kc.oid
                          where b2.src like '%''' || s.source_key || '''%'))
                 or exists (
                       select 1
                         from public.phase_c_edge_function_writes w
                         join pg_class cl on cl.relname = w.table_name
                         join pg_namespace ns on ns.oid = cl.relnamespace and ns.nspname = 'public'
                         join pg_trigger tg on tg.tgrelid = cl.oid
                                           and not tg.tgisinternal and tg.tgenabled <> 'D'
                         join pg_proc tp on tp.oid = tg.tgfoid
                         join kernelcaller kc2 on kc2.proname = tp.proname
                        where not w.unbounded
                          and s.source_kind = 'edge_function'
                          and w.edge_function = regexp_replace(s.source_key, '^edge:', ''))
                 or coalesce(s.recorded_routes_through_inbox, false)
        end as routes_through_inbox,
        case s.source_kind
            when 'cron_job'::text then cf.replays
            when 'database_trigger'::text then tf.replays
            when 'event_trigger'::text then ef.replays
            else false
        end as outbox_used_as_request_queue,
    ( select r.kind from fn_phase_c_resolve_actor(s.accountable_role_id) r(kind, role_id, department_id, system_actor_id, reason)) as accountable_kind
   from kernel_trigger_source s
     left join cron_fact cf on cf.jobid =
        case when s.source_kind = 'cron_job'::text and s.source_ref ~ '^[0-9]+$'::text then s.source_ref::bigint else null::bigint end
     left join trg_fact tf on s.source_kind = 'database_trigger'::text and tf.source_ref = s.source_ref
     left join evt_fact ef on s.source_kind = 'event_trigger'::text and ef.source_ref = s.source_ref;

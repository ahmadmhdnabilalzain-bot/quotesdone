-- K33 — the cutover headline was answering a narrower question than its own column name.
--
-- After five cutover increments, fn_kernel_trigger_state still reported:
--
--   active_autonomous_source_not_yet_routing_through_the_inbox :: 38 of 38
--
-- Eleven database triggers had been moved onto the kernel and verified against pg_proc, and the
-- number had not moved by one.
--
-- v_kernel_trigger_source_derived decides routes_through_inbox from a `kernelcaller` CTE whose
-- whole predicate was:
--
--   b.src ~ '\yfn_kernel_trigger_submit\s*\('
--
-- The cut-over sources do not name fn_kernel_trigger_submit. They call fn_kernel_source_emit —
-- the canonical wrapper §3 permits in as many words: a new-work source "must call
-- fn_kernel_trigger_submit OR ONE CANONICAL WRAPPER AROUND IT". And a class-B source reaches
-- fn_kernel_signal_submit, which is routing through the kernel just as surely as reaching the
-- trigger inbox; reporting it as a bypass is simply wrong.
--
-- The predicate was written before either existed. It has been correct about what it literally
-- tests and wrong about what its column is called ever since.
--
-- It is NOT being widened to flatter the work. It still reads the DEPLOYED body with comments
-- stripped, so a routine that merely mentions a kernel function in prose still does not qualify,
-- and a routine that inserts into a business-work table directly is still not routing through
-- anything. What changed is that it now names all three ways in.
--
-- Generated from the LIVE view definition by scripts/phase_c/gen_k33.mjs, which refuses to emit
-- unless it finds the old predicate. Nothing else in the view moved.
--
-- Rollback: re-apply scripts/sql/kernel_k28... does not exist; re-apply
-- scripts/sql/kernel_k10_trigger_inbox.sql, which carries the single-door predicate — and note
-- that doing so reinstates a headline that reports eleven cut-over sources as bypassing.

begin;

create or replace view public.v_kernel_trigger_source_derived as
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
          WHERE (b.src ~ '\yfn_kernel_trigger_submit\s*\('::text
         -- K33. All THREE doors, not one. fn_kernel_trigger_submit is the request door;
         -- fn_kernel_signal_submit is the signal door K16 built for a run that already exists;
         -- fn_kernel_source_emit is the canonical wrapper §3 authorises in as many words, and
         -- it is what every cut-over source actually calls. Matching only the first meant the
         -- view reported 38 of 38 sources bypassing the kernel after eleven had been cut over
         -- and verified against pg_proc: a column answering a narrower question than its name.
         OR b.src ~ '\yfn_kernel_signal_submit\s*\('::text
         OR b.src ~ '\yfn_kernel_source_emit\s*\('::text)
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
            ELSE s.recorded_routes_through_inbox
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

comment on view public.v_kernel_trigger_source_derived is
  'K10, corrected by K33. routes_through_inbox recognises all THREE kernel doors — '
  'fn_kernel_trigger_submit, fn_kernel_signal_submit and the canonical wrapper '
  'fn_kernel_source_emit that the specification authorises — instead of only the first. It had '
  'been answering a narrower question than its own column name.';

revoke all on public.v_kernel_trigger_source_derived from public;
grant select on public.v_kernel_trigger_source_derived to service_role;

commit;

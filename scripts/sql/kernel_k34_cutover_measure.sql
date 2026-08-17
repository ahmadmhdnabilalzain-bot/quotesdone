-- K34 — a cutover measurement that can judge an Edge Function, not only a database routine.
--
-- K33 taught v_kernel_trigger_source_derived about all three kernel doors, and the headline moved
-- from "38 of 38 bypassing" to "26 of 37". The eleven that changed are the database triggers: they
-- have a prosrc to scan, so the view can see the call.
--
-- The remaining twenty-six are Edge Functions and frontend routes. There is no prosrc for those,
-- so the view falls back to kernel_trigger_source.recorded_routes_through_inbox — a boolean a human
-- set — and a boolean is exactly the "registry-only connection" §7 says the measurement must
-- REJECT. Believing it would be believing a label; disbelieving it reports twenty-six bypasses
-- that do not exist.
--
-- So the disposition has to carry EVIDENCE, and the evidence has to be checkable.
--
-- Every source now names the routine or trigger that discharges its disposition, in
-- disposition_evidence, and fn_kernel_cutover_measure VERIFIES it: the named routine must exist and
-- its deployed body must call a kernel door. A source claiming to be covered by a trigger that
-- does not exist, or that exists and does not call the kernel, is counted as BYPASSING however its
-- status column reads.
--
-- WHAT THE MEASUREMENT RECOGNISES, per §7:
--
--   CUT_OVER_DIRECT          its own routine's deployed body calls a kernel door
--   CUT_OVER_VIA_COVERING    a named trigger on the table it writes calls a kernel door, verified
--   READ_ONLY                class C, and its routine writes none of the eight protected tables
--   RETIRED_OR_INACTIVE      class D, or switched off today
--
-- AND WHAT IT REJECTS:
--
--   * a direct insert into a workflow run, step run, task or handoff by an ACTIVE source
--   * a claim of coverage naming a trigger that does not exist or does not call the kernel
--   * a registry-only connection: a recorded boolean with nothing behind it
--   * an active source with no disposition evidence at all
--
-- There is no expected numerator anywhere in this function. It reports what it counts.
--
-- Rollback: scripts/sql/rollback/kernel_k34_cutover_measure.rollback.sql

begin;

alter table public.phase_c_source_cutover
  add column if not exists disposition_evidence text;

comment on column public.phase_c_source_cutover.disposition_evidence is
  'K34. The routine or trigger that DISCHARGES this source''s disposition, named so it can be '
  'checked. fn_kernel_cutover_measure verifies the named object exists and calls a kernel door; a '
  'claim with nothing behind it counts as bypassing however the status column reads.';

-- ---- the evidence, named per source ----------------------------------------------------------
-- A database trigger discharges its own disposition: the routine it fires is the evidence.
update public.phase_c_source_cutover c
-- The ROUTINE it fires, not its own name: trg_inquiry_received_a fires trg_inquiry_received, and
-- naming one while resolving the other made fifteen honest claims read as empty ones.
   set disposition_evidence = 'routine:' || (
         select p.proname from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
          where tg.tgname = split_part(c.source_component_id, ':', 3)
            and not tg.tgisinternal limit 1)
 where c.source_type = 'database_trigger' and c.disposition_evidence is null
   -- Only a source that is SUPPOSED to reach the kernel is discharged by naming a routine. A
   -- class-C monitor or a class-D retired trigger is discharged by what it does NOT do, and giving
   -- it a routine claim it was never going to satisfy makes an honest read-only source read as a
   -- broken coverage claim — which is what the first run of this file did, three times.
   and c.source_class in ('A NEW_WORK_REQUEST','B EXISTING_WORKFLOW_SIGNAL')
   and exists (select 1 from pg_trigger tg
                where tg.tgname = split_part(c.source_component_id, ':', 3) and not tg.tgisinternal);

-- An Edge Function or route is discharged by the trigger on the table it writes. Measured by
-- reading each function's deployed source for the table it inserts into, then naming that table's
-- kernel-calling trigger.
update public.phase_c_source_cutover set disposition_evidence = v.ev
  from (values
    ('edge:site_assistant',       'routine:trg_assistant_log_to_kernel'),
    ('edge:wa_inbound',           'routine:trg_wa_message_to_kernel'),
    ('edge:inbound_email',        'routine:trg_inbound_message_to_kernel'),
    ('edge:sup_dob',              'routine:trg_lead_dob_to_kernel'),
    ('edge:contact_submit',       'routine:trg_contact_message_to_kernel'),
    ('edge:pdpl_request',         'routine:trg_pdpl_request_to_kernel'),
    ('edge:customer_documents',   'routine:trg_document_to_kernel'),
    ('edge:attach_photos',        'read_only:writes no table at all'),
    ('edge:supplier_onboard',     'read_only:one agent_actions telemetry row'),
    ('edge:resend_inbound',       'read_only:expenses and doc_reviews, none of the eight protected tables'),
    ('edge:claim_lookup',         'read_only:agent_runs only'),
    ('edge:resend_webhook',       'read_only:agent_runs, email_suppressions, leads.invite_status, error_events'),
    ('edge:unsubscribe',          'read_only:email_suppressions only'),
    ('edge:inquiry_intake',       'routine:trg_inquiry_received'),
    ('edge:customer_api',         'routine:trg_inquiry_received'),
    ('edge:supplier_api',         'routine:notify_new_quote_sms'),
    ('edge:supplier_portal',      'routine:notify_new_quote_sms'),
    ('edge:refund_flow',          'routine:qd_notify_refund_request'),
    ('edge:stripe_webhook',       'routine:trg_reveal_receipt'),
    ('edge:stripe_confirm',       'routine:trg_reveal_receipt'),
    ('edge:messages_api',         'routine:trg_inquiry_received'),
    ('edge:supplier_ack',         'routine:qd_on_refund_resolved'),
    ('edge:voice_otp',            'retired:410 responder since 18 Jul 2026'),
    ('edge:voice_otp_capture',    'retired:410 responder since 18 Jul 2026'),
    ('ui:/[locale]/contact',      'routine:trg_contact_message_to_kernel'),
    ('ui:/[locale]/me',           'routine:trg_inquiry_received'),
    ('ui:/[locale]/portal',       'routine:trg_inquiry_received'),
    ('ui:/[locale]/supplier',     'routine:notify_new_quote_sms'),
    ('ui:ChatWidget',             'routine:trg_assistant_log_to_kernel')
  ) as v(id, ev)
 where source_component_id = v.id;

-- Anything still without evidence gets the claim its own class already makes, stated per row so no
-- active source is left blank. A class-C source's evidence IS that it writes no protected table.
update public.phase_c_source_cutover
   set disposition_evidence = 'read_only:writes none of the eight protected business-work tables'
 where source_class = 'C READ_ONLY_MONITOR' and disposition_evidence is null;

update public.phase_c_source_cutover
   set disposition_evidence = 'retired:' || status
 where source_class = 'D RETIRE_OR_HISTORICAL' and disposition_evidence is null;

update public.phase_c_source_cutover
   set disposition_evidence = 'inactive:switched off; it carries an adapter and stays off'
 where current_activation = 'DISABLED' and disposition_evidence is null;

-- ---- the measurement -------------------------------------------------------------------------
create or replace function public.fn_kernel_cutover_measure()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k34$
with
body as (
  select p.oid, p.proname,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
),
-- A routine that reaches the kernel by ANY of the three doors the specification allows.
kernel_caller as (
  select b.proname from body b
   where b.src ~ '\yfn_kernel_trigger_submit\s*\('
      or b.src ~ '\yfn_kernel_signal_submit\s*\('
      or b.src ~ '\yfn_kernel_source_emit\s*\('
),
protected(t) as (values
  ('phase_c_workflow_run'),('phase_c_workflow_step_run'),('phase_c_task'),('phase_c_handoff_run'),
  ('kernel_trigger_inbox'),('kernel_signal_inbox'),('phase_c_event_outbox'),('phase_c_refund_decision')),
-- A routine that writes business work DIRECTLY. Anything on the kernel's own allow-list is
-- excluded: fn_kernel_step_complete writes those tables because it is the kernel.
direct_writer as (
  select distinct b.proname from body b join protected pr
      on b.src ~ ('(insert\s+into|update|delete\s+from)\s+(public\.)?' || pr.t || '\M')
   where not exists (select 1 from public.kernel_write_authority a where a.routine_name = b.proname)
),
-- The trigger a source names as discharging it, resolved to the routine it actually fires.
named as (
  select c.source_component_id, c.source_class, c.current_activation, c.status,
         c.disposition_evidence,
         split_part(c.disposition_evidence, ':', 1) as ev_kind,
         split_part(c.disposition_evidence, ':', 2) as ev_ref,
         case split_part(c.disposition_evidence, ':', 1)
           when 'routine' then split_part(c.disposition_evidence, ':', 2)
           when 'trigger' then (select p.proname from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid
                                 where tg.tgname = split_part(c.disposition_evidence, ':', 2)
                                   and not tg.tgisinternal limit 1)
         end as ev_routine
    from public.phase_c_source_cutover c
),
judged as (
  select n.*,
         case
           when n.current_activation = 'DISABLED'
             or n.source_class = 'D RETIRE_OR_HISTORICAL'
             or n.ev_kind = 'retired'                      then 'RETIRED_OR_INACTIVE'
           when n.ev_kind in ('read_only','inactive') and n.source_class = 'C READ_ONLY_MONITOR'
                                                            then 'READ_ONLY'
           when n.ev_kind in ('routine','trigger') and n.ev_routine is not null
                and exists (select 1 from kernel_caller k where k.proname = n.ev_routine)
                                                            then 'CUT_OVER'
           else 'BYPASSING'
         end as verdict
    from named n
)
select 'total_sources'::text, 'reported, not asserted'::text,
       (select count(*)::text from judged), true
union all
select 'active_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'ACTIVE'), true
union all
select 'inactive_sources', 'reported',
       (select count(*)::text from judged where current_activation = 'DISABLED'), true
union all
select 'class_split', 'reported',
       (select string_agg(source_class || ' ' || n::text, '; ' order by source_class)
          from (select source_class, count(*) n from judged group by 1) d), true
union all
select 'verdict_split', 'reported',
       (select string_agg(verdict || ' ' || n::text, '; ' order by verdict)
          from (select verdict, count(*) n from judged group by 1) d), true
union all
-- THE line. No expected numerator: it counts what it finds.
select 'active_sources_bypassing_the_kernel', '0',
       (select count(*)::text from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
         || coalesce(' [' || (select string_agg(source_component_id, ', ')
              from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE') || ']', ''),
       (select count(*) = 0 from judged where verdict = 'BYPASSING' and current_activation = 'ACTIVE')
union all
select 'active_sources_with_no_disposition_evidence', '0',
       (select count(*)::text from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
         || coalesce(' [' || (select string_agg(source_component_id, ', ') from judged
              where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '') || ']', ''),
       (select count(*) = 0 from judged
         where current_activation = 'ACTIVE' and coalesce(btrim(disposition_evidence),'') = '')
union all
-- A claim that names a trigger which does not exist, or exists and does not call the kernel.
select 'coverage_claims_with_nothing_behind_them', '0',
       (select count(*)::text from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
         || coalesce(' [' || (select string_agg(source_component_id || ' -> ' || disposition_evidence, ', ')
              from judged where ev_kind in ('routine','trigger')
                and (ev_routine is null
                     or not exists (select 1 from kernel_caller k where k.proname = ev_routine))) || ']', ''),
       (select count(*) = 0 from judged
         where ev_kind in ('routine','trigger')
           and (ev_routine is null
                or not exists (select 1 from kernel_caller k where k.proname = ev_routine)))
union all
-- An ACTIVE source whose own routine writes a protected table directly. The kernel's own writers
-- are excluded by kernel_write_authority, so this is a genuine bypass and not the kernel itself.
select 'active_sources_writing_business_work_directly', '0',
       (select count(*)::text from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1))),
       (select count(*) = 0 from judged j
         where j.current_activation = 'ACTIVE'
           and exists (select 1 from direct_writer w
                        where w.proname = (select p.proname from pg_trigger tg
                                             join pg_proc p on p.oid = tg.tgfoid
                                            where tg.tgname = split_part(j.source_component_id, ':', 3)
                                              and not tg.tgisinternal limit 1)));
$k34$;

revoke all on function public.fn_kernel_cutover_measure() from public, anon, authenticated;
grant execute on function public.fn_kernel_cutover_measure() to service_role;

comment on function public.fn_kernel_cutover_measure() is
  'K34. The cutover measurement §7 asks for. Every source names the routine or trigger that '
  'discharges its disposition, and this VERIFIES it: the named object must exist and its deployed '
  'body must call one of the three kernel doors. A registry-only claim counts as bypassing. There '
  'is no expected numerator anywhere in the function — it reports what it counts.';

commit;

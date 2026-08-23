-- M01 — a committed scenario that proves it left nothing
--
-- THE FOUNDER'S BOUNDED EXCEPTION, 23 Aug 2026, and the guards it is conditional on.
--
-- Fourteen injected defects were recorded NOT_RUN with the same shape of blocker: they need a row
-- that a SECOND transaction can see. Every Phase D driver aborts by design, so the estate could
-- not produce one. Re-measured this session, eleven of the fourteen were mis-blocked -- their
-- refusals are immediate, in-transaction, and are closed by M02 -- and two genuinely need a
-- committed row: PD-PRIV-004, whose probe is an HTTP request and therefore commits, and
-- PD-CONC-001, whose one-winner property is only observable if a winner commits.
--
-- WHAT THIS OPERATION MAY CREATE is the founder's list and nothing else: customers, leads,
-- inquiries, inquiry_matches, documents, quotes, workflow runs, step runs, tasks, traces and
-- outbox rows. It may not create or move transactions, refunds, payouts, founder decisions,
-- founder approvals, Stripe objects, or anything that sends. fn_phase_d_committed_scenario_open
-- refuses by name if a forbidden relation is named.
--
-- THE WINDOW IS THE WHOLE PROBLEM AND IT IS DESIGNED FOR, NOT TIMED AROUND.
-- The Supabase management endpoint commits each statement on its own, so a create-then-delete pair
-- leaves a real window a cron job can run inside; it did, twice, on 23 Aug. Two ACTIVE cron jobs
-- reach a committed fixture:
--
--   278 phase_c_outbox_deliver_1min  EVERY MINUTE. fn_kernel_outbox_deliver claims
--       phase_c_event_outbox rows in ('pending','retry_wait') and hands them to
--       fn_kernel_event_consume. A committed inquiry starts a real W05 run through
--       trg_inquiry_received_a, and that run emits.
--    88 dropbox_backup_scan          EVERY 15 MINUTES. The edge function calls
--       fn_enqueue_doc_backups, which inserts 'C:'||customers.id||':details' for EVERY customer
--       and 'I:'||inquiries.id||':summary' for every inquiry, then uploads to Dropbox. Production
--       Dropbox writes are what the hold forbids.
--
-- Neither is timed around. open() runs as ONE statement and therefore ONE transaction, and before
-- it commits it has already:
--   * inserted both doc_backups dedupe keys itself with status 'done', so cron 88's
--     `on conflict (dedupe_key) do nothing` is a no-op and its processor -- which selects
--     status in ('pending','error') -- never sees them. The quarantine is committed in the same
--     instant as the row it quarantines, so no window exists at all;
--   * removed every queue row the transaction produced -- outbox, notifications, org_tasks,
--     event_delivery, event_assessment, company_event, kernel_trigger_inbox -- so cron 278 finds
--     nothing of ours to deliver;
--   * asserted that net.http_request_queue gained nothing attributable to this transaction, using
--     the xmin attribution J04 already wrote, not a watermark delta over a shared table.
--
-- WRITES TO KERNEL TABLES GO THROUGH DOOR 2 AND LEAVE A RECEIPT. fn_kernel_write_guard admits an
-- audited maintenance write by the table owner with `set local kernel.maintenance_reason`, and
-- records it in public.kernel_maintenance_write. Those receipt rows are the one persistent count
-- this operation raises, deliberately: removing them would defeat the guard that permitted the
-- write. They are counted and disclosed rather than cleaned.
--
-- ROLLBACK: scripts/sql/down/phase_d_m01_a_committed_scenario_that_proves_it_left_nothing_down.sql

-- ================================================================================================
-- 1. THE REGISTERS
-- ================================================================================================

create table if not exists public.phase_d_committed_scenario (
  scenario_id  bigserial primary key,
  label        text        not null,
  state        text        not null check (state in ('OPEN','CLOSED','FAILED')),
  opened_at    timestamptz not null default now(),
  closed_at    timestamptz,
  guards       jsonb       not null default '{}'::jsonb,
  watermarks   jsonb       not null default '{}'::jsonb,
  created      jsonb       not null default '{}'::jsonb,
  removed      jsonb       not null default '{}'::jsonb,
  assertions   jsonb       not null default '{}'::jsonb
);
-- It must refuse to run twice concurrently. One OPEN row estate-wide.
drop index if exists public.phase_d_committed_scenario_one_open_uk;
create unique index phase_d_committed_scenario_one_open_uk
  on public.phase_d_committed_scenario ((state)) where state = 'OPEN';

-- Every persistent table and every derived queue a committed fixture can reach, with the chain
-- that reaches it written down. Followed to the END of each chain, not to the first table.
create table if not exists public.phase_d_committed_scenario_watch (
  relation   text primary key,
  reached_by text not null,
  is_queue   boolean not null default false
);

insert into public.phase_d_committed_scenario_watch (relation, reached_by, is_queue) values
 ('public.customers',                'created directly by the scenario', false),
 ('public.inquiries',                'created directly by the scenario', false),
 ('public.leads',                    'created directly by the scenario when it needs a supplier', false),
 ('public.inquiry_matches',          'an assignment attempt against the scenario inquiry', false),
 ('public.notifications',            'inquiries AFTER INSERT -> trg_inquiry_received; inquiry_matches AFTER INSERT -> fn_notify_matched_supplier', true),
 ('public.company_event',            'customers AFTER INSERT -> fn_emit_customer_registered; inquiries AFTER INSERT -> fn_emit_event; AFTER INSERT OF category -> fn_emit_rfq_classified', true),
 ('public.event_assessment',         'company_event AFTER INSERT STATEMENT -> trg_company_event_dispatch -> fn_event_dispatch', true),
 ('public.event_delivery',           'company_event AFTER INSERT STATEMENT -> trg_company_event_dispatch -> fn_event_dispatch', true),
 ('public.org_tasks',                'company_event AFTER INSERT STATEMENT -> trg_company_event_dispatch -> fn_event_dispatch', true),
 ('public.undo_log',                 'org_tasks BEFORE DELETE OR UPDATE -> trg_undo_capture', true),
 ('public.customer_preference',      'inquiries AFTER INSERT -> trg_learn_customer_preference', false),
 ('public.doc_versions',             'inquiries AFTER INSERT OR UPDATE -> trg_version_rfq', false),
 ('public.founder_alerts',           'inquiries BEFORE INSERT -> scrub_inquiry_contacts', true),
 ('public.kernel_trigger_inbox',     'inquiries AFTER INSERT -> trg_inquiry_received -> fn_kernel_source_emit -> fn_kernel_trigger_submit', true),
 ('public.phase_c_workflow_run',     'fn_kernel_trigger_submit -> fn_kernel_workflow_start', false),
 ('public.phase_c_workflow_step_run','fn_kernel_workflow_start', false),
 ('public.phase_c_trace',            'phase_c_workflow_step_run AFTER INSERT -> fn_phase_c_step_run_trace_subject', false),
 ('public.phase_c_task',             'fn_kernel_workflow_start / fn_kernel_step_complete', false),
 ('public.phase_c_handoff_run',      'fn_kernel_step_complete on a cross-owner successor', false),
 ('public.phase_c_step_completion',  'fn_kernel_step_complete', false),
 ('public.phase_c_event_outbox',     'fn_kernel_workflow_start -> fn_kernel_outbox_emit; DRAINED BY CRON 278 EVERY MINUTE', true),
 ('public.phase_d_dispatch',         'fn_kernel_open_step -> fn_phase_d_dispatch_step (Phase D fires at step OPEN)', false),
 ('public.phase_d_effect_ledger',    'fn_phase_d_handler_execute -> fn_phase_d_effect_produce', false),
 ('public.phase_d_object_record',    'fn_phase_d_object_write', false),
 ('public.documents',                'leads/inquiries AFTER UPDATE OF a document path -> fn_register_document', false),
 ('public.doc_backups',              'CRON 88 EVERY 15 MIN -> fn_enqueue_doc_backups reads customers, inquiries, leads and quotes; it RETRIES FIVE TIMES AND OUTLIVES THE ROW THAT PRODUCED IT', true),
 ('public.agent_runs',               'fn_event_dispatch records its own exception as an agent_runs error row', true),
 ('public.quotes',                   'the founder''s list permits one; nothing in the current scenario writes it', false)
on conflict (relation) do nothing;

-- Every ACTIVE cron job that can act on a watched relation, named, with the quarantine that stops
-- it. The guard below re-derives the set and refuses on a job that is not registered here.
create table if not exists public.phase_d_committed_scenario_cron (
  jobid      bigint primary key,
  jobname    text not null,
  reaches    text not null,
  quarantine text not null
);
insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
 (278,'phase_c_outbox_deliver_1min','public.phase_c_event_outbox every minute',
      'open() removes, in its own transaction, every outbox row the transaction produced, so there is nothing in pending or retry_wait for the claimer to take'),
 (88, 'dropbox_backup_scan','public.doc_backups every 15 minutes, from customers, inquiries, leads and quotes',
      'open() inserts both dedupe keys itself with status done, so fn_enqueue_doc_backups conflicts and the edge processor -- which selects status in (pending,error) -- never sees them'),
 (64, 'autonomy_dispose_hourly','UPDATEs public.leads hourly',
      'the scenario writes no leads row today; if it ever does, the row carries the ZZ DEMO marker and close() asserts leads back at its watermark'),
 (7,  'health_check','INSERTs public.notifications, reads inquiries and quotes',
      'writes its own notification rows, never ours; close() asserts only the rows this scenario created are gone, by id'),
 (14, 'founder_brief_daily','INSERTs public.notifications, reads customers, leads, inquiries, inquiry_matches, quotes, org_tasks',
      'as 7; and 04:30 UTC is outside any scenario window this session opens'),
 (26, 'smoke_test_30min','INSERTs public.notifications, reads inquiries and quotes','as 7'),
 (57, 'board_report_weekly','INSERTs public.notifications, reads customers, leads, inquiries, inquiry_matches, quotes','as 7; Mondays 07:00 UTC'),
 (60, 'monthly_report','INSERTs public.notifications, reads customers, leads, inquiries, quotes','as 7; 1st of the month 07:00 UTC'),
 (103,'policy_consistency_weekly','INSERTs public.notifications','as 7; Mondays 06:30 UTC'),
 (110,'agent_security_hourly','INSERTs public.notifications, reads customers and leads','as 7'),
 (129,'autonomy_audit_weekly','reads public.org_tasks','read-only against a watched relation'),
 (142,'evolution_scan_weekly','reads public.org_tasks','read-only against a watched relation'),
 (92, 'security_selfaudit_daily','INSERTs public.founder_alerts',
      'writes its own alert rows about the estate, never about a fixture row; close() removes only alerts whose detail names this scenario''s customer or inquiry'),
 (172,'ai_spend_guard_hourly','INSERTs public.founder_alerts','as 92'),
 (213,'approval_trace_audit_weekly','INSERTs public.founder_alerts','as 92; Mondays 06:10 UTC'),
 (214,'decision_conflict_scan_weekly','INSERTs public.founder_alerts','as 92; Mondays 06:20 UTC'),
 (215,'regulation_watch_weekly','INSERTs public.founder_alerts','as 92; Mondays 06:40 UTC'),
 (179,'control_mode_sweep_5min','INSERTs public.agent_runs every five minutes',
      'agent_runs is watched because fn_event_dispatch records its own exception there; this job writes its own sweep rows and close() asserts agent_runs back at its watermark, so a row this job adds inside the window would be a false red -- it is registered here so that red would be read, not waved through')
on conflict (jobid) do nothing;

-- ================================================================================================
-- 2. THE GUARDS — measured, never assumed
-- ================================================================================================
create or replace function public.fn_phase_d_committed_scenario_guards()
returns table(check_name text, ok boolean, detail text)
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare v_n bigint; v_txt text;
begin
  -- (1) no other scenario is open
  select count(*) into v_n from public.phase_d_committed_scenario where state = 'OPEN';
  check_name := 'no_other_scenario_open'; ok := (v_n = 0);
  detail := format('%s scenario(s) currently OPEN', v_n); return next;

  -- (2) every registered outbound door on a relation this scenario writes is suppressed or
  --     measured unreachable. Read from the register, not asserted.
  select count(*), coalesce(string_agg(d.relation || '/' || d.trigger_name, ', '), '(none)')
    into v_n, v_txt
    from public.phase_d_outbound_door d
   where d.relation in (select relation from public.phase_d_committed_scenario_watch)
     and d.disposition not in ('SUPPRESSED_BY_ITS_OWN_GUARD','NOT_REACHED_BY_ANY_PHASE_D_WRITE_MAP');
  check_name := 'every_outbound_door_on_a_written_relation_is_disposed'; ok := (v_n = 0);
  detail := format('%s undisposed: %s', v_n, v_txt); return next;

  -- (3) every ACTIVE cron job whose command can reach a watched relation is registered here with
  --     its quarantine. Derived from cron.job and the routine bodies, so a new job refuses.
  with resolved as (
    select j.jobid, j.jobname,
           coalesce((select w.original_command from public.phase_c_system_execution_wrapper w
                      where j.command like '%fn_kernel_cron_exec(' || w.jobid || ')%' limit 1),
                    j.command) as cmd
      from cron.job j where j.active),
  reach as (
    select r.jobid, r.jobname,
           exists (select 1 from public.phase_d_committed_scenario_watch t
                    where r.cmd like '%' || replace(t.relation,'public.','') || '%')
           or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       join public.phase_d_committed_scenario_watch t
                         on p.prosrc like '%' || replace(t.relation,'public.','') || '%'
                      where n.nspname = 'public' and r.cmd like '%' || p.proname || '(%') as touches
      from resolved r)
  select count(*), coalesce(string_agg(x.jobid || ' ' || x.jobname, ', '), '(none)') into v_n, v_txt
    from reach x
   where x.touches
     and not exists (select 1 from public.phase_d_committed_scenario_cron c where c.jobid = x.jobid);
  check_name := 'every_active_cron_that_reaches_a_watched_relation_is_registered'; ok := (v_n = 0);
  detail := format('%s unregistered: %s', v_n, v_txt); return next;

  -- (4) outcome_evaluate_daily is inactive, and business automation is not being reactivated here
  select count(*) into v_n from cron.job where jobname = 'outcome_evaluate_daily' and active;
  check_name := 'outcome_evaluate_daily_inactive'; ok := (v_n = 0);
  detail := format('%s active row(s)', v_n); return next;

  -- (5) the estate has no fixture residue before we start
  select count(*) into v_n from public.fn_phase_d_fixture_residue();
  check_name := 'fixture_residue_zero_before_open'; ok := (v_n = 0);
  detail := format('%s relation(s) carry residue', v_n); return next;

  -- (6) net.http_request_queue watermark is readable
  select coalesce(max(id),0) into v_n from net.http_request_queue;
  check_name := 'outbound_http_queue_watermark_readable'; ok := true;
  detail := format('max(id) = %s', v_n); return next;
end $function$;

revoke all on function public.fn_phase_d_committed_scenario_guards() from public;
grant execute on function public.fn_phase_d_committed_scenario_guards() to service_role;

-- ================================================================================================
-- 3. WATERMARKS — one place, so open() and close() cannot measure different things
-- ================================================================================================
create or replace function public.fn_phase_d_committed_scenario_watermarks()
returns jsonb
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare r record; v_n bigint; v_out jsonb := '{}'::jsonb;
begin
  for r in select relation from public.phase_d_committed_scenario_watch order by relation loop
    execute format('select count(*) from %s', r.relation) into v_n;
    v_out := v_out || jsonb_build_object(r.relation, v_n);
  end loop;
  select coalesce(max(id),0) into v_n from net.http_request_queue;
  v_out := v_out || jsonb_build_object('net.http_request_queue_max_id', v_n);
  select count(*) into v_n from public.kernel_maintenance_write;
  v_out := v_out || jsonb_build_object('public.kernel_maintenance_write', v_n);
  return v_out;
end $function$;

revoke all on function public.fn_phase_d_committed_scenario_watermarks() from public;
grant execute on function public.fn_phase_d_committed_scenario_watermarks() to service_role;

-- ================================================================================================
-- 4. WHICH ROWS ARE OURS — the xid TREE, not the top-level xid
-- ================================================================================================
-- The first rehearsal removed the queue rows whose xmin equalled pg_current_xact_id() and left six
-- relations above their watermark: org_tasks +2, phase_c_trace +5, phase_c_task +1,
-- phase_d_dispatch +1, phase_c_workflow_run +1, phase_c_workflow_step_run +1. Every one of those
-- was written inside a plpgsql BEGIN/EXCEPTION block -- fn_event_dispatch has one, the kernel
-- adapters have one -- and a subtransaction gets its OWN xid, so an equality test on the top-level
-- xid cannot see them. J04's outbound helper already had this right and this is the same test:
-- a row VISIBLE to us whose xmin is still 'in progress' can only have been written by our own
-- transaction tree, because no other transaction's uncommitted rows are visible under READ
-- COMMITTED.
create or replace function public.fn_phase_d_row_is_ours(p_xmin xid)
returns boolean
language plpgsql stable
set search_path to 'public','pg_temp'
as $function$
declare
  v_top8  bigint := pg_current_xact_id()::text::bigint;
  v_top32 bigint := mod(pg_current_xact_id()::text::bigint, 4294967296);
  v_x     bigint := p_xmin::text::bigint;
begin
  if v_x < v_top32 then return false; end if;
  return pg_xact_status(((v_top8 - v_top32) + v_x)::text::xid8) = 'in progress';
exception when others then
  return false;
end $function$;

revoke all on function public.fn_phase_d_row_is_ours(xid) from public;
grant execute on function public.fn_phase_d_row_is_ours(xid) to service_role;

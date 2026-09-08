-- INQUIRIES CASCADE TO DISPATCH ON THEIR OWN (autonomy audit, blocking gap 1 — the inter-workflow cascade).
--
-- MEASURED. The five workflow_followup_event trigger types (route_evidence_changed -> W06,
-- safe_package_ready -> W08, safe_package_approved -> W12, notification_approved -> W13,
-- quotations_sufficient -> W15) are all activation_state='active' but implementation_state=
-- 'ADAPTER_READY_NO_LIVE_SENDER': the inbox adapter is ready and NOTHING submits to them. Their only
-- declared source is 'kernel:step_complete', and fn_kernel_step_complete (frozen) never calls
-- fn_kernel_trigger_submit. So a completed W05 inquiry never becomes a W06 route, a routed inquiry
-- never becomes a W08 package, an approved package never becomes a W12 dispatch. The marketplace does
-- not chain. (fn_phase_c_effect_state has reported 0 cross-workflow starts for exactly this reason.)
--
-- WHY THIS DOES NOT AMEND THE FROZEN STEP ENGINE. Amending fn_kernel_step_complete needs a verified
-- founder session (PCCR freeze amendment). It is also the wrong tool: fn_kernel_trigger_submit calls
-- fn_kernel_assert_not_in_delivery, so the producer may not be driven from a consumer, and the
-- followup inbox is a SEPARATE mechanism from the engine's intra-workflow step successor. The honest,
-- non-frozen wiring is a live sender that OBSERVES completed runs and submits the followup — exactly
-- what 'ADAPTER_READY_NO_LIVE_SENDER' is asking for. It carries its own honest source label
-- ('cron:workflow_succession_sweep'), registered in allowed_source_systems, never 'kernel:step_complete'.
--
-- SAFE BY CONSTRUCTION. fn_kernel_trigger_submit is idempotent (on conflict (idempotency_key) do
-- nothing) and fn_kernel_workflow_start dedupes on workflow:object:version, so re-running the sweep
-- starts each successor exactly once. Only runs that closed into their SUCCESS terminal ('completed';
-- W08's 'rejected' and blocked/'failed' closures are distinct terminals and never cascade) and whose
-- business_object_id is a well-formed 'type:{inquiry_id}' (canaries like ZZ-KERNEL-* are skipped)
-- are cascaded. The successor object is a pure transform on the SAME real inquiry id — no identity is
-- fabricated. SELF-PAUSES on the founder stand-down; scheduled DISABLED until resume.
--
-- SCOPE. Three unambiguous per-inquiry links are ACTIVE: W05->W06->W08->W12 (inquiry intake to
-- routing to supplier-safe packaging to matching/dispatch). Two links are staged INACTIVE with the
-- exact condition each needs — W12->W13 (a dispatch fans out to N notifications; needs per-
-- notification emission keyed by notification_id) and W14->W15 (emit only when an inquiry has
-- SUFFICIENT approved quotations; needs the sufficiency threshold). Activating either is a single
-- UPDATE workflow_succession SET active=true, no further change to this sender.
--
--   node scripts/apply_sql.mjs scripts/sql/inquiries_cascade_to_dispatch_on_their_own.sql --apply --ddl

begin;

-- ---- 1. THE EXPLICIT SUCCESSION MAP -----------------------------------------------------------
create table if not exists public.workflow_succession (
  predecessor_workflow_id text    not null references public.phase_b_workflow(workflow_id),
  followup_trigger_type   text    not null references public.kernel_trigger_type(trigger_type),
  followup_source_class   text    not null,
  on_terminal_state       text    not null default 'completed',
  object_key_name         text    not null default 'inquiry_id',
  active                  boolean not null default true,
  note                    text,
  primary key (predecessor_workflow_id, followup_trigger_type)
);
revoke all on public.workflow_succession from anon, authenticated;
grant select on public.workflow_succession to service_role;

insert into public.workflow_succession
  (predecessor_workflow_id, followup_trigger_type, followup_source_class, on_terminal_state, object_key_name, active, note)
values
  ('W05','workflow.route_evidence_changed','workflow_followup_event','completed','inquiry_id',true,
     'A quote-ready inquiry (W05 completed) is routed by W06. Blocked inquiries close as failed and do not cascade.'),
  ('W06','workflow.safe_package_ready','workflow_followup_event','completed','inquiry_id',true,
     'A confirmed route (W06 completed) is packaged for suppliers by W08.'),
  ('W08','workflow.safe_package_approved','workflow_followup_event','completed','inquiry_id',true,
     'An approved supplier-safe package (W08 completed; rejection is the distinct rejected terminal) is matched and dispatched by W12.'),
  ('W12','workflow.notification_approved','workflow_followup_event','completed','notification_id',false,
     'INACTIVE — fan-out. A W12 dispatch creates N notification records; W13 runs once per notification, keyed notification:{notification_id}. Needs per-notification emission, not one per-inquiry emit. Activate only once that emitter exists.'),
  ('W14','workflow.quotations_sufficient','workflow_followup_event','completed','inquiry_id',false,
     'INACTIVE — aggregate. W14 validates one quotation at a time; W15 starts only when the inquiry has SUFFICIENT approved quotations. Needs the sufficiency threshold before this may cascade.')
on conflict (predecessor_workflow_id, followup_trigger_type) do update
  set followup_source_class = excluded.followup_source_class,
      on_terminal_state = excluded.on_terminal_state,
      object_key_name = excluded.object_key_name,
      active = excluded.active,
      note = excluded.note;

-- ---- 2. REGISTER THE HONEST LIVE SENDER AS A PERMITTED SOURCE ---------------------------------
-- allowed_source_systems is text[]; fn_kernel_trigger_submit checks v_system = any(t_sources).
-- Adding this sender is the honest registration of a real producer, never a relabel: the trigger
-- fires because a real run reached its success terminal, and 'cron:workflow_succession_sweep' names
-- the producer truthfully. The routing guard only checks workflow ownership and is unaffected.
update public.kernel_trigger_type
   set allowed_source_systems =
         (select array(select distinct e from unnest(allowed_source_systems || array['cron:workflow_succession_sweep']) e))
 where trigger_type in ('workflow.route_evidence_changed','workflow.safe_package_ready',
                        'workflow.safe_package_approved','workflow.notification_approved',
                        'workflow.quotations_sufficient');

-- ---- 3. THE LIVE SENDER -----------------------------------------------------------------------
create or replace function public.fn_kernel_workflow_succession_sweep(p_limit integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  c        record;
  v_inq    text;
  v_res    jsonb;
  v_started int := 0;
  v_dupe    int := 0;
  v_failed  int := 0;
  v_errs    jsonb := '[]'::jsonb;
begin
  -- SELF-PAUSE: this starts real business workflows; it pauses with the workforce.
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'started',0);
  end if;

  -- A consumer may never drive the request side. A cron never sets kernel.in_delivery, but assert it
  -- so this can never be wired into a delivery path without failing loudly.
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_workflow_succession_sweep');

  for c in
    select r.run_id, r.workflow_id, r.business_object_id, r.object_version, r.closed_at,
           ws.followup_trigger_type, ws.followup_source_class,
           substring(r.business_object_id from position(':' in r.business_object_id) + 1) as inquiry_id
      from public.phase_c_workflow_run r
      join public.phase_b_workflow w  on w.workflow_id = r.workflow_id
      join public.workflow_succession ws
        on ws.predecessor_workflow_id = r.workflow_id and ws.active
     where r.state = ws.on_terminal_state
       and r.business_object_id like w.primary_object || ':%'      -- well-formed object; skips ZZ-* canaries
       and not exists (
             select 1 from public.kernel_trigger_inbox i
              where i.idempotency_key = 'succession:' || r.run_id || ':' || ws.followup_trigger_type)
     order by r.closed_at nulls last, r.run_id
     limit greatest(coalesce(p_limit,10),1)
  loop
    v_inq := nullif(btrim(c.inquiry_id), '');
    begin
      if v_inq is null then
        raise exception 'run % has no id segment in business_object_id %', c.run_id, c.business_object_id;
      end if;
      v_res := public.fn_kernel_trigger_submit(jsonb_build_object(
        'source_class',   c.followup_source_class,
        'source_system',  'cron:workflow_succession_sweep',
        'source_ref',     'run:' || c.run_id,
        'trigger_type',   c.followup_trigger_type,
        'requested_by',   'system.workflow_engine',
        'object_version', 1,
        'idempotency_key','succession:' || c.run_id || ':' || c.followup_trigger_type,
        'correlation_id', 'inquiry:' || v_inq,
        'causation_id',   'run:' || c.run_id,
        'raw_payload',    jsonb_build_object(
           'inquiry_id', v_inq, 'from_run_id', c.run_id, 'from_workflow', c.workflow_id)));
      if coalesce((v_res->>'duplicate')::boolean, false) then
        v_dupe := v_dupe + 1;
      else
        v_started := v_started + 1;
      end if;
    exception when others then
      v_failed := v_failed + 1;
      v_errs := v_errs || jsonb_build_object('run_id', c.run_id, 'followup', c.followup_trigger_type,
                                             'sqlstate', SQLSTATE, 'error', left(SQLERRM, 300));
    end;
  end loop;

  insert into public.agent_runs(agent, started_at, finished_at, status, counts, note)
  values ('workflow_succession_sweep', now(), now(),
          case when v_failed = 0 then 'ok' else 'partial' end,
          jsonb_build_object('started', v_started, 'duplicate', v_dupe, 'failed', v_failed),
          'Autonomous inter-workflow cascade: started ' || v_started || ' successor workflow(s), '
            || v_dupe || ' already running, ' || v_failed || ' failed to submit.'
            || case when v_failed > 0 then ' errors=' || v_errs::text else '' end);

  return jsonb_build_object('ok', v_failed = 0, 'started', v_started, 'duplicate', v_dupe,
                            'failed', v_failed, 'errors', v_errs, 'ran_at', now());
end $fn$;

revoke execute on function public.fn_kernel_workflow_succession_sweep(integer) from public;

-- ---- 4. SCHEDULE, DISABLED (self-pauses regardless; enabled at resume) ------------------------
select cron.schedule('workflow_succession_sweep_5min','*/5 * * * *',
  $$select public.fn_kernel_workflow_succession_sweep(20);$$);
select cron.alter_job((select jobid from cron.job where jobname='workflow_succession_sweep_5min'), active := false);

insert into public.cron_registry(jobname, human_name, category, purpose)
values ('workflow_succession_sweep_5min','Autonomous inter-workflow cascade','operations',
 'Every 5 min: observes workflow runs that closed into their success terminal and submits the declared '
 || 'workflow_followup_event trigger that starts the successor workflow, carrying the same inquiry forward '
 || '(W05->W06->W08->W12 active; W12->W13 and W14->W15 staged inactive). This is the live sender the five '
 || 'ADAPTER_READY_NO_LIVE_SENDER followup triggers were missing. Idempotent via fn_kernel_trigger_submit '
 || 'and fn_kernel_workflow_start dedupe. Self-pauses on the founder stand-down; scheduled disabled until resume.')
on conflict (jobname) do update set human_name=excluded.human_name, category=excluded.category, purpose=excluded.purpose;

commit;

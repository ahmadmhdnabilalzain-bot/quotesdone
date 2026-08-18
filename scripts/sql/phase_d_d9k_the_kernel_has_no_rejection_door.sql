-- =================================================================================================
-- Phase D — D9k. The kernel has no rejection door, and a board check that asserted the wrong repair.
--
-- Two boards went red on this session's own work. Both are right and both are fixed here rather
-- than adjusted to agree with what shipped.
--
-- RED 1 — `fn_kernel_retired_path_state.kernel_primitives_called_from_outside_the_kernel`, 1 of 9.
--
-- `fn_phase_d_handoff_reject` called `fn_phase_c_handoff_decide` directly. That routine is a
-- kernel-internal primitive; `kernel_write_authority` registers it with the words *"called only by
-- fn_kernel_handoff_accept"*, and the board counts exactly this. Calling it from Phase D is the
-- parallel-engine defect the whole boundary exists to prevent, and the board caught it in the same
-- session it was introduced.
--
-- THE UNCOMFORTABLE PART, STATED PLAINLY: the frozen kernel has `fn_kernel_handoff_accept` and NO
-- corresponding reject. There is no kernel door for a rejection. Phase C is frozen, so Phase D may
-- not add one, and reaching past the boundary to the primitive is what just went red.
--
-- So `fn_phase_d_handoff_reject` no longer touches `phase_c_handoff_run`. It records the Phase D
-- decision, proves the workflow did not advance, and returns `kernel_handoff_still_open: true`. The
-- rejection is real — the receiving owner's refusal is durable, specific, names the missing item and
-- returns accountability to the frozen contract's return owner, and nothing advances — but the
-- kernel's own handoff run stays open because only the kernel may close it.
--
-- That is a Phase C gap, not a Phase D one, and it is DISCLOSED rather than worked around: the new
-- board check counts handoff runs carrying a Phase D rejection that the kernel still shows as open.
-- It is expected to be non-zero and it is owned. Closing it needs a `fn_kernel_handoff_reject` in
-- the kernel, which is a Phase C change request, not a Phase D increment.
--
-- RED 2 — `fn_phase_d_fixture_state.inquiry_can_write_rfq_ready`, expected true, got false.
--
-- D9d added `rfq_ready` to the inquiry write map and D9f removed it again, because `trg_rfq_complete`
-- derives that column and overwrites whatever a caller supplies. D9f was right and the check was
-- left behind asserting the repair that D9f had just disproved. Retyping it to `false` would make
-- it agree with whatever is there. It is replaced by the check that says what actually matters:
-- the inquiry writer must cover the FACTS `fn_rfq_score` reads, and `rfq_ready` must NOT be mapped
-- because a mapped column a trigger overwrites is a promise the map cannot keep.
-- =================================================================================================

begin;

create or replace function public.fn_phase_d_handoff_reject(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c       public.phase_d_handoff_contract%rowtype;
  hr      public.phase_c_handoff_run%rowtype;
  prior   public.phase_d_handoff_acceptance%rowtype;
  v_id    bigint := nullif(p_input->>'handoff_run_id','')::bigint;
  v_actor text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_reason text  := nullif(btrim(coalesce(p_input->>'reason','')),'');
  v_missing text := nullif(btrim(coalesce(p_input->>'missing','')),'');
  v_return text  := nullif(btrim(coalesce(p_input->>'return_owner','')),'');
  v_code  text   := nullif(btrim(coalesce(p_input->>'rejection_code','')),'');
  v_idem  text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_resolved text;
  v_before int; v_after int;
  v_state_before text; v_state_after text;
  v_hstatus_before text; v_hstatus_after text;
  v_aid   bigint;
begin
  if v_id is null or v_actor is null then
    raise exception 'fn_phase_d_handoff_reject: handoff_run_id and actor_role_id are both required (pd_handoff_input_invalid)'
      using errcode = '22023';
  end if;
  v_idem := coalesce(v_idem, format('pd-handoff-reject:%s', v_id));

  select * into hr from public.phase_c_handoff_run where handoff_run_id = v_id;
  if not found then
    raise exception 'fn_phase_d_handoff_reject: no handoff run % (pd_handoff_not_found)', v_id
      using errcode = '23503';
  end if;

  select * into prior from public.phase_d_handoff_acceptance where handoff_run_id = v_id;
  if found then
    return jsonb_build_object('ok', false, 'replay', true, 'handoff_run_id', v_id,
      'outcome', prior.outcome, 'rejection_code', prior.rejection_code,
      'note', 'this handoff run already carries a Phase D decision');
  end if;

  select * into c from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
  if not found then
    raise exception 'fn_phase_d_handoff_reject: handoff % carries no Phase D contract (pd_handoff_uncontracted)',
      hr.handoff_id using errcode = '23503';
  end if;

  if hr.status <> 'open' then
    raise exception 'fn_phase_d_handoff_reject: handoff run % is % and only an open handoff may be decided (pd_handoff_not_open)',
      v_id, hr.status using errcode = '23514';
  end if;

  -- A REJECTION MUST BE ACTIONABLE. "Rejected" with no missing item leaves the work nowhere, which
  -- is the accountability gap the frozen closure_condition is written against.
  if v_reason is null or v_missing is null then
    raise exception 'fn_phase_d_handoff_reject: handoff % must be rejected with BOTH a reason and the exact missing item. Its frozen rejection_condition is: % (pd_handoff_rejection_unspecific)',
      c.handoff_id, left(c.rejection_condition, 160) using errcode = '22023';
  end if;

  select role_id into v_resolved from public.fn_phase_c_resolve_actor(v_actor);
  if v_resolved is null
     or v_resolved is distinct from (select role_id from public.fn_phase_c_resolve_actor(c.receiving_role_id)) then
    raise exception 'fn_phase_d_handoff_reject: handoff % is addressed to % and % may not decide it (pd_handoff_wrong_receiver)',
      c.handoff_id, c.receiving_role_id, v_actor using errcode = '23514';
  end if;

  -- The return owner defaults to the frozen contract's, never to whoever happens to be calling.
  v_return := coalesce(v_return, c.return_owner_role_id);

  select count(*) into v_before from public.phase_c_workflow_step_run where run_id = hr.run_id;
  select state into v_state_before from public.phase_c_workflow_run where run_id = hr.run_id;
  v_hstatus_before := hr.status;

  -- NO KERNEL PRIMITIVE IS CALLED. See the header: there is no fn_kernel_handoff_reject, Phase C is
  -- frozen, and fn_phase_c_handoff_decide is kernel-internal. The decision is recorded on the Phase D
  -- side and the kernel's handoff run is left exactly as it was.

  select count(*) into v_after from public.phase_c_workflow_step_run where run_id = hr.run_id;
  select state into v_state_after from public.phase_c_workflow_run where run_id = hr.run_id;
  select status into v_hstatus_after from public.phase_c_handoff_run where handoff_run_id = v_id;

  -- Asserted, not assumed. A rejection that advanced the workflow would be the defect §4 names.
  if v_after <> v_before then
    raise exception 'fn_phase_d_handoff_reject: rejecting handoff run % opened % new step run(s). A rejected handoff advances nothing. (pd_handoff_rejection_advanced_workflow)',
      v_id, v_after - v_before using errcode = '23514';
  end if;
  if v_state_after is distinct from v_state_before then
    raise exception 'fn_phase_d_handoff_reject: rejecting handoff run % moved run % from % to %. (pd_handoff_rejection_moved_run)',
      v_id, hr.run_id, v_state_before, v_state_after using errcode = '23514';
  end if;

  insert into public.phase_d_handoff_acceptance
    (handoff_run_id, handoff_id, run_id, workflow_id, outcome, actor_role_id,
     accountable_before, accountable_after, to_step_id,
     packet_digest, packet_keys_present, rejection_code, rejection_reason, missing_items,
     return_owner_role_id, sla_policy_id, due_at, idempotency_key)
  values (v_id, c.handoff_id, hr.run_id, c.workflow_id, 'rejected', v_resolved,
          c.accountable_before_accept,
          -- ACCOUNTABILITY DOES NOT TRANSFER ON A REJECTION. It returns to the named return owner,
          -- which is the whole point of the field; recording the receiver here would lose it.
          v_return, c.to_step_id,
          encode(sha256(convert_to(coalesce(p_input->'packet','{}'::jsonb)::text,'UTF8')),'hex'),
          '{}', coalesce(v_code, c.rejection_code), v_reason, v_missing, v_return,
          c.sla_policy_id, hr.due_at, v_idem)
  returning acceptance_id into v_aid;

  return jsonb_build_object(
    'ok', true, 'outcome', 'rejected', 'acceptance_id', v_aid,
    'handoff_run_id', v_id, 'handoff_id', c.handoff_id, 'run_id', hr.run_id,
    'rejection_code', coalesce(v_code, c.rejection_code),
    'reason', v_reason, 'missing', v_missing,
    'return_owner_role_id', v_return, 'accountable_now', v_return,
    'step_runs_before', v_before, 'step_runs_after', v_after,
    'run_state_before', v_state_before, 'run_state_after', v_state_after,
    'workflow_advanced', false,
    'kernel_handoff_status', v_hstatus_after,
    'kernel_handoff_still_open', (v_hstatus_after = 'open'),
    'disclosure', 'the frozen kernel exposes no handoff rejection routine, so the kernel-side handoff run is left open; closing it needs a Phase C change request, not a Phase D increment');
end $fn$;

-- ---- the board, corrected -------------------------------------------------------------------------

create or replace function public.fn_phase_d_fixture_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select 'fixture_stages_declared', '>= 20',
         (select count(*)::text from public.phase_d_fixture_stage),
         (select count(*) from public.phase_d_fixture_stage) >= 20
  union all
  select 'stages_naming_an_unbound_object', '0',
         (select count(*)::text from public.phase_d_fixture_stage s
           where not exists (select 1 from public.phase_d_business_object_binding b
                              where b.object_id = s.object_id)),
         not exists (select 1 from public.phase_d_fixture_stage s
                      where not exists (select 1 from public.phase_d_business_object_binding b
                                         where b.object_id = s.object_id))
  union all
  select 'stages_requiring_a_stage_that_does_not_exist', '0',
         (select count(*)::text from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
           where not exists (select 1 from public.phase_d_fixture_stage p where p.stage_key = r)),
         not exists (select 1 from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
                      where not exists (select 1 from public.phase_d_fixture_stage p
                                         where p.stage_key = r))
  union all
  select 'stages_depending_on_a_later_stage', '0',
         (select count(*)::text from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
            join public.phase_d_fixture_stage p on p.stage_key = r
           where p.stage_no >= s.stage_no),
         not exists (select 1 from public.phase_d_fixture_stage s, unnest(s.requires_stages) r
                       join public.phase_d_fixture_stage p on p.stage_key = r
                      where p.stage_no >= s.stage_no)
  union all
  select 'supplier_account_can_write_verified', 'true',
         (select (column_map ? 'verified')::text from public.phase_d_object_write_map
           where object_id = 'supplier_account'),
         (select column_map ? 'verified' from public.phase_d_object_write_map
           where object_id = 'supplier_account')
  union all
  -- REPLACES `inquiry_can_write_rfq_ready`. rfq_ready is derived by trg_rfq_complete, so mapping it
  -- is a promise the map cannot keep; what the writer must cover is the FACTS fn_rfq_score reads.
  select 'inquiry_writer_covers_the_readiness_facts', 'emirate, scope_type, budget, trades mapped',
         (select string_agg(k, ', ' order by k) from unnest(array['emirate','scope_type','budget','trades']) k
           where (select column_map ? k from public.phase_d_object_write_map where object_id='inquiry')),
         (select column_map ?& array['emirate','scope_type','budget','trades']
            from public.phase_d_object_write_map where object_id = 'inquiry')
  union all
  select 'inquiry_writer_maps_a_derived_column', '0',
         (select (column_map ? 'rfq_ready')::int::text from public.phase_d_object_write_map
           where object_id = 'inquiry'),
         not (select column_map ? 'rfq_ready' from public.phase_d_object_write_map
               where object_id = 'inquiry')
  union all
  select 'fixture_rows_surviving_in_business_tables', '0',
         (select coalesce(sum(surviving_rows),0)::text from public.fn_phase_d_fixture_residue()),
         coalesce((select sum(surviving_rows) from public.fn_phase_d_fixture_residue()), 0) = 0
  union all
  select 'fixture_stage_targeting_public_notifications', '0',
         (select count(*)::text from public.phase_d_fixture_stage s
            join public.phase_d_business_object_binding b on b.object_id = s.object_id
           where b.canonical_relation = 'public.notifications'),
         not exists (select 1 from public.phase_d_fixture_stage s
                       join public.phase_d_business_object_binding b on b.object_id = s.object_id
                      where b.canonical_relation = 'public.notifications')
  union all
  select 'canonical_object_writes_that_can_reach_a_notification_trigger', 'informational',
         (select count(*)::text from public.fn_phase_d_outbound_exposure()), true
  union all
  select 'fixture_identities_carrying_a_contact_detail', '0',
         (select count(*)::text from public.customers c
           where c.full_name like 'ZZ DEMO — %'
             and (coalesce(c.email,'') <> '' or coalesce(c.phone,'') <> '')),
         not exists (select 1 from public.customers c
                      where c.full_name like 'ZZ DEMO — %'
                        and (coalesce(c.email,'') <> '' or coalesce(c.phone,'') <> ''));
$fn$;

-- ---- the disclosure, as a counted board row ---------------------------------------------------------

create or replace function public.fn_phase_d_handoff_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  with live as (select count(*) n from public.phase_b_handoff),
       con  as (select count(*) n from public.phase_d_handoff_contract)
  select 'effective_handoffs_contracted', (select n::text from live),
         (select n::text from con), (select n from con) = (select n from live)
  union all
  select 'contracts_with_no_live_handoff', '0',
         (select count(*)::text from public.phase_d_handoff_contract c
           where not exists (select 1 from public.phase_b_handoff h where h.handoff_id = c.handoff_id)),
         not exists (select 1 from public.phase_d_handoff_contract c
                      where not exists (select 1 from public.phase_b_handoff h
                                         where h.handoff_id = c.handoff_id))
  union all
  select 'contracts_whose_packet_is_only_boilerplate', '0',
         (select count(*)::text from public.phase_d_handoff_contract
           where distinguishing_key in ('source_business_object_version','acceptance_evidence',
                                        'unresolved_blockers','requested_next_action')),
         not exists (select 1 from public.phase_d_handoff_contract
                      where distinguishing_key in ('source_business_object_version','acceptance_evidence',
                                                   'unresolved_blockers','requested_next_action'))
  union all
  select 'distinct_distinguishing_keys', (select n::text from live),
         (select count(distinct distinguishing_key)::text from public.phase_d_handoff_contract),
         (select count(distinct distinguishing_key) from public.phase_d_handoff_contract)
           = (select n from live)
  union all
  select 'contracts_drifted_from_the_frozen_packet', '0',
         (select count(*)::text from public.phase_d_handoff_contract c
            join public.phase_b_handoff h on h.handoff_id = c.handoff_id
           where c.required_packet_sha256
                 <> encode(sha256(convert_to(h.required_packet,'UTF8')),'hex')),
         not exists (select 1 from public.phase_d_handoff_contract c
                       join public.phase_b_handoff h on h.handoff_id = c.handoff_id
                      where c.required_packet_sha256
                            <> encode(sha256(convert_to(h.required_packet,'UTF8')),'hex'))
  union all
  select 'contracts_with_no_parsed_sla_target', '0',
         (select count(*)::text from public.phase_d_handoff_contract where sla_target is null),
         not exists (select 1 from public.phase_d_handoff_contract where sla_target is null)
  union all
  select 'contracts_where_accountability_does_not_move', '0',
         (select count(*)::text from public.phase_d_handoff_contract
           where accountable_before_accept = accountable_after_accept),
         not exists (select 1 from public.phase_d_handoff_contract
                      where accountable_before_accept = accountable_after_accept)
  union all
  select 'acceptances_that_opened_no_step_run', '0',
         (select count(*)::text from public.phase_d_handoff_acceptance
           where outcome = 'accepted' and opened_step_run_id is null),
         not exists (select 1 from public.phase_d_handoff_acceptance
                      where outcome = 'accepted' and opened_step_run_id is null)
  union all
  select 'handoff_runs_with_two_phase_d_decisions', '0',
         (select coalesce(count(*),0)::text from (
            select handoff_run_id from public.phase_d_handoff_acceptance
             group by handoff_run_id having count(*) > 1) x),
         not exists (select 1 from (
            select handoff_run_id from public.phase_d_handoff_acceptance
             group by handoff_run_id having count(*) > 1) x)
  union all
  select 'cancelled_runs_with_an_open_handoff', '0',
         (select count(*)::text from public.phase_c_workflow_run r
           where r.state = 'cancelled'
             and exists (select 1 from public.phase_c_handoff_run hr
                          where hr.run_id = r.run_id and hr.status = 'open')),
         not exists (select 1 from public.phase_c_workflow_run r
                      where r.state = 'cancelled'
                        and exists (select 1 from public.phase_c_handoff_run hr
                                     where hr.run_id = r.run_id and hr.status = 'open'))
  union all
  -- DISCLOSED. The frozen kernel exposes fn_kernel_handoff_accept and no rejection routine, and
  -- fn_phase_c_handoff_decide is a kernel-internal primitive Phase D may not call. So a Phase D
  -- rejection is durable and refuses to advance the workflow, and the kernel-side handoff run stays
  -- open. Counting it here is the disclosure; closing it is a Phase C change request.
  select 'phase_d_rejections_the_kernel_still_shows_open', 'informational — no kernel rejection door',
         (select count(*)::text from public.phase_d_handoff_acceptance a
            join public.phase_c_handoff_run h on h.handoff_run_id = a.handoff_run_id
           where a.outcome = 'rejected' and h.status = 'open'), true;
$fn$;

-- ---- and the cancellation path was calling the kernel with the wrong argument names ---------------
-- Found by execution: `fn_kernel_cancel: subject_kind must be founder_command or workflow_run, got`.
-- The kernel takes `subject_kind` / `subject_ref` / `actor`, and D9 sent `run_id` / `actor_role_id`,
-- so every field arrived empty and the routine refused before doing anything. It had never been
-- executed, and a cancellation path that has never run is exactly the kind of recovery path this
-- estate keeps finding guarded by a condition that cannot occur.

create or replace function public.fn_phase_d_handoff_cancel(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_run    bigint := nullif(p_input->>'run_id','')::bigint;
  v_reason text   := nullif(btrim(coalesce(p_input->>'reason','')),'');
  v_actor  text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_open_before int; v_open_after int; v_state text;
  v_res    jsonb;
begin
  if v_run is null or v_reason is null or v_actor is null then
    raise exception 'fn_phase_d_handoff_cancel: run_id, reason and actor_role_id are all required. A cancellation with no reason is not auditable. (pd_cancel_input_invalid)'
      using errcode = '22023';
  end if;

  select count(*) into v_open_before from public.phase_c_handoff_run
   where run_id = v_run and status = 'open';

  -- The kernel's own argument names, taken from its body rather than guessed.
  v_res := public.fn_kernel_cancel(jsonb_build_object(
    'subject_kind', 'workflow_run',
    'subject_ref',  v_run::text,
    'op',           'cancel',
    'reason',       v_reason,
    'actor',        v_actor));

  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'fn_phase_d_handoff_cancel: the kernel refused to cancel run %: % (pd_cancel_kernel_refused)',
      v_run, coalesce(v_res::text,'(no result)') using errcode = '23514';
  end if;

  select count(*) into v_open_after from public.phase_c_handoff_run
   where run_id = v_run and status = 'open';
  select state into v_state from public.phase_c_workflow_run where run_id = v_run;

  -- The postcondition is a row count, not an intention.
  if v_open_after <> 0 then
    raise exception 'fn_phase_d_handoff_cancel: run % was cancelled and % handoff run(s) are still open. (pd_cancel_left_open_handoff)',
      v_run, v_open_after using errcode = '23514';
  end if;
  if v_state is distinct from 'cancelled' then
    raise exception 'fn_phase_d_handoff_cancel: run % is % after a cancellation. (pd_cancel_run_not_cancelled)',
      v_run, coalesce(v_state,'(missing)') using errcode = '23514';
  end if;

  return jsonb_build_object(
    'ok', true, 'run_id', v_run, 'run_state', v_state,
    'open_handoffs_before', v_open_before, 'open_handoffs_after', v_open_after,
    'kernel_result', v_res);
end $fn$;

revoke all on function public.fn_phase_d_handoff_cancel(jsonb) from public;
grant execute on function public.fn_phase_d_handoff_cancel(jsonb) to service_role;

commit;

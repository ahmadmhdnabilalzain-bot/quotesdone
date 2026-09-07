-- =================================================================================================
-- Phase D — D9. The handoff is 159 contracts, not one.
--
-- WHAT WAS MEASURED FIRST, AND IT IS THE WHOLE REASON THIS FILE EXISTS
--
-- `fn_phase_c_handoff_packet_valid(handoff_id, packet)` reads its handoff_id argument only to
-- confirm the handoff exists. It then checks a FIXED five-key list —
-- business_object_id, object_version, output, evidence_refs, requested_action — for every one of
-- the 159 handoffs. `required_packet`, `receiving_acceptance_criteria`, `rejection_condition`,
-- `return_owner_role_id`, `closure_condition` and `sla_policy_id` are never read.
--
-- That is the same shape as the 32 gates sharing one predicate: the 159 handoffs are behaviourally
-- ONE handoff, and a packet missing the thing the frozen registry actually asks for is accepted.
-- Measured on production: 159 handoffs, 795 declared packet clauses, 163 distinct keys — four
-- boilerplate clauses shared by all 159, and exactly one clause unique to each handoff. So every
-- handoff really does ask for something of its own, and nothing was reading it.
--
-- NOTHING HERE IS HAND-TYPED. Packet keys are the semicolon clauses of the frozen `required_packet`
-- put through `fn_phase_d_slug` — the identical rule D1 used for the 514 handler contracts, so the
-- two vocabularies agree. Every contract carries the sha256 of the frozen prose it was derived
-- from, so a Phase B text change is detectable rather than leaving a contract quietly describing a
-- handoff that no longer says that.
--
-- THE KERNEL STILL MOVES THE STATE. `fn_phase_d_handoff_accept` validates the contract and then
-- calls the frozen `fn_kernel_handoff_accept`, which opens the successor step run, creates the one
-- task and moves the run. It does not re-implement any of that; a second creator for one object is
-- what deadlocked 16 of 30 workflows.
--
-- The generic Phase C path is UNCHANGED. Making it strict would refuse every handoff acceptance in
-- the estate — not a stricter check, an outage — exactly as D5 decided for the gates.
-- =================================================================================================

begin;

-- ---- 1. the contract, derived ------------------------------------------------------------------

create table if not exists public.phase_d_handoff_contract (
  -- Named explicitly with the identity Postgres itself generates. The canonical routine engine can
  -- only attribute an auto-generated constraint name when `references` sits on the same source line
  -- as its column, and a clause wrapped for readability reads to it as uncommitted DDL. The
  -- instrument is not wrong — a wrapped clause is genuinely harder to attribute — so the file is
  -- made explicit rather than the check taught to accept a shape it cannot attribute.
  handoff_id                text primary key,
  constraint phase_d_handoff_contract_handoff_id_fkey
    foreign key (handoff_id) references public.phase_b_handoff(handoff_id) on delete restrict,
  workflow_id               text not null,
  from_step_id              text not null,
  to_step_id                text not null,
  sending_role_id           text not null,
  receiving_role_id         text not null,
  handoff_type              text not null,
  packet_keys               text[] not null,
  distinguishing_key        text not null,
  kernel_packet_keys        text[] not null,
  source_object_id          text,
  source_object_version_key text not null,
  acceptance_criteria       text not null,
  rejection_condition       text not null,
  rejection_code            text not null,
  return_owner_role_id      text not null,
  accountable_before_accept text not null,
  accountable_after_accept  text not null,
  sla_policy_id             text not null,
  sla_target_text           text,
  sla_target                interval,
  closure_condition         text not null,
  required_packet_sha256    text not null,
  derived_at                timestamptz not null default now(),
  constraint phase_d_handoff_contract_keys_ck
    check (cardinality(packet_keys) >= 1 and cardinality(kernel_packet_keys) = 5),
  constraint phase_d_handoff_contract_owner_ck
    check (btrim(return_owner_role_id) <> '' and btrim(accountable_before_accept) <> ''
           and btrim(accountable_after_accept) <> '')
);

comment on table public.phase_d_handoff_contract is
  'Phase D: one acceptance contract per effective handoff, derived from the frozen phase_b_handoff row. 159 rows under PBCR-001. Never hand-typed; required_packet_sha256 makes a Phase B prose change detectable.';

-- The effective denominator is 159 and it is founder-approved (PBCR-001 removed H-W14-04-05 and
-- H-W14-05-06 because both ends became the same role). This file does not reopen it: it derives
-- from whatever `phase_b_handoff` holds and then asserts the count is 159 below.
insert into public.phase_d_handoff_contract (
  handoff_id, workflow_id, from_step_id, to_step_id, sending_role_id, receiving_role_id,
  handoff_type, packet_keys, distinguishing_key, kernel_packet_keys, source_object_id,
  source_object_version_key, acceptance_criteria, rejection_condition, rejection_code,
  return_owner_role_id, accountable_before_accept, accountable_after_accept,
  sla_policy_id, sla_target_text, sla_target, closure_condition, required_packet_sha256)
select
  h.handoff_id,
  h.workflow_id,
  h.from_step_id,
  h.to_step_id,
  h.sending_role_id,
  h.receiving_role_id,
  h.handoff_type,
  k.keys,
  k.distinguishing,
  array['business_object_id','object_version','output','evidence_refs','requested_action'],
  e.effect_object_id,
  'object_version',
  h.receiving_acceptance_criteria,
  h.rejection_condition,
  'pd_handoff_rejected',
  -- The frozen registry names a return owner on every row; if one were blank the CHECK above
  -- refuses the insert rather than defaulting to the sender and calling it a contract.
  h.return_owner_role_id,
  h.sending_role_id,     -- accountability BEFORE acceptance stays with the sender
  h.receiving_role_id,   -- and transfers on acceptance, not on send
  h.sla_policy_id,
  p.target,
  s.parsed,
  h.closure_condition,
  encode(sha256(convert_to(h.required_packet, 'UTF8')), 'hex')
from public.phase_b_handoff h
left join public.phase_d_step_effect e on e.step_id = h.from_step_id
left join public.phase_b_sla_policy  p on p.sla_policy_id = h.sla_policy_id
cross join lateral (
  select array_agg(x.k order by x.ord) as keys,
         -- The distinguishing clause is the one that is NOT shared by all 159. Measured on
         -- production: 795 clauses, 163 distinct keys — four boilerplate plus exactly one unique
         -- per handoff. Taking "the first clause" would be an assumption about ordering; this takes
         -- the one that is actually not boilerplate, and falls back to the first only if that ever
         -- stops being true, which `contracts_whose_packet_is_only_boilerplate` then reports.
         coalesce(
           (select y.k from unnest(array_agg(x.k order by x.ord)) with ordinality y(k, o)
             where y.k not in ('source_business_object_version','acceptance_evidence',
                               'unresolved_blockers','requested_next_action')
             order by y.o limit 1),
           (array_agg(x.k order by x.ord))[1])                          as distinguishing
    from (select public.fn_phase_d_slug(btrim(c.clause)) as k, c.ord
            from unnest(string_to_array(h.required_packet, ';')) with ordinality as c(clause, ord)
           where btrim(coalesce(c.clause, '')) <> '') x
) k
cross join lateral (
  select case
    when m[2] = 'minute' then (m[1] || ' minutes')::interval
    when m[2] = 'hour'   then (m[1] || ' hours')::interval
    when m[2] = 'day'    then (m[1] || ' days')::interval
    when m[2] = 'week'   then (m[1] || ' weeks')::interval
    else null end as parsed
    from (select regexp_match(lower(coalesce(p.target, '')), '(\d+)\s*(minute|hour|day|week)') as m) mm
) s
on conflict (handoff_id) do update set
  packet_keys               = excluded.packet_keys,
  distinguishing_key        = excluded.distinguishing_key,
  source_object_id          = excluded.source_object_id,
  acceptance_criteria       = excluded.acceptance_criteria,
  rejection_condition       = excluded.rejection_condition,
  return_owner_role_id      = excluded.return_owner_role_id,
  accountable_before_accept = excluded.accountable_before_accept,
  accountable_after_accept  = excluded.accountable_after_accept,
  sla_policy_id             = excluded.sla_policy_id,
  sla_target_text           = excluded.sla_target_text,
  sla_target                = excluded.sla_target,
  closure_condition         = excluded.closure_condition,
  required_packet_sha256    = excluded.required_packet_sha256,
  derived_at                = now();

-- A contract for a handoff the live registry no longer carries is a stale row, not a contract.
delete from public.phase_d_handoff_contract c
 where not exists (select 1 from public.phase_b_handoff h where h.handoff_id = c.handoff_id);

-- ---- 2. the acceptance ledger -------------------------------------------------------------------
-- UNIQUE (handoff_run_id) is the idempotency guarantee, and it is a constraint rather than a
-- convention. What a duplicate-acceptance test asserts on is the TASK COUNT on the receiving step,
-- because a replay that returned a fresh success while quietly opening a second task is the exact
-- defect this table exists to prevent, and the returned payload cannot tell the two apart.

create table if not exists public.phase_d_handoff_acceptance (
  acceptance_id       bigint generated always as identity primary key,
  handoff_run_id      bigint not null,
  handoff_id          text   not null references public.phase_d_handoff_contract(handoff_id),
  run_id              bigint not null,
  workflow_id         text   not null,
  outcome             text   not null,
  actor_role_id       text   not null,
  accountable_before  text   not null,
  accountable_after   text   not null,
  to_step_id          text,
  opened_step_run_id  bigint,
  opened_task_id      bigint,
  packet_digest       text   not null,
  packet_keys_present text[] not null,
  packet_keys_missing text[],
  rejection_code      text,
  rejection_reason    text,
  missing_items       text,
  return_owner_role_id text,
  sla_policy_id       text,
  due_at              timestamptz,
  sla_breached        boolean,
  idempotency_key     text   not null,
  trace_id            bigint,
  decided_at          timestamptz not null default now(),
  constraint phase_d_handoff_acceptance_outcome_ck
    check (outcome in ('accepted','rejected','cancelled','superseded')),
  constraint phase_d_handoff_acceptance_reject_ck
    check (outcome <> 'rejected'
           or (coalesce(btrim(rejection_reason),'') <> ''
               and coalesce(btrim(missing_items),'') <> ''
               and coalesce(btrim(return_owner_role_id),'') <> '')),
  constraint phase_d_handoff_acceptance_accept_ck
    check (outcome <> 'accepted' or opened_step_run_id is not null),
  constraint phase_d_handoff_acceptance_one_per_run
    unique (handoff_run_id)
);

comment on table public.phase_d_handoff_acceptance is
  'Phase D: one decision per handoff run. UNIQUE(handoff_run_id) is why a duplicate acceptance cannot open a second task.';

create index if not exists phase_d_handoff_acceptance_run_idx
  on public.phase_d_handoff_acceptance (run_id, outcome);

-- ---- 3. the strict packet check -----------------------------------------------------------------

create or replace function public.fn_phase_d_handoff_packet_valid(p_handoff_id text, p_packet jsonb)
returns table(valid boolean, missing text[], required text[], present text[])
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c public.phase_d_handoff_contract%rowtype;
  v_all text[];
begin
  select * into c from public.phase_d_handoff_contract where handoff_id = p_handoff_id;
  if not found then
    -- Fail closed. An uncontracted handoff is not a permissive one.
    valid := false;
    missing := array['(no Phase D contract for ' || coalesce(p_handoff_id,'(null)') || ')'];
    required := '{}'; present := '{}';
    return next; return;
  end if;

  if p_packet is null or jsonb_typeof(p_packet) <> 'object' then
    valid := false; missing := c.packet_keys || c.kernel_packet_keys;
    required := c.packet_keys || c.kernel_packet_keys; present := '{}';
    return next; return;
  end if;

  -- BOTH sets. The contract keys come from the frozen prose; the kernel keys come from the kernel.
  -- Dropping either would mean a packet that satisfies this routine and is then refused downstream,
  -- or the reverse — a check that disagrees with the thing it guards.
  v_all := c.packet_keys || c.kernel_packet_keys;

  select array_agg(k order by k) into missing
    from unnest(v_all) k
   where not (p_packet ? k)
      or jsonb_typeof(p_packet->k) = 'null'
      or (jsonb_typeof(p_packet->k) = 'string' and btrim(p_packet->>k) = '');

  select array_agg(k order by k) into present
    from unnest(v_all) k where p_packet ? k;

  required := v_all;
  present  := coalesce(present, '{}');
  valid    := (missing is null);
  return next;
end $fn$;

-- ---- 4. acceptance — contract first, then the frozen kernel --------------------------------------

create or replace function public.fn_phase_d_handoff_accept(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c        public.phase_d_handoff_contract%rowtype;
  hr       public.phase_c_handoff_run%rowtype;
  r        public.phase_c_workflow_run%rowtype;
  prior    public.phase_d_handoff_acceptance%rowtype;
  v_id     bigint := nullif(p_input->>'handoff_run_id','')::bigint;
  v_actor  text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_packet jsonb  := p_input->'packet';
  v_idem   text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_valid  record;
  v_res    jsonb;
  v_resolved text;
  v_due    timestamptz;
  v_tasks  int;
  v_aid    bigint;
begin
  if v_id is null or v_actor is null then
    raise exception 'fn_phase_d_handoff_accept: handoff_run_id and actor_role_id are both required (pd_handoff_input_invalid)'
      using errcode = '22023';
  end if;
  v_idem := coalesce(v_idem, format('pd-handoff-accept:%s', v_id));

  select * into hr from public.phase_c_handoff_run where handoff_run_id = v_id;
  if not found then
    raise exception 'fn_phase_d_handoff_accept: no handoff run % (pd_handoff_not_found)', v_id
      using errcode = '23503';
  end if;

  -- IDEMPOTENCY IS A READ. The kernel would raise k3_handoff_not_open on a second call, which is
  -- correct but tells a replaying caller nothing about what happened the first time. The stored
  -- decision is returned verbatim and NOTHING is created.
  select * into prior from public.phase_d_handoff_acceptance where handoff_run_id = v_id;
  if found then
    return jsonb_build_object(
      'ok', prior.outcome = 'accepted', 'replay', true,
      'handoff_run_id', v_id, 'handoff_id', prior.handoff_id, 'outcome', prior.outcome,
      'run_id', prior.run_id, 'to_step_id', prior.to_step_id,
      'step_run_id', prior.opened_step_run_id, 'task_id', prior.opened_task_id,
      'accountable_now', prior.accountable_after,
      'note', 'this handoff run already carries a Phase D decision; no second task was opened');
  end if;

  select * into c from public.phase_d_handoff_contract where handoff_id = hr.handoff_id;
  if not found then
    raise exception 'fn_phase_d_handoff_accept: handoff % carries no Phase D contract — refusing to accept under a contract nobody declared (pd_handoff_uncontracted)',
      hr.handoff_id using errcode = '23503';
  end if;

  if hr.status <> 'open' then
    raise exception 'fn_phase_d_handoff_accept: handoff run % is % and only an open handoff may be accepted (pd_handoff_not_open)',
      v_id, hr.status using errcode = '23514';
  end if;

  select * into r from public.phase_c_workflow_run where run_id = hr.run_id;
  if not found then
    raise exception 'fn_phase_d_handoff_accept: handoff run % names workflow run %, which does not exist (pd_handoff_run_missing)',
      v_id, hr.run_id using errcode = '23503';
  end if;
  -- A run that has reached a terminal state, or is blocked, cannot take work back. The kernel
  -- would move it to active regardless, because its transition guard permits waiting_* -> active
  -- and says nothing about cancelled -> active being reached from here.
  if r.state not in ('waiting_handoff','waiting_review','active','waiting_input') then
    raise exception 'fn_phase_d_handoff_accept: run % is in state % and no handoff may be accepted into it (pd_handoff_run_state_invalid)',
      r.run_id, r.state using errcode = '23514';
  end if;

  -- THE RECEIVER, DECIDED FROM THE CONTRACT AND NOT FROM THE RUN ROW. The kernel checks the same
  -- thing against phase_c_handoff_run.receiving_role_id; checking the frozen contract as well means
  -- a handoff run whose receiver was written wrong cannot be accepted by the wrong role and then
  -- have the kernel agree with it.
  select role_id into v_resolved from public.fn_phase_c_resolve_actor(v_actor);
  if v_resolved is null
     or v_resolved is distinct from (select role_id from public.fn_phase_c_resolve_actor(c.receiving_role_id)) then
    raise exception 'fn_phase_d_handoff_accept: handoff % is addressed to % and % may not accept it (pd_handoff_wrong_receiver)',
      c.handoff_id, c.receiving_role_id, v_actor using errcode = '23514';
  end if;

  select * into v_valid from public.fn_phase_d_handoff_packet_valid(hr.handoff_id, v_packet);
  if not v_valid.valid then
    raise exception 'fn_phase_d_handoff_accept: handoff % packet is missing [%]. Its frozen required_packet is: % (pd_handoff_packet_incomplete)',
      c.handoff_id, array_to_string(v_valid.missing, ', '),
      left((select required_packet from public.phase_b_handoff where handoff_id = c.handoff_id), 180)
      using errcode = '23514';
  end if;

  -- SLA is a measurement, not a second gate. A late acceptance is still an acceptance; recording it
  -- as a breach is the contract element, and refusing it would invent a rule Phase B does not state.
  v_due := coalesce(hr.due_at, hr.opened_at + c.sla_target);

  -- ---- the frozen kernel does the state move ---------------------------------------------------
  v_res := public.fn_kernel_handoff_accept(jsonb_build_object(
    'handoff_run_id', v_id, 'actor_role_id', v_actor, 'packet', v_packet,
    'priority', coalesce(nullif(p_input->>'priority',''), 'P2')));

  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'fn_phase_d_handoff_accept: the kernel refused handoff run %: % (pd_handoff_kernel_refused)',
      v_id, coalesce(v_res::text, '(no result)') using errcode = '23514';
  end if;

  -- ONE OPEN TASK ON THE RECEIVING STEP. Asserted on the row count, not inferred from the kernel's
  -- own summary. `phase_c_task` carries (run_id, step_id) and no step_run_id, so the population is
  -- the receiving step of this run; a duplicate acceptance that opened a second task makes this 2,
  -- which is precisely the failure "duplicate acceptance creating duplicate task = 0" names.
  select count(*) into v_tasks from public.phase_c_task t
   where t.run_id = r.run_id and t.step_id = c.to_step_id and t.closed_at is null;
  if v_tasks <> 1 then
    raise exception 'fn_phase_d_handoff_accept: accepting handoff run % left % open task(s) on %; exactly one is the contract (pd_handoff_task_count_wrong)',
      v_id, v_tasks, c.to_step_id using errcode = '23514';
  end if;

  insert into public.phase_d_handoff_acceptance
    (handoff_run_id, handoff_id, run_id, workflow_id, outcome, actor_role_id,
     accountable_before, accountable_after, to_step_id, opened_step_run_id, opened_task_id,
     packet_digest, packet_keys_present, packet_keys_missing, sla_policy_id, due_at, sla_breached,
     idempotency_key, trace_id)
  values (v_id, c.handoff_id, r.run_id, r.workflow_id, 'accepted', v_resolved,
          c.accountable_before_accept, c.accountable_after_accept, c.to_step_id,
          (v_res->>'step_run_id')::bigint, (v_res->>'task_id')::bigint,
          encode(sha256(convert_to(coalesce(v_packet,'{}'::jsonb)::text,'UTF8')),'hex'),
          v_valid.present, null, c.sla_policy_id, v_due,
          case when v_due is null then null else now() > v_due end,
          v_idem, (v_res->>'handoff_trace_id')::bigint)
  returning acceptance_id into v_aid;

  if v_aid is null then
    raise exception 'fn_phase_d_handoff_accept: the acceptance ledger insert for handoff run % returned no id (pd_handoff_ledger_produced_nothing)',
      v_id using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'replay', false, 'acceptance_id', v_aid,
    'handoff_run_id', v_id, 'handoff_id', c.handoff_id,
    'run_id', r.run_id, 'workflow_id', r.workflow_id,
    'accepted_by', v_resolved,
    'accountable_before', c.accountable_before_accept,
    'accountable_after', c.accountable_after_accept,
    'to_step_id', c.to_step_id,
    'step_run_id', (v_res->>'step_run_id')::bigint,
    'task_id', (v_res->>'task_id')::bigint,
    'tasks_opened', v_tasks,
    'packet_keys_checked', v_valid.required,
    'sla_policy_id', c.sla_policy_id, 'due_at', v_due,
    'sla_breached', case when v_due is null then null else now() > v_due end,
    'run_state', v_res->>'run_state',
    'closure_condition', c.closure_condition);
end $fn$;

-- ---- 5. rejection — specific, and it does NOT advance the workflow -------------------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_handoff_reject was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---- 6. cancellation leaves no open handoff ------------------------------------------------------
-- The kernel already owns this: fn_kernel_cancel is the registered writer that cancels open handoff
-- runs beneath a cancelled run. This routine calls it and then PROVES the postcondition by counting,
-- because "cancellation leaving open handoff = 0" is a claim about rows, not about intent.

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_handoff_cancel was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---- 7. the board ---------------------------------------------------------------------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_handoff_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---- 8. grants ------------------------------------------------------------------------------------
-- Every SECURITY DEFINER function created here is granted EXECUTE to PUBLIC by Postgres. Revoking
-- from `anon` alone is a silent no-op when the grant is held through PUBLIC, so PUBLIC is the target.

revoke all on function public.fn_phase_d_handoff_accept(jsonb) from public;
revoke all on function public.fn_phase_d_handoff_reject(jsonb) from public;
revoke all on function public.fn_phase_d_handoff_cancel(jsonb) from public;
revoke all on function public.fn_phase_d_handoff_packet_valid(text, jsonb) from public;
revoke all on function public.fn_phase_d_handoff_state() from public;

grant execute on function public.fn_phase_d_handoff_accept(jsonb) to service_role;
grant execute on function public.fn_phase_d_handoff_reject(jsonb) to service_role;
grant execute on function public.fn_phase_d_handoff_cancel(jsonb) to service_role;
grant execute on function public.fn_phase_d_handoff_packet_valid(text, jsonb) to service_role;
grant execute on function public.fn_phase_d_handoff_state() to service_role, authenticated;

revoke all on public.phase_d_handoff_contract from anon, authenticated;
revoke all on public.phase_d_handoff_acceptance from anon, authenticated;
grant select on public.phase_d_handoff_contract to service_role;
grant select on public.phase_d_handoff_acceptance to service_role;

alter table public.phase_d_handoff_contract   enable row level security;
alter table public.phase_d_handoff_acceptance enable row level security;

-- ---- 9. positive controls, executed on this deployment --------------------------------------------
-- Zero cannot tell a dead guard from an idle system. Each control below makes the guard fire.

do $ctl$
declare
  v record; v_n int; v_h text; v_key text;
begin
  -- the denominator, asserted rather than described
  select count(*) into v_n from public.phase_d_handoff_contract;
  if v_n <> 159 then
    raise exception 'D9: % handoff contracts derived; the founder-approved effective denominator is 159 (PBCR-001)', v_n;
  end if;

  select handoff_id, distinguishing_key into v_h, v_key
    from public.phase_d_handoff_contract order by handoff_id limit 1;

  -- A packet carrying ONLY the kernel's five generic keys must now be REFUSED. Before this file it
  -- was accepted for all 159 handoffs, and that is the defect being closed.
  select * into v from public.fn_phase_d_handoff_packet_valid(v_h, jsonb_build_object(
    'business_object_id','x','object_version',1,'output','x','evidence_refs','x','requested_action','x'));
  if v.valid then
    raise exception 'D9 positive control FAILED: handoff % accepted a packet with none of its own declared items', v_h;
  end if;
  if not (v.missing @> array[v_key]) then
    raise exception 'D9 positive control FAILED: handoff % did not name its own missing item % (missing was %)',
      v_h, v_key, v.missing;
  end if;

  -- A packet carrying BOTH sets must pass. A check that refuses everything is not stricter, it is
  -- broken, and only a positive control can tell the two apart.
  select * into v from public.fn_phase_d_handoff_packet_valid(v_h,
    (select jsonb_object_agg(k, 'evidence') from unnest(
        (select packet_keys || kernel_packet_keys from public.phase_d_handoff_contract
          where handoff_id = v_h)) k));
  if not v.valid then
    raise exception 'D9 positive control FAILED: handoff % refuses a complete packet (missing %)',
      v_h, v.missing;
  end if;

  -- An empty packet must be refused, and an unknown handoff must fail closed rather than pass.
  select * into v from public.fn_phase_d_handoff_packet_valid(v_h, '{}'::jsonb);
  if v.valid then
    raise exception 'D9 positive control FAILED: an empty packet was accepted for %', v_h;
  end if;
  select * into v from public.fn_phase_d_handoff_packet_valid('H-DOES-NOT-EXIST',
    jsonb_build_object('business_object_id','x'));
  if v.valid then
    raise exception 'D9 positive control FAILED: an unknown handoff id was accepted';
  end if;

  raise notice 'D9 positive controls: 159 contracts, strict packet refuses generic-only, accepts complete, fails closed on unknown.';
end $ctl$;

commit;

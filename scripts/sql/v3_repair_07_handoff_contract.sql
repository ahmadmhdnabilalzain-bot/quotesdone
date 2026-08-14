-- V3 REMEDIATION — STAGE 7: THE CROSS-DEPARTMENT HANDOFF CONTRACT
--
-- The certification recorded CROSS_DEPARTMENT_ERROR on 1,056 questions. The three weakest specific
-- behaviours were "require proof the downstream step actually happened" (CMP-HO-05, 26.39%),
-- "handoff acceptance" (52%) and "define what closed means before opening the action"
-- (CMP-QA-02, 7.29%). Two neighbouring failures come from the same hole: CMP-HO-06 "guard against
-- replay and duplicate state" (9.38%).
--
-- WHAT ALREADY EXISTS, MEASURED ON STAGING 14 AUG 2026 BEFORE THIS FILE:
--   agent_actions kind='handoff'   11 rows, oldest 8 days. The transport and the inbox.
--   fn_agent_handoff_inbox(agent)  three oldest open handoffs, as text, for the receiving employee.
--   fn_handoff_answer(id,agent,a)  the receiver writes an answer; the asker gets an agent_memory row.
--   fn_role_handoff(from,to,...)   role-to-role ownership transfer, recorded in review_chain.
-- What NONE of them carries: a receiving department, a deadline, acceptance criteria, closure
-- criteria, an escalation condition, or an accountable owner that survives the transfer. The detail
-- objects of those 11 rows come in three shapes and NOT ONE of them holds a single one of those
-- fields: 7 are {from, from_name, requested_at}, 3 add {answer, answered_at}, 1 is a worked-row
-- shape. So there is nothing for a receiver to accept AGAINST and nothing to close AGAINST, and
-- "answered" is the only terminal state that exists — which proves nothing downstream.
--
-- THIS FILE EXTENDS THAT PATH, IT DOES NOT REPLACE IT. The contract hangs off the agent_actions row
-- by action_id, so fn_agent_handoff_inbox keeps working unchanged and the tool registry entry
-- 'handoff_inbox' keeps pointing at the same routine. What is added is the state the inbox never
-- had: acceptance, rejection with a reason, correction and return, and a closure that cannot be
-- recorded without proof for every closure criterion the sender declared BEFORE the work started.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE CONTRACT
-- ---------------------------------------------------------------------------------------------
-- One row per handoff, 1:1 with the agent_actions row that carries it to the receiver's inbox.
create table if not exists public.handoff_contract (
  id                    bigserial primary key,
  action_id             bigint not null unique
                          references public.agent_actions(id) on delete cascade,
  -- REPLAY GUARD (CMP-HO-06, 9.38%). Two identical handoffs cannot be live at once; the second
  -- call gets the first one's id back. The 82-row escalation storm this repo already documented
  -- was the same question re-asked with a louder title because nobody answered the first.
  idempotency_key       text not null,

  from_dept             text not null references public.org_departments(dept_key),
  -- NOT NULL is half of it; a00_handoff_contract_guard is the other half. See section 2.
  accountable_owner     text not null references public.org_agents(agent_key),
  to_dept               text not null references public.org_departments(dept_key),
  to_role               text not null check (btrim(to_role) <> ''),

  purpose               text not null check (length(btrim(purpose)) >= 10),
  -- Evidence handed over WITH the request. May legitimately be empty at open time — that is what
  -- makes a handoff rejectable on arrival rather than un-openable.
  evidence              jsonb not null default '[]'::jsonb
                          check (jsonb_typeof(evidence) = 'array'),
  requested_action      text not null check (length(btrim(requested_action)) >= 10),
  deadline              timestamptz not null,
  acceptance_criteria   text[] not null default '{}',
  -- CMP-QA-02, 7.29%: what "closed" means is declared BEFORE the work is handed over, never after.
  -- This is the one criteria array with a floor, because closure with no definition is the defect.
  closure_criteria      text[] not null check (cardinality(closure_criteria) >= 1),
  escalation_conditions text not null check (btrim(escalation_conditions) <> ''),

  status                text not null default 'open'
                          check (status in ('open','accepted','rejected','returned','closed')),
  -- What the ORIGINATING side is told came back. Null while the receiver has not answered yet.
  return_status         text
                          check (return_status in ('accepted','rejected','rejected_incomplete',
                                                   'returned_for_correction','closed')),
  return_reason         text,
  accepted_by           text references public.org_agents(agent_key),
  accepted_at           timestamptz,
  closed_by             text references public.org_agents(agent_key),
  closed_at             timestamptz,
  -- CMP-HO-05, 26.39%: proof the downstream step happened. [{"criterion": ..., "evidence": ...}].
  -- The guard refuses a close where any closure criterion has no non-empty evidence string.
  closure_evidence      jsonb,
  returns_count         integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.handoff_contract is
  'V3 remediation: the terms of one cross-department handoff. Hangs off agent_actions(id) so the existing inbox and answer path keep working; adds the acceptance, correction and proven-closure states they never had.';
comment on column public.handoff_contract.accountable_owner is
  'Never null, never blank, always an agent of from_dept. Changing it is a reassignment and must name another active agent - a handoff cannot be left with nobody accountable.';
comment on column public.handoff_contract.closure_evidence is
  'Array of {criterion, evidence}. A close is refused unless every closure_criteria entry has a non-empty evidence string here.';

create unique index if not exists handoff_contract_live_idem_idx
  on public.handoff_contract (idempotency_key) where status in ('open','accepted','returned');
create index if not exists handoff_contract_to_idx
  on public.handoff_contract (to_dept, status, deadline);
create index if not exists handoff_contract_owner_idx
  on public.handoff_contract (accountable_owner, status);

alter table public.handoff_contract enable row level security;

-- ---------------------------------------------------------------------------------------------
-- 2. THE GUARD — accountability and proof, enforced at the table, not in a caller
-- ---------------------------------------------------------------------------------------------
-- Named a00_ because BEFORE triggers fire in name order and this one must run before anything
-- later decides the row is acceptable. Everything here is reachable by a direct UPDATE, which is
-- exactly why it is not left to the functions in sections 3-6.
create or replace function public.fn_handoff_contract_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_check_owner boolean := false;
  v_owner       record;
  v_missing     text;
begin
  new.updated_at := now();

  -- (a) THE OWNER CANNOT BE LOST. NOT NULL stops the null; this stops the blank, the stranger,
  --     the deactivated replacement, and the owner who does not belong to the sending department.
  if coalesce(btrim(new.accountable_owner), '') = '' then
    raise exception 'handoff %: accountable_owner cannot be blank', coalesce(new.id, 0);
  end if;
  if tg_op = 'INSERT' then
    v_check_owner := true;
  elsif new.accountable_owner is distinct from old.accountable_owner then
    v_check_owner := true;
  end if;
  if v_check_owner then
    select agent_key, department, active into v_owner
      from org_agents where agent_key = new.accountable_owner;
    if not found then
      raise exception 'handoff %: accountable_owner % is not on the roster',
        coalesce(new.id, 0), new.accountable_owner;
    end if;
    if not v_owner.active then
      raise exception 'handoff %: accountable_owner % is not an active employee',
        coalesce(new.id, 0), new.accountable_owner;
    end if;
    if v_owner.department is distinct from new.from_dept then
      raise exception 'handoff %: accountable_owner % belongs to %, not the originating department %',
        coalesce(new.id, 0), new.accountable_owner, coalesce(v_owner.department, '(none)'), new.from_dept;
    end if;
  end if;

  -- (b) THE LIFECYCLE. open -> accepted|rejected; accepted -> returned|closed;
  --     rejected|returned -> open (the sender corrected it). closed is terminal.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if old.status = 'closed' then
      raise exception 'handoff %: closed is terminal, cannot move to %', new.id, new.status;
    end if;
    if not ((old.status = 'open'     and new.status in ('accepted','rejected'))
         or (old.status = 'accepted' and new.status in ('returned','closed'))
         or (old.status in ('rejected','returned') and new.status = 'open')) then
      raise exception 'handoff %: illegal transition % -> %', new.id, old.status, new.status;
    end if;
  end if;

  -- (c) CLOSURE NEEDS PROOF, PER CRITERION. This is CMP-HO-05 made unavoidable: a closure with a
  --     criterion nobody evidenced is refused, and the message names which criterion.
  if new.status = 'closed' then
    if new.closed_by is null or new.closed_at is null then
      raise exception 'handoff %: a closure must record who closed it and when', new.id;
    end if;
    select string_agg(c, '; ') into v_missing
      from unnest(new.closure_criteria) c
     where not exists (
       select 1 from jsonb_array_elements(coalesce(new.closure_evidence, '[]'::jsonb)) e
        where btrim(coalesce(e->>'criterion', '')) = btrim(c)
          and coalesce(btrim(e->>'evidence'), '') <> '');
    if v_missing is not null then
      raise exception 'handoff %: cannot close, no recorded proof for closure criteria: %',
        new.id, v_missing;
    end if;
  end if;

  return new;
end $$;
revoke all on function public.fn_handoff_contract_guard() from public;

create or replace trigger a00_handoff_contract_guard
  before insert or update on public.handoff_contract
  for each row execute function public.fn_handoff_contract_guard();

-- ---------------------------------------------------------------------------------------------
-- 3. OPENING A HANDOFF
-- ---------------------------------------------------------------------------------------------
-- Small shared parser: a jsonb array of strings -> text[], blanks dropped.
create or replace function public.fn_handoff_criteria(p jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(btrim(x)) filter (where btrim(x) <> ''), '{}'::text[])
    from jsonb_array_elements_text(
           case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) x;
$$;
revoke all on function public.fn_handoff_criteria(jsonb) from public;
grant execute on function public.fn_handoff_criteria(jsonb) to service_role;

-- One place that decides whether a colleague is a real, active employee before writing to their
-- memory. Used by every path in this file that has to tell the sender something came back.
create or replace function public.fn_handoff_notify(p_agent_key text, p_content text, p_source text)
returns boolean language plpgsql volatile security definer set search_path = public as $$
begin
  if coalesce(btrim(p_agent_key), '') = ''
     or not exists (select 1 from org_agents where agent_key = p_agent_key) then
    return false;
  end if;
  insert into agent_memory (agent_key, kind, content, source, importance)
  values (p_agent_key, 'learned', left(p_content, 2000), p_source, 4);
  return true;
end $$;
revoke all on function public.fn_handoff_notify(text, text, text) from public;
grant execute on function public.fn_handoff_notify(text, text, text) to service_role;

-- Returns {ok:false, missing:[...]} rather than raising, so a caller that got it wrong can fix the
-- request instead of losing its transaction. Anything absent here is absent from the CONTRACT, and
-- the contract is what the receiver later accepts or rejects against.
create or replace function public.fn_handoff_open(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  v_from     text := btrim(coalesce(p->>'from_dept', ''));
  v_owner    text := btrim(coalesce(p->>'accountable_owner', ''));
  v_to       text := btrim(coalesce(p->>'to_dept', ''));
  v_role     text := btrim(coalesce(p->>'to_role', ''));
  v_purpose  text := btrim(coalesce(p->>'purpose', ''));
  v_act      text := btrim(coalesce(p->>'requested_action', ''));
  v_escal    text := btrim(coalesce(p->>'escalation_conditions', ''));
  v_evidence jsonb := case when jsonb_typeof(p->'evidence') = 'array' then p->'evidence' else '[]'::jsonb end;
  v_accept   text[] := public.fn_handoff_criteria(p->'acceptance_criteria');
  v_closure  text[] := public.fn_handoff_criteria(p->'closure_criteria');
  v_deadline timestamptz;
  v_missing  text[] := '{}';
  v_gaps     text[] := '{}';
  v_idem     text;
  v_recv     text;
  v_ownrec   record;
  v_action   bigint;
  v_id       bigint;
  v_dupe     bigint;
begin
  begin v_deadline := (p->>'deadline')::timestamptz; exception when others then v_deadline := null; end;

  if v_from    = '' then v_missing := v_missing || 'from_dept'::text;             end if;
  if v_owner   = '' then v_missing := v_missing || 'accountable_owner'::text;     end if;
  if v_to      = '' then v_missing := v_missing || 'to_dept'::text;               end if;
  if v_role    = '' then v_missing := v_missing || 'to_role'::text;               end if;
  if length(v_purpose) < 10 then v_missing := v_missing || 'purpose'::text;       end if;
  if length(v_act) < 10 then v_missing := v_missing || 'requested_action'::text;  end if;
  if v_escal   = '' then v_missing := v_missing || 'escalation_conditions'::text; end if;
  if v_deadline is null then v_missing := v_missing || 'deadline'::text;          end if;
  if cardinality(v_closure) = 0 then v_missing := v_missing || 'closure_criteria'::text; end if;
  if array_length(v_missing, 1) is not null then
    return jsonb_build_object('ok', false, 'reason', 'the handoff contract is not complete enough to open',
                              'missing', to_jsonb(v_missing));
  end if;
  if v_deadline <= now() then
    return jsonb_build_object('ok', false, 'reason', 'deadline is already in the past', 'deadline', v_deadline);
  end if;

  if not exists (select 1 from org_departments where dept_key = v_from) then
    return jsonb_build_object('ok', false, 'reason', 'unknown originating department', 'from_dept', v_from);
  end if;
  if not exists (select 1 from org_departments where dept_key = v_to) then
    return jsonb_build_object('ok', false, 'reason', 'unknown receiving department', 'to_dept', v_to);
  end if;
  select agent_key, department, active into v_ownrec from org_agents where agent_key = v_owner;
  if not found or not v_ownrec.active then
    return jsonb_build_object('ok', false, 'reason', 'accountable owner is not an active employee',
                              'accountable_owner', v_owner);
  end if;
  if v_ownrec.department is distinct from v_from then
    return jsonb_build_object('ok', false, 'reason', 'accountable owner does not belong to the originating department',
                              'accountable_owner', v_owner, 'owner_department', v_ownrec.department, 'from_dept', v_from);
  end if;

  -- REPLAY / DUPLICATE STATE. Same sender, same receiver, same ask = the same handoff.
  v_idem := coalesce(nullif(btrim(p->>'idempotency_key'), ''),
                     md5(v_from||'>'||v_to||'|'||lower(v_role)||'|'||lower(v_purpose)||'|'||lower(v_act)));
  select id into v_dupe from handoff_contract
   where idempotency_key = v_idem and status in ('open','accepted','returned') limit 1;
  if v_dupe is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'id', v_dupe,
      'note', 'an identical handoff is already live; returning it rather than opening a second');
  end if;

  -- WHO ACTUALLY RECEIVES IT. The named role first, then a role that contains the name, then the
  -- department lead. A handoff addressed to a department with nobody in it is refused, not queued.
  select a.agent_key into v_recv
    from org_agents a
    left join org_departments d on d.dept_key = a.department
   where a.department = v_to and a.active
   order by (lower(a.role) = lower(v_role)) desc,
            (position(lower(v_role) in lower(coalesce(a.role,''))) > 0) desc,
            coalesce(a.available, true) desc,
            (a.agent_key = d.lead_agent) desc,
            a.agent_key
   limit 1;
  if v_recv is null then
    return jsonb_build_object('ok', false, 'reason', 'receiving department has no active employee to accept it',
                              'to_dept', v_to);
  end if;

  -- The transport row: this is what fn_agent_handoff_inbox already reads. Unchanged shape.
  insert into agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table)
  values (v_recv, 'handoff', 'needs_review', 'medium',
          'Handoff — '||left(v_purpose, 160), left(v_act, 500),
          jsonb_build_object(
            'from', v_owner, 'from_name', v_owner, 'from_dept', v_from,
            'to_dept', v_to, 'to_role', v_role, 'deadline', v_deadline,
            'acceptance_criteria', to_jsonb(v_accept), 'closure_criteria', to_jsonb(v_closure),
            'escalation_conditions', v_escal, 'requested_at', now(), 'contract', true),
          'handoff_contract')
  returning id into v_action;

  insert into handoff_contract (action_id, idempotency_key, from_dept, accountable_owner, to_dept,
                                to_role, purpose, evidence, requested_action, deadline,
                                acceptance_criteria, closure_criteria, escalation_conditions)
  values (v_action, v_idem, v_from, v_owner, v_to, v_role, v_purpose, v_evidence, v_act, v_deadline,
          v_accept, v_closure, v_escal)
  returning id into v_id;

  update agent_actions set target_id = v_id::text where id = v_action;

  if jsonb_array_length(v_evidence) = 0 then v_gaps := v_gaps || 'evidence'::text; end if;
  if cardinality(v_accept) = 0 then v_gaps := v_gaps || 'acceptance_criteria'::text; end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'action_id', v_action,
    'receiving_agent', v_recv, 'idempotency_key', v_idem,
    'complete', array_length(v_gaps, 1) is null,
    'rejectable_on_arrival', array_length(v_gaps, 1) is not null,
    'missing_for_acceptance', to_jsonb(v_gaps));
end $$;
revoke all on function public.fn_handoff_open(jsonb) from public;
grant execute on function public.fn_handoff_open(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. THE RECEIVING SIDE — accept, reject, or hand it back
-- ---------------------------------------------------------------------------------------------
-- One entry point, because all three answers share the same authorisation: only an active employee
-- of the RECEIVING department may answer, and every answer that is not an acceptance must carry a
-- reason. Acceptance of an incomplete handoff is refused - it must be rejected or corrected first.
create or replace function public.fn_handoff_respond(
  p_id bigint, p_agent_key text, p_decision text, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c        handoff_contract%rowtype;
  v_dec    text := lower(btrim(coalesce(p_decision, '')));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_gaps   text[] := '{}';
begin
  if v_dec not in ('accept','reject','return') then
    return jsonb_build_object('ok', false, 'reason', 'decision must be accept, reject or return');
  end if;
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.to_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the receiving department may answer',
                              'to_dept', c.to_dept);
  end if;

  if jsonb_array_length(c.evidence) = 0 then v_gaps := v_gaps || 'evidence'::text; end if;
  if cardinality(c.acceptance_criteria) = 0 then v_gaps := v_gaps || 'acceptance_criteria'::text; end if;

  if v_dec = 'accept' then
    if c.status <> 'open' then
      return jsonb_build_object('ok', false, 'reason', 'only an open handoff can be accepted', 'status', c.status);
    end if;
    -- REJECTABLE ON ARRIVAL: an incomplete handoff cannot be silently taken on.
    if array_length(v_gaps, 1) is not null then
      return jsonb_build_object('ok', false, 'reason', 'handoff is incomplete and cannot be accepted',
        'missing', to_jsonb(v_gaps), 'next', 'reject it with a reason, or ask the sender to amend it');
    end if;
    update handoff_contract
       set status = 'accepted', return_status = 'accepted',
           accepted_by = p_agent_key, accepted_at = now(), return_reason = nullif(v_reason, '')
     where id = p_id;
    perform public.fn_handoff_notify(c.accountable_owner,
      'Handoff #'||p_id||' ("'||c.purpose||'") was ACCEPTED by '||p_agent_key||' ('||c.to_dept||'). '
      ||'Due '||to_char(c.deadline, 'YYYY-MM-DD HH24:MI')||'. Closure criteria: '
      ||array_to_string(c.closure_criteria, ' | '),
      'handoff_contract:'||p_id);
    return jsonb_build_object('ok', true, 'id', p_id, 'status', 'accepted',
      'accepted_by', p_agent_key, 'deadline', c.deadline,
      'acceptance_criteria', to_jsonb(c.acceptance_criteria),
      'closure_criteria', to_jsonb(c.closure_criteria));
  end if;

  if v_reason = '' then
    return jsonb_build_object('ok', false, 'reason', 'a '||v_dec||' must state why');
  end if;

  if v_dec = 'reject' then
    if c.status <> 'open' then
      return jsonb_build_object('ok', false, 'reason', 'only an open handoff can be rejected', 'status', c.status);
    end if;
    update handoff_contract
       set status = 'rejected',
           return_status = case when array_length(v_gaps, 1) is not null
                                then 'rejected_incomplete' else 'rejected' end,
           return_reason = v_reason
     where id = p_id;
    -- The transport row leaves the receiver's inbox; the sender is told, in their own memory.
    update agent_actions
       set status = 'done', decided_at = now(), decided_by = p_agent_key,
           detail = coalesce(detail, '{}'::jsonb)
                    || jsonb_build_object('outcome', 'rejected', 'reason', left(v_reason, 1000),
                                          'missing', to_jsonb(v_gaps), 'rejected_at', now())
     where id = c.action_id;
    perform public.fn_handoff_notify(c.accountable_owner,
      'Handoff #'||p_id||' ("'||c.purpose||'") was REJECTED by '||p_agent_key||' ('||c.to_dept||'): '
      ||v_reason||case when array_length(v_gaps, 1) is not null
                       then '. Missing: '||array_to_string(v_gaps, ', ')||'. Amend and resubmit with fn_handoff_amend.'
                       else '' end,
      'handoff_contract:'||p_id);
    return jsonb_build_object('ok', true, 'id', p_id, 'status', 'rejected',
      'return_status', case when array_length(v_gaps, 1) is not null then 'rejected_incomplete' else 'rejected' end,
      'missing', to_jsonb(v_gaps), 'sender_notified', c.accountable_owner);
  end if;

  -- return: the receiver took it on, then found it cannot be finished as handed over.
  if c.status <> 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'only an accepted handoff can be returned for correction',
                              'status', c.status);
  end if;
  update handoff_contract
     set status = 'returned', return_status = 'returned_for_correction',
         return_reason = v_reason, returns_count = returns_count + 1
   where id = p_id;
  perform public.fn_handoff_notify(c.accountable_owner,
    'Handoff #'||p_id||' ("'||c.purpose||'") was RETURNED FOR CORRECTION by '||p_agent_key||': '||v_reason
    ||' Correct it with fn_handoff_amend; it goes back to '||c.to_dept||' as open.',
    'handoff_contract:'||p_id);
  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'returned',
    'return_status', 'returned_for_correction', 'returns_count', c.returns_count + 1,
    'sender_notified', c.accountable_owner);
end $$;
revoke all on function public.fn_handoff_respond(bigint, text, text, text) from public;
grant execute on function public.fn_handoff_respond(bigint, text, text, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. THE SENDING SIDE — correct it and put it back
-- ---------------------------------------------------------------------------------------------
-- The only way a rejected or returned handoff becomes open again. The caller must be the
-- accountable owner or another active employee of the originating department; if it is someone
-- else in that department, ownership MOVES to them explicitly and is recorded - it is never vacant.
create or replace function public.fn_handoff_amend(p_id bigint, p_agent_key text, p_patch jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c          handoff_contract%rowtype;
  v_evidence jsonb;
  v_accept   text[];
  v_deadline timestamptz;
  v_owner    text;
  v_gaps     text[] := '{}';
begin
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if c.status = 'closed' then
    return jsonb_build_object('ok', false, 'reason', 'a closed handoff cannot be amended');
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.from_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the originating department may amend',
                              'from_dept', c.from_dept);
  end if;

  v_evidence := case when jsonb_typeof(p_patch->'evidence') = 'array' then p_patch->'evidence' else c.evidence end;
  v_accept   := case when jsonb_typeof(p_patch->'acceptance_criteria') = 'array'
                     then public.fn_handoff_criteria(p_patch->'acceptance_criteria') else c.acceptance_criteria end;
  v_owner    := coalesce(nullif(btrim(p_patch->>'accountable_owner'), ''), p_agent_key);
  begin v_deadline := coalesce((p_patch->>'deadline')::timestamptz, c.deadline);
  exception when others then v_deadline := c.deadline; end;

  update handoff_contract
     set evidence = v_evidence,
         acceptance_criteria = v_accept,
         deadline = v_deadline,
         accountable_owner = v_owner,          -- guard refuses a blank, a stranger or an ex-employee
         status = case when c.status in ('rejected','returned') then 'open' else c.status end,
         return_status = case when c.status in ('rejected','returned') then null else c.return_status end,
         return_reason = case when c.status in ('rejected','returned') then null else c.return_reason end
   where id = p_id;

  -- Back into the receiver's inbox if the rejection had taken it out.
  update agent_actions
     set status = 'needs_review', decided_at = null, decided_by = null,
         detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object('amended_at', now(), 'amended_by', p_agent_key)
   where id = c.action_id and c.status in ('rejected','returned');

  if jsonb_array_length(v_evidence) = 0 then v_gaps := v_gaps || 'evidence'::text; end if;
  if cardinality(v_accept) = 0 then v_gaps := v_gaps || 'acceptance_criteria'::text; end if;

  return jsonb_build_object('ok', true, 'id', p_id,
    'status', case when c.status in ('rejected','returned') then 'open' else c.status end,
    'accountable_owner', v_owner, 'owner_changed', v_owner is distinct from c.accountable_owner,
    'complete', array_length(v_gaps, 1) is null, 'missing_for_acceptance', to_jsonb(v_gaps));
end $$;
revoke all on function public.fn_handoff_amend(bigint, text, jsonb) from public;
grant execute on function public.fn_handoff_amend(bigint, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 6. CLOSURE, WITH PROOF
-- ---------------------------------------------------------------------------------------------
-- p_closure_evidence is [{"criterion": "<one of closure_criteria>", "evidence": "<what proves it>"}].
-- The gaps are named back to the caller here; the trigger in section 2 is the backstop that makes
-- the same rule true for a direct UPDATE.
create or replace function public.fn_handoff_close(p_id bigint, p_agent_key text, p_closure_evidence jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c         handoff_contract%rowtype;
  v_ev      jsonb := case when jsonb_typeof(p_closure_evidence) = 'array' then p_closure_evidence else '[]'::jsonb end;
  v_missing text[];
begin
  select * into c from handoff_contract where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no handoff contract with that id');
  end if;
  if c.status <> 'accepted' then
    return jsonb_build_object('ok', false, 'reason', 'only an accepted handoff can be closed', 'status', c.status);
  end if;
  if not exists (select 1 from org_agents
                  where agent_key = p_agent_key and active and department = c.to_dept) then
    return jsonb_build_object('ok', false, 'reason', 'only an active employee of the receiving department may close it',
                              'to_dept', c.to_dept);
  end if;

  select coalesce(array_agg(x), '{}'::text[]) into v_missing
    from unnest(c.closure_criteria) x
   where not exists (
     select 1 from jsonb_array_elements(v_ev) e
      where btrim(coalesce(e->>'criterion', '')) = btrim(x)
        and coalesce(btrim(e->>'evidence'), '') <> '');
  if array_length(v_missing, 1) is not null then
    return jsonb_build_object('ok', false, 'reason', 'closure criteria without recorded proof',
      'unproven', to_jsonb(v_missing), 'declared', to_jsonb(c.closure_criteria));
  end if;

  update handoff_contract
     set status = 'closed', return_status = 'closed', closure_evidence = v_ev,
         closed_by = p_agent_key, closed_at = now()
   where id = p_id;

  update agent_actions
     set status = 'done', decided_at = now(), decided_by = p_agent_key,
         detail = coalesce(detail, '{}'::jsonb)
                  || jsonb_build_object('outcome', 'closed', 'closure_evidence', v_ev, 'closed_at', now())
   where id = c.action_id;

  perform public.fn_handoff_notify(c.accountable_owner,
    'Handoff #'||p_id||' ("'||c.purpose||'") was CLOSED by '||p_agent_key||' ('||c.to_dept||'). '
    ||'Proof recorded for '||cardinality(c.closure_criteria)||' closure criteria: '||v_ev::text,
    'handoff_contract:'||p_id);

  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'closed', 'closed_by', p_agent_key,
    'criteria_proven', cardinality(c.closure_criteria), 'closure_evidence', v_ev);
end $$;
revoke all on function public.fn_handoff_close(bigint, text, jsonb) from public;
grant execute on function public.fn_handoff_close(bigint, text, jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 7. WHAT MANAGEMENT READS
-- ---------------------------------------------------------------------------------------------
-- A handoff nobody accepted, one accepted and never closed, one handed back and never corrected,
-- one whose owner has left, and one whose inbox row was cleared while the contract stayed open -
-- that last shape is the legacy fn_handoff_answer path being used on a contracted handoff.
create or replace view public.v_handoff_stalled as
  select * from (
    select c.id, c.action_id, c.from_dept, c.accountable_owner, c.to_dept, c.to_role,
           c.purpose, c.status, c.deadline, c.accepted_by, c.accepted_at, c.returns_count,
           o.active as owner_active, a.status as transport_status,
           case
             when not o.active                                            then 'owner_inactive'
             when c.status = 'open'     and now() > c.deadline            then 'overdue_never_accepted'
             when c.status = 'accepted' and now() > c.deadline            then 'overdue_accepted_not_closed'
             when c.status = 'accepted' and c.accepted_at < now() - interval '3 days'
                                                                          then 'accepted_never_closed'
             when c.status = 'returned' and c.updated_at < now() - interval '2 days'
                                                                          then 'returned_not_corrected'
             when c.status in ('open','accepted')
                  and a.status not in ('pending','needs_review')          then 'transport_closed_contract_open'
           end as stall_reason,
           case when now() > c.deadline
                then round(extract(epoch from now() - c.deadline) / 86400.0, 2)
                else 0 end as days_past_deadline
      from handoff_contract c
      join org_agents o     on o.agent_key = c.accountable_owner
      join agent_actions a  on a.id = c.action_id
     where c.status in ('open','accepted','returned')
  ) s
  where stall_reason is not null;
comment on view public.v_handoff_stalled is
  'Cross-department work that has stopped moving, with the reason. Empty is the correct state; a row here always names one accountable owner.';

create or replace function public.fn_handoff_stalled(p_dept text default null, p_limit integer default 50)
returns setof public.v_handoff_stalled
language sql stable security definer set search_path = public as $$
  select * from public.v_handoff_stalled s
   where p_dept is null or s.from_dept = p_dept or s.to_dept = p_dept
   order by s.days_past_deadline desc, s.deadline
   limit greatest(1, coalesce(p_limit, 50));
$$;
revoke all on function public.fn_handoff_stalled(text, integer) from public;
grant execute on function public.fn_handoff_stalled(text, integer) to service_role;

-- The bypass count. Every handoff that still travels with no contract - the 11 rows that exist
-- today, and any new one written straight into agent_actions instead of through fn_handoff_open.
create or replace view public.v_handoff_without_contract as
  select a.id as action_id, a.agent as receiving_agent, a.status, a.title, a.created_at,
         round(extract(epoch from now() - a.created_at) / 86400.0, 1) as age_days
    from agent_actions a
   where a.kind = 'handoff'
     and not exists (select 1 from handoff_contract c where c.action_id = a.id);
comment on view public.v_handoff_without_contract is
  'Handoffs with no acceptance criteria, no closure criteria and no accountable owner, because they were written straight into agent_actions. This count is the remaining size of the defect.';

-- ---------------------------------------------------------------------------------------------
-- 8. THE ENTRY POINT
-- ---------------------------------------------------------------------------------------------
-- A finished routine no agent can reach is the failure mode this repo keeps rediscovering, so the
-- management read surface is registered as a tool in the same change that creates it. Guarded on
-- the registry existing, because this file must still apply to a project that has not had stage 2.
-- The three WRITE routines are deliberately not registered here: stage 2's rule is that write tools
-- route through org_action_executor, and that wiring is not this file's to invent.
do $reg$
begin
  if to_regclass('public.agent_tool') is not null then
    insert into public.agent_tool
      (tool_id, purpose, kind, impl_kind, impl_target, authorised_roles, authorised_departments,
       input_schema, timeout_seconds, failure_behaviour, requires_current_data, note)
    values
      ('handoff_stalled',
       'Cross-department handoffs that have stopped moving: past deadline, accepted and never closed, handed back and never corrected, or owned by someone who has left. Each row names one accountable owner.',
       'read','rpc','fn_handoff_stalled','{*}','{*}',
       '{"type":"object","properties":{"dept":{"type":"string"},"limit":{"type":"integer","minimum":1,"maximum":200}},"additionalProperties":false}'::jsonb,
       15,'fail_closed',true,
       'Empty is the correct answer most days; an empty result here is ok_empty, never a failure.')
    on conflict (tool_id) do update set
      purpose = excluded.purpose, impl_target = excluded.impl_target,
      input_schema = excluded.input_schema, note = excluded.note;
  end if;
end $reg$;

commit;

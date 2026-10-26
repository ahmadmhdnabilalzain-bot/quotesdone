-- HE GIVES AN INSTRUCTION AND NOTHING ASKS HIM TO CONFIRM IT AGAIN
--
-- Operating constitution 1.2, Full Autonomy: the founder approves nothing, and neither agent sends
-- him unsolicited operational alerts or approval requests. But he still COMMANDS, and the update is
-- explicit about the shape a command must have:
--
--   "Founder instructions are authenticated commands, not approvals. Give each a durable command
--    identifier, an explicit scope, a sequence position and an idempotency key. Execute an
--    authenticated command; do not send it back to him for reconfirmation."
--
--   Step 5: "Audit and migrate any case still awaiting a founder decision."
--
-- THIS UPGRADES THE LIVE TABLE RATHER THAN STANDING A NEW ONE BESIDE IT. public.founder_command
-- already exists with 27 rows, 11 inbound foreign keys, 33 routines and a state machine guarded by
-- z20_founder_command_state_guard. A second table called something like founder_command_v2 would
-- have been the succession failure this estate has already paid for: the new record unreachable
-- behind the row it was meant to replace, and two answers to "what did he tell us".
--
-- WHAT WAS ALREADY THERE, measured rather than assumed:
--   durable id      -- founder_command.command_id, primary key. Present.
--   idempotency     -- founder_command_message.client_idempotency_key, non-null on all 27 rows.
--   ownership       -- founder_command_owner_ck already pins every command to the CEO, which is the
--                      7 September structure. Nothing to change.
--
-- WHAT WAS MISSING, and is added below:
--   AUTHENTICATED -- nothing checked that a command came from HIM. founder_identity was a text label
--     written by the caller, so 'management@quotesdone.com' authenticated a command by being typed.
--     Under full autonomy this matters more, not less: there is no human review standing between an
--     instruction and its execution, so the sender check is the only thing between the two.
--   SCOPE and SEQUENCE -- supersession existed (superseded_by) but was decided by ARRIVAL. WhatsApp
--     does not guarantee order. Two instructions on the same subject arriving reversed would let the
--     older one land last and silently reinstate something he had cancelled.
--
-- AND THE ROUTE THAT HAD TO GO. The state model contained interpreting -> clarification_required:
-- an authenticated instruction parked in a non-terminal state, waiting for him to explain himself.
-- That is an approval queue wearing a question mark. Removing the approval table does not remove the
-- habit while the transition into it still exists, so the transition is deleted here and the state
-- becomes unreachable. Refusing a command that names nothing determinate stays available -- refusal
-- is terminal and waits on nobody; clarification_required was neither.

-- ---------------------------------------------------------------------------------------------
-- 1. THE FOUR PROPERTIES, ON THE TABLE THAT ALREADY EXISTS
-- ---------------------------------------------------------------------------------------------
alter table public.founder_command
  add column if not exists authenticated   boolean,
  add column if not exists auth_basis      text,
  add column if not exists command_scope   text,
  add column if not exists command_seq     bigint;

-- Backfill the 27 historical rows honestly. They were accepted before any sender check existed, so
-- they are recorded as unauthenticated with the basis saying exactly that. Marking them true would
-- be writing a verification that never happened, which is the defect the whole column exists to fix.
update public.founder_command
   set authenticated = false,
       auth_basis = 'pre_v1_2_no_sender_check: this command was accepted before the founder''s sender was verified against the number on file. Recorded as unverified because it was.'
 where authenticated is null;

alter table public.founder_command
  alter column authenticated set not null,
  alter column authenticated set default false;

do $$ begin
  -- AN AUTHENTICATION IS A BASIS, NOT A BOOLEAN. "authenticated = true" with nothing behind it is
  -- the same defect as a verified flag with no method: a claim recorded as a fact.
  if not exists (select 1 from pg_constraint where conname = 'founder_command_auth_basis_ck') then
    alter table public.founder_command add constraint founder_command_auth_basis_ck
      check (not authenticated or coalesce(auth_basis, '') <> '');
  end if;
  -- SCOPE AND SEQUENCE TRAVEL TOGETHER. A sequence number means "later than" only within a scope; a
  -- bare sequence across unrelated instructions orders things that were never in a line.
  if not exists (select 1 from pg_constraint where conname = 'founder_command_scope_seq_ck') then
    alter table public.founder_command add constraint founder_command_scope_seq_ck
      check ((command_scope is null) = (command_seq is null));
  end if;
end $$;

-- ONE COMMAND PER SCOPE POSITION. A retried webhook that arrives with a fresh command_id but the
-- same scope and sequence is the same instruction, and the index says so rather than a reader.
create unique index if not exists founder_command_scope_seq_uk
  on public.founder_command (command_scope, command_seq)
  where command_scope is not null and state not in ('superseded','cancelled','refused','failed');

comment on column public.founder_command.authenticated is
  'Whether the sender was verified as the founder against the number on file, not whether a caller typed his name into founder_identity.';
comment on column public.founder_command.command_seq is
  'Position within command_scope. WhatsApp does not guarantee order, so supersession is decided by this rather than by arrival time.';

-- ---------------------------------------------------------------------------------------------
-- 2. IS THIS HIM? Read from configuration, never from the message.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_command_authenticate(p_channel text, p_sender_ref text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_his text;
begin
  select regexp_replace(coalesce(value,''), '[^0-9]', '', 'g') into v_his
    from public.app_secrets where key = 'founder_public_phone';

  if coalesce(v_his,'') = '' then
    -- A MISSING CONFIGURATION IS NOT A PASS. With no number on file, a comparison that "did not
    -- find a mismatch" would authenticate every sender alive. That is a guard that lets everything
    -- through because the thing it compares against is absent, and it refuses instead.
    return jsonb_build_object('authenticated', false, 'basis', 'none',
      'why', 'no founder number is configured, so no sender can be shown to be him. This refuses rather than assumes.');
  end if;

  if p_channel <> 'whatsapp' then
    return jsonb_build_object('authenticated', false, 'basis', 'none',
      'why', format('%L is not the founder command channel; WhatsApp is. A command arriving elsewhere is a message, and it is answered rather than executed.', p_channel));
  end if;

  if regexp_replace(coalesce(p_sender_ref,''), '[^0-9]', '', 'g') = v_his then
    return jsonb_build_object('authenticated', true, 'basis', 'registered_mobile_on_whatsapp',
      'why', 'the message came from the number on file for the founder, on his command channel.');
  end if;

  return jsonb_build_object('authenticated', false, 'basis', 'none',
    'why', 'this sender is not the founder. An imperative sentence from a member of the public is a message, not a command.');
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 3. RECEIVE AND ACT. One call, because a "received, awaiting confirmation" step is how the
--    approval queue grows back with a different column name.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_command_admit(
  p_message_id      bigint,
  p_channel         text,
  p_sender_ref      text,
  p_scope           text,
  p_seq             bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  a jsonb; v_prior record; v_existing record; v_id bigint; v_key text;
begin
  -- IDEMPOTENCY FIRST, before anything is judged or locked. A provider retry is the same
  -- instruction, and answering it from the first admission is not a shortcut -- re-running the
  -- judgement would produce a second command_id for one thing he said once.
  select client_idempotency_key into v_key
    from public.founder_command_message where message_id = p_message_id;
  if v_key is null then
    return jsonb_build_object('ok', false, 'reason',
      'the message carries no idempotency key, so a retry could not be told from a second instruction.');
  end if;

  select c.* into v_existing from public.founder_command c
    join public.founder_command_message m on m.message_id = c.message_id
   where m.client_idempotency_key = v_key
   order by c.command_id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'command_id', v_existing.command_id, 'state', v_existing.state,
      'duplicate', true,
      'note', 'the same instruction arriving twice. Answered from the first admission rather than admitted again.');
  end if;

  a := public.fn_founder_command_authenticate(p_channel, p_sender_ref);

  -- SEQUENCE, before admission. A command older than one already live on the same scope is stale,
  -- and admitting it would let it execute after the instruction that replaced it.
  if (a->>'authenticated') = 'true' and p_scope is not null and p_seq is not null then
    select * into v_prior from public.founder_command
     where command_scope = p_scope and command_seq is not null
       and state not in ('superseded','cancelled','refused','failed')
     order by command_seq desc limit 1;
    if found and v_prior.command_seq >= p_seq then
      insert into public.founder_command
        (message_id, command_owner_role_id, state, intent_id, outcome, authenticated, auth_basis, command_scope, command_seq, superseded_by)
      values (p_message_id, 'ceo', 'received', 'UNINTERPRETED', 'PENDING_INTERPRETATION', true, a->>'basis', p_scope, p_seq, null)
      returning command_id into v_id;
      update public.founder_command
         set state = 'superseded', superseded_by = v_prior.command_id where command_id = v_id;
      return jsonb_build_object('ok', true, 'command_id', v_id, 'state', 'superseded',
        'superseded_by', v_prior.command_id,
        'reason', format('a later instruction on %L (sequence %s) is already live. Running this one now would reinstate something he has since changed.', p_scope, v_prior.command_seq));
    end if;
  end if;

  insert into public.founder_command
    (message_id, command_owner_role_id, state, intent_id, outcome, authenticated, auth_basis, command_scope, command_seq)
  values (p_message_id, 'ceo', 'received', 'UNINTERPRETED', 'PENDING_INTERPRETATION',
          (a->>'authenticated') = 'true',
          case when (a->>'authenticated') = 'true' then a->>'basis' else null end,
          p_scope, p_seq)
  returning command_id into v_id;

  return jsonb_build_object('ok', true, 'command_id', v_id, 'state', 'received',
    'authenticated', (a->>'authenticated')::boolean, 'auth_basis', a->>'basis', 'why', a->>'why',
    'scope', p_scope, 'seq', p_seq,
    -- The sentence that replaces the old habit. Not "shall I?" -- there is no route that produces one.
    'note', case when (a->>'authenticated') = 'true'
      then 'Admitted on his authority. It is interpreted and acted on; nothing goes back to him for reconfirmation.'
      else 'Not from him. Answered as an ordinary message; it commands nothing.' end);
end $function$;

revoke execute on function public.fn_founder_command_authenticate(text,text) from public;
revoke execute on function public.fn_founder_command_authenticate(text,text) from anon;
revoke execute on function public.fn_founder_command_authenticate(text,text) from authenticated;
revoke execute on function public.fn_founder_command_admit(bigint,text,text,text,bigint) from public;
revoke execute on function public.fn_founder_command_admit(bigint,text,text,text,bigint) from anon;
revoke execute on function public.fn_founder_command_admit(bigint,text,text,text,bigint) from authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. THE RECONFIRMATION ROUTE IS DELETED, AND THE CASES WAITING ON HIM ARE CLEARED (step 5)
-- ---------------------------------------------------------------------------------------------
-- Removing the transition is what makes the rule real. Left in place, the next caller reaches
-- clarification_required and the approval queue is back with one row in it.
delete from public.phase_c_command_transition
 where from_state = 'interpreting' and to_state = 'clarification_required';

-- Command 81887 ("status", 6 September) sat in clarification_required: an instruction of his,
-- parked, waiting for him to explain himself. Under 1.2 that state is unreachable, so it is closed
-- rather than left in a state nothing can now leave. Cancelled and not answered, because answering a
-- two-day-old "status" with today's numbers would be replying to a question he has moved past.
update public.founder_command
   set state = 'cancelled'
 where state = 'clarification_required';

-- Six commands stood in accepted/tasks_created with ZERO rows in founder_command_task_link: the work
-- they created was deleted on 7 September on his instruction that no job may exist without an agent
-- that owns it. A command claiming in-flight work that does not exist is the same defect as a
-- discharge claim that never reaches its table, so they are closed against the fact.
update public.founder_command c
   set state = 'cancelled'
 where c.state in ('accepted','tasks_created')
   and not exists (select 1 from public.founder_command_task_link l where l.command_id = c.command_id);

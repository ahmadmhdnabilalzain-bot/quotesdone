-- THE CEO'S COMMAND MACHINE BECOMES THE CEO'S, AND STOPS BEING PHASE C'S.
--
-- Founder, 8 September 2026: "for the new CEO we will build proper tables and edge functions and
-- everything. we dont rely on the old structure", and "phases A to D are irrelevant".
--
-- WHY THIS FILE EXISTS BEFORE THE DELETION. Phase C cannot be dropped while the CEO seat runs on it.
-- `founder_command` — the channel the founder issues instructions through, 27 rows — carries:
--
--     founder_command_state_fkey        FOREIGN KEY (state) -> phase_c_command_state(state)
--     z20_founder_command_state_guard   BEFORE UPDATE -> fn_founder_command_state_guard(),
--                                       which validates every transition against
--                                       phase_c_command_transition
--
-- That was my shortcut when the command channel was rebuilt on 8 Sep: it borrowed a governance
-- programme's state model rather than owning one. The consequence is that a table nobody wants keeps
-- 13 rows alive and blocks the drop of everything around it. This is the repair, and it is a
-- re-homing rather than a rewrite: the states and transitions are copied EXACTLY as they stand, so
-- the seat behaves identically the moment this lands and the deletion becomes possible afterwards.
--
-- MEASURED FIRST: all 27 live commands are in terminal states (cancelled, refused). There is no
-- in-flight command whose transition could be invalidated mid-flight by swapping the model beneath
-- it. Had there been, this file would have had to run differently.
--
-- WHAT IS NOT COPIED, and this matters. phase_c_command_state has 13 states and
-- phase_c_command_transition 24 edges, and `interpreting -> clarification_required` is absent from
-- both — it was deleted on 8 Sep under the founder's ruling that he is never asked to confirm an
-- instruction twice. The absence is carried forward deliberately, not repaired.
--
-- STILL BROKEN AFTER THIS, and named here so it is not mistaken for fixed: phase_c_command_rule and
-- phase_c_command_intent are EMPTY, so every submitted command classifies ambiguous, and
-- phase_c_task_state is empty, so no task row can be inserted at all. The CEO's classification and
-- task model are the next file, not this one. This file moves the state machine; it does not pretend
-- the seat works.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_gets_its_own_command_machine_not_phase_cs.sql --apply --ddl

begin;

-- ── THE STATES THE CEO SEAT OWNS ───────────────────────────────────────────────────────────────
create table if not exists public.ceo_command_state (
  state        text primary key,
  is_terminal  boolean not null default false,
  meaning      text not null,
  added_at     timestamptz not null default now()
);

comment on table public.ceo_command_state is
  'The states a founder instruction can hold. Owned by the CEO seat. Replaces phase_c_command_state, '
  'which belonged to a governance programme the founder retired on 7 September 2026.';

insert into public.ceo_command_state (state, is_terminal, meaning) values
  ('received',               false, 'the instruction arrived and has not been read yet'),
  ('interpreting',           false, 'the CEO is working out what was asked'),
  ('clarification_required', false, 'kept as a state, but nothing may transition INTO it: the founder is not asked to confirm an instruction twice'),
  ('accepted',              false, 'understood, and the CEO has taken it on'),
  ('refused',                true,  'the CEO will not do it, and said why'),
  ('routed',                false, 'assigned to whoever is doing it'),
  ('tasks_created',         false, 'broken into work items'),
  ('in_progress',           false, 'being worked'),
  ('partially_blocked',     false, 'some of it is moving, some is stuck'),
  ('completed',              true,  'done'),
  ('failed',                 true,  'it could not be done'),
  ('cancelled',              true,  'stopped, by the founder or by the CEO'),
  ('superseded',             true,  'a later instruction replaced it')
on conflict (state) do nothing;

-- ── THE EDGES ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_command_transition (
  from_state text not null references public.ceo_command_state(state),
  to_state   text not null references public.ceo_command_state(state),
  primary key (from_state, to_state)
);

comment on table public.ceo_command_transition is
  'Every legal move between command states. A move not listed here is refused by '
  'fn_founder_command_state_guard. `interpreting -> clarification_required` is deliberately absent.';

insert into public.ceo_command_transition (from_state, to_state) values
  ('received','interpreting'), ('received','cancelled'), ('received','failed'), ('received','superseded'),
  ('interpreting','accepted'), ('interpreting','refused'), ('interpreting','failed'),
  ('clarification_required','interpreting'), ('clarification_required','cancelled'),
  ('accepted','routed'), ('accepted','cancelled'), ('accepted','superseded'),
  ('routed','tasks_created'), ('routed','cancelled'), ('routed','failed'),
  ('tasks_created','in_progress'), ('tasks_created','cancelled'), ('tasks_created','superseded'),
  ('in_progress','completed'), ('in_progress','failed'), ('in_progress','cancelled'), ('in_progress','partially_blocked'),
  ('partially_blocked','in_progress'), ('partially_blocked','completed')
on conflict do nothing;

-- ── POINT THE COMMAND CHANNEL AT ITS OWN MODEL ─────────────────────────────────────────────────
alter table public.founder_command drop constraint if exists founder_command_state_fkey;
alter table public.founder_command
  add constraint founder_command_state_fkey
  foreign key (state) references public.ceo_command_state(state);

-- The guard keeps its name and its trigger; only the table it consults changes. CREATE OR REPLACE
-- preserves the existing ACL, so there is no grant to re-revoke here.
create or replace function public.fn_founder_command_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if new.state is distinct from old.state
     and not exists (select 1 from public.ceo_command_transition
                      where from_state = old.state and to_state = new.state) then
    raise exception
      'founder_command %: transition % -> % is not a legal move in the CEO command model',
      old.command_id, old.state, new.state
      using hint = 'Legal moves are listed in public.ceo_command_transition.';
  end if;
  return new;
end
$fn$;

commit;

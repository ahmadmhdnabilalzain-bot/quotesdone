-- THE CEO'S COMMAND CHANNEL, BUILT NEW.
--
-- Founder, 8 September 2026: "for the new CEO we will build proper tables and edge functions and
-- everything. we dont rely on the old structure", and "website content with FAQ and company previous
-- knowledge and leads and old api secrets remain. these are literally the only stuff you should keep
-- from anything created prior 7 september."
--
-- public.founder_command was created on 15 August and is therefore not on that list. The previous
-- file re-homed its state machine so that Phase C could be dropped; this one goes further and gives
-- the seat a channel of its own, so `founder_command` and its eleven satellite tables can be deleted
-- with the rest of the pre-7-September estate rather than carried.
--
-- Nothing of value is lost by that: all 27 rows in founder_command are in terminal states (cancelled
-- or refused), measured before writing this.
--
-- WHAT WAS ACTUALLY BROKEN, and why this is not just a rename. The old channel could not work:
--
--     phase_c_command_rule    0 rows  -> every instruction classified ambiguous
--     phase_c_command_intent  0 rows  -> nothing to classify it AS
--     phase_c_task_state      0 rows  -> FK target empty, so no task could be inserted at all
--
-- The 7 September collapse emptied the runtime tables and left the classifier reading from nothing.
-- The seat would have failed on the founder's first command. So the intents, the rules and the task
-- states are SEEDED here — a state model with no rows is not a state model.
--
-- AMBIGUOUS STILL MAKES WORK, and that is deliberate. The first probe of this channel classified an
-- unmatched sentence as ambiguous, marked the command accepted, and created nothing -- so an
-- instruction the pattern table did not recognise would have been silently swallowed. The founder's
-- standing rule is that he is never asked to confirm an instruction twice, which means the seat has
-- to work out what he meant rather than wait. Unrecognised is a reason to think, not a reason to
-- stop.
--
-- THE CLASSIFIER IS DETERMINISTIC, on purpose. It is a pattern table and a rank, not a model call.
-- An instruction from the founder must be routed the same way twice, must cost nothing to route, and
-- must be explainable by pointing at the row that matched. The model's judgement belongs in HOW the
-- work is done, not in whether his instruction was understood.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_command_channel_is_new_not_inherited.sql --apply --ddl

begin;

-- ── WHAT AN INSTRUCTION CAN BE ─────────────────────────────────────────────────────────────────
create table if not exists public.ceo_command_intent (
  intent_id    text primary key,
  meaning      text not null,
  needs_work   boolean not null default true,
  added_at     timestamptz not null default now()
);

insert into public.ceo_command_intent (intent_id, meaning, needs_work) values
  ('build',    'make something that does not exist yet',                       true),
  ('fix',      'something is broken or wrong and must be put right',           true),
  ('remove',   'delete, retire or switch something off',                       true),
  ('measure',  'find out and report a fact about the company',                 true),
  ('decide',   'make a judgement the founder is delegating',                   true),
  ('stop',     'halt work already in flight',                                  true),
  ('inform',   'a statement of fact or a standing rule, not a task',           false),
  ('ask',      'a question wanting an answer, not an action',                  false),
  ('ambiguous','nothing matched, so the CEO works out what was meant rather than dropping it', true)
on conflict (intent_id) do update set needs_work = excluded.needs_work, meaning = excluded.meaning;

-- ── HOW AN INSTRUCTION IS RECOGNISED ───────────────────────────────────────────────────────────
-- Matched longest-pattern-first so a specific phrase beats a general verb: "stop building" is stop,
-- not build. rank breaks ties where two patterns are the same length.
create table if not exists public.ceo_command_rule (
  rule_id    bigint generated always as identity primary key,
  pattern    text not null unique,
  intent_id  text not null references public.ceo_command_intent(intent_id),
  rank       int  not null default 100,
  note       text
);

insert into public.ceo_command_rule (pattern, intent_id, rank, note) values
  ('stop',        'stop',    10, 'halt beats every verb that follows it'),
  ('cancel',      'stop',    10, null),
  ('pause',       'stop',    10, null),
  ('delete',      'remove',  20, null),
  ('remove',      'remove',  20, null),
  ('retire',      'remove',  20, null),
  ('switch off',  'remove',  20, null),
  ('turn off',    'remove',  20, null),
  ('fix',         'fix',     30, null),
  ('repair',      'fix',     30, null),
  ('broken',      'fix',     30, null),
  ('not working', 'fix',     30, null),
  ('doesnt work', 'fix',     30, null),
  ('build',       'build',   40, null),
  ('create',      'build',   40, null),
  ('make',        'build',   40, null),
  ('add',         'build',   40, null),
  ('set up',      'build',   40, null),
  ('how many',    'measure', 50, null),
  ('how much',    'measure', 50, null),
  ('report',      'measure', 50, null),
  ('measure',     'measure', 50, null),
  ('check',       'measure', 50, null),
  ('verify',      'measure', 50, null),
  ('decide',      'decide',  60, null),
  ('approve',     'decide',  60, null),
  ('refund',      'decide',  60, 'refunds are the CEO''s decision from 8 Sep 2026'),
  ('from now on', 'inform',  70, 'a standing rule, not a task'),
  ('the rule is', 'inform',  70, null),
  ('remember',    'inform',  70, null),
  ('what is',     'ask',     80, null),
  ('what are',    'ask',     80, null),
  ('why',         'ask',     80, null),
  ('who',         'ask',     80, null)
on conflict (pattern) do nothing;

-- ── THE CHANNEL ────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_command (
  command_id    bigint generated always as identity primary key,
  received_at   timestamptz not null default now(),
  channel       text not null check (channel in ('whatsapp','email','api','console')),
  from_identity text not null,
  body          text not null,
  intent_id     text not null references public.ceo_command_intent(intent_id) default 'ambiguous',
  matched_rule  bigint references public.ceo_command_rule(rule_id),
  state         text not null references public.ceo_command_state(state) default 'received',
  outcome       text,
  closed_at     timestamptz
);

comment on table public.ceo_command is
  'Instructions to the CEO seat. Replaces founder_command, which was built on 15 August for a company '
  'of ten departments. The state model is ceo_command_state / ceo_command_transition.';

create index if not exists ceo_command_state_idx on public.ceo_command (state, received_at desc);

-- The same transition guard the previous file proved, on the new channel.
create or replace function public.fn_ceo_command_state_guard()
returns trigger
language plpgsql
as $fn$
begin
  if new.state is distinct from old.state
     and not exists (select 1 from public.ceo_command_transition
                      where from_state = old.state and to_state = new.state) then
    raise exception 'ceo_command %: transition % -> % is not a legal move',
      old.command_id, old.state, new.state
      using hint = 'Legal moves are listed in public.ceo_command_transition.';
  end if;
  return new;
end
$fn$;

drop trigger if exists z20_ceo_command_state_guard on public.ceo_command;
create trigger z20_ceo_command_state_guard
  before update on public.ceo_command
  for each row execute function public.fn_ceo_command_state_guard();

-- ── THE WORK AN INSTRUCTION BECOMES ────────────────────────────────────────────────────────────
create table if not exists public.ceo_task_state (
  state       text primary key,
  is_terminal boolean not null default false,
  meaning     text not null
);

insert into public.ceo_task_state (state, is_terminal, meaning) values
  ('open',      false, 'created, not started'),
  ('working',   false, 'being done now'),
  ('blocked',   false, 'cannot proceed, and the reason is recorded'),
  ('done',      true,  'finished, with evidence'),
  ('abandoned', true,  'deliberately not going to be done, and why')
on conflict (state) do nothing;

create table if not exists public.ceo_task (
  task_id     bigint generated always as identity primary key,
  command_id  bigint references public.ceo_command(command_id),
  title       text not null,
  detail      text,
  state       text not null references public.ceo_task_state(state) default 'open',
  blocked_reason text,
  evidence    text,
  created_at  timestamptz not null default now(),
  closed_at   timestamptz,
  -- A task does not get to be blocked silently, or done without saying how you know.
  constraint ceo_task_blocked_says_why check (state <> 'blocked' or coalesce(btrim(blocked_reason),'') <> ''),
  constraint ceo_task_done_shows_evidence check (state <> 'done' or coalesce(btrim(evidence),'') <> '')
);

create index if not exists ceo_task_open_idx on public.ceo_task (state, created_at) where state in ('open','working','blocked');

-- ── THE CLASSIFIER ─────────────────────────────────────────────────────────────────────────────
-- Longest matching pattern wins, then lowest rank. Returns 'ambiguous' when nothing matches, which
-- is a real answer and not a failure: the CEO says it did not understand rather than guessing.
create or replace function public.fn_ceo_classify(p_text text)
returns table (intent_id text, rule_id bigint, matched text)
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select r.intent_id, r.rule_id, r.pattern
    from public.ceo_command_rule r
   where position(r.pattern in lower(coalesce(p_text, ''))) > 0
   order by length(r.pattern) desc, r.rank asc
   limit 1
$fn$;

revoke all on function public.fn_ceo_classify(text) from public;
revoke all on function public.fn_ceo_classify(text) from anon;

-- ── SUBMIT ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_command_submit(
  p_channel text, p_from text, p_body text
) returns table (command_id bigint, intent_id text, state text, matched text)
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_intent text; v_rule bigint; v_match text; v_id bigint;
begin
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'an empty instruction is not an instruction' using errcode = '22023';
  end if;

  select c.intent_id, c.rule_id, c.matched into v_intent, v_rule, v_match
    from public.fn_ceo_classify(p_body) c;
  v_intent := coalesce(v_intent, 'ambiguous');

  insert into public.ceo_command (channel, from_identity, body, intent_id, matched_rule, state)
  values (p_channel, p_from, p_body, v_intent, v_rule, 'received')
  returning ceo_command.command_id into v_id;

  -- An instruction that asks for work becomes work. One that states a rule or asks a question is
  -- accepted and answered without manufacturing a task nobody wanted.
  update public.ceo_command set state = 'interpreting' where ceo_command.command_id = v_id;
  if exists (select 1 from public.ceo_command_intent i where i.intent_id = v_intent and i.needs_work) then
    update public.ceo_command set state = 'accepted' where ceo_command.command_id = v_id;
    insert into public.ceo_task (command_id, title, detail)
    values (v_id, left(btrim(p_body), 200), p_body);
    update public.ceo_command set state = 'routed'        where ceo_command.command_id = v_id;
    update public.ceo_command set state = 'tasks_created' where ceo_command.command_id = v_id;
  else
    update public.ceo_command set state = 'accepted' where ceo_command.command_id = v_id;
  end if;

  return query
    select c.command_id, c.intent_id, c.state, v_match
      from public.ceo_command c where c.command_id = v_id;
end
$fn$;

revoke all on function public.fn_ceo_command_submit(text, text, text) from public;
revoke all on function public.fn_ceo_command_submit(text, text, text) from anon;

commit;

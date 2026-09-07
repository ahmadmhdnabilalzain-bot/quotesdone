-- THE OS NEVER LEARNED WHO IT WORKS FOR
--
-- Row #3 §"personalization-learns-founder-habits" asks the OS to learn the founder's habits.
-- Measured on production before this change: 0 candidate founder-behaviour stores among 426 public
-- tables. Nothing anywhere recorded what he does, so nothing could adapt to it.
--
-- The evidence was there and unread. He has decided 12 agent_actions himself, and they are not
-- random:
--     bd_batch           4 of 4 REJECTED, a median 270 hours to answer
--     content_review     3 of 3 REJECTED, 328 hours
--     compliance_update  2 of 2 APPROVED,  79 hours
--     agent_created      1 of 1 APPROVED,  19 hours
--     handoff            1 done, 1 rejected
-- Two habits fall straight out of that. He rejects everything of two kinds — so the queue is
-- spending his attention on work he does not want — and he answers the things he approves roughly
-- four times faster, so his latency is itself a signal about what he cares about.
--
-- WHAT THIS REFUSES TO DO. Twelve decisions is a small sample and the table says so on every row:
-- `sample_n` travels with every habit and `confident` is false below EVIDENCE_FLOOR (3). A habit
-- observed twice is recorded as an observation, never asserted as a habit — the screen reads
-- `confident` and says "not enough evidence yet" rather than presenting n=1 as a preference. This
-- is the same rule as a scorer that reports NO SOURCE instead of a false 100%.
--
-- It also does NOT act on what it learns. Nothing here changes an authority, a route or a gate;
-- presentation may adapt, governance may not, and the check one row below this one in the spec
-- exists precisely to keep those apart.

create table if not exists public.founder_habit (
  founder        text        not null,
  habit_key      text        not null,
  habit_kind     text        not null,
  observed_value numeric,
  observed_text  text        not null,
  sample_n       integer     not null default 0,
  confident      boolean     not null default false,
  evidence       jsonb       not null default '{}'::jsonb,
  first_seen     timestamptz,
  last_seen      timestamptz,
  computed_at    timestamptz not null default now(),
  primary key (founder, habit_key)
);

-- A NEW TABLE GETS RLS ON PRODUCTION BY EVENT TRIGGER AND NOT ON STAGING, so it is enabled here
-- explicitly and the two projects stay in step. project_parity compares the count of tables without
-- RLS, and a table that is protected on one project and open on the other is exactly the drift that
-- check exists to catch.
alter table public.founder_habit enable row level security;

comment on table public.founder_habit is
  'What the OS has observed about how the founder decides. Every row carries its sample size and a
   `confident` flag; below three observations a row is an observation, not a habit. Presentation may
   adapt to these; governance may not.';

-- ROUTINE REMOVED 7 September 2026. public.fn_founder_habits_learn was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- The reader the OS console uses. STABLE, writes nothing.
create or replace function public.fn_founder_habits()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  select jsonb_build_object(
    'habits_total',     (select count(*) from founder_habit),
    'habits_confident', (select count(*) from founder_habit where confident),
    'evidence_floor',   3,
    'learned_at',       (select max(computed_at) from founder_habit),
    -- The note is part of the payload rather than the screen, so a caller that renders the rows
    -- without reading `confident` still carries the caveat with them.
    'note', 'A habit below the evidence floor is an observation, not a preference. sample_n travels with every row.',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
              'habit_key', h.habit_key, 'habit_kind', h.habit_kind, 'value', h.observed_value,
              'text', h.observed_text, 'sample_n', h.sample_n, 'confident', h.confident,
              'evidence', h.evidence, 'last_seen', h.last_seen)
            order by h.confident desc, h.sample_n desc, h.habit_key)
            from founder_habit h), '[]'::jsonb)
  );
$function$;

revoke all on function public.fn_founder_habits_learn() from public, anon, authenticated;
revoke all on function public.fn_founder_habits() from public, anon, authenticated;

-- Both classification gates, same change. requires_control is GENERATED and is not set.
insert into public.control_mode_action (action, description, classification, risk)
values ('founder_habits',
        'Reads founder_habit — what the OS has observed about how the founder decides. fn_founder_habits is STABLE and writes nothing.',
        'read_only', 'low')
on conflict (action) do update
  set classification = excluded.classification, description = excluded.description, risk = excluded.risk;

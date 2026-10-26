-- A recommendation that cannot say what it assumed — 12 Aug 2026
--
-- s36-recommendation-seven-fields asks that EVERY recommendation carry evidence, assumptions,
-- risks, alternatives, expected impact, confidence and cost. agent_actions had columns for four —
-- evidence, risk, confidence and (since 12 Aug) alternatives. Three had no column at all.
--
-- MEASURED FIRST, because the previous session's conclusion deserved re-testing rather than
-- inheriting: I searched decision_log, agent_actions, evolution_proposal, board_opinion,
-- org_action_executor, agent_runs, org_tasks and challenge_record for any column matching
-- assumption|premise|impact|expected|cost|spend|price. There is none. So unlike `alternatives` —
-- which was one join away in decision_log and could be filled by extraction — there is nothing in
-- the estate to extract these three from. That makes s36 an OUTPUT-CONTRACT change, not a schema
-- change: the routine that reasons has to state them at the moment it reasons.
--
-- WHY THIS IS NOT THE "DEFAULTS DEFEAT THE SPEC" TRAP. A default is one value stamped on every row
-- regardless of what the row says. What ships alongside this migration is the opposite: each of the
-- thirteen call sites in supabase/functions/agents/index.ts states its OWN three fields, and they
-- interpolate that call site's own data — the agents that failed, the page that is down, the number
-- of days a licence has left. Two rows from different watchers do not get the same sentence.
--
-- NULLABLE, AND MOST ROWS WILL STAY NULL FOR NOW, deliberately. This covers the writers in
-- agents/index.ts, which produced 714 of the ~1,311 recommendations in the last 30 days (agent 'it'
-- 556, 'onboarding' 158). The rest keep NULL, which reads as "this routine did not say what it
-- assumed" — true, and better than a sentence invented on its behalf. s36 therefore stays MISSING
-- until every writer states them, and that is the honest state, not a shortfall in this change.
--
-- cost is TEXT, not numeric, and that is a deliberate refusal of false precision. Most of these
-- recommendations cost attention rather than money; "no spend — engineering attention" is a true
-- and useful answer that a numeric column would have forced into a fabricated 0.00.

alter table public.agent_actions add column if not exists assumptions     jsonb;
alter table public.agent_actions add column if not exists expected_impact text;
alter table public.agent_actions add column if not exists cost            text;

comment on column public.agent_actions.assumptions is
  'What the routine took as given when it raised this, as a JSON array of statements. Stated by the '
  'call site that raised the recommendation, never defaulted. NULL means the routine did not say '
  'what it assumed, NOT that it assumed nothing.';

comment on column public.agent_actions.expected_impact is
  'What changes if this recommendation is acted on, in the raising routine''s own words and '
  'interpolating its own data. NULL means unstated, NOT that the impact is nil.';

comment on column public.agent_actions.cost is
  'What acting on this costs. TEXT rather than numeric on purpose: most of these cost attention '
  'rather than money, and a numeric column would force that into a fabricated 0.00. NULL means '
  'unstated, NOT free.';

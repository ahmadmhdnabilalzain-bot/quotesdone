-- Omniscience scoreboard: a question bank + graded runs proving any agent can answer company questions.
create table if not exists public.canon_eval_questions (
  id bigserial primary key, category text, question text not null, reference text, active boolean default true);
create table if not exists public.canon_eval_runs (
  id bigserial primary key, run_at timestamptz default now(), agent text,
  asked int, passed int, score_pct numeric, gaps jsonb);
alter table public.canon_eval_questions enable row level security;
alter table public.canon_eval_runs enable row level security;
-- 79 grounded questions loaded as DATA (exported in the final seed dump). canon_eval edge fn asks a real
-- agent via agent_brain, LLM-judges each answer vs the reference, records score + gaps. cron canon_eval_weekly.
-- Baseline: followup agent 80% (4/5); it honestly declined the one it did not know rather than fabricating.

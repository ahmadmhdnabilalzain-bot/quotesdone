-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726145047   name: knowledge_exam_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Rolling question bank per agent (grows over time; deduped in the edge fn).
create table if not exists public.knowledge_exam_questions (
  id bigserial primary key,
  agent_key text not null,
  question text not null,
  reference_answer text,
  topic text,
  difficulty text default 'core',
  times_asked int default 0,
  last_asked timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_kexam_q_agent on public.knowledge_exam_questions(agent_key, last_asked nulls first);

-- Every exam attempt: the agent's answer, the grader's independent answer/verdict, whether the two
-- independent models converged, and whether a fact was auto-written (with provenance to the knowledge row).
create table if not exists public.knowledge_exam_results (
  id bigserial primary key,
  agent_key text not null,
  question_id bigint references public.knowledge_exam_questions(id) on delete set null,
  examinee_answer text,
  verdict text,                 -- correct | partial | wrong | not_covered | unverifiable
  grader_answer text,
  grader_confidence numeric,
  converged boolean default false,
  gap_fact text,
  filled boolean default false,
  knowledge_id bigint,          -- the agent_knowledge row written (if any)
  created_at timestamptz default now()
);
create index if not exists idx_kexam_r_agent on public.knowledge_exam_results(agent_key, created_at desc);

alter table public.knowledge_exam_questions enable row level security;
alter table public.knowledge_exam_results enable row level security;

-- Per-agent competency summary from recent exams (read-only; OS reads it via os_api service role).
create or replace function public.fn_knowledge_exam_summary()
returns jsonb language sql stable security definer set search_path to 'public','pg_catalog' as $$
  with recent as (
    select * from knowledge_exam_results where created_at > now() - interval '30 days'
  ),
  per as (
    select agent_key,
      count(*) as examined,
      count(*) filter (where verdict='correct') as correct,
      count(*) filter (where verdict in ('wrong','partial','not_covered')) as gaps,
      count(*) filter (where filled) as filled,
      max(created_at) as last_exam
    from recent group by agent_key
  )
  select jsonb_build_object(
    'overall', jsonb_build_object(
      'question_bank', (select count(*) from knowledge_exam_questions),
      'exams_30d', (select count(*) from recent),
      'agents_examined', (select count(*) from per),
      'gaps_filled_30d', (select count(*) from recent where filled),
      'avg_score', (select round(100.0*count(*) filter (where verdict='correct')/nullif(count(*),0),1) from recent)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'agent_key', agent_key, 'examined', examined, 'correct', correct,
        'score_pct', round(100.0*correct/nullif(examined,0),1),
        'gaps', gaps, 'filled', filled, 'last_exam', last_exam
      ) order by round(100.0*correct/nullif(examined,0),1) asc nulls first) from per), '[]'::jsonb)
  );
$$;
revoke execute on function public.fn_knowledge_exam_summary() from anon, authenticated, public;

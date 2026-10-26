-- EVERY POSITION HAS ITS CERTIFICATIONS AND AN EXAM BANK (6 Sep 2026).
--
-- Founder, 6 Sep 2026: "create a list of the top certificates for every position we have in the company
-- and then test all agents. if they dont pass them all, then their knowledge is simply not enough."
--
-- Two tables. role_certification names, per employee, the professional certifications a top senior human
-- in that seat would hold (issuing body, real pass mark, why it is the one that matters). certification_exam_question
-- is the bank: multiple-choice questions at the real exam's difficulty, one key, a rationale and the syllabus
-- area, authored per certification. certification_exam_result records every sitting: the employee answers
-- deterministically from its own knowledge (fn_certification_exam_sit), the key grades it, the pass mark
-- decides. No paid model is involved in sitting or grading; an employee that cannot find the answer in what
-- it knows fails the question, which is the founder's criterion exactly.
--
--   node scripts/apply_sql.mjs scripts/sql/every_position_has_its_certifications_and_an_exam_bank.sql --apply --ddl

begin;

create table if not exists public.role_certification (
  id bigserial primary key,
  agent_key text not null references public.org_agents(agent_key),
  certification text not null,            -- e.g. 'CPA (Certified Public Accountant)'
  issuing_body text not null,             -- e.g. 'AICPA / NASBA'
  pass_mark_pct numeric(5,2) not null,    -- the real exam's pass mark, e.g. 75
  rank smallint not null default 1,       -- 1 = the certification that matters most for the seat
  why text not null,                      -- why a top senior human in this seat holds it
  syllabus_areas text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (agent_key, certification)
);
comment on table public.role_certification is 'Per employee: the professional certifications a top senior human in that seat holds (founder, 6 Sep 2026).';

create table if not exists public.certification_exam_question (
  id bigserial primary key,
  certification text not null,
  syllabus_area text not null,
  difficulty text not null default 'exam' check (difficulty in ('exam','hard')),
  question text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option char(1) not null check (correct_option in ('A','B','C','D')),
  rationale text not null,
  created_at timestamptz not null default now()
);
create index if not exists certification_exam_question_cert_idx on public.certification_exam_question (certification);
comment on table public.certification_exam_question is 'Multiple-choice bank per certification at the real exam''s difficulty; the key and rationale grade a sitting without any model.';

create table if not exists public.certification_exam_result (
  id bigserial primary key,
  agent_key text not null references public.org_agents(agent_key),
  certification text not null,
  sat_at timestamptz not null default now(),
  questions int not null,
  correct int not null,
  score_pct numeric(5,2) not null,
  pass_mark_pct numeric(5,2) not null,
  passed boolean not null,
  weakest_areas jsonb not null default '[]'::jsonb,   -- [{area, asked, correct}]
  answers jsonb not null default '[]'::jsonb          -- [{question_id, chosen, correct, evidence_record}]
);
create index if not exists certification_exam_result_agent_idx on public.certification_exam_result (agent_key, sat_at desc);

alter table public.role_certification enable row level security;
alter table public.certification_exam_question enable row level security;
alter table public.certification_exam_result enable row level security;
revoke all on public.role_certification, public.certification_exam_question, public.certification_exam_result from public, anon, authenticated;

commit;

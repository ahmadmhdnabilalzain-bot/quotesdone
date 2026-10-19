-- A SEAT EXAM QUESTION IS NEVER ASKED IN THE SAME WORDING, AND EVERY MISS OPENS A FIX (ledger 1084, 19 Oct 2026).
-- Seat: it_engineer. Written by scripts/eval/seat_exam_llm_on.mjs; read by the daily exam run and its acceptance query.
--
-- seat_exam_asked   one row per question put to a seat with the model on: the fresh wording, the seat's own answer,
--                   the grade and who graded it (code = every expected fact present; claude = a Claude agent on the
--                   subscription, where judgement was needed). The unique index makes a repeated wording impossible:
--                   a correct reply to one exact wording proves nothing (the founder, ledger 1084).
-- seat_exam_fix     one open row per missed question. It records the fix (a knowledge ingest or a prompt change) and
--                   is closed only by a later PASSING ask of the same question in a new wording.
create table if not exists public.seat_exam_fix (
  id           bigint generated always as identity primary key,
  seat         text not null,
  item_id      text not null,
  opened_at    timestamptz not null default now(),
  opened_run   text not null,
  kind         text check (kind in ('knowledge_ingest', 'prompt')),
  fix_ref      text,                      -- the commit or PR that carries the fix
  status       text not null default 'open' check (status in ('open', 'closed')),
  closed_at    timestamptz,
  closed_by_asked_id bigint,
  check ((status = 'closed') = (closed_at is not null and closed_by_asked_id is not null and fix_ref is not null))
);
create unique index if not exists seat_exam_fix_one_open_per_item on public.seat_exam_fix (item_id) where status = 'open';

create table if not exists public.seat_exam_asked (
  id         bigint generated always as identity primary key,
  run_tag    text not null,
  asked_at   timestamptz not null default now(),
  seat       text not null,
  item_id    text not null,
  wording    text not null,
  answer     text,
  model      text,
  status     text not null,               -- think(): answered | held | error
  pass       boolean not null,
  graded_by  text not null check (graded_by in ('code', 'claude')),
  missing    text[] not null default '{}', -- the expected facts the answer did not contain
  fix_id     bigint references public.seat_exam_fix (id)
);
create unique index if not exists seat_exam_asked_wording_once
  on public.seat_exam_asked (item_id, md5(lower(regexp_replace(wording, '\W+', '', 'g'))));
create index if not exists seat_exam_asked_item_time on public.seat_exam_asked (item_id, asked_at desc);

alter table public.seat_exam_fix enable row level security;
alter table public.seat_exam_asked enable row level security;
drop policy if exists seat_exam_fix_service_role_only on public.seat_exam_fix;
create policy seat_exam_fix_service_role_only on public.seat_exam_fix as permissive for all to public using (false) with check (false);
drop policy if exists seat_exam_asked_service_role_only on public.seat_exam_asked;
create policy seat_exam_asked_service_role_only on public.seat_exam_asked as permissive for all to public using (false) with check (false);
revoke all on public.seat_exam_fix, public.seat_exam_asked from anon, authenticated;

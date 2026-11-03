-- A CONVERSATION TOO BIG TO DRAW IS KEPT AS A TEXT COPY. Seat: it_engineer, 2 Nov 2026 (review of #1797).
--
-- The founder (14 Sep 2026): every conversation is kept, printed and backed up twice. conversation_archive draws each
-- message as a PDF inside the edge's 2 s CPU cap; a message the renderer cannot draw inside that cap kills its worker
-- (HTTP 546) every time, leaves no trace, and would stay pending for ever. This counts the attempts: the sweep calls
-- fn_conversation_archive_attempt BEFORE each render, so a worker that dies has still counted. From the fourth attempt
-- the message is kept as an HTML copy of the same fields and text (conversation_archive/document.ts conversationHtml),
-- recorded through fn_conversation_archived like a PDF (Dropbox included), and an it_engineer finding names it.
-- A successful archive removes its counter row, so the table holds only messages that are failing.
create table if not exists public.conversation_archive_attempt (
  source_table text not null,
  source_id    text not null,
  attempts     integer not null default 0,
  first_at     timestamptz not null default now(),
  last_at      timestamptz not null default now(),
  primary key (source_table, source_id)
);
comment on table public.conversation_archive_attempt is
  'conversation_archive render attempts per message still pending; from the 4th the message is kept as an HTML copy. Seat: it_engineer.';
alter table public.conversation_archive_attempt enable row level security;
drop policy if exists conversation_archive_attempt_service_role_only on public.conversation_archive_attempt;
create policy conversation_archive_attempt_service_role_only on public.conversation_archive_attempt
  as permissive for all to public using (false) with check (false);
revoke all on public.conversation_archive_attempt from anon, authenticated;

-- Counts one attempt and returns the count including it.
create or replace function public.fn_conversation_archive_attempt(p_source_table text, p_source_id text)
returns integer
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  insert into public.conversation_archive_attempt as a (source_table, source_id, attempts)
  values (p_source_table, p_source_id, 1)
  on conflict (source_table, source_id) do update set attempts = a.attempts + 1, last_at = now()
  returning attempts;
$fn$;
revoke execute on function public.fn_conversation_archive_attempt(text, text) from public, anon, authenticated;

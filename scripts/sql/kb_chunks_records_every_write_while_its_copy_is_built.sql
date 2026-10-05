-- kb_chunks COPY-AND-SWAP: the write log (5 Oct 2026, it_engineer; ledger 1094).
--
-- scripts/kb/kb_chunks_copy_swap.mjs rebuilds public.kb_chunks as a fresh copy (live rows only, ~54 k after the
-- trim) and swaps it in, instead of VACUUM FULL: VACUUM FULL holds ACCESS EXCLUSIVE for ~3 min and both the
-- management API and the SQL editor cancel a statement at ~2 min (the founder's attempt on 5 Oct: timed out, no
-- change, 148,326 rows / 8,089 MB).
--
-- While the copy is built, every write to kb_chunks must reach the copy. A row trigger on kb_chunks (created by the
-- driver's prepare stage, dropped by its swap) appends the touched id here; the catch-up and the swap re-read the
-- CURRENT row for each logged id from kb_chunks and replace it in the copy (or remove it, if it is gone). Logging the
-- id, not the row, means the copy never keeps a stale version, whatever order the copy pages and the writes commit in.
--
-- Both objects are dropped with kb_chunks_old, a day after the swap (docs/runbooks/kb_chunks_rewrite.md, step 8).

create table if not exists public.kb_chunks_swap_log (
  seq       bigint generated always as identity primary key,
  id        bigint not null,
  logged_at timestamptz not null default now()
);
alter table public.kb_chunks_swap_log enable row level security;
drop policy if exists kb_chunks_swap_log_service_role_only on public.kb_chunks_swap_log;
create policy kb_chunks_swap_log_service_role_only on public.kb_chunks_swap_log
  as permissive for all to public using (false) with check (false);
revoke all on public.kb_chunks_swap_log from anon, authenticated;

-- SECURITY DEFINER so a write by any role that may write kb_chunks is logged; it only ever inserts an id.
create or replace function public.fn_kb_chunks_swap_log()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    insert into public.kb_chunks_swap_log (id) values (old.id);
  end if;
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.id is distinct from old.id) then
    insert into public.kb_chunks_swap_log (id) values (new.id);
  end if;
  return null;
end
$fn$;
revoke execute on function public.fn_kb_chunks_swap_log() from public, anon, authenticated;

select case when (select relrowsecurity from pg_class where oid = 'public.kb_chunks_swap_log'::regclass)
             and not has_function_privilege('anon', 'public.fn_kb_chunks_swap_log()', 'execute')
            then 'PROBE OK' else 'PROBE FAILED: kb_chunks_swap_log not closed' end as verdict;

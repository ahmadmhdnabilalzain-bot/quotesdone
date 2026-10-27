-- THE SEATS READ THE KNOWLEDGE LIBRARY ONCE IT HOLDS EVERY ROW.
-- Seat: it_engineer. 27 Oct 2026. Founder ledger 889 ("every agent's knowledge must be accessible at any time and
-- genuinely helpful"); ledger 1085 stage 2, PHASE 2 (read) of one_knowledge_library_is_built_beside_the_nine_stores_and_read_behind_a_flag.sql.
--
-- MEASURED 27 Oct 2026 08:41 UTC on production (htdblwldjkcgjvmqkbeh), read-only:
--   knowledge_library 56 rows (ops_knowledge 39, agent_knowledge 17), knowledge_library_origin 56,
--   fn_knowledge_library_read() = 'legacy'.
--   The nine stores it should mirror: kb_chunks 54,360, ops_knowledge 9,143, sales_knowledge 6,536, agent_knowledge 2,570,
--   ceo_knowledge 796, support_knowledge 722, it_engineer_knowledge 427, accountant_knowledge 399, marketing_knowledge 284.
--
-- WHY THE FLAG IS OFF. Phase 1 (applied 5 Oct, MANIFEST) built the library, its sync triggers and its readers, and put
-- the switch on an app_secrets value that nothing ever set. The backfill (scripts/kb/fill_knowledge_library.mjs --run)
-- never ran, so only rows WRITTEN since 5 Oct reached the library through the triggers: 56 of ~74,000. Setting the
-- secret today would hand every seat's retrieval to a library holding 0.08% of its knowledge. So the flag was never the
-- missing piece; a complete library was, and nothing tied the switch to the library being complete.
--
-- WHAT THIS FILE CHANGES (nothing is filled, nothing is dropped, app_secrets is not written)
--   knowledge_library_state   one row (id = 1): the last reconciliation verdict of the library against the nine stores,
--                             recorded by fn_knowledge_library_record_reconcile().
--   fn_knowledge_library_record_reconcile()   runs fn_knowledge_library_reconcile() and records its verdict. The fill
--                             script calls it at the end of every --run and in plan mode, so the verdict is never older
--                             than the last time anyone looked.
--   fn_knowledge_library_read()   now 'library' exactly when the recorded verdict says reconciled (every row and every
--                             citation of the nine stores is mapped), and 'legacy' otherwise. The app_secrets value
--                             'knowledge_library_read' = 'off' stays as a kill switch (any other value, or none, no
--                             longer decides anything): a recorded NOT reconciled verdict switches the seats back to the
--                             nine stores by itself, with no one setting anything.
--   Once the fill's last page is mapped and the reconciliation is recorded, fn_reason_retrieve and fn_reason_retrieve_ml
--   hand every seat's call to the library readers (their one-line dispatch from phase 1, unchanged). The sync triggers
--   then keep it in line with every writer, which is what makes a recorded verdict stay true.
--
-- WHAT IT DOES NOT DO: it does not fill the library (the fill is a night job, 23:00-06:00 Dubai, under the purge's load
-- and disk guard that only the script can read: scripts/kb/fill_knowledge_library.mjs --run), it does not switch the
-- writers or rename the nine stores (phase 2's later steps), and it does not prove the exam over the filled library.
-- Prevented by: scripts/checks/the_seats_read_the_knowledge_library_once_it_holds_every_row.test.mjs

create table if not exists public.knowledge_library_state (
  id            smallint primary key default 1,
  reconciled    boolean not null default false,
  verdict       jsonb not null default '{}'::jsonb,
  checked_at    timestamptz not null default now(),
  constraint knowledge_library_state_one_row_ck check (id = 1)
);
alter table public.knowledge_library_state enable row level security;
drop policy if exists knowledge_library_state_service_role_only on public.knowledge_library_state;
create policy knowledge_library_state_service_role_only on public.knowledge_library_state
  as permissive for all to public using (false) with check (false);
revoke all on public.knowledge_library_state from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('knowledge_library_state', true, 'knowledge', 'the last reconciliation verdict of the knowledge library against the nine stores; the seats read the library only while it says reconciled (ledger 889, 1085)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- A new routine: CREATE grants EXECUTE to PUBLIC, so it is revoked below.
create or replace function public.fn_knowledge_library_record_reconcile()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v jsonb := public.fn_knowledge_library_reconcile();
begin
  insert into public.knowledge_library_state as s (id, reconciled, verdict, checked_at)
  values (1, coalesce((v ->> 'reconciled')::boolean, false), v, now())
  on conflict (id) do update set reconciled = excluded.reconciled, verdict = excluded.verdict, checked_at = excluded.checked_at;
  return v;
end;
$fn$;
revoke execute on function public.fn_knowledge_library_record_reconcile() from public, anon, authenticated;

-- CREATE OR REPLACE keeps phase 1's ACL (already revoked from public, anon and authenticated).
create or replace function public.fn_knowledge_library_read()
returns text
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when (select value from public.app_secrets where key = 'knowledge_library_read') = 'off' then 'legacy'
    when coalesce((select reconciled from public.knowledge_library_state where id = 1), false) then 'library'
    else 'legacy' end;
$fn$;

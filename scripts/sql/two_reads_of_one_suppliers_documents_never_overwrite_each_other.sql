-- TWO READS OF ONE SUPPLIER'S DOCUMENTS NEVER OVERWRITE EACH OTHER (12 Nov 2026; seat: customer_support).
-- Final audit 12 Nov 2026, finding R1 (regcert_diagnosis F1, BLOCKER); founder: "Proceed with fixes" (ledger 1642).
--
-- MEASURED ON PRODUCTION, paid registration certification run 2 (tag 2777f7ae), J1, lead 157558, edge_logs by trace id:
--   22:53:17.975  the profile's read took its copy of supplier_capabilities.source_docs: the licence still 'reading'
--   22:53:21.408  the licence's read wrote the licence 'read', with its 3 activities
--   22:54:03.301  the profile's read wrote back ITS copy, 42 s old: the licence 'reading' again, licence_check.activities []
-- and fn_sales_engineer_verifies_supplier held the supplier pending / documents_being_read until the 30-minute sweep. Every
-- writer of source_docs (_shared/supplier_doc_trades.ts markReading and proposeFromRead, which the licence, the profile, the
-- catalogues, the sweep's re-read and its read-together-again all go through) read the value, waited on the model (4-60 s,
-- 30 calls, mean 17.4 s that round), and wrote the WHOLE value back. Nothing compared what was there at write time.
--
-- WHAT THIS DOES. fn_supplier_source_docs_store writes source_docs only if it is still what the writer read: it locks the
-- supplier's row (inserting it first when there is none, as the old upsert did) and compares the row's fingerprint with the
-- one the writer took (p_expect). Same: the value is written, with its version `v` one higher, and the call answers true.
-- Different: nothing is written and it answers false; the writer reads the row again and lays its own documents onto what
-- is there now (supplier_doc_trades.ts storeSourceDocs; a reading that is no longer of the same documents is read together
-- again, at most twice). So a read only ever writes over a value it has seen.
--
-- THE FINGERPRINT is { "v": <source_docs.v, 0 when absent>, "docs": [[path, status, read_at], ...] in stored order }. `v`
-- moves on every write through here, and on every other change of source_docs by the trigger at the end of this file. The documents' path, status and read_at also catch the SQL writers that set a document
-- with jsonb_set and do not move `v` (fn_supplier_doc_reading_escalate and the orphan clean-up): each changes a status.
-- supplier_doc_trades.ts sourceDocsFingerprint builds the same value from the row it read; strings only, so it compares
-- exactly after the JSON round trip (a float would not). The probe (..._probe.sql) and
-- two_reads_of_one_supplier_never_overwrite_each_other.test.ts hold the two to one literal.
--
-- WHY A COMPARE-AND-SET AND NOT A PER-DOCUMENT MERGE IN SQL. The merge rules (a licence or profile replaces the earlier one
-- of its kind, catalogues accumulate, at most 40 entries, a reader-@2 record is cleared) and the supplier-wide fields
-- computed from all the documents together (proposed_services, licence_check, proposed_trades) live in one place,
-- supplier_doc_trades.ts. A merge in SQL would be a second copy of those rules, and could still store a licence_check
-- computed without a licence that had been read meanwhile, which is exactly what the profile's write did on 11 Nov.
--
-- security invoker: the only caller is the service role (the edge functions), which owns its writes to the table; there is
-- nothing to lend. Revoked from everyone else all the same, and the search_path is pinned.

create or replace function public.fn_supplier_source_docs_store(
  p_supplier_id bigint, p_expect jsonb, p_source_docs jsonb, p_proposed_trades text[] default null, p_extracted boolean default false
) returns boolean
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_sd jsonb;
  v_now jsonb;
begin
  if p_supplier_id is null or p_source_docs is null or jsonb_typeof(p_source_docs) <> 'object' then
    raise exception 'fn_supplier_source_docs_store: a supplier id and a source_docs object are required';
  end if;
  insert into public.supplier_capabilities (supplier_id) values (p_supplier_id) on conflict (supplier_id) do nothing;
  select coalesce(c.source_docs, '{}'::jsonb) into v_sd from public.supplier_capabilities c where c.supplier_id = p_supplier_id for update;
  v_now := jsonb_build_object(
    'v', coalesce((v_sd ->> 'v')::bigint, 0),
    'docs', coalesce((select jsonb_agg(jsonb_build_array(d ->> 'path', d ->> 'status', d ->> 'read_at') order by o)
                        from jsonb_array_elements(case when jsonb_typeof(v_sd -> 'docs') = 'array' then v_sd -> 'docs' else '[]'::jsonb end)
                             with ordinality as x(d, o)), '[]'::jsonb));
  if p_expect is distinct from v_now then
    return false;
  end if;
  update public.supplier_capabilities c
     set source_docs = p_source_docs || jsonb_build_object('v', coalesce((v_sd ->> 'v')::bigint, 0) + 1),
         proposed_trades = coalesce(p_proposed_trades, c.proposed_trades),
         extracted_at = case when p_extracted then now() else c.extracted_at end
   where c.supplier_id = p_supplier_id;
  return true;
end
$fn$;

comment on function public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean) is
  'Writes supplier_capabilities.source_docs only when it still has the fingerprint {v, docs:[[path,status,read_at]]} the writer read (row locked); true = written and v+1, false = someone wrote first, read again. The one writer of source_docs from the edge (supplier_doc_trades.ts storeSourceDocs). Final audit 12 Nov 2026, R1.';

revoke execute on function public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean) from public, anon, authenticated;
grant execute on function public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean) to service_role;

-- EVERY CHANGE OF source_docs MOVES `v` (review of this fix, 12 Nov 2026). The fingerprint's path / status / read_at miss a writer
-- that changes only what a document says: fn_sales_engineer_decides_vision_trades (a_trade_read_off_a_picture_waits_for_the_sales_
-- engineer_to_confirm_it.sql, `set source_docs = jsonb_set(cap.source_docs, '{docs}', docs)`) moves a held trade into `trades` and
-- leaves all three as they were, so a read in flight would have written its copy over the sales engineer's decision. This trigger
-- moves `v` on ANY update that changes source_docs without moving `v` itself, so every writer, present and future, is seen by the
-- compare-and-set. fn_supplier_source_docs_store already writes v+1, which the trigger leaves alone. Measured 12 Nov 2026:
-- supplier_capabilities had no trigger of its own, so there is no order to keep with another.
create or replace function public.fn_supplier_source_docs_moves_v()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.source_docs is distinct from old.source_docs
     and (new.source_docs ->> 'v') is not distinct from (old.source_docs ->> 'v')
     and jsonb_typeof(new.source_docs) = 'object' then
    new.source_docs := new.source_docs || jsonb_build_object('v', coalesce((old.source_docs ->> 'v')::bigint, 0) + 1);
  end if;
  return new;
end
$fn$;
revoke execute on function public.fn_supplier_source_docs_moves_v() from public, anon, authenticated;

drop trigger if exists supplier_capabilities_source_docs_moves_v on public.supplier_capabilities;
create trigger supplier_capabilities_source_docs_moves_v
  before update of source_docs on public.supplier_capabilities
  for each row execute function public.fn_supplier_source_docs_moves_v();

-- PROBE: TWO READS OF ONE SUPPLIER'S DOCUMENTS NEVER OVERWRITE EACH OTHER (12 Nov 2026; seat: customer_support).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it after
-- two_reads_of_one_suppliers_documents_never_overwrite_each_other.sql, or after it in the same rolled-back transaction
-- (node scripts/ci/rehearse_sql.mjs <file> <this probe>). It makes one ZZ DEMO lead of its own and touches no other row.
-- It proves, on the real table and its triggers: the fingerprint the edge computes (the literal below, the same one
-- supabase/functions/_shared/two_reads_of_one_supplier_never_overwrite_each_other.test.ts asserts sourceDocsFingerprint builds) is the one the routine
-- computes; a write against it lands and moves v; the second writer, holding the value from before that write, is refused
-- and changes nothing (the 11 Nov lost write); a SQL writer's jsonb_set of one status is seen; a supplier with no row gets one;
-- and anon / authenticated cannot call it. Two sessions cannot run inside one transaction: the row lock that serialises
-- them is `select ... for update`; the interleavings themselves are driven by the Deno test over the same compare.

do $probe$
declare
  v_bad text[] := '{}'; v_lead bigint; v_lead2 bigint; v_ok boolean; v_sd jsonb;
  v_docs jsonb := '[{"path":"licenses/1/a.pdf","name":"a.pdf","kind":"licence","status":"reading","read_at":"2026-11-11T22:53:07.260Z","trades":[]},
                    {"path":"profiles/1/p.pdf","name":"p.pdf","kind":"profile","status":"reading","read_at":"2026-11-11T22:53:17.044Z","trades":[]}]';
  -- what sourceDocsFingerprint returns for { docs: v_docs } (no v yet)
  v_fp0 jsonb := '{"v":0,"docs":[["licenses/1/a.pdf","reading","2026-11-11T22:53:07.260Z"],["profiles/1/p.pdf","reading","2026-11-11T22:53:17.044Z"]]}';
  v_licence_read jsonb;
begin
  insert into public.leads (company_name) values ('ZZ DEMO source docs store probe') returning id into v_lead;
  insert into public.supplier_capabilities (supplier_id, source_docs) values (v_lead, jsonb_build_object('reader', 'supplier_doc_trades@4', 'docs', v_docs))
    on conflict (supplier_id) do update set source_docs = excluded.source_docs;

  -- the licence's read lands first, against the fingerprint both reads took
  v_licence_read := jsonb_set(v_docs, '{0}', (v_docs -> 0) || '{"status":"read","read_at":"2026-11-11T22:53:21.300Z","activities":["a","b","c"]}');
  v_ok := public.fn_supplier_source_docs_store(v_lead, v_fp0, jsonb_build_object('reader', 'supplier_doc_trades@4', 'docs', v_licence_read,
            'licence_check', '{"activities":["a","b","c"]}'::jsonb), array['mep_general'], true);
  select source_docs into v_sd from public.supplier_capabilities where supplier_id = v_lead;
  if v_ok is not true then v_bad := v_bad || 'the first write against the fingerprint it read was refused'::text; end if;
  if (v_sd ->> 'v') is distinct from '1' then v_bad := v_bad || ('v after the first write is ' || coalesce(v_sd ->> 'v', 'null')); end if;
  if (select proposed_trades from public.supplier_capabilities where supplier_id = v_lead) is distinct from array['mep_general'] then v_bad := v_bad || 'proposed_trades not written'::text; end if;
  if (select extracted_at from public.supplier_capabilities where supplier_id = v_lead) is null then v_bad := v_bad || 'extracted_at not set'::text; end if;

  -- the profile's read, 42 s later, still holding the fingerprint from before: refused, the licence stays read
  v_ok := public.fn_supplier_source_docs_store(v_lead, v_fp0, jsonb_build_object('reader', 'supplier_doc_trades@4', 'docs', v_docs, 'licence_check', '{"activities":[]}'::jsonb), array['x'], true);
  select source_docs into v_sd from public.supplier_capabilities where supplier_id = v_lead;
  if v_ok is not false then v_bad := v_bad || 'a write holding a stale fingerprint was accepted'::text; end if;
  if (v_sd #>> '{docs,0,status}') is distinct from 'read' or jsonb_array_length(v_sd #> '{licence_check,activities}') <> 3 then v_bad := v_bad || 'the stale write changed the row'::text; end if;

  -- read again, it writes: the fingerprint of the row as it is now
  v_ok := public.fn_supplier_source_docs_store(v_lead,
            '{"v":1,"docs":[["licenses/1/a.pdf","read","2026-11-11T22:53:21.300Z"],["profiles/1/p.pdf","reading","2026-11-11T22:53:17.044Z"]]}',
            v_sd || '{"docs":[]}'::jsonb || jsonb_build_object('docs', jsonb_set(v_sd -> 'docs', '{1,status}', '"read"')), null, false);
  if v_ok is not true then v_bad := v_bad || 'a write with the current fingerprint was refused'::text; end if;
  if (select source_docs ->> 'v' from public.supplier_capabilities where supplier_id = v_lead) is distinct from '2' then v_bad := v_bad || 'v did not move to 2'::text; end if;
  if (select proposed_trades from public.supplier_capabilities where supplier_id = v_lead) is distinct from array['mep_general'] then v_bad := v_bad || 'a null p_proposed_trades changed proposed_trades'::text; end if;

  -- a SQL writer that sets one status with jsonb_set (the escalation) and does not move v is still seen
  update public.supplier_capabilities set source_docs = jsonb_set(source_docs, '{docs,1,status}', '"unreadable"') where supplier_id = v_lead;
  v_ok := public.fn_supplier_source_docs_store(v_lead,
            '{"v":2,"docs":[["licenses/1/a.pdf","read","2026-11-11T22:53:21.300Z"],["profiles/1/p.pdf","read","2026-11-11T22:53:17.044Z"]]}',
            '{"docs":[]}'::jsonb, null, false);
  if v_ok is not false then v_bad := v_bad || 'a jsonb_set of one status by SQL was not seen'::text; end if;

  -- a supplier with no capability row: the first mark creates it, as the upsert did
  insert into public.leads (company_name) values ('ZZ DEMO source docs store probe, no row') returning id into v_lead2;
  delete from public.supplier_capabilities where supplier_id = v_lead2;
  v_ok := public.fn_supplier_source_docs_store(v_lead2, '{"v":0,"docs":[]}', jsonb_build_object('docs', v_docs), null, false);
  if v_ok is not true or not exists (select 1 from public.supplier_capabilities where supplier_id = v_lead2 and source_docs ->> 'v' = '1') then
    v_bad := v_bad || 'a supplier with no row was not given one'::text;
  end if;

  if has_function_privilege('anon', 'public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean)', 'execute') then
    v_bad := v_bad || 'anon or authenticated may call it'::text;
  end if;
  if not has_function_privilege('service_role', 'public.fn_supplier_source_docs_store(bigint, jsonb, jsonb, text[], boolean)', 'execute') then
    v_bad := v_bad || 'the service role may not call it'::text;
  end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'leads', jsonb_build_array(v_lead, v_lead2));
end $probe$;

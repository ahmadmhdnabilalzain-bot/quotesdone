-- PROBE: A SUPPLIER DOCUMENT WHOSE READ DIED IS READ AGAIN WITHIN FIFTEEN MINUTES (12 Nov 2026; seat: customer_support).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back (and a net.http_post queued
-- inside it is never sent: pg_net sends only what a committed transaction queued). Run it after
-- a_supplier_document_whose_read_died_is_read_again_within_fifteen_minutes.sql, or after it in the same rolled-back transaction.
-- It makes one ZZ DEMO lead of its own and proves: a document 'reading' for 11 minutes is due, one for 9 minutes is not, one
-- already re-read (retry) is not; the job exists at :03/:08, calls the kick and names its seat; nobody but the service role runs either routine.

do $probe$
declare
  v_bad text[] := '{}'; v_lead bigint;
  mk jsonb;
begin
  insert into public.leads (company_name) values ('ZZ DEMO doc reread probe') returning id into v_lead;
  mk := jsonb_build_object('path', 'profiles/' || v_lead || '/p.pdf', 'name', 'p.pdf', 'kind', 'profile', 'status', 'reading', 'trades', '[]'::jsonb);
  insert into public.supplier_capabilities (supplier_id, source_docs)
    values (v_lead, jsonb_build_object('docs', jsonb_build_array(mk || jsonb_build_object('read_at', to_char((now() - interval '9 minutes') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))))
    on conflict (supplier_id) do update set source_docs = excluded.source_docs;
  if public.fn_supplier_doc_reread_due(v_lead) then v_bad := v_bad || 'a mark 9 minutes old is due'::text; end if;

  update public.supplier_capabilities set source_docs = jsonb_build_object('docs', jsonb_build_array(mk || jsonb_build_object('read_at',
    to_char((now() - interval '11 minutes') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))) where supplier_id = v_lead;
  if not public.fn_supplier_doc_reread_due(v_lead) then v_bad := v_bad || 'a mark 11 minutes old is not due'::text; end if;

  update public.supplier_capabilities set source_docs = jsonb_build_object('docs', jsonb_build_array(mk || jsonb_build_object('retry', true, 'read_at',
    to_char((now() - interval '11 minutes') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')))) where supplier_id = v_lead;
  if public.fn_supplier_doc_reread_due(v_lead) then v_bad := v_bad || 'a document already re-read is due again (the escalation owns it)'::text; end if;

  if not exists (select 1 from cron.job where jobname = 'supplier_doc_reread_5min' and active and schedule = '3-59/5 * * * *'
                   and command like '%fn_supplier_doc_reread_kick()%') then
    v_bad := v_bad || 'the job supplier_doc_reread_5min is not scheduled at 3-59/5'::text;
  end if;
  if exists (select 1 from public.fn_writers_without_a_seat(7) w where w.name = 'supplier_doc_reread_5min') then
    v_bad := v_bad || 'the job names no seat'::text;
  end if;
  if has_function_privilege('anon', 'public.fn_supplier_doc_reread_kick()', 'execute') or has_function_privilege('authenticated', 'public.fn_supplier_doc_reread_kick()', 'execute')
     or has_function_privilege('anon', 'public.fn_supplier_doc_reread_due(bigint)', 'execute') or has_function_privilege('authenticated', 'public.fn_supplier_doc_reread_due(bigint)', 'execute') then
    v_bad := v_bad || 'anon or authenticated may run the kick or the due check'::text;
  end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'lead', v_lead, 'due_now_on_production', public.fn_supplier_doc_reread_due());
end $probe$;

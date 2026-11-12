-- A SUPPLIER DOCUMENT WHOSE READ DIED IS READ AGAIN WITHIN FIFTEEN MINUTES, NOT FORTY (12 Nov 2026; seat: customer_support).
-- Final audit 12 Nov 2026, finding R1b (regcert_diagnosis F5); founder: "Proceed with fixes" (ledger 1642).
--
-- WHAT WAS INTENDED. Every statement of the rule says 10 minutes: _shared/supplier_docs_later.ts REREAD_AFTER_MIN = 10 ("a document
-- still 'reading' REREAD_AFTER_MIN minutes on is read once more by the sweep"), resilience_ping later_duties.ts ("still 'reading'
-- 10 minutes on is read once more by supplier_api"), and the held licence's recommendation (a_licence_our_reader_failed_on_..sql:
-- "supplier_api docs_reread reads it again (after 10 minutes, doubling...)"). No ruling sets 30.
-- WHAT RAN. The read-again is a step of resilience_ping's itlater run, whose cadence is 1800 s (resilience_step; schedule.test.ts
-- SEED). Measured in edge_logs 11 Nov 16:15-23:16 UTC: docs_reread probes at :16 and :46 only. So a document is read again 10 to
-- 40 minutes after its mark, and the supplier is held Pending (documents_being_read / licence_being_read) all that time
-- (lead 157558: marked 22:53:07, first sweep after 23:03:07 was 23:16:03).
--
-- WHAT THIS DOES. pg_cron asks supplier_api docs_reread every 5 minutes, at :04 and :09 of every ten (away from :x0 / :x5, where
-- the seat duties' p90 edge latency was 3.4 s against 1.4 s, 11 Nov; this job is not a seat duty). The emptiest offset: counted
-- 12 Nov 2026 over cron.job, active jobs per minute (every-minute jobs included) by minute mod 5 were offset 0: 23-28, 1: 21-22,
-- 2: 22-23, 3: 21-22 (the hourly :23), 4: 21 in every minute; each offset carries 18 seat duties by #1936's spread. It makes the call ONLY when fn_supplier_doc_reread_due() finds something to
-- read: a document still 'reading', not yet re-read, marked 10 minutes ago or more (stuckOf's own rule), or a licence our reader
-- failed on that fn_supplier_licence_reread_claim would hand out now (its own predicate, without counting a try). Nothing due, no
-- request and no cost. So a dead read is read again 10 to 15 minutes after its mark. The 10 minutes stay: an edge worker's
-- background work lives at most 400 s (Supabase's wall-clock limit for a paid project), so a mark younger than that may still be a
-- read in progress, and 10 minutes is the first round figure past it with margin.
-- The itlater step stays as it is (it also runs the 30-minute escalation); two callers are harmless: the first re-read marks the
-- document retry, so stuckOf does not pick it again, and the writes go through fn_supplier_source_docs_store
-- (two_reads_of_one_suppliers_documents_never_overwrite_each_other.sql), which never writes over a newer value.
-- The credential is cred_fn_resilience_ping, whose scope names supplier_api (internal_credential fn.resilience_ping), as the
-- itlater step and fn_wa_human_request_tick already send it; the gateway key comes from fn_gateway_client_key() (supplier_api has
-- verify_jwt = true), as fn_reask_kick sends it.
-- APPLY ORDER: after two_reads_of_one_suppliers_documents_never_overwrite_each_other.sql and after supplier_api is deployed with it.

create or replace function public.fn_supplier_doc_reread_due(p_supplier_id bigint default null)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (
           select 1 from public.supplier_capabilities c
            cross join lateral jsonb_array_elements(case when jsonb_typeof(c.source_docs -> 'docs') = 'array' then c.source_docs -> 'docs' else '[]'::jsonb end) d
            where c.source_docs @> '{"docs":[{"status":"reading"}]}'
              and (p_supplier_id is null or c.supplier_id = p_supplier_id)
              and d ->> 'status' = 'reading'
              and (d ->> 'retry') is distinct from 'true'
              and (d ->> 'read_at') is not null
              and (d ->> 'read_at')::timestamptz <= now() - interval '10 minutes')
      or exists (
           select 1 from public.leads l
            where l.licence_read_state = 'ours_failed'
              and (p_supplier_id is null or l.id = p_supplier_id)
              and l.license_doc_path is not null
              and coalesce(btrim(l.claimed_by), '') <> ''
              and not coalesce(l.banned, false)
              and l.licence_read_tries < 8
              and coalesce(l.licence_read_at, '-infinity'::timestamptz) <= now() - make_interval(mins => 10 * (2 ^ l.licence_read_tries)::int)
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by) or coalesce(l.company_name, '') ~* '^\s*zz\s*demo')
                  = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'));
$fn$;
revoke execute on function public.fn_supplier_doc_reread_due(bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_doc_reread_kick()
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_ref text; v_key text; v_cred text;
begin
  -- no request unless something is due: no edge call, no cost
  if not public.fn_supplier_doc_reread_due() then
    return null;
  end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  v_key := public.fn_gateway_client_key();
  select value into v_cred from public.app_secrets where key = 'cred_fn_resilience_ping';
  if v_ref is null or v_key is null or v_cred is null then
    raise exception 'fn_supplier_doc_reread_kick: project_ref, the gateway key or cred_fn_resilience_ping missing from app_secrets';
  end if;
  return net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/supplier_api',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
    body := jsonb_build_object('__secret', v_cred, 'action', 'docs_reread'), timeout_milliseconds := 30000);
end $fn$;
revoke execute on function public.fn_supplier_doc_reread_kick() from public, anon, authenticated;

select cron.schedule('supplier_doc_reread_5min', '4-59/5 * * * *', $CRON$set statement_timeout = '20s'; select public.fn_supplier_doc_reread_kick();$CRON$);

-- the job names its seat (every_run_label_and_cron_job_names_its_seat.sql: a cron job no seat_duty or function_owner names)
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'supplier_doc_reread_5min', 'customer_support',
   'fn_supplier_doc_reread_kick() every 5 min at :04/:09: asks supplier_api docs_reread, only when a supplier document read died 10 minutes ago or a licence our reader failed on is due; a registration held Pending is read again in 10-15 min.',
   'scripts/sql/a_supplier_document_whose_read_died_is_read_again_within_fifteen_minutes.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql
-- Assigned: customer_support (the case is support's record). Founder rulings of 11 Nov 2026:
--   1635: "... The case summaries are backed up in the customer's or supplier's Dropbox folder with their profile."
--   1634: "Every customer and supplier is also backed up in their own Dropbox folder ... following the Dropbox structure
--          already built."
--
-- MEASURED 11 Nov 2026 (production, read-only): #1938's seam (fn_support_case_summary_backup_enqueue in
-- every_support_case_keeps_a_summary_and_the_reply_reads_it.sql) was off (app_secrets.case_summary_backup_enabled unset),
-- waiting for pdf_native to render a case summary. It also could not have worked when switched on: it queued one row per
-- summary VERSION, all at the same Dropbox path, each with a storage path set up front ('generated/case_summary_<ref>_v<n>')
-- that nothing ever writes - every 'generated' row on production (customer_details, supplier_details, inquiry_summary,
-- comparison; 516 rows) is queued with path NULL and rendered by dropbox_backup, which only renders when path is NULL. And
-- the daily listing check (fn_it_backup_listing_expected + dropbox_backup/listing.ts) compares EVERY done row's hash with
-- the one file at its path, so N versions at one path would read as N-1 "changed" files every day.
--
-- WHAT THIS CHANGES (fn_support_case_summary_backup_enqueue only; the summary writer already calls it):
--   * the file is text: <person folder>/cases/<case number>.md, written by code (supabase/functions/_shared/case_dropbox.ts)
--     from the case as it is NOW, so it needs no PDF renderer and a late upload never writes an older version over a newer;
--   * ONE doc_backups row per case (dedupe_key 'CASE:<case number>'), re-queued on every new summary version (status
--     pending, path NULL, attempts 0), uploaded with mode 'overwrite' and verified; every earlier version stays in
--     support_case_summary_version, which is exported every day;
--   * the folder is the person's own, built exactly as fn_enqueue_doc_backups builds the Customer Details / Company Details
--     path, and the admit trigger (trg_doc_backups_admit) then files it beside the first file that opened their folder;
--     a ZZ DEMO person's row is dropped by that trigger, as every demo document is (unless a tagged sandbox run admits it);
--   * the switch is now a brake: on unless app_secrets.case_summary_backup_enabled = 'false';
--   * a person who is neither a customer nor a supplier (an e-mail or a phone only) has no folder, and is not queued.
-- WHAT IT DOES NOT CHANGE: dropbox_backup's queue, uploader or listing check; any existing doc_backups row; the summary
-- writer. Deploy dropbox_backup (renderGenerated's case_summary branch) BEFORE applying this file, or the first rows fail
-- 'unknown_gen_kind' and retry with backoff until it is deployed.
-- prevented by: supabase/functions/dropbox_backup/case_summary.test.ts (the request Dropbox receives, through backupRow on
-- a stubbed fetch), this file's _probe.sql (a ZZ DEMO case in a tagged sandbox run: one row per case, re-queued per
-- version; run on a local Postgres 16 stub, 11 Nov 2026: PROBE OK) and scripts/checks/every_case_keeps_a_summary.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql --apply --ddl

create or replace function public.fn_support_case_summary_backup_enqueue(p_case_id bigint)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; p public.support_customer_profile; v_entity text; v_id text; v_base text;
begin
  -- a brake, not a gate: the text file needs no renderer (11 Nov 2026)
  if coalesce((select value from public.app_secrets where key = 'case_summary_backup_enabled'), '') = 'false' then return false; end if;
  select * into c from public.support_case where case_id = p_case_id;
  if c.case_id is null or c.summary is null then return false; end if;
  select * into p from public.support_customer_profile where id = c.customer_profile_id;
  -- the person's folder, as fn_enqueue_doc_backups names it; the admit trigger re-anchors it to their first named folder
  if p.customer_id is not null then
    select '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(cu.full_name, 'Customer')) || ' (' || left(cu.id::text, 8) || ')/'
      into v_base from public.customers cu where cu.id = p.customer_id;
    v_entity := 'customer'; v_id := p.customer_id::text;
  elsif p.lead_id is not null then
    select '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/' || public.fn_dbx_safe(coalesce(l.company_name, 'Supplier'))
           || ' (' || l.id || ')/'
      into v_base from public.leads l where l.id = p.lead_id;
    v_entity := 'supplier'; v_id := p.lead_id::text;
  end if;
  if v_base is null then return false; end if;
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, file_name, dropbox_path, status, dedupe_key)
  values (v_entity, v_id, 'Case Summary', 'generated', 'case_summary', c.case_ref, c.case_ref || '.md',
          v_base || 'cases/' || c.case_ref || '.md', 'pending', 'CASE:' || c.case_ref)
  on conflict (dedupe_key) do update
     set status = 'pending', bucket = null, path = null, upload_state = null, error = null, attempts = 0,
         requeued_at = now(), claimed_at = null, claimed_by = null, last_attempt_at = null
   where doc_backups.status not in ('prune_pending', 'pruning', 'pruned');
  return found;
end $fn$;
revoke execute on function public.fn_support_case_summary_backup_enqueue(bigint) from public, anon, authenticated;

-- VERDICT (this file defines a routine, so it never raises to report)
select case
  when has_function_privilege('anon', 'public.fn_support_case_summary_backup_enqueue(bigint)', 'execute')
    then 'PROBE FAILED: anon can execute the case backup enqueue'
  when position('''CASE:'' || c.case_ref' in (select prosrc from pg_proc where oid = 'public.fn_support_case_summary_backup_enqueue(bigint)'::regprocedure)) = 0
    then 'PROBE FAILED: the case backup is not one row per case'
  else 'PROBE OK' end as verdict;

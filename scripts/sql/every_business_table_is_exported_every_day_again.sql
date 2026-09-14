-- EVERY BUSINESS TABLE IS EXPORTED EVERY DAY AGAIN, INTO THE BACKUPS BUCKET AND ON TO DROPBOX.
--
-- Assigned: it_engineer. 14 Sep 2026.
--
-- The founder, 14 Sep 2026: backups go to two places, the Supabase private 'backups' bucket and
-- Dropbox, in the entity -> type -> date tree, and "there is no reason for the loop of the back up to
-- fail except literally a disconnection from dropbox and supabase for a server issue from their end".
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production, read-only):
--   * storage.objects in 'backups' holds a dated export <YYYY-MM-DD>/<table>/page_NNNN.json for every
--     day from 2026-06-23 to 2026-09-07 and none after. The 7 Sep export is 248 objects, 725 MB, 21
--     tables: customers, inquiries, quotes, transactions, supplier_dues, reviews, questions,
--     inquiry_matches, reveal_invoices, pricing_config, expenses, content_drafts, category_specs,
--     category_agents, agent_memory, agent_chats, agent_knowledge, dept_library, ops_knowledge,
--     kb_chunks (200 pages) and leads (a column subset).
--   * Its writer was supabase/functions/backup, fired at 03:30 UTC by pg_cron job 109 (through the
--     kernel's cron executor, since dropped); cron.job_run_details shows its last run
--     2026-09-07 03:30:00 UTC. pg_cron's last run of any job is 2026-09-07 17:51 UTC: every job was
--     removed that evening on the founder's 7 Sep instruction, and cron.job now holds one inactive
--     row (wa_flush). The function itself was deleted the next morning by commit 182308b (#530,
--     "137 functions deleted"), because no seat owned it; the endpoint returns 404 today.
--   * ROOT CAUSE: the schedule and the writer were removed as part of the 7-8 Sep structural
--     clean-up, and nothing re-homed the daily table export the way dropbox_backup, the WhatsApp
--     drain and the refund ladder were re-homed onto resilience_ping. No decision was made to stop
--     backing up the database; the loop simply lost its clock and its worker.
--   * v1 had two silent failures of its own: it stopped at 200,000 rows (kb_chunks now holds 2.69 M,
--     so its "backup" was a truncated one), and a table that errored was written as -1 while the
--     manifest still said ok.
--
-- WHAT CHANGES (no pg_cron, nothing the founder removed is re-registered):
--   public.table_export_run                 one row per Asia/Dubai day: status, attempts, heartbeat,
--                                           the worker's resume point and the manifest
--   public.fn_table_export_list()           THE list of exported tables (below, with the reason)
--   public.fn_table_export_page()           one keyset page of one table, demo rows excluded,
--                                           vector columns stripped
--   public.fn_table_export_due()            called by resilience_ping every 15 min: claims today's
--                                           export after 03:00 Dubai, resumes a chain whose
--                                           heartbeat stopped, retries a failed day (6 attempts)
--   public.fn_table_export_save()           the worker's resume point after every slice
--   public.fn_table_export_finish()         verifies every page is in storage, marks the day, and
--                                           queues the files for Dropbox
--   public.fn_enqueue_doc_backups()         + TABLE EXPORTS: every file of a finished day is filed
--                                           under /QuotesDone Backup/Company/Database Exports/
--                                           <YYYY-MM>/<YYYY-MM-DD>/ (entity -> type -> date)
--   supabase/functions/backup (v2)          the revived writer; owned by it_engineer
--   fn.resilience_ping credential           may now call 'backup'
-- The expected list (fn_it_backup_expected) and the source registry are in
-- every_stored_document_source_is_registered_for_backup.sql, applied AFTER this file.
--
-- THE TABLE LIST, and why. In: every table holding a customer, supplier, inquiry, quote, payment,
-- accounting, conversation, consent/legal record, or a founder decision; plus the rules a quote is
-- checked against. The v1 business tables are all in. Out, by name:
--   * knowledge, not a business record: kb_chunks, dept_library, ops_knowledge, agent_knowledge,
--     support_knowledge, accountant_knowledge, ceo_knowledge. They are what v1 spent 700 MB a day on
--     (kb_chunks truncated at 200,000 of 2.69 M rows). NOT covered by this export; they need their
--     own decision, which is not taken here.
--   * agent working state from v1: agent_memory, content_drafts, category_agents.
--   * derived, regenerated from the tables above: supplier_score, customer_score, *_kpi_snapshots,
--     finance_snapshots, finance_reports, accountant_weekly_report, accountant_spend_report,
--     review_chain, review_queue, qd_compare_cache, quote_pdf_cache, supplier_opportunity_score,
--     supplier_response_watch, lead_trade_map.
--   * security material and verification caches, never copied into a file: customer_phone_otps,
--     admin_mfa_sessions, email_verifications, phone_verifications, email_domain_mx,
--     support_identity_challenge, user_roles.
--   * import staging and runtime logs: yello_staging, llm_calls, ai_usage, agent_runs, wa_inbound_seen,
--     wa_reply_intent, wa_answer_log, support_ceo_report.
--
--   node scripts/apply_sql.mjs scripts/sql/every_business_table_is_exported_every_day_again.sql --apply --ddl

-- ── 1. THE RECORD OF EACH DAY'S EXPORT ─────────────────────────────────────────────────────────────
create table if not exists public.table_export_run (
  stamp        date primary key,                       -- the Asia/Dubai day the export belongs to
  status       text not null default 'running' check (status in ('running', 'done', 'failed')),
  attempts     integer not null default 1,
  started_at   timestamptz not null default now(),
  heartbeat_at timestamptz not null default now(),
  finished_at  timestamptz,
  state        jsonb,                                  -- the worker's resume point (queue, per-table counts)
  manifest     jsonb,
  error        text
);
comment on table public.table_export_run is
  'One row per Asia/Dubai day of the daily business-table export (supabase/functions/backup v2). Written only by fn_table_export_due/_save/_finish. every_business_table_is_exported_every_day_again.sql';
alter table public.table_export_run enable row level security;
drop policy if exists table_export_run_service_role_only on public.table_export_run;
create policy table_export_run_service_role_only on public.table_export_run
  as permissive for all to public using (false) with check (false);
revoke all on public.table_export_run from anon, authenticated;

-- ── 2. THE LIST ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision')
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

-- ── 3. ONE PAGE OF ONE TABLE ───────────────────────────────────────────────────────────────────────
-- Keyset on the primary key (p_after is the previous page's last key as a JSON array), so a page
-- costs the same at row 20,000 as at row 1 and nothing stops at an arbitrary row count. A row is a
-- demo row when any of its values carries the fixture markers (ZZ DEMO, @example.invalid), when it
-- is_demo, or when it belongs to a demo customer, supplier, inquiry or quote. The page is filtered
-- BEFORE the limit, so done is exact.
create or replace function public.fn_table_export_page(p_table text, p_after jsonb default null, p_limit integer default 500)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_rel regclass; v_cols text; v_keyvals text; v_after text := 'true'; v_where text;
  v_strip text[]; v_lim integer := greatest(1, least(coalesce(p_limit, 500), 1000));
  v_dc text[]; v_dl text[]; v_di text[]; v_dq text[];
  v_rows jsonb; v_n integer; v_last jsonb;
begin
  if not exists (select 1 from public.fn_table_export_list() x where x.table_name = p_table) then
    raise exception 'fn_table_export_page: % is not in fn_table_export_list()', p_table;
  end if;
  v_rel := to_regclass(format('public.%I', p_table));
  if v_rel is null then raise exception 'fn_table_export_page: public.% does not exist', p_table; end if;

  select string_agg(format('t.%I', a.attname), ', ' order by k.ord),
         string_agg(format('(($1->>%s)::%s)', k.ord - 1, format_type(a.atttypid, a.atttypmod)), ', ' order by k.ord)
    into v_cols, v_keyvals
    from pg_index i
    cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = v_rel and i.indisprimary;
  if v_cols is null then raise exception 'fn_table_export_page: public.% has no primary key to page on', p_table; end if;
  if p_after is not null then v_after := format('(%s) > (%s)', v_cols, v_keyvals); end if;

  select coalesce(array_agg(a.attname::text), '{}') into v_strip
    from pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped and format_type(a.atttypid, a.atttypmod) like 'vector%';

  select coalesce(array_agg(c.id::text), '{}') into v_dc from public.customers c
   where coalesce(c.is_demo, false) or coalesce(c.email, '') ~* 'example\.invalid' or coalesce(c.full_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(l.id::text), '{}') into v_dl from public.leads l
   where coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid' or coalesce(l.company_name, '') ~* 'zz[_ -]?demo';
  select coalesce(array_agg(i.id::text), '{}') into v_di from public.inquiries i where i.customer_id::text = any(v_dc);
  select coalesce(array_agg(q.id::text), '{}') into v_dq from public.quotes q
   where q.supplier_id::text = any(v_dl) or q.inquiry_id::text = any(v_di);

  select format('(to_jsonb(t) - $2)::text !~* %L', 'zz[_ -]?demo|example\.invalid')
         || coalesce(string_agg(case a.attname
              when 'is_demo'     then ' and not coalesce(t.is_demo, false)'
              when 'customer_id' then ' and not coalesce(t.customer_id::text = any($3), false)'
              when 'supplier_id' then ' and not coalesce(t.supplier_id::text = any($4), false)'
              when 'lead_id'     then ' and not coalesce(t.lead_id::text = any($4), false)'
              when 'inquiry_id'  then ' and not coalesce(t.inquiry_id::text = any($5), false)'
              when 'quote_id'    then ' and not coalesce(t.quote_id::text = any($6), false)' end, ''), '')
    into v_where
    from pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped
     and a.attname in ('is_demo', 'customer_id', 'supplier_id', 'lead_id', 'inquiry_id', 'quote_id');

  execute format(
    'select coalesce(jsonb_agg(y.j order by y.ord), ''[]''::jsonb), count(*)::int, (array_agg(y.k order by y.ord desc))[1]
       from (select row_number() over () as ord, x.k, x.j
               from (select jsonb_build_array(%1$s) as k, to_jsonb(t) - $2 as j
                       from public.%2$I t where %3$s and %4$s order by %1$s limit %5$s) x) y',
    v_cols, p_table, v_after, v_where, v_lim)
    into v_rows, v_n, v_last
    using p_after, v_strip, v_dc, v_dl, v_di, v_dq;

  return jsonb_build_object('table', p_table, 'rows', v_rows, 'n', v_n, 'last', v_last, 'done', v_n < v_lim);
end $fn$;
revoke execute on function public.fn_table_export_page(text, jsonb, integer) from public, anon, authenticated;

-- ── 4. THE CLOCK: resilience_ping asks every 15 minutes ────────────────────────────────────────────
-- Due once per Asia/Dubai day after 03:00 local. A 'running' day whose heartbeat is older than 10
-- minutes is a chain that died between hops: it is resumed from its saved state. A 'failed' day is
-- restarted from the first table. After 6 attempts the day stays failed and the missing _manifest.json
-- is what the IT engineer's expected list reports.
create or replace function public.fn_table_export_due()
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_stamp date := (now() at time zone 'Asia/Dubai')::date;
  v_run public.table_export_run;
begin
  if v_local::time < time '03:00' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'before 03:00 Asia/Dubai');
  end if;
  select * into v_run from public.table_export_run r where r.stamp = v_stamp for update;
  if not found then
    insert into public.table_export_run (stamp) values (v_stamp) on conflict (stamp) do nothing;
    if not found then return jsonb_build_object('due', false, 'stamp', v_stamp, 'reason', 'claimed concurrently'); end if;
    return jsonb_build_object('due', true, 'stamp', v_stamp, 'attempt', 1, 'resume', null);
  end if;
  if v_run.status = 'done' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', 'done');
  end if;
  if v_run.heartbeat_at > now() - interval '10 minutes' then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'reason', 'in progress or waiting to retry');
  end if;
  if v_run.attempts >= 6 then
    return jsonb_build_object('due', false, 'stamp', v_stamp, 'status', v_run.status, 'attempts', v_run.attempts, 'reason', 'gave up after 6 attempts');
  end if;
  update public.table_export_run r
     set attempts = r.attempts + case when r.status = 'failed' then 1 else 0 end,
         status = 'running', heartbeat_at = now(),
         state = case when r.status = 'failed' then null else r.state end
   where r.stamp = v_stamp;
  return jsonb_build_object('due', true, 'stamp', v_stamp,
    'attempt', v_run.attempts + case when v_run.status = 'failed' then 1 else 0 end,
    'resume', case when v_run.status = 'running' then v_run.state end);
end $fn$;
revoke execute on function public.fn_table_export_due() from public, anon, authenticated;

create or replace function public.fn_table_export_save(p_stamp date, p_state jsonb)
returns boolean
language sql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
  update public.table_export_run r set state = p_state, heartbeat_at = now()
   where r.stamp = p_stamp and r.status = 'running'
  returning true;
$fn$;
revoke execute on function public.fn_table_export_save(date, jsonb) from public, anon, authenticated;

-- ── 5. THE DAY IS DONE ONLY WHEN STORAGE SAYS SO ───────────────────────────────────────────────────
create or replace function public.fn_table_export_finish(p_stamp date, p_manifest jsonb, p_error text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day text := to_char(p_stamp, 'YYYY-MM-DD');
  v_bad text; v_queued integer;
begin
  if p_error is null then
    select string_agg(x.table_name, ', ') into v_bad
      from public.fn_table_export_list() x
     where coalesce((p_manifest->'tables'->x.table_name->>'pages')::int, -1)
           <> (select count(*) from storage.objects o
                where o.bucket_id = 'backups' and o.name like v_day || '/' || x.table_name || '/page\_%.json');
    if v_bad is not null then p_error := 'pages in storage disagree with the manifest for: ' || v_bad; end if;
    if p_error is null and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = v_day || '/_manifest.json') then
      p_error := 'the manifest is not in storage';
    end if;
  end if;

  if p_error is not null then
    update public.table_export_run r set status = 'failed', error = left(p_error, 2000), heartbeat_at = now()
     where r.stamp = p_stamp;
    return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', left(p_error, 500));
  end if;

  update public.table_export_run r set status = 'done', finished_at = now(), heartbeat_at = now(), manifest = p_manifest, error = null
   where r.stamp = p_stamp;
  v_queued := public.fn_enqueue_doc_backups();
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'queued_for_dropbox', v_queued);
end $fn$;
revoke execute on function public.fn_table_export_finish(date, jsonb, text) from public, anon, authenticated;

-- ── 6. THE DROPBOX HALF: fn_enqueue_doc_backups + TABLE EXPORTS ────────────────────────────────────
-- The body is the MANIFEST-last definition (every_conversation_is_kept_backed_up_twice_and_readable_
-- by_the_sales_engineer.sql) with ONE section added at the end. PR #659 also redefines this routine
-- (the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql, + ACCOUNTING):
-- whichever of the two lands second must carry both sections, or the other is silently dropped.
create or replace function public.fn_enqueue_doc_backups()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare n integer := 0; m integer;
begin
  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      ('Trade licence','supplier-docs', s.license_doc_path),
      ('Bank IBAN','supplier-docs', s.iban_doc_path),
      ('Establishment card','supplier-docs', s.egr_doc_path),
      ('Insurance','supplier-docs', s.insurance_doc_path),
      ('VAT certificate','supplier-docs', s.vat_doc_path),
      ('ISO certificate','supplier-docs', s.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', s.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', s.company_profile_doc_path),
      ('Signed Terms & Conditions','signed-terms', s.signed_terms_path)
    ) v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
  )
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', sd.id::text, sd.doc_type, sd.bucket, sd.path,
         regexp_replace(sd.path,'^.*/',''),
         sd.base || sd.doc_type || ' - ' || regexp_replace(sd.path,'^.*/',''),
         'storage', 'S:'||sd.id||':'||sd.doc_type||':'||sd.path
  from sd on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base,
      l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMERS ============
  -- This is the row that carries a signed T&C certificate into Dropbox. compliance_archive writes
  -- customers.signed_terms_path and stops; the file is placed here, in one folder, once.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ INQUIRIES (under their customer) ============
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- The gen_kind='comparison' block that stood here is deliberately absent. See the header.

  -- ============ REVENUE INVOICES (9 SEP 2026) ============
  -- The founder: "our accountant need to retrieve that and be connected, then add it to his
  -- records, sync it with back up on dropbox." This is the sync half. The trigger is doc_path
  -- being non-null, NOT who wrote it, so a backfill or a hand-repair mirrors on the same rule as
  -- the webhook. They are filed under Finance rather than under the customer, because the person
  -- who opens this folder is the accountant reconciling a month, not someone reading one customer.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'transaction', t.id::text, 'Stripe invoice', 'finance-docs', t.doc_path,
         coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         '/QuotesDone Backup/Finance/Revenue Invoices/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY') || '/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY-MM') || '/'
           || public.fn_dbx_safe(coalesce(t.stripe_invoice_number, t.stripe_invoice_id, left(t.id::text,8)))
           || ' - ' || coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         'storage', 'T:'||t.id||':invoice:'||t.doc_path
  from public.transactions t
  where t.doc_path is not null and length(t.doc_path) > 0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;


  -- ============ CORRESPONDENCE (14 SEP 2026) ============
  -- The founder: "by back up i mean 2 points. supabase and dropbox." Every conversation message whose
  -- PDF is in backups/conversations/ (public.conversation_archive) is mirrored to Dropbox on his
  -- entity -> type -> date tree. A customer's message on an inquiry goes under that inquiry; a
  -- supplier's goes under the supplier ONLY when the supplier is a registrant (the same predicate the
  -- supplier documents use above); everything else is Company correspondence by month. Demo rows are
  -- never queued. Times are Dubai time.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select x.entity, x.entity_id, 'Correspondence', a.pdf_bucket, a.pdf_path, x.fname, x.base || x.fname, 'storage',
         'CONV:' || a.source_table || ':' || a.source_id
  from public.conversation_archive a
  join public.v_conversation_message v on v.source_table = a.source_table and v.source_id = a.source_id
  left join public.customers c on v.party_kind = 'customer' and c.id::text = v.party_id
  left join public.inquiries i on c.id is not null and i.id::text = v.inquiry_id
  left join public.leads l on v.party_kind = 'supplier' and l.id::text = v.party_id
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed,false))
  cross join lateral (select
      case when c.id is not null then 'customer' when l.id is not null then 'supplier' else 'company' end as entity,
      coalesce(c.id::text, l.id::text, v.source_table || ':' || v.source_id) as entity_id,
      case when c.id is not null then
             '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer')) || ' (' || left(c.id::text,8) || ')/'
             || case when i.id is not null then 'Inquiries/' || to_char(i.created_at,'YYYY-MM-DD') || ' ' || left(i.id::text,8)
                       || ' - ' || public.fn_dbx_safe(coalesce(i.status,'inquiry')) || '/' else '' end
             || 'Correspondence/'
           when l.id is not null then
             '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/'
             || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/Correspondence/'
           else '/QuotesDone Backup/Company/Correspondence/' || to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
      end as base,
      to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM-DD HH24MI') || ' ' || v.direction || ' ' || v.channel || ' - '
        || public.fn_dbx_safe(left(coalesce(nullif(btrim(v.subject),''),'(no subject)'),80)) || ' #' || v.source_id || '.pdf' as fname) x
  where not v.is_demo
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ TABLE EXPORTS (14 SEP 2026, it_engineer) ============
  -- Every file of a FINISHED day's export (public.table_export_run.status = 'done'), filed as
  -- Company -> Database Exports -> month -> day. Only finished days: a day that is re-run rewrites its
  -- pages, and a page mirrored mid-run would be a copy of an export that never completed. Demo rows
  -- never reach these files (fn_table_export_page). A (bucket, path) already queued by another rule
  -- (a refile) is skipped rather than allowed to fail this whole routine on the unique key.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || to_char(r.stamp,'YYYY-MM-DD'), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || to_char(r.stamp,'YYYY-MM') || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from public.table_export_run r
  join storage.objects o on o.bucket_id = 'backups' and o.name like to_char(r.stamp,'YYYY-MM-DD') || '/%'
  where r.status = 'done'
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;
revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ── 7. THE WRITER, ITS OWNER AND ITS CALLER ────────────────────────────────────────────────────────
insert into public.function_owner (function_slug, owner, note) values
 ('backup', 'it_engineer',
  'The daily export of every business table into the private backups bucket (<YYYY-MM-DD>/<table>/page_NNNN.json), queued on to Dropbox by fn_table_export_finish. Revived 14 Sep 2026 on the founder''s ruling that backups go to Supabase and Dropbox; deleted 8 Sep by #530 when no seat owned it. Scheduled by resilience_ping through fn_table_export_due.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note, recorded_at = now(), moves_to = null, moves_to_note = null;

-- resilience_ping starts the chain and each hop passes the same credential on to the next.
update public.internal_credential set scope = array_append(scope, 'backup')
 where context = 'fn.resilience_ping' and not ('backup' = any(scope));

-- ── 8. PROBE: read-only, leaves nothing behind (this file defines things, so it ends in notice) ────
do $probe$
declare v_missing text; v_nopk text; v_tables int; v_page jsonb; v_demo_left int; v_real int; v_exported int;
begin
  select string_agg(x.table_name, ', ') into v_missing from public.fn_table_export_list() x
   where to_regclass(format('public.%I', x.table_name)) is null;
  assert v_missing is null, 'listed tables that do not exist: ' || v_missing;
  select string_agg(x.table_name, ', ') into v_nopk from public.fn_table_export_list() x
   where not exists (select 1 from pg_index i where i.indrelid = to_regclass(format('public.%I', x.table_name)) and i.indisprimary);
  assert v_nopk is null, 'listed tables with no primary key: ' || v_nopk;
  select count(*) into v_tables from public.fn_table_export_list();

  -- customers: the export holds exactly the non-demo customers
  select count(*) into v_real from public.customers c
   where not (coalesce(c.is_demo, false) or coalesce(c.email, '') ~* 'example\.invalid' or coalesce(c.full_name, '') ~* 'zz[_ -]?demo');
  v_page := public.fn_table_export_page('customers', null, 1000);
  v_exported := (v_page->>'n')::int;
  assert v_exported = v_real, format('customers: exported %s, non-demo %s', v_exported, v_real);

  -- leads: two consecutive keyset pages do not overlap, and no demo marker survives
  v_page := public.fn_table_export_page('leads', null, 200);
  assert (v_page->>'n')::int = 200, 'leads: first page is not full';
  assert not ((v_page->'rows'->0) ? 'embedding'), 'leads: the vector column was not stripped';
  select count(*) into v_demo_left from jsonb_array_elements(v_page->'rows') e where e::text ~* 'zz[_ -]?demo|example\.invalid';
  assert v_demo_left = 0, 'leads: a demo row reached the export';
  assert (public.fn_table_export_page('leads', v_page->'last', 1)->'rows'->0->>'id')::bigint > (v_page->'last'->>0)::bigint,
    'leads: the second page does not start after the first';

  -- composite keys page too
  v_page := public.fn_table_export_page('lead_subcategory', null, 50);
  assert jsonb_array_length(v_page->'last') = 2, 'lead_subcategory: the composite key was not returned';

  raise notice 'table export: % tables listed, customers % exported of % non-demo, leads paged and clean; due now: %',
    v_tables, v_exported, v_real, (select count(*) from public.table_export_run);
end $probe$;

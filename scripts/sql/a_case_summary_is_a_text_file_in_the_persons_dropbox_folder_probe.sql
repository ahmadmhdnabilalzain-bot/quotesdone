-- a_case_summary_is_a_text_file_in_the_persons_dropbox_folder_probe.sql (customer_support, 11 Nov 2026)
-- A pure probe: run AFTER the file, in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'). Its
-- subjects are ZZ DEMO with @example.invalid addresses, created here; their backup rows are admitted only because this
-- transaction runs as a TAGGED SANDBOX RUN (qd.backup_sandbox, as fn_backup_sandbox_enqueue sets it), which re-roots them
-- under /QuotesDone Backup/_sandbox/<tag>/ - nothing here could reach a real person's folder even if it committed.
-- Run 11 Nov 2026 on a local Postgres 16 stub built from the schema mirror: PROBE OK.
do $probe$
declare
  v_tag constant text := 'casefileprobe';
  v_cust uuid; v_lead bigint; v_prof bigint; v_sprof bigint; v_ref text; v_sref text; v_anon bigint; v_aref text;
  s jsonb := jsonb_build_object('asked', 'ZZ DEMO a quote', 'said_or_did', 'took the sizes', 'promised', '[]'::jsonb, 'open', '[]'::jsonb);
  d public.doc_backups; n int; v_real int; v_real_after int;
begin
  perform set_config('qd.backup_sandbox', v_tag, true);
  select count(*) into v_real from public.doc_backups where gen_kind = 'case_summary' and entity <> 'zz_demo';

  -- a customer: the file is <their folder>/cases/<case number>.md, one row, waiting to be rendered
  insert into public.customers (full_name, email) values ('ZZ DEMO ' || v_tag || ' customer', 'zz-' || v_tag || '@example.invalid') returning id into v_cust;
  v_prof := public.fn_support_profile_resolve('customer', v_cust::text, 'zz-' || v_tag || '@example.invalid', null);
  v_ref := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO case file probe', 'en') ->> 'case_ref';
  perform public.fn_support_case_summary_write(v_ref, 0, s, 'ASKED: ZZ DEMO a quote', 'ZZ DEMO windows', 'customer_support');
  select * into d from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_ref;
  if d.id is null then raise exception 'CHK<<PROBE FAILED: the customer''s case was not queued for Dropbox>>'; end if;
  if d.dropbox_path <> '/QuotesDone Backup/_sandbox/' || v_tag || '/Customers/' || public.fn_dbx_safe('ZZ DEMO ' || v_tag || ' customer')
                       || ' (' || left(v_cust::text, 8) || ')/cases/' || v_ref || '.md'
     or d.file_name <> v_ref || '.md' or d.source <> 'generated' or d.path is not null or d.status <> 'pending'
    then raise exception 'CHK<<PROBE FAILED: the customer row is not <folder>/cases/<case>.md, generated, waiting: % % % %>>', d.dropbox_path, d.path, d.status, d.source; end if;

  -- uploaded (as dropbox_backup marks it), then a new summary version: the SAME row goes back to the queue, to be re-rendered
  update public.doc_backups set status = 'done', bucket = 'backups', path = 'generated/cases/' || v_ref || '.md', attempts = 1,
         dropbox_content_hash = 'h1', backed_up_at = now() where id = d.id;
  perform public.fn_support_case_summary_write(v_ref, 1, s || jsonb_build_object('said_or_did', 'sent the quotes'), 'ASKED: ZZ DEMO a quote', null, 'customer_support');
  select count(*) into n from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_ref;
  if n <> 1 then raise exception 'CHK<<PROBE FAILED: % rows for one case (the listing check would read the older ones as changed)>>', n; end if;
  if not exists (select 1 from public.doc_backups where id = d.id and status = 'pending' and path is null and attempts = 0 and requeued_at is not null)
    then raise exception 'CHK<<PROBE FAILED: a new version did not re-queue the case file>>'; end if;

  -- a supplier: its folder is Suppliers/<category>/<company (id)>/
  insert into public.leads (company_name) values ('ZZ DEMO ' || v_tag || ' supplier') returning id into v_lead;
  v_sprof := public.fn_support_profile_resolve('supplier', v_lead::text, null, null);
  v_sref := public.fn_support_case_route(v_sprof, 'new', null, 'portal', 'ZZ DEMO case file probe', 'en') ->> 'case_ref';
  perform public.fn_support_case_summary_write(v_sref, 0, s, 'ASKED: ZZ DEMO a quote', 'ZZ DEMO review', 'sales_engineer');
  if not exists (select 1 from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_sref
                  and dropbox_path like '/QuotesDone Backup/_sandbox/' || v_tag || '/Suppliers/%/' || public.fn_dbx_safe('ZZ DEMO ' || v_tag || ' supplier') || ' (' || v_lead || ')/cases/' || v_sref || '.md')
    then raise exception 'CHK<<PROBE FAILED: the supplier''s case is not in its company folder: %>>',
      (select dropbox_path from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_sref); end if;

  -- someone known only by an address is neither a customer nor a supplier: no folder, nothing queued
  v_anon := public.fn_support_profile_resolve('unknown', null, 'zz-' || v_tag || '-anon@example.invalid', null);
  v_aref := public.fn_support_case_route(v_anon, 'new', null, 'email', 'ZZ DEMO case file probe', 'en') ->> 'case_ref';
  perform public.fn_support_case_summary_write(v_aref, 0, s, 'ASKED: ZZ DEMO a quote', 'ZZ DEMO mail', 'customer_support');
  if exists (select 1 from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_aref)
    then raise exception 'CHK<<PROBE FAILED: a case with no customer or supplier was queued to a folder>>'; end if;

  -- the brake: 'false' stops the queue
  insert into public.app_secrets (key, value) values ('case_summary_backup_enabled', 'false')
  on conflict (key) do update set value = excluded.value;
  update public.doc_backups set status = 'done' where gen_kind = 'case_summary' and gen_ref = v_ref;
  perform public.fn_support_case_summary_write(v_ref, 2, s, 'ASKED: ZZ DEMO a quote', null, 'customer_support');
  if not exists (select 1 from public.doc_backups where gen_kind = 'case_summary' and gen_ref = v_ref and status = 'done')
    then raise exception 'CHK<<PROBE FAILED: the brake did not stop the queue>>'; end if;

  -- without the sandbox tag a demo person's row is dropped by the admit trigger, as every demo document is
  perform set_config('qd.backup_sandbox', '', true);
  update public.app_secrets set value = 'true' where key = 'case_summary_backup_enabled';
  perform public.fn_support_case_summary_write(v_ref, 3, s, 'ASKED: ZZ DEMO a quote', null, 'customer_support');
  if exists (select 1 from public.doc_backups where dedupe_key = 'CASE:' || v_ref)
    then raise exception 'CHK<<PROBE FAILED: a demo case reached the real backup tree>>'; end if;

  select count(*) into v_real_after from public.doc_backups where gen_kind = 'case_summary' and entity <> 'zz_demo';
  if v_real_after <> v_real then raise exception 'CHK<<PROBE FAILED: real case rows moved (% -> %)>>', v_real, v_real_after; end if;
  raise exception 'CHK<<PROBE OK %>>', jsonb_build_object('customer_case', v_ref, 'supplier_case', v_sref);
end $probe$;

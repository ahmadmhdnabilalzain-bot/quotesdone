-- DEMO DATA IS PURGED BY ITS MARKER, AND NO SEAT DUTY READS IT.
--
-- Assigned: it_engineer. Founder ruling 1199, 12 Oct 2026: once the tests finish, delete ALL test/demo data once
-- and for all (database, storage, Dropbox, logs) so no agent ever works on it as if it were real.
--
-- MEASURED (production, 12 Oct 2026 ~17:20-18:30Z, while the final sandbox run was live):
--   customers 16 rows, 14 demo (is_demo); leads 19,964, 38-39 demo; auth.users 73, 58 on a reserved domain;
--   doc_backups 859 rows of entity 'zz_demo' plus SBX:<tag> sandbox rows; dropbox_files (the Dropbox mirror, last
--   synced 7 Sep 2026) holds ZZ DEMO / __selftest__ / QD DEMO entity folders. Full census: the Desktop inventory
--   demo_inventory_2026-10-12.md. 8 enabled seat duties read customers/leads/inquiries/quotes/support_case with
--   no demo predicate (fn_support_case_idle_close, fn_ceo_pricing_monitor, fn_accountant_ubo_rescreen,
--   fn_sales_engineer_comparison_kpi, fn_sales_engineer_supplier_onboarding, fn_marketing_reputation,
--   fn_sales_engineer_quote_quality_tick [has its fixture switch], fn_sales_engineer_supplier_performance).
--
-- WHAT CHANGES:
--   1. ONE shared predicate family beside fn_is_demo_email / fn_is_demo_phone / fn_inquiry_is_demo:
--      fn_customer_is_demo(uuid), fn_supplier_is_demo(bigint), fn_quote_is_demo(uuid),
--      fn_transaction_is_demo(uuid), fn_party_is_demo(kind, id). Every one reads only a marker
--      (is_demo, which is itself the reserved e-mail / fixture mobile / ZZ DEMO / qd_demo rule, or provenance qd_run).
--   2. fn_demo_purge(p_apply): the ONE purge. Plan (default) runs the whole purge inside a savepoint and rolls it
--      back, so its counts are exact, not a lower bound. Apply deletes in foreign-key order: the demo id sets are
--      taken from markers first, every FK child is walked from pg_constraint (children before parents), the
--      id-keyed log tables go while the ids are still known, storage objects and Dropbox copies are listed in the
--      existing signup_purge_object / signup_purge_dropbox queues that dropbox_backup already drains.
--      THE GUARD: before and after, the count of NON-demo customers, leads, inquiries, quotes, transactions and
--      auth users is taken; any difference raises DEMO PURGE REFUSED and nothing is deleted. A real customer or
--      supplier cannot be touched: the only way a real row can be reached is through a real row pointing at a demo
--      one (a real inquiry that hired a demo supplier), and that changes a guarded count.
--   3. The seven duty routines above that lacked one now carry the predicate. quote_quality_tick already skips
--      fixtures (p_include_fixtures) and is unchanged.
--
-- WHAT DOES NOT CHANGE: free-text MENTIONS of demo names in knowledge, findings, instructions, incidents, run logs
--   and reports. They are not demo rows (a finding about a demo run is a real finding) and are listed as AMBIGUOUS
--   in the inventory, never deleted. Dropbox entity folders without a marker (QA Test Customer, ahmad test, ...)
--   are likewise ambiguous and kept.
--
-- PREVENTED BY: scripts/checks/no_seat_duty_reads_demo_rows.test.mjs (a duty routine that reads a subject table
--   without a demo predicate fails it), scripts/sql/demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it_probe.sql
--   (the guard refuses a purge that would reach a real inquiry; rolled back), the verdict row at the foot.

-- ── 1. the shared predicate ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_customer_is_demo(p_id uuid)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$ select coalesce((select c.is_demo from public.customers c where c.id = p_id), false) $fn$;

create or replace function public.fn_supplier_is_demo(p_id bigint)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$ select coalesce((select l.is_demo from public.leads l where l.id = p_id), false) $fn$;

create or replace function public.fn_quote_is_demo(p_id uuid)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select public.fn_inquiry_is_demo(q.inquiry_id) or public.fn_supplier_is_demo(q.supplier_id)
                     from public.quotes q where q.id = p_id), false)
$fn$;

create or replace function public.fn_transaction_is_demo(p_id uuid)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((select public.fn_customer_is_demo(t.customer_id) or public.fn_supplier_is_demo(t.supplier_id)
                          or public.fn_inquiry_is_demo(t.inquiry_id) or public.fn_quote_is_demo(t.quote_id)
                     from public.transactions t where t.id = p_id), false)
$fn$;

-- a party named by kind and text id (support_case, wa_conversation)
create or replace function public.fn_party_is_demo(p_kind text, p_id text)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select case
    -- a party known only by a reserved address (an 'unknown' inbound probe, or a demo party already removed)
    when public.fn_is_demo_email(p_id) then true
    when p_kind = 'customer' and p_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.fn_customer_is_demo(p_id::uuid)
    when p_kind in ('supplier', 'lead') and p_id ~ '^[0-9]{1,18}$' then public.fn_supplier_is_demo(p_id::bigint)
    else false end
$fn$;

revoke execute on function public.fn_customer_is_demo(uuid) from public, anon, authenticated;
revoke execute on function public.fn_supplier_is_demo(bigint) from public, anon, authenticated;
revoke execute on function public.fn_quote_is_demo(uuid) from public, anon, authenticated;
revoke execute on function public.fn_transaction_is_demo(uuid) from public, anon, authenticated;
revoke execute on function public.fn_party_is_demo(text, text) from public, anon, authenticated;

-- ── 1b. the name marker is a WORD (release review of #1348): 'ZZ Demolition LLC' is a real company, never demo.
-- Measured 12 Oct 2026: 0 leads, 0 customers, 0 social_conversation rows change value. Each ALTER rewrites its table
-- (leads ~20k rows) under a 3 s lock timeout, so a busy table fails this file instead of queueing sign-ins behind it.
set local lock_timeout = '3s';
alter table public.leads alter column is_demo set expression as (
  public.fn_is_demo_email(email) or public.fn_is_demo_email(claimed_by) or public.fn_is_demo_phone(phone)
  or 'qd_demo' = any(coalesce(tags, '{}'::text[]))
  or coalesce(company_name, '') ~* '^ZZ DEMO([^a-z]|$)'
  or coalesce(company_name, '') like 'QD Demo %'
  or coalesce(source, '') = any(array['demo_factory', 'qd_demo_fixture'])
);
alter table public.customers alter column is_demo set expression as (
  public.fn_is_demo_email(email) or public.fn_is_demo_phone(phone) or public.fn_is_demo_phone(whatsapp_phone)
  or coalesce(full_name, '') ~* '^ZZ DEMO([^a-z]|$)'
);
alter table public.social_conversation alter column is_demo set expression as (
  user_id ~* '^ZZDEMO([^a-z]|$)' or coalesce(handle, '') ~* '^ZZ DEMO([^a-z]|$)'
);

-- ── 2. the queues the purge hands storage and Dropbox to ─────────────────────────────────────────────────
alter table public.signup_purge drop constraint if exists signup_purge_kind_check;
alter table public.signup_purge add constraint signup_purge_kind_check
  check (kind in ('customer', 'supplier_self_registered', 'supplier_invited_lead', 'demo_purge'));
-- a whole demo entity folder has no backup record of its own
alter table public.signup_purge_dropbox alter column doc_backup_id drop not null;

-- THE FROZEN DROPBOX LIST (review of #1348): exactly supabase/functions/dropbox_backup/demo_purge_paths.json, which the
-- coordinator read before any apply. scripts/checks/no_seat_duty_reads_demo_rows.test.mjs fails if the two differ.
create or replace function public.fn_demo_purge_dropbox_paths()
 returns text[] language sql immutable set search_path to 'pg_catalog', 'pg_temp'
as $fn$ select array[
  '/QuotesDone Backup/Customers/Ahmad Nabil Al Zain',
  '/QuotesDone Backup/Customers/QA Journey Tester',
  '/QuotesDone Backup/Customers/QA Portal Tester',
  '/QuotesDone Backup/Customers/QA Test Customer',
  '/QuotesDone Backup/Customers/QA Villa Owner',
  '/QuotesDone Backup/Customers/TIWNKLE SHARMA',
  '/QuotesDone Backup/Customers/ahmad test',
  '/QuotesDone Backup/Customers/ahmad test 2',
  '/QuotesDone Backup/Customers/qa.portal.testquotesdone.com',
  '/QuotesDone Backup/_archive/demo-leftovers-2026-10-12',
  '/QuotesDone Backup/_archive/ownerless-2026-10-12'
]::text[] $fn$;
revoke execute on function public.fn_demo_purge_dropbox_paths() from public, anon, authenticated;

-- ── 3. the FK walk: delete (or count) the rows of p_rel matching p_where, every FK child first ───────────
create or replace function public.fn_demo_purge_walk(p_rel regclass, p_where text, p_depth integer, p_counts jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare f record; v_n bigint; v_key text := p_rel::text; v_k text;
begin
  if p_depth > 8 then raise exception 'demo purge: foreign-key chain deeper than 8 at %', p_rel; end if;
  -- every child, cascading ones included, is walked here, so the plan names each table the purge touches
  for f in
    select c.conrelid::regclass child, a.attname col, pa.attname pcol, c.confdeltype del
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
      join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
     where c.contype = 'f' and c.confrelid = p_rel and c.conrelid <> p_rel and cardinality(c.conkey) = 1
  loop
    if f.del = 'n' then
      -- a SET NULL reference is unlinked, never deleted: that row is not the demo entity's own
      execute format('update %s set %I = null where %I in (select %I from %s where %s)', f.child, f.col, f.col, f.pcol, p_rel, p_where);
      get diagnostics v_n = row_count;
      v_k := f.child::text || ' (unlinked ' || f.col || ')';
      p_counts := jsonb_set(p_counts, '{touched}', coalesce(p_counts->'touched', '{}'::jsonb)
                    || jsonb_build_object(v_k, coalesce((p_counts->'touched'->>v_k)::bigint, 0) + v_n));
    else
      p_counts := public.fn_demo_purge_walk(f.child,
        format('%I in (select %I from %s where %s)', f.col, f.pcol, p_rel, p_where), p_depth + 1, p_counts);
    end if;
  end loop;
  execute format('delete from %s where %s', p_rel, p_where);
  get diagnostics v_n = row_count;
  -- the books are never purged: a demo row that reached a ledger table is reversed by the accountant first
  if v_n > 0 and regexp_replace(v_key, '^.*[.]', '') ~ '^(gl_|ledger|journal|supplier_dues|accountant_issued|reveal_invoices|refund|stripe_|payout|bank_|cash_|finance_)' then
    raise exception 'DEMO PURGE REFUSED: % demo row(s) reached the ledger table %; the accountant reverses them first', v_n, v_key
      using errcode = 'QD197';
  end if;
  p_counts := jsonb_set(p_counts, '{touched}', coalesce(p_counts->'touched', '{}'::jsonb)
                || jsonb_build_object(v_key, coalesce((p_counts->'touched'->>v_key)::bigint, 0) + v_n));
  return p_counts;
end $fn$;
revoke execute on function public.fn_demo_purge_walk(regclass, text, integer, jsonb) from public, anon, authenticated;

-- the guarded count of everything that is NOT demo
create or replace function public.fn_demo_purge_real_counts()
 returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'leads', (select count(*) from public.leads where not coalesce(is_demo, false)),
    'inquiries', (select count(*) from public.inquiries i where not public.fn_inquiry_is_demo(i.id)),
    'quotes', (select count(*) from public.quotes q where not public.fn_quote_is_demo(q.id)),
    'transactions', (select count(*) from public.transactions t where not public.fn_transaction_is_demo(t.id)),
    'auth_users', (select count(*) from auth.users u where not public.fn_is_demo_email(u.email) and not public.fn_is_demo_phone(u.phone)
                     and not exists (select 1 from public.customers c where c.id = u.id and c.is_demo)))
$fn$;
revoke execute on function public.fn_demo_purge_real_counts() from public, anon, authenticated;

-- ── 4. the purge itself (always applies; fn_demo_purge decides whether it is kept) ──────────────────────
create or replace function public.fn_demo_purge_run()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_before jsonb := public.fn_demo_purge_real_counts(); v_after jsonb;
  c jsonb := '{}'::jsonb; v_pid bigint; v_obj int; v_dbx int; v_rec int; r record;
  EM constant text := '@([a-z0-9_-]+[.])*(example[.](com|net|org)|test|example|invalid|localhost)([^a-z0-9._-]|$)';
begin
  -- the demo id sets: markers only
  create temp table _dc on commit drop as select id from public.customers where is_demo;
  create temp table _dl on commit drop as select id from public.leads where is_demo;
  create temp table _di on commit drop as select id from public.inquiries i where public.fn_inquiry_is_demo(i.id);
  create temp table _dq on commit drop as select id from public.quotes where inquiry_id in (select id from _di) or supplier_id in (select id from _dl);
  create temp table _dt on commit drop as select id from public.transactions
    where customer_id in (select id from _dc) or supplier_id in (select id from _dl) or inquiry_id in (select id from _di) or quote_id in (select id from _dq);
  create temp table _du on commit drop as select id from auth.users u
    where public.fn_is_demo_email(u.email) or public.fn_is_demo_phone(u.phone) or u.id in (select id from _dc);
  create temp table _dk on commit drop as
    select id::text k from _dc union select id::text from _dl union select id::text from _di
    union select id::text from _dq union select id::text from _dt;
  c := jsonb_build_object('demo_ids', jsonb_build_object('customers', (select count(*) from _dc), 'leads', (select count(*) from _dl),
         'inquiries', (select count(*) from _di), 'quotes', (select count(*) from _dq), 'transactions', (select count(*) from _dt),
         'auth_users', (select count(*) from _du)));

  insert into public.signup_purge (kind, subject_ref, missing) values ('demo_purge', 'founder ruling 1199', '{}') returning id into v_pid;

  -- storage: every object a demo row names, or whose path carries a marker, that storage actually holds
  insert into public.signup_purge_object (purge_id, bucket, path)
  select v_pid, o.bucket_id, o.name from storage.objects o
    join (
      select 'signed-terms' b, signed_terms_path p from public.customers where id in (select id from _dc)
      union select 'signed-terms', signed_terms_path from public.leads where id in (select id from _dl)
      union select 'supplier-docs', regexp_replace(unnest(array[license_doc_path, company_profile_doc_path, egr_doc_path, insurance_doc_path,
                     vat_doc_path, iso_doc_path, manufacturer_auth_doc_path] || coalesce(catalog_doc_paths, '{}'::text[])), '^supplier-docs/', '')
          from public.leads where id in (select id from _dl)
      union select 'drawing-files', drawing_file_path from public.inquiries where id in (select id from _di)
      union select 'drawing-files', unnest(drawing_redacted_paths) from public.inquiries where id in (select id from _di)
      union select 'quote-files', original_file_path from public.quotes where id in (select id from _dq)
      union select 'quote-files', original_file_path from public.quote_reviews where inquiry_id in (select id from _di) or supplier_id in (select id from _dl)
      union select bucket, path from public.documents where ref_table in ('inquiries', 'quotes', 'leads', 'customers', 'transactions') and ref_id in (select k from _dk)
      union select bucket, path from public.doc_backups where entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and entity_id in (select k from _dk)
      union select bucket, path from public.supplier_document_cache where supplier_id in (select id from _dl)
      union select pdf_bucket, pdf_path from public.quote_spec_hold where quote_id in (select id from _dq)
    ) x on x.b = o.bucket_id and x.p = o.name
  union
  select v_pid, o.bucket_id, o.name from storage.objects o
   where (o.bucket_id = 'drawing-files' and split_part(o.name, '/', 2) in (select k from _dk))
      or (o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) in (select id::text from _dl))
      or (o.bucket_id = 'agent-docs' and exists (select 1 from _di where o.name like '%QD-' || upper(left(_di.id::text, 8)) || '-CMP%'))
      or (o.bucket_id not in ('brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'backups')
          and o.name ~* '(^|/)(zz[ _-]?demo([^a-z]|$)|__selftest__|_selftest/)')
  on conflict (bucket, path) do nothing;
  get diagnostics v_obj = row_count;

  -- Dropbox (review of #1348, coordinator 13 Oct 2026): ONLY the frozen, reviewed list (fn_demo_purge_dropbox_paths,
  -- the same paths as supabase/functions/dropbox_backup/demo_purge_paths.json) and the _sandbox/_selftest probe roots.
  -- No name pattern decides. Each backup record whose copy lies inside a listed path goes with it; a demo entity's
  -- copy anywhere else is NOT deleted from Dropbox and is named in the plan for a person to add to the list.
  create temp table _fp on commit drop as select unnest(public.fn_demo_purge_dropbox_paths()) p;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select v_pid, d.id, d.dropbox_path from public.doc_backups d
   where d.dropbox_path is not null
     and (exists (select 1 from _fp where d.dropbox_path = _fp.p or starts_with(d.dropbox_path, _fp.p || '/'))
          or d.dropbox_path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+/')
  on conflict (doc_backup_id) do nothing;
  get diagnostics v_dbx = row_count;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select v_pid, null, f.p from (
      select p from _fp
      union select substring(dropbox_path from '^(/QuotesDone Backup/_(?:sandbox|selftest)/[^/]+)/') from public.doc_backups
       where dropbox_path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+/'
      union select path from public.dropbox_files where path ~ '^/QuotesDone Backup/_(sandbox|selftest)/[^/]+$') f
   where f.p is not null
     and not exists (select 1 from public.signup_purge_dropbox s where s.dropbox_file = f.p and s.done_at is null);
  get diagnostics v_rec = row_count;
  v_dbx := v_dbx + v_rec;
  c := c || jsonb_build_object('dropbox_frozen_paths', (select jsonb_agg(p order by p) from _fp));
  -- a listed copy keeps its record until dropbox_backup has deleted the copy; a record with no copy goes now
  update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
         error = 'demo data purged (founder ruling 1199): Dropbox copy and record to be deleted'
   where d.id in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null);
  -- a demo record with no copy, or whose copy the live Dropbox listing (refreshed within 36 hours) no longer holds, has
  -- nothing in Dropbox to delete: the record goes now. Without a fresh listing such a record is kept and named.
  create temp table _dgone on commit drop as
  select d.id from public.doc_backups d
   where ((d.entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and d.entity_id in (select k from _dk))
          or d.entity = 'zz_demo' or d.dedupe_key like 'SBX:%')
     and d.id not in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null)
     and (d.dropbox_path is null
          or ((select max(synced_at) from public.dropbox_files) > now() - interval '36 hours'
              and not exists (select 1 from public.dropbox_files f where lower(f.path) = lower(d.dropbox_path)
                                and f.synced_at > now() - interval '36 hours')));
  c := c || jsonb_build_object('dropbox_demo_copies_still_in_dropbox_outside_the_list', coalesce((select jsonb_agg(d.dropbox_path order by d.dropbox_path)
         from public.doc_backups d
        where ((d.entity in ('customer', 'supplier', 'inquiry', 'quote', 'transaction') and d.entity_id in (select k from _dk))
               or d.entity = 'zz_demo' or d.dedupe_key like 'SBX:%')
          and d.id not in (select doc_backup_id from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null)
          and d.id not in (select id from _dgone)), '[]'::jsonb));
  c := public.fn_demo_purge_walk('public.doc_backups', 'id in (select id from _dgone)', 0, c);
  c := c || jsonb_build_object('storage_objects_listed', v_obj, 'dropbox_listed', v_dbx, 'purge_id', v_pid);

  -- the id-keyed and identity-keyed rows, while the ids are still known
  for r in select * from (values
    ('public.company_event', 'entity_type in (''customer'',''supplier'',''lead'',''inquiry'',''quote'',''transaction'',''refund'') and entity_id in (select k from _dk)'),
    ('public.agent_actions', 'target_table in (''customers'',''leads'',''suppliers'',''inquiries'',''quotes'',''transactions'') and target_id in (select k from _dk)'),
    ('public.doc_versions', 'entity_type in (''quote'',''rfq'',''inquiry'',''customer'',''lead'',''supplier'',''transaction'') and entity_id in (select k from _dk)'),
    ('public.documents', 'ref_table in (''inquiries'',''quotes'',''leads'',''customers'',''transactions'') and ref_id in (select k from _dk)'),
    ('public.quote_items', 'quote_id in (select id::text from _dq)'),
    ('public.notifications', 'public.fn_is_demo_email(to_email) or public.fn_is_demo_phone(to_phone) or lead_id in (select id from _dl) or inquiry_id in (select id from _di) or quote_id in (select id from _dq)'),
    ('public.email_verifications', 'public.fn_is_demo_email(email)'),
    ('public.phone_verifications', 'public.fn_is_demo_email(email) or public.fn_is_demo_phone(phone)'),
    ('public.inquiry_intake', 'customer_id in (select id from _dc) or public.fn_is_demo_email(email)'),
    ('public.drawing_redaction_runs', 'customer_id in (select id from _dc) or public.fn_is_demo_email(owner_email)'),
    ('public.cad_read_jobs', 'customer_id in (select id from _dc) or public.fn_is_demo_email(owner_email)'),
    ('public.support_case', 'public.fn_party_is_demo(party_kind, party_id)'),
    ('public.support_customer_profile', 'customer_id in (select id from _dc) or lead_id in (select id from _dl) or public.fn_is_demo_email(email)'),
    ('public.customer_support_duty_message', 'customer_id in (select id from _dc) or lead_id in (select id from _dl) or public.fn_is_demo_email(to_email)'),
    ('public.quote_reviews', 'inquiry_id in (select id from _di) or supplier_id in (select id from _dl) or public.fn_is_demo_email(owner_email)'),
    ('public.quote_spec_hold', 'quote_id in (select id from _dq) or inquiry_id in (select id from _di) or supplier_id in (select id from _dl)'),
    ('public.supplier_score', 'lead_id in (select id from _dl)'),
    ('public.supplier_document_cache', 'supplier_id in (select id from _dl)'),
    ('public.wa_conversation', 'public.fn_is_demo_phone(phone_e164) or public.fn_party_is_demo(party_kind, party_id)'),
    ('public.wa_messages', 'public.fn_is_demo_phone(wa_from) or public.fn_is_demo_phone(wa_to)'),
    ('public.wa_inbound_seen', 'public.fn_is_demo_phone(wa_from)'),
    ('public.wa_answer_log', 'public.fn_is_demo_phone(from_phone)'),
    ('public.sms_messages', 'public.fn_is_demo_phone(sms_from) or public.fn_is_demo_phone(sms_to)'),
    ('public.email_suppressions', 'public.fn_is_demo_email(email)'),
    ('public.pdpl_requests', 'public.fn_is_demo_email(email)'),
    ('public.pdpl_operator_log', 'public.fn_is_demo_email(email)'),
    ('public.rl_hits', 'k ~* ''' || EM || ''''),
    ('public.ai_rate_limit', 'bucket ~* ''' || EM || ''''),
    ('public.assistant_logs', 'user_agent ~* ''(qd-[a-z-]*probe|latency-probe)'''),
    ('public.ai_cost_log', 'e2e_run_tag is not null'),
    ('public.rehearsal_window', 'run_tag like ''qd\_run:%'''),
    ('public.marketing_outreach_message', 'is_demo'),
    ('public.marketing_prospect', 'is_demo'),
    ('public.marketing_post', 'is_demo'),
    ('public.marketing_campaign', 'is_demo'),
    ('public.marketing_article', 'is_demo'),
    ('public.marketing_ad_spend_day', 'is_demo'),
    ('public.ad_campaign_state', 'is_demo'),
    ('public.social_conversation', 'is_demo'),
    -- the entities, children first through the walk
    ('public.transactions', 'id in (select id from _dt)'),
    ('public.quotes', 'id in (select id from _dq)'),
    ('public.inquiries', 'id in (select id from _di)'),
    ('public.customers', 'id in (select id from _dc)'),
    ('public.leads', 'id in (select id from _dl)'),
    ('auth.users', 'id in (select id from _du)')
  ) t(rel, w) loop
    continue when to_regclass(r.rel) is null;
    c := public.fn_demo_purge_walk(r.rel::regclass, r.w, 0, c);
  end loop;

  -- THE GUARD: nothing that is not demo may have moved
  v_after := public.fn_demo_purge_real_counts();
  if v_after is distinct from v_before then
    raise exception 'DEMO PURGE REFUSED: a real row would change. before % after %', v_before, v_after
      using errcode = 'QD198';
  end if;
  return c || jsonb_build_object('real_counts_unchanged', v_after);
end $fn$;
revoke execute on function public.fn_demo_purge_run() from public, anon, authenticated;

-- p_apply false (default): the exact plan, rolled back. true: the purge, kept. Either refuses under the guard.
create or replace function public.fn_demo_purge(p_apply boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb;
begin
  if p_apply then return jsonb_build_object('mode', 'apply') || public.fn_demo_purge_run(); end if;
  begin
    v := public.fn_demo_purge_run();
    raise exception using errcode = 'QD199', message = v::text;
  exception when sqlstate 'QD199' then
    return jsonb_build_object('mode', 'plan') || sqlerrm::jsonb;
  end;
end $fn$;
revoke execute on function public.fn_demo_purge(boolean) from public, anon, authenticated;

-- verify-zero: nothing demo is left, and the Dropbox and storage queues of every demo purge are drained
create or replace function public.fn_demo_purge_verify()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'customers', (select count(*) from public.customers where is_demo),
    'leads', (select count(*) from public.leads where is_demo),
    'inquiries', (select count(*) from public.inquiries i where public.fn_inquiry_is_demo(i.id)),
    'auth_users', (select count(*) from auth.users u where public.fn_is_demo_email(u.email) or public.fn_is_demo_phone(u.phone)),
    'notifications', (select count(*) from public.notifications where public.fn_is_demo_email(to_email) or public.fn_is_demo_phone(to_phone)),
    'ai_cost_log_tagged', (select count(*) from public.ai_cost_log where e2e_run_tag is not null),
    'rehearsal_windows', (select count(*) from public.rehearsal_window where run_tag like 'qd\_run:%'),
    'doc_backups', (select count(*) from public.doc_backups where entity = 'zz_demo' or dedupe_key like 'SBX:%'),
    'marketing_demo', (select count(*) from public.marketing_prospect where is_demo) + (select count(*) from public.marketing_post where is_demo)
                    + (select count(*) from public.marketing_campaign where is_demo) + (select count(*) from public.marketing_outreach_message where is_demo),
    'social_demo', (select count(*) from public.social_conversation where is_demo),
    'storage_queue_open', (select count(*) from public.signup_purge_object o join public.signup_purge p on p.id = o.purge_id
                            where p.kind = 'demo_purge' and o.done_at is null),
    'dropbox_queue_open', (select count(*) from public.signup_purge_dropbox o join public.signup_purge p on p.id = o.purge_id
                            where p.kind = 'demo_purge' and o.done_at is null))
$fn$;
revoke execute on function public.fn_demo_purge_verify() from public, anon, authenticated;

-- ── 5. the seat duties that read a subject table without the predicate ─────────────────────────────────
create or replace function public.fn_support_case_idle_close()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days)
     and not public.fn_party_is_demo(party_kind, party_id);
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_ceo_pricing_monitor()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_week date := public.fn_ceo_review_week(); v_ev jsonb; v_quoted int; v_held bigint;
begin
  with q as (
    select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) as quotes
      from public.inquiries i where i.created_at > now() - interval '90 days' and not public.fn_inquiry_is_demo(i.id)
  )
  select jsonb_build_object(
    'pricing_config', (select to_jsonb(p) - 'id' - 'updated_at' from public.pricing_config p order by id limit 1),
    'requests_90d', (select count(*) from q),
    'quoted_requests_90d', (select count(*) from q where quotes > 0),
    'reveals_90d', (select count(*) from public.transactions t where t.revealed_at > now() - interval '90 days' and not public.fn_transaction_is_demo(t.id)),
    'refunds_90d', (select count(*) from public.transactions t where t.refund_requested_at > now() - interval '90 days' and not public.fn_transaction_is_demo(t.id)),
    'avg_quote_aed', (select round(avg(quote_amount), 2) from public.quotes x where x.created_at > now() - interval '90 days' and x.quote_amount > 0 and not public.fn_quote_is_demo(x.id)),
    'avg_reveal_fee_aed', (select round(avg(t.reveal_fee), 2) from public.transactions t where t.revealed_at > now() - interval '90 days' and not public.fn_transaction_is_demo(t.id)),
    'nonresponse_refunds', (select coalesce(sum(rv_nonresponse_refunds), 0) from public.leads where not is_demo),
    'supplier_fee_paying', (select count(*) from public.leads where registration_paid_at is not null and not is_demo),
    'competitors_on_file', (select count(*) from public.competitor),
    'unit_economics_last_month', public.fn_accountant_unit_economics((date_trunc('month', now() at time zone 'Asia/Dubai') - interval '1 month')::date))
  into v_ev;
  v_quoted := (v_ev->>'quoted_requests_90d')::int;
  insert into public.ceo_review (kind, period, facts, decision) values ('pricing_monitor', v_week, v_ev,
    case when v_quoted < 20 then 'insufficient_evidence' end)
  on conflict (kind, period) do update set facts = excluded.facts,
    decision = case when ceo_review.decided_at is null then excluded.decision else ceo_review.decision end;

  -- UNDER 20 QUOTED REQUESTS THE EVIDENCE CANNOT SUPPORT A PRICE CALL: recorded, not reasoned, not proposed.
  if v_quoted >= 20 and (select held_id from public.ceo_review where kind = 'pricing_monitor' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.pricing_monitor',
      'The weekly pricing review. From 90 days of evidence, decide whether our pricing (the supplier annual fee, the caps, '
        || 'the promotion window and the non-response charge) should stay as it is or whether an evidence-based change should '
        || 'be proposed to the founder. The 3 per cent reveal fee paid by the buyer is the founder''s fixed rule and is not in scope.',
      ('[{"id":"keep","meaning":"the evidence supports the current pricing"},'
      || '{"id":"propose_change","meaning":"the evidence supports proposing a specific change to the founder"}]')::jsonb,
      v_ev, jsonb_build_object('kind', 'pricing_monitor', 'period', v_week), 'ceo_pricing:' || v_week);
    update public.reasoning_held_question
       set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
             jsonb_build_object('key', 'proposal', 'question', 'the exact change proposed, if any, with the figure'),
             jsonb_build_object('key', 'evidence', 'question', 'the measured evidence it rests on')))
     where id = v_held;
    -- ONE CALL PER REPORT (24 Sep 2026, it_engineer): normal stakes, so think() runs no second-family verify on it.
    update public.reasoning_held_question set request = request || '{"stakes":"normal"}'::jsonb where id = v_held;
    update public.ceo_review set held_id = v_held where kind = 'pricing_monitor' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'quoted_requests_90d', v_quoted, 'reasoning_filed', v_held is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_accountant_ubo_rescreen()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_runs bigint[]; v_owners int; v_new int := 0; v_missing int; v_stale int; v_screen jsonb; h record;
begin
  select array_agg(id order by id) into v_runs
    from (select distinct on (source) id from public.screening_run where status = 'ok'
           order by source, fetched_at desc, id desc) x;
  if v_runs is null then raise exception 'no sanctions list has ever been fetched successfully (screening_run has no ok row)'; end if;

  -- the suppliers in scope are exactly the ones fn_supplier_sanctions_screen screens (same demo split)
  create temp table if not exists tmp_ubo_scope (lead_id bigint primary key) on commit drop;
  truncate tmp_ubo_scope;
  insert into tmp_ubo_scope
  select l.id from public.leads l
   where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
     and l.is_demo = v_fx;   -- the shared marker (founder ruling 1199): fixtures only under qd.duty_fixtures, never otherwise

  select count(*) into v_owners from public.supplier_beneficial_owner o join tmp_ubo_scope s on s.lead_id = o.lead_id;

  for h in
    select o.lead_id, o.full_name, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when x.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when x.norm = e.name_norm then 1.0
                else round(least(cardinality(x.toks), cardinality(e.tokens))::numeric / greatest(cardinality(x.toks), cardinality(e.tokens), 1), 2) end as score
      from public.supplier_beneficial_owner o
      join tmp_ubo_scope s on s.lead_id = o.lead_id
      cross join lateral (select public.fn_screening_normalise(o.full_name) as norm, public.fn_screening_tokens(o.full_name) as toks) x
      join public.screening_entry e
        on e.run_id = any(v_runs)
       and ((x.norm = e.name_norm and length(x.norm) >= 6)
         or (cardinality(x.toks) >= 2 and cardinality(e.tokens) >= 2 and (x.toks <@ e.tokens or e.tokens <@ x.toks)))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, 'beneficial_owner', h.full_name, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- the existing screen files the CEO decision and the sales_engineer hold for every open hit of these runs
  v_screen := public.fn_accountant_sanctions_rescreen();

  select count(*) filter (where not exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id)),
         count(*) filter (where exists (select 1 from public.supplier_beneficial_owner o where o.lead_id = s.lead_id
                                          and coalesce(o.verified_at, o.declared_at) < now() - interval '365 days'))
    into v_missing, v_stale from tmp_ubo_scope s;

  return jsonb_build_object('owners_screened', v_owners, 'owner_hits_new', v_new,
    'suppliers_without_owner_on_record', v_missing, 'suppliers_with_owner_unverified_a_year', v_stale,
    'screen', v_screen - 'sources' - 'runs' - 'oldest_list');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_comparison_kpi(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with rep as (
  select c.inquiry_id, min(c.created_at) as reported_at
    from public.qd_compare_cache c
   where not (c.analysis ? '__failed')
     and not exists (select 1 from public.inquiries di where di.id::text = c.inquiry_id and public.fn_inquiry_is_demo(di.id))
     and c.created_at >= now() - make_interval(days => greatest(1, p_days))
   group by c.inquiry_id
),
q as (
  select r.inquiry_id,
         count(*) filter (where coalesce(qt.price_ex_vat, qt.quote_amount) is not null
                            and nullif(btrim(qt.lead_time), '') is not null
                            and nullif(btrim(qt.validity), '') is not null
                            and nullif(btrim(qt.warranty), '') is not null
                            and nullif(btrim(qt.payment_terms), '') is not null) as complete_n,
         count(*) filter (where nullif(btrim(qt.exclusions), '') is not null) as excl_n
    from rep r
    left join public.quotes qt on qt.inquiry_id::text = r.inquiry_id
   group by r.inquiry_id
),
t as (
  select r.inquiry_id, extract(epoch from (r.reported_at - i.created_at)) / 3600.0 as hours,
         q.complete_n, q.excl_n
    from rep r
    join q on q.inquiry_id = r.inquiry_id
    left join public.inquiries i on i.id::text = r.inquiry_id
)
select jsonb_build_object(
  'window_days', greatest(1, p_days),
  'reports', count(*),
  'hours_median', round((percentile_cont(0.5) within group (order by hours))::numeric, 1),
  'hours_p90', round((percentile_cont(0.9) within group (order by hours))::numeric, 1),
  'share_3plus_complete', case when count(*) > 0 then round(count(*) filter (where complete_n >= 3)::numeric / count(*), 3) end,
  'reports_with_exclusions', count(*) filter (where excl_n > 0),
  'quotes_with_exclusions', coalesce(sum(excl_n), 0))
from t;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_nudged int := 0; v_to text; v_stages jsonb; v_inv jsonb;
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where (l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null) and not l.is_demo
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE 'invited' STAGE (#1007): day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id and not l.is_demo
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    -- ENGLISH ONLY (#1007, review of 29 Sep 2026): #1065's body kept an Arabic branch behind a flag fixed to English; it is
    -- removed, not switched off. A matched supplier is registered, so the link is the English portal (no claim token).
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en',
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', 'Customer requests are waiting for your quotation',
      -- #1070's greeting guard (#1007): an Arabic-script company name is not written into an English letter
      'body', 'Dear ' || coalesce(nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), ''), 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: '
          || coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
          || '/en/portal' || chr(10) || chr(10)
          || 'QuotesDone')));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged, 'invite_nudges', v_inv);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_marketing_reputation()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_link text := nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), '');
  r record; v_asked int := 0; v_waiting int := 0; v_ar boolean;
begin
  insert into public.company_review_ask (customer_id, transaction_id, status)
  select k.customer_id, k.transaction_id, 'waiting_link' from public.fn_marketing_review_ask_candidates() k
  on conflict (transaction_id) do nothing;

  if v_link is null then
    select count(*) into v_waiting from public.company_review_ask where status = 'waiting_link';
    if v_waiting > 0 then
      perform public.fn_it_engineer_finding_upsert('reputation:no_public_review_link',
        v_waiting || ' customer job(s) are waiting to be asked for a public review, and no review link is configured',
        'app_secrets public_review_url', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile or directory review link to use'], 'marketing');
    end if;
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a public review link is configured'
     where issue_key = 'reputation:no_public_review_link' and closed_at is null;
    for r in select a.id, a.customer_id, coalesce(a.transaction_id::text, a.customer_id::text) as job,
                    c.full_name, lower(btrim(c.email)) as email, c.locale
               from public.company_review_ask a join public.customers c on c.id = a.customer_id and not c.is_demo
              where a.status = 'waiting_link' and a.created_at > now() - interval '60 days'
                and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
              order by a.id limit 50 loop
      v_ar := r.locale = 'ar';
      -- customer_support is the only seat that addresses a customer; the ask is marketing's, the send is support's.
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'public_review_ask', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', r.email,
        'to_role', 'customer', 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'public_review_ask:' || r.job,
        'subject', case when v_ar then 'هل تشاركون تجربتكم مع QuotesDone؟' else 'Would you share your experience of QuotesDone?' end,
        'body', case when v_ar then
            'عزيزنا ' || coalesce(nullif(btrim(r.full_name), ''), 'العميل') || '،' || chr(10) || chr(10)
            || 'شكرًا لاستخدامكم QuotesDone. نرحب برأيكم الصريح علنًا، أيًّا كان، فذلك يساعد غيركم على اختيار موردين موثوقين: '
            || v_link || chr(10) || chr(10) || 'مع خالص الشكر والتقدير،'
          else
            'Dear ' || coalesce(nullif(btrim(r.full_name), ''), 'customer') || ',' || chr(10) || chr(10)
            || 'Thank you for using QuotesDone. If you have a minute, we would welcome your honest public review, '
            || 'whatever your experience; it helps other companies find reliable suppliers: ' || v_link
            || chr(10) || chr(10) || 'QuotesDone' end)));
      update public.company_review_ask set status = 'asked', asked_at = now() where id = r.id;
      v_asked := v_asked + 1;
    end loop;
  end if;

  -- The snapshot measures reputation; it is written after the asks and decides none of them.
  insert into public.company_reputation_snapshot as s (day, reviews, avg_rating, low_ratings_30d, asks_sent, asks_waiting)
  select (now() at time zone 'Asia/Dubai')::date, count(*), round(avg(rating)::numeric, 2),
         count(*) filter (where rating <= 2 and created_at > now() - interval '30 days'),
         (select count(*) from public.company_review_ask where status = 'asked'),
         (select count(*) from public.company_review_ask where status = 'waiting_link')
    from public.reviews
  on conflict (day) do update set reviews = excluded.reviews, avg_rating = excluded.avg_rating, low_ratings_30d = excluded.low_ratings_30d,
    asks_sent = excluded.asks_sent, asks_waiting = excluded.asks_waiting;
  return jsonb_build_object('asked', v_asked, 'waiting_for_link', v_link is null,
    'snapshot', (select to_jsonb(s) from public.company_reputation_snapshot s where day = (now() at time zone 'Asia/Dubai')::date));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_performance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_refreshed int; v_scored int; v_null int;
begin
  v_refreshed := public.fn_supplier_score_refresh();
  -- WEIGHTED OVER WHAT WAS MEASURED: reliability 0.5, the customers' rating 0.3, disputes 0.2 (only once a customer
  -- has reviewed him). A part that does not exist is left out of both sides of the average, never counted as zero.
  -- Only a supplier whose lead still exists is scored: supplier_performance keys on leads(id).
  with parts as (
    select s.lead_id,
           case when s.reliability is not null then least(1, greatest(0, s.reliability / 100.0)) end as rel,
           case when s.quality_rating is not null then least(1, greatest(0, s.quality_rating / 100.0)) end as qual,
           case when coalesce(r.review_count, 0) > 0 then 1 - least(1, greatest(0, coalesce(r.dispute_rate_pct, 0) / 100.0)) end as disp
      from public.supplier_score s
      join public.leads l on l.id = s.lead_id and not l.is_demo
      left join public.supplier_reputation r on r.supplier_id = s.lead_id
     where s.reliability is not null or s.quality_rating is not null or coalesce(r.review_count, 0) > 0
  )
  insert into public.supplier_performance as p (lead_id, score, components, computed_at)
  select lead_id,
         round((coalesce(0.5 * rel, 0) + coalesce(0.3 * qual, 0) + coalesce(0.2 * disp, 0))
               / nullif((case when rel is not null then 0.5 else 0 end) + (case when qual is not null then 0.3 else 0 end)
                        + (case when disp is not null then 0.2 else 0 end), 0), 3),
         jsonb_build_object('reliability', rel, 'rating', qual, 'disputes', disp), now()
    from parts
  on conflict (lead_id) do update set score = excluded.score, components = excluded.components, computed_at = now();
  get diagnostics v_scored = row_count;
  -- a supplier who lost every measurement is unmeasured again, not scored on stale numbers
  delete from public.supplier_performance p where p.computed_at < now() - interval '1 minute';
  get diagnostics v_null = row_count;
  return jsonb_build_object('score_rows_refreshed', v_refreshed, 'scored', v_scored, 'dropped_unmeasured', v_null);
end $function$;

-- VERDICT (reads only: predicates and pg_proc. Applying this file never runs the purge, not even rolled back: it would lock auth.users).
select case
  when to_regproc('public.fn_demo_purge') is not null and to_regproc('public.fn_demo_purge_verify') is not null
   and public.fn_party_is_demo('unknown', 'qd-x@example.invalid')
   and 'ZZ Demolition LLC' !~* '^ZZ DEMO([^a-z]|$)' and 'ZZ DEMO — x' ~* '^ZZ DEMO([^a-z]|$)'
   and (select count(*) from pg_attrdef d join pg_attribute t on t.attrelid = d.adrelid and t.attnum = d.adnum
         where t.attname = 'is_demo' and d.adrelid in ('public.leads'::regclass, 'public.customers'::regclass, 'public.social_conversation'::regclass)
           and pg_get_expr(d.adbin, d.adrelid) like '%([^a-z]|$)%') = 3
   and not public.fn_customer_is_demo(gen_random_uuid()) and not public.fn_supplier_is_demo(-1)
   and not public.fn_party_is_demo('customer', 'not-a-uuid') and not public.fn_party_is_demo('unknown', '1')
   and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'is_demo'
          and proname in ('fn_support_case_idle_close', 'fn_ceo_pricing_monitor', 'fn_accountant_ubo_rescreen',
                          'fn_sales_engineer_comparison_kpi', 'fn_sales_engineer_supplier_onboarding',
                          'fn_marketing_reputation', 'fn_sales_engineer_supplier_performance')) = 7
  then 'PROBE OK: the predicates answer and the seven duties carry them (the purge plan runs only in the _probe file, never at apply)'
  else 'PROBE FAILED: a predicate or a duty routine is not what this file defines' end as verdict;

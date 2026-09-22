-- THE IT ENGINEER KNOWS WHAT SHOULD BE BACKED UP, AND CLOSES THE LOOP ITSELF.
--
-- Assigned: it_engineer (the expected list, the three comparisons, the re-check, the close, the
-- escalation, the daily confirmation), with sales_engineer (the refile) and ceo (instructions back,
-- the re-check of the remediation, the founder only for causes outside the company). 14 Sep 2026.
--
-- The founder, 14 Sep 2026 (relayed by the coordinating session): "i think the IT agent need to check
-- such details yea?" -- and the requirement built here: the IT engineer computes what SHOULD be in
-- the backup itself, compares it three ways, hands every finding to the sales engineer in ONE
-- handoff, re-checks each file itself, and is the only seat that can close it; still failing after
-- two refiles or 48 hours goes to the CEO with the evidence; only a cause outside the company
-- (Dropbox auth, storage full, plan/billing) reaches the founder; silence of the check is an alarm.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   doc_backups     pending 121 / done 208 / abandoned 26 (the conversation archive had just queued
--                   115 correspondence PDFs); fn_backup_coverage ok, conversation retention total 0.
--   real owners     0 real qualifying suppliers, 1 real customer, 0 inquiries, 0 transactions with
--                   an invoice document; 115 real conversation messages, 115 archived, 115 with a row.
--   storage         the four buckets the enqueue files from hold 76 objects; 37 have no doc_backups
--                   row, and almost all of them belong to deleted test suppliers/customers or to no
--                   one (supplier-docs/inbound/unknown, legal/). So "expected" is NOT "every object
--                   in the bucket": an object is expected when it resolves to a REAL owner (a
--                   non-demo lead, customer, inquiry of a real customer, or a transaction), by the
--                   column that names it or by the owner id in its path. An object whose owner id is
--                   a real entity but that no column names -- a file sales never queued -- is
--                   therefore visible, which is the point.
--   founder path    fn_notify_founder(p_kind) with founder_mail_policy kind 'backup_failed_after_retry'
--                   (allowed_to_email, owner_role it_engineer). The CEO calls it only for an external
--                   cause and never when every file in the case is ZZ DEMO.
--
-- THE LOOP:
--   daily   fn_dropbox_reconcile_due is due once per Asia/Dubai day. dropbox_backup mode 'reconcile'
--           reads files/get_metadata for up to 40 done rows never confirmed, plus -- once per ISO
--           week -- 20 random older confirmed rows, and hands the outcomes to fn_it_backup_check.
--   check   fn_it_backup_check compares (1) expected vs doc_backups -> never_queued (24h grace);
--           (2) doc_backups vs Dropbox -> missing_in_dropbox / mismatch; (3) rows the uploader gave up
--           on -> upload_failed. Every file not already in an open refile goes into ONE
--           'backup.refile' handoff to the sales engineer, and the run is logged as the daily check.
--   refile  fn_sales_engineer_refiles_backup: requeue, or enqueue, or file a row itself; replies with
--           what it did and WAITS. It cannot close: trg_backup_refile_only_it_engineer_closes refuses
--           a close unless the it_engineer's re-check is the caller.
--   recheck fn_it_backup_recheck: each file must be done AND confirmed after the refile. All good ->
--           it closes. A file that failed again -> a second refile. After two refiles, or 48 hours ->
--           fn_support_report_to_ceo from it_engineer with the file list, attempts and errors.
--   ceo     fn_ceo_backup_escalation_decide accepts the report and either sends instructions back as a
--           'backup.remediate' handoff to the sales engineer (the refund rejection-loop pattern) or,
--           for an external cause only, notifies the founder in plain words. fn_ceo_backup_escalation_sweep
--           re-checks: when the it_engineer has closed the remediation, the report is completed.
--   confirm fn_dropbox_backup_daily_report (19:00 Dubai): expected / backed up / verified / pending /
--           failed / open handoffs. fn_backup_watch raises a serious report to the CEO when the daily
--           check itself has not run for 26 hours.
--
-- DEMO ROWS: entity 'zz_demo'. They are left out of every global scan, the sample, the summary and
-- (dropbox_backup v7) the uploader, so proving the loop on them needs no Dropbox write.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql --apply --ddl

-- ── 1. THE CONVERSATIONS: backup.remediate joins backup.refile ────────────────────────────────────
-- Mirrored in supabase/functions/_shared/payment_handoffs.ts.
create or replace function public.fn_seat_handoff_types()
returns table(type text, from_seat text, to_seat text, meaning text)
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  values
    ('reveal.paid',              'accountant',       'sales_engineer',   'A reveal charge settled at Stripe: tell the customer the contact is released and the supplier that they were revealed.'),
    ('payment.failed',           'accountant',       'sales_engineer',   'A reveal checkout expired or failed: tell the customer nothing was charged and how to try again.'),
    ('payment.received',         'accountant',       'sales_engineer',   'A supplier paid an outstanding charge or the registration fee: confirm it to them.'),
    ('refund.request_checked',   'accountant',       'sales_engineer',   'The books checked a refund request: acknowledge it to the customer.'),
    ('refund.paid',              'accountant',       'sales_engineer',   'A refund settled: tell the customer what came back and when the bank shows it.'),
    ('refund.declined',          'accountant',       'sales_engineer',   'A refund was declined: tell the customer why.'),
    ('refund.in_progress',       'accountant',       'sales_engineer',   'A refund is approved but not settled after a retry: tell the customer it is in progress.'),
    ('nonresponse.charge_raised','accountant',       'sales_engineer',   'The non-response charge was raised: tell the supplier the figures.'),
    ('charge.corrected',         'accountant',       'sales_engineer',   'A charge already sent was wrong: send a correction to whoever got the original.'),
    ('subscription.due',         'accountant',       'sales_engineer',   'The yearly registration fee fell due: tell the supplier.'),
    ('billing.answer',           'accountant',       'sales_engineer',   'The books answered a billing question: relay it.'),
    ('charge.dispute_answer',    'accountant',       'sales_engineer',   'The books checked a disputed charge: relay the result to the supplier.'),
    ('refund.requested',         'sales_engineer',   'accountant',       'A customer asked for a refund in the portal: check the money behind it.'),
    ('billing.question',         'sales_engineer',   'accountant',       'A customer or supplier asked about a charge, an invoice or a refund: read the books.'),
    ('charge.disputed',          'sales_engineer',   'accountant',       'A supplier disputed a charge: recompute it from the refund record.'),
    ('refund.remediate',         'ceo',              'accountant',       'The CEO refused approval on a money check the accountant owns: fix it and report back.'),
    ('refund.remediate',         'ceo',              'sales_engineer',   'The CEO refused approval on a ladder check the sales engineer owns: fix it and report back.'),
    ('incident.fix',             'ceo',              'accountant',       'Post-payment re-verification found a mismatch: apply the fix the playbook names.'),
    ('delivery.request',         'sales_engineer',   'customer_support', 'Deliver these words to a customer or supplier through the outbox, and watch for the reply when asked.'),
    ('delivery.request',         'ceo',              'customer_support', 'Deliver this summary to the founder on his command channel.'),
    ('delivery.request',         'accountant',       'customer_support', 'Deliver this money exception to the founder on his command channel.'),
    ('delivery.result',          'customer_support', 'sales_engineer',   'What came back: proof the supplier responded, or confirmation that nothing did.'),
    ('backup.refile',            'it_engineer',      'sales_engineer',   'The IT engineer found backed-up documents missing, changed, failed or never queued: file each again. Only the IT engineer closes it, once each new copy is verified.'),
    ('backup.remediate',         'ceo',              'sales_engineer',   'The CEO read the IT engineer''s escalation and sends instructions back: re-file these documents or record why they cannot be. The IT engineer re-checks and closes.')
$fn$;

-- ── 2. WHAT SHOULD BE BACKED UP, COMPUTED FROM THE SOURCES ───────────────────────────────────────
-- Never from doc_backups and never by running the enqueue.
create or replace function public.fn_it_backup_expected()
returns table(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with rl as (select * from public.leads where not coalesce(is_demo, false)),
       rc as (select * from public.customers where not coalesce(is_demo, false)),
       ri as (select i.* from public.inquiries i join rc on rc.id = i.customer_id)
  select 'obj:' || o.bucket_id || ':' || o.name, 'storage', o.bucket_id, o.name, null::text, null::text, x.owner, o.created_at
    from storage.objects o
    cross join lateral (select case
      when o.bucket_id = 'supplier-docs' then (select 'supplier:' || l.id from rl l
             where l.id::text = split_part(o.name, '/', 2)
                or o.name in (l.license_doc_path, l.iban_doc_path, l.egr_doc_path, l.insurance_doc_path, l.vat_doc_path,
                              l.iso_doc_path, l.manufacturer_auth_doc_path, l.company_profile_doc_path)
                or o.name = any(coalesce(l.catalog_doc_paths, '{}')) limit 1)
      when o.bucket_id = 'signed-terms' then coalesce(
             (select 'customer:' || c.id from rc c where c.signed_terms_path = o.name limit 1),
             (select 'supplier:' || l.id from rl l where l.signed_terms_path = o.name limit 1))
      when o.bucket_id = 'drawing-files' then (select 'inquiry:' || i.id from ri i
             where i.id::text = split_part(o.name, '/', 2) or i.drawing_file_path = o.name limit 1)
      when o.bucket_id = 'finance-docs' then (select 'transaction:' || t.id from public.transactions t where t.doc_path = o.name limit 1)
    end as owner) x
   where o.bucket_id in ('supplier-docs', 'signed-terms', 'drawing-files', 'finance-docs')
     and x.owner is not null and o.name !~* 'zz[_ -]?demo'
  union all
  -- a Stripe invoice the transaction names but storage no longer holds is still expected
  select 'obj:finance-docs:' || t.doc_path, 'invoice', 'finance-docs', t.doc_path, null, null, 'transaction:' || t.id, t.revealed_at
    from public.transactions t
    -- transactions carries no is_demo of its own: a sale is demo when either party is (review of
    -- #628). Without this, a purged demo invoice would read never_queued forever and escalate.
    left join public.customers tc on tc.id = t.customer_id
    left join public.leads tl on tl.id = t.supplier_id
   where t.doc_path is not null
     and not coalesce(tc.is_demo, false) and not coalesce(tl.is_demo, false)
     and coalesce(tc.email, '') !~* 'example\.invalid' and coalesce(tl.email, '') !~* 'example\.invalid'
     and not exists (select 1 from storage.objects o where o.bucket_id = 'finance-docs' and o.name = t.doc_path)
  union all
  select 'msg:' || m.source_table || ':' || m.source_id, 'conversation', c.pdf_bucket, c.pdf_path, null, null,
         coalesce(m.party_kind || ':' || m.party_id, 'company'), m.occurred_at
    from public.v_conversation_message m
    left join public.conversation_archive c on c.source_table = m.source_table and c.source_id = m.source_id
   where not m.is_demo
  union all
  select 'gen:supplier_details:' || l.id, 'generated', null, null, 'supplier_details', l.id::text, 'supplier:' || l.id, l.created_at
    from rl l
   where l.approved_at is not null or l.registration_submitted_at is not null or l.signed_terms_path is not null
      or l.company_profile_doc_path is not null or l.license_doc_path is not null or coalesce(l.claimed, false)
  union all
  select 'gen:customer_details:' || c.id, 'generated', null, null, 'customer_details', c.id::text, 'customer:' || c.id, c.created_at from rc c
  union all
  select 'gen:inquiry_summary:' || i.id, 'generated', null, null, 'inquiry_summary', i.id::text, 'inquiry:' || i.id, i.created_at from ri i;
$fn$;
revoke execute on function public.fn_it_backup_expected() from public, anon, authenticated;

-- The lateral join below looks a row up by (bucket, path) or by (gen_kind, gen_ref) for every
-- expected item (review of #628). (bucket, path) is already indexed by the unique constraint
-- doc_backups_bucket_path_key; (gen_kind, gen_ref) was not.
create index if not exists doc_backups_gen_kind_ref_idx on public.doc_backups (gen_kind, gen_ref);

-- Each expected item with the doc_backups row that covers it, if any.
create or replace function public.fn_it_backup_expected_status()
returns table(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamptz,
              doc_backup_id bigint, status text, attempts int, verified_at timestamptz, error text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select e.*, d.id, d.status, d.attempts, d.verified_at, d.error
    from public.fn_it_backup_expected() e
    left join lateral (
      select * from public.doc_backups d
       where (e.kind <> 'generated' and e.bucket is not null and d.bucket = e.bucket and d.path = e.path)
          or (e.kind = 'generated' and d.gen_kind = e.gen_kind and d.gen_ref = e.gen_ref)
       order by (d.status = 'done') desc, d.id desc limit 1) d on true;
$fn$;
revoke execute on function public.fn_it_backup_expected_status() from public, anon, authenticated;

-- ── 3. THE DAILY / WEEKLY DROPBOX SAMPLE ─────────────────────────────────────────────────────────
create or replace function public.fn_dropbox_weekly_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs r
                      where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check' and r.counts->>'weekly' = 'true'
                        and to_char(r.started_at at time zone 'Asia/Dubai', 'IYYY-IW') = to_char(now() at time zone 'Asia/Dubai', 'IYYY-IW'));
$fn$;
revoke execute on function public.fn_dropbox_weekly_due() from public, anon, authenticated;

create or replace function public.fn_dropbox_reconcile_due()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'due', not exists (select 1 from public.agent_runs r
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check' and r.status in ('ok', 'warn')
                          and (r.started_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date)
       and not exists (select 1 from public.agent_runs r
                        where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_daily_check'
                          and r.status = 'error' and r.started_at > now() - interval '6 hours'),
    'day', (now() at time zone 'Asia/Dubai')::date,
    'weekly_due', public.fn_dropbox_weekly_due());
$fn$;


revoke execute on function public.fn_dropbox_reconcile_due() from public, anon, authenticated;

-- Return type changes (adds `why`), so the old shape is dropped first; its ACL is re-closed below.
drop function if exists public.fn_dropbox_reconcile_sample(integer);
create function public.fn_dropbox_reconcile_sample(p_n integer default 20)
returns table(id bigint, dropbox_path text, bucket text, path text, bytes bigint, dropbox_content_hash text, why text)
language sql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
  (select d.id, d.dropbox_path, d.bucket, d.path, d.bytes, d.dropbox_content_hash, 'new'
     from public.doc_backups d
    where d.status = 'done' and d.verified_at is null and d.dropbox_path is not null and d.entity <> 'zz_demo'
    order by d.backed_up_at desc nulls last limit 40)
  union all
  (select d.id, d.dropbox_path, d.bucket, d.path, d.bytes, d.dropbox_content_hash, 'weekly'
     from public.doc_backups d
    where public.fn_dropbox_weekly_due()
      and d.status = 'done' and d.verified_at is not null and d.dropbox_path is not null and d.entity <> 'zz_demo'
    order by random() limit greatest(1, least(coalesce(p_n, 20), 200)));
$fn$;
revoke execute on function public.fn_dropbox_reconcile_sample(integer) from public, anon, authenticated;

-- ── 4. THE CHECK: three comparisons, ONE handoff ─────────────────────────────────────────────────
-- p_job 'dropbox_daily_check' (the scheduled run: global scans + the Dropbox results) or 'targeted'
-- (only the rows named in p_results; never counts as the daily check).
-- WHAT THE DAILY CHECK ACTUALLY DID, AND WHAT IS STILL OPEN (22 Sep 2026, it_engineer, UNSOLVED-06).
-- MEASURED: agent_runs it_engineer job dropbox_daily_check ran 19 Sep 21:15:54Z, failed at 21 Sep 23:31:18Z
-- and 22 Sep 01:10:51Z with "apply canceling statement due to statement timeout", and ran again on
-- 22 Sep 12:00:59Z (20 read, 20 confirmed) — so it did NOT stop on 19 Sep, as the 22 Sep audit read it.
-- pg_stat_statements puts the expected-vs-live comparison this routine runs at 5,420 ms and 5,333 ms:
-- inside the caller's 8 s with no room for a slower moment. A `SET statement_timeout` on this function was
-- tried and removed — a timeout armed before the statement starts cannot be extended from inside it
-- (proved on production: 3 s armed, 30 s set locally, pg_sleep(6) cancelled with 57014). Making this fit
-- means bounding the comparison, which is its own change with its own measurement. Stated, not papered over.
create or replace function public.fn_it_backup_check(p_results jsonb, p_job text default 'dropbox_daily_check', p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r jsonb; v_id bigint; v_out text; f jsonb := '[]'::jsonb; x record; d public.doc_backups;
  n_ok int := 0; n_unver int := 0; n_err int := 0; v_h bigint; v_status text; c jsonb;
  v_weekly boolean := exists (select 1 from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) e where e->>'why' = 'weekly');
begin
  if p_error is not null then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'error', jsonb_build_object('job', p_job, 'stage', 'fatal'),
            left('The IT engineer''s Dropbox check did not run: ' || p_error || '. Retried after 6 hours.', 500), now(), now());
    return jsonb_build_object('ok', false, 'error', p_error);
  end if;

  -- (2) doc_backups vs Dropbox
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    v_id := (r->>'id')::bigint; v_out := r->>'outcome';
    if v_out = 'ok' then
      update public.doc_backups set dropbox_content_hash = r->>'hash', dropbox_size = (r->>'size')::bigint, verified_at = now()
       where id = v_id and status = 'done';
      n_ok := n_ok + 1;
    elsif v_out in ('missing', 'changed') then
      update public.doc_backups set verified_at = null,
             error = case when v_out = 'missing' then 'it_engineer: missing in Dropbox' else 'it_engineer: size/content_hash in Dropbox differs' end
       where id = v_id returning * into d;
      if found then
        f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', case when v_out = 'missing' then 'missing_in_dropbox' else 'mismatch' end,
               'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'bucket', d.bucket, 'path', d.path, 'demo', d.entity = 'zz_demo');
      end if;
    elsif v_out = 'unverifiable' then n_unver := n_unver + 1;
    else n_err := n_err + 1;
    end if;
  end loop;

  if p_job = 'dropbox_daily_check' then
    -- (1) expected vs doc_backups: never queued, past a 24-hour grace
    for x in select * from public.fn_it_backup_expected_status() s
              where s.doc_backup_id is null and s.since < now() - interval '24 hours' loop
      f := f || jsonb_build_object('key', 'exp:' || x.item_key, 'reason', 'never_queued', 'item_key', x.item_key, 'kind', x.kind,
             'bucket', x.bucket, 'path', x.path, 'gen_kind', x.gen_kind, 'gen_ref', x.gen_ref, 'owner', x.owner, 'demo', false);
    end loop;
    -- (3) the uploader gave up
    for d in select * from public.doc_backups b
              where b.entity <> 'zz_demo' and ((b.status = 'error' and b.attempts >= 5) or b.status = 'skipped_large') loop
      f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', 'upload_failed', 'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path,
             'bucket', d.bucket, 'path', d.path, 'error', d.error, 'demo', false);
    end loop;
  end if;

  -- a file already in an open refile or remediation is not handed over twice
  select coalesce(jsonb_agg(e), '[]'::jsonb) into f
    from jsonb_array_elements(f) e
   where not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' in ('backup.refile', 'backup.remediate')
                        and exists (select 1 from jsonb_array_elements(a.detail->'files') g where g->>'key' = e->>'key'));

  if jsonb_array_length(f) > 0 then
    v_h := public.fn_seat_handoff('it_engineer', 'sales_engineer', 'backup.refile', 'doc_backups',
             'check:' || p_job || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
             jsonb_build_object('files', f, 'job', p_job, 'refile_attempts', 0));
  end if;

  c := jsonb_build_object('job', p_job, 'weekly', v_weekly, 'checked', jsonb_array_length(coalesce(p_results, '[]'::jsonb)),
         'confirmed', n_ok, 'unverifiable', n_unver, 'read_errors', n_err, 'findings', jsonb_array_length(f),
         'by_reason', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select e->>'reason' k, count(*) n from jsonb_array_elements(f) e group by 1) z),
         'handoff', v_h);
  v_status := case when jsonb_array_length(f) + n_err > 0 then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, c,
          left('IT engineer Dropbox check (' || p_job || '): ' || (c->>'checked') || ' read in Dropbox, ' || n_ok || ' confirmed, '
               || jsonb_array_length(f) || ' finding(s) ' || (c->>'by_reason')
               || case when v_h is not null then ', handed to the sales engineer as handoff ' || v_h else '' end || '.', 500),
          now(), now());
  return c || jsonb_build_object('status', v_status);
end $fn$;
revoke execute on function public.fn_it_backup_check(jsonb, text, text) from public, anon, authenticated;

-- The name dropbox_backup v6 calls; now the daily check.
create or replace function public.fn_dropbox_reconcile_apply(p_results jsonb, p_error text default null)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_it_backup_check(p_results, 'dropbox_daily_check', p_error);
$fn$;

-- ── 5. THE REFILE, AND WHO MAY CLOSE IT ──────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_refiles_backup(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; fin jsonb; fout jsonb := '[]'::jsonb; v_att int; v_row bigint; n int; v_out text;
  v_enq boolean := false; s record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_att := coalesce((a.detail->>'refile_attempts')::int, 0) + 1;
  fin := coalesce(a.detail->'files',
           jsonb_build_array(jsonb_build_object('key', 'db:' || (a.detail->>'doc_backup_id'), 'reason', a.detail->>'reason',
                                                'doc_backup_id', (a.detail->>'doc_backup_id')::bigint)));
  for s in select e from jsonb_array_elements(fin) e loop
    v_row := (s.e->>'doc_backup_id')::bigint; v_out := null;
    if v_row is null then
      -- never queued: the enqueue first, then a row of our own for what it does not cover
      if not v_enq then perform public.fn_enqueue_doc_backups(); v_enq := true; end if;
      select x.doc_backup_id into v_row from public.fn_it_backup_expected_status() x where x.item_key = s.e->>'item_key';
      if v_row is null and s.e->>'bucket' is not null and s.e->>'kind' <> 'conversation' then
        insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', s.e->>'bucket', s.e->>'path',
                regexp_replace(s.e->>'path', '^.*/', ''), '/QuotesDone Backup/Refiled/' || (s.e->>'bucket') || '/' || (s.e->>'path'),
                'storage', 'REFILE:' || (s.e->>'bucket') || ':' || (s.e->>'path'))
        on conflict do nothing returning id into v_row;
      elsif v_row is null and s.e->>'kind' = 'generated' then
        insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
        values (split_part(s.e->>'owner', ':', 1), split_part(s.e->>'owner', ':', 2), 'Refiled', 'generated', s.e->>'gen_kind', s.e->>'gen_ref',
                '/QuotesDone Backup/Refiled/' || (s.e->>'gen_kind') || '/' || (s.e->>'gen_ref') || '.pdf', 'REFILE:' || (s.e->>'item_key'))
        on conflict do nothing returning id into v_row;
      end if;
      v_out := case when v_row is null then 'cannot_refile: no source to file from' else 'queued' end;
    end if;
    if v_row is not null and v_out is null then
      update public.doc_backups
         set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
             error = left('refile ' || v_att || ': ' || coalesce(s.e->>'reason', 'requested') || ' (handoff ' || p_id || ')', 300)
       where id = v_row and status <> 'abandoned';
      get diagnostics n = row_count;
      v_out := case when n = 1 then 'requeued' else 'cannot_refile: row missing or abandoned' end;
    end if;
    fout := fout || (s.e || jsonb_build_object('doc_backup_id', v_row, 'refile', v_out));
  end loop;
  update public.agent_actions
     set detail = detail || jsonb_build_object('files', fout, 'refile_attempts', v_att, 'refiled_at', now(), 'sales_done_at', now())
   where id = p_id;
  return jsonb_build_object('waiting', 'it_engineer re-verification', 'refile_attempt', v_att, 'files', fout);
end $fn$;

-- The sales engineer replies "done" by returning; it never closes. This trigger makes that a rule:
-- a backup refile or remediation reaches status 'done' only inside the it_engineer's re-check.
create or replace function public.trg_backup_refile_only_it_engineer_closes()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.kind = 'handoff' and new.detail->>'type' in ('backup.refile', 'backup.remediate')
     and new.status = 'done' and old.status is distinct from 'done'
     and coalesce(current_setting('qd.backup_closer', true), '') <> 'it_engineer' then
    raise exception 'only the it_engineer closes a backup handoff (% %), after verifying every file itself', new.detail->>'type', new.id;
  end if;
  -- An allowed close is recorded: which routine closed it and as which session user (review of #628).
  if new.kind = 'handoff' and new.detail->>'type' in ('backup.refile', 'backup.remediate')
     and new.status = 'done' and old.status is distinct from 'done' then
    new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('closed_by', jsonb_build_object(
      'seat', current_setting('qd.backup_closer', true),
      'routine', nullif(current_setting('qd.backup_closer_routine', true), ''),
      'session_user', session_user::text, 'at', now()));
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_backup_refile_only_it_engineer_closes() from public, anon, authenticated;
drop trigger if exists z60_backup_refile_only_it_engineer_closes on public.agent_actions;
create trigger z60_backup_refile_only_it_engineer_closes before update of status on public.agent_actions
  for each row execute function public.trg_backup_refile_only_it_engineer_closes();

-- The sales engineer's handler: as applied by the_dropbox_backup_is_confirmed_not_assumed.sql, the
-- backup branch now also answers 'backup.remediate'.
create or replace function public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
as $fn$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';
  select refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3); v_min := coalesce(v_min, 7); v_max := coalesce(v_max, 14);

  select null::uuid as id, null::text as email, null::text as full_name into v_cust;
  select null::bigint as id, null::text as company_name, null::text as email into v_sup;
  if (d->>'customer_id') is not null then
    select id, email, full_name into v_cust from public.customers where id = (d->>'customer_id')::uuid;
  end if;
  if (d->>'supplier_id') is not null then
    select id, company_name, coalesce(claimed_by, email) as email into v_sup from public.leads where id = (d->>'supplier_id')::bigint;
  end if;
  if (d->>'inquiry_id') is not null then
    select summary into v_inq from public.inquiries where id = (d->>'inquiry_id')::uuid;
  end if;
  v_revealed := coalesce(to_char((d->>'revealed_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date');
  v_rid := left(coalesce(d->>'transaction_id', d->>'subject_id', ''), 8);

  if t = 'reveal.paid' then
    -- The words trg_reveal_receipt used to write itself, unchanged, now composed by the seat whose
    -- voice the portal is and carried by the seat that owns the pipe.
    if v_cust.email is not null then
      v_req := public.fn_sales_engineer_writes('reveal_receipt', 'customer', v_cust.email, null, v_cust.id,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Reveal confirmed — ' || coalesce(v_sup.company_name, 'supplier'),
        'You have unlocked ' || coalesce(v_sup.company_name, 'the supplier') || '''s contact details'
          || coalesce(' for: ' || left(v_inq, 80), '')
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'تم تأكيد الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لك الآن، ويمكنك مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل نتواصل معه نيابةً عنك مع نسخة لك، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' يقرّر رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا نردّ إليك كامل ما دفعته.',
        '{}', 'reveal_receipt:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    if coalesce(v_sup.email, '') like '%@%' then
      perform public.fn_sales_engineer_writes('quote_accepted', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'A customer revealed your quote on QuotesDone',
        'A customer paid to reveal your contact for: ' || coalesce(v_inq, '')
          || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
          || ' working days of the reveal. If you have not responded after ' || v_chase::text
          || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
        'كشف عميل عن عرضك على QuotesDone',
        'دفع عميل للكشف عن بيانات التواصل معك بخصوص: ' || coalesce(v_inq, '') || '. يُرجى الرد سريعًا — بموجب اتفاقية المورّد يجب الرد خلال '
          || v_window::text || ' أيام عمل من الكشف، وإلا يُردّ للعميل ما دفعه ويُسترد المبلغ من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم تكتمل عملية الدفع للكشف',
      'لم تنجح عملية الدفع للكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتك. يمكنك المحاولة مجددًا في أي وقت من بوابتك في QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'تم استلام دفعتك', 'استلمنا دفعتك بقيمة ' || (d->>'amount_aed') || ' درهم. شكرًا لك.',
      '{}', 'payment_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.request_checked' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_amt := case when (d->>'money_ok')::boolean then ' — AED ' || (d->>'amount_aed') else '' end;
    v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'We have your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have received your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || '.' || E'\n\n'
        || 'What happens next: we check whether the supplier ever replied to you, our chief executive decides on that record, and if the refund is due you get back everything you paid'
        || v_amt || ', the reveal fee and the card processing part together, to the card you paid with. Banks usually take ' || v_min || '–' || v_max || ' working days to show it.' || E'\n\n'
        || 'If you have an email thread with the supplier, keep it: it is the proof we rely on.',
      'استلمنا طلب الاسترداد',
      'استلمنا طلب استرداد مبلغ الكشف. نتحقق أولًا من ردّ المورّد، ثم يقرّر رئيسنا التنفيذي، وإن كان الاسترداد مستحقًا يعود إليك كامل ما دفعته إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'تم إصدار استرداد بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لك استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، وهو كامل ما دفعته، إلى وسيلة الدفع الأصلية لأن المورّد لم يردّ خلال '
        || v_window::text || ' أيام عمل. قد يستغرق ظهوره في كشف حسابك ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بخصوص طلب الاسترداد',
      'راجعنا طلب الاسترداد ولم تتم الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'السجل يُظهر أن المورّد قد ردّ.')
        || ' إن كان لديك ما يثبت خلاف ذلك فردّ على هذه الرسالة وسنراجع الطلب مجددًا.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادك قيد المعالجة',
      'تمت الموافقة على استردادك وهو قيد المعالجة لدى مزوّد الدفع، ولم يصل إلى بطاقتك بعد. سنراسلك فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round((d->>'refunded_aed')::numeric + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date');
    if t = 'nonresponse.charge_raised' then
      v_req := public.fn_sales_engineer_writes('nonresponse_charge', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Charge under the Supplier Agreement — reveal #' || left(coalesce(d->>'transaction_id', ''), 8),
        'Hello ' || coalesce(v_sup.company_name, '') || E',\n\n'
          || 'A customer paid to reveal your contact details and did not hear from you within ' || v_window::text
          || ' working days, despite the reminders we sent. Under the Supplier Agreement the customer has been refunded in full, and that refund is recovered from your account:' || E'\n\n'
          || v_lines || E'\n\n'
          || 'Matching is paused until this is settled. You can pay it from the Billing section of your supplier portal. If you believe it is wrong, use "Dispute this charge" there or reply to this email and we will check the figures against the payment record.',
        'رسوم بموجب اتفاقية المورّد',
        'دفع عميل للكشف عن بيانات التواصل معك ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات. بموجب اتفاقية المورّد رُدّ للعميل كامل ما دفعه ويُسترد من حسابك: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد. يمكنك السداد أو الاعتراض من قسم الفواتير في بوابتك.',
        '{}', 'nonresponse_charge:' || (d->>'subject_id'));
    else
      -- THE CORRECTION MUST REACH WHOEVER GOT THE ORIGINAL: its To and every Cc, not today's address book.
      select * into v_orig from public.notifications where id = (d->>'original_notification_id')::bigint;
      v_req := public.fn_sales_engineer_writes('nonresponse_charge_correction', 'supplier',
        coalesce(v_orig.to_email, v_sup.email), v_sup.id, null, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Correction: ' || coalesce(v_orig.subject, 'your charge under the Supplier Agreement'),
        'This replaces our message of ' || coalesce(to_char(v_orig.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'earlier')
          || ' about this charge, which carried the wrong figures. Please disregard it. The correct figures are:' || E'\n\n' || v_lines,
        'تصحيح: رسوم بموجب اتفاقية المورّد',
        'هذه الرسالة تحلّ محلّ رسالتنا السابقة التي تضمنت أرقامًا غير صحيحة. الأرقام الصحيحة: المبلغ المسترد ' || (d->>'refunded_aed')
          || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراكك السنوي في QuotesDone مستحق',
      'اشتراكك السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم مستحق الآن. يمكنك السداد بأمان من بوابة المورّد.',
      '{}', 'subscription_due:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'billing.answer' then
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'facts') x);
    if d->>'party' = 'supplier' then
      if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  Nothing is recorded against your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    else
      if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'customer', v_cust.email, null, v_cust.id, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  No payment is recorded on your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req, 'facts', d->'facts');

  elsif t = 'charge.dispute_answer' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'lines') x);
    v_req := public.fn_sales_engineer_writes('charge_dispute_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your query about charge #' || coalesce(d->>'due_id', ''),
      case when (d->>'figures_match')::boolean
           then E'We checked the charge against the payment record and the figures stand:\n\n'
           else E'We checked the charge against the payment record and the figures do not match it. It is on hold while our chief executive reviews it; you do not need to pay it until we write again.\n\n' end
        || coalesce(v_lines, ''),
      null, null, '{}', 'charge_dispute_answer:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'figures_match', d->'figures_match');

  elsif t = 'refund.remediate' then
    return public.fn_sales_engineer_remediates(p_id);

  elsif t = 'delivery.result' then
    return public.fn_sales_engineer_attaches_delivery_result(p_id);

  elsif t in ('backup.refile', 'backup.remediate') then
    return public.fn_sales_engineer_refiles_backup(p_id);
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $fn$;

-- ── 6. THE RE-CHECK, THE CLOSE, THE ESCALATION ───────────────────────────────────────────────────
create or replace function public.fn_it_backup_recheck()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; s record; d public.doc_backups; v_since timestamptz; v_files jsonb; v_state text;
  n_ok int; n_fail int; n_wait int; v_att int; v_rep jsonb; n_closed int := 0; n_retry int := 0; n_esc int := 0;
begin
  for h in select * from public.agent_actions
            where kind = 'handoff' and agent = 'sales_engineer' and status = 'pending'
              and detail->>'type' in ('backup.refile', 'backup.remediate') order by id loop
    v_since := coalesce((h.detail->>'refiled_at')::timestamptz, h.created_at);
    v_files := '[]'::jsonb; n_ok := 0; n_fail := 0; n_wait := 0;
    for s in select e from jsonb_array_elements(coalesce(h.detail->'files', '[]'::jsonb)) e loop
      d := null;
      select * into d from public.doc_backups where id = (s.e->>'doc_backup_id')::bigint;
      v_state := case
        when d.id is null then case when h.detail ? 'sales_done_at' then 'failing' else 'waiting' end
        when d.status = 'done' and d.verified_at > v_since then 'ok'
        when d.status in ('skipped_large', 'abandoned') or (d.status = 'error' and d.attempts >= 5) then 'failing'
        else 'waiting' end;
      if v_state = 'ok' then n_ok := n_ok + 1; elsif v_state = 'failing' then n_fail := n_fail + 1; else n_wait := n_wait + 1; end if;
      v_files := v_files || (s.e || jsonb_build_object('state', v_state, 'status', d.status, 'attempts', d.attempts, 'error', d.error));
    end loop;
    v_att := coalesce((h.detail->>'refile_attempts')::int, 0);

    if n_fail = 0 and n_wait = 0 then
      perform set_config('qd.backup_closer', 'it_engineer', true);
      perform set_config('qd.backup_closer_routine', 'fn_it_backup_recheck', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer', 'files', v_files, 'verified_at', now()));
      perform set_config('qd.backup_closer', '', true);
      perform set_config('qd.backup_closer_routine', '', true);
      update public.agent_actions set decided_by = 'it_engineer' where id = h.id;
      n_closed := n_closed + 1;
    elsif h.detail->>'type' = 'backup.refile' and not (h.detail ? 'escalated_report_id') then
      if n_fail > 0 and v_att < 2 then
        perform public.fn_seat_handoff_act(h.id);          -- the second refile
        n_retry := n_retry + 1;
      elsif n_fail > 0 or h.created_at < now() - interval '48 hours' then
        v_rep := public.fn_support_report_to_ceo(
          'backup_escalation:' || h.id, 'serious',
          'Dropbox backup: ' || (n_fail + n_wait) || ' file(s) still not backed up after ' || v_att || ' refile(s)'
            || case when h.created_at < now() - interval '48 hours' then ' and 48 hours' else '' end,
          jsonb_build_object('handoff_id', h.id, 'files', v_files, 'refile_attempts', v_att, 'opened_at', h.created_at),
          jsonb_build_array(jsonb_build_object('action', 'handed to sales_engineer to refile', 'handoff_id', h.id, 'attempts', v_att,
                                               'last_refile_at', h.detail->>'refiled_at')),
          'Send the sales engineer instructions for these files, or record that they cannot be backed up and why. The IT engineer re-checks each file and closes only when it is verified in Dropbox.',
          p_review_in => interval '1 day', p_source_agent => 'it_engineer');
        update public.agent_actions set detail = detail || jsonb_build_object('escalated_report_id', v_rep->'report_id', 'escalated_at', now())
         where id = h.id;
        perform public.fn_ceo_backup_escalation_decide((v_rep->>'report_id')::bigint);
        n_esc := n_esc + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'second_refiles', n_retry, 'escalated', n_esc);
end $fn$;
revoke execute on function public.fn_it_backup_recheck() from public, anon, authenticated;

create or replace function public.fn_it_backup_refile_close()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_it_backup_recheck();
$fn$;

-- The CEO reads the evidence and decides. External cause -> the founder, in plain words, and only
-- when the case is not ZZ DEMO. Anything else -> instructions back to the sales engineer.
create or replace function public.fn_ceo_backup_escalation_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; v_files jsonb; v_demo boolean; v_errs text; v_cause text; v_h bigint; v_out jsonb;
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  v_files := coalesce(r.verified_evidence->'files', '[]'::jsonb);
  v_demo := jsonb_array_length(v_files) > 0
            and not exists (select 1 from jsonb_array_elements(v_files) e where not coalesce((e->>'demo')::boolean, false));
  v_errs := coalesce((select string_agg(coalesce(e->>'error', ''), ' | ') from jsonb_array_elements(v_files) e), '');
  if not v_demo then
    v_errs := v_errs || ' | ' || coalesce((select string_agg(note, ' | ') from public.agent_runs
                                              where agent in ('dropbox_backup', 'fn:dropbox_backup') and status = 'error'
                                                and started_at > now() - interval '48 hours'), '');
  end if;
  v_cause := case
    when v_errs ~* '(no_dropbox_auth|invalid_access_token|expired_access_token|invalid_grant|access token|dbx_upload 401|get_metadata 401)' then 'Dropbox refused our credentials (the connection needs to be re-authorised)'
    when v_errs ~* '(insufficient_space|over_quota|storage (is )?full|quota)' then 'the Dropbox account is out of space'
    when v_errs ~* '(payment|billing|plan (expired|limit)|account_suspended|disabled)' then 'the Dropbox plan or billing is blocking uploads'
    else null end;

  if v_cause is not null and not v_demo then
    v_out := public.fn_notify_founder(
      'Dropbox backup is blocked by something outside the company',
      'Our document backup to your Dropbox has stopped because ' || v_cause || '. ' || jsonb_array_length(v_files)
        || ' document(s) are waiting and will be sent as soon as it is fixed. Nothing inside the company can fix this part; it needs you.',
      'high', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_external:' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'));
  else
    v_h := public.fn_seat_handoff('ceo', 'sales_engineer', 'backup.remediate', 'support_ceo_report', r.id::text,
      jsonb_build_object('report_id', r.id, 'refile_handoff_id', r.verified_evidence->'handoff_id',
        'files', (select coalesce(jsonb_agg(e - 'state' - 'status' - 'attempts'), '[]'::jsonb) from jsonb_array_elements(v_files) e where e->>'state' <> 'ok'),
        'refile_attempts', 0,
        'instructions', 'Re-file each file below from its source. Where the source no longer exists, mark its row abandoned with the reason (error ''abandoned: ...'') so it stops counting as lost. Do not close this: the IT engineer re-checks and closes.'));
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(),
         acceptance_receipt = 'ceo: ' || case when v_h is not null then 'instructions sent back as handoff ' || v_h
                                              else 'external cause (' || v_cause || '), founder notified' end
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'cause', coalesce(v_cause, 'internal'), 'demo', v_demo,
                            'remediate_handoff', v_h, 'founder', v_out);
end $fn$;
revoke execute on function public.fn_ceo_backup_escalation_decide(bigint) from public, anon, authenticated;

-- The CEO's re-check: a remediation the it_engineer has closed completes the report.
create or replace function public.fn_ceo_backup_escalation_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'CEO re-checked: the IT engineer verified every file of the remediation (handoff ' || a.id || ') and closed it.'
    from public.agent_actions a
   where r.idempotency_key like 'backup_escalation:%' and r.status = 'accepted'
     and a.kind = 'handoff' and a.detail->>'type' = 'backup.remediate' and a.detail->>'report_id' = r.id::text and a.status = 'done';
  get diagnostics n = row_count;
  return jsonb_build_object('completed', n);
end $fn$;
revoke execute on function public.fn_ceo_backup_escalation_sweep() from public, anon, authenticated;

-- ── 7. COVERAGE AND THE HEARTBEAT ────────────────────────────────────────────────────────────────
create or replace function public.fn_backup_coverage()
returns jsonb language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_not_done int; v_ids jsonb; v_abandoned int; v_unqueued int; v_unq_err text; v_last_ok timestamptz;
  v_conv jsonb; v_conv_fn text := 'public.fn_conversation_retention' || '_breaches(interval)';
  v_refile int; v_fail text[] := '{}';
begin
  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]'::jsonb) into v_not_done, v_ids
    from (select d.id, row_number() over (order by d.id) rn from public.doc_backups d
           where d.status <> 'done' and d.entity <> 'zz_demo'
             and not (d.status = 'abandoned' and coalesce(d.error, '') like 'abandoned:%')
             and coalesce(d.requeued_at, d.created_at) < now() - interval '48 hours') x;
  select count(*) into v_abandoned from public.doc_backups where status = 'abandoned' and coalesce(error, '') like 'abandoned:%';
  if v_not_done > 0 then v_fail := array_append(v_fail, 'not_done_after_48h'); end if;

  begin
    v_unqueued := public.fn_enqueue_doc_backups();
    raise exception using errcode = 'QDRBK', message = 'roll back the coverage measurement';
  exception
    when sqlstate 'QDRBK' then null;
    when read_only_sql_transaction then v_unq_err := 'not measurable in a read-only transaction';
    when others then v_unq_err := left(sqlerrm, 200);
  end;
  select max(started_at) into v_last_ok from public.agent_runs where agent = 'dropbox_backup' and status = 'ok';
  if (v_unqueued > 0 and coalesce(v_last_ok, '-infinity') < now() - interval '48 hours')
     or (v_unq_err is not null and v_unq_err <> 'not measurable in a read-only transaction') then
    v_fail := array_append(v_fail, 'sources_without_a_row');
  end if;

  if to_regprocedure(v_conv_fn) is not null then
    begin
      execute 'select ' || replace(v_conv_fn, '(interval)', '($1)') into v_conv using interval '48 hours';
    exception when others then v_conv := jsonb_build_object('error', left(sqlerrm, 200));
    end;
    if coalesce((v_conv->>'total')::int, 0) > 0 or v_conv ? 'error' then v_fail := array_append(v_fail, 'conversation_retention'); end if;
  end if;

  select count(*) into v_refile from public.agent_actions
   where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' in ('backup.refile', 'backup.remediate')
     and (status = 'failed' or (status = 'pending' and created_at < now() - interval '48 hours'));
  if v_refile > 0 then v_fail := array_append(v_fail, 'refile_not_verified_in_48h'); end if;

  return jsonb_build_object(
    'ok', cardinality(v_fail) = 0, 'failing', to_jsonb(v_fail),
    'not_done_after_48h', v_not_done, 'not_done_ids', v_ids, 'abandoned_documented', v_abandoned,
    'sources_without_a_row', v_unqueued, 'sources_error', v_unq_err, 'last_ok_backup', v_last_ok,
    'conversation_retention', coalesce(v_conv, jsonb_build_object('checked', false, 'reason', 'function not installed')),
    'refiles_open_past_48h', v_refile, 'measured_at', now());
end $fn$;

-- Canonical until now: the_dropbox_backup_is_confirmed_not_assumed.sql. Unchanged except the
-- heartbeat block: the it_engineer's daily check itself going silent for 26 hours is an alarm.
create or replace function public.fn_backup_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_last timestamptz; v_status text; v_stale boolean; v_open int; v_subject_rows int;
  v_cov jsonb; v_cov_ok boolean; v_cov_open int := 0; v_date text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  v_hb timestamptz; v_hb_silent boolean;
  -- when this watcher started expecting a daily check (the apply of this file)
  c_hb_since constant timestamptz := '2026-09-14 15:00:00+00';
  c_agents constant text[] := array['dropbox_backup','fn:dropbox_backup'];
begin
  select count(*) into v_subject_rows from agent_runs where agent = any(c_agents);
  if v_subject_rows = 0 then
    return jsonb_build_object(
      'ok', false,
      'reason', 'subject_not_found',
      'watched', c_agents,
      'detail', 'No run of any watched backup agent has ever been recorded, so this watcher cannot '
             || 'tell a stopped backup from a renamed one. It alerts nobody rather than reporting '
             || 'catastrophe from an empty lookup. Check the agent name before the backup.');
  end if;

  select started_at, status into v_last, v_status
    from agent_runs where agent = any(c_agents) order by started_at desc limit 1;

  -- HEARTBEAT: silence of the check is an alarm, never a clean bill.
  select max(started_at) into v_hb from agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'dropbox_daily_check' and status in ('ok','warn');
  v_hb_silent := coalesce(v_hb, c_hb_since) < now() - interval '26 hours';
  if v_hb_silent then
    perform public.fn_support_report_to_ceo(
      'it_backup_heartbeat:' || v_date, 'serious',
      'The IT engineer''s daily Dropbox check has not run for '
        || round(extract(epoch from (now() - coalesce(v_hb, c_hb_since))) / 3600)::text || ' hours',
      jsonb_build_object('last_daily_check', v_hb, 'expected_since', c_hb_since, 'watched', 'agent_runs it_engineer job dropbox_daily_check'),
      '[]'::jsonb,
      'Find out why the daily check is not running (resilience_ping -> fn_it_backup_tick -> dropbox_backup mode reconcile). Until it runs, nothing confirms that the backup is complete.',
      p_review_in => interval '1 day', p_source_agent => 'it_engineer');
  end if;

  v_cov := public.fn_backup_coverage();
  v_cov_ok := coalesce((v_cov->>'ok')::boolean, false);
  if not v_cov_ok then
    select count(*) into v_cov_open from agent_actions
     where kind = 'backup_coverage' and agent = 'it_engineer' and coalesce(status,'') in ('pending','needs_review')
       and created_at > now() - interval '20 hours';
    if v_cov_open = 0 then
      insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
      values('it_engineer','backup_coverage','pending','medium',
        'Dropbox backup coverage failing: ' || (v_cov->>'failing'),
        'Something that should be in Dropbox has not reached it within 48 hours: '
        || (v_cov->>'not_done_after_48h') || ' queued row(s) not done, '
        || coalesce(v_cov->>'sources_without_a_row','unknown') || ' source(s) with no row, '
        || (v_cov->>'refiles_open_past_48h') || ' refile(s) not verified. Rows: ' || (v_cov->>'not_done_ids') || '.',
        'doc_backups', v_cov);
      perform public.fn_support_report_to_ceo(
        'dropbox_backup_escalation:' || v_date, 'serious',
        'Dropbox backup coverage has been failing for over 48 hours (' || (v_cov->>'failing') || ')',
        v_cov,
        coalesce((select jsonb_agg(jsonb_build_object('handoff_id', id, 'status', status, 'type', detail->>'type'))
                    from agent_actions where kind = 'handoff' and detail->>'type' in ('backup.refile','backup.remediate') and status <> 'done'), '[]'::jsonb),
        'Decide whether the missing documents need the founder''s Dropbox checked by hand or the filing corrected. The IT engineer has raised it and handed each missing file to the sales engineer to refile; this is past 48 hours, which is why it reaches you.',
        p_review_in => interval '1 day', p_source_agent => 'it_engineer');
    end if;
  end if;

  v_stale := (v_last < now() - interval '26 hours') or (coalesce(v_status,'') = 'error');
  if not v_stale then
    return jsonb_build_object('ok', v_cov_ok and not v_hb_silent, 'last', v_last, 'status', v_status, 'watched', c_agents,
                              'coverage', v_cov, 'coverage_alerted', not v_cov_ok and v_cov_open = 0,
                              'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
  end if;

  select count(*) into v_open from agent_actions
   where kind = 'backup_alert' and coalesce(status,'') in ('pending','needs_review')
     and created_at > now() - interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values('it_engineer','backup_alert','pending','high',
      'Document backup to Dropbox has failed or is overdue',
      'The Dropbox document mirror has not completed successfully in the last 26 hours (last: '
      || coalesce(v_last::text,'never') || ', status: ' || coalesce(v_status,'unknown')
      || '). Check the dropbox_backup function and its logs. This concerns stored DOCUMENTS only — '
      || 'the managed Postgres backups are outside this database and are not covered by this check.',
      'agent_runs', jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    insert into security_events(kind, severity, source, subject, detail)
    values('backup_overdue','high','backup','dropbox document mirror',
      jsonb_build_object('last_backup', v_last, 'last_status', v_status, 'watched', c_agents));

    if v_last < now() - interval '48 hours' then
      perform public.fn_notify_founder(
        'Document backup failing after retry: no successful Dropbox mirror for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours',
        'The Dropbox document mirror has now been failing for '
        || round(extract(epoch from (now() - v_last)) / 3600)::text || ' hours (last run: '
        || v_last::text || ', status: ' || coalesce(v_status,'unknown')
        || '). This covers stored DOCUMENTS — supplier files, quotes, drawings. The managed Postgres '
        || 'backups are a separate system outside this database and this alert says nothing about '
        || 'them either way. Verify the dropbox_backup function.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;
  end if;

  return jsonb_build_object('alerted', true, 'last', v_last, 'status', v_status,
                            'existing_open', v_open, 'watched', c_agents, 'coverage', v_cov,
                            'heartbeat', jsonb_build_object('last_daily_check', v_hb, 'silent', v_hb_silent));
end
$function$;

-- ── 8. THE DAILY CONFIRMATION ────────────────────────────────────────────────────────────────────
create or replace function public.fn_dropbox_backup_summary()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select * from public.fn_it_backup_expected_status()),
  ex as (
    select count(*) as expected,
           count(*) filter (where status = 'done') as backed_up,
           count(*) filter (where status = 'done' and verified_at is not null) as verified,
           count(*) filter (where doc_backup_id is null) as never_queued
      from e),
  f as (
    select
      count(*) filter (where created_at > now() - interval '24 hours')                  as queued_24h,
      count(*) filter (where backed_up_at > now() - interval '24 hours')                as uploaded_24h,
      count(*) filter (where verified_at > now() - interval '24 hours')                 as verified_24h,
      count(*) filter (where status in ('pending','error') and coalesce(attempts,0) < 5) as pending,
      count(*) filter (where status = 'done')                                           as uploaded_total,
      count(*) filter (where status = 'done' and verified_at is not null)               as verified_total,
      count(*) filter (where (status = 'error' and attempts >= 5) or status = 'skipped_large') as failed,
      count(*) filter (where status = 'abandoned')                                      as abandoned,
      count(*)                                                                          as total
    from public.doc_backups where entity <> 'zz_demo'),
  h as (select count(*) as open_handoffs from public.agent_actions
         where kind = 'handoff' and status = 'pending' and detail->>'type' in ('backup.refile','backup.remediate'))
  select to_jsonb(ex) || to_jsonb(f) || to_jsonb(h) || jsonb_build_object('line',
    'Dropbox backup: ' || ex.expected || ' expected, ' || ex.backed_up || ' backed up, ' || ex.verified || ' verified in Dropbox, '
    || ex.never_queued || ' never queued; queue ' || f.pending || ' pending, ' || f.failed || ' failed, '
    || h.open_handoffs || ' open refile handoff(s). Last 24h: ' || f.queued_24h || ' queued, ' || f.uploaded_24h || ' uploaded, '
    || f.verified_24h || ' verified. All rows: ' || f.uploaded_total || ' uploaded (' || f.verified_total || ' verified), '
    || f.abandoned || ' abandoned with a recorded reason, of ' || f.total || '.',
    'measured_at', now())
  from ex, f, h;
$fn$;

create or replace function public.fn_dropbox_backup_daily_report()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; s jsonb;
begin
  if v_local::time < time '19:00' then
    return jsonb_build_object('filed', false, 'reason', 'before 19:00 Asia/Dubai');
  end if;
  if exists (select 1 from public.support_ceo_report
              where idempotency_key = 'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD')) then
    return jsonb_build_object('filed', false, 'reason', 'already filed today');
  end if;
  s := public.fn_dropbox_backup_summary();
  return public.fn_support_report_to_ceo(
    'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD'),
    case when (s->>'failed')::int > 0 or (s->>'never_queued')::int > 0 or (s->>'open_handoffs')::int > 0 then 'elevated' else 'routine' end,
    'Dropbox backup ' || to_char(v_local, 'DD Mon') || ': ' || (s->>'line'),
    s, '[]'::jsonb,
    'Note the day''s backup position. NOTHING IS REQUESTED: this is the IT engineer''s daily confirmation. A case still failing after two refiles or 48 hours reaches you separately, as a serious report.',
    p_review_in => interval '1 day', p_source_agent => 'it_engineer') || jsonb_build_object('filed', true);
end $fn$;

-- ── 9. THE TICK ─────────────────────────────────────────────────────────────────────────────────
-- A stage that throws must not only say so in the tick's JSON (review of #628): it writes an
-- agent_runs error row and opens ONE it_engineer finding per stage per 20 hours, so a silently
-- broken recheck / ceo / watch / daily stage is itself something the loop has to close.
create or replace function public.fn_it_backup_stage_failed(p_stage text, p_error text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  insert into public.agent_runs(agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'error', now(), now(), jsonb_build_object('job', 'backup_tick', 'stage', p_stage),
          'backup tick stage ' || p_stage || ' failed: ' || left(coalesce(p_error, ''), 300));
  if not exists (select 1 from public.agent_actions
                  where agent = 'it_engineer' and kind = 'backup_tick_stage_failed' and detail->>'stage' = p_stage
                    and coalesce(status, '') in ('pending', 'needs_review') and created_at > now() - interval '20 hours') then
    insert into public.agent_actions(agent, kind, status, risk, title, recommendation, target_table, detail)
    values ('it_engineer', 'backup_tick_stage_failed', 'pending', 'medium',
            'Backup check stage "' || p_stage || '" is failing',
            'The it_engineer''s ' || p_stage || ' stage threw: ' || left(coalesce(p_error, ''), 300)
              || '. Until it runs cleanly this part of the backup is not being checked.',
            'doc_backups', jsonb_build_object('stage', p_stage, 'error', left(coalesce(p_error, ''), 500)))
    returning id into v_id;
  end if;
  return jsonb_build_object('error', left(coalesce(p_error, ''), 200), 'finding_id', v_id);
end $fn$;
revoke execute on function public.fn_it_backup_stage_failed(text, text) from public, anon, authenticated;

create or replace function public.fn_it_backup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('recheck', public.fn_it_backup_recheck());
  exception when others then o := o || jsonb_build_object('recheck', public.fn_it_backup_stage_failed('recheck', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_backup_escalation_sweep());
  exception when others then o := o || jsonb_build_object('ceo', public.fn_it_backup_stage_failed('ceo', sqlerrm)); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', public.fn_it_backup_stage_failed('watch', sqlerrm)); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', public.fn_it_backup_stage_failed('daily', sqlerrm)); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due());
end $fn$;

-- New routines are revoked above where they are created; these were CREATE OR REPLACE of routines
-- already closed, and are re-stated so the file is complete on its own.
revoke execute on function public.fn_sales_engineer_refiles_backup(bigint) from public, anon, authenticated;
revoke execute on function public.fn_dropbox_reconcile_apply(jsonb, text) from public, anon, authenticated;
revoke execute on function public.fn_it_backup_refile_close() from public, anon, authenticated;
revoke execute on function public.fn_backup_coverage() from public, anon, authenticated;
revoke execute on function public.fn_backup_watch() from public, anon, authenticated;
revoke execute on function public.fn_dropbox_backup_summary() from public, anon, authenticated;
revoke execute on function public.fn_dropbox_backup_daily_report() from public, anon, authenticated;
revoke execute on function public.fn_it_backup_tick() from public, anon, authenticated;

-- ── 10. PROBE: read-only notices ────────────────────────────────────────────────────────────────
do $probe$
declare s jsonb; n_exp int; n_never int;
begin
  select count(*), count(*) filter (where doc_backup_id is null and since < now() - interval '24 hours')
    into n_exp, n_never from public.fn_it_backup_expected_status();
  s := public.fn_dropbox_backup_summary();
  raise notice 'expected items: %, never queued past 24h: %', n_exp, n_never;
  raise notice 'summary: %', s->>'line';
  raise notice 'daily check due: %', public.fn_dropbox_reconcile_due()::text;
end $probe$;

-- a_customer_who_accepted_terms_or_sent_a_file_is_never_purged
-- Seat: it_engineer (the purge, fn_unfinished_signup_purge); customer_support (the sign-up it protects, and the activation
-- duty that writes to a held one). 19 Nov 2026.
--
-- WHAT WAS MEASURED (production, read-only, 19 Nov 2026):
--   * cron 392 'unfinished_signup_purge' runs `select public.fn_unfinished_signup_purge(true)` every 5 minutes. A customer
--     is removed (row, login, OTPs, outbox, and its files through signup_purge_object / signup_purge_dropbox) when it is not
--     demo, misses any of email / mobile / terms / terms_ip, started over 30 minutes ago, and fn_signup_customer_held(id) is
--     false. Its only other caller is fn_signup_email_kept_elsewhere (whether the login stays).
--   * fn_signup_customer_held held on a request, a sale, a PO, signed_terms_path, an intake, a message, an assistant chat,
--     an inbound e-mail, a contact message or a complaint. It did NOT hold on:
--       - tos_accepted_at / tos_ip / tos_sha256 when the certificate never landed (signed_terms_path null): a customer who
--         accepted the terms, whose certificate render failed (13 Nov: kyc's write was cancelled by a lock), and who had not
--         verified the mobile was deleted 30 minutes later with the acceptance;
--       - a drawing, BOQ or site photo in drawing-files (drawings/<customer id>/, redacted/<customer id>/), a CAD read job or
--         a redaction run: the purge LISTED those files and deleted them with the person;
--       - an inbound mail still in inbound_mail_queue, a support case, a data request or a fault report.
--   * public.signup_purge holds 2 customer deletions (the log began 12 Oct 2026). Both: e-mail verified; mobile, terms and
--     terms IP missing; their only files were ones WE generated (backups/generated/..._customer_details_<id>.pdf, and for #5
--     an archived copy of an outbound notification). #5 (started 22 Sep, removed 12 Oct, on the first run) was a corporate
--     ihg.com address that customer_support's activation duty had e-mailed on 25 Sep; nothing inbound from it was found.
--     #154 (started 29 Oct 12:48, removed 13:20) left no trace from which even the domain can be read (the log stores a
--     sha256 of the e-mail; matched against 960 addresses still held in 28 tables). NEITHER had accepted the terms or sent
--     a file, so neither would be held by this file: it changes no past outcome. A July sign-up (Ekana Global) predates the
--     log and cannot be measured either way.
--   * public.customers holds 0 rows today, so no live customer's outcome changes at apply.
--
-- WHAT CHANGES:
--   1. fn_signup_customer_shows_intent(public.customers): the evidence, read from a customers row value. True when the
--      person
--        a) accepted the terms by ANY signal: tos_accepted_at, tos_ip, tos_sha256, signed_terms_path / _at / _url, a
--           signed-terms certificate filed in doc_backups, or a terms re-sign recorded in agent_actions;
--        b) sent ANY file: an object under drawing-files drawings/<id>/ or redacted/<id>/ (drawings, BOQs, site photos: the
--           portal and WhatsApp both store there), a doc_backups row of that bucket, a CAD read job, a redaction run, an
--           e-mailed document (doc_reviews), a support document intake; or anything on a request (inquiries, inquiry_intake
--           including site_photos, messages including attachment_path), as before;
--        c) wrote to us: an inbound e-mail (inbound_messages or still in inbound_mail_queue), a contact message, a complaint,
--           a support case (by customer id or e-mail), a data request, a fault report, a message or an assistant chat.
--      Every held reason of the previous body is kept. Matching is by customer id or the verified-or-not E-MAIL only:
--      never by the unverified mobile (an unverified number may be someone else's).
--   2. fn_signup_customer_held(uuid), same signature, same grants: reads the row and asks (1). A row that does not exist is
--      null, as before.
--   3. doc_backups_entity_entity_id_idx on doc_backups (entity, entity_id), so the check in (1) is an index read (see below).
--   A held customer is not deleted; customer_support's activation duty (fn_customer_support_activation_tick, every 6 hours,
--   customer_support_activates_wins_back_and_settles_disputes.sql) writes to him once 3 days after sign-up, through
--   fn_customer_support_duty_send (suppression and demo rules). Someone with only an e-mail and nothing else is still removed.
--
-- WHAT IT DOES NOT CHANGE: fn_unfinished_signup_purge (it already skips a held customer and counts it as held), the
-- supplier side (fn_signup_supplier_held), fn_signup_email_kept_elsewhere, the activation duty's text.
--
-- AUTHORITY: founder ledger 1737 (19 Nov 2026, standing), amending 1181 (12 Oct 2026, "deleted entirely as if they never
-- tried - nothing kept"): a customer sign-up who accepted our terms by any signal, sent us any file, or wrote to us is
-- kept and reminded; a sign-up with only an e-mail is still deleted after 30 minutes. 1737 is about customers: the
-- supplier rule (an upload alone never holds a company sign-up) is unchanged. The same PR moves
-- scripts/checks/an_unfinished_sign_up_is_never_a_customer.test.mjs to read the customer rule from this file (the
-- latest definition, scripts/lib/canonical_body.mjs) and inverts its upload assertion for customers only.
--
-- HOW TO APPLY: node scripts/apply_sql.mjs scripts/sql/a_customer_who_accepted_terms_or_sent_a_file_is_never_purged.sql --apply --ddl
--   then append this file as the LAST line of scripts/sql/MANIFEST.txt (Edit, never a redirect), delete the pending note,
--   node scripts/checks/canonical_routine_manifest.mjs (0 findings).
-- ROLLBACK: re-apply fn_signup_customer_held from scripts/sql/an_unfinished_sign_up_is_never_a_customer.sql (its body is
--   unchanged since that file), then `drop function public.fn_signup_customer_shows_intent(public.customers);`.
-- PROBE: at the end of this file, on in-memory ZZ DEMO rows plus one ZZ DEMO redaction-run row inserted and deleted inside
--   this transaction (drawing_redaction_runs has no trigger). It raises only on failure, which rolls this whole file back,
--   so a guard that does not hold is never left live; on success it leaves nothing and returns a verdict row.
-- Prevented by: the probe below, and (in the same PR) the updated an_unfinished_sign_up_is_never_a_customer.test.mjs.

set local lock_timeout = '1500ms';

-- THE INDEX the held check reads doc_backups by (review, 19 Nov 2026). Production: 61,152 rows, 36 MB heap (62 MB with its
-- 8 indexes), none on (entity, entity_id), so each lookup was a seq scan costing 5,720, and the purge asks for every
-- non-demo customer every 5 minutes. Built on a 61,152-row, 40 MB local stand-in in 63-70 ms. The stand-in plans an index scan
-- costing 8.44. A plain CREATE INDEX holds a SHARE lock: reads go on, writes to doc_backups wait while it builds and until
-- this file commits. Measured 58 doc_backups writes in the last hour, about 1 a minute, so a writer may wait well under
-- a second. CONCURRENTLY would not block writers, but it cannot run inside apply_sql.mjs's one transaction.
-- lock_timeout bounds only the wait to TAKE the lock, not the build.
create index if not exists doc_backups_entity_entity_id_idx on public.doc_backups (entity, entity_id);

create or replace function public.fn_signup_customer_shows_intent(p_cu public.customers)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select
    -- a) accepted the terms, by any signal (a certificate that never landed does not undo the acceptance)
       cu.tos_accepted_at is not null
    or cu.tos_ip is not null
    or cu.tos_sha256 is not null
    or cu.signed_terms_path is not null
    or cu.signed_terms_at is not null
    or cu.signed_terms_url is not null
    -- one read of doc_backups for both: a filed certificate (a) and a filed drawing-files upload (b)
    or exists (select 1 from public.doc_backups d
                where d.entity = 'customer' and d.entity_id = cu.id::text
                  and (d.bucket = 'signed-terms' or d.doc_type = 'Signed Terms & Conditions' or d.bucket = 'drawing-files'))
    or exists (select 1 from public.agent_actions a
                where a.agent = 'customer_support' and a.kind = 'customer_terms_resign' and a.target_id = cu.id::text)
    -- b) sent a file: drawings, BOQs and site photos are stored under the customer's id in drawing-files
    or exists (select 1 from storage.objects o
                where o.bucket_id = 'drawing-files'
                  and (o.name like 'drawings/' || cu.id::text || '/%' or o.name like 'redacted/' || cu.id::text || '/%'))
    or exists (select 1 from public.cad_read_jobs j where j.customer_id = cu.id or lower(j.owner_email) = lower(cu.email))
    or exists (select 1 from public.drawing_redaction_runs r where r.customer_id = cu.id or lower(r.owner_email) = lower(cu.email))
    or exists (select 1 from public.doc_reviews dr where lower(dr.from_email) = lower(cu.email))
    or exists (select 1 from public.support_document_intake sdi where lower(sdi.sender_ref) = lower(cu.email))
    -- a request, a sale, an order or a draft (its site_photos and attachments with it)
    or exists (select 1 from public.inquiries i where i.customer_id = cu.id)
    or exists (select 1 from public.transactions t where t.customer_id = cu.id)
    or exists (select 1 from public.po_orders p where p.customer_id = cu.id)
    or exists (select 1 from public.inquiry_intake ii where ii.customer_id = cu.id or lower(ii.email) = lower(cu.email))
    -- c) wrote to us, or we hold a case for him
    or exists (select 1 from public.messages m where m.customer_id = cu.id)
    or exists (select 1 from public.assistant_logs a where a.audience = 'customer:' || cu.id::text)
    or exists (select 1 from public.inbound_messages im where lower(im.from_email) = lower(cu.email))
    or exists (select 1 from public.inbound_mail_queue q where lower(q.from_email) = lower(cu.email))
    or exists (select 1 from public.contact_messages cm where lower(cm.email) = lower(cu.email))
    or exists (select 1 from public.complaint_tickets ct where lower(ct.email) = lower(cu.email))
    or exists (select 1 from public.support_case sc
                where (sc.party_kind = 'customer' and sc.party_id = cu.id::text) or lower(sc.party_id) = lower(cu.email))
    or exists (select 1 from public.customer_support_data_request dq where lower(dq.email) = lower(cu.email))
    or exists (select 1 from public.support_fault_report fr where fr.customer_id = cu.id or lower(fr.email) = lower(cu.email))
  from (select (p_cu).*) cu;
$fn$;
-- a new routine: CREATE granted EXECUTE to PUBLIC (and Supabase's defaults to anon and authenticated)
revoke execute on function public.fn_signup_customer_shows_intent(public.customers) from public, anon, authenticated;
grant execute on function public.fn_signup_customer_shows_intent(public.customers) to service_role;

create or replace function public.fn_signup_customer_held(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_signup_customer_shows_intent(cu) from public.customers cu where cu.id = p_id;
$fn$;
-- the live ACL (read 19 Nov 2026 from pg_proc.proacl): {postgres=X/postgres,service_role=X/postgres}. One overload only.
revoke execute on function public.fn_signup_customer_held(uuid) from public, anon, authenticated;
grant execute on function public.fn_signup_customer_held(uuid) to service_role;

-- ── PROBE ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- ZZ DEMO only. The customers rows are VALUES built in memory (customers carries six triggers: no row is inserted there).
-- The one written row is a ZZ DEMO drawing_redaction_runs row (no trigger, customer_id null, an @example.invalid owner),
-- deleted again before the end; uncommitted, no other session ever sees it.
do $probe$
declare
  v_tag   text := 'zz-demo-purgehold-' || replace(gen_random_uuid()::text, '-', '');
  v_email text := v_tag || '@example.invalid';
  v_base  public.customers;
  v_row   public.customers;
  v_runs_before bigint; v_runs_after bigint; v_run uuid; v_obj text;
begin
  -- the base: ZZ DEMO, e-mail only, e-mail verified, nothing else
  v_base := jsonb_populate_record(null::public.customers, jsonb_build_object(
    'id', gen_random_uuid(), 'full_name', 'ZZ DEMO purge-hold probe', 'email', v_email, 'is_demo', true,
    'email_verified', true, 'phone_verified', false, 'created_at', now() - interval '2 hours'));

  -- 1. only an e-mail: NOT held (the abandoned sign-up stays purge-able)
  if public.fn_signup_customer_shows_intent(v_base) is distinct from false then
    raise exception 'CHK<<purgehold: a sign-up with only an e-mail is held; the purge could never remove an abandoned one>>';
  end if;

  -- 2. terms accepted, certificate never landed: held. Each signal alone.
  v_row := v_base; v_row.tos_accepted_at := now() - interval '1 hour';
  if public.fn_signup_customer_shows_intent(v_row) is not true then
    raise exception 'CHK<<purgehold: tos_accepted_at alone (no certificate) does not hold>>';
  end if;
  v_row := v_base; v_row.tos_ip := '192.0.2.1';                      -- TEST-NET-1, documentation range
  if public.fn_signup_customer_shows_intent(v_row) is not true then
    raise exception 'CHK<<purgehold: tos_ip alone does not hold>>';
  end if;
  v_row := v_base; v_row.signed_terms_path := 'customers/zz_demo_probe_TnC-Acceptance.pdf';
  if public.fn_signup_customer_shows_intent(v_row) is not true then
    raise exception 'CHK<<purgehold: signed_terms_path no longer holds (a reason of the previous body was lost)>>';
  end if;

  -- 3. a file sent: held. A ZZ DEMO redaction run of a drawing, matched by the e-mail (customer_id stays null: no FK row)
  select count(*) into v_runs_before from public.drawing_redaction_runs;
  insert into public.drawing_redaction_runs (owner_email, caller_ref, source_path, status)
  values (v_email, 'ZZ DEMO probe a_customer_who_accepted_terms_or_sent_a_file_is_never_purged',
          'drawings/' || (v_base).id::text || '/zz_demo_probe.pdf', 'zz_demo_probe')
  returning id into v_run;
  if public.fn_signup_customer_shows_intent(v_base) is not true then
    raise exception 'CHK<<purgehold: a drawing sent (redaction run) does not hold>>';
  end if;
  delete from public.drawing_redaction_runs where id = v_run;
  select count(*) into v_runs_after from public.drawing_redaction_runs;
  if v_runs_after <> v_runs_before or exists (select 1 from public.drawing_redaction_runs where owner_email = v_email) then
    raise exception 'CHK<<purgehold: the probe row was not removed (% before, % after)>>', v_runs_before, v_runs_after;
  end if;
  -- ...and once it is gone the same person is not held again (the hold is the file, not the probe's tag)
  if public.fn_signup_customer_shows_intent(v_base) is distinct from false then
    raise exception 'CHK<<purgehold: still held after the file went: something else matched the ZZ DEMO e-mail>>';
  end if;

  -- 4. a file in storage under a customer id: read-only, on an object that is already there (its customer row is gone, so
  --    the id reaches nobody). Skipped only when drawing-files holds no drawings/<uuid>/ object at all.
  select o.name into v_obj from storage.objects o
   where o.bucket_id = 'drawing-files' and o.name ~ '^drawings/[0-9a-f-]{36}/'
     and not exists (select 1 from public.customers c where o.name like 'drawings/' || c.id::text || '/%')
   limit 1;
  if v_obj is not null then
    v_row := v_base; v_row.id := split_part(v_obj, '/', 2)::uuid;
    if public.fn_signup_customer_shows_intent(v_row) is not true then
      raise exception 'CHK<<purgehold: a drawing stored under drawings/<id>/ does not hold>>';
    end if;
  end if;

  -- 5. the wrapper the purge calls: same answer through the id, null for an id with no row (as before)
  if public.fn_signup_customer_held(gen_random_uuid()) is not null then
    raise exception 'CHK<<purgehold: fn_signup_customer_held answers for a customer that does not exist>>';
  end if;

  -- 6. the grants: nobody but the service role (and the owner) may call either routine
  if exists (select 1 from pg_proc p, unnest(coalesce(p.proacl, '{}'::aclitem[])) acl
              where p.oid in ('public.fn_signup_customer_held(uuid)'::regprocedure,
                              'public.fn_signup_customer_shows_intent(public.customers)'::regprocedure)
                and (acl::text like '=%' or acl::text like 'anon=%' or acl::text like 'authenticated=%')) then
    raise exception 'CHK<<purgehold: a held-check routine is executable by public, anon or authenticated>>';
  end if;
end
$probe$;

select 'PROBE OK' as verdict;

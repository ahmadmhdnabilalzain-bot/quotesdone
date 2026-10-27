-- AN UNFINISHED SIGN-UP'S ARCHIVED MAIL GOES WITH IT.
--
-- Agent: it_engineer (owns the purge job, an_unfinished_sign_up_is_never_a_customer.sql). 13 Oct 2026.
-- scripts/checks/every_conversation_is_kept_and_the_sales_engineer_can_read_it.test.mjs ("every conversation
-- older than two hours has its PDF and its Dropbox queue row") failed on the full npm test:
--   {"total":1,"sample":["notifications:67170"],"pdfs_without_dropbox_row":1}
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 13 Oct 2026 07:00 UTC): notification 67170 (the
-- activation e-mail of 25 Sep to the one unfinished customer sign-up measured in ruling 1181) was removed by
-- signup_purge 5 at 12 Oct 11:05 UTC. The same purge removed its PDF from storage
-- (signup_purge_object backups/conversations/email/2026-09/notifications-67170.pdf, done 11:05:23) and its
-- Dropbox copy and CONV record (fn_signup_purge_backups, entity customer) -- but its public.conversation_archive
-- row stayed, pointing at a PDF that no longer exists. No other archive row is dangling in this way: the four
-- other archive rows whose source message is gone (notifications 37043-37045, wa_messages 530) still have their
-- Dropbox row.
-- ROOT CAUSE: fn_unfinished_signup_purge deletes a sign-up's outbox rows (public.notifications) but nothing
-- that DESCRIBES them: the conversation_archive row of each removed mail, and -- when the mail was filed as
-- Company correspondence rather than under the customer -- its CONV Dropbox copy.
--
-- WHAT THIS DOES:
--   * fn_signup_purge_mail(purge_id, email): for the mail it is about to delete, lists each archived PDF for the
--     storage removal the purge already runs (signup_purge_object), lists any CONV Dropbox copy of it for the
--     Dropbox removal (signup_purge_dropbox), and deletes the archive rows. Policy 1.6: "deleted in full".
--   * fn_unfinished_signup_purge calls it before each of its two outbox deletes. Nothing else in it changes.
--   * The one dangling row (notifications:67170) is removed by its exact key: its PDF, Dropbox copy and source
--     are already gone, so the row describes nothing. No other row is touched.
--
-- Prevented by: scripts/checks/every_conversation_is_kept_and_the_sales_engineer_can_read_it.test.mjs (live:
-- an archive row with no Dropbox row is a breach) and the verdict row at the end of this file.
--   node scripts/apply_sql.mjs scripts/sql/an_unfinished_sign_ups_archived_mail_goes_with_it.sql --apply --ddl --seat it_engineer

create or replace function public.fn_signup_purge_mail(p_purge_id bigint, p_email text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_pdf int; v_dbx int; v_rows int;
begin
  insert into public.signup_purge_object (purge_id, bucket, path)
  select p_purge_id, a.pdf_bucket, a.pdf_path
    from public.notifications n
    join public.conversation_archive a on a.source_table = 'notifications' and a.source_id = n.id::text
   where lower(n.to_email) = lower(p_email) and a.pdf_bucket is not null and a.pdf_path is not null
  on conflict do nothing;
  get diagnostics v_pdf = row_count;
  insert into public.signup_purge_dropbox (purge_id, doc_backup_id, dropbox_file)
  select p_purge_id, d.id, d.dropbox_path
    from public.notifications n
    join public.doc_backups d on d.dedupe_key = 'CONV:notifications:' || n.id
   where lower(n.to_email) = lower(p_email) and d.dropbox_path is not null
  on conflict (doc_backup_id) do nothing;
  get diagnostics v_dbx = row_count;
  update public.doc_backups d set status = 'signup_purge_pending', claimed_at = null, claimed_by = null,
         error = 'unfinished sign-up removed (signup_purge ' || p_purge_id || '): Dropbox copy and record to be deleted'
    from public.notifications n
   where d.dedupe_key = 'CONV:notifications:' || n.id and lower(n.to_email) = lower(p_email);
  delete from public.conversation_archive a using public.notifications n
   where a.source_table = 'notifications' and a.source_id = n.id::text and lower(n.to_email) = lower(p_email);
  get diagnostics v_rows = row_count;
  return jsonb_build_object('mail_pdfs_listed', v_pdf, 'mail_copies_listed', v_dbx, 'mail_archive_rows', v_rows);
end $function$;
revoke execute on function public.fn_signup_purge_mail(bigint, text) from public, anon, authenticated;


-- p_apply false: the plan only (who and why, no names). p_only_email: the probe's one row; it also lifts the
-- demo exclusion for that one address, and nothing else.
create or replace function public.fn_unfinished_signup_purge(p_apply boolean default false, p_limit integer default 20,
                                                             p_only_email text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c record; v_id bigint; v_n int; v_out jsonb := '[]'::jsonb; v_cnt jsonb; v_auth uuid; v_email text; v_keep boolean;
  n_done int := 0; n_held int := 0;
begin
  -- ── customers ──
  for c in
    select cu.id, lower(cu.email) email, cu.phone,
           least(cu.created_at, coalesce((select min(u.created_at) from auth.users u where lower(u.email) = lower(cu.email)), cu.created_at)) started,
           array_remove(array[case when not coalesce(cu.email_verified, false) then 'email' end,
                               case when not coalesce(cu.phone_verified, false) then 'mobile' end,
                               case when cu.tos_accepted_at is null then 'terms' end,
                               case when cu.tos_ip is null then 'terms_ip' end], null) missing,
           public.fn_signup_customer_held(cu.id) busy
      from public.customers cu
     where (p_only_email is null and not coalesce(cu.is_demo, false)) or lower(cu.email) = lower(p_only_email)
  loop
    continue when cardinality(c.missing) = 0;                       -- complete: never touched
    continue when c.started > now() - interval '30 minutes';        -- still inside its 30 minutes
    if c.busy then n_held := n_held + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'held', 'has a request, a sale, an upload, a draft, a signature or a conversation', 'missing', c.missing); continue; end if;
    exit when n_done >= greatest(1, least(coalesce(p_limit, 20), 200));
    if not p_apply then
      n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'missing', c.missing, 'started', c.started); continue;
    end if;
    insert into public.signup_purge (kind, subject_ref, started_at, missing)
    values ('customer', encode(sha256(convert_to(coalesce(c.email, c.id::text), 'UTF8')), 'hex'), c.started, c.missing) returning id into v_id;
    -- the partial uploads: what storage still holds for this sign-up (removed through the storage API)
    insert into public.signup_purge_object (purge_id, bucket, path)
    select v_id, x.bucket, x.path from (
      select 'signed-terms' bucket, cu.signed_terms_path path from public.customers cu where cu.id = c.id and cu.signed_terms_path is not null
      union select o.bucket_id, o.name from storage.objects o where o.bucket_id = 'drawing-files' and o.name like 'drawings/' || c.id || '/%'
      union select d.bucket, d.path from public.doc_backups d where d.entity = 'customer' and d.entity_id = c.id::text and d.bucket is not null and d.path is not null
    ) x where x.path is not null on conflict do nothing;
    -- the backups: Dropbox copies and records go too (dropbox_backup deletes the listed copies)
    v_cnt := public.fn_signup_purge_backups(v_id, 'customer', c.id::text);
    v_keep := public.fn_signup_email_kept_elsewhere(c.email, 'customer');
    if not v_keep then
      -- by e-mail only (the mobile was never verified), and only when no other account of this e-mail stays
      v_cnt := v_cnt || public.fn_signup_purge_mail(v_id, c.email);   -- its archived PDFs and copies first (13 Oct)
      delete from public.notifications n where lower(n.to_email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('outbox', v_n);
      delete from public.email_verifications e where lower(e.email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('email_otp', v_n);
      delete from public.phone_verifications p where lower(p.email) = c.email;
      get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('phone_otp', v_n);
    else
      v_cnt := v_cnt || jsonb_build_object('outbox', 0, 'email_otp', 0, 'phone_otp', 0, 'login', 'kept: another account of this e-mail is complete or held');
    end if;
    delete from public.inquiry_intake ii where ii.customer_id = c.id or lower(ii.email) = c.email;
    delete from public.drawing_redaction_runs r where r.customer_id = c.id or lower(r.owner_email) = c.email;
    delete from public.customer_preference p where p.customer_id = c.id;
    delete from public.customer_layout l where l.customer_id = c.id;
    delete from public.company_event e where e.entity_type = 'customer' and e.entity_id = c.id::text;
    delete from public.customers cu where cu.id = c.id;               -- customer_phone_otps and company_review_ask cascade
    -- the login is kept while another account of this e-mail is complete or held
    if not v_keep then
      delete from auth.users u where lower(u.email) = c.email;        -- sessions, identities and refresh tokens cascade
      get diagnostics v_n = row_count;
    else v_n := 0; end if;
    v_cnt := v_cnt || jsonb_build_object('auth_users', v_n);
    update public.signup_purge set counts = v_cnt || jsonb_build_object('objects', (select count(*) from public.signup_purge_object where purge_id = v_id)) where id = v_id;
    n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'customer', 'purge_id', v_id, 'missing', c.missing, 'counts', v_cnt);
  end loop;

  -- ── suppliers (a claimed company whose owner's sign-up is unfinished) ──
  for c in
    select l.id, lower(l.claimed_by) email, l.source,
           (l.invited_at is not null or l.invite_status is not null or coalesce(l.source, '') <> 'self_registered') invited,
           least(coalesce(l.portal_updated_at, l.created_at, now()), coalesce((select min(u.created_at) from auth.users u where lower(u.email) = lower(l.claimed_by)), now())) started,
           array_remove(array[case when not coalesce(l.owner_email_verified, false) then 'email' end,
                               case when not coalesce(l.owner_phone_verified, false) then 'mobile' end,
                               case when l.accepted_terms_at is null then 'terms' end,
                               case when l.accepted_terms_ip is null then 'terms_ip' end], null) missing,
           public.fn_signup_supplier_held(l.id) busy
      from public.leads l
     where l.claimed_by is not null
       and ((p_only_email is null and not coalesce(l.is_demo, false)) or lower(l.claimed_by) = lower(p_only_email))
  loop
    continue when cardinality(c.missing) = 0;
    continue when c.started > now() - interval '30 minutes';
    if c.busy then n_held := n_held + 1; v_out := v_out || jsonb_build_object('kind', 'supplier', 'held', 'has a quote, a sale, a match, an upload, a signature or a conversation', 'missing', c.missing); continue; end if;
    exit when n_done >= greatest(1, least(coalesce(p_limit, 20), 200));
    if not p_apply then
      n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', case when c.invited then 'supplier_invited_lead' else 'supplier_self_registered' end, 'missing', c.missing, 'started', c.started); continue;
    end if;
    insert into public.signup_purge (kind, subject_ref, started_at, missing)
    values (case when c.invited then 'supplier_invited_lead' else 'supplier_self_registered' end,
            encode(sha256(convert_to(coalesce(c.email, c.id::text), 'UTF8')), 'hex'), c.started, c.missing) returning id into v_id;
    v_email := c.email;
    v_keep := public.fn_signup_email_kept_elsewhere(v_email, 'supplier', c.id);
    v_cnt := '{}'::jsonb;
    if not v_keep then
      delete from public.email_verifications e where lower(e.email) = v_email;
      delete from public.phone_verifications p where lower(p.email) = v_email;
      -- an invited lead's mail is the campaign's (its invitation and follow-ups): never deleted; a self-registered
      -- company's mail to this address is the sign-up's own
      if not c.invited then
        v_cnt := v_cnt || public.fn_signup_purge_mail(v_id, v_email);
        delete from public.notifications n where lower(n.to_email) = v_email;
        get diagnostics v_n = row_count; v_cnt := v_cnt || jsonb_build_object('outbox', v_n);
      else v_cnt := jsonb_build_object('outbox', 0, 'outbox_kept', 'campaign mail of an invited lead'); end if;
    else
      v_cnt := jsonb_build_object('outbox', 0, 'login', 'kept: another account of this e-mail is complete or held');
    end if;
    if c.invited then
      -- campaign data stays: the lead goes back to the pool, unclaimed, with nothing of the sign-up on it
      update public.leads l set claimed = false, claimed_by = null, owner_email_verified = false, owner_phone_verified = false,
             owner_dob = null, accepted_terms_at = null, accepted_terms_version = null, accepted_terms_ip = null,
             accepted_terms_sha256 = null, accepted_terms_user_agent = null, signed_terms_path = null, portal_updated_at = now()
       where l.id = c.id;
      v_cnt := v_cnt || jsonb_build_object('lead', 'returned to the invited pool');
      -- what the sign-up uploaded or produced goes, as for any unfinished sign-up (policy 1.6 "deleted in full")
      insert into public.signup_purge_object (purge_id, bucket, path)
      select v_id, o.bucket_id, o.name from storage.objects o where o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) = c.id::text
      on conflict do nothing;
      v_cnt := v_cnt || public.fn_signup_purge_backups(v_id, 'supplier', c.id::text);
      update public.leads l set license_doc_path = null, egr_doc_path = null, insurance_doc_path = null, vat_doc_path = null,
             iso_doc_path = null, manufacturer_auth_doc_path = null, company_profile_doc_path = null, catalog_doc_paths = null
       where l.id = c.id;
    else
      insert into public.signup_purge_object (purge_id, bucket, path)
      select v_id, d.bucket, d.path from public.doc_backups d
       where d.entity = 'supplier' and d.entity_id = c.id::text and d.bucket is not null and d.path is not null
      union select v_id, o.bucket_id, o.name from storage.objects o where o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) = c.id::text
      on conflict do nothing;
      v_cnt := v_cnt || public.fn_signup_purge_backups(v_id, 'supplier', c.id::text);
      begin
        delete from public.leads l where l.id = c.id;
        v_cnt := v_cnt || jsonb_build_object('lead', 'removed');
      exception when foreign_key_violation then
        -- something else already points at the company: it is unclaimed instead, and the purge says so
        update public.leads l set claimed = false, claimed_by = null, owner_email_verified = false, owner_phone_verified = false,
               owner_dob = null, accepted_terms_at = null, accepted_terms_version = null, accepted_terms_ip = null,
               accepted_terms_sha256 = null, accepted_terms_user_agent = null, signed_terms_path = null, portal_updated_at = now()
         where l.id = c.id;
        v_cnt := v_cnt || jsonb_build_object('lead', 'unclaimed (still referenced: ' || left(sqlerrm, 120) || ')');
      end;
    end if;
    if not v_keep then
      delete from auth.users u where lower(u.email) = v_email;
      get diagnostics v_n = row_count;
    else v_n := 0; end if;
    v_cnt := v_cnt || jsonb_build_object('auth_users', v_n);
    update public.signup_purge set counts = v_cnt where id = v_id;
    n_done := n_done + 1; v_out := v_out || jsonb_build_object('kind', 'supplier', 'purge_id', v_id, 'missing', c.missing, 'counts', v_cnt);
  end loop;

  -- the customer register is rebuilt from the table when a customer row went (audit 12 Oct: it listed 7 for 6)
  if p_apply and p_only_email is null and exists (select 1 from jsonb_array_elements(v_out) i where i->>'kind' = 'customer' and i ? 'purge_id') then
    begin
      perform net.http_post('https://' || public.qd_project_ref() || '.supabase.co/functions/v1/compliance_archive',
        jsonb_build_object('__secret', (select value from public.app_secrets where key = 'cred_db_internal'), 'action', 'register'),
        '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
    exception when others then null;    -- the register is rebuilt again at the next registration
    end;
  end if;
  if p_apply and n_done > 0 and p_only_email is null then
    -- counts only: no name, no e-mail, no file (the coordinator, 12 Oct 2026)
    insert into public.agent_actions (agent, kind, status, risk, title, detail, decided_at, decided_by)
    values ('it_engineer', 'signup_purge', 'done', 'low', 'Unfinished sign-ups removed (founder ruling 1181)',
            jsonb_build_object('removed', n_done, 'held', n_held,
              'customers', (select count(*) from jsonb_array_elements(v_out) i where i->>'kind' = 'customer' and i ? 'purge_id'),
              'suppliers', (select count(*) from jsonb_array_elements(v_out) i where i->>'kind' = 'supplier' and i ? 'purge_id')),
            now(), 'it_engineer');
  end if;
  return jsonb_build_object('apply', p_apply, 'removed', n_done, 'held', n_held, 'items', v_out);
end $function$;

-- the one dangling row, by its exact key (measured above: its PDF, Dropbox copy and source are already gone)
delete from public.conversation_archive a
 where a.source_table = 'notifications' and a.source_id = '67170'
   and not exists (select 1 from public.notifications n where n.id = 67170)
   and not exists (select 1 from storage.objects o where o.bucket_id = a.pdf_bucket and o.name = a.pdf_path);

select case
  when to_regprocedure('public.fn_signup_purge_mail(bigint,text)') is null then 'PROBE FAILED: fn_signup_purge_mail missing'
  when has_function_privilege('anon', 'public.fn_signup_purge_mail(bigint,text)', 'execute')
    or has_function_privilege('authenticated', 'public.fn_signup_purge_mail(bigint,text)', 'execute')
    then 'PROBE FAILED: fn_signup_purge_mail is executable by a client role'
  when (select count(*) from pg_proc where proname = 'fn_unfinished_signup_purge'
          and prosrc like '%fn_signup_purge_mail(v_id, c.email)%' and prosrc like '%fn_signup_purge_mail(v_id, v_email)%') <> 1
    then 'PROBE FAILED: the purge does not remove the archived mail in both branches'
  when ((public.fn_conversation_retention_breaches(interval '2 hours'))->>'pdfs_without_dropbox_row')::int <> 0
    then 'PROBE FAILED: an archived PDF still has no Dropbox row'
  else 'PROBE OK' end as verdict;

-- an_unfinished_sign_up_is_never_a_customer.sql
--
-- Assigned: it_engineer (the deterministic purge job and its proof); customer_support owns the sign-up it
-- protects. Founder ruling 1181 (12 Oct 2026): "an unfinished sign-up is never a customer". 30 minutes after
-- a sign-up starts, if the e-mail, the mobile OTP and the signed terms with the IP are not ALL done, everything
-- of it is removed: the customers row, the auth user (its sessions go with it), the OTP rows, the outbox items,
-- and any partial uploads (storage objects, removed by dropbox_backup through the storage API) and backups
-- (their Dropbox copies are MOVED to _archive/unfinished-signups/, never deleted). Nothing is kept and nothing
-- is sent; there is no reminder.
--   * A supplier sign-up on a lead from the invited pool does NOT delete the lead (campaign data): the lead is
--     put back to its unclaimed state and only the partial account, auth user and OTP rows are removed.
--   * A supplier sign-up with no lead behind it (source self_registered) is removed like a customer's.
--   * The guard is the COMPLETION FIELDS, never time alone: a sign-up with all four done is never touched,
--     whatever its age. A customer or company that already has a request, a sale or a quote is never removed
--     by this job (it is counted as 'held' for the it_engineer instead).
--   * Demo rows (is_demo) are left to the harness that made them.
-- Measured 12 Oct 2026 before this file: 1 customer (email verified, mobile not verified, terms never accepted;
-- he received a "Your first request on QuotesDone" activation e-mail on 25 Sep) and 1 self-registered company
-- (same state) are unfinished; 4 customers and 0 companies are complete.
--
-- prevented by: scripts/checks/an_unfinished_sign_up_is_never_a_customer.test.mjs and the probe at the end.

create table if not exists public.signup_purge (
  id bigserial primary key,
  kind text not null check (kind in ('customer', 'supplier_self_registered', 'supplier_invited_lead')),
  subject_ref text not null,          -- sha256 of the e-mail: what was removed is not kept, only that it was
  started_at timestamptz,
  purged_at timestamptz not null default now(),
  missing text[] not null,            -- which of email / mobile / terms / terms_ip were not done
  counts jsonb not null default '{}'::jsonb
);
create table if not exists public.signup_purge_object (
  id bigserial primary key,
  purge_id bigint not null references public.signup_purge(id) on delete cascade,
  bucket text not null,
  path text not null,
  done_at timestamptz,
  error text,
  unique (bucket, path)
);
alter table public.signup_purge enable row level security;
alter table public.signup_purge_object enable row level security;
drop policy if exists signup_purge_service_role_only on public.signup_purge;
create policy signup_purge_service_role_only on public.signup_purge as permissive for all to public using (false) with check (false);
drop policy if exists signup_purge_object_service_role_only on public.signup_purge_object;
create policy signup_purge_object_service_role_only on public.signup_purge_object as permissive for all to public using (false) with check (false);
revoke all on public.signup_purge, public.signup_purge_object from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('signup_purge', false, 'log', 'One row per unfinished sign-up removed (kind, hashed e-mail, what was missing, counts): a log of the purge job, never personal data.', 'it_engineer'),
  ('signup_purge_object', false, 'log', 'The storage objects an unfinished sign-up left, until dropbox_backup removes them through the storage API.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- WHAT HOLDS A SIGN-UP (release review of #1292, 12 Oct 2026): a request, a sale, an order, a quote or a match; a
-- signature; a draft request (inquiry_intake); a conversation (portal chat, assistant, inbound e-mail, contact
-- form, complaint). A held sign-up is counted, never removed.
-- AN UPLOAD DOES NOT HOLD IT (founder, under ruling 1181, 12 Oct 2026: "the held self-registered company is deleted
-- ... with its uploads to _archive, never deleted"): the sign-up is removed and every file it uploaded is MOVED to
-- _archive/unfinished-signups/ in storage and in Dropbox (dropbox_backup), never deleted.
create or replace function public.fn_signup_customer_held(p_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select exists (select 1 from public.inquiries i where i.customer_id = cu.id)
      or exists (select 1 from public.transactions t where t.customer_id = cu.id)
      or exists (select 1 from public.po_orders p where p.customer_id = cu.id)
      or cu.signed_terms_path is not null
      or exists (select 1 from public.inquiry_intake ii where ii.customer_id = cu.id or lower(ii.email) = lower(cu.email))
      or exists (select 1 from public.messages m where m.customer_id = cu.id)
      or exists (select 1 from public.assistant_logs a where a.audience = 'customer:' || cu.id::text)
      or exists (select 1 from public.inbound_messages im where lower(im.from_email) = lower(cu.email))
      or exists (select 1 from public.contact_messages cm where lower(cm.email) = lower(cu.email))
      or exists (select 1 from public.complaint_tickets ct where lower(ct.email) = lower(cu.email))
    from public.customers cu where cu.id = p_id;
$function$;
revoke execute on function public.fn_signup_customer_held(uuid) from public, anon, authenticated;

create or replace function public.fn_signup_supplier_held(p_id bigint)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select exists (select 1 from public.quotes q where q.supplier_id = l.id)
      or exists (select 1 from public.transactions t where t.supplier_id = l.id)
      or exists (select 1 from public.inquiry_matches im where im.supplier_id = l.id)
      or l.signed_terms_path is not null
      or exists (select 1 from public.messages m where m.supplier_id = l.id)
      or exists (select 1 from public.inbound_messages i2 where i2.lead_id = l.id or lower(i2.from_email) = lower(l.claimed_by))
    from public.leads l where l.id = p_id;
$function$;
revoke execute on function public.fn_signup_supplier_held(bigint) from public, anon, authenticated;

-- One login can hold several accounts: a customer and one or more claimed companies. While ANY other account of
-- the same e-mail (the other role, or another company of the same owner: p_except_lead) is COMPLETE or HELD, the
-- unfinished one is removed alone: the login, its OTPs and its outbox stay (release review 12 Oct, rounds 2-3).
create or replace function public.fn_signup_email_kept_elsewhere(p_email text, p_role text, p_except_lead bigint default null)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select exists (select 1 from public.leads l where lower(l.claimed_by) = lower(p_email)
                   and (p_role = 'customer' or l.id is distinct from p_except_lead)
                   and ((coalesce(l.owner_email_verified, false) and coalesce(l.owner_phone_verified, false)
                         and l.accepted_terms_at is not null and l.accepted_terms_ip is not null)
                        or public.fn_signup_supplier_held(l.id)
                        -- a sign-up in the other role still inside its own 30 minutes keeps the login too
                        or least(coalesce(l.portal_updated_at, l.created_at, now()), now()) > now() - interval '30 minutes'))
      or (p_role <> 'customer' and exists (select 1 from public.customers c where lower(c.email) = lower(p_email)
                   and ((coalesce(c.email_verified, false) and coalesce(c.phone_verified, false)
                         and c.tos_accepted_at is not null and c.tos_ip is not null)
                        or public.fn_signup_customer_held(c.id)
                        or c.created_at > now() - interval '30 minutes')));
$function$;
revoke execute on function public.fn_signup_email_kept_elsewhere(text, text, bigint) from public, anon, authenticated;

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
    -- the backups: their Dropbox copies go to _archive (dropbox_backup), never deleted
    update public.doc_backups d set status = 'archive_pending', claimed_at = null, claimed_by = null,
           error = 'unfinished sign-up removed (signup_purge ' || v_id || '): Dropbox copy to _archive'
     where d.entity = 'customer' and d.entity_id = c.id::text and d.status not in ('archived', 'archive_pending');
    get diagnostics v_n = row_count; v_cnt := jsonb_build_object('backups_to_archive', v_n);
    v_keep := public.fn_signup_email_kept_elsewhere(c.email, 'customer');
    if not v_keep then
      -- by e-mail only (the mobile was never verified), and only when no other account of this e-mail stays
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
        delete from public.notifications n where lower(n.to_email) = v_email;
        get diagnostics v_n = row_count; v_cnt := jsonb_build_object('outbox', v_n);
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
    else
      insert into public.signup_purge_object (purge_id, bucket, path)
      select v_id, d.bucket, d.path from public.doc_backups d
       where d.entity = 'supplier' and d.entity_id = c.id::text and d.bucket is not null and d.path is not null
      union select v_id, o.bucket_id, o.name from storage.objects o where o.bucket_id = 'supplier-docs' and split_part(o.name, '/', 2) = c.id::text
      on conflict do nothing;
      update public.doc_backups d set status = 'archive_pending', claimed_at = null, claimed_by = null,
             error = 'unfinished sign-up removed (signup_purge ' || v_id || '): Dropbox copy to _archive'
       where d.entity = 'supplier' and d.entity_id = c.id::text and d.status not in ('archived', 'archive_pending');
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
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'unfinished_signup_purge', 'removed', n_done, 'held', n_held),
            'Unfinished sign-ups removed (founder ruling 1181): ' || n_done || ', held because a request, quote or sale exists: ' || n_held || '.', now(), now());
  end if;
  return jsonb_build_object('apply', p_apply, 'removed', n_done, 'held', n_held, 'items', v_out);
end $function$;
revoke execute on function public.fn_unfinished_signup_purge(boolean, integer, text) from public, anon, authenticated;

-- every 5 minutes, owned by the it_engineer
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'unfinished_signup_purge', 'it_engineer',
   'fn_unfinished_signup_purge(true) every 5 minutes: an unfinished sign-up older than 30 minutes is removed (founder ruling 1181).',
   'scripts/sql/an_unfinished_sign_up_is_never_a_customer.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;
select cron.schedule('unfinished_signup_purge', '*/5 * * * *', $CRON$select public.fn_unfinished_signup_purge(true)$CRON$);

-- ── the storage sweep leaves an archived sign-up's files alone (they are in Dropbox _archive already) ──
-- (live definition of 12 Oct 2026, one line added)
CREATE OR REPLACE FUNCTION public.fn_backup_sweep_objects()
 RETURNS TABLE(bucket text, path text, bytes bigint, created_at timestamp with time zone, entity text, entity_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The cheap filters first, once: without the fence the planner evaluated the owner lookups below for
  -- every object of every swept bucket, 8,369 export pages included (47.8 s measured; 125 ms with it).
  with o as materialized (
    select o.bucket_id, o.name, o.metadata, o.created_at
      from storage.objects o
     where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r
                            where r.kind = 'bucket' and r.backed_up and r.enqueue_rule like '%STORAGE SWEEP%')
       and right(o.name, 1) <> '/' and o.name !~ '(^|/)\.emptyFolderPlaceholder$'
       and o.name !~* 'zz[ _-]?demo'
       -- an unfinished sign-up's files moved to _archive/unfinished-signups/ (fn_unfinished_signup_purge, ruling 1181):
       -- their Dropbox copies are already in _archive, so the sweep never files them a second time
       and left(o.name, 9) <> '_archive/'
       and not (o.bucket_id = 'backups' and o.name ~ '^(\d{4}-\d{2}-\d{2}|conversations)/')
       and not (o.bucket_id = 'signed-terms' and o.name like 'registers/%')
       and not exists (select 1 from public.pdpl_erase_files e where e.bucket = o.bucket_id and e.storage_path = o.name))
  select o.bucket_id, o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at, x.entity, x.id
    from o
    cross join lateral (select
        (regexp_match(o.name, '^generated/\d+_(customer_details|inquiry_summary|comparison|supplier_details)_([0-9a-f_]{36}|\d{1,18})\.pdf$', 'i')) as gen,
        split_part(o.name, '/', 2) as seg2, split_part(o.name, '/', 3) as seg3) p
    -- OFFSET 0 keeps this a subquery computed once per row; flattened, it was copied into every reference.
    cross join lateral (select coalesce(
        (select case d.ref_table when 'customers' then 'customer' when 'inquiries' then 'inquiry'
                                 when 'quotes' then 'quote' when 'leads' then 'supplier' end || ':' || d.ref_id
           from public.documents d
          where d.bucket = o.bucket_id and d.path = o.name
            and d.ref_table in ('customers', 'inquiries', 'quotes', 'leads') and coalesce(d.ref_id, '') <> '' limit 1),
        (select 'customer:' || c.customer_id from public.quote_pdf_cache c
          where c.bucket = o.bucket_id and c.path = o.name and c.customer_id is not null limit 1),
        (select 'customer:' || t.customer_id from public.reveal_invoices ri join public.transactions t on t.id = ri.transaction_id
          where ri.bucket = o.bucket_id and ri.path = o.name and t.customer_id is not null limit 1),
        (select 'quote:' || q.id from public.quotes q where o.bucket_id = 'quote-files' and q.original_file_path = o.name limit 1),
        case when o.bucket_id = 'backups' and p.gen is not null then
               case lower(p.gen[1]) when 'customer_details' then 'customer' when 'supplier_details' then 'supplier' else 'inquiry' end
               || ':' || replace(lower(p.gen[2]), '_', '-') end,
        case when o.bucket_id = 'supplier-docs' and p.seg2 ~ '^\d{1,18}$' then 'supplier:' || p.seg2 end,
        case when o.bucket_id = 'drawing-files' and p.seg2 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg2) end,
        case when o.bucket_id = 'quote-files' and p.seg3 ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then 'inquiry:' || lower(p.seg3) end,
        'company:storage/' || o.bucket_id) as owner
      offset 0) y
    cross join lateral (select split_part(y.owner, ':', 1) as entity, substr(y.owner, strpos(y.owner, ':') + 1) as id) x
    -- the owner row behind it: is it demo (null when the row is gone), and which customer email, for PDPL.
    -- Each cast is inside CASE behind the shape test that makes it safe.
    left join lateral (select
        case x.entity
          when 'supplier' then (select coalesce(l.is_demo, false) from public.leads l
                                 where l.id = case when x.id ~ '^\d{1,18}$' then x.id::bigint end)
          when 'customer' then (select coalesce(c.is_demo, false) from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select coalesce(c.is_demo, false) from public.inquiries i left join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select coalesce(l.is_demo, false) or coalesce(c.is_demo, false)
                                  from public.quotes q left join public.leads l on l.id = q.supplier_id
                                  left join public.inquiries i on i.id = q.inquiry_id left join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as demo,
        case x.entity
          when 'customer' then (select c.email from public.customers c
                                 where c.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'inquiry'  then (select c.email from public.inquiries i join public.customers c on c.id = i.customer_id
                                 where i.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
          when 'quote'    then (select c.email from public.quotes q join public.inquiries i on i.id = q.inquiry_id
                                  join public.customers c on c.id = i.customer_id
                                 where q.id = case when x.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then x.id::uuid end)
        end as email
      offset 0) w on true
   where not coalesce(w.demo, false)
     and not (x.entity <> 'company' and w.demo is null
              and exists (select 1 from public.doc_backups z where z.entity = 'zz_demo' and z.entity_id = x.id))
     and not (w.email is not null and (w.email ~* '@removed\.invalid$'
              or exists (select 1 from public.pdpl_requests r
                          where r.kind = 'delete' and coalesce(r.status, '') not in ('rejected', 'withdrawn', 'cancelled')
                            and lower(r.email) = lower(w.email))));
$function$;

-- ── probe: complete sign-ups untouched, an unfinished one removed, an invited lead returned; nothing left ──
do $probe$
declare v_fail text := ''; r jsonb; v_c1 uuid := gen_random_uuid(); v_c2 uuid := gen_random_uuid(); v_c3 uuid := gen_random_uuid(); v_l bigint; v_l2 bigint;
begin
  insert into public.customers (id, email, full_name, email_verified, phone_verified, tos_accepted_at, tos_ip, created_at)
  values (v_c1, 'probe-unfinished-1181@example.invalid', 'Probe Unfinished', true, false, null, null, now() - interval '2 hours'),
         (v_c2, 'probe-complete-1181@example.invalid', 'Probe Complete', true, true, now() - interval '2 hours', '10.0.0.1', now() - interval '2 hours');
  r := public.fn_unfinished_signup_purge(false, 20, 'probe-complete-1181@example.invalid');
  if (r->>'removed')::int <> 0 then v_fail := v_fail || ' complete_planned'; end if;
  r := public.fn_unfinished_signup_purge(true, 20, 'probe-complete-1181@example.invalid');
  if not exists (select 1 from public.customers where id = v_c2) then v_fail := v_fail || ' complete_removed'; end if;
  r := public.fn_unfinished_signup_purge(true, 20, 'probe-unfinished-1181@example.invalid');
  if exists (select 1 from public.customers where id = v_c1) or (r->>'removed')::int <> 1 then v_fail := v_fail || ' unfinished_kept:' || r::text; end if;
  -- an invited lead: claimed by an unfinished sign-up, returned to the pool (not deleted)
  insert into public.leads (company_name, email, invited_at, invite_status, claimed, claimed_by, owner_email_verified, created_at, portal_updated_at, tags)
  values ('Probe Invited Co 1181', 'probe-lead-1181@example.invalid', now() - interval '3 days', 'invited', true, 'probe-owner-1181@example.invalid', true, now() - interval '3 days', now() - interval '2 hours', array['qd_demo'])
  returning id into v_l;
  r := public.fn_unfinished_signup_purge(true, 20, 'probe-owner-1181@example.invalid');
  if not exists (select 1 from public.leads where id = v_l and not claimed and claimed_by is null) then v_fail := v_fail || ' invited_lead:' || r::text; end if;
  -- an unfinished sign-up that SIGNED something is HELD, not removed (an upload alone does not hold it)
  insert into public.customers (id, email, full_name, email_verified, phone_verified, signed_terms_path, created_at)
  values (v_c1, 'probe-held-1181@example.invalid', 'Probe Held', true, false, 'customers/probe_held_1181.pdf', now() - interval '2 hours');
  r := public.fn_unfinished_signup_purge(true, 20, 'probe-held-1181@example.invalid');
  if not exists (select 1 from public.customers where id = v_c1) or (r->>'held')::int <> 1 then v_fail := v_fail || ' signature_not_held:' || r::text; end if;
  -- a login that is a complete account in the other role is never removed
  insert into public.leads (company_name, email, claimed, claimed_by, owner_email_verified, owner_phone_verified, accepted_terms_at, accepted_terms_ip, created_at, tags)
  values ('Probe Complete Co 1181', 'probe-co-1181@example.invalid', true, 'probe-both-1181@example.invalid', true, true, now(), '10.0.0.2', now(), array['qd_demo']);
  if not public.fn_signup_email_kept_elsewhere('probe-both-1181@example.invalid', 'customer') then v_fail := v_fail || ' cross_role'; end if;
  if public.fn_signup_email_kept_elsewhere('probe-nobody-1181@example.invalid', 'customer') then v_fail := v_fail || ' cross_role_false_positive'; end if;
  delete from public.leads where company_name = 'Probe Complete Co 1181';
  -- ... and while it is a HELD (unfinished but signed) account in the other role
  insert into public.leads (company_name, email, claimed, claimed_by, owner_email_verified, signed_terms_path, created_at, tags)
  values ('Probe Held Co 1181', 'probe-co2-1181@example.invalid', true, 'probe-both2-1181@example.invalid', true, 'suppliers/probe_1181.pdf', now(), array['qd_demo']);
  if not public.fn_signup_email_kept_elsewhere('probe-both2-1181@example.invalid', 'customer') then v_fail := v_fail || ' cross_role_held'; end if;
  delete from public.leads where company_name = 'Probe Held Co 1181';
  -- round 3 (1): an unfinished CUSTOMER sign-up of an e-mail that is a COMPLETE supplier owner: the customer row
  -- goes; the shared outbox and OTP rows stay
  insert into public.leads (company_name, email, claimed, claimed_by, owner_email_verified, owner_phone_verified, accepted_terms_at, accepted_terms_ip, created_at, tags)
  values ('Probe Shared Co 1181', 'probe-sco-1181@example.invalid', true, 'probe-shared-1181@example.invalid', true, true, now(), '10.0.0.3', now(), array['qd_demo']);
  insert into public.customers (id, email, full_name, email_verified, phone_verified, created_at)
  values (v_c3, 'probe-shared-1181@example.invalid', 'Probe Shared', true, false, now() - interval '2 hours');
  insert into public.notifications (type, channel, status, to_email, subject, body) values ('zz_probe_1181', 'email', 'sent', 'probe-shared-1181@example.invalid', 'probe 1181', 'probe');
  insert into public.email_verifications (email, expires_at) values ('probe-shared-1181@example.invalid', now() + interval '1 hour');
  r := public.fn_unfinished_signup_purge(true, 20, 'probe-shared-1181@example.invalid');
  if exists (select 1 from public.customers where id = v_c3) then v_fail := v_fail || ' shared_customer_kept'; end if;
  if not exists (select 1 from public.notifications where to_email = 'probe-shared-1181@example.invalid')
     or not exists (select 1 from public.email_verifications where email = 'probe-shared-1181@example.invalid') then v_fail := v_fail || ' shared_mail_or_otp_deleted:' || r::text; end if;
  delete from public.notifications where to_email = 'probe-shared-1181@example.invalid';
  delete from public.email_verifications where email = 'probe-shared-1181@example.invalid';
  -- round 3 (3): one owner with two companies cannot exist (leads_claimed_by_lower_uidx: one claimed company per
  -- e-mail); the same-role check in fn_signup_email_kept_elsewhere still covers it, and the index is asserted here
  if not exists (select 1 from pg_indexes where tablename = 'leads' and indexname = 'leads_claimed_by_lower_uidx' and indexdef ilike 'create unique index%') then
    v_fail := v_fail || ' one_company_per_owner_index_missing';
  end if;
  select id into v_l2 from public.leads where company_name = 'Probe Shared Co 1181';
  if public.fn_signup_email_kept_elsewhere('probe-shared-1181@example.invalid', 'supplier', v_l2) then v_fail := v_fail || ' same_role_counts_itself'; end if;
  delete from public.leads where company_name in ('Probe Shared Co 1181', 'Probe Second Co 1181');
  delete from public.signup_purge where subject_ref = encode(sha256(convert_to('probe-shared-1181@example.invalid', 'UTF8')), 'hex');
  -- clean up and prove nothing is left
  delete from public.customers where id in (v_c1, v_c2, v_c3);
  delete from public.leads where id = v_l;
  delete from public.signup_purge where subject_ref in (encode(sha256(convert_to('probe-unfinished-1181@example.invalid', 'UTF8')), 'hex'),
                                                         encode(sha256(convert_to('probe-owner-1181@example.invalid', 'UTF8')), 'hex'));
  if exists (select 1 from public.customers where email like 'probe-%-1181@example.invalid')
     or exists (select 1 from public.leads where company_name = 'Probe Invited Co 1181')
     or exists (select 1 from public.agent_runs where counts->>'job' = 'unfinished_signup_purge' and started_at > now() - interval '1 minute' and note like '%probe%') then
    v_fail := v_fail || ' probe_rows_left';
  end if;
  perform set_config('qd.probe_1181', coalesce(nullif(v_fail, ''), 'ok'), true);
end $probe$;
select case when current_setting('qd.probe_1181', true) = 'ok' then 'PROBE OK'
            else 'PROBE FAILED: ' || coalesce(current_setting('qd.probe_1181', true), 'no verdict') end as verdict;

-- THE ROW AND THE KERNEL NAME THE SAME TERMS VERSION (6 Sep 2026). Follows
-- the_customer_accepts_and_the_step_can_execute.sql and the_acceptance_the_product_writes_reaches_the_kernel.sql.
--
-- THE LATENT DEFECT (measured by the adversarial verifier, aborted probes, 6 Sep 2026). On the z56 path
-- -- kyc.accept_terms writes customers.tos_accepted_at / tos_version, the AFTER UPDATE trigger calls
-- fn_customer_terms_accept, which records the acceptance against the PUBLISHED customer terms
-- (public.legal_documents: version + sha256) and writes that version back to the row -- the row's
-- tos_version was NOT re-aligned, contrary to the function's own comment ("keep the product's own
-- fast-path columns in step"). The BEFORE UPDATE trigger qd_norm_customer_ver resets NEW.tos_version
-- := OLD.tos_version whenever an UPDATE leaves tos_accepted_at unchanged, which is exactly the nested
-- "coalesce(tos_accepted_at, now())" UPDATE inside the trigger chain. Probe 1 (via z56): row
-- 'probe-literal', kernel record v5. Today it is invisible because kyc stamps
-- app_secrets.customer_terms_version, which happens to equal the published v5; the day the secret and
-- the registry disagree, the row and the kernel record name different documents.
--
-- TWO ROOTS, TWO SMALL CHANGES.
--
-- 1. TWO "SINGLE SOURCES" OF THE VERSION IN FORCE. fn_terms_version (2 Aug 2026) resolved the version
--    from app_secrets, which was the only place a version lived then. Since 23 Aug the legal registry
--    public.legal_documents is what the kernel judges an acceptance against (BR-025 reads the version
--    and sha256 there; public.phase_d_acceptance_document maps each acceptance object to its slug), and
--    since 6 Sep the registry is kept from the published pages by trigger. fn_terms_version now answers
--    REGISTRY FIRST -- the document phase_d_acceptance_document names for the kind, newest
--    effective_date -- and falls back to the app_secrets label only when the registry has no row. One
--    resolver, one answer, for the normalisers on customers and leads alike.
--
-- 2. THE NORMALISER MAY NOT BLOCK THE ACCEPTANCE'S OWN RE-ALIGNMENT. qd_norm_customer_ver keeps its
--    rule -- a recorded acceptance is evidence and is never rewritten -- with ONE named exception:
--    inside the acceptance transition's own trigger chain (pg_trigger_depth() > 1: kyc's UPDATE ->
--    z56 -> fn_customer_terms_accept -> nested UPDATE), an explicitly supplied tos_version that EQUALS
--    the version the registry publishes now is kept. That is the value fn_customer_terms_accept just
--    recorded in the kernel, so the row and the record can never name different documents. A hand
--    call on a legacy row (depth 1), a save_customer edit, a re-stamp with any other value: all still
--    discarded, exactly as before.
--
-- Not changed: fn_customer_terms_accept (its UPDATE now takes effect), qd_norm_supplier_ver (it reads
-- the same resolver and needs nothing else), kyc (it still stamps the secret's label first; the z56
-- chain corrects it to the registry's within the same statement).
--
-- Proven in an aborted probe inside this file: a ZZ DEMO customer (@example.invalid) registers and
-- accepts with tos_version = 'probe-literal' (a stale secret), and after the trigger chain the row
-- carries the published version and so does the kernel record; the sub-transaction is rolled back.
--
--   node scripts/apply_sql.mjs scripts/sql/the_row_and_the_kernel_name_the_same_terms_version.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_terms_version(p_kind text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    -- 1. The legal registry: the document the kernel's acceptance object names for this kind, newest
    --    effective_date first (version is a label, not an order). This is the pair BR-025 judges.
    (select d.version
       from public.phase_d_acceptance_document a
       join public.legal_documents d on d.slug = a.document_slug
      where a.object_id = case lower(p_kind) when 'supplier' then 'supplier_terms_acceptance'
                                             when 'customer' then 'customer_terms_acceptance' end
        and nullif(btrim(d.version), '') is not null
      order by d.effective_date desc nulls last, d.version desc
      limit 1),
    -- 2. The app_secrets label, the only source before the registry existed.
    nullif((select a.value from public.app_secrets a
             where a.key = case lower(p_kind) when 'supplier' then 'terms_version'
                                              when 'customer' then 'customer_terms_version' end), ''),
    'unversioned');
$function$;

CREATE OR REPLACE FUNCTION public.qd_norm_customer_ver()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if TG_OP = 'UPDATE' then
    if NEW.tos_accepted_at is not distinct from OLD.tos_accepted_at then
      -- Not a new acceptance: the recorded version is evidence and is never rewritten -- except
      -- (6 Sep 2026) by the acceptance's own trigger chain re-aligning the row to the version the
      -- registry publishes now, which is the version fn_customer_terms_accept just recorded in the
      -- kernel. Depth > 1 means we are inside z56's chain, not a later hand call or a profile edit.
      if pg_trigger_depth() > 1
         and NEW.tos_version is distinct from OLD.tos_version
         and NEW.tos_version = public.fn_terms_version('customer') then
        return NEW;
      end if;
      NEW.tos_version := OLD.tos_version;
      return NEW;
    end if;
    if NEW.tos_version is not distinct from OLD.tos_version then
      NEW.tos_version := public.fn_terms_version('customer');
      return NEW;
    end if;
  end if;
  if NEW.tos_accepted_at is not null and coalesce(NEW.tos_version,'') = '' then
    NEW.tos_version := public.fn_terms_version('customer');
  end if;
  return NEW;
end $function$;

-- Ownership ledger follows the manifest (conventions step 4): both routines move from the 2 Aug
-- migration to this file.
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification)
values
  ('public','fn_terms_version','p_kind text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_row_and_the_kernel_name_the_same_terms_version.sql','MANIFEST',
   'scripts/sql/the_row_and_the_kernel_name_the_same_terms_version.sql', null),
  ('public','qd_norm_customer_ver','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT',
   'canonical file scripts/sql/the_row_and_the_kernel_name_the_same_terms_version.sql','MANIFEST',
   'scripts/sql/the_row_and_the_kernel_name_the_same_terms_version.sql', null)
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  justification = excluded.justification;

do $proof$
declare
  v_cid   uuid := gen_random_uuid();
  v_email text;
  v_pub   text;
  v_reg   text;
  v_row   text;
  v_rec   text;
  v_hash  text;
  v_err   int;
  v_hand  text;
begin
  -- The resolver answers from the registry (customer-terms via phase_d_acceptance_document).
  v_pub := public.fn_terms_version('customer');
  select d.version into v_reg from public.legal_documents d
   where d.slug = (select document_slug from public.phase_d_acceptance_document where object_id = 'customer_terms_acceptance')
   order by d.effective_date desc nulls last, d.version desc limit 1;
  if v_pub is distinct from v_reg then
    raise exception 'fn_terms_version(customer) = % but the registry publishes %', v_pub, v_reg;
  end if;

  -- ABORTED PROBE: register, accept with a stale label, read what the row and the kernel hold, roll back.
  begin
    v_email := 'zz-demo-' || substr(v_cid::text, 1, 8) || '@example.invalid';
    insert into public.rehearsal_window (run_tag, opened_by, started_at, note)
    values ('fix21-tosver-' || substr(v_cid::text, 1, 8), 'worktree-wf_9d4fde26-79c-6-fix', now(),
            'aborted-transaction probe: acceptance re-aligns tos_version to the registry');
    insert into public.customers (id, email, full_name, phone, email_verified, locale)
    values (v_cid, v_email, 'ZZ DEMO — tos_version probe', '+971500000000', true, 'en');
    -- Exactly the UPDATE the deployed kyc.accept_terms issues, with a label the registry does not publish.
    update public.customers set tos_accepted_at = now(), tos_version = 'probe-literal', tos_ip = '203.0.113.9'
     where id = v_cid;
    select tos_version into v_row from public.customers where id = v_cid;
    select payload->>'terms_version', left(payload->>'terms_hash', 16) into v_rec, v_hash
      from public.phase_d_object_record
     where object_id = 'customer_terms_acceptance' and owner_ref = v_cid::text
     order by record_id desc limit 1;
    select count(*) into v_err from public.error_events
     where source = 'customer_terms_accepted_trg' and (detail->>'customer_id') = v_cid::text;
    -- A later hand call (depth 1) on the accepted row may NOT rewrite the evidence to anything else.
    update public.customers set tos_version = 'later-literal' where id = v_cid;
    select tos_version into v_hand from public.customers where id = v_cid;
    raise exception using errcode = 'P0999', message = 'probe rollback';
  exception when sqlstate 'P0999' then
    null;
  end;

  if v_err <> 0 then
    raise exception 'z56 chain wrote % error_events for the probe customer', v_err;
  end if;
  if v_rec is distinct from v_pub then
    raise exception 'kernel record names % (expected %)', coalesce(v_rec, '(none)'), v_pub;
  end if;
  if v_row is distinct from v_pub then
    raise exception 'row tos_version stayed % after the acceptance chain (expected %)', coalesce(v_row, '(null)'), v_pub;
  end if;
  if v_hand is distinct from v_pub then
    raise exception 'a later hand UPDATE rewrote tos_version to % (evidence must not be rewritten)', v_hand;
  end if;
  if exists (select 1 from public.customers where id = v_cid) then
    raise exception 'probe customer persisted';
  end if;
  raise notice 'proof: acceptance with a stale label -> row % = kernel record % (hash %...); a later hand write stayed %; probe rolled back',
    v_row, v_rec, v_hash, v_hand;
end $proof$;

commit;

-- a_supplier_is_named_by_his_trade_licence_not_by_typing.sql
--
-- Seat: sales_engineer (supplier registration). Built by it_engineer, 12 Nov 2026. Founder ruling 1672 (12 Nov 2026, after he
-- registered his own company on his iPhone): "even the company name, he doesn't have to fill it. Like once he attaches trade
-- license, the company name is there ... eventually legally we care about the trade license the most"; no "pick your category";
-- a trading name that differs from the licence is optional, in the company profile.
--
-- THE DESIGN: A ROW WITH NO NAME UNTIL THE LICENCE NAMES IT. The website registration (supplier_api create_company) now creates
-- the supplier's row with company_name '' when no name is typed. The empty string was chosen over a placeholder text because the
-- database already reads it as "no name" everywhere it matters (read on production 12 Nov 2026, 0 rows carry it today):
--   * leads_claimed_company_name_uidx is on fn_company_registration_name_key(company_name), which answers NULL for '' (NULL
--     never conflicts), so any number of rows may wait for their licence; a placeholder text would have to be unique per row;
--   * fn_supplier_name_norm('') is NULL, so trg_leads_keep_the_public_name writes no public name;
--   * fn_supplier_registration_reminder_compose greets nullif(btrim(company_name), '') as "Dear Sir or Madam" (السادة الكرام);
--   * fn_supplier_licence_name_mismatch('' against the licence's name) is true, so fn_sales_engineer_verifies_supplier's rename
--     of ruling 1176 names the company from its licence, with the claimed-name collision check it already has.
-- What did NOT read '' right, and is changed here:
--   1. fn_supplier_mandatory_six listed 'reg_name' ("company name") for a blank name, so every reminder, the "Thanks for
--      registering" mail and the gate's reason would have asked him to type a name. A name is now missing only once a licence
--      is on file: before that, the licence is what is missing (the name is read from it).
--   2. fn_sales_engineer_verifies_supplier: (a) a rename FROM a blank name sends no "your company name was updated" mail;
--      (b) the six were read before the rename and its stale 'reg_name' then decided the outcome: they are read again after it;
--      (c) 'reg_name' is never the reason told to the supplier: a blank name with a licence on file is the licence unread,
--      being read, or naming another claimed company, each with its own reason (it still blocks approval);
--      (d) the unclaimed-listing check create_company ran on the TYPED name (H10, possible_duplicate_listing for it_engineer)
--      now runs when the licence names the company, with the same flag in the same queue.
--   3. fn_enqueue_doc_backups filed a blank-named supplier under fn_dbx_safe('') = '_': "Suppliers/<category>/_ (<id>)/", and
--      trg_doc_backups_admit anchors every later file to that first folder. A supplier is not filed until his licence names him;
--      the next run (dropbox_backup calls this on every run) files everything under the name. What the hourly STORAGE SWEEP took
--      meanwhile (his licence, profile and signed agreement under Storage/<bucket>/<path>; doc_backups is unique on bucket and path,
--      so the named inserts would skip them) is re-filed to his named folder the moment he is named: the sweep's own row is pointed
--      at the named path and queued again (a second copy in Dropbox, never a missing one; review of #1987, S3).
--      BUILT ON #1985's a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql (applied 12 Nov 2026: its body equals live
--      pg_get_functiondef), so its 15-minute rule for a licence still being read is kept word for word; the probe asserts it.
--      DIFF THIS ROUTINE AGAINST pg_get_functiondef('public.fn_enqueue_doc_backups()') RIGHT BEFORE APPLYING: any change made live
--      since then must be carried into this file first, or applying it reverts that change.
--   4. leads.trading_name: the optional "Trading name, if different from your licence" (ruling 1672: "MK General Trading ...
--      his shop name is different"). No existing column held it (brands_carried is the brands a supplier sells).
-- Every routine below is its LIVE definition (pg_get_functiondef, read 12 Nov 2026) with only the lines named above changed.
-- CREATE OR REPLACE keeps each ACL (live: postgres and service_role only); the revokes restate it. No new routine, no new table.
-- APPLY ORDER: after #1985's a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql (already live), and BEFORE supplier_api is
-- deployed (the new save_profile writes leads.trading_name). It is safe under the old code: no row has a blank name today, and every
-- changed line only acts on a blank name. Then supplier_api and compliance_archive, then the website (the merge), then
-- the_acceptance_certificate_follows_the_trade_licence.sql.
-- Probe: a_supplier_is_named_by_his_trade_licence_not_by_typing_probe.sql (rolled back).

-- ── 4. the trading name ─────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.leads add column if not exists trading_name text;
alter table public.leads drop constraint if exists leads_trading_name_len;
alter table public.leads add constraint leads_trading_name_len check (trading_name is null or char_length(trading_name) <= 160);
comment on column public.leads.trading_name is
  'The trading, shop or brand name a supplier uses when it differs from the legal name on its trade licence (founder ruling 1672, 12 Nov 2026). Optional, typed by the supplier in the company profile; company_name stays the licensed name.';

-- ── 1. the six: a name is missing only once a licence is on file ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_supplier_mandatory_six(p leads)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select array_remove(array[
    -- ruling 1672: the name is read from the trade licence, so with no licence on file the licence is what is missing
    case when coalesce(btrim(p.company_name), '') = ''
              and exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.license_doc_path)
         then 'reg_name' end,
    case when not (coalesce(p.owner_phone_verified, false)
                   and regexp_replace(coalesce(nullif(btrim(p.phone), ''), p.phone_e164, ''), '[^0-9]', '', 'g') ~ '^9715[0-9]{8}$')
         then 'reg_mobile' end,
    case when not coalesce(p.owner_email_verified, false) then 'reg_email' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.license_doc_path)
         then 'reg_licence' end,
    case when not exists (select 1 from storage.objects o where o.bucket_id = 'supplier-docs' and o.name = p.company_profile_doc_path)
         then 'reg_profile' end,
    case when coalesce(btrim(p.signed_terms_path), '') = '' then 'reg_terms' end
  ], null)
$function$;
revoke execute on function public.fn_supplier_mandatory_six(public.leads) from public, anon, authenticated;

-- ── 2. the gate: named from the licence, never told to type a name ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT 'save_profile'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int; v_doc_reading boolean; v_authority_unread boolean; v_authority_foreign boolean; v_authority_unknown boolean; v_services_open boolean; v_ours_failed boolean; v_listings jsonb;
begin
  select * into l from public.leads where id = p_lead_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'lead_not_found'); end if;
  -- A registration closed for being incomplete (fn_sales_engineer_supplier_documents_tick) is re-opened
  -- by the supplier saving again: the closing notice tells them they may. Any other rejection stands.
  if coalesce(l.banned, false)
     or (coalesce(l.approval_status, '') = 'rejected'
         and not (p_source = 'save_profile' and coalesce(l.rejection_reason, '') like 'registration incomplete after %')) then
    return jsonb_build_object('ok', true, 'decision', 'unchanged', 'approval_status', l.approval_status);
  end if;

  v_missing := public.fn_supplier_mandatory_six(l);
  -- "Not known to be expired": license_extract leaves the expiry null when the licence prints none, and
  -- blocking on that would refuse suppliers whose licence genuinely has no date (29 Jul 2026 note).
  v_expired := l.license_expiry is not null and l.license_expiry < current_date;
  -- 24 Sep 2026: the licence must be this company's. Unread name = not a mismatch (nothing guessed).
  v_name_mismatch := public.fn_supplier_licence_name_mismatch(l);
  -- FOUNDER RULING 1176 (7 Oct 2026): "auto fill the name from the attachment instead of rejection". A licence name
  -- that was READ (code, or the model under its confidence rule - licence_legal_name is only ever written so) and
  -- differs from the registered name becomes the company name: the old name is kept in agent_actions, the supplier
  -- is told in English, and the gate goes on as for a matching name. Not a hold, not a review.
  -- The one exception is a licence naming a company ANOTHER claimed supplier already registered: copying that name
  -- would break leads_claimed_company_name_uidx and hand one company's identity to another, so it stays the
  -- licence_name_mismatch hold of #1275 for a person to look at.
  if v_name_mismatch then
    v_name_taken := exists (select 1 from public.leads o where o.id <> l.id and o.claimed
                              and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(l.licence_legal_name));
    if not v_name_taken then
      v_old_name := l.company_name;
      update public.leads set company_name = btrim(l.licence_legal_name) where id = l.id;
      l.company_name := btrim(l.licence_legal_name);
      v_name_mismatch := false;
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'supplier_name_from_licence', 'auto_done', 'low',
              'Company name updated from the trade licence — ' || left(l.company_name, 120),
              'No action required. The registered name did not match the name the trade licence prints; the licence name now is the company name (founder ruling 1176). The previous name is in detail.previous_name.',
              jsonb_build_object('supplier_id', l.id, 'previous_name', v_old_name, 'new_name', l.company_name,
                                 'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path, 'source', p_source),
              'leads', l.id::text);
      -- A NAME NOBODY TYPED IS NOT "CORRECTED" (12 Nov 2026, sales_engineer; founder ruling 1672): a supplier who registered on the
      -- website since that ruling types no name; his row is created with company_name '' and is named HERE, by the licence. He is
      -- not told "your company name was updated" from a name he never gave.
      if coalesce(btrim(v_old_name), '') <> '' and coalesce(nullif(btrim(l.claimed_by), ''), l.email, '') like '%@%' then
        perform public.fn_sales_engineer_writes('company_name_from_licence', 'supplier', coalesce(nullif(btrim(l.claimed_by), ''), l.email), l.id, null, null, null,
          'Your company name was updated to match your trade licence',
          'Your registered company name was "' || coalesce(v_old_name, '') || '". Your trade licence prints "' || l.company_name
            || '", so your company name on QuotesDone is now "' || l.company_name || '". This is the name customers, quotes and documents show. '
            || 'If this is not right, reply to this email or upload the correct trade licence.',
          null, null, '{}'::text[], 'company_name_from_licence:' || l.id || ':' || md5(l.company_name));
      end if;
      -- THE LISTING CHECK MOVES TO THE MOMENT THE NAME IS KNOWN (12 Nov 2026, sales_engineer; ruling 1672). create_company flagged an
      -- unclaimed directory listing with the typed name for a person to merge (supplier_api/create_company.ts, H10); with no name typed
      -- there was nothing to compare until now. The same flag, in the same it_engineer queue, from the licensed name: the open listings
      -- whose name is this name (fn_company_name_norm: case, punctuation and the legal form folded), a fixture never meeting a real
      -- company. Nothing is merged and nothing waits: the registration stands as its own row.
      if coalesce(btrim(v_old_name), '') = '' then
        select jsonb_agg(jsonb_build_object('id', o.id, 'company_name', o.company_name, 'emirate', o.emirate, 'trade_license_no', o.trade_license_no) order by o.id)
          into v_listings
          from (select o.* from public.leads o
                 where o.id <> l.id and o.claimed_by is null and not coalesce(o.claimed, false)
                   and not coalesce(o.permanently_closed, false) and not coalesce(o.banned, false)
                   and public.fn_company_name_norm(o.company_name) = public.fn_company_name_norm(l.company_name)
                   and public.fn_seat_clock_lead_is_fixture(o) = public.fn_seat_clock_lead_is_fixture(l)
                 order by o.id limit 10) o;
        if v_listings is not null then
          insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
          values ('it_engineer', 'possible_duplicate_listing', 'pending', 'medium',
                  'Possible duplicate of a directory listing — ' || left(l.company_name, 120),
                  'A registration''s trade licence names a company that is also an unclaimed directory listing (' || jsonb_array_length(v_listings)
                    || ' listing' || case when jsonb_array_length(v_listings) = 1 then '' else 's' end || ' with this name). The company was registered as a new row and the listing was not touched. Compare the two rows (detail.new_lead_id and detail.listings): if they are the same company, merge the listing into the registered row by hand and mark this done; if not, mark it dismissed with the reason. Nothing waits on this: the supplier is already registered.',
                  jsonb_build_object('new_lead_id', l.id, 'account', l.claimed_by, 'licence_legal_name', l.company_name, 'trade_license_no', l.trade_license_no,
                                     'emirate', l.emirate, 'why', 'the trade licence names the listing''s company (name read from the licence, not typed)', 'listings', v_listings),
                  'leads', l.id::text);
        end if;
      end if;
    end if;
  end if;
  -- After a rename the six are read again: the name is no longer missing (it was read above, before the rename).
  v_missing := public.fn_supplier_mandatory_six(l);
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '')) = '';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '') = '';
  -- 2 Nov 2026 (ledger 1442, Supplier Agreement v16 clause 13): only a readable UAE authority approves automatically.
  v_authority_unread := l.license_doc_path is not null and coalesce(btrim(l.license_authority), '') = '';
  v_authority_foreign := l.license_doc_path is not null and public.fn_licence_authority_class(l.license_authority) = 'foreign';
  v_authority_unknown := l.license_doc_path is not null and public.fn_licence_authority_class(l.license_authority) = 'unknown';
  -- 10 Nov 2026 (customer_support, item 6 of #1901's report): a field is blank because OUR reader failed on the licence
  -- (leads.licence_read_state, _shared/licence_read_state.ts), not because the file is unreadable. It is held, never approved,
  -- and never put to the supplier as "upload a clearer copy": supplier_api docs_reread reads it again.
  v_ours_failed := l.license_doc_path is not null and coalesce(l.licence_read_state, '') = 'ours_failed'
                   and (v_name_unread or v_expiry_unread or v_number_unread or v_authority_unread);
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  -- 13 Oct 2026 (review of #1404): a profile or catalogue still being read ('reading', marked before its parse) holds
  -- approval: the gate never approves past a document whose read has not finished (or was killed mid-parse).
  v_doc_reading := exists (select 1 from public.supplier_capabilities c, jsonb_array_elements(coalesce(c.source_docs -> 'docs', '[]'::jsonb)) e
                            where c.supplier_id = l.id and e ->> 'status' = 'reading');
  -- 2 Nov 2026 (founder ledger 1469, a_supplier_is_verified_only_after_it_confirms_its_services): the supplier has confirmed what the company does, for the CURRENT version of the record.
  -- Seeders (their own source) are given a capability row by their harness and are not asked.
  v_services_open := p_source not in ('demo_factory', 'hvac_dress_rehearsal', 'document_intake_accuracy')
                     and not exists (select 1 from public.supplier_capabilities c
                                      where c.supplier_id = l.id and c.confirmed_at is not null
                                        and coalesce(c.confirmed_version, 0) >= coalesce((select max(k.version) from public.supplier_capability_confirmation k where k.supplier_id = l.id), 0));
  -- A name still missing is explained by the licence reasons below (unread, being read, or another company's name): the supplier
  -- is never asked to type it (ruling 1672). It still blocks approval: the approved branches need cardinality(v_missing) = 0.
  v_reason := case when cardinality(array_remove(v_missing, 'reg_name')) > 0 then (array_remove(v_missing, 'reg_name'))[1]
                   when v_name_mismatch then 'licence_name_mismatch'
                   when v_expired then 'licence_expired' end;

  if coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread
     and not v_authority_unread and not v_authority_foreign and not v_authority_unknown then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    -- An approved supplier is never asked to confirm services after the fact (ledger 1469): nobody is demoted.
    v_decision := 'approved';
  -- 7 Oct 2026 (review of #1275): an APPROVED supplier whose licence names another company is held for
  -- review, whatever asked - a licence change or a save. The approved branch above used to keep him approved
  -- and log "the licence name matches", which was false. A supplier whose name matches is untouched by a save.
  elsif coalesce(l.approval_status, '') = 'approved' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := 'pending'; v_reason := 'licence_name_mismatch';
  elsif v_reason is not null then v_decision := 'action_required';
  elsif v_ours_failed then v_decision := 'pending'; v_reason := 'licence_being_read';
  elsif v_name_unread then v_decision := 'pending'; v_reason := 'licence_unreadable';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
  elsif v_expiry_unread then v_decision := 'pending'; v_reason := 'licence_expiry_unread';
  elsif v_number_unread then v_decision := 'pending'; v_reason := 'licence_number_unread';
  elsif v_authority_unread then v_decision := 'pending'; v_reason := 'licence_authority_unread';
  elsif v_authority_foreign then v_decision := 'pending'; v_reason := 'licence_authority_not_uae';
  elsif v_authority_unknown then v_decision := 'pending'; v_reason := 'licence_authority_unconfirmed';
  elsif v_doc_reading then v_decision := 'pending'; v_reason := 'documents_being_read';
  elsif v_services_open then v_decision := 'pending'; v_reason := 'services_unconfirmed';
  elsif coalesce(v_auto, false) then v_decision := 'approved';
  else v_decision := 'pending';
  end if;

  update public.leads
     set approval_status = v_decision,
         verified = (v_decision = 'approved'),
         approved_at = case when v_decision = 'approved' then coalesce(approved_at, now()) else approved_at end,
         approval_decided_by = 'sales_engineer',
         licence_gate_reason = v_reason
   where id = p_lead_id
     and (approval_status is distinct from v_decision or verified is distinct from (v_decision = 'approved')
          or licence_gate_reason is distinct from v_reason);
  get diagnostics v_changed = row_count;

  -- Every decision is recorded; a re-run by the trigger that changed nothing is not a decision.
  if v_changed > 0 or p_source not in ('mandatory_item_changed', 'licence_changed') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values ('sales_engineer', 'supplier_verification', case when v_reason in ('licence_unreadable', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed', 'documents_being_read', 'licence_being_read') or (v_decision = 'pending' and v_reason = 'licence_name_mismatch') then 'needs_review' else 'auto_done' end,
          case when v_decision = 'action_required' or v_reason in ('licence_unreadable', 'licence_name_mismatch', 'licence_expiry_unread', 'licence_number_unread', 'licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed') then 'medium' else 'low' end,
          'Supplier ' || v_decision || coalesce(' (' || v_reason || ')', '') || ' — ' || left(coalesce(l.company_name, 'supplier #' || l.id), 120),
          case v_decision
            when 'approved' then 'No action required. All six mandatory items are present, the licence name matches, the licence is not known to be expired and the supplier has confirmed its services.'
            when 'pending' then case when v_reason = 'licence_being_read'
              then 'Held: our document reader failed on the trade licence (the model did not answer, is switched off, or the file could not be fetched to send it); the file itself was never judged unreadable. The supplier is told it is on our side and is not asked for a copy. supplier_api docs_reread reads it again (after 10 minutes, doubling, at most 8 tries); after 3 days fn_sales_engineer_decides_held_registrations puts it to the ceo seat. If you can read it by hand meanwhile, record the fields and approve.'
              when v_reason = 'documents_being_read'
              then 'Held: a company profile or catalogue of this supplier is still being read. The gate is run again when the read finishes; a read still unfinished after 30 minutes is marked unreadable and handed to you (document_read_stuck).'
              when v_reason = 'services_unconfirmed'
              then 'Held: the six mandatory items are complete, but the supplier has not yet confirmed what its company does. The portal shows the summary and keywords prepared from its company profile; the gate is run again the moment it presses confirm (source services_confirmed).'
              when v_reason in ('licence_authority_unread', 'licence_authority_not_uae', 'licence_authority_unconfirmed')
              then 'Held: the issuing authority on the trade licence ' || case v_reason when 'licence_authority_unread' then 'could not be read' when 'licence_authority_unconfirmed' then 'is on no list we hold, which does not make it foreign' else 'names a foreign country or registry' end || '. fn_sales_engineer_decides_held_registrations asks the supplier and closes the registration through the ceo seat after 14 days.'
              when v_reason = 'licence_name_mismatch'
              then 'Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.'
              when v_reason in ('licence_expiry_unread', 'licence_number_unread')
              then 'Review: complete, but the ' || case v_reason when 'licence_expiry_unread' then 'expiry date' else 'licence number' end || ' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.'
              when v_reason = 'licence_unreadable'
              then 'Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.'
              else 'Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.' end
            else 'No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.' end,
          jsonb_build_object('supplier_id', l.id, 'decision', v_decision, 'previous_status', l.approval_status,
                             'missing', v_missing, 'licence_expired', v_expired, 'license_expiry', l.license_expiry,
                             'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                             'licence_expiry_unread', v_expiry_unread, 'licence_number_unread', v_number_unread,
                             'services_unconfirmed', v_services_open, 'licence_read_state', l.licence_read_state,
                             'licence_authority_unread', v_authority_unread, 'licence_authority_foreign', v_authority_foreign, 'license_authority', l.license_authority,
                             'licence_legal_name', l.licence_legal_name, 'license_doc_path', l.license_doc_path,
                             'auto_approve', v_auto, 'source', p_source),
          'leads', l.id::text);
  end if;

  return jsonb_build_object('ok', true, 'decision', v_decision, 'approval_status', v_decision, 'missing', to_jsonb(v_missing),
                            'licence_expired', v_expired, 'licence_name_mismatch', v_name_mismatch, 'licence_name_unread', v_name_unread,
                            'reason', v_reason, 'auto_approve', v_auto);
end $function$;
revoke execute on function public.fn_sales_engineer_verifies_supplier(bigint, text) from public, anon, authenticated;

-- ── 3. the Dropbox tree: a supplier is filed once his licence names him, and what the sweep took meanwhile is re-filed there ──
CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n integer := 0; m integer;
begin
  -- ============ A SUPPLIER NAMED BY HIS LICENCE GETS HIS FILES IN HIS FOLDER (12 Nov 2026, ruling 1672; review of #1987, S3) ============
  -- A supplier who registered with no name is filed only once his licence names him (below). Meanwhile the hourly STORAGE SWEEP
  -- (fn_enqueue_doc_backups_backfill) copies any of his files older than an hour under Storage/<bucket>/<path>, and doc_backups is unique
  -- on (bucket, path), so the inserts below could never file those files under his name. The founder keeps Dropbox as the record. So the
  -- sweep's own row for his licence, profile and signed agreement is re-filed to his named folder once he is named: the same row,
  -- pointed at the named path and queued again ('pending'). The drain uploads it there; the copy under Storage/ stays (a second copy,
  -- never a missing one; no Dropbox move is needed). Only suppliers the gate named from no name (agent_actions supplier_name_from_licence,
  -- previous_name ''), never a demo row outside a tagged sandbox run, never a row being worked on.
  update public.doc_backups d
     set entity = 'supplier', entity_id = x.id::text, doc_type = x.doc_type,
         dropbox_path = public.fn_dbx_path(x.base || x.doc_type || ' - ' || regexp_replace(d.path, '^.*/', '')),
         dedupe_key = 'S:' || x.id || ':' || x.doc_type || ':' || d.path,
         status = 'pending', error = null, attempts = 0, backed_up_at = null, verified_at = null, upload_state = null,
         dropbox_content_hash = null, dropbox_size = null, requeued_at = now()
    from (select l.id, v.doc_type, v.bucket, v.path,
                 '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/' || public.fn_dbx_safe(l.company_name) || ' (' || l.id || ')/' as base
            from public.leads l
            cross join lateral (values ('Trade licence', 'supplier-docs', l.license_doc_path), ('Company profile', 'supplier-docs', l.company_profile_doc_path),
                                       ('Signed Terms & Conditions', 'signed-terms', l.signed_terms_path)) v(doc_type, bucket, path)
           where coalesce(l.claimed, false) and coalesce(btrim(l.company_name), '') <> '' and v.path is not null
             and (not coalesce(l.is_demo, false) or coalesce(current_setting('qd.backup_sandbox', true), '') <> '')
             and exists (select 1 from public.agent_actions a where a.kind = 'supplier_name_from_licence' and a.target_id = l.id::text
                            and coalesce(a.detail ->> 'previous_name', '') = '')) x
   where d.bucket = x.bucket and d.path = x.path and d.dedupe_key like 'SWEEP:%' and d.status in ('done', 'error', 'pending', 'abandoned');
  get diagnostics m = row_count; n := n + m;

  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false))
      and coalesce(btrim(l.company_name), '') <> ''   -- named by its licence first (ruling 1672): never a folder '_ (<id>)'
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      -- a licence file is not filed in the first 15 minutes our reader is on it (see the header); after that it is filed as before
      ('Trade licence','supplier-docs', case when coalesce(s.licence_read_state, '') = 'ours_failed' and s.licence_read_at > now() - interval '15 minutes'
                                            then null else s.license_doc_path end),
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
  from sd on conflict do nothing;
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
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null
      and coalesce(btrim(l.company_name), '') <> '' ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false))
      and coalesce(btrim(l.company_name), '') <> '' ) s
  on conflict do nothing;
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
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict do nothing;
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
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict do nothing;
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
  on conflict do nothing;
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
  -- 21 SEP 2026 (it_engineer): ONLY ARCHIVE ROWS THAT HAVE NO CORRESPONDENCE ROW YET. This block used to
  -- join every conversation_archive row (257) to v_conversation_message on every call and let ON CONFLICT
  -- discard all of them; the view resolves each message's party through fn_conversation_party, 20-45 ms
  -- a row, so the call cost 7,006 ms (EXPLAIN ANALYZE, 21 Sep) and PostgREST cancels at 8 s. The OFFSET 0
  -- fences keep the anti-join FIRST and the view LATERAL, so a call with nothing new costs 1.7 ms and a
  -- new message costs one party lookup. The dedupe key is unchanged, so what is queued is unchanged.
  from (select ca.* from public.conversation_archive ca
         where not exists (select 1 from public.doc_backups d
                            where d.dedupe_key = 'CONV:' || ca.source_table || ':' || ca.source_id)
         offset 0) a
  cross join lateral (select * from public.v_conversation_message v0
                       where v0.source_table = a.source_table and v0.source_id = a.source_id offset 0) v
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
  -- a tagged sandbox run (fn_backup_sandbox_enqueue) lets its own demo messages through; trg_doc_backups_admit
  -- files them under _sandbox/<tag>/ and drops every other demo row exactly as before
  where (not v.is_demo or coalesce(current_setting('qd.backup_sandbox', true), '') <> '')
    -- a supplier not yet named by his licence waits: queued by the sweep after the name lands, under the name (ruling 1672)
    and not (v.party_kind = 'supplier' and exists (select 1 from public.leads b where b.id::text = v.party_id and coalesce(btrim(b.company_name), '') = ''))
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ ACCOUNTING (14 SEP 2026, accountant duty 4 of the five further duties) ============
  -- The founder, 14 Sep 2026: "add all for accountant and IT". The accountant's own documents are filed on
  -- the entity -> type -> date tree under Finance: the month close the CEO signed for (PDF and CSV), the
  -- Mashreq statements, every document the accountant issued in the founder's name, and the year-end pack.
  -- A path stored as '<bucket>/<path>' (bank_statement_intake.doc_path, accountant_issued_document.file_path)
  -- is split at its first slash; any other shape is not queued. Demo rows are filtered exactly as
  -- fn_it_backup_expected filters them (a zz_demo account, an @example.invalid recipient, a ZZ DEMO path):
  -- no demo document reaches Dropbox or the backups bucket.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'close:' || to_char(c.month,'YYYY-MM'), v.doc_type, c.pdf_bucket, v.path,
         regexp_replace(v.path,'^.*/',''),
         '/QuotesDone Backup/Finance/Month Close/' || to_char(c.month,'YYYY') || '/' || to_char(c.month,'YYYY-MM')
           || ' - ' || regexp_replace(v.path,'^.*/',''),
         'storage', 'ACCT:close:' || to_char(c.month,'YYYY-MM') || ':' || v.path
  from public.accountant_month_close c
  cross join lateral (values ('Month close (PDF)', c.pdf_path), ('Month close (CSV)', c.csv_path)) v(doc_type, path)
  where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path,'')) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'bank_statement:' || b.source_ref, 'Bank statement', split_part(b.doc_path,'/',1),
         substr(b.doc_path, strpos(b.doc_path,'/') + 1), regexp_replace(b.doc_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Bank Statements/' || initcap(b.account) || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY') || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY-MM')
           || ' - ' || regexp_replace(b.doc_path,'^.*/',''),
         'storage', 'ACCT:bank:' || b.source_ref
  from public.bank_statement_intake b
  where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'issued:' || d.id, 'Issued document', split_part(d.file_path,'/',1),
         substr(d.file_path, strpos(d.file_path,'/') + 1), regexp_replace(d.file_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Issued Documents/' || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' ' || d.document_kind || ' #' || d.id
           || ' - ' || regexp_replace(d.file_path,'^.*/',''),
         'storage', 'ACCT:issued:' || d.id
  from public.accountant_issued_document d
  where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'year_end:' || p.year, 'Year-end pack', f->>'bucket', f->>'path', f->>'name',
         '/QuotesDone Backup/Finance/Year End/' || p.year || '/' || (f->>'name'),
         'storage', 'ACCT:year_end:' || p.year || ':' || (f->>'name')
  from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
  where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMER DOCUMENTS (7 OCT 2026, sales_engineer) ============
  -- Founder gate, ledger 1162: "no issue in the Dropbox backup of supplier/customer documents and the
  -- folder workflow and organisation". Measured 7 Oct 2026: 386 files that belong to a customer, an
  -- inquiry, a quote or a supplier were filed by the STORAGE SWEEP under Storage/<bucket>/<path>, outside
  -- the entity -> type -> date tree (quote-files 274, agent-docs 92, drawing-files 33 ...). The documents
  -- of a request are filed under that request, in the customer's folder:
  --   Quotes/   the supplier's quotation as uploaded, and the quotation PDF the customer downloaded
  --   Payment/  every reveal invoice and receipt (agent-docs/reveal_invoice/<sale id8>/)
  --   Reports/  the comparison report and the request brief (agent-docs/compare|brief/<inquiry id>/,
  --             the folders customer_api writes since this change)
  -- A file already queued by any rule (the sweep included) is skipped on (bucket, path), so nothing is
  -- filed twice and nothing already in Dropbox is moved. The folder of the request is the one its
  -- Inquiry Summary was filed in (trg_doc_backups_admit), so a status change never splits it.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, x.doc_type, x.bucket, x.path, regexp_replace(x.path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/' || x.folder || '/' || public.fn_dbx_safe(x.fname),
         'storage', x.dkey
  from (
    select q.inquiry_id, 'Supplier quotation' as doc_type, 'quote-files' as bucket, q.original_file_path as path, 'Quotes' as folder,
           to_char(q.created_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' Quote ' || left(q.id::text,8) || ' - '
             || coalesce(nullif(btrim(q.original_file_name),''), regexp_replace(q.original_file_path,'^.*/','')) as fname,
           'Q:' || q.id || ':original:' || q.original_file_path as dkey
      from public.quotes q
     where length(coalesce(q.original_file_path,'')) > 0
    union all
    select q.inquiry_id, 'Quotation PDF', p.bucket, p.path, 'Quotes',
           'Quote ' || left(q.id::text,8) || ' (' || upper(coalesce(p.lang,'')) || ') - ' || regexp_replace(p.path,'^.*/',''),
           'QPDF:' || p.bucket || ':' || p.path
      from public.quote_pdf_cache p join public.quotes q on q.id = p.quote_id
     where length(coalesce(p.path,'')) > 0 and p.bucket is not null
    union all
    select t.inquiry_id, 'Reveal invoice or receipt', o.bucket_id, o.name, 'Payment', regexp_replace(o.name,'^.*/',''),
           'RCPT:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.transactions t on left(t.id::text,8) = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and o.name like 'reveal\_invoice/%' and t.inquiry_id is not null
    union all
    select i2.id, case split_part(o.name,'/',1) when 'compare' then 'Comparison report' else 'Request brief' end,
           o.bucket_id, o.name, 'Reports', regexp_replace(o.name,'^.*/',''), 'IDOC:' || o.bucket_id || ':' || o.name
      from storage.objects o join public.inquiries i2 on i2.id::text = split_part(o.name,'/',2)
     where o.bucket_id = 'agent-docs' and (o.name like 'compare/%' or o.name like 'brief/%')
  ) x
  join public.inquiries i on i.id = x.inquiry_id
  join public.customers c on c.id = i.customer_id
  where not exists (select 1 from public.doc_backups d where d.bucket = x.bucket and d.path = x.path)
  on conflict do nothing;
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
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$;
revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

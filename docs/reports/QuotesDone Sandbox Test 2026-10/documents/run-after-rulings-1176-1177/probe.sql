do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  execute '-- Assigned: sales_engineer
-- A LICENCE NAME BECOMES THE COMPANY NAME, AND A FIELD NOBODY COULD READ IS HELD (7 Oct 2026, #1285).
-- BUILT ON #1275 (an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql), which applies first:
-- its log guard (a re-run that changed nothing is not logged for ''mandatory_item_changed'' and ''licence_changed''),
-- its re-gate of an approved supplier who swaps licences, and its z20 trigger stand unchanged.
--
-- FOUNDER RULING 1176: "auto fill the name from the attachment instead of rejection". A licence name that was READ
-- (by code, or by the model under licenceNameFromModel''s confidence rule - leads.licence_legal_name is only ever
-- written so) and differs from the registered name becomes leads.company_name. The previous name is kept in an
-- agent_actions row (kind supplier_name_from_licence, detail.previous_name), the supplier is told in English through
-- fn_sales_engineer_writes, and the gate continues as for a matching name: no hold, no review. This applies to an
-- approved supplier who swaps licences too: he gets the new name. ONE exception: a licence printing the name another
-- CLAIMED supplier registered stays #1275''s licence_name_mismatch hold (pending, needs_review) - copying it would
-- break leads_claimed_company_name_uidx and give one company another''s identity.
-- Every surface reads the company name from leads.company_name (measured 7 Oct 2026: no other table stores a copy of
-- it in the schema mirror), so the portal, quotes, PDFs and search show the new name from the next read.
--
-- FOUNDER RULING 1177 + LEDGER 1162: every licence is read in full (code, then the vision model); a field still
-- unread after both is HELD, never guessed: name -> licence_unreadable (as before), expiry -> licence_expiry_unread,
-- number -> licence_number_unread; pending, needs_review, medium, and the supplier is asked for a clearer copy
-- (serverCopy.ts); a new upload is read again and re-runs this gate. The approved branch asks all three, so an
-- approved supplier''s new licence that could not be dated or numbered is held too. Measured on production 7 Oct 2026:
-- 3 approved suppliers, 0 with a mismatch and 0 with an unread expiry or number - no current approval changes.
-- Measured on 50 synthetic licences by scripts/e2e/document_intake_accuracy.mjs (--gate-sql, inside a rolled-back
-- transaction): before, the gate approved on the name alone.
-- NOT changed: the six, the rule for an expiry that WAS read. CREATE OR REPLACE keeps the existing ACL (revoked in
-- the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql).
-- Prevented by: scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs and the suite''s gate probe.

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT ''save_profile''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''public'', ''pg_temp''
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_name_taken boolean := false; v_old_name text; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
begin
  select * into l from public.leads where id = p_lead_id for update;
  if not found then return jsonb_build_object(''ok'', false, ''error'', ''lead_not_found''); end if;
  -- A registration closed for being incomplete (fn_sales_engineer_supplier_documents_tick) is re-opened
  -- by the supplier saving again: the closing notice tells them they may. Any other rejection stands.
  if coalesce(l.banned, false)
     or (coalesce(l.approval_status, '''') = ''rejected''
         and not (p_source = ''save_profile'' and coalesce(l.rejection_reason, '''') like ''registration incomplete after %'')) then
    return jsonb_build_object(''ok'', true, ''decision'', ''unchanged'', ''approval_status'', l.approval_status);
  end if;

  v_missing := public.fn_supplier_mandatory_six(l);
  -- "Not known to be expired": license_extract leaves the expiry null when the licence prints none, and
  -- blocking on that would refuse suppliers whose licence genuinely has no date (29 Jul 2026 note).
  v_expired := l.license_expiry is not null and l.license_expiry < current_date;
  -- 24 Sep 2026: the licence must be this company''s. Unread name = not a mismatch (nothing guessed).
  v_name_mismatch := public.fn_supplier_licence_name_mismatch(l);
  -- FOUNDER RULING 1176 (7 Oct 2026): "auto fill the name from the attachment instead of rejection". A licence name
  -- that was READ (code, or the model under its confidence rule - licence_legal_name is only ever written so) and
  -- differs from the registered name becomes the company name: the old name is kept in agent_actions, the supplier
  -- is told in English, and the gate goes on as for a matching name. Not a hold, not a review.
  -- The one exception is a licence naming a company ANOTHER claimed supplier already registered: copying that name
  -- would break leads_claimed_company_name_uidx and hand one company''s identity to another, so it stays the
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
      values (''sales_engineer'', ''supplier_name_from_licence'', ''auto_done'', ''low'',
              ''Company name updated from the trade licence — '' || left(l.company_name, 120),
              ''No action required. The registered name did not match the name the trade licence prints; the licence name now is the company name (founder ruling 1176). The previous name is in detail.previous_name.'',
              jsonb_build_object(''supplier_id'', l.id, ''previous_name'', v_old_name, ''new_name'', l.company_name,
                                 ''licence_legal_name'', l.licence_legal_name, ''license_doc_path'', l.license_doc_path, ''source'', p_source),
              ''leads'', l.id::text);
      if coalesce(nullif(btrim(l.claimed_by), ''''), l.email, '''') like ''%@%'' then
        perform public.fn_sales_engineer_writes(''company_name_from_licence'', ''supplier'', coalesce(nullif(btrim(l.claimed_by), ''''), l.email), l.id, null, null, null,
          ''Your company name was updated to match your trade licence'',
          ''Your registered company name was "'' || coalesce(v_old_name, '''') || ''". Your trade licence prints "'' || l.company_name
            || ''", so your company name on QuotesDone is now "'' || l.company_name || ''". This is the name customers, quotes and documents show. ''
            || ''If this is not right, reply to this email or upload the correct trade licence.'',
          null, null, ''{}''::text[], ''company_name_from_licence:'' || l.id || '':'' || md5(l.company_name));
      end if;
    end if;
  end if;
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '''')) = '''';
  -- 7 Oct 2026 (#1285): a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '''') = '''';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then ''licence_name_mismatch''
                   when v_expired then ''licence_expired'' end;

  if coalesce(l.approval_status, '''') = ''approved'' and cardinality(v_missing) = 0 and not v_name_unread
     and not v_name_mismatch and not v_expiry_unread and not v_number_unread then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := ''approved'';
  -- 7 Oct 2026 (review of #1275): an APPROVED supplier whose licence names another company is held for
  -- review, whatever asked - a licence change or a save. The approved branch above used to keep him approved
  -- and log "the licence name matches", which was false. A supplier whose name matches is untouched by a save.
  elsif coalesce(l.approval_status, '''') = ''approved'' and cardinality(v_missing) = 0
        and v_name_mismatch then v_decision := ''pending''; v_reason := ''licence_name_mismatch'';
  elsif v_reason is not null then v_decision := ''action_required'';
  elsif v_name_unread then v_decision := ''pending''; v_reason := ''licence_unreadable'';
  -- 7 Oct 2026 (#1285): an unread expiry or licence number is held, never approved on the name alone - also for
  -- an APPROVED supplier whose new licence (licence_changed) could not be dated or numbered.
  elsif v_expiry_unread then v_decision := ''pending''; v_reason := ''licence_expiry_unread'';
  elsif v_number_unread then v_decision := ''pending''; v_reason := ''licence_number_unread'';
  elsif coalesce(v_auto, false) then v_decision := ''approved'';
  else v_decision := ''pending'';
  end if;

  update public.leads
     set approval_status = v_decision,
         verified = (v_decision = ''approved''),
         approved_at = case when v_decision = ''approved'' then coalesce(approved_at, now()) else approved_at end,
         approval_decided_by = ''sales_engineer'',
         licence_gate_reason = v_reason
   where id = p_lead_id
     and (approval_status is distinct from v_decision or verified is distinct from (v_decision = ''approved'')
          or licence_gate_reason is distinct from v_reason);
  get diagnostics v_changed = row_count;

  -- Every decision is recorded; a re-run by the trigger that changed nothing is not a decision.
  if v_changed > 0 or p_source not in (''mandatory_item_changed'', ''licence_changed'') then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values (''sales_engineer'', ''supplier_verification'', case when v_reason in (''licence_unreadable'', ''licence_expiry_unread'', ''licence_number_unread'') or (v_decision = ''pending'' and v_reason = ''licence_name_mismatch'') then ''needs_review'' else ''auto_done'' end,
          case when v_decision = ''action_required'' or v_reason in (''licence_unreadable'', ''licence_name_mismatch'', ''licence_expiry_unread'', ''licence_number_unread'') then ''medium'' else ''low'' end,
          ''Supplier '' || v_decision || coalesce('' ('' || v_reason || '')'', '''') || '' — '' || left(coalesce(l.company_name, ''supplier #'' || l.id), 120),
          case v_decision
            when ''approved'' then ''No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.''
            when ''pending'' then case when v_reason = ''licence_name_mismatch''
              then ''Review: an approved supplier uploaded a new trade licence whose company name does not match the registered name. Matching is held. Compare the licence with the registered name, then re-approve or ask for the right licence.''
              when v_reason in (''licence_expiry_unread'', ''licence_number_unread'')
              then ''Review: complete, but the '' || case v_reason when ''licence_expiry_unread'' then ''expiry date'' else ''licence number'' end || '' on the trade licence could not be read. Read it on the licence, record it, then approve or ask for a clearer copy. It is never approved automatically on the name alone.''
              when v_reason = ''licence_unreadable''
              then ''Review: complete, but the company name on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.''
              else ''Complete, and waiting for the sales engineer: pricing_config.auto_approve_suppliers is off.'' end
            else ''No action required. The supplier was told exactly what is missing; the verification re-runs when it arrives, and the registration closes after 14 days.'' end,
          jsonb_build_object(''supplier_id'', l.id, ''decision'', v_decision, ''previous_status'', l.approval_status,
                             ''missing'', v_missing, ''licence_expired'', v_expired, ''license_expiry'', l.license_expiry,
                             ''licence_name_mismatch'', v_name_mismatch, ''licence_name_unread'', v_name_unread,
                             ''licence_expiry_unread'', v_expiry_unread, ''licence_number_unread'', v_number_unread,
                             ''licence_legal_name'', l.licence_legal_name, ''license_doc_path'', l.license_doc_path,
                             ''auto_approve'', v_auto, ''source'', p_source),
          ''leads'', l.id::text);
  end if;

  return jsonb_build_object(''ok'', true, ''decision'', v_decision, ''approval_status'', v_decision, ''missing'', to_jsonb(v_missing),
                            ''licence_expired'', v_expired, ''licence_name_mismatch'', v_name_mismatch, ''licence_name_unread'', v_name_unread,
                            ''reason'', v_reason, ''auto_approve'', v_auto);
end $function$;
';
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-accxl0x7y-acc0@example.invalid', '+971500000086', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_text', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-28'::date, 'ZZACC-accxl0x7y-507919',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_ded_old_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-accxl0x7y-acc1@example.invalid', '+971500000087', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_scan_pdf', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_ded_old_scan_pdf', 'ZZ DEMO Pearl Electrical LLC', '2028-02-01'::date, 'ZZACC-accxl0x7y-515838',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_ded_old_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-accxl0x7y-acc2@example.invalid', '+971500000088', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dubai_det_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_text', 'ZZ DEMO Dune Plumbing LLC', '2028-03-02'::date, 'ZZACC-accxl0x7y-1023757',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['plumbing','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['plumbing','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_det_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air LLC', 'qd-accxl0x7y-acc3@example.invalid', '+971500000089', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dubai_det_png.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_png', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_png', 'ZZ DEMO Oasis Air LLC', '2027-04-03'::date, 'ZZACC-accxl0x7y-1031676',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_det_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-accxl0x7y-acc4@example.invalid', '+971500000000', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_text', 'ZZ DEMO Horizon Floor LLC', '2027-05-04'::date, 'ZZACC-accxl0x7y-CN-1523645',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry LLC', 'qd-accxl0x7y-acc5@example.invalid', '+971500000001', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_jpg.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_jpg', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_jpg', 'ZZ DEMO Saker Carpentry LLC', '2029-06-05'::date, 'ZZACC-accxl0x7y-CN-1628374',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_adgm_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_adgm_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting Ltd', 'qd-accxl0x7y-acc6@example.invalid', '+971500000002', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_adgm_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_adgm_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_adgm_text', 'ZZ DEMO Marina Painting Ltd', '2027-07-06'::date, 'ZZACC-accxl0x7y-000010259',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_adgm_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_adgm_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_adgm_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building Ltd', 'qd-accxl0x7y-acc7@example.invalid', '+971500000003', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_adgm_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_adgm_rotated90', 'profiles/zzdemo-accuracy-accxl0x7y/lic_adgm_rotated90', 'ZZ DEMO Crescent Building Ltd', '2028-08-07'::date, 'ZZACC-accxl0x7y-000010296',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_adgm_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-accxl0x7y-acc8@example.invalid', '+971500000004', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_text', 'ZZ DEMO Ghaf Landscaping LLC', '2028-09-08'::date, 'ZZACC-accxl0x7y-705517',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Glass LLC', 'qd-accxl0x7y-acc9@example.invalid', '+971500000005', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_skewed.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_skewed', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_skewed', 'ZZ DEMO Palm Glass LLC', '2027-01-09'::date, 'ZZACC-accxl0x7y-706130',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_skewed', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Lifts Est', 'qd-accxl0x7y-acc10@example.invalid', '+971500000006', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_text', 'ZZ DEMO Sidra Lifts Est', '2027-02-10'::date, 'ZZACC-accxl0x7y-12981',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ajman_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Fire Est', 'qd-accxl0x7y-acc11@example.invalid', '+971500000007', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_lowdpi.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_lowdpi', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_lowdpi', 'ZZ DEMO Nakheel Fire Est', '2029-03-11'::date, 'ZZACC-accxl0x7y-13252',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','flooring']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','flooring']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ajman_ded_lowdpi', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_rak_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rak_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Aluminium LLC', 'qd-accxl0x7y-acc12@example.invalid', '+971500000008', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_rak_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_rak_ded_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rak_ded_text', 'ZZ DEMO Corniche Aluminium LLC', '2027-04-12'::date, 'ZZACC-accxl0x7y-24303',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_rak_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_rak_ded_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rak_ded_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Electrical LLC', 'qd-accxl0x7y-acc13@example.invalid', '+971500000009', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_rak_ded_phone.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_rak_ded_phone', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rak_ded_phone', 'ZZ DEMO Lulu Electrical LLC', '2028-05-13'::date, 'ZZACC-accxl0x7y-24634',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_rak_ded_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_rakez_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rakez_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Plumbing FZ LLC', 'qd-accxl0x7y-acc14@example.invalid', '+971500000010', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_rakez_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_rakez_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rakez_text', 'ZZ DEMO Wadi Plumbing FZ LLC', '2028-06-14'::date, 'ZZACC-accxl0x7y-5115755',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['plumbing','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['plumbing','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_rakez_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_rakez_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rakez_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Air FZ LLC', 'qd-accxl0x7y-acc15@example.invalid', '+971500000011', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_rakez_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_rakez_scan_pdf', 'profiles/zzdemo-accuracy-accxl0x7y/lic_rakez_scan_pdf', 'ZZ DEMO Qamar Air FZ LLC', '2027-07-15'::date, 'ZZACC-accxl0x7y-5123472',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_rakez_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Floor LLC', 'qd-accxl0x7y-acc16@example.invalid', '+971500000012', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_text', 'ZZ DEMO Najm Floor LLC', '2027-08-16'::date, 'ZZACC-accxl0x7y-4649',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_uaq_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Carpentry LLC', 'qd-accxl0x7y-acc17@example.invalid', '+971500000013', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_png.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_png', 'profiles/zzdemo-accuracy-accxl0x7y/lic_uaq_ded_png', 'ZZ DEMO Reem Carpentry LLC', '2029-09-17'::date, 'ZZACC-accxl0x7y-4746',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_uaq_ded_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Painting LLC', 'qd-accxl0x7y-acc18@example.invalid', '+971500000014', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_text', 'ZZ DEMO Falcon Painting LLC', '2027-01-18'::date, 'ZZACC-accxl0x7y-42147',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Building LLC', 'qd-accxl0x7y-acc19@example.invalid', '+971500000015', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_jpg.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_jpg', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_jpg', 'ZZ DEMO Pearl Building LLC', '2028-02-19'::date, 'ZZACC-accxl0x7y-42260',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Landscaping FZE', 'qd-accxl0x7y-acc20@example.invalid', '+971500000016', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_jafza_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_text', 'ZZ DEMO Dune Landscaping FZE', '2028-03-20'::date, 'ZZACC-accxl0x7y-189691',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_jafza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Glass FZE', 'qd-accxl0x7y-acc21@example.invalid', '+971500000017', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_jafza_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_rotated90', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_rotated90', 'ZZ DEMO Oasis Glass FZE', '2027-04-21'::date, 'ZZACC-accxl0x7y-193962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_jafza_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Lifts DMCC', 'qd-accxl0x7y-acc22@example.invalid', '+971500000018', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dmcc_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_text', 'ZZ DEMO Horizon Lifts DMCC', '2027-05-22'::date, 'ZZACC-accxl0x7y-DMCC-238161',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dmcc_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Fire DMCC', 'qd-accxl0x7y-acc23@example.invalid', '+971500000019', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dmcc_skewed.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_skewed', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_skewed', 'ZZ DEMO Saker Fire DMCC', '2029-06-23'::date, 'ZZACC-accxl0x7y-DMCC-244168',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','flooring']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','flooring']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dmcc_skewed', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Aluminium FZ LLC', 'qd-accxl0x7y-acc24@example.invalid', '+971500000020', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dafza_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dafza_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dafza_text', 'ZZ DEMO Marina Aluminium FZ LLC', '2027-07-24'::date, 'ZZACC-accxl0x7y-1925',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dafza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dafza_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dafza_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Electrical FZ LLC', 'qd-accxl0x7y-acc25@example.invalid', '+971500000021', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dafza_lowdpi.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dafza_lowdpi', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dafza_lowdpi', 'ZZ DEMO Crescent Electrical FZ LLC', '2028-08-25'::date, 'ZZACC-accxl0x7y-1962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dafza_lowdpi', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dso_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dso_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Plumbing FZ LLC', 'qd-accxl0x7y-acc26@example.invalid', '+971500000022', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dso_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dso_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dso_text', 'ZZ DEMO Ghaf Plumbing FZ LLC', '2028-09-26'::date, 'ZZACC-accxl0x7y-21043',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['plumbing','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['plumbing','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dso_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dso_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dso_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Air FZ LLC', 'qd-accxl0x7y-acc27@example.invalid', '+971500000023', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dso_phone.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dso_phone', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dso_phone', 'ZZ DEMO Palm Air FZ LLC', '2027-01-28'::date, 'ZZACC-accxl0x7y-21452',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dso_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_ifza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ifza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Floor FZ LLC', 'qd-accxl0x7y-acc28@example.invalid', '+971500000024', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_ifza_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_ifza_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ifza_text', 'ZZ DEMO Sidra Floor FZ LLC', '2027-02-01'::date, 'ZZACC-accxl0x7y-24587',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ifza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_ifza_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ifza_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Carpentry FZ LLC', 'qd-accxl0x7y-acc29@example.invalid', '+971500000025', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_ifza_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_ifza_scan_pdf', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ifza_scan_pdf', 'ZZ DEMO Nakheel Carpentry FZ LLC', '2029-03-02'::date, 'ZZACC-accxl0x7y-25090',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ifza_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_meydan_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_meydan_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Painting FZ LLC', 'qd-accxl0x7y-acc30@example.invalid', '+971500000026', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_meydan_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_meydan_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_meydan_text', 'ZZ DEMO Corniche Painting FZ LLC', '2027-04-03'::date, 'ZZACC-accxl0x7y-MFZ-7541',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_meydan_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_meydan_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_meydan_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Building FZ LLC', 'qd-accxl0x7y-acc31@example.invalid', '+971500000027', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_meydan_png.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_meydan_png', 'profiles/zzdemo-accuracy-accxl0x7y/lic_meydan_png', 'ZZ DEMO Lulu Building FZ LLC', '2028-05-04'::date, 'ZZACC-accxl0x7y-MFZ-7752',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_meydan_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_shams_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_shams_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Landscaping FZE', 'qd-accxl0x7y-acc32@example.invalid', '+971500000028', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_shams_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_shams_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_shams_text', 'ZZ DEMO Wadi Landscaping FZE', '2028-06-05'::date, 'ZZACC-accxl0x7y-2033429',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_shams_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_shams_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_shams_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Glass FZE', 'qd-accxl0x7y-acc33@example.invalid', '+971500000029', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_shams_jpg.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_shams_jpg', 'profiles/zzdemo-accuracy-accxl0x7y/lic_shams_jpg', 'ZZ DEMO Qamar Glass FZE', '2027-07-06'::date, 'ZZACC-accxl0x7y-2034442',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_shams_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_difc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_difc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Lifts Ltd', 'qd-accxl0x7y-acc34@example.invalid', '+971500000030', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_difc_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_difc_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_difc_text', 'ZZ DEMO Najm Lifts Ltd', '2027-08-07'::date, 'ZZACC-accxl0x7y-CL2015',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_difc_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_difc_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_difc_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Fire Ltd', 'qd-accxl0x7y-acc35@example.invalid', '+971500000031', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_difc_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_difc_rotated90', 'profiles/zzdemo-accuracy-accxl0x7y/lic_difc_rotated90', 'ZZ DEMO Reem Fire Ltd', '2029-09-08'::date, 'ZZACC-accxl0x7y-CL2044',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','flooring']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','flooring']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_difc_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_bi_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_bi_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-accxl0x7y-acc36@example.invalid', '+971500000032', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dubai_det_bi_jpg.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dubai_det_bi_jpg', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dubai_det_bi_jpg', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-09'::date, 'ZZACC-accxl0x7y-1293003',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_det_bi_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_bi_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_bi_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-accxl0x7y-acc37@example.invalid', '+971500000033', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_bi_phone.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_bi_phone', 'profiles/zzdemo-accuracy-accxl0x7y/lic_sharjah_sedd_bi_phone', 'ZZ DEMO Pearl Electrical LLC', '2028-02-10'::date, 'ZZACC-accxl0x7y-723294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_bi_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_bi_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_bi_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-accxl0x7y-acc38@example.invalid', '+971500000034', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_bi_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_bi_scan_pdf', 'profiles/zzdemo-accuracy-accxl0x7y/lic_abu_dhabi_added_bi_scan_pdf', 'ZZ DEMO Dune Plumbing LLC', '2028-03-11'::date, 'ZZACC-accxl0x7y-CN-5084431',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['plumbing','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['plumbing','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_bi_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_ar_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_ar_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air Est', 'qd-accxl0x7y-acc39@example.invalid', '+971500000035', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_ar_png.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_ar_png', 'profiles/zzdemo-accuracy-accxl0x7y/lic_ajman_ded_ar_png', null, '2027-04-12'::date, 'ZZACC-accxl0x7y-20840',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_ajman_ded_ar_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_ar_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_ar_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-accxl0x7y-acc40@example.invalid', '+971500000036', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_ar_jpg.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_ar_jpg', 'profiles/zzdemo-accuracy-accxl0x7y/lic_fujairah_ded_ar_jpg', null, '2027-05-13'::date, 'ZZACC-accxl0x7y-44633',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_ar_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry DMCC', 'qd-accxl0x7y-acc41@example.invalid', '+971500000037', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_dmcc_multipage.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_dmcc_multipage', 'profiles/zzdemo-accuracy-accxl0x7y/lic_dmcc_multipage', 'ZZ DEMO Saker Carpentry DMCC', '2029-06-14'::date, 'ZZACC-accxl0x7y-DMCC-352294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dmcc_multipage', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting FZE', 'qd-accxl0x7y-acc42@example.invalid', '+971500000038', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_jafza_multipage.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_jafza_multipage', 'profiles/zzdemo-accuracy-accxl0x7y/lic_jafza_multipage', 'ZZ DEMO Marina Painting FZE', '2027-07-15'::date, 'ZZACC-accxl0x7y-183654',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['fire_fighting','painting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['fire_fighting','painting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_jafza_multipage', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_expired_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_expired_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building LLC', 'qd-accxl0x7y-acc43@example.invalid', '+971500000039', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_expired_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_expired_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_expired_text', 'ZZ DEMO Crescent Building LLC', '2025-06-30'::date, 'ZZACC-accxl0x7y-1348436',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_expired_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_expired_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_expired_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-accxl0x7y-acc44@example.invalid', '+971500000040', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_expired_scan.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_expired_scan', 'profiles/zzdemo-accuracy-accxl0x7y/lic_expired_scan', 'ZZ DEMO Ghaf Landscaping LLC', '2026-02-10'::date, 'ZZACC-accxl0x7y-727585',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_expired_scan', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sahara Technical Services LLC', 'qd-accxl0x7y-acc45@example.invalid', '+971500000041', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_mismatch_text.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_text', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_text', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-accxl0x7y-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_mismatch_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_text_approved_swap');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_text_approved_swap');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('approved', true, 'ZZ DEMO Oasis Swap Trading LLC', 'qd-accxl0x7y-acc46@example.invalid', '+971500000042', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_mismatch_text_approved_swap.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_text_approved_swap', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_text_approved_swap', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-accxl0x7y-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_mismatch_text_approved_swap', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Zenith Maintenance FZ LLC', 'qd-accxl0x7y-acc47@example.invalid', '+971500000043', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_mismatch_scan.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_mismatch_scan', 'profiles/zzdemo-accuracy-accxl0x7y/lic_mismatch_scan', 'ZZ DEMO Atlas Building Works FZ LLC', '2027-02-19'::date, 'ZZACC-accxl0x7y-5362699',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators','hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators','hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_mismatch_scan', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_blank_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_blank_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Page LLC', 'qd-accxl0x7y-acc48@example.invalid', '+971500000044', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_blank_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_blank_pdf', 'profiles/zzdemo-accuracy-accxl0x7y/lic_blank_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/lic_blank_photo');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_blank_photo');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Photo LLC', 'qd-accxl0x7y-acc49@example.invalid', '+971500000045', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_blank_photo.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/lic_blank_photo', 'profiles/zzdemo-accuracy-accxl0x7y/lic_blank_photo', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_photo', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/lic_missing');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO No Licence LLC', 'qd-accxl0x7y-acc50@example.invalid', '+971500000046', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/lic_missing.pdf',
          null, 'profiles/zzdemo-accuracy-accxl0x7y/lic_missing', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_missing', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Projects LLC', 'qd-accxl0x7y-acc51@example.invalid', '+971500000047', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_pdf-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pdf', 'ZZ DEMO Oasis Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-51',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_docx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_docx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Projects LLC', 'qd-accxl0x7y-acc52@example.invalid', '+971500000048', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_docx.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_docx-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_docx', 'ZZ DEMO Horizon Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-52',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical','fire_fighting']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical','fire_fighting']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_docx', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_pptx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pptx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Projects LLC', 'qd-accxl0x7y-acc53@example.invalid', '+971500000049', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_pptx.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_pptx-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pptx', 'ZZ DEMO Saker Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-53',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pptx', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_png-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Projects LLC', 'qd-accxl0x7y-acc54@example.invalid', '+971500000050', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_png.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_png-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_png', 'ZZ DEMO Marina Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-54',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_pdf_paint-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pdf_paint');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Projects LLC', 'qd-accxl0x7y-acc55@example.invalid', '+971500000051', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_pdf_paint.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_pdf_paint-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_pdf_paint', 'ZZ DEMO Crescent Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-55',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['painting','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['painting','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pdf_paint', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/profile_docx_land-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/profile_docx_land');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Projects LLC', 'qd-accxl0x7y-acc56@example.invalid', '+971500000052', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/profile_docx_land.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/profile_docx_land-licence', 'profiles/zzdemo-accuracy-accxl0x7y/profile_docx_land', 'ZZ DEMO Ghaf Projects LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-56',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_docx_land', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxl0x7y/catalogue_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxl0x7y/catalogue_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Building Supplies LLC', 'qd-accxl0x7y-acc57@example.invalid', '+971500000053', true, true, now(), 'terms/zzdemo-accuracy-accxl0x7y/catalogue_pdf.pdf',
          'licenses/zzdemo-accuracy-accxl0x7y/catalogue_pdf-licence', 'profiles/zzdemo-accuracy-accxl0x7y/catalogue_pdf', 'ZZ DEMO Reem Building Supplies LLC', '2028-12-31'::date, 'ZZACC-accxl0x7y-ZZACC-57',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxl0x7y']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'catalogue_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  mt := mt || jsonb_build_object('aluminium', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['aluminium'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('corporate_training', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['corporate_training'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('electrical', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['electrical'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('elevators', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['elevators'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('fire_fighting', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['fire_fighting'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('flooring', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['flooring'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('glazing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['glazing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('hvac', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['hvac'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('joinery', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['joinery'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('landscaping', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['landscaping'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('legal_services', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['legal_services'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('painting', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['painting'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('plumbing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['plumbing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('tax_advisory', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['tax_advisory'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('waterproofing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['waterproofing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  raise exception 'CHK<<%>>', jsonb_build_object('gate', res, 'match', mt)::text;
end $probe$;
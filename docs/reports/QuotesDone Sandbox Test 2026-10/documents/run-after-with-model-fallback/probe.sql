do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  execute '-- Assigned: sales_engineer
-- A LICENCE WHOSE EXPIRY OR NUMBER COULD NOT BE READ IS HELD, AND A WRONG NAME UN-APPROVES (7 Oct 2026).
-- Founder gate, ledger 1162: "not a single mistake in any trade licence shared by a supplier". Measured by the
-- document intake accuracy suite (scripts/e2e/document_intake_accuracy.mjs) on 50 synthetic licences, with
-- pricing_config.auto_approve_suppliers = true:
--   * the gate approved on the NAME alone. A licence whose name was read but whose expiry was not (a scan the model
--     named but could not date) was approved with license_expiry null - "not known to be expired" - so an expired
--     licence whose date could not be read would be approved. "Any unreadable field HELD, never guessed": a licence
--     on file with no expiry read is now held at ''pending'' with reason licence_expiry_unread, and with no licence
--     number read, licence_number_unread; the verification row needs review, as licence_unreadable does.
--   * an APPROVED supplier who replaced the licence with one printing ANOTHER company''s name stayed approved: the
--     approved branch came before the mismatch reason. A mismatch now takes the approval away (action_required,
--     licence_name_mismatch). Measured on production 7 Oct 2026: 3 approved suppliers, 0 with a mismatch, 0 with an
--     unread expiry or number, so no current approval changes. An expired licence on an approved supplier still
--     stays approved (fn_reconcile_doc_blocks pauses its matching), as before.
-- NOT changed: the six, the rule for an expiry that WAS read, and the order of the reasons (missing, mismatch,
-- expired, then the unread holds). CREATE OR REPLACE keeps the existing ACL (revoked in
-- the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql).
-- Prevented by: scripts/checks/an_unread_licence_field_is_held_never_approved.test.mjs, and the suite''s gate probe,
-- which measures this file inside a rolled-back transaction before it is applied (--gate-sql).

create or replace function public.fn_sales_engineer_verifies_supplier(p_lead_id bigint, p_source text DEFAULT ''save_profile''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''public'', ''pg_temp''
AS $function$
declare l public.leads; v_missing text[]; v_expired boolean; v_name_mismatch boolean; v_name_unread boolean; v_expiry_unread boolean; v_number_unread boolean; v_auto boolean; v_reason text; v_decision text; v_changed int;
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
  -- ...and an unread name is not a match: no name match, no automatic approval.
  v_name_unread := public.fn_company_name_norm(coalesce(l.licence_legal_name, '''')) = '''';
  -- 7 Oct 2026: a licence on file whose expiry or number nobody could read is not a licence that was checked.
  v_expiry_unread := l.license_doc_path is not null and l.license_expiry is null;
  v_number_unread := l.license_doc_path is not null and coalesce(btrim(l.trade_license_no), '''') = '''';
  select coalesce(p.auto_approve_suppliers, false) into v_auto from public.pricing_config p where p.id = 1;
  v_reason := case when cardinality(v_missing) > 0 then v_missing[1]
                   when v_name_mismatch then ''licence_name_mismatch''
                   when v_expired then ''licence_expired'' end;

  if coalesce(l.approval_status, '''') = ''approved'' and cardinality(v_missing) = 0 and not v_name_unread and not v_name_mismatch then
    -- An approved supplier whose licence has since expired stays approved: fn_reconcile_doc_blocks
    -- pauses their matching and restores it on renewal, without taking the registration away.
    v_decision := ''approved'';
  elsif v_reason is not null then v_decision := ''action_required'';
  elsif v_name_unread then v_decision := ''pending''; v_reason := ''licence_unreadable'';
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
  if v_changed > 0 or p_source <> ''mandatory_item_changed'' then
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
  values (''sales_engineer'', ''supplier_verification'', case when v_reason in (''licence_unreadable'', ''licence_expiry_unread'', ''licence_number_unread'') then ''needs_review'' else ''auto_done'' end,
          case when v_decision = ''action_required'' or v_reason in (''licence_unreadable'', ''licence_expiry_unread'', ''licence_number_unread'') then ''medium'' else ''low'' end,
          ''Supplier '' || v_decision || coalesce('' ('' || v_reason || '')'', '''') || '' — '' || left(coalesce(l.company_name, ''supplier #'' || l.id), 120),
          case v_decision
            when ''approved'' then ''No action required. All six mandatory items are present, the licence name matches and the licence is not known to be expired.''
            when ''pending'' then case when v_reason in (''licence_unreadable'', ''licence_expiry_unread'', ''licence_number_unread'')
              then ''Review: complete, but the '' || case v_reason when ''licence_expiry_unread'' then ''expiry date'' when ''licence_number_unread'' then ''licence number'' else ''company name'' end || '' on the trade licence could not be read (a scan the document model could not read, or the model is held). Compare the licence with the registered name, then approve or ask for the right licence. It is never approved automatically without a name match.''
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
end $function$
;
';
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Aluminium LLC', 'qd-0b1f0765-acc0@example.invalid', '+971500000038', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_text', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-28'::date, 'ZZACC-0b1f0765-507919',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Electrical LLC', 'qd-0b1f0765-acc1@example.invalid', '+971500000039', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_scan_pdf', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_ded_old_scan_pdf', 'ZZ DEMO Pearl Electrical LLC', '2028-02-01'::date, 'ZZACC-0b1f0765-515838',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Plumbing LLC', 'qd-0b1f0765-acc2@example.invalid', '+971500000040', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dubai_det_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_text', 'ZZ DEMO Dune Plumbing LLC', '2028-03-02'::date, 'ZZACC-0b1f0765-1023757',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Air LLC', 'qd-0b1f0765-acc3@example.invalid', '+971500000041', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dubai_det_png.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_png', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_png', 'ZZ DEMO Oasis Air LLC', '2027-04-03'::date, 'ZZACC-0b1f0765-1031676',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Floor LLC', 'qd-0b1f0765-acc4@example.invalid', '+971500000042', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_text', 'ZZ DEMO Horizon Floor LLC', '2027-05-04'::date, 'ZZACC-0b1f0765-CN-1523645',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Carpentry LLC', 'qd-0b1f0765-acc5@example.invalid', '+971500000043', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_jpg.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_jpg', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_jpg', 'ZZ DEMO Saker Carpentry LLC', '2029-06-05'::date, 'ZZACC-0b1f0765-CN-1628374',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_adgm_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_adgm_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Painting Ltd', 'qd-0b1f0765-acc6@example.invalid', '+971500000044', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_adgm_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_adgm_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_adgm_text', 'ZZ DEMO Marina Painting Ltd', '2027-07-06'::date, 'ZZACC-0b1f0765-000010259',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_adgm_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_adgm_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Building Ltd', 'qd-0b1f0765-acc7@example.invalid', '+971500000045', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_adgm_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_adgm_rotated90', 'profiles/zzdemo-accuracy-0b1f0765/lic_adgm_rotated90', 'ZZ DEMO Crescent Building Ltd', '2028-08-07'::date, 'ZZACC-0b1f0765-000010296',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Landscaping LLC', 'qd-0b1f0765-acc8@example.invalid', '+971500000046', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_text', 'ZZ DEMO Ghaf Landscaping LLC', '2028-09-08'::date, 'ZZACC-0b1f0765-705517',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_skewed');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Palm Glass LLC', 'qd-0b1f0765-acc9@example.invalid', '+971500000047', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_skewed.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_skewed', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_skewed', 'ZZ DEMO Palm Glass LLC', '2027-01-09'::date, 'ZZACC-0b1f0765-706130',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sidra Lifts Est', 'qd-0b1f0765-acc10@example.invalid', '+971500000048', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_ajman_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_text', 'ZZ DEMO Sidra Lifts Est', '2027-02-10'::date, 'ZZACC-0b1f0765-12981',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_lowdpi');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Nakheel Fire Est', 'qd-0b1f0765-acc11@example.invalid', '+971500000049', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_ajman_ded_lowdpi.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_lowdpi', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_lowdpi', 'ZZ DEMO Nakheel Fire Est', '2029-03-11'::date, 'ZZACC-0b1f0765-13252',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_rak_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_rak_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Corniche Aluminium LLC', 'qd-0b1f0765-acc12@example.invalid', '+971500000050', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_rak_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_rak_ded_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_rak_ded_text', 'ZZ DEMO Corniche Aluminium LLC', '2027-04-12'::date, 'ZZACC-0b1f0765-24303',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_rak_ded_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_rak_ded_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Lulu Electrical LLC', 'qd-0b1f0765-acc13@example.invalid', '+971500000051', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_rak_ded_phone.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_rak_ded_phone', 'profiles/zzdemo-accuracy-0b1f0765/lic_rak_ded_phone', 'ZZ DEMO Lulu Electrical LLC', '2028-05-13'::date, 'ZZACC-0b1f0765-24634',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_rakez_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_rakez_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Wadi Plumbing FZ LLC', 'qd-0b1f0765-acc14@example.invalid', '+971500000052', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_rakez_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_rakez_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_rakez_text', 'ZZ DEMO Wadi Plumbing FZ LLC', '2028-06-14'::date, 'ZZACC-0b1f0765-5115755',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_rakez_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_rakez_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Qamar Air FZ LLC', 'qd-0b1f0765-acc15@example.invalid', '+971500000053', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_rakez_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_rakez_scan_pdf', 'profiles/zzdemo-accuracy-0b1f0765/lic_rakez_scan_pdf', 'ZZ DEMO Qamar Air FZ LLC', '2027-07-15'::date, 'ZZACC-0b1f0765-5123472',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_uaq_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_uaq_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Najm Floor LLC', 'qd-0b1f0765-acc16@example.invalid', '+971500000054', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_uaq_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_uaq_ded_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_uaq_ded_text', 'ZZ DEMO Najm Floor LLC', '2027-08-16'::date, 'ZZACC-0b1f0765-4649',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_uaq_ded_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_uaq_ded_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Carpentry LLC', 'qd-0b1f0765-acc17@example.invalid', '+971500000055', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_uaq_ded_png.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_uaq_ded_png', 'profiles/zzdemo-accuracy-0b1f0765/lic_uaq_ded_png', 'ZZ DEMO Reem Carpentry LLC', '2029-09-17'::date, 'ZZACC-0b1f0765-4746',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Painting LLC', 'qd-0b1f0765-acc18@example.invalid', '+971500000056', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_text', 'ZZ DEMO Falcon Painting LLC', '2027-01-18'::date, 'ZZACC-0b1f0765-42147',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Building LLC', 'qd-0b1f0765-acc19@example.invalid', '+971500000057', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_jpg.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_jpg', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_jpg', 'ZZ DEMO Pearl Building LLC', '2028-02-19'::date, 'ZZACC-0b1f0765-42260',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Landscaping FZE', 'qd-0b1f0765-acc20@example.invalid', '+971500000058', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_jafza_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_text', 'ZZ DEMO Dune Landscaping FZE', '2028-03-20'::date, 'ZZACC-0b1f0765-189691',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Glass FZE', 'qd-0b1f0765-acc21@example.invalid', '+971500000059', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_jafza_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_rotated90', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_rotated90', 'ZZ DEMO Oasis Glass FZE', '2027-04-21'::date, 'ZZACC-0b1f0765-193962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Lifts DMCC', 'qd-0b1f0765-acc22@example.invalid', '+971500000060', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dmcc_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_text', 'ZZ DEMO Horizon Lifts DMCC', '2027-05-22'::date, 'ZZACC-0b1f0765-DMCC-238161',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_skewed');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Fire DMCC', 'qd-0b1f0765-acc23@example.invalid', '+971500000061', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dmcc_skewed.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_skewed', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_skewed', 'ZZ DEMO Saker Fire DMCC', '2029-06-23'::date, 'ZZACC-0b1f0765-DMCC-244168',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dafza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Aluminium FZ LLC', 'qd-0b1f0765-acc24@example.invalid', '+971500000062', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dafza_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dafza_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_dafza_text', 'ZZ DEMO Marina Aluminium FZ LLC', '2027-07-24'::date, 'ZZACC-0b1f0765-1925',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dafza_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dafza_lowdpi');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Electrical FZ LLC', 'qd-0b1f0765-acc25@example.invalid', '+971500000063', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dafza_lowdpi.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dafza_lowdpi', 'profiles/zzdemo-accuracy-0b1f0765/lic_dafza_lowdpi', 'ZZ DEMO Crescent Electrical FZ LLC', '2028-08-25'::date, 'ZZACC-0b1f0765-1962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dso_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dso_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Plumbing FZ LLC', 'qd-0b1f0765-acc26@example.invalid', '+971500000064', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dso_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dso_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_dso_text', 'ZZ DEMO Ghaf Plumbing FZ LLC', '2028-09-26'::date, 'ZZACC-0b1f0765-21043',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dso_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dso_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Palm Air FZ LLC', 'qd-0b1f0765-acc27@example.invalid', '+971500000065', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dso_phone.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dso_phone', 'profiles/zzdemo-accuracy-0b1f0765/lic_dso_phone', 'ZZ DEMO Palm Air FZ LLC', '2027-01-28'::date, 'ZZACC-0b1f0765-21452',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_ifza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_ifza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sidra Floor FZ LLC', 'qd-0b1f0765-acc28@example.invalid', '+971500000066', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_ifza_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_ifza_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_ifza_text', 'ZZ DEMO Sidra Floor FZ LLC', '2027-02-01'::date, 'ZZACC-0b1f0765-24587',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_ifza_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_ifza_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Nakheel Carpentry FZ LLC', 'qd-0b1f0765-acc29@example.invalid', '+971500000067', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_ifza_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_ifza_scan_pdf', 'profiles/zzdemo-accuracy-0b1f0765/lic_ifza_scan_pdf', 'ZZ DEMO Nakheel Carpentry FZ LLC', '2029-03-02'::date, 'ZZACC-0b1f0765-25090',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_meydan_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_meydan_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Corniche Painting FZ LLC', 'qd-0b1f0765-acc30@example.invalid', '+971500000068', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_meydan_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_meydan_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_meydan_text', 'ZZ DEMO Corniche Painting FZ LLC', '2027-04-03'::date, 'ZZACC-0b1f0765-MFZ-7541',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_meydan_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_meydan_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Lulu Building FZ LLC', 'qd-0b1f0765-acc31@example.invalid', '+971500000069', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_meydan_png.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_meydan_png', 'profiles/zzdemo-accuracy-0b1f0765/lic_meydan_png', 'ZZ DEMO Lulu Building FZ LLC', '2028-05-04'::date, 'ZZACC-0b1f0765-MFZ-7752',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_shams_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_shams_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Wadi Landscaping FZE', 'qd-0b1f0765-acc32@example.invalid', '+971500000070', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_shams_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_shams_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_shams_text', 'ZZ DEMO Wadi Landscaping FZE', '2028-06-05'::date, 'ZZACC-0b1f0765-2033429',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_shams_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_shams_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Qamar Glass FZE', 'qd-0b1f0765-acc33@example.invalid', '+971500000071', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_shams_jpg.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_shams_jpg', 'profiles/zzdemo-accuracy-0b1f0765/lic_shams_jpg', 'ZZ DEMO Qamar Glass FZE', '2027-07-06'::date, 'ZZACC-0b1f0765-2034442',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_difc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_difc_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Najm Lifts Ltd', 'qd-0b1f0765-acc34@example.invalid', '+971500000072', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_difc_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_difc_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_difc_text', 'ZZ DEMO Najm Lifts Ltd', '2027-08-07'::date, 'ZZACC-0b1f0765-CL2015',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_difc_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_difc_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Fire Ltd', 'qd-0b1f0765-acc35@example.invalid', '+971500000073', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_difc_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_difc_rotated90', 'profiles/zzdemo-accuracy-0b1f0765/lic_difc_rotated90', 'ZZ DEMO Reem Fire Ltd', '2029-09-08'::date, 'ZZACC-0b1f0765-CL2044',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_bi_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_bi_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Aluminium LLC', 'qd-0b1f0765-acc36@example.invalid', '+971500000074', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dubai_det_bi_jpg.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dubai_det_bi_jpg', 'profiles/zzdemo-accuracy-0b1f0765/lic_dubai_det_bi_jpg', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-09'::date, 'ZZACC-0b1f0765-1293003',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_bi_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_bi_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Electrical LLC', 'qd-0b1f0765-acc37@example.invalid', '+971500000075', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_bi_phone.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_bi_phone', 'profiles/zzdemo-accuracy-0b1f0765/lic_sharjah_sedd_bi_phone', 'ZZ DEMO Pearl Electrical LLC', '2028-02-10'::date, 'ZZACC-0b1f0765-723294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_bi_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_bi_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Plumbing LLC', 'qd-0b1f0765-acc38@example.invalid', '+971500000076', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_bi_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_bi_scan_pdf', 'profiles/zzdemo-accuracy-0b1f0765/lic_abu_dhabi_added_bi_scan_pdf', 'ZZ DEMO Dune Plumbing LLC', '2028-03-11'::date, 'ZZACC-0b1f0765-CN-5084431',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_ar_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_ar_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Air Est', 'qd-0b1f0765-acc39@example.invalid', '+971500000077', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_ajman_ded_ar_png.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_ajman_ded_ar_png', 'profiles/zzdemo-accuracy-0b1f0765/lic_ajman_ded_ar_png', null, '2027-04-12'::date, 'ZZACC-0b1f0765-20840',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_ajman_ded_ar_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_ar_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_ar_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Floor LLC', 'qd-0b1f0765-acc40@example.invalid', '+971500000078', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_ar_jpg.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_ar_jpg', 'profiles/zzdemo-accuracy-0b1f0765/lic_fujairah_ded_ar_jpg', null, '2027-05-13'::date, 'ZZACC-0b1f0765-44633',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_multipage');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Carpentry DMCC', 'qd-0b1f0765-acc41@example.invalid', '+971500000079', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_dmcc_multipage.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_dmcc_multipage', 'profiles/zzdemo-accuracy-0b1f0765/lic_dmcc_multipage', 'ZZ DEMO Saker Carpentry DMCC', '2029-06-14'::date, 'ZZACC-0b1f0765-DMCC-352294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_multipage');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Painting FZE', 'qd-0b1f0765-acc42@example.invalid', '+971500000080', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_jafza_multipage.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_jafza_multipage', 'profiles/zzdemo-accuracy-0b1f0765/lic_jafza_multipage', 'ZZ DEMO Marina Painting FZE', '2027-07-15'::date, 'ZZACC-0b1f0765-183654',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_expired_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_expired_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Building LLC', 'qd-0b1f0765-acc43@example.invalid', '+971500000081', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_expired_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_expired_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_expired_text', 'ZZ DEMO Crescent Building LLC', '2025-06-30'::date, 'ZZACC-0b1f0765-1348436',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_expired_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_expired_scan');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Landscaping LLC', 'qd-0b1f0765-acc44@example.invalid', '+971500000082', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_expired_scan.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_expired_scan', 'profiles/zzdemo-accuracy-0b1f0765/lic_expired_scan', 'ZZ DEMO Ghaf Landscaping LLC', '2026-02-10'::date, 'ZZACC-0b1f0765-727585',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_mismatch_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_mismatch_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sahara Technical Services LLC', 'qd-0b1f0765-acc45@example.invalid', '+971500000083', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_mismatch_text.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_mismatch_text', 'profiles/zzdemo-accuracy-0b1f0765/lic_mismatch_text', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-0b1f0765-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_mismatch_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_mismatch_scan');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Zenith Maintenance FZ LLC', 'qd-0b1f0765-acc46@example.invalid', '+971500000084', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_mismatch_scan.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_mismatch_scan', 'profiles/zzdemo-accuracy-0b1f0765/lic_mismatch_scan', 'ZZ DEMO Atlas Building Works FZ LLC', '2027-02-19'::date, 'ZZACC-0b1f0765-5362699',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_blank_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_blank_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Blank Page LLC', 'qd-0b1f0765-acc47@example.invalid', '+971500000085', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_blank_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_blank_pdf', 'profiles/zzdemo-accuracy-0b1f0765/lic_blank_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/lic_blank_photo');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_blank_photo');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Blank Photo LLC', 'qd-0b1f0765-acc48@example.invalid', '+971500000086', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_blank_photo.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/lic_blank_photo', 'profiles/zzdemo-accuracy-0b1f0765/lic_blank_photo', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_photo', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/lic_missing');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO No Licence LLC', 'qd-0b1f0765-acc49@example.invalid', '+971500000087', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/lic_missing.pdf',
          null, 'profiles/zzdemo-accuracy-0b1f0765/lic_missing', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_missing', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Projects LLC', 'qd-0b1f0765-acc50@example.invalid', '+971500000088', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_pdf-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_pdf', 'ZZ DEMO Oasis Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-50',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_docx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_docx');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Projects LLC', 'qd-0b1f0765-acc51@example.invalid', '+971500000089', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_docx.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_docx-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_docx', 'ZZ DEMO Horizon Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-51',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_pptx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_pptx');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Projects LLC', 'qd-0b1f0765-acc52@example.invalid', '+971500000000', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_pptx.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_pptx-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_pptx', 'ZZ DEMO Saker Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-52',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_png-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Projects LLC', 'qd-0b1f0765-acc53@example.invalid', '+971500000001', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_png.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_png-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_png', 'ZZ DEMO Marina Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-53',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'profile_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_pdf_paint-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_pdf_paint');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Projects LLC', 'qd-0b1f0765-acc54@example.invalid', '+971500000002', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_pdf_paint.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_pdf_paint-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_pdf_paint', 'ZZ DEMO Crescent Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-54',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/profile_docx_land-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/profile_docx_land');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Projects LLC', 'qd-0b1f0765-acc55@example.invalid', '+971500000003', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/profile_docx_land.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/profile_docx_land-licence', 'profiles/zzdemo-accuracy-0b1f0765/profile_docx_land', 'ZZ DEMO Ghaf Projects LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-55',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b1f0765/catalogue_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b1f0765/catalogue_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Building Supplies LLC', 'qd-0b1f0765-acc56@example.invalid', '+971500000004', true, true, now(), 'terms/zzdemo-accuracy-0b1f0765/catalogue_pdf.pdf',
          'licenses/zzdemo-accuracy-0b1f0765/catalogue_pdf-licence', 'profiles/zzdemo-accuracy-0b1f0765/catalogue_pdf', 'ZZ DEMO Reem Building Supplies LLC', '2028-12-31'::date, 'ZZACC-0b1f0765-ZZACC-56',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b1f0765']::text[])
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
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
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
do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Aluminium LLC', 'qd-accxhlmhn-acc0@example.invalid', '+971500000055', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_text', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-28'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dubai_ded_old_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Electrical LLC', 'qd-accxhlmhn-acc1@example.invalid', '+971500000056', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_scan_pdf', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_ded_old_scan_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dubai_ded_old_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Plumbing LLC', 'qd-accxhlmhn-acc2@example.invalid', '+971500000057', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dubai_det_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_text', null, '2028-03-02'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Air LLC', 'qd-accxhlmhn-acc3@example.invalid', '+971500000058', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dubai_det_png.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_png', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_png', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dubai_det_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Floor LLC', 'qd-accxhlmhn-acc4@example.invalid', '+971500000059', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_text', 'ZZ DEMO Horizon Floor LLC', '2027-05-04'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['cleaning_chemicals','flooring','glass_containers','glazing','racking_storage']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['cleaning_chemicals','flooring','glass_containers','glazing','racking_storage']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Carpentry LLC', 'qd-accxhlmhn-acc5@example.invalid', '+971500000060', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_jpg.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_jpg', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_jpg', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_adgm_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_adgm_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Painting Ltd', 'qd-accxhlmhn-acc6@example.invalid', '+971500000061', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_adgm_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_adgm_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_adgm_text', null, '2027-07-06'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_adgm_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_adgm_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_adgm_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Building Ltd', 'qd-accxhlmhn-acc7@example.invalid', '+971500000062', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_adgm_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_adgm_rotated90', 'profiles/zzdemo-accuracy-accxhlmhn/lic_adgm_rotated90', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_adgm_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Landscaping LLC', 'qd-accxhlmhn-acc8@example.invalid', '+971500000063', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_text', null, '2028-09-08'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_skewed');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Palm Glass LLC', 'qd-accxhlmhn-acc9@example.invalid', '+971500000064', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_skewed.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_skewed', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_skewed', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_skewed', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sidra Lifts Est', 'qd-accxhlmhn-acc10@example.invalid', '+971500000065', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_text', 'ZZ DEMO Sidra Lifts', '2027-02-10'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ajman_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_lowdpi');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Nakheel Fire Est', 'qd-accxhlmhn-acc11@example.invalid', '+971500000066', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_lowdpi.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_lowdpi', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_lowdpi', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_ajman_ded_lowdpi', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_rak_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rak_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Corniche Aluminium LLC', 'qd-accxhlmhn-acc12@example.invalid', '+971500000067', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_rak_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_rak_ded_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rak_ded_text', 'ZZ DEMO Corniche Aluminium LLC', '2027-04-12'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_rak_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_rak_ded_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rak_ded_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Lulu Electrical LLC', 'qd-accxhlmhn-acc13@example.invalid', '+971500000068', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_rak_ded_phone.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_rak_ded_phone', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rak_ded_phone', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_rak_ded_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_rakez_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rakez_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Wadi Plumbing FZ LLC', 'qd-accxhlmhn-acc14@example.invalid', '+971500000069', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_rakez_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_rakez_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rakez_text', null, '2028-06-14'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_rakez_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rakez_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Qamar Air FZ LLC', 'qd-accxhlmhn-acc15@example.invalid', '+971500000070', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_rakez_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_rakez_scan_pdf', 'profiles/zzdemo-accuracy-accxhlmhn/lic_rakez_scan_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_rakez_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Najm Floor LLC', 'qd-accxhlmhn-acc16@example.invalid', '+971500000071', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_text', 'ZZ DEMO Najm Floor LLC', '2027-08-16'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['cleaning_chemicals','flooring','glass_containers','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['cleaning_chemicals','flooring','glass_containers','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_uaq_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Carpentry LLC', 'qd-accxhlmhn-acc17@example.invalid', '+971500000072', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_png.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_png', 'profiles/zzdemo-accuracy-accxhlmhn/lic_uaq_ded_png', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_uaq_ded_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Painting LLC', 'qd-accxhlmhn-acc18@example.invalid', '+971500000073', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_text', 'ZZ DEMO Falcon Painting LLC', '2027-01-18'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Building LLC', 'qd-accxhlmhn-acc19@example.invalid', '+971500000074', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_jpg.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_jpg', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_jpg', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Landscaping FZE', 'qd-accxhlmhn-acc20@example.invalid', '+971500000075', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_jafza_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_text', null, '2028-03-20'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_jafza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Glass FZE', 'qd-accxhlmhn-acc21@example.invalid', '+971500000076', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_jafza_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_rotated90', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_rotated90', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_jafza_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Lifts DMCC', 'qd-accxhlmhn-acc22@example.invalid', '+971500000077', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dmcc_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_text', 'ZZ DEMO Horizon Lifts DMCC', '2027-05-22'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dmcc_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_skewed');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Fire DMCC', 'qd-accxhlmhn-acc23@example.invalid', '+971500000078', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dmcc_skewed.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_skewed', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_skewed', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dmcc_skewed', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dafza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Aluminium FZ LLC', 'qd-accxhlmhn-acc24@example.invalid', '+971500000079', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dafza_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dafza_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dafza_text', null, '2027-07-24'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dafza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dafza_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dafza_lowdpi');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Electrical FZ LLC', 'qd-accxhlmhn-acc25@example.invalid', '+971500000080', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dafza_lowdpi.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dafza_lowdpi', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dafza_lowdpi', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dafza_lowdpi', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dso_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dso_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Plumbing FZ LLC', 'qd-accxhlmhn-acc26@example.invalid', '+971500000081', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dso_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dso_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dso_text', 'ZZ DEMO Ghaf Plumbing FZ LLC', '2028-09-26'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dso_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dso_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Palm Air FZ LLC', 'qd-accxhlmhn-acc27@example.invalid', '+971500000082', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dso_phone.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dso_phone', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dso_phone', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dso_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_ifza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ifza_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sidra Floor FZ LLC', 'qd-accxhlmhn-acc28@example.invalid', '+971500000083', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_ifza_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_ifza_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ifza_text', null, '2027-02-01'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['cleaning_chemicals','flooring','glass_containers','glazing','racking_storage']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['cleaning_chemicals','flooring','glass_containers','glazing','racking_storage']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ifza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_ifza_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ifza_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Nakheel Carpentry FZ LLC', 'qd-accxhlmhn-acc29@example.invalid', '+971500000084', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_ifza_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_ifza_scan_pdf', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ifza_scan_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_ifza_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_meydan_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_meydan_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Corniche Painting FZ LLC', 'qd-accxhlmhn-acc30@example.invalid', '+971500000085', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_meydan_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_meydan_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_meydan_text', 'ZZ DEMO Corniche Painting FZ LLC', '2027-04-03'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_meydan_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_meydan_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_meydan_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Lulu Building FZ LLC', 'qd-accxhlmhn-acc31@example.invalid', '+971500000086', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_meydan_png.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_meydan_png', 'profiles/zzdemo-accuracy-accxhlmhn/lic_meydan_png', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_meydan_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_shams_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_shams_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Wadi Landscaping FZE', 'qd-accxhlmhn-acc32@example.invalid', '+971500000087', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_shams_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_shams_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_shams_text', null, '2028-06-05'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['electrical']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['electrical']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_shams_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_shams_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_shams_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Qamar Glass FZE', 'qd-accxhlmhn-acc33@example.invalid', '+971500000088', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_shams_jpg.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_shams_jpg', 'profiles/zzdemo-accuracy-accxhlmhn/lic_shams_jpg', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_shams_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_difc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_difc_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Najm Lifts Ltd', 'qd-accxhlmhn-acc34@example.invalid', '+971500000089', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_difc_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_difc_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_difc_text', 'ZZ DEMO Najm Lifts Ltd', '2027-08-07'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_difc_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_difc_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_difc_rotated90');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Fire Ltd', 'qd-accxhlmhn-acc35@example.invalid', '+971500000000', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_difc_rotated90.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_difc_rotated90', 'profiles/zzdemo-accuracy-accxhlmhn/lic_difc_rotated90', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_difc_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_bi_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_bi_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Falcon Aluminium LLC', 'qd-accxhlmhn-acc36@example.invalid', '+971500000001', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dubai_det_bi_jpg.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dubai_det_bi_jpg', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dubai_det_bi_jpg', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_dubai_det_bi_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_bi_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_bi_phone');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Pearl Electrical LLC', 'qd-accxhlmhn-acc37@example.invalid', '+971500000002', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_bi_phone.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_bi_phone', 'profiles/zzdemo-accuracy-accxhlmhn/lic_sharjah_sedd_bi_phone', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_sharjah_sedd_bi_phone', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_bi_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_bi_scan_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Dune Plumbing LLC', 'qd-accxhlmhn-acc38@example.invalid', '+971500000003', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_bi_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_bi_scan_pdf', 'profiles/zzdemo-accuracy-accxhlmhn/lic_abu_dhabi_added_bi_scan_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_abu_dhabi_added_bi_scan_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_ar_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_ar_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Air Est', 'qd-accxhlmhn-acc39@example.invalid', '+971500000004', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_ar_png.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_ar_png', 'profiles/zzdemo-accuracy-accxhlmhn/lic_ajman_ded_ar_png', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_ajman_ded_ar_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_ar_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_ar_jpg');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Floor LLC', 'qd-accxhlmhn-acc40@example.invalid', '+971500000005', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_ar_jpg.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_ar_jpg', 'profiles/zzdemo-accuracy-accxhlmhn/lic_fujairah_ded_ar_jpg', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_ar_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_multipage');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Carpentry DMCC', 'qd-accxhlmhn-acc41@example.invalid', '+971500000006', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_dmcc_multipage.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_dmcc_multipage', 'profiles/zzdemo-accuracy-accxhlmhn/lic_dmcc_multipage', 'ZZ DEMO Saker Carpentry DMCC', '2029-06-14'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['elevators']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['elevators']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dmcc_multipage', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_multipage');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Painting FZE', 'qd-accxhlmhn-acc42@example.invalid', '+971500000007', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_jafza_multipage.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_jafza_multipage', 'profiles/zzdemo-accuracy-accxhlmhn/lic_jafza_multipage', null, '2027-07-15'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_jafza_multipage', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_expired_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_expired_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Building LLC', 'qd-accxhlmhn-acc43@example.invalid', '+971500000008', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_expired_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_expired_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_expired_text', null, '2025-06-30'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_expired_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_expired_scan');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Landscaping LLC', 'qd-accxhlmhn-acc44@example.invalid', '+971500000009', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_expired_scan.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_expired_scan', 'profiles/zzdemo-accuracy-accxhlmhn/lic_expired_scan', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_expired_scan', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_mismatch_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_mismatch_text');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Sahara Technical Services LLC', 'qd-accxhlmhn-acc45@example.invalid', '+971500000010', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_mismatch_text.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_mismatch_text', 'profiles/zzdemo-accuracy-accxhlmhn/lic_mismatch_text', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glass_containers','glazing','plumbing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glass_containers','glazing','plumbing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_mismatch_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_mismatch_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_mismatch_scan');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Zenith Maintenance FZ LLC', 'qd-accxhlmhn-acc46@example.invalid', '+971500000011', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_mismatch_scan.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_mismatch_scan', 'profiles/zzdemo-accuracy-accxhlmhn/lic_mismatch_scan', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_mismatch_scan', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_blank_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_blank_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Blank Page LLC', 'qd-accxhlmhn-acc47@example.invalid', '+971500000012', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_blank_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_blank_pdf', 'profiles/zzdemo-accuracy-accxhlmhn/lic_blank_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/lic_blank_photo');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_blank_photo');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Blank Photo LLC', 'qd-accxhlmhn-acc48@example.invalid', '+971500000013', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_blank_photo.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/lic_blank_photo', 'profiles/zzdemo-accuracy-accxhlmhn/lic_blank_photo', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_photo', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/lic_missing');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO No Licence LLC', 'qd-accxhlmhn-acc49@example.invalid', '+971500000014', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/lic_missing.pdf',
          null, 'profiles/zzdemo-accuracy-accxhlmhn/lic_missing', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_missing', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Oasis Projects LLC', 'qd-accxhlmhn-acc50@example.invalid', '+971500000015', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_pdf-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pdf', 'ZZ DEMO Oasis Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-50',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['glazing','iso_certification']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['glazing','iso_certification']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_docx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_docx');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Horizon Projects LLC', 'qd-accxhlmhn-acc51@example.invalid', '+971500000016', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_docx.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_docx-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_docx', 'ZZ DEMO Horizon Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-51',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['iso_certification']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['iso_certification']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_docx', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_pptx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pptx');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Saker Projects LLC', 'qd-accxhlmhn-acc52@example.invalid', '+971500000017', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_pptx.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_pptx-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pptx', 'ZZ DEMO Saker Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-52',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['iso_certification']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['iso_certification']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pptx', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_png-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_png');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Marina Projects LLC', 'qd-accxhlmhn-acc53@example.invalid', '+971500000018', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_png.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_png-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_png', 'ZZ DEMO Marina Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-53',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'profile_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_pdf_paint-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pdf_paint');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Crescent Projects LLC', 'qd-accxhlmhn-acc54@example.invalid', '+971500000019', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_pdf_paint.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_pdf_paint-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_pdf_paint', 'ZZ DEMO Crescent Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-54',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['iso_certification','painting','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['iso_certification','painting','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pdf_paint', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/profile_docx_land-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/profile_docx_land');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Ghaf Projects LLC', 'qd-accxhlmhn-acc55@example.invalid', '+971500000020', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/profile_docx_land.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/profile_docx_land-licence', 'profiles/zzdemo-accuracy-accxhlmhn/profile_docx_land', 'ZZ DEMO Ghaf Projects LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-55',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['iso_certification']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['iso_certification']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_docx_land', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-accxhlmhn/catalogue_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-accxhlmhn/catalogue_pdf');
  insert into public.leads (company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('ZZ DEMO Reem Building Supplies LLC', 'qd-accxhlmhn-acc56@example.invalid', '+971500000021', true, true, now(), 'terms/zzdemo-accuracy-accxhlmhn/catalogue_pdf.pdf',
          'licenses/zzdemo-accuracy-accxhlmhn/catalogue_pdf-licence', 'profiles/zzdemo-accuracy-accxhlmhn/catalogue_pdf', 'ZZ DEMO Reem Building Supplies LLC', '2028-12-31'::date, 'ZZACC-accxhlmhn-ZZACC-56',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:accxhlmhn']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'catalogue_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid));
  mt := mt || jsonb_build_object('aluminium', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['aluminium'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('cleaning_chemicals', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['cleaning_chemicals'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('corporate_training', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['corporate_training'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('electrical', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['electrical'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('elevators', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['elevators'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('fire_fighting', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['fire_fighting'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('flooring', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['flooring'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('glass_containers', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['glass_containers'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('glazing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['glazing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('hvac', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['hvac'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('iso_certification', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['iso_certification'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('joinery', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['joinery'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('landscaping', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['landscaping'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('painting', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['painting'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('plumbing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['plumbing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('racking_storage', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['racking_storage'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('tax_advisory', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['tax_advisory'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('waterproofing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['waterproofing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  raise exception 'CHK<<%>>', jsonb_build_object('gate', res, 'match', mt)::text;
end $probe$;
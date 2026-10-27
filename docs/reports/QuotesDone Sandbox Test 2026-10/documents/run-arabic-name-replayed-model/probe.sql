do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-acc59w8y7-acc0@example.invalid', '+971500000083', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_text', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-28'::date, 'ZZACC-acc59w8y7-507919',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-acc59w8y7-acc1@example.invalid', '+971500000084', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_scan_pdf', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_ded_old_scan_pdf', 'ZZ DEMO Pearl Electrical LLC', '2028-02-01'::date, 'ZZACC-acc59w8y7-515838',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-acc59w8y7-acc2@example.invalid', '+971500000085', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dubai_det_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_text', 'ZZ DEMO Dune Plumbing LLC', '2028-03-02'::date, 'ZZACC-acc59w8y7-1023757',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air LLC', 'qd-acc59w8y7-acc3@example.invalid', '+971500000086', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dubai_det_png.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_png', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_png', 'ZZ DEMO Oasis Air LLC', '2027-04-03'::date, 'ZZACC-acc59w8y7-1031676',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-acc59w8y7-acc4@example.invalid', '+971500000087', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_text', 'ZZ DEMO Horizon Floor LLC', '2027-05-04'::date, 'ZZACC-acc59w8y7-CN-1523645',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry LLC', 'qd-acc59w8y7-acc5@example.invalid', '+971500000088', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_jpg.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_jpg', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_jpg', 'ZZ DEMO Saker Carpentry LLC', '2029-06-05'::date, 'ZZACC-acc59w8y7-CN-1628374',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_adgm_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_adgm_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting Ltd', 'qd-acc59w8y7-acc6@example.invalid', '+971500000089', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_adgm_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_adgm_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_adgm_text', 'ZZ DEMO Marina Painting Ltd', '2027-07-06'::date, 'ZZACC-acc59w8y7-000010259',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_adgm_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_adgm_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building Ltd', 'qd-acc59w8y7-acc7@example.invalid', '+971500000000', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_adgm_rotated90.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_adgm_rotated90', 'profiles/zzdemo-accuracy-acc59w8y7/lic_adgm_rotated90', 'ZZ DEMO Crescent Building Ltd', '2028-08-07'::date, 'ZZACC-acc59w8y7-000010296',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-acc59w8y7-acc8@example.invalid', '+971500000001', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_text', 'ZZ DEMO Ghaf Landscaping LLC', '2028-09-08'::date, 'ZZACC-acc59w8y7-705517',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Glass LLC', 'qd-acc59w8y7-acc9@example.invalid', '+971500000002', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_skewed.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_skewed', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_skewed', 'ZZ DEMO Palm Glass LLC', '2027-01-09'::date, 'ZZACC-acc59w8y7-706130',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Lifts Est', 'qd-acc59w8y7-acc10@example.invalid', '+971500000003', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_text', 'ZZ DEMO Sidra Lifts Est', '2027-02-10'::date, 'ZZACC-acc59w8y7-12981',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Fire Est', 'qd-acc59w8y7-acc11@example.invalid', '+971500000004', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_lowdpi.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_lowdpi', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_lowdpi', 'ZZ DEMO Nakheel Fire Est', '2029-03-11'::date, 'ZZACC-acc59w8y7-13252',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_rak_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rak_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Aluminium LLC', 'qd-acc59w8y7-acc12@example.invalid', '+971500000005', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_rak_ded_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_rak_ded_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rak_ded_text', 'ZZ DEMO Corniche Aluminium LLC', '2027-04-12'::date, 'ZZACC-acc59w8y7-24303',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_rak_ded_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rak_ded_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Electrical LLC', 'qd-acc59w8y7-acc13@example.invalid', '+971500000006', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_rak_ded_phone.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_rak_ded_phone', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rak_ded_phone', 'ZZ DEMO Lulu Electrical LLC', '2028-05-13'::date, 'ZZACC-acc59w8y7-24634',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_rakez_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rakez_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Plumbing FZ LLC', 'qd-acc59w8y7-acc14@example.invalid', '+971500000007', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_rakez_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_rakez_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rakez_text', 'ZZ DEMO Wadi Plumbing FZ LLC', '2028-06-14'::date, 'ZZACC-acc59w8y7-5115755',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_rakez_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rakez_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Air FZ LLC', 'qd-acc59w8y7-acc15@example.invalid', '+971500000008', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_rakez_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_rakez_scan_pdf', 'profiles/zzdemo-accuracy-acc59w8y7/lic_rakez_scan_pdf', 'ZZ DEMO Qamar Air FZ LLC', '2027-07-15'::date, 'ZZACC-acc59w8y7-5123472',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Floor LLC', 'qd-acc59w8y7-acc16@example.invalid', '+971500000009', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_text', 'ZZ DEMO Najm Floor LLC', '2027-08-16'::date, 'ZZACC-acc59w8y7-4649',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Carpentry LLC', 'qd-acc59w8y7-acc17@example.invalid', '+971500000010', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_png.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_png', 'profiles/zzdemo-accuracy-acc59w8y7/lic_uaq_ded_png', 'ZZ DEMO Reem Carpentry LLC', '2029-09-17'::date, 'ZZACC-acc59w8y7-4746',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Painting LLC', 'qd-acc59w8y7-acc18@example.invalid', '+971500000011', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_text', 'ZZ DEMO Falcon Painting LLC', '2027-01-18'::date, 'ZZACC-acc59w8y7-42147',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Building LLC', 'qd-acc59w8y7-acc19@example.invalid', '+971500000012', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_jpg.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_jpg', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_jpg', 'ZZ DEMO Pearl Building LLC', '2028-02-19'::date, 'ZZACC-acc59w8y7-42260',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Landscaping FZE', 'qd-acc59w8y7-acc20@example.invalid', '+971500000013', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_jafza_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_text', 'ZZ DEMO Dune Landscaping FZE', '2028-03-20'::date, 'ZZACC-acc59w8y7-189691',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Glass FZE', 'qd-acc59w8y7-acc21@example.invalid', '+971500000014', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_jafza_rotated90.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_rotated90', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_rotated90', 'ZZ DEMO Oasis Glass FZE', '2027-04-21'::date, 'ZZACC-acc59w8y7-193962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Lifts DMCC', 'qd-acc59w8y7-acc22@example.invalid', '+971500000015', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dmcc_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_text', 'ZZ DEMO Horizon Lifts DMCC', '2027-05-22'::date, 'ZZACC-acc59w8y7-DMCC-238161',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Fire DMCC', 'qd-acc59w8y7-acc23@example.invalid', '+971500000016', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dmcc_skewed.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_skewed', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_skewed', 'ZZ DEMO Saker Fire DMCC', '2029-06-23'::date, 'ZZACC-acc59w8y7-DMCC-244168',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Aluminium FZ LLC', 'qd-acc59w8y7-acc24@example.invalid', '+971500000017', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dafza_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dafza_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dafza_text', 'ZZ DEMO Marina Aluminium FZ LLC', '2027-07-24'::date, 'ZZACC-acc59w8y7-1925',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dafza_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dafza_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Electrical FZ LLC', 'qd-acc59w8y7-acc25@example.invalid', '+971500000018', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dafza_lowdpi.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dafza_lowdpi', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dafza_lowdpi', 'ZZ DEMO Crescent Electrical FZ LLC', '2028-08-25'::date, 'ZZACC-acc59w8y7-1962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dso_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dso_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Plumbing FZ LLC', 'qd-acc59w8y7-acc26@example.invalid', '+971500000019', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dso_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dso_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dso_text', 'ZZ DEMO Ghaf Plumbing FZ LLC', '2028-09-26'::date, 'ZZACC-acc59w8y7-21043',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dso_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dso_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Air FZ LLC', 'qd-acc59w8y7-acc27@example.invalid', '+971500000020', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dso_phone.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dso_phone', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dso_phone', 'ZZ DEMO Palm Air FZ LLC', '2027-01-28'::date, 'ZZACC-acc59w8y7-21452',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_ifza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ifza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Floor FZ LLC', 'qd-acc59w8y7-acc28@example.invalid', '+971500000021', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_ifza_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_ifza_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ifza_text', 'ZZ DEMO Sidra Floor FZ LLC', '2027-02-01'::date, 'ZZACC-acc59w8y7-24587',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_ifza_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ifza_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Carpentry FZ LLC', 'qd-acc59w8y7-acc29@example.invalid', '+971500000022', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_ifza_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_ifza_scan_pdf', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ifza_scan_pdf', 'ZZ DEMO Nakheel Carpentry FZ LLC', '2029-03-02'::date, 'ZZACC-acc59w8y7-25090',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_meydan_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_meydan_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Painting FZ LLC', 'qd-acc59w8y7-acc30@example.invalid', '+971500000023', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_meydan_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_meydan_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_meydan_text', 'ZZ DEMO Corniche Painting FZ LLC', '2027-04-03'::date, 'ZZACC-acc59w8y7-MFZ-7541',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_meydan_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_meydan_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Building FZ LLC', 'qd-acc59w8y7-acc31@example.invalid', '+971500000024', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_meydan_png.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_meydan_png', 'profiles/zzdemo-accuracy-acc59w8y7/lic_meydan_png', 'ZZ DEMO Lulu Building FZ LLC', '2028-05-04'::date, 'ZZACC-acc59w8y7-MFZ-7752',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_shams_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_shams_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Landscaping FZE', 'qd-acc59w8y7-acc32@example.invalid', '+971500000025', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_shams_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_shams_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_shams_text', 'ZZ DEMO Wadi Landscaping FZE', '2028-06-05'::date, 'ZZACC-acc59w8y7-2033429',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_shams_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_shams_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Glass FZE', 'qd-acc59w8y7-acc33@example.invalid', '+971500000026', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_shams_jpg.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_shams_jpg', 'profiles/zzdemo-accuracy-acc59w8y7/lic_shams_jpg', 'ZZ DEMO Qamar Glass FZE', '2027-07-06'::date, 'ZZACC-acc59w8y7-2034442',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_difc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_difc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Lifts Ltd', 'qd-acc59w8y7-acc34@example.invalid', '+971500000027', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_difc_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_difc_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_difc_text', 'ZZ DEMO Najm Lifts Ltd', '2027-08-07'::date, 'ZZACC-acc59w8y7-CL2015',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_difc_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_difc_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Fire Ltd', 'qd-acc59w8y7-acc35@example.invalid', '+971500000028', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_difc_rotated90.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_difc_rotated90', 'profiles/zzdemo-accuracy-acc59w8y7/lic_difc_rotated90', 'ZZ DEMO Reem Fire Ltd', '2029-09-08'::date, 'ZZACC-acc59w8y7-CL2044',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_bi_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_bi_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-acc59w8y7-acc36@example.invalid', '+971500000029', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dubai_det_bi_jpg.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dubai_det_bi_jpg', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dubai_det_bi_jpg', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-09'::date, 'ZZACC-acc59w8y7-1293003',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_bi_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_bi_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-acc59w8y7-acc37@example.invalid', '+971500000030', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_bi_phone.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_bi_phone', 'profiles/zzdemo-accuracy-acc59w8y7/lic_sharjah_sedd_bi_phone', 'ZZ DEMO Pearl Electrical LLC', '2028-02-10'::date, 'ZZACC-acc59w8y7-723294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_bi_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_bi_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-acc59w8y7-acc38@example.invalid', '+971500000031', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_bi_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_bi_scan_pdf', 'profiles/zzdemo-accuracy-acc59w8y7/lic_abu_dhabi_added_bi_scan_pdf', 'ZZ DEMO Dune Plumbing LLC', '2028-03-11'::date, 'ZZACC-acc59w8y7-CN-5084431',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_ar_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_ar_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air Est', 'qd-acc59w8y7-acc39@example.invalid', '+971500000032', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_ar_png.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_ar_png', 'profiles/zzdemo-accuracy-acc59w8y7/lic_ajman_ded_ar_png', null, '2027-04-12'::date, 'ZZACC-acc59w8y7-20840',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['hvac','landscaping']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['hvac','landscaping']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_ajman_ded_ar_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_ar_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_ar_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-acc59w8y7-acc40@example.invalid', '+971500000033', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_ar_jpg.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_ar_jpg', 'profiles/zzdemo-accuracy-acc59w8y7/lic_fujairah_ded_ar_jpg', null, '2027-05-13'::date, 'ZZACC-acc59w8y7-44633',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['flooring','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['flooring','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_ar_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry DMCC', 'qd-acc59w8y7-acc41@example.invalid', '+971500000034', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_dmcc_multipage.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_dmcc_multipage', 'profiles/zzdemo-accuracy-acc59w8y7/lic_dmcc_multipage', 'ZZ DEMO Saker Carpentry DMCC', '2029-06-14'::date, 'ZZACC-acc59w8y7-DMCC-352294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting FZE', 'qd-acc59w8y7-acc42@example.invalid', '+971500000035', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_jafza_multipage.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_jafza_multipage', 'profiles/zzdemo-accuracy-acc59w8y7/lic_jafza_multipage', 'ZZ DEMO Marina Painting FZE', '2027-07-15'::date, 'ZZACC-acc59w8y7-183654',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_expired_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_expired_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building LLC', 'qd-acc59w8y7-acc43@example.invalid', '+971500000036', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_expired_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_expired_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_expired_text', 'ZZ DEMO Crescent Building LLC', '2025-06-30'::date, 'ZZACC-acc59w8y7-1348436',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_expired_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_expired_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-acc59w8y7-acc44@example.invalid', '+971500000037', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_expired_scan.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_expired_scan', 'profiles/zzdemo-accuracy-acc59w8y7/lic_expired_scan', 'ZZ DEMO Ghaf Landscaping LLC', '2026-02-10'::date, 'ZZACC-acc59w8y7-727585',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sahara Technical Services LLC', 'qd-acc59w8y7-acc45@example.invalid', '+971500000038', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_mismatch_text.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_text', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_text', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-acc59w8y7-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_text_approved_swap');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_text_approved_swap');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('approved', true, 'ZZ DEMO Oasis Swap Trading LLC', 'qd-acc59w8y7-acc46@example.invalid', '+971500000039', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_mismatch_text_approved_swap.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_text_approved_swap', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_text_approved_swap', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-acc59w8y7-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Zenith Maintenance FZ LLC', 'qd-acc59w8y7-acc47@example.invalid', '+971500000040', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_mismatch_scan.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_mismatch_scan', 'profiles/zzdemo-accuracy-acc59w8y7/lic_mismatch_scan', 'ZZ DEMO Atlas Building Works FZ LLC', '2027-02-19'::date, 'ZZACC-acc59w8y7-5362699',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_blank_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_blank_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Page LLC', 'qd-acc59w8y7-acc48@example.invalid', '+971500000041', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_blank_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_blank_pdf', 'profiles/zzdemo-accuracy-acc59w8y7/lic_blank_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/lic_blank_photo');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_blank_photo');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Photo LLC', 'qd-acc59w8y7-acc49@example.invalid', '+971500000042', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_blank_photo.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/lic_blank_photo', 'profiles/zzdemo-accuracy-acc59w8y7/lic_blank_photo', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_photo', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/lic_missing');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO No Licence LLC', 'qd-acc59w8y7-acc50@example.invalid', '+971500000043', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/lic_missing.pdf',
          null, 'profiles/zzdemo-accuracy-acc59w8y7/lic_missing', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_missing', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Projects LLC', 'qd-acc59w8y7-acc51@example.invalid', '+971500000044', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_pdf-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pdf', 'ZZ DEMO Oasis Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-51',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_docx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_docx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Projects LLC', 'qd-acc59w8y7-acc52@example.invalid', '+971500000045', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_docx.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_docx-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_docx', 'ZZ DEMO Horizon Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-52',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_pptx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pptx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Projects LLC', 'qd-acc59w8y7-acc53@example.invalid', '+971500000046', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_pptx.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_pptx-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pptx', 'ZZ DEMO Saker Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-53',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_png-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Projects LLC', 'qd-acc59w8y7-acc54@example.invalid', '+971500000047', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_png.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_png-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_png', 'ZZ DEMO Marina Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-54',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_pdf_paint-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pdf_paint');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Projects LLC', 'qd-acc59w8y7-acc55@example.invalid', '+971500000048', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_pdf_paint.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_pdf_paint-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_pdf_paint', 'ZZ DEMO Crescent Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-55',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/profile_docx_land-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/profile_docx_land');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Projects LLC', 'qd-acc59w8y7-acc56@example.invalid', '+971500000049', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/profile_docx_land.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/profile_docx_land-licence', 'profiles/zzdemo-accuracy-acc59w8y7/profile_docx_land', 'ZZ DEMO Ghaf Projects LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-56',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-acc59w8y7/catalogue_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-acc59w8y7/catalogue_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Building Supplies LLC', 'qd-acc59w8y7-acc57@example.invalid', '+971500000050', true, true, now(), 'terms/zzdemo-accuracy-acc59w8y7/catalogue_pdf.pdf',
          'licenses/zzdemo-accuracy-acc59w8y7/catalogue_pdf-licence', 'profiles/zzdemo-accuracy-acc59w8y7/catalogue_pdf', 'ZZ DEMO Reem Building Supplies LLC', '2028-12-31'::date, 'ZZACC-acc59w8y7-ZZACC-57',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:acc59w8y7']::text[])
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
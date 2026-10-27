do $probe$
declare lid bigint; v jsonb; ids bigint[] := '{}'; res jsonb := '[]'; mt jsonb := '{}';
begin
  
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-0b8b1fd6-acc0@example.invalid', '+971500000028', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_text', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-28'::date, 'ZZACC-0b8b1fd6-507919',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_ded_old_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-0b8b1fd6-acc1@example.invalid', '+971500000029', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_scan_pdf', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_ded_old_scan_pdf', 'ZZ DEMO Pearl Electrical LLC', '2028-02-01'::date, 'ZZACC-0b8b1fd6-515838',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-0b8b1fd6-acc2@example.invalid', '+971500000030', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_text', 'ZZ DEMO Dune Plumbing LLC', '2028-03-02'::date, 'ZZACC-0b8b1fd6-1023757',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air LLC', 'qd-0b8b1fd6-acc3@example.invalid', '+971500000031', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_png.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_png', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_png', 'ZZ DEMO Oasis Air LLC', '2027-04-03'::date, 'ZZACC-0b8b1fd6-1031676',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-0b8b1fd6-acc4@example.invalid', '+971500000032', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_text', 'ZZ DEMO Horizon Floor LLC', '2027-05-04'::date, 'ZZACC-0b8b1fd6-CN-1523645',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry LLC', 'qd-0b8b1fd6-acc5@example.invalid', '+971500000033', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_jpg.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_jpg', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_jpg', 'ZZ DEMO Saker Carpentry LLC', '2029-06-05'::date, 'ZZACC-0b8b1fd6-CN-1628374',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_adgm_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_adgm_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting Ltd', 'qd-0b8b1fd6-acc6@example.invalid', '+971500000034', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_adgm_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_adgm_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_adgm_text', 'ZZ DEMO Marina Painting Ltd', '2027-07-06'::date, 'ZZACC-0b8b1fd6-000010259',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_adgm_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_adgm_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building Ltd', 'qd-0b8b1fd6-acc7@example.invalid', '+971500000035', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_adgm_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_adgm_rotated90', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_adgm_rotated90', 'ZZ DEMO Crescent Building Ltd', '2028-08-07'::date, 'ZZACC-0b8b1fd6-000010296',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_adgm_rotated90', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-0b8b1fd6-acc8@example.invalid', '+971500000036', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_text', 'ZZ DEMO Ghaf Landscaping LLC', '2028-09-08'::date, 'ZZACC-0b8b1fd6-705517',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Glass LLC', 'qd-0b8b1fd6-acc9@example.invalid', '+971500000037', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_skewed.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_skewed', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_skewed', 'ZZ DEMO Palm Glass LLC', '2027-01-09'::date, 'ZZACC-0b8b1fd6-706130',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Lifts Est', 'qd-0b8b1fd6-acc10@example.invalid', '+971500000038', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_text', 'ZZ DEMO Sidra Lifts Est', '2027-02-10'::date, 'ZZACC-0b8b1fd6-12981',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Fire Est', 'qd-0b8b1fd6-acc11@example.invalid', '+971500000039', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_lowdpi.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_lowdpi', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_lowdpi', 'ZZ DEMO Nakheel Fire Est', '2029-03-11'::date, 'ZZACC-0b8b1fd6-13252',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Aluminium LLC', 'qd-0b8b1fd6-acc12@example.invalid', '+971500000040', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_text', 'ZZ DEMO Corniche Aluminium LLC', '2027-04-12'::date, 'ZZACC-0b8b1fd6-24303',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_rak_ded_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Electrical LLC', 'qd-0b8b1fd6-acc13@example.invalid', '+971500000041', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_phone.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_phone', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rak_ded_phone', 'ZZ DEMO Lulu Electrical LLC', '2028-05-13'::date, 'ZZACC-0b8b1fd6-24634',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_rakez_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rakez_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Plumbing FZ LLC', 'qd-0b8b1fd6-acc14@example.invalid', '+971500000042', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_rakez_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_rakez_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rakez_text', 'ZZ DEMO Wadi Plumbing FZ LLC', '2028-06-14'::date, 'ZZACC-0b8b1fd6-5115755',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_rakez_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rakez_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Air FZ LLC', 'qd-0b8b1fd6-acc15@example.invalid', '+971500000043', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_rakez_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_rakez_scan_pdf', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_rakez_scan_pdf', 'ZZ DEMO Qamar Air FZ LLC', '2027-07-15'::date, 'ZZACC-0b8b1fd6-5123472',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Floor LLC', 'qd-0b8b1fd6-acc16@example.invalid', '+971500000044', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_text', 'ZZ DEMO Najm Floor LLC', '2027-08-16'::date, 'ZZACC-0b8b1fd6-4649',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Carpentry LLC', 'qd-0b8b1fd6-acc17@example.invalid', '+971500000045', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_png.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_png', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_uaq_ded_png', 'ZZ DEMO Reem Carpentry LLC', '2029-09-17'::date, 'ZZACC-0b8b1fd6-4746',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Painting LLC', 'qd-0b8b1fd6-acc18@example.invalid', '+971500000046', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_text', 'ZZ DEMO Falcon Painting LLC', '2027-01-18'::date, 'ZZACC-0b8b1fd6-42147',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Building LLC', 'qd-0b8b1fd6-acc19@example.invalid', '+971500000047', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_jpg.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_jpg', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_jpg', 'ZZ DEMO Pearl Building LLC', '2028-02-19'::date, 'ZZACC-0b8b1fd6-42260',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_fujairah_ded_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Landscaping FZE', 'qd-0b8b1fd6-acc20@example.invalid', '+971500000048', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_jafza_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_text', 'ZZ DEMO Dune Landscaping FZE', '2028-03-20'::date, 'ZZACC-0b8b1fd6-189691',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Glass FZE', 'qd-0b8b1fd6-acc21@example.invalid', '+971500000049', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_jafza_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_rotated90', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_rotated90', 'ZZ DEMO Oasis Glass FZE', '2027-04-21'::date, 'ZZACC-0b8b1fd6-193962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Lifts DMCC', 'qd-0b8b1fd6-acc22@example.invalid', '+971500000050', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dmcc_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_text', 'ZZ DEMO Horizon Lifts DMCC', '2027-05-22'::date, 'ZZACC-0b8b1fd6-DMCC-238161',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_skewed');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_skewed');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Fire DMCC', 'qd-0b8b1fd6-acc23@example.invalid', '+971500000051', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dmcc_skewed.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_skewed', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_skewed', 'ZZ DEMO Saker Fire DMCC', '2029-06-23'::date, 'ZZACC-0b8b1fd6-DMCC-244168',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dafza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dafza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Aluminium FZ LLC', 'qd-0b8b1fd6-acc24@example.invalid', '+971500000052', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dafza_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dafza_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dafza_text', 'ZZ DEMO Marina Aluminium FZ LLC', '2027-07-24'::date, 'ZZACC-0b8b1fd6-1925',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dafza_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dafza_lowdpi');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dafza_lowdpi');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Electrical FZ LLC', 'qd-0b8b1fd6-acc25@example.invalid', '+971500000053', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dafza_lowdpi.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dafza_lowdpi', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dafza_lowdpi', 'ZZ DEMO Crescent Electrical FZ LLC', '2028-08-25'::date, 'ZZACC-0b8b1fd6-1962',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dso_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dso_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Plumbing FZ LLC', 'qd-0b8b1fd6-acc26@example.invalid', '+971500000054', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dso_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dso_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dso_text', 'ZZ DEMO Ghaf Plumbing FZ LLC', '2028-09-26'::date, 'ZZACC-0b8b1fd6-21043',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dso_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dso_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Palm Air FZ LLC', 'qd-0b8b1fd6-acc27@example.invalid', '+971500000055', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dso_phone.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dso_phone', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dso_phone', 'ZZ DEMO Palm Air FZ LLC', '2027-01-28'::date, 'ZZACC-0b8b1fd6-21452',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_ifza_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ifza_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sidra Floor FZ LLC', 'qd-0b8b1fd6-acc28@example.invalid', '+971500000056', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_ifza_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_ifza_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ifza_text', 'ZZ DEMO Sidra Floor FZ LLC', '2027-02-01'::date, 'ZZACC-0b8b1fd6-24587',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_ifza_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ifza_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Nakheel Carpentry FZ LLC', 'qd-0b8b1fd6-acc29@example.invalid', '+971500000057', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_ifza_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_ifza_scan_pdf', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ifza_scan_pdf', 'ZZ DEMO Nakheel Carpentry FZ LLC', '2029-03-02'::date, 'ZZACC-0b8b1fd6-25090',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_meydan_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_meydan_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Corniche Painting FZ LLC', 'qd-0b8b1fd6-acc30@example.invalid', '+971500000058', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_meydan_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_meydan_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_meydan_text', 'ZZ DEMO Corniche Painting FZ LLC', '2027-04-03'::date, 'ZZACC-0b8b1fd6-MFZ-7541',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_meydan_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_meydan_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Lulu Building FZ LLC', 'qd-0b8b1fd6-acc31@example.invalid', '+971500000059', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_meydan_png.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_meydan_png', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_meydan_png', 'ZZ DEMO Lulu Building FZ LLC', '2028-05-04'::date, 'ZZACC-0b8b1fd6-MFZ-7752',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_meydan_png', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_shams_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_shams_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Wadi Landscaping FZE', 'qd-0b8b1fd6-acc32@example.invalid', '+971500000060', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_shams_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_shams_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_shams_text', 'ZZ DEMO Wadi Landscaping FZE', '2028-06-05'::date, 'ZZACC-0b8b1fd6-2033429',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_shams_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_shams_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Qamar Glass FZE', 'qd-0b8b1fd6-acc33@example.invalid', '+971500000061', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_shams_jpg.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_shams_jpg', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_shams_jpg', 'ZZ DEMO Qamar Glass FZE', '2027-07-06'::date, 'ZZACC-0b8b1fd6-2034442',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_difc_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_difc_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Najm Lifts Ltd', 'qd-0b8b1fd6-acc34@example.invalid', '+971500000062', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_difc_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_difc_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_difc_text', 'ZZ DEMO Najm Lifts Ltd', '2027-08-07'::date, 'ZZACC-0b8b1fd6-CL2015',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_difc_rotated90');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_difc_rotated90');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Fire Ltd', 'qd-0b8b1fd6-acc35@example.invalid', '+971500000063', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_difc_rotated90.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_difc_rotated90', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_difc_rotated90', 'ZZ DEMO Reem Fire Ltd', '2029-09-08'::date, 'ZZACC-0b8b1fd6-CL2044',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_bi_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_bi_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Falcon Aluminium LLC', 'qd-0b8b1fd6-acc36@example.invalid', '+971500000064', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_bi_jpg.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_bi_jpg', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dubai_det_bi_jpg', 'ZZ DEMO Falcon Aluminium LLC', '2027-01-09'::date, 'ZZACC-0b8b1fd6-1293003',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','joinery']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','joinery']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_dubai_det_bi_jpg', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_bi_phone');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_bi_phone');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Pearl Electrical LLC', 'qd-0b8b1fd6-acc37@example.invalid', '+971500000065', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_bi_phone.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_bi_phone', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_sharjah_sedd_bi_phone', 'ZZ DEMO Pearl Electrical LLC', '2028-02-10'::date, 'ZZACC-0b8b1fd6-723294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_bi_scan_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_bi_scan_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Dune Plumbing LLC', 'qd-0b8b1fd6-acc38@example.invalid', '+971500000066', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_bi_scan_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_bi_scan_pdf', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_abu_dhabi_added_bi_scan_pdf', 'ZZ DEMO Dune Plumbing LLC', '2028-03-11'::date, 'ZZACC-0b8b1fd6-CN-5084431',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_ar_png');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_ar_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Air Est', 'qd-0b8b1fd6-acc39@example.invalid', '+971500000067', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_ar_png.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_ar_png', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_ajman_ded_ar_png', null, '2027-04-12'::date, 'ZZACC-0b8b1fd6-20840',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_ar_jpg');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_ar_jpg');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Floor LLC', 'qd-0b8b1fd6-acc40@example.invalid', '+971500000068', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_ar_jpg.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_ar_jpg', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_fujairah_ded_ar_jpg', null, '2027-05-13'::date, 'ZZACC-0b8b1fd6-44633',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Carpentry DMCC', 'qd-0b8b1fd6-acc41@example.invalid', '+971500000069', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_dmcc_multipage.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_dmcc_multipage', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_dmcc_multipage', 'ZZ DEMO Saker Carpentry DMCC', '2029-06-14'::date, 'ZZACC-0b8b1fd6-DMCC-352294',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_multipage');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_multipage');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Painting FZE', 'qd-0b8b1fd6-acc42@example.invalid', '+971500000070', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_jafza_multipage.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_jafza_multipage', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_jafza_multipage', 'ZZ DEMO Marina Painting FZE', '2027-07-15'::date, 'ZZACC-0b8b1fd6-183654',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_expired_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_expired_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Building LLC', 'qd-0b8b1fd6-acc43@example.invalid', '+971500000071', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_expired_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_expired_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_expired_text', 'ZZ DEMO Crescent Building LLC', '2025-06-30'::date, 'ZZACC-0b8b1fd6-1348436',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','waterproofing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','waterproofing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'lic_expired_text', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_expired_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_expired_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Landscaping LLC', 'qd-0b8b1fd6-acc44@example.invalid', '+971500000072', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_expired_scan.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_expired_scan', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_expired_scan', 'ZZ DEMO Ghaf Landscaping LLC', '2026-02-10'::date, 'ZZACC-0b8b1fd6-727585',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Sahara Technical Services LLC', 'qd-0b8b1fd6-acc45@example.invalid', '+971500000073', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-0b8b1fd6-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text_approved_swap');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text_approved_swap');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values ('approved', true, 'ZZ DEMO Oasis Swap Trading LLC', 'qd-0b8b1fd6-acc46@example.invalid', '+971500000074', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text_approved_swap.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text_approved_swap', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_text_approved_swap', 'ZZ DEMO Mirage Contracting LLC', '2027-01-18'::date, 'ZZACC-0b8b1fd6-864274',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_scan');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_scan');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Zenith Maintenance FZ LLC', 'qd-0b8b1fd6-acc47@example.invalid', '+971500000075', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_mismatch_scan.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_mismatch_scan', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_mismatch_scan', 'ZZ DEMO Atlas Building Works FZ LLC', '2027-02-19'::date, 'ZZACC-0b8b1fd6-5362699',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_blank_pdf');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_blank_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Page LLC', 'qd-0b8b1fd6-acc48@example.invalid', '+971500000076', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_blank_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_blank_pdf', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_blank_pdf', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/lic_blank_photo');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_blank_photo');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Blank Photo LLC', 'qd-0b8b1fd6-acc49@example.invalid', '+971500000077', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_blank_photo.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/lic_blank_photo', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_blank_photo', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_blank_photo', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/lic_missing');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO No Licence LLC', 'qd-0b8b1fd6-acc50@example.invalid', '+971500000078', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/lic_missing.pdf',
          null, 'profiles/zzdemo-accuracy-0b8b1fd6/lic_missing', null, null, null,
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  
  res := res || jsonb_build_object('id', 'lic_missing', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Oasis Projects LLC', 'qd-0b8b1fd6-acc51@example.invalid', '+971500000079', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_pdf-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pdf', 'ZZ DEMO Oasis Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-51',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','glazing']::text[])), '{}'::jsonb),
      '{}', '{"overall":0.9}', '{}', '{}', 90, 'confirmed', now(), now(), array['Dubai']);
  res := res || jsonb_build_object('id', 'profile_pdf', 'lead', lid, 'gate', v,
           'status', (select approval_status from public.leads where id = lid), 'reason', (select licence_gate_reason from public.leads where id = lid),
           'company_name', (select company_name from public.leads where id = lid));
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_docx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_docx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Horizon Projects LLC', 'qd-0b8b1fd6-acc52@example.invalid', '+971500000080', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_docx.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_docx-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_docx', 'ZZ DEMO Horizon Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-52',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_pptx-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pptx');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Saker Projects LLC', 'qd-0b8b1fd6-acc53@example.invalid', '+971500000081', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_pptx.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_pptx-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pptx', 'ZZ DEMO Saker Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-53',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_png-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_png');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Marina Projects LLC', 'qd-0b8b1fd6-acc54@example.invalid', '+971500000082', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_png.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_png-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_png', 'ZZ DEMO Marina Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-54',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_pdf_paint-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pdf_paint');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Crescent Projects LLC', 'qd-0b8b1fd6-acc55@example.invalid', '+971500000083', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_pdf_paint.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_pdf_paint-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_pdf_paint', 'ZZ DEMO Crescent Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-55',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/profile_docx_land-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_docx_land');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Ghaf Projects LLC', 'qd-0b8b1fd6-acc56@example.invalid', '+971500000084', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/profile_docx_land.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/profile_docx_land-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/profile_docx_land', 'ZZ DEMO Ghaf Projects LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-56',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
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
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/zzdemo-accuracy-0b8b1fd6/catalogue_pdf-licence');
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'profiles/zzdemo-accuracy-0b8b1fd6/catalogue_pdf');
  insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at, signed_terms_path,
                            license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no, emirate, city, source, tags)
  values (null, false, 'ZZ DEMO Reem Building Supplies LLC', 'qd-0b8b1fd6-acc57@example.invalid', '+971500000085', true, true, now(), 'terms/zzdemo-accuracy-0b8b1fd6/catalogue_pdf.pdf',
          'licenses/zzdemo-accuracy-0b8b1fd6/catalogue_pdf-licence', 'profiles/zzdemo-accuracy-0b8b1fd6/catalogue_pdf', 'ZZ DEMO Reem Building Supplies LLC', '2028-12-31'::date, 'ZZACC-0b8b1fd6-ZZACC-57',
          'Dubai', 'Dubai', 'document_intake_accuracy', array['qd_demo', 'qd_run:0b8b1fd6']::text[])
  returning id into lid;
  ids := ids || lid;
  v := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  insert into public.supplier_capabilities (supplier_id, trades, roles, products_norm, project_types, brands, exclusions, authority_approvals,
      source_docs, confidence, missing_fields, excluded_trades, completeness, review_status, confirmed_at, extracted_at, coverage_emirates)
    values (lid, array['aluminium','glazing']::text[], array['contractor','installer','supplier']::text[], '{}', '{}', '{}', '{}',
      coalesce((select jsonb_object_agg(a, jsonb_build_object('ref', 'ZZ-DEMO', 'valid_until', '2028-12-31'))
                  from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = any(array['aluminium','glazing']::text[])), '{}'::jsonb),
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
  mt := mt || jsonb_build_object('painting', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['painting'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('plumbing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['plumbing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('tax_advisory', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['tax_advisory'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  mt := mt || jsonb_build_object('waterproofing', (select coalesce(jsonb_agg(x.supplier_id order by x.supplier_id), '[]') from public.fn_match_capability(array['waterproofing'], 'executes', p_limit => 100000) x where x.supplier_id = any(ids)));
  raise exception 'CHK<<%>>', jsonb_build_object('gate', res, 'match', mt)::text;
end $probe$;
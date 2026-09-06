// The five remaining branches, spliced in place of the PD-QUOTE-005 values list at the tail of the
// runner. Kept in their own file so the anchors above stay readable.
module.exports = `
// ------------------------------------------------------------------ the five real branches
swap(
\`  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------
  for v_key, v_msg in
    select * from (values
      ('PD-QUOTE-005','QUOTE: needs normalization to attempt an overwrite of an original supplier value; the normalization path is not built.'),\`,
\`  -- ---- THE FIVE THAT NEEDED A CONTRACT, AND NOW HAVE ONE ---------------------------------------
  -- Each of these was NOT_RUN because the control it names did not exist in this estate. O03-O07
  -- built them. Every branch below drives an injection AND its control, and the control is the half
  -- that makes the refusal mean something: a predicate that refuses both arms is indistinguishable
  -- from a dead path.

  -- PD-LEGAL-004. Four ways a source fails and one way it does not, over committed reference rows
  -- in public.phase_d_legal_source that this branch does not create -- a probe that writes its own
  -- stale source and then asks whether a stale source is refused has answered its own question.
  declare v_g4 text[]; v_g4_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-expired')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-undated-circular')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-blog-vat-opinion')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-2024')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_legal_source_current('zz-demo-fta-corporate-tax-current')),'USABLE'),
      coalesce((select refusal_code from public.fn_phase_d_gate_evaluate('GATE-027', jsonb_build_object(
        'reconciliation_ref','zz','control_exception_ref','zz','tax_source_ref','zz-demo-fta-corporate-tax-expired'))),'PASSED')
    ] into v_g4;
    v_g4_ok := v_g4[1]='pd_legal_source_stale' and v_g4[2]='pd_legal_source_missing'
           and v_g4[3]='pd_legal_source_not_authoritative' and v_g4[4]='pd_legal_source_superseded'
           and v_g4[5]='USABLE' and v_g4[6]='pd_legal_source_stale';
    -- and the HARD boundary: an assertion citing the stale source is refused outright
    begin
      insert into public.phase_d_legal_assertion
        (subject, jurisdiction, position_summary, source_id, asserted_by_role_id)
      values ('pd-legal-004','AE','probe','zz-demo-fta-corporate-tax-expired','general_counsel');
      v_g4 := v_g4 || 'ASSERTION_ACCEPTED';
    exception when others then
      v_g4 := v_g4 || case when position('pd_legal_source_stale' in SQLERRM) > 0
                           then 'pd_legal_source_stale' else 'other:'||SQLSTATE end;
    end;
    v_g4_ok := v_g4_ok and v_g4[7] = 'pd_legal_source_stale';
    defect_id:='PD-LEGAL-004'; category:='LEGAL';
    status := case when v_g4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('freshness predicate stale/undated/non-authoritative/superseded/current -> %s; GATE-027 on the stale source -> %s; assertion citing it -> %s',
                       array_to_string(v_g4[1:5],','), v_g4[6], v_g4[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-002. A revision whose redaction is unapproved, one rejected, one superseded, and the
  -- approved clean one, all through BR-012 and GATE-013 -- the two predicates that returned the
  -- IDENTICAL ENFORCED_PASS to the injection and the control before O07.
  declare v_p2 text[]; v_p2_ok boolean;
  begin
    select array[
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-rejected')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-superseded')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-safe', repeat('f',64))),'DISPATCHABLE'),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002','safe_package_approved_by','compliance_and_privacy_officer',
        'actor_role_id','marketplace_content_privacy_reviewer'))),
      (select state from public.fn_phase_d_gate_evaluate('GATE-013', jsonb_build_object(
        'safe_package_ref','zz-demo-pkg-priv-002-clean','safe_package_approved_by','compliance_and_privacy_officer',
        'actor_role_id','marketplace_content_privacy_reviewer')))
    ] into v_p2;
    v_p2_ok := v_p2[1]='pd_revision_redaction_unapproved' and v_p2[2]='pd_revision_redaction_rejected'
           and v_p2[3]='pd_revision_superseded' and v_p2[4]='DISPATCHABLE'
           and v_p2[5]='pd_revision_digest_mismatch' and v_p2[6]='BLOCKED' and v_p2[7]='PASSED';
    defect_id:='PD-PRIV-002'; category:='PRIVACY';
    status := case when v_p2_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('revision pending/rejected/superseded/approved/wrong-digest -> %s; GATE-013 on the unapproved package -> %s, on the approved one -> %s',
                       array_to_string(v_p2[1:5],','), v_p2[6], v_p2[7]);
    blocker := null; return next;
  end;

  -- PD-PRIV-005. The hidden-metadata verdict recorded by scripts/phase_d/run_metadata_scan_probe.mjs
  -- over the committed fixture bytes, and the two fail-closed arms. The scan is a MEASUREMENT taken
  -- outside the database because Postgres never receives file bytes; this branch reads what it
  -- recorded and refuses to score a revision whose scan is absent.
  declare v_p5 text[]; v_p5_ok boolean; v_p5_n bigint;
  begin
    select count(*) into v_p5_n from public.phase_d_metadata_scan;
    select array[
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-unredacted' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select outcome from public.phase_d_metadata_scan
                 where revision_ref='zz-demo-rev-photo-safe' order by scan_id desc limit 1),'NO_SCAN'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-unredacted')),'DISPATCHABLE'),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-photo-safe')),'DISPATCHABLE'),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-unredacted'))),
      (select state from public.fn_phase_d_rule_check('BR-011', jsonb_build_object(
        'supplier_payload','scope only','file_revision_ref','zz-demo-rev-photo-safe'))),
      coalesce((select refusal_code from public.fn_phase_d_file_revision_dispatchable('zz-demo-rev-drawing-unredacted')),'DISPATCHABLE')
    ] into v_p5;
    v_p5_ok := v_p5[1]='IDENTIFIERS_FOUND' and v_p5[2]='CLEAN'
           and v_p5[3]='pd_hidden_metadata_identifier_found' and v_p5[4]='DISPATCHABLE'
           and v_p5[5]='ENFORCED_FAIL' and v_p5[6]='ENFORCED_PASS' and v_p5_n >= 4;
    defect_id:='PD-PRIV-005'; category:='PRIVACY';
    status := case when v_p5_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('recorded scans %s; dirty bytes -> %s, cleared bytes -> %s; dispatch %s / %s; BR-011 %s / %s',
                       v_p5_n, v_p5[1], v_p5[2], v_p5[3], v_p5[4], v_p5[5], v_p5[6]);
    blocker := null; return next;
  end;

  -- PD-QUOTE-001. Supplier B naming supplier A's key, through the canonical write service, and
  -- supplier A rewriting their own key in the same shape. The object is SUPPLIER-scoped and goes
  -- through the same routine and the same owner_ref handling as a quotation; nothing here writes
  -- public.quotes, so no marketplace trigger fires.
  declare v_q1_a text; v_q1_b text; v_q1_msg text := ''; v_q1_ok boolean := false;
         v_q1_I text; v_q1_C text; v_q1_n bigint;
  begin
    begin
      select id::text into v_q1_a from public.leads order by id limit 1;
      select id::text into v_q1_b from public.leads order by id offset 1 limit 1;
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
        'created_by','pd_quote_001','state','open','payload',jsonb_build_object('n',1)));
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_b,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',2)));
        v_q1_I := 'ACCEPTED';
      exception when others then
        v_q1_I := case when position('pd_object_cross_owner_write' in SQLERRM) > 0
                       then 'pd_object_cross_owner_write' else 'other:'||SQLSTATE end;
      end;
      begin
        perform public.fn_phase_d_object_write(jsonb_build_object(
          'object_id','supplier_correction_case','business_key','pd-quote-001','owner_ref',v_q1_a,
          'created_by','pd_quote_001','state','in_progress','payload',jsonb_build_object('n',3)));
        v_q1_C := 'ACCEPTED';
      exception when others then v_q1_C := 'REFUSED '||SQLSTATE; end;
      select count(*) into v_q1_n from public.phase_d_object_record
       where object_id='supplier_correction_case' and business_key='pd-quote-001'
         and owner_ref = v_q1_b;
      raise exception '%', 'PDQ1' || chr(31) || v_q1_I ||'|'|| v_q1_C ||'|'|| v_q1_n;
    exception when others then
      if position('PDQ1' in SQLERRM) = 1 then v_q1_msg := split_part(SQLERRM, chr(31), 2);
      else v_q1_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q1_ok := split_part(v_q1_msg,'|',1)='pd_object_cross_owner_write'
           and split_part(v_q1_msg,'|',2)='ACCEPTED'
           and split_part(v_q1_msg,'|',3)='0';
    defect_id:='PD-QUOTE-001'; category:='QUOTE';
    status := case when v_q1_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('supplier B writing supplier A''''s key -> %s; supplier A rewriting their own -> %s; rows left owned by B: %s',
                       split_part(v_q1_msg,'|',1), split_part(v_q1_msg,'|',2), split_part(v_q1_msg,'|',3));
    blocker := null; return next;
  end;

  -- PD-QUOTE-004. One customer, two comparisons differing in EXACTLY ONE respect -- the publication
  -- state -- read as the owner, as an unrelated customer, and as admin.
  declare v_q4_msg text := ''; v_q4_ok boolean := false; v_q4_cust uuid; v_q4_d uuid; v_q4_p uuid;
         v_q4_a1 text; v_q4_a2 text; v_q4_a3 text; v_q4_a4 text; v_q4_n bigint;
  begin
    begin
      v_q4_cust := '00000000-0000-4000-8000-0000000c0004'::uuid;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-draft', '{}'::jsonb, 'DRAFT')
      returning id into v_q4_d;
      insert into public.quote_comparisons(inquiry_id, customer_id, lang, quote_count, signature, analysis, publication_state, published_at)
      values (gen_random_uuid(), v_q4_cust, 'en', 2, 'PD-QUOTE-004-published', '{}'::jsonb, 'PUBLISHED', now())
      returning id into v_q4_p;
      select coalesce(refusal_code,'VISIBLE') into v_q4_a1 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a2 from public.fn_phase_d_comparison_visible(v_q4_p::text, v_q4_cust::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a3 from public.fn_phase_d_comparison_visible(v_q4_p::text, gen_random_uuid()::text, 'customer');
      select coalesce(refusal_code,'VISIBLE') into v_q4_a4 from public.fn_phase_d_comparison_visible(v_q4_d::text, v_q4_cust::text, 'admin');
      select count(*) into v_q4_n from public.fn_phase_d_rule_check('BR-019', jsonb_build_object(
        'comparison_id', v_q4_d::text, 'caller_customer_id', v_q4_cust::text)) rc where rc.ok;
      raise exception '%', 'PDQ4' || chr(31) || v_q4_a1 ||'|'|| v_q4_a2 ||'|'|| v_q4_a3 ||'|'|| v_q4_a4 ||'|'|| v_q4_n;
    exception when others then
      if position('PDQ4' in SQLERRM) = 1 then v_q4_msg := split_part(SQLERRM, chr(31), 2);
      else v_q4_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q4_ok := split_part(v_q4_msg,'|',1)='pd_comparison_unpublished'
           and split_part(v_q4_msg,'|',2)='VISIBLE'
           and split_part(v_q4_msg,'|',3)='pd_comparison_not_the_owner'
           and split_part(v_q4_msg,'|',4)='VISIBLE'
           and split_part(v_q4_msg,'|',5)='0';
    defect_id:='PD-QUOTE-004'; category:='QUOTE';
    status := case when v_q4_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
    observed := format('owner reading their own unpublished -> %s, published -> %s; unrelated customer on the published one -> %s; admin on the draft -> %s; BR-019 passes on the draft: %s',
                       split_part(v_q4_msg,'|',1), split_part(v_q4_msg,'|',2), split_part(v_q4_msg,'|',3),
                       split_part(v_q4_msg,'|',4), split_part(v_q4_msg,'|',5));
    blocker := null; return next;
  end;

  -- PD-QUOTE-005. A supplier revision, a normalisation beside it, a replay, and an attempt to
  -- overwrite the original -- all through the object store, none of it touching public.quotes.
  declare v_q5_msg text := ''; v_q5_ok boolean := false; v_q5_rec bigint; v_q5_sha text;
         v_q5_N text; v_q5_R text; v_q5_O text; v_q5_I text; v_q5_B text; v_q5_n1 bigint; v_q5_n2 bigint;
  begin
    begin
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','quotation_revision','business_key','pd-quote-005','owner_ref','ZZ DEMO SUPPLIER',
        'created_by','pd_quote_005','state','submitted',
        'payload', jsonb_build_object('lead_time','30 days','payment_terms','50/50','scope','as tendered')));
      select o.record_id, encode(extensions.digest(convert_to(o.payload::text,'UTF8'),'sha256'),'hex')
        into v_q5_rec, v_q5_sha
        from public.phase_d_object_record o
       where o.object_id='quotation_revision' and o.business_key='pd-quote-005' and o.superseded_by is null
       order by o.record_id desc limit 1;

      -- the derived projection, referencing the original and restating none of it
      insert into public.phase_d_quote_normalisation
        (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
         transformation, actor_role_id)
      values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
              jsonb_build_object('normalised_lead_time_days', 30),
              jsonb_build_object('source_fields', jsonb_build_array('lead_time'),
                                 'rule','"30 days" -> 30'), 'quote_evaluation');
      v_q5_N := 'ACCEPTED';
      select count(*) into v_q5_n1 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- replay: identical source, identical schema version -> no second row
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v1',
                jsonb_build_object('normalised_lead_time_days', 30),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'quote_evaluation');
        v_q5_R := 'DUPLICATED';
      exception when unique_violation then v_q5_R := 'IDEMPOTENT_NO_DUPLICATE';
                when others then v_q5_R := 'other:'||SQLSTATE; end;
      select count(*) into v_q5_n2 from public.phase_d_quote_normalisation where source_revision_ref='pd-quote-005';

      -- a projection that restates a supplier-authored field is not a projection
      begin
        insert into public.phase_d_quote_normalisation
          (source_quote_ref, source_revision_ref, source_payload_sha256, schema_version, normalised,
           transformation, actor_role_id)
        values ('pd-quote-005','pd-quote-005', v_q5_sha, 'v2',
                jsonb_build_object('lead_time','7 days'),
                jsonb_build_object('source_fields', jsonb_build_array('lead_time')), 'quote_evaluation');
        v_q5_B := 'ACCEPTED';
      exception when others then
        v_q5_B := case when position('pd_normalisation_restates_original' in SQLERRM) > 0
                       then 'pd_normalisation_restates_original' else 'other:'||SQLSTATE end;
      end;

      -- the direct overwrite of the original
      perform set_config('kernel.maintenance_reason','PD-QUOTE-005: attempt the original overwrite', true);
      begin
        update public.phase_d_object_record set payload = jsonb_build_object('lead_time','7 days')
         where record_id = v_q5_rec;
        v_q5_O := 'ACCEPTED';
      exception when others then
        v_q5_O := case when position('pd_object_overwrite_refused' in SQLERRM) > 0
                       then 'pd_object_overwrite_refused' else 'other:'||SQLSTATE end;
      end;
      perform set_config('kernel.maintenance_reason','', true);

      select case when qi.intact then 'INTACT' else coalesce(qi.refusal_code,'NOT_INTACT') end into v_q5_I
        from public.fn_phase_d_quote_original_intact('pd-quote-005') qi;
      raise exception '%', 'PDQ5' || chr(31) || v_q5_N ||'|'|| v_q5_R ||'|'|| v_q5_B ||'|'|| v_q5_O ||'|'|| v_q5_I ||'|'|| v_q5_n1||'/'||v_q5_n2;
    exception when others then
      if position('PDQ5' in SQLERRM) = 1 then v_q5_msg := split_part(SQLERRM, chr(31), 2);
      else v_q5_msg := 'BRANCH_ERROR '||left(SQLERRM,110); end if;
    end;
    v_q5_ok := split_part(v_q5_msg,'|',1)='ACCEPTED'
           and split_part(v_q5_msg,'|',2)='IDEMPOTENT_NO_DUPLICATE'
           and split_part(v_q5_msg,'|',3)='pd_normalisation_restates_original'
           and split_part(v_q5_msg,'|',4)='pd_object_overwrite_refused'
           and split_part(v_q5_msg,'|',5)='INTACT'
           and split_part(split_part(v_q5_msg,'|',6),'/',1)=split_part(split_part(v_q5_msg,'|',6),'/',2);
    defect_id:='PD-QUOTE-005'; category:='QUOTE';
    status := case when v_q5_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
    observed := format('normalisation -> %s; replay -> %s (rows %s); restating an original field -> %s; direct overwrite -> %s; original %s',
                       split_part(v_q5_msg,'|',1), split_part(v_q5_msg,'|',2), split_part(v_q5_msg,'|',6),
                       split_part(v_q5_msg,'|',3), split_part(v_q5_msg,'|',4), split_part(v_q5_msg,'|',5));
    blocker := null; return next;
  end;

  -- ---- Remaining rows whose subject exists but whose injection needs a committed run ------------
  for v_key, v_msg in
    select * from (values\`,
  'the five branches');
`;

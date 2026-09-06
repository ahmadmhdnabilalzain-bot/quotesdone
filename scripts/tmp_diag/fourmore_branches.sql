
  -- ---- THE FOUR THAT NEEDED A FIXTURE, NOT A COMMITTED ROW -------------------------------------
  -- public.inquiries, public.quotes and public.phase_d_object_record hold ZERO rows OUTSIDE a
  -- fixture. Inside one they do not. fn_phase_d_fixture_scenario builds the customer, the inquiry,
  -- the supplier account and the terms acceptance IN THIS TRANSACTION, and every refusal below is
  -- an immediate BEFORE-trigger, CHECK or writer refusal -- none is deferred to commit. The four
  -- blockers these branches replace each said the injection needed a COMMITTED row. It did not; it
  -- needed a fixture, and this function already runs inside a verified fixture context.
  -- MEASURED, NOT ASSUMED: the deliverable driver opens the context and builds NO scenario, so the
  -- scenario is built here rather than presumed to be standing.
  v_pay := public.fn_phase_d_fixture_scenario(jsonb_build_object(
             'label','zz-defect-four','execution_context','test'));
  v_sup := v_pay->'parent_refs'->>'inquiry_id';

  -- PD-DISP-001 an inquiry that is not quote-ready, presented to the dispatch path.
  -- TWO IMPLEMENTATIONS AND THEY DO NOT READ THE SAME COLUMN. fn_phase_d_gate_evaluate('GATE-011')
  -- and fn_phase_d_rule_check('BR-013') read public.inquiries.status; trigger gate_incomplete_match
  -- BEFORE INSERT ON public.inquiry_matches reads i.rfq_ready and returns null. Both are measured.
  -- rfq_ready is DERIVED -- trg_rfq_complete recomputes it from fn_rfq_score on every write -- so
  -- setting that column false is not an injection at all. The injection is an RFQ that is genuinely
  -- incomplete; the scorer then makes both columns unready, which is why one arm can move both.
  v_a := (select to_jsonb(i) from public.inquiries i where i.id::text = v_sup);
  -- RESOLVE, THEN CREATE. uq_leads_email_lower is a unique index on lower(email), so a second call
  -- to this function inside one transaction would collide on it. Every demo supplier below is
  -- looked up first and written only when it is not already standing.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp001@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp001-sup','owner_ref','zz-disp001-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp001 supplier',
        'email','zz-disp001@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp001@example.invalid';
  update public.inquiries set spec=null, summary=null, raw_input=null, boq=null, budget=null,
         trades=null, scope_type=null, status='new',
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  select (g.passed is not true) and g.refusal_code = 'gate011_inquiry_not_ready'
    into v_ok from public.fn_phase_d_gate_evaluate('GATE-011', jsonb_build_object('inquiry_id', v_sup)) g;
  select coalesce(v_ok,false) and (r.ok is not true) into v_ok
    from public.fn_phase_d_rule_check('BR-013', jsonb_build_object('inquiry_id', v_sup)) r;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 injection')));
    v_ok := false; v_msg := 'the dispatch write was NOT refused: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- THE VERDICT IS READ OUT OF THE RAISED MESSAGE, NOT OFF THE GUC. This exception block is a
    -- subtransaction, so the set_config the refusing trigger issued was rolled back with it and the
    -- key still holds PASS from the fixture's own earlier assignment. Reading it here measured the
    -- wrong subject and said PASS for a write that had just been refused.
    v_ok := coalesce(v_ok,false) and position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_NOT_RFQ_READY' in SQLERRM) > 0;
    v_msg := format('status=%s rfq_ready=%s: gate011_inquiry_not_ready + BR-013 BLOCKED, trigger %s, pd_object_write_produced_nothing, im %s->%s. ',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      v_n, (select count(*) from public.inquiry_matches));
  end;
  -- CONTROL. The SAME inquiry with its qualification content restored and the SAME supplier, so
  -- readiness is the only thing that differs between the two arms.
  update public.inquiries set spec = v_a->'spec', summary = v_a->>'summary',
         raw_input = v_a->>'raw_input', boq = v_a->'boq', budget = v_a->>'budget',
         scope_type = v_a->>'scope_type', status = v_a->>'status',
         trades = (select coalesce(array_agg(x),'{}')::text[]
                     from jsonb_array_elements_text(coalesce(v_a->'trades','[]'::jsonb)) x),
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object('dispatched_at', now(),
           'dispatched_by','phase_d_test_context','phase_d_outbound_suppressed', true)
   where id::text = v_sup;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp001-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp001 control')));
    v_ok := coalesce(v_ok,false) and (v_b->>'result_reference') is not null;
    v_msg := v_msg || format('CONTROL restored (%s/%s), same supplier: written, im %s->%s.',
      (select coalesce(i2.status,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      (select coalesce(i2.rfq_ready::text,'(null)') from public.inquiries i2 where i2.id::text=v_sup),
      v_n, (select count(*) from public.inquiry_matches));
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-001'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-DISP-002 a supplier that is pending, rejected or expired, presented to the assignment path.
  -- All four suppliers below are verified=true, so approval_status is the ONLY thing that differs
  -- between each injection and the control -- leads_approved_implies_verified would otherwise make
  -- the control differ in two columns at once.
  -- pending / rejected / expired are written into approval_status, which is the column both
  -- BR-015 and GATE-014 read and which carries no CHECK on its values. leads.registration_expires_at
  -- exists but no rule, no gate and no trigger on inquiry_matches reads it, so expiry has no other
  -- representation any of these three implementations would see.
  v_msg := ''; v_ok := true;
  for v_key in select unnest(array['pending','rejected','expired']) loop
    if not exists (select 1 from public.leads l
                    where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid') then
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_account','business_key','zz-disp002-'||v_key,
        'owner_ref','zz-disp002-'||v_key,'created_by','defect_probe','state', v_key,
        'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 '||v_key,
          'email','zz-disp002-'||v_key||'@example.invalid','verified', true)));
    end if;
    select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
     where lower(l.email) = 'zz-disp002-'||v_key||'@example.invalid';
    select coalesce(v_ok,false) and (r.ok is not true) into v_ok
      from public.fn_phase_d_rule_check('BR-015', v_a) r;
    select coalesce(v_ok,false) and (g.passed is not true)
       and g.refusal_code = 'gate014_supplier_unverified'
      into v_ok from public.fn_phase_d_gate_evaluate('GATE-014', v_a) g;
    -- AND WHAT THE WRITE PATH ITSELF DOES WITH THE SAME SUPPLIER. Undone in its own subtransaction
    -- so the measurement leaves nothing behind whichever way it comes out.
    begin
      v_b := public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','supplier_assignment','business_key','zz-disp002-a-'||v_key,
        'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
        'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
          'match_reason','ZZ DEMO - disp002 '||v_key)));
      v_msg := v_msg || v_key || '=W ';
      raise exception 'ZZ_UNDO';
    exception when others then
      if SQLERRM <> 'ZZ_UNDO' then v_msg := v_msg || v_key || '=refused '; end if;
    end;
  end loop;
  if not exists (select 1 from public.leads l
                  where lower(l.email) = 'zz-disp002-approved@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp002-approved',
      'owner_ref','zz-disp002-approved','created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp002 approved',
        'email','zz-disp002-approved@example.invalid','verified', true)));
  end if;
  select jsonb_build_object('supplier_id', l.id::text) into v_a from public.leads l
   where lower(l.email) = 'zz-disp002-approved@example.invalid';
  select coalesce(v_ok,false) and coalesce(r.ok,false) into v_ok
    from public.fn_phase_d_rule_check('BR-015', v_a) r;
  select count(*) into v_n from public.inquiry_matches;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp002-control',
      'owner_ref', v_a->>'supplier_id','created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp002 control')));
    v_msg := v_msg || format('| CTRL approved: written, im %s->%s',
      v_n, (select count(*) from public.inquiry_matches));
    raise exception 'ZZ_UNDO';
  exception when others then
    if SQLERRM <> 'ZZ_UNDO' then
      v_ok := false; v_msg := v_msg || '| CONTROL refused: ' || left(SQLERRM,60);
    end if;
  end;
  defect_id:='PD-DISP-002'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format('BR-015+GATE-014(gate014_supplier_unverified) refuse all 3 alike, none distinguished; the inquiry_matches BEFORE-INSERT guard never reads approval_status and WROTE all 3: %s', v_msg);
  blocker := null; return next;

  -- PD-DISP-004 a refused assignment counted as a notification.
  -- The refusal is a BEFORE-trigger return-null on public.inquiry_matches; the notification is
  -- written by the AFTER INSERT trigger notify_matched_supplier, which a BEFORE null never reaches.
  -- Both counts are taken around both arms and both are stated.
  if not exists (select 1 from public.leads l where lower(l.email) = 'zz-disp004@example.invalid') then
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_account','business_key','zz-disp004-sup','owner_ref','zz-disp004-sup',
      'created_by','defect_probe','state','approved',
      'payload', jsonb_build_object('company_name','ZZ DEMO - disp004 supplier',
        'email','zz-disp004@example.invalid','verified', true)));
  end if;
  select l.id::text into v_key from public.leads l where lower(l.email)='zz-disp004@example.invalid';
  update public.leads set matching_blocked = true,
         matching_block_reason = 'ZZ DEMO - PD-DISP-004 injection' where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-inject','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 injection')));
    v_ok := false; v_msg := 'the refused assignment was written: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    -- Same reason as PD-DISP-001: the GUC the trigger published was rolled back with this
    -- subtransaction, so the verdict is taken from the message the writer raised.
    v_ok := position('pd_object_write_produced_nothing' in SQLERRM) > 0
            and position('BLOCKED_INELIGIBLE_SUPPLIER' in SQLERRM) > 0
            and v_n = (select count(*) from public.inquiry_matches)
            and v_id = (select count(*) from public.notifications);
    v_msg := format('refused %s: im %s->%s, notifications %s->%s. ',
      split_part(coalesce(nullif(split_part(SQLERRM, 'Gate verdict: ', 2),''),'(no verdict)'), ' ', 1),
      v_n, (select count(*) from public.inquiry_matches),
      v_id, (select count(*) from public.notifications));
  end;
  -- CONTROL. The SAME supplier and the SAME inquiry; matching_blocked is the one thing that moves.
  update public.leads set matching_blocked = false, matching_block_reason = null
   where id::text = v_key;
  select count(*) into v_n from public.inquiry_matches;
  select count(*) into v_id from public.notifications;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','supplier_assignment','business_key','zz-disp004-control','owner_ref', v_key,
      'created_by','defect_probe',
      'payload', jsonb_build_object('inquiry_id', v_sup,'similarity',0.5,
        'match_reason','ZZ DEMO - disp004 control')));
    v_msg := v_msg || format('CONTROL same supplier+inquiry, unblocked: im %s->%s, notifications %s->%s.',
      v_n, (select count(*) from public.inquiry_matches),
      v_id, (select count(*) from public.notifications));
    v_ok := coalesce(v_ok,false)
            and (select count(*) from public.inquiry_matches) = v_n + 1
            and (select count(*) from public.notifications) = v_id + 1;
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL was refused too: ' || left(SQLERRM,80);
  end;
  defect_id:='PD-DISP-004'; category:='DISPATCH';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-LEGAL-002 an accepted terms version, rewritten. Two layers and both are immediate.
  select r.record_id, r.business_key, r.owner_ref into v_id, v_key, v_msg
    from public.phase_d_object_record r
   where r.object_id = 'customer_terms_acceptance' and r.superseded_by is null
   order by r.record_id desc limit 1;
  begin
    v_b := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','customer_terms_acceptance','business_key', v_key,'owner_ref', v_msg,
      'created_by','defect_probe','state','accepted',
      'payload', jsonb_build_object('stage','customer_terms_acceptance',
        'terms_version','v9-rewritten','accepted_by', v_msg)));
    v_ok := false; v_msg := 'the writer accepted a second version: ' || (v_b->>'result_reference') || ' ';
  exception when others then
    v_ok := position('pd_object_append_only' in SQLERRM) > 0;
    v_msg := 'writer pd_object_append_only; ';
  end;
  select count(*) into v_n from public.phase_d_object_record;
  begin
    update public.phase_d_object_record
       set payload = jsonb_set(payload, '{terms_version}', '"v9-rewritten"')
     where record_id = v_id;
    v_ok := false; v_msg := v_msg || 'the guard permitted a payload rewrite; ';
  exception when others then
    v_ok := coalesce(v_ok,false) and position('pd_object_overwrite_refused' in SQLERRM) > 0;
    v_msg := v_msg || 'guard pd_object_overwrite_refused; ';
  end;
  -- CONTROL. The SAME UPDATE on the SAME row, differing in exactly one respect: the column it moves
  -- is one the APPEND_ONLY family does not freeze. Read from the guard body -- identity, owner,
  -- payload, created_by and created_at are frozen, and for APPEND_ONLY the state too; the
  -- supersession columns are not, and that is the one change an append-only record still permits.
  begin
    update public.phase_d_object_record set superseded_at = now() where record_id = v_id;
    v_msg := v_msg || 'CONTROL same row, superseded_at (not frozen): ACCEPTED';
  exception when others then
    v_ok := false; v_msg := v_msg || 'CONTROL refused too: ' || left(SQLERRM,60);
  end;
  defect_id:='PD-LEGAL-002'; category:='LEGAL';
  status := case when coalesce(v_ok,false) then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || format('; records %s->%s, terms_version still %s', v_n,
    (select count(*) from public.phase_d_object_record),
    (select r2.payload->>'terms_version' from public.phase_d_object_record r2 where r2.record_id = v_id));
  blocker := null; return next;


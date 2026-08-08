-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802182259   name: p2_c1_stage_b6_holdout_runner
-- SHA-256 of the applied SQL: cba0bb644ec36baae1269575c21b019e12594404bb8f73a0d536d23e7425435b
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- Runs the frozen holdout in both languages and reports agreement, false positives, false
-- negatives and conflict detection. Refuses to run if the seal is broken.

create or replace function public.fn_p2c1_holdout_run()
returns table(case_key text, category text, en_active text, ar_active text,
              trade_set_agree boolean, disposition_agree boolean, component_agree boolean,
              clarify_agree boolean, conflict_ok boolean,
              en_false_pos text[], en_false_neg text[], ar_false_pos text[], ar_false_neg text[],
              verdict text)
language plpgsql security definer set search_path to 'public' as $fn$
declare c public.p2c1_holdout_case%rowtype; g bigint; L text; txt text;
        act jsonb := '{}'::jsonb; dsp jsonb := '{}'::jsonb; cmp jsonb := '{}'::jsonb;
        clr jsonb := '{}'::jsonb; cfl jsonb := '{}'::jsonb;
        a text[]; d text; m text; k boolean; x boolean; ed text; ec text; seal jsonb;
begin
  seal := public.fn_p2c1_holdout_verify_seal();
  if not coalesce((seal->>'intact')::boolean, false) then
    raise exception 'HOLDOUT SEAL BROKEN - refusing to report results: %', seal::text;
  end if;

  for c in select * from public.p2c1_holdout_case order by category, case_key loop
    act := '{}'::jsonb; dsp := '{}'::jsonb; cmp := '{}'::jsonb; clr := '{}'::jsonb; cfl := '{}'::jsonb;
    foreach L in array array['en','ar'] loop
      txt := case when L='ar' then c.text_ar else c.text_en end;
      insert into public.inquiry_workstream_group (inquiry_id) values (gen_random_uuid()) returning id into g;
      perform public.fn_inquiry_interpret(g, txt, null, null, 'holdout');

      select coalesce(array_agg(trade_key order by trade_key),'{}') into a
        from public.inquiry_workstream where group_id = g and active;
      select coalesce(string_agg(s.trade_key||'='||s.disposition,' ' order by s.trade_key),'')
        into d from public.v_trade_scope_status s where s.group_id=g and s.disposition <> 'included';
      select coalesce(string_agg(distinct e.scope_component||'='||e.disposition,' '),'')
        into m from public.v_scope_disposition_effective e
       where e.group_id=g and e.scope_component <> 'complete_trade_scope' and e.disposition <> 'included';
      select exists (select 1 from public.inquiry_trade_clarification
                      where group_id=g and answered_at is null) into k;
      select exists (select 1 from public.v_trade_scope_status s where s.group_id=g and s.is_conflict) into x;

      act := act || jsonb_build_object(L, to_jsonb(a));
      dsp := dsp || jsonb_build_object(L, d);
      cmp := cmp || jsonb_build_object(L, m);
      clr := clr || jsonb_build_object(L, k);
      cfl := cfl || jsonb_build_object(L, x);

      perform set_config('quotesdone.p2c1_teardown','approved',true);
      delete from public.inquiry_state_audit where group_id = g;
      delete from public.inquiry_workstream_group where id = g;
      perform set_config('quotesdone.p2c1_teardown','',true);
    end loop;

    select coalesce(string_agg(kk||'='||vv,' ' order by kk),'') into ed
      from jsonb_each_text(c.expect_dispositions) z(kk,vv);
    select coalesce(string_agg(kk||'='||vv,' ' order by kk),'') into ec
      from jsonb_each_text(c.expect_components) z(kk,vv);

    case_key := c.case_key; category := c.category;
    en_active := array_to_string(array(select jsonb_array_elements_text(act->'en')),',');
    ar_active := array_to_string(array(select jsonb_array_elements_text(act->'ar')),',');
    trade_set_agree   := (act->'en' = act->'ar');
    disposition_agree := (dsp->>'en' = dsp->>'ar');
    component_agree   := (cmp->>'en' = cmp->>'ar');
    clarify_agree     := (clr->>'en' = clr->>'ar');
    conflict_ok       := ((cfl->>'en')::boolean = c.expect_conflict
                          and (cfl->>'ar')::boolean = c.expect_conflict);

    en_false_pos := array(select jsonb_array_elements_text(act->'en') except select unnest(c.expect_active) order by 1);
    en_false_neg := array(select unnest(c.expect_active) except select jsonb_array_elements_text(act->'en') order by 1);
    ar_false_pos := array(select jsonb_array_elements_text(act->'ar') except select unnest(c.expect_active) order by 1);
    ar_false_neg := array(select unnest(c.expect_active) except select jsonb_array_elements_text(act->'ar') order by 1);

    verdict := case
      when trade_set_agree and disposition_agree and component_agree and clarify_agree and conflict_ok
           and cardinality(en_false_pos)=0 and cardinality(en_false_neg)=0
           and cardinality(ar_false_pos)=0 and cardinality(ar_false_neg)=0
           and dsp->>'en' = ed and cmp->>'en' = ec then 'PASS'
      when not trade_set_agree then 'PARITY_MISMATCH'
      when cardinality(en_false_pos)+cardinality(ar_false_pos) > 0 then 'FALSE_POSITIVE'
      when cardinality(en_false_neg)+cardinality(ar_false_neg) > 0 then 'FALSE_NEGATIVE'
      when not conflict_ok then 'CONFLICT_MISDETECTED'
      when dsp->>'en' <> ed then 'DISPOSITION_MISMATCH:got[' || (dsp->>'en') || ']want[' || ed || ']'
      when cmp->>'en' <> ec then 'COMPONENT_MISMATCH:got[' || (cmp->>'en') || ']want[' || ec || ']'
      else 'CLARIFY_MISMATCH' end;
    return next;
  end loop;
end $fn$;

revoke all on function public.fn_p2c1_holdout_run() from public, anon, authenticated;
;
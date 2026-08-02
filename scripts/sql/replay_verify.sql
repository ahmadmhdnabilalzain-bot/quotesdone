-- P2-C1 full replay verification (Stage A + B + B.5 + B.6).
--
-- Replay source: supabase_migrations.schema_migrations.statements.
-- Those bytes are SHA-256 identical to the recovered repository files
-- (proved by scripts/recover_stage_a_b_b5.mjs and scripts/recover_stage_b6.mjs
-- against the committed manifests), so replaying them replays the repository.
--
-- Method: inside ONE DO block (therefore one atomic statement),
--   1. snapshot a fingerprint of the ENTIRE public schema,
--   2. tear down every object these migrations create,
--   3. replay all migrations in production version order,
--   4. snapshot the fingerprint again,
--   5. report the symmetric difference,
--   6. RAISE EXCEPTION so the whole thing rolls back. Production is never mutated.
--
-- The report travels out in the exception message.

do $rep$
declare
  v_views  text[] := array[
    'v_group_completeness','v_group_dispatch','v_inquiry_trade_status',
    'v_inquiry_workstream_identity','v_scope_disposition_effective','v_trade_scope_status',
    'v_workstream_answer','v_workstream_brand_policy','v_workstream_completeness',
    'v_workstream_conflict','v_workstream_dispatch'];
  v_tables text[] := array[
    'brand_acceptance_policy_value','field_definition','field_definition_reference',
    'field_definition_source','field_definition_trade','field_question_variant',
    'inquiry_answer','inquiry_answer_conflict','inquiry_answer_conflict_value',
    'inquiry_answer_corroboration','inquiry_answer_document','inquiry_answer_scope',
    'inquiry_gate','inquiry_gate_required','inquiry_scope_disposition','inquiry_state_audit',
    'inquiry_trade_candidate','inquiry_trade_candidate_evidence','inquiry_trade_clarification',
    'inquiry_workstream','inquiry_workstream_group','inquiry_workstream_requirement',
    'mep_evidence_weight','mep_subcategory_review','mep_trade','mep_trade_pattern',
    'mep_trade_route','p2c1_disposition_case','p2c1_holdout_case',
    'p2c1_holdout_result_of_record','p2c1_holdout_seal','p2c1_lang_case','p2c1_scope_case',
    'scope_component','scope_disposition_kind','scope_marker','subcategory_trade_contribution'];
  v_funcs  text[] := array[
    'fn_answer_precedence_rank','fn_field_normalise','fn_field_value_allowed',
    'fn_gate_state_satisfies','fn_group_dispatch_report','fn_inquiry_answer_confirm',
    'fn_inquiry_answer_set','fn_inquiry_answer_supersede','fn_inquiry_interpret',
    'fn_inquiry_workstream_activate','fn_inquiry_workstream_deactivate','fn_mep_full_scope',
    'fn_norm_text','fn_p2c1_disposition_tests','fn_p2c1_fixture_satisfy',
    'fn_p2c1_holdout_checksum','fn_p2c1_holdout_run','fn_p2c1_holdout_verify_seal',
    'fn_p2c1_lang_parity_suite','fn_p2c1_no_active_trade_blocker','fn_p2c1_rollback_stage_b',
    'fn_p2c1_rollback_stage_b6',
    'fn_p2c1_run_lang_case','fn_p2c1_scope_rule_tests','fn_p2c1_stage_a_selftest',
    'fn_p2c1_stage_b_regression','fn_p2c1_stage_b_selftest','fn_scope_apply','fn_scope_clauses',
    'fn_scope_detect','fn_scope_inverse','fn_term_matches','fn_term_position',
    'fn_text_matches_pattern','fn_trade_confirm','fn_trade_identify','fn_trade_reject',
    'fn_trade_remove','trg_holdout_expectations_immutable','trg_holdout_record_immutable',
    'trg_inquiry_answer_value_domain','trg_inquiry_answer_value_immutable',
    'trg_inquiry_gate_state_sync','trg_mep_pattern_norm','trg_p2c1_append_only',
    'trg_scope_marker_norm'];
  v_types  text[] := array['answer_precedence','gate_state'];
  v_from   text := '20260802165328';
  v_to     text := '20260802184500';
  r        record;
  s        text;
  v_mig    int := 0;
  v_stmt   int := 0;
  v_expect int;
  v_pre    int;
  v_post   int;
  v_diff   text;
  v_dropped int := 0;
  v_left   int;
begin
  execute 'set statement_timeout = ''600s''';

  select count(*) into v_expect
    from supabase_migrations.schema_migrations
   where version >= v_from and version <= v_to;

  if v_expect <> 45 then
    raise exception 'MIGRATION COUNT MISMATCH: % applied in the window, manifests cover 45', v_expect;
  end if;

  ------------------------------------------------------------------ 1. pre
  create temp table fp_pre on commit drop as
  with rels as (
    select c.oid, c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r','v','m','p','f')
  )
  select 'R '||relname||' kind='||relkind::text||' rls='||relrowsecurity::text
         ||' force='||relforcerowsecurity::text as l from rels
  union all
  select 'C '||rl.relname||'.'||a.attname||' '||format_type(a.atttypid, a.atttypmod)
         ||' notnull='||a.attnotnull::text
         ||' default='||coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
         ||' ident='||a.attidentity::text||' gen='||a.attgenerated::text
    from rels rl
    join pg_attribute a on a.attrelid = rl.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  union all
  select 'K '||rl.relname||' '||con.conname||' '||pg_get_constraintdef(con.oid)
    from rels rl join pg_constraint con on con.conrelid = rl.oid
  union all
  select 'I '||i.tablename||' '||i.indexname||' '||i.indexdef
    from pg_indexes i where i.schemaname = 'public'
  union all
  select 'T '||rl.relname||' '||t.tgname||' '||pg_get_triggerdef(t.oid)
    from rels rl join pg_trigger t on t.tgrelid = rl.oid and not t.tgisinternal
  union all
  select 'W '||rl.relname||' '||md5(pg_get_viewdef(rl.oid))
    from rels rl where rl.relkind in ('v','m')
  union all
  select 'F '||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '||md5(p.prosrc)
         ||' secdef='||p.prosecdef::text||' vol='||p.provolatile::text
         ||' ret='||pg_get_function_result(p.oid)||' lang='||lg.lanname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language lg on lg.oid = p.prolang
   where n.nspname = 'public'
  union all
  select 'E '||t.typname||' '||e.enumsortorder::text||' '||e.enumlabel
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_enum e on e.enumtypid = t.oid
   where n.nspname = 'public'
  union all
  select 'G '||g.table_name||' '||g.grantee||' '||g.privilege_type
    from information_schema.role_table_grants g where g.table_schema = 'public';

  ------------------------------------------------------------------ 2. teardown
  foreach s in array v_views loop
    execute 'drop view if exists public.'||quote_ident(s)||' cascade';
    v_dropped := v_dropped + 1;
  end loop;

  foreach s in array v_tables loop
    execute 'drop table if exists public.'||quote_ident(s)||' cascade';
    v_dropped := v_dropped + 1;
  end loop;

  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any(v_funcs)
  loop
    execute 'drop function if exists '||r.sig||' cascade';
    v_dropped := v_dropped + 1;
  end loop;

  foreach s in array v_types loop
    execute 'drop type if exists public.'||quote_ident(s)||' cascade';
    v_dropped := v_dropped + 1;
  end loop;

  select count(*) into v_left
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','v','m','p','f')
     and (c.relname = any(v_tables) or c.relname = any(v_views));
  select count(*) + v_left into v_left
    from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
   where n.nspname = 'public' and pr.proname = any(v_funcs);
  select count(*) + v_left into v_left
    from pg_type ty join pg_namespace n on n.oid = ty.typnamespace
   where n.nspname = 'public' and ty.typname = any(v_types);
  if v_left <> 0 then
    raise exception 'TEARDOWN INCOMPLETE: % target objects still present; the replay would not be a real rebuild', v_left;
  end if;

  ------------------------------------------------------------------ 3. replay
  for r in
    select version, statements
      from supabase_migrations.schema_migrations
     where version >= v_from and version <= v_to
     order by version
  loop
    begin
      foreach s in array r.statements loop
        execute s;
        v_stmt := v_stmt + 1;
      end loop;
    exception when others then
      raise exception 'REPLAY FAILED at migration % (after % statements): % / %',
        r.version, v_stmt, sqlstate, sqlerrm;
    end;
    v_mig := v_mig + 1;
  end loop;

  ------------------------------------------------------------------ 4. post
  create temp table fp_post on commit drop as
  with rels as (
    select c.oid, c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r','v','m','p','f')
  )
  select 'R '||relname||' kind='||relkind::text||' rls='||relrowsecurity::text
         ||' force='||relforcerowsecurity::text as l from rels
  union all
  select 'C '||rl.relname||'.'||a.attname||' '||format_type(a.atttypid, a.atttypmod)
         ||' notnull='||a.attnotnull::text
         ||' default='||coalesce(pg_get_expr(d.adbin, d.adrelid), '-')
         ||' ident='||a.attidentity::text||' gen='||a.attgenerated::text
    from rels rl
    join pg_attribute a on a.attrelid = rl.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  union all
  select 'K '||rl.relname||' '||con.conname||' '||pg_get_constraintdef(con.oid)
    from rels rl join pg_constraint con on con.conrelid = rl.oid
  union all
  select 'I '||i.tablename||' '||i.indexname||' '||i.indexdef
    from pg_indexes i where i.schemaname = 'public'
  union all
  select 'T '||rl.relname||' '||t.tgname||' '||pg_get_triggerdef(t.oid)
    from rels rl join pg_trigger t on t.tgrelid = rl.oid and not t.tgisinternal
  union all
  select 'W '||rl.relname||' '||md5(pg_get_viewdef(rl.oid))
    from rels rl where rl.relkind in ('v','m')
  union all
  select 'F '||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '||md5(p.prosrc)
         ||' secdef='||p.prosecdef::text||' vol='||p.provolatile::text
         ||' ret='||pg_get_function_result(p.oid)||' lang='||lg.lanname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language lg on lg.oid = p.prolang
   where n.nspname = 'public'
  union all
  select 'E '||t.typname||' '||e.enumsortorder::text||' '||e.enumlabel
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_enum e on e.enumtypid = t.oid
   where n.nspname = 'public'
  union all
  select 'G '||g.table_name||' '||g.grantee||' '||g.privilege_type
    from information_schema.role_table_grants g where g.table_schema = 'public';

  ------------------------------------------------------------------ 5. diff
  select count(*) into v_pre  from fp_pre;
  select count(*) into v_post from fp_post;

  select coalesce(string_agg(x, E'\n' order by x), '(no differences)')
    into v_diff
    from (
      select '- '||l as x from (select l from fp_pre  except all select l from fp_post) a
      union all
      select '+ '||l as x from (select l from fp_post except all select l from fp_pre ) b
    ) z;

  raise exception E'REPLAY REPORT\nversion range: % .. %\nmigrations in range: %\nmigrations replayed: %\nstatements executed: %\nobjects torn down: %\nteardown residue before replay: 0 (asserted)\nfingerprint lines pre: %\nfingerprint lines post: %\nDIFF:\n%',
    v_from, v_to, v_expect, v_mig, v_stmt, v_dropped, v_pre, v_post, left(v_diff, 6000);
end
$rep$;

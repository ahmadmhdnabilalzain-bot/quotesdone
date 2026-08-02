-- P2-C1 STAGE B.6 - completing the operator rollback.
--
-- The previous fn_p2c1_rollback_stage_b6 removed 22 of the objects Stage B.6 creates and silently
-- said nothing about the rest. Four objects were unaccounted for. Each is now classified in the
-- open, and the report states what actually happened rather than implying a clean sweep.
--
-- CLASSIFICATION
--
-- p2c1_holdout_result_of_record  -> B. PERMANENT AUDIT EVIDENCE. It intentionally survives.
--   1. It is the once-only record of the first and only independent evaluation of holdout v1.
--      If rollback deleted it, a rollback-then-reapply cycle would allow a second "first
--      evaluation" to be written - defeating the holdout_record_immutable trigger, whose whole
--      purpose is that a holdout measures an implementation exactly once.
--   2. It has no operational role. No interpretation function, view, dispatch path or route reads
--      it. Removing it changes no behaviour; keeping it costs nothing.
--   3. It has no foreign keys in either direction, so surviving leaves no dangling reference.
--   4. Its creating migration is already survival-safe: create table if not exists, plus
--      insert ... on conflict do nothing. Re-applying B.6 over a surviving table is idempotent.
--
-- trg_holdout_record_immutable() and trigger holdout_record_immutable
--   -> B, and necessarily so. They are the protection on the row above. An audit record that can
--      be edited after the fact is not audit evidence, so they survive with the table they guard.
--
-- fn_p2c1_rollback_stage_b6  -> stage-owned, but retained deliberately: it is the instrument
--   performing the removal, and an operator must be able to re-run and re-read it afterwards.
--   Re-running it after a completed rollback returns stage_b6_not_present rather than acting.
--
-- fn_mep_full_scope  -> DECLARED EXCEPTION, and the one genuine judgement call here.
--   It is a Stage B.5 function that B.6 corrected (20260802182423): the B.5 adjacency rule said
--   "in the same clause" and the regex did not implement it, so a full-scope modifier could reach
--   an MEP anchor across a full stop and activate three trades. Restoring the B.5 text would
--   reintroduce a FALSE POSITIVE - wrong trade activation - which is the unsafe direction.
--   The rule applied here: prior-stage objects are restored to their prior-stage form, except
--   where the B.6 change was a defect fix to a prior-stage rule whose reversion is unsafe.
--   fn_term_matches is restored, because reverting it only loses English plural and Arabic
--   internal-article tolerance - a false NEGATIVE, which degrades to a clarification question
--   rather than to a wrong dispatch. Both decisions are now reported, not assumed.
--
-- The report additionally asserts what it previously only printed: Stage B.5's language parity and
-- scope negative suites must pass, and no fixture data may remain.

create or replace function public.fn_p2c1_rollback_stage_b6(
  p_mode text default 'rehearse', p_actor text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_removable_before int; v_removable_after int;
  v_a text; v_b text; v_lang text; v_scope text;
  v_report jsonb; v_survivors jsonb; v_restored jsonb; v_fixtures jsonb;
  v_tm_b5 boolean; v_gdr_b5 boolean; v_mfs_fixed boolean;
  v_orphan_groups int; v_orphan_answers int; v_orphan_audit int;
  v_missing text;
  c_tables text[] := array['inquiry_scope_disposition','scope_marker','scope_disposition_kind',
                           'scope_component','p2c1_disposition_case','p2c1_holdout_case','p2c1_holdout_seal'];
  c_views  text[] := array['v_scope_disposition_effective','v_trade_scope_status'];
  c_funcs  text[] := array['fn_p2c1_holdout_run','fn_p2c1_disposition_tests','fn_p2c1_holdout_verify_seal',
                           'fn_p2c1_holdout_checksum','fn_inquiry_interpret','fn_scope_apply','fn_scope_detect',
                           'fn_scope_inverse','fn_scope_clauses','fn_term_position',
                           'fn_p2c1_no_active_trade_blocker','trg_holdout_expectations_immutable',
                           'trg_scope_marker_norm'];
begin
  if p_mode not in ('rehearse','commit') then
    return jsonb_build_object('ok', false, 'error','mode must be rehearse or commit'); end if;
  if coalesce(btrim(p_actor),'') = '' then
    return jsonb_build_object('ok', false, 'error','actor_required'); end if;
  if to_regclass('public.inquiry_scope_disposition') is null then
    return jsonb_build_object('ok', false, 'error','stage_b6_not_present'); end if;

  select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and (c.relname = any(c_tables) or c.relname = any(c_views)))
       + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname = any(c_funcs))
    into v_removable_before;

  ---------------------------------------------------------------- remove
  drop view if exists public.v_trade_scope_status cascade;
  drop view if exists public.v_scope_disposition_effective cascade;
  drop function if exists public.fn_p2c1_holdout_run() cascade;
  drop function if exists public.fn_p2c1_disposition_tests() cascade;
  drop function if exists public.fn_p2c1_holdout_verify_seal() cascade;
  drop function if exists public.fn_p2c1_holdout_checksum() cascade;
  drop function if exists public.fn_inquiry_interpret(bigint,text,jsonb,jsonb,text) cascade;
  drop function if exists public.fn_scope_apply(bigint,text) cascade;
  drop function if exists public.fn_scope_detect(bigint,text,text) cascade;
  drop function if exists public.fn_scope_inverse(text) cascade;
  drop function if exists public.fn_scope_clauses(text) cascade;
  drop function if exists public.fn_term_position(text,text,text) cascade;
  drop function if exists public.fn_p2c1_no_active_trade_blocker(jsonb,jsonb) cascade;
  drop table if exists public.p2c1_disposition_case cascade;
  drop table if exists public.p2c1_holdout_seal cascade;
  drop trigger if exists holdout_expectations_immutable on public.p2c1_holdout_case;
  drop function if exists public.trg_holdout_expectations_immutable() cascade;
  drop table if exists public.p2c1_holdout_case cascade;
  drop trigger if exists scope_marker_norm on public.scope_marker;
  drop function if exists public.trg_scope_marker_norm() cascade;
  drop table if exists public.inquiry_scope_disposition cascade;
  drop table if exists public.scope_marker cascade;
  drop table if exists public.scope_disposition_kind cascade;
  drop table if exists public.scope_component cascade;
  delete from public.mep_trade_pattern where pattern in
    ('وحدات مناوله الهواء','فان كويل','شيلر');

  ---------------------------------------------------------------- restore prior stage
  execute $q1$
    create or replace function public.fn_term_matches(
      p_text_norm text, p_pattern_norm text, p_lang text default 'en')
    returns boolean language sql immutable as $i$
      select case when p_lang = 'ar'
        then p_text_norm ~ ('(^|[^[:alnum:]])(وال|بال|فال|كال|ال|لل|و|ف|ب|ك|ل)?'
                            || p_pattern_norm || '(ات|ين|ون|ها|هم|ه)?($|[^[:alnum:]])')
        else p_text_norm ~ ('(^|[^[:alnum:]])' || p_pattern_norm || '($|[^[:alnum:]])')
      end;
    $i$
  $q1$;

  execute $q2$
    create or replace function public.fn_group_dispatch_report(p_group_id bigint)
    returns jsonb language plpgsql stable security definer set search_path to 'public' as $i$
    declare v_gd public.v_group_dispatch%rowtype; v_blockers jsonb := '[]'::jsonb; r record;
    begin
      select * into v_gd from public.v_group_dispatch where group_id = p_group_id;
      if not found then return jsonb_build_object('ok', false, 'error','unknown_group'); end if;
      if v_gd.active_workstreams = 0 then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'blocker','no_active_workstream','severity','blocking',
          'detail','No trade has been confirmed for this inquiry, so there is nothing to dispatch.'));
      end if;
      if cardinality(v_gd.shared_missing_mandatory) > 0 then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'blocker','shared_mandatory_missing','severity','blocking',
          'fields', to_jsonb(v_gd.shared_missing_mandatory)));
      end if;
      for r in select * from public.v_workstream_dispatch
                where group_id = p_group_id and active and not dispatch_eligible loop
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'blocker','trade_not_eligible','severity','blocking','trade_key', r.trade_key,
          'missing_mandatory', to_jsonb(r.missing_mandatory), 'gate_states', r.gate_states));
      end loop;
      return jsonb_build_object('ok', true, 'group_id', p_group_id,
        'overall_dispatch_eligible', v_gd.overall_dispatch_eligible,
        'active_workstreams', v_gd.active_workstreams,
        'group_gate_states', v_gd.gate_states, 'blockers', v_blockers,
        'blocker_count', jsonb_array_length(v_blockers));
    end $i$
  $q2$;

  ---------------------------------------------------------------- verify: nothing removable left
  select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and (c.relname = any(c_tables) or c.relname = any(c_views)))
       + (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname = any(c_funcs))
    into v_removable_after;
  if v_removable_after <> 0 then
    raise exception 'ROLLBACK ABORTED: % removable Stage B.6 objects survived', v_removable_after; end if;

  ---------------------------------------------------------------- verify: survivors are all present
  v_missing := '';
  if to_regclass('public.p2c1_holdout_result_of_record') is null then
    v_missing := v_missing || 'p2c1_holdout_result_of_record '; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname='trg_holdout_record_immutable') then
    v_missing := v_missing || 'trg_holdout_record_immutable() '; end if;
  if not exists (select 1 from pg_trigger t where t.tgname='holdout_record_immutable' and not t.tgisinternal) then
    v_missing := v_missing || 'trigger holdout_record_immutable '; end if;
  if v_missing <> '' then
    raise exception 'ROLLBACK ABORTED: audit evidence that must survive is missing: %', v_missing; end if;

  v_survivors := jsonb_build_array(
    jsonb_build_object('object','p2c1_holdout_result_of_record','kind','table','class','B',
      'reason','permanent audit evidence: the once-only record of the first independent evaluation of holdout v1',
      'rows', (select count(*) from public.p2c1_holdout_result_of_record)),
    jsonb_build_object('object','trg_holdout_record_immutable()','kind','function','class','B',
      'reason','protects the row above; an editable audit record is not evidence'),
    jsonb_build_object('object','holdout_record_immutable','kind','trigger','class','B',
      'reason','protects the row above; an editable audit record is not evidence'),
    jsonb_build_object('object','fn_p2c1_rollback_stage_b6(text,text)','kind','function','class','instrument',
      'reason','the tool performing this rollback; returns stage_b6_not_present if re-run'));

  ---------------------------------------------------------------- verify: prior stage restored
  -- executed dynamically so the probe cannot be answered by a plan cached against the pre-restore body
  execute 'select public.fn_term_matches($1,$2,$3)' into v_tm_b5 using 'ahus','ahu','en';
  select p.prosrc not like '%scope%' into v_gdr_b5
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_group_dispatch_report';
  select p.prosrc like '%v_sep%' into v_mfs_fixed
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_mep_full_scope';

  if v_tm_b5 then
    raise exception 'ROLLBACK ABORTED: fn_term_matches still matches the English plural "ahus"; the B.5 form was not restored'; end if;
  if not coalesce(v_gdr_b5, false) then
    raise exception 'ROLLBACK ABORTED: fn_group_dispatch_report still mentions scope; the B.5 form was not restored'; end if;
  if not coalesce(v_mfs_fixed, false) then
    raise exception 'ROLLBACK ABORTED: fn_mep_full_scope is not the corrected form; see the declared exception'; end if;

  v_restored := jsonb_build_object(
    'fn_term_matches','Stage B.5 form verified: does not match the English plural "ahus"',
    'fn_group_dispatch_report','Stage B.5 form verified: no scope sections',
    'mep_trade_pattern','3 Stage B.6 Arabic HVAC patterns deleted');

  ---------------------------------------------------------------- verify: suites
  select count(*) filter (where passed)||'/'||count(*) into v_a from public.fn_p2c1_stage_a_selftest();
  select count(*) filter (where passed)||'/'||count(*) into v_b from public.fn_p2c1_stage_b_selftest();
  select count(*) filter (where verdict='PASS')||'/'||count(*) into v_lang from public.fn_p2c1_lang_parity_suite();
  select count(*) filter (where passed)||'/'||count(*) into v_scope from public.fn_p2c1_scope_rule_tests();
  if v_a <> '14/14' or v_b <> '14/14' then
    raise exception 'ROLLBACK ABORTED: Stage A %, Stage B % after rollback', v_a, v_b; end if;
  if v_lang <> '23/23' or v_scope <> '12/12' then
    raise exception 'ROLLBACK ABORTED: Stage B.5 language parity %, scope negatives % after rollback', v_lang, v_scope; end if;

  ---------------------------------------------------------------- verify: no fixture data remains
  select count(*) into v_orphan_groups
    from public.inquiry_workstream_group g
   where not exists (select 1 from public.inquiry_intake i where i.id::text = g.inquiry_id::text);
  select count(*) into v_orphan_answers
    from public.inquiry_answer a join public.inquiry_workstream_group g on g.id = a.group_id
   where not exists (select 1 from public.inquiry_intake i where i.id::text = g.inquiry_id::text);
  select count(*) into v_orphan_audit
    from public.inquiry_state_audit s join public.inquiry_workstream_group g on g.id = s.group_id
   where not exists (select 1 from public.inquiry_intake i where i.id::text = g.inquiry_id::text);
  if v_orphan_groups <> 0 or v_orphan_answers <> 0 or v_orphan_audit <> 0 then
    raise exception 'ROLLBACK ABORTED: fixture data remains - % groups, % answers, % audit rows with no real inquiry',
      v_orphan_groups, v_orphan_answers, v_orphan_audit; end if;
  v_fixtures := jsonb_build_object('orphan_groups', v_orphan_groups,
    'orphan_answers', v_orphan_answers, 'orphan_audit_rows', v_orphan_audit);

  ---------------------------------------------------------------- report
  v_report := jsonb_build_object(
    'ok', true, 'mode', p_mode, 'actor', p_actor,
    'removable_objects', jsonb_build_object('before', v_removable_before, 'after', v_removable_after,
       'all_removed', v_removable_after = 0,
       'inventory', jsonb_build_object('tables', to_jsonb(c_tables), 'views', to_jsonb(c_views),
                                       'functions', to_jsonb(c_funcs))),
    'intentional_survivors', v_survivors,
    'prior_stage_restored', v_restored,
    'declared_exceptions', jsonb_build_array(jsonb_build_object(
       'object','fn_mep_full_scope(text)','action','NOT restored to the Stage B.5 text',
       'reason','the B.6 change was a defect fix to a Stage B.5 rule. Reverting it reintroduces a false positive - a full-scope modifier reaching an MEP anchor across a clause boundary and activating three trades. Reversion is unsafe, so the corrected form is kept and declared.')),
    'tests', jsonb_build_object('stage_a', v_a, 'stage_b', v_b,
                                'lang_parity', v_lang, 'scope_negatives', v_scope),
    'fixtures_remaining', v_fixtures,
    'verdict', 'stage b6 removed; audit evidence retained; prior stage restored');

  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (null, 'p2c1_stage_b6_rollback_' || p_mode, v_report, p_actor);

  if p_mode = 'rehearse' then
    raise exception 'REHEARSAL COMPLETE (nothing committed): %', v_report::text; end if;
  return v_report;
end $fn$;

revoke all on function public.fn_p2c1_rollback_stage_b6(text, text) from public, anon, authenticated;

comment on function public.fn_p2c1_rollback_stage_b6(text, text) is
  'Operator rollback for P2-C1 Stage B.6. Removes 22 stage-owned objects, restores the Stage B.5 forms of fn_term_matches and fn_group_dispatch_report, and deliberately retains four objects it names in the report: the holdout v1 result of record and its immutability trigger (class B, permanent audit evidence), and itself. fn_mep_full_scope is a declared exception - the B.6 defect fix is kept because reverting it reintroduces a false positive. Aborts if any removable object survives, if the audit evidence is missing, if the restored functions are not in their B.5 form, if Stage A/B/B.5 suites do not pass, or if fixture data remains.'

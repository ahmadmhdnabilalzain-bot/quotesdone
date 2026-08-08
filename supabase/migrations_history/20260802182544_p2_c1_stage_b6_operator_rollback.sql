-- P2-C1 STAGE B.6 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802182544   name: p2_c1_stage_b6_operator_rollback
-- SHA-256 of the applied SQL: 57e61e516b9cb0a909e305dbdd49376b2240a91e8e6e4240dbbd4a468b65ae77
-- Recovered by scripts/recover_stage_b6.mjs. The body below is byte-for-byte as applied;
-- only this header was added, and it is excluded from the checksum.

-- P2-C1 STAGE B.6 - operator rollback for this stage. Same contract as the Stage B one:
-- one transaction, verify, run the suites that must survive, abort on any failure.
--   select public.fn_p2c1_rollback_stage_b6('rehearse','ops:you');
--   select public.fn_p2c1_rollback_stage_b6('commit','ops:you');
-- Roll back B.6 BEFORE fn_p2c1_rollback_stage_b: B.6 sits on top of B.5/B objects.

create or replace function public.fn_p2c1_rollback_stage_b6(
  p_mode text default 'rehearse', p_actor text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_before int; v_after int; v_a text; v_b text; v_lang text; v_scope text; v_report jsonb;
begin
  if p_mode not in ('rehearse','commit') then
    return jsonb_build_object('ok', false, 'error','mode must be rehearse or commit'); end if;
  if coalesce(btrim(p_actor),'') = '' then
    return jsonb_build_object('ok', false, 'error','actor_required'); end if;
  if to_regclass('public.inquiry_scope_disposition') is null then
    return jsonb_build_object('ok', false, 'error','stage_b6_not_present'); end if;

  select count(*) into v_before from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('inquiry_scope_disposition','scope_marker',
     'scope_disposition_kind','scope_component','p2c1_disposition_case','p2c1_holdout_case',
     'p2c1_holdout_seal','v_scope_disposition_effective','v_trade_scope_status');

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

  -- restore the Stage B.5 matcher (no English plural, no internal Arabic article)
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

  -- restore the Stage B.5 dispatch report (no scope sections)
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

  select count(*) into v_after from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('inquiry_scope_disposition','scope_marker',
     'scope_disposition_kind','scope_component','p2c1_disposition_case','p2c1_holdout_case',
     'p2c1_holdout_seal','v_scope_disposition_effective','v_trade_scope_status');
  if v_after <> 0 then raise exception 'ROLLBACK ABORTED: % B.6 objects survived', v_after; end if;

  select count(*) filter (where passed)||'/'||count(*) into v_a from public.fn_p2c1_stage_a_selftest();
  select count(*) filter (where passed)||'/'||count(*) into v_b from public.fn_p2c1_stage_b_selftest();
  select count(*) filter (where verdict='PASS')||'/'||count(*) into v_lang from public.fn_p2c1_lang_parity_suite();
  select count(*) filter (where passed)||'/'||count(*) into v_scope from public.fn_p2c1_scope_rule_tests();
  if v_a <> '14/14' or v_b <> '14/14' then
    raise exception 'ROLLBACK ABORTED: Stage A %, Stage B % after rollback', v_a, v_b; end if;

  v_report := jsonb_build_object('ok', true, 'mode', p_mode, 'actor', p_actor,
    'b6_objects', v_before || ' -> ' || v_after,
    'stage_a', v_a, 'stage_b', v_b, 'lang_parity', v_lang, 'scope_tests', v_scope);
  insert into public.inquiry_state_audit (group_id, event, detail, actor)
  values (null, 'p2c1_stage_b6_rollback_' || p_mode, v_report, p_actor);

  if p_mode = 'rehearse' then
    raise exception 'REHEARSAL COMPLETE (nothing committed): %', v_report::text; end if;
  return v_report;
end $fn$;

revoke all on function public.fn_p2c1_rollback_stage_b6(text, text) from public, anon, authenticated;
;
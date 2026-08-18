-- PHASE D · D7c — THE SECOND ATTEMPT AT ONE CHECK, AND WHY THE FIRST TWO BOTH FAILED THE SAME WAY.
--
-- effect_services_that_do_not_resolve was 257 of 257 in D7 and STILL 257 of 257 after D7b "fixed"
-- it. Two wrong answers to one question, and both were wrong for the same underlying reason: the
-- predicate was written from what the rendering was assumed to produce instead of from what it was
-- MEASURED to produce.
--
--   D7  compared against pg_get_function_identity_arguments — includes the parameter NAME:
--         public.fn_phase_d_effect_produce(p_input jsonb)
--   D7b compared against oid::regprocedure — omits the SCHEMA whenever it is on search_path, and
--       every routine here runs with `set search_path to 'public','pg_temp'`, so it rendered:
--         fn_phase_d_effect_produce(jsonb)
--
-- The contract stores public.fn_phase_d_effect_produce(jsonb). Neither rendering equals it, so a
-- check whose job is to catch a contract naming a routine nobody deployed reported that all 257
-- were broken while all 257 resolved. This is the same defect the phase exists to remove — a number
-- that is not measuring what its name says — committed twice inside the instrument itself.
--
-- MEASURED FIRST THIS TIME, before the file was written:
--
--   as_regproc                          built
--   fn_kernel_step_complete(jsonb)      public.fn_kernel_step_complete(jsonb)
--   fn_phase_d_effect_produce(jsonb)    public.fn_phase_d_effect_produce(jsonb)
--
-- The right-hand column is built from nspname, proname and format_type over proargtypes, which is
-- search_path-independent and carries no parameter names. That is what the check now compares.

begin;

create or replace function public.fn_phase_d_effect_state()
returns table(check_name text, expected text, actual text, ok boolean)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare n int; m int; v text;
begin
  select count(*) into m from public.phase_b_workflow_step;

  select count(*) into n from public.phase_d_step_effect;
  check_name := 'every_frozen_step_declares_an_effect';
  expected := m::text; actual := n::text; ok := (n = m); return next;

  select count(*) into n from public.phase_d_step_effect where expected_effect_type is null;
  check_name := 'steps_with_no_expected_effect_type';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect
   where expected_effect_type not in ('KERNEL_ONLY_TRANSITION','CAPABILITY_REQUEST')
     and effect_object_id is null;
  check_name := 'domain_effects_with_no_object';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- Built from the catalogue, not rendered by a cast whose output depends on search_path.
  select count(*) into n from public.phase_d_step_effect e
   where not exists (
     select 1 from pg_proc p join pg_namespace nn on nn.oid = p.pronamespace
      where nn.nspname = 'public'
        and nn.nspname || '.' || p.proname || '('
            || coalesce((select string_agg(format_type(t.o, null), ', ' order by t.ord)
                           from unnest(p.proargtypes) with ordinality t(o, ord)), '')
            || ')' = e.effect_service);
  check_name := 'effect_services_that_do_not_resolve';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect e
    join public.phase_d_business_object_binding ob on ob.object_id = e.effect_object_id
   where e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
     and ob.relation_kind = 'EXISTING_TABLE'
     and not exists (select 1 from public.phase_d_object_write_map w where w.object_id = ob.object_id);
  check_name := 'existing_table_effects_with_no_write_map';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n
    from public.phase_d_object_write_map w
    cross join lateral jsonb_object_keys(w.column_map) k
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = split_part(w.target_relation,'.',1)
                        and c.table_name   = split_part(w.target_relation,'.',2)
                        and c.column_name  = k);
  check_name := 'write_map_columns_absent_from_the_target';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_object_write_map w
    join public.phase_d_business_object_binding ob on ob.object_id = w.object_id
   where ob.governing_workflow_id = 'ALL' and ob.canonical_relation like 'public.phase_c_%';
  check_name := 'kernel_owned_objects_with_a_phase_d_writer';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_object_write_map
   where target_relation = 'public.notifications';
  check_name := 'phase_d_write_maps_into_the_outbound_notification_table';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_step_effect
   where effect_object_id in ('notification','notification_attempt')
     and expected_effect_type <> 'EXTERNAL_EFFECT_INTENT';
  check_name := 'notification_effects_not_classified_as_intent';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.phase_d_effect_ledger
   where provider_mode not in ('none','mock','disabled');
  check_name := 'ledger_rows_claiming_a_live_external_effect';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from (
    select step_run_id, effect_type from public.phase_d_effect_ledger
     group by 1,2 having count(*) > 1) d;
  check_name := 'duplicate_effects_for_one_step_run';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  -- DISCLOSURE, NOT A PASS. Counts steps whose effect has actually been produced at least once,
  -- which is a different question from whether the path exists. Reported as the gap so it FALLS,
  -- and ratcheted with an owner.
  select count(distinct step_id) into n from public.phase_d_effect_ledger;
  check_name := 'steps_with_no_effect_ever_produced';
  expected := '0'; actual := (m - n)::text; ok := (n = m); return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select expected_effect_type t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'effect_type_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select implementation_depth t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'implementation_depth_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select object_resolution t, count(*)::text c
            from public.phase_d_step_effect group by 1) x;
  check_name := 'object_resolution_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;
end $fn$;

commit;

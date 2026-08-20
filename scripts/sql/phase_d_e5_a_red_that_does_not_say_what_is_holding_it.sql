-- =================================================================================================
-- Phase D — E5. A red that does not say what is holding it.
--
-- `fn_phase_d_effect_state().steps_with_no_effect_ever_produced = 257` is the single red on a
-- twelve-check board. It is CORRECT. What it is not is readable: one number over 257 steps, and the
-- two documents that explain it give two different causes, one of which is wrong for most of them.
--
--   scripts/checks/kernel-boards.json says: "the only executions so far were aborted-transaction
--   probes, which roll back by design and leave no ledger row" — right, and true of all 257.
--
--   docs/phase-d/PHASE_D_BUILDER_CLOSURE.md says: "The effect ledger is empty because no committed
--   business arrival has ever driven a step" — and that is MEASURABLY WRONG for 185 of the 257.
--
-- THE CLASSIFICATION, read out of the effect contracts and the object bindings rather than asserted.
-- The deciding fact is which branch of fn_phase_d_effect_produce each step's declared effect takes:
--
--    21  CAPABILITY_REQUEST                       -> the production branch RAISES pd_capability_-
--        (no object binding at all)                  unavailable. The declared effect IS the refusal;
--                                                    a ledger row is only reachable in `test` mode,
--                                                    which the closure document already rules out as
--                                                    a result. HELD BY THE PROVIDER HOLD.
--
--    51  DOMAIN_MUTATION / VERSIONED_ARTIFACT     -> fn_phase_d_object_write against a real business
--        bound to an EXISTING_TABLE                  table: customers, inquiries, quotes,
--                                                    transactions, leads, refunds, os_incidents and
--                                                    eleven more. HELD BY THE ZERO-RESIDUE RULE.
--
--   185  everything else                          -> the effect writes ONLY the kernel's own step run
--        KERNEL_ONLY_TRANSITION (51),                or Phase D's own object store. No business row is
--        REVIEW_VERDICT (41),                        involved at any point. Held by NEITHER hold.
--        EXTERNAL_EFFECT_INTENT (12, mock-only),
--        MEASUREMENT_RECORD (7),
--        DOMAIN_MUTATION / VERSIONED_ARTIFACT
--        bound to a PHASE_D_OBJECT_VIEW (74)
--
--   ---
--   257  and 0 of the 257 carry a ledger row.
--
-- SO WHY ARE THE 185 STILL AT ZERO? Not for the reason the closure document gives. Measured:
--
--   The only routine that produces an effect is fn_phase_d_effect_produce, and its only caller is
--   fn_phase_d_handler_execute, whose only driver is fn_phase_d_drive_workflow. That driver opens
--   every run with `source_ref = format('zz-phase-d-%s-%s', …)` and
--   `trigger_ctx = {"driver":"fn_phase_d_drive_workflow","fixture":true}`. It DECLARES ITS OWN ROWS
--   FIXTURES. fn_phase_d_fixture_residue() scans every write-map target relation and
--   phase_d_object_record for `zz-phase-d-%`, `ZZ DEMO — %` and `%@example.invalid` in every text,
--   varchar and jsonb column, and is required to return 0.
--
--   The 185 therefore stay at zero because committing the only drive that can produce them would put
--   fixture rows on production — the same rule that keeps the fixtures out, not the business-arrival
--   argument. That is a THIRD blocker, and it is the one nobody had written down.
--
-- THE PATH ITSELF WORKS, and this was proved by execution on production at 02:5x UTC on 2026-08-20
-- rather than reasoned about. Two step runs — 255 (W06-S06) and 256 (W06-S07) — are real, committed,
-- `completed` KERNEL_ONLY_TRANSITION runs. Producing their declared effect inside an aborted
-- transaction and then reading pg_stat_xact_user_tables, which reports what the TRANSACTION wrote
-- rather than what a list of tables I chose to count says:
--
--     WROTE: public.phase_d_effect_ledger ins=2 upd=0 del=0
--     ledger_now=2   fn_phase_d_fixture_residue() = 0 rows
--     ref1 = public.phase_c_workflow_step_run:step_run_id=255   provider_mode=none
--     ref2 = public.phase_c_workflow_step_run:step_run_id=256   provider_mode=none
--
-- Exactly one table, two rows, no business row, no notification, no residue. THE ROWS WERE NOT KEPT.
-- Backfilling a ledger for two step runs that completed before the recording path was built would be
-- a row added to make a count look better, and `produced_by` would carry a role that did not produce
-- it. The measurement is the deliverable; the row is not.
--
-- WHAT THIS FILE DOES
--   1. fn_phase_d_effect_reachability() — the classification as an inspectable per-step relation,
--      derived from the contracts, so nobody has to trust the three numbers in this header.
--   2. fn_phase_d_effect_state() gains four rows beside the red. `steps_with_no_effect_ever_produced`
--      KEEPS ITS NAME AND ITS VALUE. It is not renamed, not lowered, not split into something that
--      passes — a ratchet whose subject is renamed silences whatever later takes the name, and its
--      entry in scripts/checks/kernel-boards.json is keyed on that exact string.
--
-- WHAT THIS FILE DOES NOT DO. It does not move the number. 257 is the honest reading and it stays.
-- Two of the three blockers are the founder's holds and are his to lift; the third is the fixture
-- rule, and lifting that means building a driver that does not mark its own rows fixtures — which is
-- Phase E work, not a Phase D repair.
-- =================================================================================================

create or replace function public.fn_phase_d_effect_reachability()
returns table(
  step_id text,
  workflow_id text,
  expected_effect_type text,
  reachability text,
  blocker text,
  canonical_relation text,
  has_produced_an_effect boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  select e.step_id,
         e.workflow_id,
         e.expected_effect_type,
         case
           when e.expected_effect_type = 'CAPABILITY_REQUEST'
             then 'REFUSAL_IS_THE_DECLARED_EFFECT'
           when e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
            and ob.relation_kind = 'EXISTING_TABLE'
             then 'NEEDS_A_COMMITTED_BUSINESS_ROW'
           else 'INTERNAL_EFFECT_NEEDS_NO_BUSINESS_ROW'
         end,
         case
           when e.expected_effect_type = 'CAPABILITY_REQUEST'
             then 'the provider hold — fn_phase_d_effect_produce raises pd_capability_unavailable in '
                  || 'production, and the refusal is the contract, not a failure'
           when e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT')
            and ob.relation_kind = 'EXISTING_TABLE'
             then 'the zero-residue rule — the effect writes ' || coalesce(ob.canonical_relation,'(unbound)')
           else 'the fixture rule — the only driver, fn_phase_d_drive_workflow, opens every run with '
                || 'source_ref zz-phase-d-… and trigger_ctx.fixture=true, and fn_phase_d_fixture_residue() '
                || 'must return 0. Neither the provider hold nor the zero-residue rule touches this step.'
         end,
         coalesce(ob.canonical_relation, '(none — the effect is the kernel step run itself)'),
         exists (select 1 from public.phase_d_effect_ledger l where l.step_id = e.step_id)
    from public.phase_d_step_effect e
    left join public.phase_d_business_object_binding ob on ob.object_id = e.effect_object_id;
$fn$;

-- A plain CREATE grants EXECUTE to PUBLIC. This function is SECURITY INVOKER, so it carries no
-- elevated privilege, but the estate's rule since E4 is that nothing in public answers anon.
revoke execute on function public.fn_phase_d_effect_reachability() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- fn_phase_d_effect_state — the eleven pass/fail checks and the three distributions are UNCHANGED.
-- steps_with_no_effect_ever_produced is unchanged in name, in derivation and in value. Four rows are
-- added after it: three that say what is holding the red, and one that fails if the classification
-- ever stops covering all 257 steps — a decomposition that silently loses a step would make the
-- three reasons add up to less than the number they explain.
-- -------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_phase_d_effect_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  --
  -- E5: NAME, DERIVATION AND VALUE ARE UNCHANGED ON PURPOSE. scripts/checks/kernel-boards.json keys
  -- its ratchet on this exact string, and a ratchet whose subject is renamed goes on silencing
  -- whatever later takes the name. The three rows that follow say what is holding it; they do not
  -- replace it and they do not lower it.
  select count(distinct step_id) into n from public.phase_d_effect_ledger;
  check_name := 'steps_with_no_effect_ever_produced';
  expected := '0'; actual := (m - n)::text; ok := (n = m); return next;

  -- ---- E5. THE RED, DECOMPOSED INTO THE THREE THINGS ACTUALLY HOLDING IT ----------------------
  -- Each row is a disclosure (ok = true) and each carries the count AND the lever that would move
  -- it, because a number with no named blocker is what made this red unreadable in the first place.
  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'REFUSAL_IS_THE_DECLARED_EFFECT' and not has_produced_an_effect;
  check_name := 'no_effect_because_the_refusal_is_the_effect';
  expected := 'informational — the provider hold, and it is the founder''s to lift';
  actual := n::text || ' CAPABILITY_REQUEST step(s): fn_phase_d_effect_produce raises '
         || 'pd_capability_unavailable in production. A ledger row here needs execution_context=test, '
         || 'which is not a result.';
  ok := true; return next;

  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'NEEDS_A_COMMITTED_BUSINESS_ROW' and not has_produced_an_effect;
  check_name := 'no_effect_because_no_business_row_may_be_created';
  expected := 'informational — the zero-residue rule, and it is the founder''s to lift';
  actual := n::text || ' step(s) whose effect writes an EXISTING_TABLE. The estate holds 0 customers, '
         || '0 inquiries, 0 quotes and 0 transactions since the 16 Aug purge and may not be given one.';
  ok := true; return next;

  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'INTERNAL_EFFECT_NEEDS_NO_BUSINESS_ROW' and not has_produced_an_effect;
  check_name := 'no_effect_although_none_is_needed_from_the_business';
  expected := 'informational — NEITHER hold touches these; the fixture rule does';
  actual := n::text || ' step(s) whose effect writes only the kernel step run or Phase D''s own '
         || 'object store. They are not waiting on a business arrival. The only driver, '
         || 'fn_phase_d_drive_workflow, opens every run with source_ref zz-phase-d-… and '
         || 'trigger_ctx.fixture=true, so committing one leaves residue that must be 0.';
  ok := true; return next;

  -- A decomposition that stops covering the thing it decomposes is worse than no decomposition:
  -- the three reasons would add up to fewer steps than the red they explain, and nothing would say so.
  select count(*) into n from public.fn_phase_d_effect_reachability();
  check_name := 'every_step_carries_a_reachability_class';
  expected := m::text; actual := n::text; ok := (n = m); return next;

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
end $function$;

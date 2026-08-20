-- =================================================================================================
-- Phase D — E7. The classifier read the binding, not the branch.
--
-- E5 partitioned the 257 steps by what their effect writes and put the answer on the board as
-- 21 / 51 / 185. **The 185 is wrong, and so is the 51.** E7 corrects them from the code path.
--
-- WHAT E5 GOT WRONG. `fn_phase_d_effect_reachability()` decided each step's class from
-- `phase_d_step_effect.effect_object_id` joined to `phase_d_business_object_binding`. That is the
-- DECLARED object. For two of the seven effect types it is not the object the routine writes:
--
--   REVIEW_VERDICT — fn_phase_d_effect_produce ignores e.effect_object_id entirely and calls
--     fn_phase_d_object_write with a HARDCODED 'object_id','review_record'. `review_record` binds to
--     `public.review_chain`, `relation_kind = EXISTING_TABLE`. All **41** review steps therefore
--     write a real existing table, and E5 counted every one of them as needing no table at all,
--     because their declared effect_object_id happens to name a Phase D view.
--
--   EXTERNAL_EFFECT_INTENT and MEASUREMENT_RECORD — both branches set
--     `v_relation := 'public.phase_d_effect_ledger'` and write nothing else, whatever their declared
--     object says. E5 reached the right class for these 19 steps by the wrong route, which is not
--     the same as being right.
--
-- This is the estate's own recurring lens turned on the instrument this session built: **is this
-- number measuring what its name says?** The name said "what the effect writes". The measurement
-- read what the registry declares. They agree for 216 of 257 and disagree for 41.
--
-- THE CORRECTED PARTITION, taken from the branch each effect type actually executes:
--
--    21  CAPABILITY_REQUEST                     raises pd_capability_unavailable in production.
--                                               The declared effect IS the refusal. PROVIDER HOLD.
--    70  KERNEL_ONLY_TRANSITION 51              writes ONE row, into public.phase_d_effect_ledger,
--        EXTERNAL_EFFECT_INTENT 12              and nothing else anywhere.
--        MEASUREMENT_RECORD 7
--    74  DOMAIN_MUTATION / VERSIONED_ARTIFACT   writes public.phase_d_object_record through a
--        bound to a PHASE_D_OBJECT_VIEW         v_obj_* view — Phase D's own store.
--    78  REVIEW_VERDICT 41 -> review_chain      writes a REAL EXISTING TABLE that the zero-residue
--        DOMAIN/VERSIONED 37 -> refunds,        rule does not name: review_chain, refunds,
--        company_goals, opportunity,            company_goals, opportunity, os_incidents,
--        os_incidents, legal_reviews,           legal_reviews, documents, quote_comparisons,
--        documents, quote_comparisons,          supplier_capabilities, leads, stripe_events,
--        supplier_capabilities, leads,          inquiry_matches, department_objective,
--        stripe_events, inquiry_matches,        content_drafts, reveal_invoices, org_tasks
--        department_objective, content_drafts,
--        reveal_invoices, org_tasks
--    14  DOMAIN_MUTATION -> quotes 5,           writes one of the FIVE tables the zero-residue rule
--        inquiries 4, customers 4,              names. ZERO-RESIDUE RULE.
--        transactions 1
--   ---
--   257
--
-- WHAT THAT CHANGES IN THE STORY, stated plainly because the wrong version is already committed:
--
--   E5 said 185 steps are "held by neither hold". The honest figure for "writes nothing outside
--   Phase D's own two tables" is **144** (70 + 74). A further **78** write a real table the
--   zero-residue rule does not name — permitted by the letter of the rule, and still a row in a
--   table the company uses, which is a different thing from a Phase D ledger row and should not have
--   been counted with it. Only **14** touch customers, inquiries, quotes or transactions.
--
--   E5 said 51 steps need a committed business row. Following the branch, **92** write an
--   EXISTING_TABLE (78 + 14). The 51 was the count of DOMAIN_MUTATION and VERSIONED_ARTIFACT steps
--   bound to an EXISTING_TABLE and it missed all 41 review steps.
--
-- The red itself does not move: `steps_with_no_effect_ever_produced` is still **257**, still named
-- exactly as `scripts/checks/kernel-boards.json` keys its ratchet, and still not lowered.
--
-- The board rows are renamed to say what they now measure. The three E5 rows
-- (`no_effect_because_the_refusal_is_the_effect`, `no_effect_because_no_business_row_may_be_created`,
-- `no_effect_although_none_is_needed_from_the_business`) are REPLACED, not kept alongside: two of
-- the three carried a number this file proves wrong, and a board that shows both readings makes the
-- reader choose. None of the three is a ratchet subject in kernel-boards.json — only
-- `steps_with_no_effect_ever_produced` is — so renaming them silences nothing.
-- =================================================================================================

-- A RETURN-TYPE CHANGE, NOT A NEW OBJECT. The out-parameter `canonical_relation` becomes
-- `writes_relation`, because the old name described the object the row DECLARES and the new one
-- describes what the branch WRITES — which is the whole correction. Postgres refuses
-- `create or replace` across a changed OUT row type ("cannot change return type of existing
-- function"), so the drop is required and is immediately followed by the create.
--
-- THE DROP MATTERS FOR THE GRANT. A plain CREATE grants EXECUTE to PUBLIC; only CREATE OR REPLACE
-- preserves the ACL. So E5's revoke does NOT survive this file, and the revoke below is load-bearing
-- rather than belt and braces. It is verified by the control block at the end.
drop function if exists public.fn_phase_d_effect_reachability();

create or replace function public.fn_phase_d_effect_reachability()
returns table(
  step_id text,
  workflow_id text,
  expected_effect_type text,
  reachability text,
  blocker text,
  writes_relation text,
  has_produced_an_effect boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- THE JOIN IS ON WHAT THE BRANCH WRITES, NOT ON WHAT THE ROW DECLARES. fn_phase_d_effect_produce
  -- hardcodes 'review_record' for every REVIEW_VERDICT step and writes only the ledger for
  -- EXTERNAL_EFFECT_INTENT and MEASUREMENT_RECORD, so e.effect_object_id is the wrong key for 60 of
  -- the 257 and reading it was the E5 defect.
  with resolved as (
    select e.step_id, e.workflow_id, e.expected_effect_type,
           case
             when e.expected_effect_type = 'CAPABILITY_REQUEST'
               then '(nothing — the branch raises pd_capability_unavailable)'
             when e.expected_effect_type in
                  ('KERNEL_ONLY_TRANSITION','EXTERNAL_EFFECT_INTENT','MEASUREMENT_RECORD')
               then 'public.phase_d_effect_ledger'
             else (select ob.canonical_relation
                     from public.phase_d_business_object_binding ob
                    where ob.object_id = case when e.expected_effect_type = 'REVIEW_VERDICT'
                                              then 'review_record' else e.effect_object_id end)
           end as writes_relation,
           case
             when e.expected_effect_type in
                  ('CAPABILITY_REQUEST','KERNEL_ONLY_TRANSITION','EXTERNAL_EFFECT_INTENT',
                   'MEASUREMENT_RECORD')
               then null
             else (select ob.relation_kind
                     from public.phase_d_business_object_binding ob
                    where ob.object_id = case when e.expected_effect_type = 'REVIEW_VERDICT'
                                              then 'review_record' else e.effect_object_id end)
           end as relation_kind
      from public.phase_d_step_effect e
  )
  select r.step_id, r.workflow_id, r.expected_effect_type,
         case
           when r.expected_effect_type = 'CAPABILITY_REQUEST' then 'REFUSAL_IS_THE_DECLARED_EFFECT'
           when r.writes_relation = 'public.phase_d_effect_ledger' then 'WRITES_ONLY_THE_PHASE_D_LEDGER'
           when r.relation_kind = 'PHASE_D_OBJECT_VIEW' then 'WRITES_ONLY_THE_PHASE_D_OBJECT_STORE'
           when r.writes_relation in ('public.customers','public.inquiries','public.quotes',
                                      'public.transactions','public.notifications')
             then 'WRITES_A_ZERO_RESIDUE_TABLE'
           when r.relation_kind = 'EXISTING_TABLE' then 'WRITES_AN_EXISTING_TABLE_NOT_UNDER_THE_RULE'
           else 'UNRESOLVED'
         end,
         case
           when r.expected_effect_type = 'CAPABILITY_REQUEST'
             then 'the provider hold — the branch raises rather than records, and the refusal is the '
                  || 'contract. A ledger row here needs execution_context=test, which is not a result.'
           when r.writes_relation in ('public.customers','public.inquiries','public.quotes',
                                      'public.transactions','public.notifications')
             then 'the zero-residue rule — the effect writes ' || r.writes_relation
                  || ', one of the five tables that rule names'
           when r.relation_kind = 'EXISTING_TABLE'
             then 'the fixture rule, AND a row in a real table — ' || r.writes_relation
                  || '. The zero-residue rule does not name it, which is not the same as it being '
                  || 'Phase D''s own storage.'
           else 'the fixture rule — the only driver, fn_phase_d_drive_workflow, opens every run with '
                || 'source_ref zz-phase-d-… and trigger_ctx.fixture=true, and '
                || 'fn_phase_d_fixture_residue() must return 0. Neither the provider hold nor the '
                || 'zero-residue rule touches this step.'
         end,
         coalesce(r.writes_relation, '(unresolved — no binding for the object this branch writes)'),
         exists (select 1 from public.phase_d_effect_ledger l where l.step_id = r.step_id)
    from resolved r;
$fn$;

-- REQUIRED, not decorative: the DROP above discarded E5's ACL and the CREATE re-granted EXECUTE to
-- PUBLIC. `public` is named first — a revoke naming only anon against a PUBLIC grant is a silent
-- no-op, which is the whole subject of E4.
revoke execute on function public.fn_phase_d_effect_reachability() from public, anon, authenticated;

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
  -- which is a different question from whether the path exists.
  --
  -- NAME, DERIVATION AND VALUE UNCHANGED SINCE IT WAS WRITTEN. scripts/checks/kernel-boards.json
  -- keys its ratchet on this exact string, and a ratchet whose subject is renamed goes on silencing
  -- whatever later takes the name. The rows that follow say what is holding it; they neither replace
  -- it nor lower it, and E7 did not touch it either.
  select count(distinct step_id) into n from public.phase_d_effect_ledger;
  check_name := 'steps_with_no_effect_ever_produced';
  expected := '0'; actual := (m - n)::text; ok := (n = m); return next;

  -- ---- THE RED, DECOMPOSED BY THE BRANCH EACH EFFECT ACTUALLY EXECUTES ------------------------
  -- E5 wrote three rows here and derived them from the DECLARED effect object. E7 replaces them
  -- with five derived from the branch, because fn_phase_d_effect_produce hardcodes 'review_record'
  -- for all 41 REVIEW_VERDICT steps and writes only the ledger for EXTERNAL_EFFECT_INTENT and
  -- MEASUREMENT_RECORD. The E5 rows are gone rather than kept beside these: two of them carried a
  -- number this file proves wrong, and a board showing both readings makes the reader choose.
  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'REFUSAL_IS_THE_DECLARED_EFFECT' and not has_produced_an_effect;
  check_name := 'no_effect_because_the_refusal_is_the_effect';
  expected := 'informational — the provider hold, and it is the founder''s to lift';
  actual := n::text || ' CAPABILITY_REQUEST step(s): the branch raises pd_capability_unavailable in '
         || 'production rather than recording. A ledger row needs execution_context=test, which is '
         || 'not a result.';
  ok := true; return next;

  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'WRITES_A_ZERO_RESIDUE_TABLE' and not has_produced_an_effect;
  check_name := 'no_effect_because_the_effect_writes_a_zero_residue_table';
  expected := 'informational — the zero-residue rule, and it is the founder''s to lift';
  actual := n::text || ' step(s) whose effect writes customers, inquiries, quotes or transactions. '
         || 'The estate holds 0 of each since the 16 Aug purge and may not be given one.';
  ok := true; return next;

  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'WRITES_AN_EXISTING_TABLE_NOT_UNDER_THE_RULE' and not has_produced_an_effect;
  check_name := 'no_effect_and_the_effect_writes_a_real_table_the_rule_does_not_name';
  expected := 'informational — the fixture rule, plus a row in a table the company uses';
  actual := n::text || ' step(s) writing review_chain, refunds, company_goals, opportunity, '
         || 'os_incidents, legal_reviews, documents, quote_comparisons, supplier_capabilities, '
         || 'leads, stripe_events, inquiry_matches, department_objective, content_drafts, '
         || 'reveal_invoices or org_tasks. Permitted by the letter of the zero-residue rule and '
         || 'still not Phase D''s own storage — 41 of them are the REVIEW_VERDICT steps, which write '
         || 'review_chain through a hardcoded object_id their own effect row does not name.';
  ok := true; return next;

  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability in ('WRITES_ONLY_THE_PHASE_D_LEDGER','WRITES_ONLY_THE_PHASE_D_OBJECT_STORE')
     and not has_produced_an_effect;
  check_name := 'no_effect_although_the_effect_leaves_phase_d_tables_only';
  expected := 'informational — NEITHER hold touches these; the fixture rule does';
  actual := n::text || ' step(s) writing only phase_d_effect_ledger or phase_d_object_record. '
         || 'They are not waiting on a business arrival. The only driver, fn_phase_d_drive_workflow, '
         || 'opens every run with source_ref zz-phase-d-… and trigger_ctx.fixture=true, so '
         || 'committing one leaves residue that fn_phase_d_fixture_residue() must report as 0.';
  ok := true; return next;

  -- A decomposition that stops covering the thing it decomposes is worse than no decomposition, and
  -- UNRESOLVED is its own failure: a branch whose written relation cannot be resolved is a step
  -- nobody can say anything about.
  select count(*) into n from public.fn_phase_d_effect_reachability()
   where reachability = 'UNRESOLVED';
  check_name := 'steps_whose_written_relation_does_not_resolve';
  expected := '0'; actual := n::text; ok := (n = 0); return next;

  select count(*) into n from public.fn_phase_d_effect_reachability();
  check_name := 'every_step_carries_a_reachability_class';
  expected := m::text; actual := n::text; ok := (n = m); return next;

  select string_agg(x.t || '=' || x.c, ' ' order by x.t) into v
    from (select reachability t, count(*)::text c
            from public.fn_phase_d_effect_reachability() group by 1) x;
  check_name := 'reachability_class_distribution';
  expected := 'informational'; actual := coalesce(v,'(none)'); ok := true; return next;

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

-- -------------------------------------------------------------------------------------------------
-- Read-only, and it raises rather than reporting. It asserts the two things this file could get
-- wrong: that the corrected partition still covers all 257, and that the DROP did not leave the new
-- routine open to anon — the exact regression E4 exists to prevent, reintroduced by a drop-and-
-- recreate in the very session that closed it.
-- -------------------------------------------------------------------------------------------------
do $e7$
declare
  v_total int; v_steps int; v_unresolved int; v_anon boolean; v_auth boolean; v_dist text;
begin
  select count(*) into v_total from public.fn_phase_d_effect_reachability();
  select count(*) into v_steps from public.phase_b_workflow_step;
  if v_total <> v_steps then
    raise exception 'E7: the classifier returns % rows for % frozen steps. A duplicate binding row '
      'multiplies the join and a missing one drops a step; either way the decomposition stops '
      'covering the number it explains.', v_total, v_steps;
  end if;

  select count(*) into v_unresolved from public.fn_phase_d_effect_reachability()
   where reachability = 'UNRESOLVED';
  if v_unresolved <> 0 then
    raise exception 'E7: % step(s) write a relation that does not resolve. A step nobody can '
      'classify is not evidence of anything.', v_unresolved;
  end if;

  select has_function_privilege('anon', p.oid, 'EXECUTE'),
         has_function_privilege('authenticated', p.oid, 'EXECUTE')
    into v_anon, v_auth
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_phase_d_effect_reachability';
  if coalesce(v_anon, true) or coalesce(v_auth, true) then
    raise exception 'E7: the drop-and-recreate left fn_phase_d_effect_reachability executable by '
      'anon=% authenticated=%. A plain CREATE grants EXECUTE to PUBLIC and only CREATE OR REPLACE '
      'preserves an ACL.', v_anon, v_auth;
  end if;

  select actual into v_dist from public.fn_phase_d_effect_state()
   where check_name = 'reachability_class_distribution';
  raise notice 'E7 distribution: %', v_dist;
end
$e7$;

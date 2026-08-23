-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of scripts/sql/phase_d_d2_business_object_map.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the row counts below, accepts them, and runs it.
--
-- WHY EVERY VIEW IS NAMED. `drop table public.phase_d_object_record cascade` would take all thirty
-- v_obj_* views silently — the operator would see one line of output and thirty objects would be
-- gone without ever appearing in the script. Every one is dropped by name first, so the file is a
-- complete list of what disappears and a missing view shows up as an error rather than as nothing.
-- Thirty is measured, not assumed: 30 views of relkind 'v' named v_obj_% live on
-- htdblwldjkcgjvmqkbeh, and phase_d_business_object_binding holds 30 rows with
-- relation_kind = 'PHASE_D_OBJECT_VIEW'. The two counts agree.
--
-- OBJECTS DROPPED, by name, in FK/dependency-safe order (never `cascade`):
--   1. the 30 v_obj_* views (all read public.phase_d_object_record)
--   2. trigger a00_phase_d_object_policy_guard on public.phase_d_object_record
--   3. trigger z00_kernel_truncate_guard        on public.phase_d_object_record
--   4. index  public.phase_d_object_record_object_key_idx (object_id, business_key, version desc)
--   5. table  public.phase_d_object_record — with phase_d_object_record_pkey, _identity_key
--      UNIQUE (object_id, business_key, version), _payload_not_empty, _object_id_fkey,
--      _superseded_by_fkey (self-referencing), and sequence phase_d_object_record_record_id_seq
--   6. table  public.phase_d_business_object_binding — with _policy_family_check,
--      _relation_kind_check, _ownership_scope_check, _target_action_check, _object_id_fkey
--
-- PRECONDITION — RUN THE d9c DOWN FIRST. public.phase_d_fixture_stage.object_id is
-- phase_d_fixture_stage_object_id_fkey -> phase_d_business_object_binding(object_id) ON DELETE
-- RESTRICT. While phase_d_fixture_stage exists, step 6 below fails. That failure is correct: it is
-- the FK doing its job, not a defect in this file. Run
-- scripts/sql/down/phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it_down.sql first.
--
-- ROW COUNT AT RISK (measured on htdblwldjkcgjvmqkbeh; WORKLIST D.1 item 17):
--   public.phase_d_business_object_binding   56 rows  — the object catalogue, hand-derived
--   public.phase_d_object_record              0 rows  — nothing has ever been written through it
--   The 30 views hold no rows of their own.
--
-- NOT TOUCHED: the four CREATE OR REPLACE FUNCTION bodies in d2 (fn_phase_d_object_write,
-- fn_phase_d_object_read, fn_phase_d_object_policy_guard and one more). A create-or-replace has no
-- down — see scripts/sql/down/README.md. fn_phase_d_object_policy_guard survives this file with
-- nothing left to guard, which is deliberate: dropping a function another file may still name is a
-- larger blast radius than leaving an unused one behind.
-- =================================================================================================

begin;

-- ---- 1. the thirty object views, by name --------------------------------------------------------
drop view if exists public.v_obj_ai_change;
drop view if exists public.v_obj_capability_case;
drop view if exists public.v_obj_content_campaign;
drop view if exists public.v_obj_customer_case;
drop view if exists public.v_obj_customer_selection;
drop view if exists public.v_obj_customer_terms_acceptance;
drop view if exists public.v_obj_dispatch_batch;
drop view if exists public.v_obj_document_extraction;
drop view if exists public.v_obj_exception_record;
drop view if exists public.v_obj_financial_close;
drop view if exists public.v_obj_growth_program;
drop view if exists public.v_obj_inquiry_route_set;
drop view if exists public.v_obj_inquiry_version;
drop view if exists public.v_obj_intelligence_product;
drop view if exists public.v_obj_knowledge_change;
drop view if exists public.v_obj_notification_attempt;
drop view if exists public.v_obj_organization_change_request;
drop view if exists public.v_obj_performance_recovery_case;
drop view if exists public.v_obj_product_change;
drop view if exists public.v_obj_quotation_evaluation;
drop view if exists public.v_obj_quotation_revision;
drop view if exists public.v_obj_reconciliation_case;
drop view if exists public.v_obj_release_candidate;
drop view if exists public.v_obj_supplier_correction_case;
drop view if exists public.v_obj_supplier_coverage_case;
drop view if exists public.v_obj_supplier_retention_case;
drop view if exists public.v_obj_supplier_safe_package;
drop view if exists public.v_obj_supplier_terms_acceptance;
drop view if exists public.v_obj_supplier_verification_case;
drop view if exists public.v_obj_ux_specification;

-- ---- 2-3. the two triggers on the record table --------------------------------------------------
drop trigger if exists a00_phase_d_object_policy_guard on public.phase_d_object_record;
drop trigger if exists z00_kernel_truncate_guard       on public.phase_d_object_record;

-- ---- 4-5. the record table and its index --------------------------------------------------------
drop index if exists public.phase_d_object_record_object_key_idx;
drop table if exists public.phase_d_object_record;

-- ---- 6. the object catalogue --------------------------------------------------------------------
drop table if exists public.phase_d_business_object_binding;

do $ctl$
declare
  v_left  text := '';
  v_views int;
begin
  select count(*) into v_views
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'v\_obj\_%';

  if v_views <> 0 then
    raise exception 'D2 down did not take: % v_obj_* views survive. Name every survivor in this file rather than adding cascade.', v_views;
  end if;

  if to_regclass('public.phase_d_object_record') is not null then
    v_left := v_left || 'public.phase_d_object_record ';
  end if;
  if to_regclass('public.phase_d_business_object_binding') is not null then
    v_left := v_left || 'public.phase_d_business_object_binding ';
  end if;
  if to_regclass('public.phase_d_object_record_object_key_idx') is not null then
    v_left := v_left || 'public.phase_d_object_record_object_key_idx ';
  end if;

  if v_left <> '' then
    raise exception 'D2 down did not take: still present -> %', v_left;
  end if;

  raise notice 'D2 down: 30 v_obj_* views, phase_d_object_record and phase_d_business_object_binding are gone.';
end $ctl$;


-- ---- ROUTINES THIS FILE INTRODUCED ------------------------------------------------------
-- Added 23 Aug 2026. Every routine below is defined by no other file under scripts/sql/, so
-- re-applying a predecessor cannot restore it and dropping it is the whole of its reversal.
-- Anything still calling one of them will raise on a missing function after this rollback.
drop function if exists public.fn_phase_d_object_policy_guard();
drop function if exists public.fn_phase_d_object_state();
commit;

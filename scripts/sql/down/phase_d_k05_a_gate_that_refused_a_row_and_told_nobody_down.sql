-- =================================================================================================
-- PHASE D DOWN — reverses scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- THIS ONE IS HAND-WRITTEN AND IT DOES NOT DROP ANYTHING, DELIBERATELY.
--
-- scripts/phase_d/build_missing_down_scripts.mjs generated a version of this file that ran
--   drop function if exists public.trg_gate_incomplete_match();
-- because its rule is "a routine only ONE Phase D file defines was introduced by that file". That
-- rule cannot tell a routine a Phase D file CREATED from a pre-existing product routine a Phase D
-- file REPLACED, and both of the trigger functions K05 touches are the second kind: they have
-- guarded public.inquiry_matches since long before Phase D and are named nowhere else in
-- scripts/sql or supabase/migrations, which is why the generator could not see it. Running the
-- generated version would have dropped a live product trigger's function and left the trigger
-- public.gate_incomplete_match on public.inquiry_matches pointing at nothing.
--
-- The correct reversal is a RESTORE. Both bodies below are the exact live definitions read out of
-- htdblwldjkcgjvmqkbeh on 23 Aug 2026 immediately BEFORE K05 was applied.
--
-- NOT TOUCHED: public.fn_phase_d_object_write, which K05 also replaces. Many Phase D files define
-- it; its predecessor is restored by re-applying the file before K05 in that routine's chain, in
-- order, exactly as scripts/sql/down/README.md describes.
-- =================================================================================================


CREATE OR REPLACE FUNCTION public.trg_gate_incomplete_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ready boolean;
begin
  select rfq_ready into ready from public.inquiries where id = NEW.inquiry_id;
  if ready is not true then return null; end if;   -- silently skip: incomplete RFQs don't qualify for routing
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_unsafe_match_eligibility_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare l record; v_reason text;
begin
  select id, company_name, banned, matching_blocked, permanently_closed, license_expiry
    into l from public.leads where id = new.supplier_id;
  if l.id is null then return new; end if;

  v_reason := case
    when coalesce(l.banned,false)             then 'supplier is banned'
    when coalesce(l.matching_blocked,false)   then 'supplier is blocked from matching'
    when coalesce(l.permanently_closed,false) then 'supplier is permanently closed'
    when l.license_expiry is not null and l.license_expiry < current_date
                                              then 'supplier licence expired ' || l.license_expiry
    else null end;
  if v_reason is null then return new; end if;

  perform public.fn_unsafe_block(
    'ineligible_supplier_match', 'trigger:a00_unsafe_match_eligibility',
    'inquiry_matches', coalesce(new.inquiry_id::text,'') || '/' || new.supplier_id::text,
    'insert match row',
    jsonb_build_object('supplier_id', new.supplier_id, 'company', l.company_name,
                       'inquiry_id', new.inquiry_id, 'reason', v_reason));
  raise warning 'unsafe_block: refused match of inquiry % to supplier % — %',
        new.inquiry_id, new.supplier_id, v_reason;
  return null;   -- row not inserted; the ledger row survives
end $function$;


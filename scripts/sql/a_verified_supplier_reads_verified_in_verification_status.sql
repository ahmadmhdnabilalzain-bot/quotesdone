-- a_verified_supplier_reads_verified_in_verification_status.sql — sales_engineer, 19 Oct 2026 (ruling 1230 walk).
--
-- THE DEFECT. Approval sets leads.verified (fn_sales_engineer_verifies_supplier: verified = (decision = 'approved'))
-- and no writer anywhere sets leads.verification_status, so it stays at its column default 'unverified' on an
-- approved supplier. Measured 19 Oct 2026 03:45 Dubai over all 19,933 leads: 19,931 verified=false/'unverified',
-- 2 verified=true/'unverified' (126512, 144967 — both ZZ DEMO), 0 consistent verified rows. The OS supplier views
-- (fn_os_* list, the supplier 360) show the column, so an approved supplier read "unverified" there.
--
-- THE FIX, ONCE, WHERE EVERY WRITER PASSES. verified is written by more than one routine and also flipped to false
-- by trg_leads_e0_mandatory_six_gate (an approved supplier who loses a mandatory item). Patching each writer would
-- leave the next one stale, so a BEFORE trigger derives verification_status from the FINAL verified value.
-- Its name sorts after trg_leads_e0_* (Postgres fires BEFORE triggers in name order), so it sees the gate's demotion.
-- No column list on UPDATE: a column list tests the statement's SET list, and the gate changes verified without
-- the statement naming it.

create or replace function public.fn_leads_verification_status_follows_verified()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  new.verification_status := case when new.verified is true then 'verified' else 'unverified' end;
  return new;
end $fn$;

revoke execute on function public.fn_leads_verification_status_follows_verified() from public, anon, authenticated;

drop trigger if exists trg_leads_z90_verification_status_follows_verified on public.leads;
create trigger trg_leads_z90_verification_status_follows_verified
  before insert or update on public.leads
  for each row execute function public.fn_leads_verification_status_follows_verified();

-- ONE-TIME CORRECTION, BY EXACT ID: the two rows measured inconsistent above. Lead 143027 is not touched.
update public.leads
   set verification_status = case when verified is true then 'verified' else 'unverified' end
 where id in (126512, 144967)
   and verification_status is distinct from case when verified is true then 'verified' else 'unverified' end;

-- VERDICT (DDL in this file, so no raise: a raise would roll the trigger back with it).
select case
  when (select count(*) from public.leads
         where verification_status is distinct from case when verified is true then 'verified' else 'unverified' end) <> 0
    then 'PROBE FAILED: leads still disagree between verified and verification_status'
  when not exists (select 1 from pg_trigger where tgrelid = 'public.leads'::regclass
                    and tgname = 'trg_leads_z90_verification_status_follows_verified' and not tgisinternal)
    then 'PROBE FAILED: trigger missing'
  else 'PROBE OK' end as verdict;

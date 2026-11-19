-- A PAUSED CUSTOMER IS TOLD AN ADDRESS THAT IS READ (customer_support, 19 Nov 2026).
--
-- WHAT. trg_block_banned_inquiry (BEFORE INSERT on inquiries) refuses a paused customer's new request with a message that
-- named a "support" mailbox at quotesdone.com. Nothing reads that mailbox: measured 19 Nov 2026 (SELECT on production), 0 of
-- the 100 inbound_messages rows were addressed to it, and no reading, triage or routing code names it. The customer who
-- writes there to get their account back is never answered. info@quotesdone.com is the public address customer_support
-- answers (email_triage reads it as a tenant mailbox, supplier_mailbox_reading.ts TENANT_READ_MAILBOXES; login_otp already
-- names it in its do-not-send copy). The same copy in customer_api/index.ts (a suspended account) changes in the same PR.
-- WHY. Founder ledger 1474 (never lose the conversation): an address nobody reads loses it before it starts.
-- The body is the live definition of 19 Nov 2026 (pg_get_functiondef) with only the address changed. CREATE OR REPLACE keeps
-- the ACL (postgres, service_role); the revoke below restates it.
-- Seat: customer_support. Apply at merge: node scripts/apply_sql.mjs scripts/sql/a_paused_customer_is_told_an_address_that_is_read.sql --apply --ddl
-- Rollback: re-run the definition in scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql (line 1610).
-- prevented by: scripts/checks/no_copy_names_a_mailbox_nobody_reads.test.mjs
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.trg_block_banned_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_banned boolean;
begin
  select banned into v_banned from customers where id = NEW.customer_id;
  if coalesce(v_banned, false) then
    raise exception 'Your account has been paused due to repeated cancelled requests. Please contact info@quotesdone.com to restore it.';
  end if;
  return NEW;
end $function$;
revoke execute on function public.trg_block_banned_inquiry() from public, anon, authenticated;

-- PROBE (a light catalog read, no row touched): the live body names the read address and no longer the unread one.
select case
  when position('info@quotesdone.com' in pg_get_functiondef('public.trg_block_banned_inquiry()'::regprocedure)) = 0
    then 'PROBE FAILED: trg_block_banned_inquiry does not name info@quotesdone.com'
  when pg_get_functiondef('public.trg_block_banned_inquiry()'::regprocedure) ~ 'support@quotesdone\.com'
    then 'PROBE FAILED: trg_block_banned_inquiry still names the unread mailbox'
  else 'PROBE OK' end as verdict;

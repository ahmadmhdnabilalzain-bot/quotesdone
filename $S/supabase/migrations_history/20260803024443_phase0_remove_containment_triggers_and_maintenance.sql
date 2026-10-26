-- PHASE 0 — remove containment from the product architecture. Founder decision, 2026-08-03.
--
-- Removes: the three registration/upload refusal triggers, maintenance mode, and the COS freeze.
-- Does NOT restore the two supplier-docs storage policies recorded in containment.policy_removed:
-- they granted bucket-wide SELECT+INSERT on every supplier's KYC documents to any authenticated
-- account with no owner predicate, which is the audit's #1 critical finding. Owner-scoped
-- replacements are impossible (no table joins auth.uid() to a supplier — see identity-model-gap.md),
-- so the correct end state is the current one: RLS on, zero policies, all document access through
-- edge functions on the service role. Uploads are restored by dropping the trigger below, not by
-- restoring those policies.
--
-- agent_autonomy_enabled stays false and the 18 contained crons return one at a time as
-- Workstream J clears each, per the same founder decision.

drop trigger if exists zz_containment_customer_registration on public.customers;
drop trigger if exists zz_containment_supplier_registration on public.leads;
drop trigger if exists zz_containment_sensitive_upload on storage.objects;

drop function if exists public.trg_containment_block_customer_registration();
drop function if exists public.trg_containment_block_supplier_registration();
drop function if exists public.trg_containment_block_sensitive_upload();
drop function if exists public.fn_containment_maintenance();

update public.app_secrets set value = 'false', updated_at = now() where key = 'containment_maintenance';
update public.app_secrets set value = 'false', updated_at = now() where key = 'cos_frozen';

update containment.change_log
   set rollback_sql = coalesce(rollback_sql,'') || E'\n-- RESTORED 2026-08-03 (Phase 0).'
 where id in (1,6,7,8,9,10);;

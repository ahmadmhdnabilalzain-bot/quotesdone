-- OUR OWN claim_lookup PROBE PROVES ITSELF, AS supplier_portal'S DOES.
-- Seat: it_engineer, 7 Oct 2026. Gap 1 of the learning-gate audit (PR #1281), handoff 100487.
--
-- MEASURED: watch:refusal_rate:claim_lookup (25 Sep 14:01Z): all 24 refusals in 24 h were the hourly launch-path
-- probe api:claim_lookup (supabase/functions/_shared/launch_path.ts), answered 400 invalid_link on purpose; it still
-- runs hourly (7 Oct 01:16Z, 400). #1139 gave supplier_portal's probe a credential (x-qd-probe) and marked its refusal
-- fixture, which refusal_rate excludes; claim_lookup's probe was left without one, so its refusals still read as
-- strangers turned away, and the finding cleared only when other traffic diluted them.
-- CHANGE: the probe presents cred_fn_resilience_ping in x-qd-probe (launch_path.ts), claim_lookup marks its
-- invalid-link refusal fixture only when fn_internal_auth accepts that credential for claim_lookup
-- (_shared/probe_caller.ts), and this file adds 'claim_lookup' to fn.resilience_ping's scope. The call is still refused.
-- prevented by: scripts/checks/the_three_detector_gaps_of_the_learning_audit_stay_closed.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/our_own_claim_lookup_probe_proves_itself.sql --apply --ddl

update public.internal_credential
   set scope = array_append(scope, 'claim_lookup')
 where context = 'fn.resilience_ping' and not ('claim_lookup' = any(scope));

select case when coalesce((select 'claim_lookup' = any(scope) from public.internal_credential where context = 'fn.resilience_ping'), false)
            then 'PROBE OK :: fn.resilience_ping may prove itself to claim_lookup'
            else 'PROBE FAILED :: fn.resilience_ping is not scoped to claim_lookup' end as verdict;

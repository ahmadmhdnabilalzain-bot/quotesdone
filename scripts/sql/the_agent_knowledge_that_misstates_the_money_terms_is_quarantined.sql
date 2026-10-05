-- THE AGENT KNOWLEDGE THAT MISSTATES THE MONEY TERMS IS QUARANTINED.
--
-- Assigned: accountant (money terms). 6 Oct 2026. Founder ledger 1122.
--
-- MEASURED (production, read-only, 6 Oct 2026): five live agent_knowledge rows, all validation_status 'unvalidated',
-- tell a seat that late-payment interest is "capped at the principal" and that the AED 250 / AED 500 administrative fee
-- is "NOT in either instrument" / "not yet in the Supplier Agreement" and must be kept out of demands:
--   id 3     _global              'Penalty & collections model'       (priority 94: reaches every seat)
--   id 5     collections          'Role & expertise'
--   id 21    legal                'Debt-recovery procedure'
--   id 22    collections          'Professional standard (CICM credit management)'
--   id 8012  contract_specialist  'Contract review for the supplier and customer agreements' (also says 9%, no cap date)
-- None of it is what the signed documents say: Supplier Agreement v13 clause 33(b) carries the AED 500 fee, v14 clause
-- 33(d) the agreed 12% (9% for v9-v13), simple, and no clause caps interest at the principal; the charge is computed by
-- fn_accountant_nonresponse_charge from the version signed at the reveal. A seat drafting a demand from these rows would
-- either under-claim or cite a cap that is not in the contract.
--
-- WHAT THIS DOES: quarantines exactly those five ids (closed by exact key, never by a text match), with the reason.
-- The authority on the money terms is the signed agreement and fn_accountant_nonresponse_charge, not knowledge prose.
--   node scripts/apply_sql.mjs scripts/sql/the_agent_knowledge_that_misstates_the_money_terms_is_quarantined.sql --apply --seat accountant

update public.agent_knowledge
   set validation_status = 'quarantined',
       supporting_evidence = coalesce(supporting_evidence, '') || ' | QUARANTINED 6 Oct 2026 (accountant, legal audit): states an interest cap at the principal and an admin fee "not in the instrument"; Supplier Agreement v13/v14 clause 33 and fn_accountant_nonresponse_charge are the authority.',
       updated_at = now()
 where id in (3, 5, 21, 22, 8012) and validation_status <> 'quarantined';

select case when (select count(*) from public.agent_knowledge where id in (3, 5, 21, 22, 8012) and validation_status = 'quarantined') = 5
            then 'PROBE OK: the five rows are quarantined'
            else 'PROBE FAILED: not all five rows are quarantined' end as verdict;

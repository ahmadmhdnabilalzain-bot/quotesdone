import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_dispatch_step(jsonb)'::regprocedure) as def`);

const OLD = `    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');
    end if;`;

const NEW = `    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');
    end if;

    -- F37. THE SAME HOLE F13 CLOSED FOR THE KEY, STILL OPEN FOR THE OWNER.
    --
    -- E25 gave a COMPANY-scoped object an owner -- the frozen registry's own accountable role for
    -- the step -- and left CUSTOMER- and SUPPLIER-scoped objects to row_owner_ref, which reads the
    -- owner column of the run's OWN business row. A step that CREATES the first record of such an
    -- object has no such row yet, so the owner is unresolvable by construction and the step refuses
    -- with pd_effect_owner_or_key_missing on every drive. Measured: W10-S01
    -- (supplier_verification_case), W18-S01 (customer_case) and W19-S01 (supplier_retention_case)
    -- are the FIRST handler refusal of their whole workflow, for exactly this.
    --
    -- In production that refusal is right and it stays: a supplier case owned by a supplier this
    -- routine picked would be the auto-vivified account defect one table over.
    --
    -- Inside a verified Phase D fixture run there is a real answer and it is a READ. The scenario
    -- factory created the parent -- a supplier, a customer -- through the canonical services and
    -- recorded it in public.phase_d_scenario_record with its own owner_ref and ownership_scope.
    -- This takes THAT owner, matched on the scope the object declares. It invents nothing, it
    -- cannot fire outside a fixture context, and where the scenario created no parent of that scope
    -- the owner is still null and the step still refuses.
    if v_owner is null
       and coalesce(v_scope,'COMPANY') <> 'COMPANY'
       and public.fn_phase_d_fixture_context() is not null then
      select nullif(btrim(coalesce(sc.owner_ref,'')),'') into v_owner
        from public.phase_d_scenario_record sc
       where sc.fixture_run_id = public.fn_phase_d_fixture_context()
         and sc.ownership_scope = v_scope
         and coalesce(btrim(sc.owner_ref),'') <> ''
       order by sc.scenario_record_id
       limit 1;
    end if;`;

const n = def.split(OLD).length - 1;
if (n !== 1) { console.error(`anchor matched ${n} times`); process.exit(1); }

const HEADER = `-- F37 - the same hole F13 closed for the key, still open for the owner
--
-- MEASURED. Three of the thirty frozen workflows have their FIRST handler refusal at their FIRST
-- step, all with the same code and the same shape:
--
--   W10-S01 :: writes business object supplier_verification_case and the call names no owner_ref
--   W18-S01 :: writes business object customer_case and the call names no owner_ref
--   W19-S01 :: writes business object supplier_retention_case and the call names no owner_ref
--
-- All three objects are CUSTOMER- or SUPPLIER-scoped. E25 resolves the owner of a COMPANY-scoped
-- object from the frozen registry's accountable role for the step, and everything else from
-- row_owner_ref -- the owner column of the run's own business row. A step that CREATES the first
-- record of an object has no such row, so for these three the owner was unresolvable by
-- construction, exactly as the business_key was for W01-S07 until F13.
--
-- F13 fixed the key by reading the scenario the factory built. This does the same for the owner,
-- with the same three limits: it is a read of public.phase_d_scenario_record, it cannot fire
-- outside a verified Phase D fixture context, and where the scenario created no parent of the
-- object's own ownership scope the owner stays null and the step still refuses. In production
-- nothing changes at all.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. One anchor, required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f37_the_owner_the_scenario_created_and_the_dispatch_never_read.sql',
  HEADER + def.replace(OLD, NEW) + ';\n');
console.log('written');

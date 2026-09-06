import { writeFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_d_dispatch_step'`);
let body = prosrc;
const rep = (o, n) => { const c = body.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); body = body.replace(o, n); };

const OLD = `    if v_owner is null
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

rep(OLD, `    if v_owner is null
       and coalesce(v_scope,'COMPANY') <> 'COMPANY'
       and public.fn_phase_d_fixture_context() is not null then
      -- J06. WHICH SCENARIO RECORD IS THE OWNER. The block below took the FIRST record of the same
      -- ownership scope, and "same scope" is not an identity. Measured 23 Aug 2026 on one built
      -- scenario, SUPPLIER-scoped records in scenario_record_id order:
      --
      --   supplier_safe_package   owner=9385a4f3-...   <- the INQUIRY's uuid, and the first row
      --   supplier_account        owner=5909be81-...   key=37090
      --   supplier_terms_acceptance owner=37090
      --   supplier_capability     owner=37090
      --   supplier_assignment     owner=37090
      --
      -- so every SUPPLIER-scoped write inherited an inquiry's uuid as its supplier, and
      -- public.supplier_capabilities.supplier_id is bigint: "invalid input syntax for type bigint:
      -- 65d2c329-64dd-0209-1544-e87ef8a30684" -- pd_effect_value_malformed, on W09-S03 and W12-S06.
      --
      -- The owner column already says what it wants, in the schema: it carries a FOREIGN KEY to the
      -- relation that holds the owning party. Read that, find the business object bound to that
      -- relation, and take the key the scenario gave THAT object. Nothing is chosen by position, by
      -- naming convention or by a list of scopes; every step is a read of a record the estate
      -- already holds. Where the owner column carries no foreign key, or the scenario created no
      -- such party, the previous behaviour stands and the step still refuses when it resolves
      -- nothing.
      select cl2.relname, ns2.nspname into v_own_rel, v_own_ns
        from public.phase_d_object_write_map wm2
        join pg_attribute a2 on a2.attrelid = to_regclass(wm2.target_relation)
                            and a2.attname = wm2.owner_column and a2.attnum > 0
        join pg_constraint c2 on c2.conrelid = a2.attrelid and c2.contype = 'f'
                             and a2.attnum = any (c2.conkey)
        join pg_class cl2 on cl2.oid = c2.confrelid
        join pg_namespace ns2 on ns2.oid = cl2.relnamespace
       where wm2.object_id = v_cx#>>'{business_object,object_id}'
         and coalesce(btrim(wm2.owner_column),'') <> ''
       limit 1;

      if v_own_rel is not null then
        select nullif(btrim(coalesce(sc.business_key,'')),'') into v_owner
          from public.phase_d_scenario_record sc
          join public.phase_d_business_object_binding bb on bb.object_id = sc.object_id
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and bb.canonical_relation = v_own_ns || '.' || v_own_rel
           and coalesce(btrim(sc.business_key),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;

      if v_owner is null then
        select nullif(btrim(coalesce(sc.owner_ref,'')),'') into v_owner
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.ownership_scope = v_scope
           and coalesce(btrim(sc.owner_ref),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;
    end if;`);

rep('  v_scope    text;   -- E25', '  v_scope    text;   -- E25\n  v_own_rel  text;   -- J06\n  v_own_ns   text;   -- J06');

const header = `-- J06 — a scope is not an identity: every supplier-scoped write inherited the first row's owner
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. Two of the seven steps the 257-step coverage matrix
-- left without an effect refused with pd_effect_value_malformed:
--
--   W09-S03  invalid input syntax for type bigint: "65d2c329-64dd-0209-1544-e87ef8a30684"
--   W12-S06  invalid input syntax for type bigint: "2617926b-3a53-2def-f1d1-72fcc582e93f"
--
-- F37 gave a CUSTOMER- or SUPPLIER-scoped object its owner from the scenario, by taking the first
-- public.phase_d_scenario_record of the same ownership scope. Dumping one built scenario's
-- SUPPLIER-scoped records in that order says why that is not an answer:
--
--   supplier_safe_package     owner=9385a4f3-...  <- the INQUIRY's uuid, and the first row
--   supplier_account          owner=5909be81-...  key=37090
--   supplier_terms_acceptance owner=37090
--   supplier_capability       owner=37090
--   supplier_assignment       owner=37090
--
-- Ten of eleven agree on 37090 and the one that is first does not, so the write took an inquiry's
-- uuid as its supplier and public.supplier_capabilities.supplier_id is bigint.
--
-- The owner column says what it wants and it says it in the schema: it carries a foreign key to the
-- relation that holds the owning party. The dispatch reads that key, finds the business object
-- bound to that relation, and takes the identity the scenario gave THAT object. No position, no
-- naming convention, no list of scopes, and no majority vote -- three reads of records the estate
-- already holds. Where the owner column has no foreign key, or the scenario created no such party,
-- the previous behaviour stands and a step that resolves no owner still refuses with
-- pd_effect_owner_or_key_missing, exactly as it did.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_dispatch_step. No DDL, no grants.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j06.mjs.
CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j06_a_scope_is_not_an_identity_and_the_first_row_won.sql',
  header + body + '$function$;\n');
console.log('written');

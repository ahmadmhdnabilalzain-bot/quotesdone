import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';
let d = (await sql(`select pg_get_functiondef('public.fn_phase_d_dispatch_step(jsonb)'::regprocedure) def`))[0].def;
const A = `      if v_owner is null then
        select nullif(btrim(coalesce(sc.owner_ref,'')),'') into v_owner
          from public.phase_d_scenario_record sc
         where sc.fixture_run_id = public.fn_phase_d_fixture_context()
           and sc.ownership_scope = v_scope
           and coalesce(btrim(sc.owner_ref),'') <> ''
         order by sc.scenario_record_id
         limit 1;
      end if;`;
if (!d.includes(A)) { console.error('MISS'); process.exit(1); }
const R = `      -- L04. AND AN OBJECT THE ESTATE STORES IN public.phase_d_object_record HAS NO WRITE MAP, SO
      -- IT HAS NO OWNER COLUMN AND NO FOREIGN KEY FOR J06 TO READ. All 22 PHASE_D_OBJECT_VIEW
      -- objects fall straight past that block to the positional fallback below -- "the first
      -- scenario record of the same ownership scope" -- which J06 itself recorded is not an
      -- identity. It went unseen because the fixture scenario built those objects too, so nothing
      -- downstream ever had to read one the product had written.
      --
      -- Measured 23 Aug 2026 with the harness withholding the object the workflow under test
      -- produces: W09-S06 wrote the supplier terms acceptance owned by ca99c3de-..., which is the
      -- supplier_safe_package's uuid and the first SUPPLIER-scoped scenario record. The acceptance
      -- therefore belonged to no supplier, "the acceptance this run's party owns" found nothing at
      -- W09-S07, S08 and S09, and BR-025 refused all three from the catalogue.
      --
      -- THE REGISTRY SAYS WHOSE IT IS. The object's governing workflow has a primary object, and
      -- where that primary object is a DIFFERENT object of the SAME ownership scope, that object is
      -- the party. supplier_terms_acceptance is governed by W09 whose primary object is
      -- supplier_account, both SUPPLIER. Nothing is chosen by position. An object that is its own
      -- governing workflow's primary object, or whose governing workflow names none (the two
      -- registered as W16/W27 and W09/W10), resolves nothing here and the fallback below still
      -- runs, so no object loses an owner it had.
      if v_owner is null then
        select nullif(btrim(coalesce(sc.business_key,'')),'') into v_owner
          from public.phase_d_business_object_binding bb
          join public.phase_b_workflow w on w.workflow_id = bb.governing_workflow_id
          join public.phase_d_business_object_binding pb on pb.object_id = w.primary_object
          join public.phase_d_scenario_record sc on sc.object_id = pb.object_id
         where bb.object_id = v_cx#>>'{business_object,object_id}'
           and pb.object_id <> bb.object_id
           and pb.ownership_scope = bb.ownership_scope
           and sc.fixture_run_id = public.fn_phase_d_fixture_context()
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
      end if;`;
d = d.replace(A, R);
writeFileSync('scripts/tmp_diag/l01_dispatch_step.sql', d);
console.log('dispatch len=' + d.length);

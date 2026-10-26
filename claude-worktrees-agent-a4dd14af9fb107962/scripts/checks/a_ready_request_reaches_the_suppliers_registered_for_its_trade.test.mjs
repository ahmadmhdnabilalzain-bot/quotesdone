// a_ready_request_reaches_the_suppliers_registered_for_its_trade — Assigned: sales_engineer.
//
// MEASURED 14 Sep 2026. sales_engineer's `match` passed an inquiry's stored INTAKE slugs straight to
// fn_match_capability, whose gate is `supplier_capabilities.trades && p_trades`. Suppliers registered
// in TAXONOMY codes, and 39 of the 56 intake slugs are not taxonomy codes — so a ready request for
// glass, fitout, carpentry, fire safety, security, generators ... matched nobody.
// fn_match_capability(['glass']) returned 0 while (['aluminium']) returned both demo aluminium suppliers.
//
// THE FOUNDER'S RULINGS (14 Sep 2026), which these tests hold the router to:
//   "there is nothing called nearest match. either exact match or no match"
//   "if a supplier comes tomorrow and register for packaging services he is welcomed"
//
// THE PROPERTIES, each proved for real inside an aborted transaction (the demo supplier is inserted,
// matched and rolled back, so nothing is left and nobody is emailed):
//   1. EXACT. A request in intake trade X invites a verified supplier registered for trade X.
//   2. NO NEAREST. A request whose trade has no exact supplier invites nobody — even when a supplier
//      of the neighbouring trade exists (roofing is not waterproofing; acrylic is not signage).
//   3. OPEN. A supplier who registers a trade nobody listed ("Packaging Services", stored the way
//      supplier_capability.ts stores it) is invited to a request in that same category.
// The end-to-end half — the portal posting a ready request and suppliers being invited — is harness
// journeys a/b (scripts/e2e).
//
// RE-MEASURED 18 Sep 2026. All 13 tests failed against production with
// "leads N: a supplier whose mandatory fields are incomplete cannot be verified (missing: reg_mobile,
// reg_email, reg_licence, reg_profile, reg_terms)". The seed, not the gate, was wrong: it inserted an
// approved+verified supplier carrying NONE of the founder's mandatory six. trg_leads_e0_mandatory_six_gate
// went live with #698 (325a3e1, 15 Sep 11:14 +0400 — the commit that first carries it in the schema
// mirror), not with #725; #725's only trigger on leads is AFTER UPDATE OF claimed_by. The gate is right
// and stays untouched: the seed below now creates a COMPLETE demo supplier.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

/** A demo supplier registered with `capTrades` (a SQL text[] expression); a request for `requested`:
 *  was the supplier invited? */
async function probe(label, capTrades, requested) {
  try {
    await sql(`do $probe$
      declare v_id bigint; v_n int; v_demo boolean; v_code text; v_lic text; v_prof text; v_six text[];
      begin
        -- THE SIX ARE MANDATORY (the founder's rule; trg_leads_e0_mandatory_six_gate since 15 Sep 2026,
        -- scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql). An
        -- approved supplier must carry all six, so the demo supplier this probe seeds is COMPLETE: name,
        -- verified UAE mobile, verified e-mail, trade licence, company profile, signed terms. The two
        -- documents are storage rows the probe creates for itself -- a path naming nothing is not a
        -- document -- so no real document registration is touched; the whole block is rolled back.
        v_code := public.fn_trade_code(${q(label)});
        v_lic := 'zz-demo/routing-probe-' || v_code || '-licence.pdf';
        v_prof := 'zz-demo/routing-probe-' || v_code || '-profile.pdf';
        -- on conflict: two runs of this check probing the same trade at once would otherwise serialize
        -- on the unique index (bucket_id, name) until the first one rolled back.
        insert into storage.objects (bucket_id, name) values ('supplier-docs', v_lic), ('supplier-docs', v_prof)
        on conflict do nothing;  -- no target: since Supabase storage versioning (measured 22 Sep 2026) the (bucket_id, name) uniques are partial indexes, which a column list cannot name (42P10)
        -- leads.id is GENERATED ALWAYS; the probe rolls back, so the id it takes is never kept.
        insert into public.leads (company_name, email, phone, owner_phone_verified, owner_email_verified,
                                  license_doc_path, company_profile_doc_path, signed_terms_path,
                                  verified, approval_status)
        values ('ZZ DEMO routing probe ' || ${q(label)}, 'routing-probe-' || v_code || '@example.invalid',
                '+971500000099', true, true, v_lic, v_prof,
                'suppliers/zz-demo-routing-probe-' || v_code || '.pdf', true, 'approved')
        returning id into v_id;
        -- The gate would have refused the insert; this says so in the probe's own words if the
        -- definition of the six ever moves ahead of this seed again.
        v_six := public.fn_supplier_mandatory_six_for(v_id);
        if cardinality(v_six) <> 0 then raise exception 'CHK<<incomplete demo supplier: %>>', v_six; end if;
        select is_demo into v_demo from public.leads where id = v_id;
        -- A trade that legally needs an approval (fire_fighting: civil_defence, security_systems: sira)
        -- is only matched to a supplier holding it, so the probe supplier holds what its trades need.
        insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, authority_approvals)
        values (v_id, ${capTrades}, array['contractor','installer','supplier'], now(),
                (select coalesce(jsonb_object_agg(a, true), '{}'::jsonb)
                   from public.taxonomy_trade t, unnest(t.authority_required) a
                  where t.code = any(${capTrades})));
        select count(*) into v_n
          from public.fn_match_capability(public.fn_taxonomy_trades_for(array[${q(requested)}]), 'executes', '{}'::text[], '{}'::text[], null, null, 'Dubai', 60) m
         where m.supplier_id = v_id;
        raise exception 'CHK<<invited=% demo=%>>', v_n, v_demo;
      end $probe$;`);
    throw new Error(`${label}: the probe returned without its CHK exception, so nothing was measured and nothing was rolled back.`);
  } catch (e) {
    const msg = String(e?.message || e);
    const m = msg.match(/CHK<<invited=(\d+) demo=(\w+)>>/);
    // RAISE prints a boolean as t/f, not true/false.
    if (m) return { invited: Number(m[1]), demo: m[2] === 't' || m[2] === 'true' };
    // A SEED THAT IS REFUSED IS NOT A MATCHING RESULT. This used to return { invited: null }, and
    // every assertion then read "the supplier was not invited" when in truth the supplier was never
    // created — an instrument measuring the wrong subject: 13 green-looking properties asserting
    // nothing at all about matching. It is now an unmistakable error naming the seed.
    throw new Error(`${label}: THE PROBE COULD NOT SEED A VERIFIABLE DEMO SUPPLIER, so this check asserts NOTHING about matching. `
      + `Fix the seed (it must satisfy the founder's mandatory six) — never the gate. Database said: ${msg.slice(0, 400)}`);
  }
}
/** Registered the way the portal registers a picked trade: the taxonomy code(s) of that trade. */
const asCode = (t) => `public.fn_taxonomy_trades_for(array[${q(t)}])`;

// Intake slugs that are NOT taxonomy codes (the measured failure) and one that is (aluminium).
for (const t of ['aluminium', 'glass', 'safety', 'fitout', 'carpentry', 'security', 'generators']) {
  test(`exact: a ready ${t} request invites the demo supplier registered for ${t}`, { skip: SKIP }, async () => {
    const r = await probe(t, asCode(t), t);
    assert.equal(r.invited, 1, `not invited: ${JSON.stringify(r)}`);
    assert.equal(r.demo, true, 'the probe supplier must be a demo identity');
  });
}

test('exact: an aluminium supplier is not invited to a fire-safety request', { skip: SKIP }, async () => {
  const r = await probe('aluminium', asCode('aluminium'), 'safety');
  assert.equal(r.invited, 0, JSON.stringify(r));
});

// The mappings removed on the 14 Sep ruling: each was a neighbouring trade, not the same one.
for (const [requested, neighbour] of [['roofing', 'waterproofing'], ['acrylic', 'signage'], ['tents-and-shade-structures', 'steel'], ['safety', 'safety_equipment']]) {
  test(`no nearest: a ${neighbour} supplier is not invited to a ${requested} request`, { skip: SKIP }, async () => {
    const r = await probe(neighbour, `array[${q(neighbour)}]`, requested);
    assert.equal(r.invited, 0, JSON.stringify(r));
  });
}

test('open: a supplier registered for "Packaging Services" is invited to a packaging-services request', { skip: SKIP }, async () => {
  const r = await probe('Packaging Services', `array[public.fn_trade_code('Packaging Services')]`, 'packaging-services');
  assert.equal(r.invited, 1, JSON.stringify(r));
  assert.equal(r.demo, true, 'the probe supplier must be a demo identity');
});

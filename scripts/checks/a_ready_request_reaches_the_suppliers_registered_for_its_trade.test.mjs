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
      declare v_id bigint; v_n int; v_demo boolean;
      begin
        -- leads.id is GENERATED ALWAYS; the probe rolls back, so the id it takes is never kept.
        insert into public.leads (company_name, email, verified, approval_status)
        values ('ZZ DEMO routing probe ' || ${q(label)}, 'routing-probe-' || public.fn_trade_code(${q(label)}) || '@example.invalid', true, 'approved')
        returning id into v_id;
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
    return { invited: null, note: 'no exception at all' };
  } catch (e) {
    const m = String(e?.message || e).match(/CHK<<invited=(\d+) demo=(\w+)>>/);
    // RAISE prints a boolean as t/f, not true/false.
    return m ? { invited: Number(m[1]), demo: m[2] === 't' || m[2] === 'true' } : { invited: null, note: String(e?.message || e).slice(0, 200) };
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

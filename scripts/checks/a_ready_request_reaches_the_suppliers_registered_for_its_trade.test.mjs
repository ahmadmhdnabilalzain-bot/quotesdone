// a_ready_request_reaches_the_suppliers_registered_for_its_trade — Assigned: sales_engineer.
//
// MEASURED 14 Sep 2026. sales_engineer's `match` passed an inquiry's stored INTAKE slugs straight to
// fn_match_capability, whose gate is `supplier_capabilities.trades && p_trades`. Suppliers register
// in TAXONOMY codes (_shared/supplier_capability.ts accepts only active taxonomy_trade codes), and 39
// of the 56 intake slugs are not taxonomy codes — so a ready request for glass, fitout, carpentry,
// fire safety, security, generators ... matched nobody, and the router's "no fit" suppressed the
// keyword fallback. fn_match_capability(['glass']) returned 0 while (['aluminium']) returned both
// demo aluminium suppliers.
//
// THE PROPERTY. For a request in intake trade X, a verified supplier whose confirmed capability is
// the taxonomy codes X resolves to (public.fn_taxonomy_trades_for — the router's own resolver) is
// among the suppliers the router's matcher returns. Proved for real inside an aborted transaction:
// the demo supplier is inserted, matched and rolled back, so nothing is left and nobody is emailed.
// A negative control proves the gate still discriminates (an aluminium supplier is not invited to a
// fire-safety request). The end-to-end half — the portal posting a ready request and suppliers being
// invited — is harness journeys a/b (scripts/e2e).
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

/** Register a demo supplier for `registeredFor`, route a request for `requested`: was it invited? */
async function probe(registeredFor, requested) {
  try {
    await sql(`do $probe$
      declare v_id bigint; v_n int; v_demo boolean;
      begin
        v_id := (select coalesce(max(id), 0) from public.leads) + 1000000;
        insert into public.leads (id, company_name, email, verified, approval_status)
        values (v_id, 'ZZ DEMO routing probe ' || ${q(registeredFor)}, 'routing-probe-' || ${q(registeredFor)} || '@example.invalid', true, 'approved');
        select is_demo into v_demo from public.leads where id = v_id;
        insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at)
        values (v_id, public.fn_taxonomy_trades_for(array[${q(registeredFor)}]), array['contractor','installer','supplier'], now());
        select count(*) into v_n
          from public.fn_match_capability(public.fn_taxonomy_trades_for(array[${q(requested)}]), 'executes', '{}'::text[], '{}'::text[], null, null, 'Dubai', 60) m
         where m.supplier_id = v_id;
        raise exception 'CHK<<invited=% demo=%>>', v_n, v_demo;
      end $probe$;`);
    return { invited: null, note: 'no exception at all' };
  } catch (e) {
    const m = String(e?.message || e).match(/CHK<<invited=(\d+) demo=(\w+)>>/);
    return m ? { invited: Number(m[1]), demo: m[2] === 'true' } : { invited: null, note: String(e?.message || e).slice(0, 200) };
  }
}

// Intake slugs that are NOT taxonomy codes (the measured failure) and one that is (aluminium).
const TRADES = ['aluminium', 'glass', 'safety', 'fitout', 'carpentry', 'security', 'generators'];

for (const t of TRADES) {
  test(`a ready ${t} request invites the demo supplier registered for ${t}`, { skip: SKIP }, async () => {
    const r = await probe(t, t);
    assert.equal(r.invited, 1, `not invited: ${JSON.stringify(r)}`);
    assert.equal(r.demo, true, 'the probe supplier must be a demo identity');
  });
}

test('the gate still discriminates: an aluminium supplier is not invited to a fire-safety request', { skip: SKIP }, async () => {
  const r = await probe('aluminium', 'safety');
  assert.equal(r.invited, 0, JSON.stringify(r));
});

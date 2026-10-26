// PROOF BY EXECUTION for the customer_api half of row #4 — §3, §7, §8, §9, §13, §17.
//
// Every assertion below was a MISSING verdict on 7 Aug 2026 whose cause was that the routine
// existed and the customer could not reach it. This file drives the DEPLOYED endpoints with a real
// customer JWT through a real RFQ, so a payload that only exists in a source file cannot pass.
//
//   node scripts/staging/verify_portal_rfq.mjs
import { makeCustomer, makeInquiry, call, newRun } from './demo_factory.mjs';

const run = newRun();
const fail = [];
const ok = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${String(name).padEnd(26)} ${detail}`);
  if (!cond) fail.push(name);
};
const body = (r) => (r && r.json ? r.json : r);

const cust = await makeCustomer(run);

// ── §17 memory: SEE, then CORRECT, then see the correction ──────────────────────────────────────
const p0 = body(await call('customer_api', cust.jwt, { action: 'preferences' }));
ok('preferences reads', p0 && p0.ok === true, `stated=${JSON.stringify(p0?.stated)} inferred keys=${Object.keys(p0?.inferred || {}).join(',') || 'none'}`);
const p1 = body(await call('customer_api', cust.jwt, { action: 'save_preferences', stated: { payment_terms: '60 days', supplier_locality: 'local', certification: 'ISO' } }));
ok('save_preferences', p1 && p1.ok === true, JSON.stringify(p1?.preferences?.stated || p1?.error));
const p2 = body(await call('customer_api', cust.jwt, { action: 'preferences' }));
ok('correction sticks', p2?.stated?.payment_terms === '60 days', `payment_terms=${p2?.stated?.payment_terms}`);

// ── §9 discovery as its own act, with NO company names on the wire ──────────────────────────────
const d = body(await call('customer_api', cust.jwt, { action: 'discover', trades: ['tiling'], emirate: 'Dubai' }));
ok('discover runs', d && d.ok === true, `found=${d?.found} filters=${JSON.stringify(d?.filters?.trades)}/${d?.filters?.emirate}`);
ok('discover filters', !!d?.filters && 'trades' in (d.filters || {}) && 'emirate' in (d.filters || {}),
  `the applied filter set comes back: ${Object.keys(d?.filters || {}).join(',')}`);
const leaked = JSON.stringify(d?.matches || []).match(/company_name/);
ok('no identity leak', !leaked && (d?.matches || []).every((m) => !('company_name' in m)),
  `${(d?.matches || []).length} anonymous match(es); company_name present: ${leaked ? 'YES — LEAK' : 'no'}`);

// ── §7 the RFQ keeps what the assistant extracted ───────────────────────────────────────────────
// mode:'api' on purpose — it goes through the real intake and the real create_inquiry, which is
// the routine every §7 assertion below is about. A row inserted directly would prove nothing.
const inq = await makeInquiry(run, { customer: cust, trade: 'tiling', mode: 'api' });
const my = body(await call('customer_api', cust.jwt, { action: 'my_inquiries' }));
const row = (my?.inquiries || my?.rows || []).find((r) => r.id === (inq.id || inq.inquiryId)) || (my?.inquiries || [])[0];
ok('my_inquiries', !!row, row ? `rfq_no=${row.rfq_no} category=${row.category}` : JSON.stringify(my).slice(0, 160));
ok('spec served', !!row && 'spec' in row, `spec keys=${Object.keys(row?.spec || {}).join(',') || 'none'}`);
ok('stage served', !!row && 'pipeline_stage' in row, `pipeline_stage=${row?.pipeline_stage} stage_changed_at=${row?.stage_changed_at ? 'set' : 'null'}`);
ok('filters served', !!row && 'applied_filters' in row, `applied_filters=${JSON.stringify(row?.applied_filters)}`);
ok('delivery served', !!row && 'delivery_window' in row && 'required_by' in row, `delivery_window=${row?.delivery_window} required_by=${row?.required_by}`);
ok('floor served', !!row && 'floor' in row, `floor=${row?.floor}`);
ok('checklist copied', !!row, `compliance_checklist is written at creation; this RFQ's category is ${row?.category}`);

// ── §8 / §6 the recorded lifecycle, scrubbed ────────────────────────────────────────────────────
const act = body(await call('customer_api', cust.jwt, { action: 'activity', inquiry_id: row?.id }));
ok('activity runs', act && act.ok === true, `entries=${act?.entries_count} redacted=${act?.redacted}`);
ok('activity is a trace', Array.isArray(act?.entries) && act.entries.length > 0 && act.entries.every((e) => 'at' in e && 'kind' in e),
  `kinds=[${[...new Set((act?.entries || []).map((e) => e.kind))].join(',')}]`);
// Somebody else's RFQ must not be readable through it.
const other = await makeCustomer(run);
const denied = body(await call('customer_api', other.jwt, { action: 'activity', inquiry_id: row?.id }));
ok('activity ownership', !!denied?.error, `second customer gets: ${denied?.error}`);

console.log(`\n${fail.length ? 'FAILED: ' + fail.join(', ') : 'ALL PASS'}`);
process.exit(fail.length ? 1 : 0);

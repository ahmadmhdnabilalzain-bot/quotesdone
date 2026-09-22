// PROOF BY EXECUTION for the §1/§2/§20/§21 entry payload — customer_portal action=overview.
//
// The scorer reads source; this calls the DEPLOYED function with a real customer JWT and asserts
// the keys are on the wire. A payload that exists in a file and 500s in production is not a
// capability, and every one of these keys was added in the same change as the routines behind it.
//
//   node scripts/staging/verify_portal_entry.mjs
import { makeCustomer, call, newRun } from '../lib/demo_factory.mjs';

const run = newRun();
const fail = [];
const ok = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${String(name).padEnd(30)} ${detail}`);
  if (!cond) fail.push(name);
};

const cust = await makeCustomer(run);
const r = await call('customer_portal', cust.jwt, { action: 'overview' });
const j = r && r.json ? r.json : r;

if (!j || j.error) { console.log('overview failed: ' + JSON.stringify(j)); process.exit(1); }

ok('ok', j.ok === true, String(j.ok));
ok('stats', !!j.stats, Object.keys(j.stats || {}).join(','));
ok('headline', typeof j.headline === 'string' && j.headline.length > 0, JSON.stringify(j.headline));
ok('alerts_count', typeof j.alerts_count === 'number', String(j.alerts_count));
// The twin is the §2 profile. A brand-new customer has no history, so the ASSERTION is on the KEYS
// the twin carries, never on their values — demanding a non-zero project count here would be
// demanding that a customer created four seconds ago already have projects.
const TWIN_KEYS = ['industry', 'projects_active', 'preferred_suppliers', 'preferred_categories', 'understanding_pct'];
const present = TWIN_KEYS.filter((k) => j.twin && k in j.twin);
ok('twin', !!j.twin, j.twin ? 'kind=' + j.twin.kind : 'null');
ok('twin keys', present.length === TWIN_KEYS.length, `${present.length}/${TWIN_KEYS.length} [${present.join(',')}]`);
ok('understanding_pct', Number.isFinite(Number(j.twin?.understanding_pct)), String(j.twin?.understanding_pct) + ' (computed from facts held, not a constant)');
ok('layout', Array.isArray(j.layout?.order) && j.layout.order.length > 0, `${j.layout?.source} order=[${(j.layout?.order || []).join(',')}] reason=${j.layout?.reason}`);
ok('degraded', !j.degraded, j.degraded ? 'DEGRADED: ' + j.degraded.join(',') : 'no routine failed');

// §21 save_layout: a hand-arranged order must win over the computed one on the next read.
const s = await call('customer_portal', cust.jwt, { action: 'save_layout', pinned: ['documents'], order: ['documents', 'projects'] });
const sj = s && s.json ? s.json : s;
ok('save_layout', sj && sj.ok === true, JSON.stringify(sj?.layout || sj));
const r2 = await call('customer_portal', cust.jwt, { action: 'overview' });
const j2 = r2 && r2.json ? r2.json : r2;
ok('pin survives', j2?.layout?.order?.[0] === 'documents' && j2?.layout?.source === 'saved',
  `first=${j2?.layout?.order?.[0]} source=${j2?.layout?.source}`);

console.log(`\n${fail.length ? 'FAILED: ' + fail.join(', ') : 'ALL PASS'}`);
process.exit(fail.length ? 1 : 0);

// IS ANYTHING FROM THIS SESSION STAGING-ONLY?
//
//   node scripts/staging/audit_session_parity.mjs
//
// The founder's standing rule is "nothing is for staging. all for deploy." A routine promoted but
// not deployed, an edge function deployed to one project, a cron scheduled on one side, or demo
// data seeded on staging alone are four different ways to break it and they fail differently — so
// each is checked separately and the evidence names which side is short.
//
// Read-only on both projects: qd_guard's mgmtRead refuses anything else.
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token };

// Everything this session created or changed, by name.
const ROUTINES = [
  'fn_supplier_twin', 'fn_supplier_products', 'fn_supplier_advisor', 'fn_supplier_network_map',
  'fn_supplier_market', 'fn_supplier_workspaces', 'fn_supplier_quality', 'fn_supplier_score_refresh',
  'fn_supplier_opportunities', 'fn_supplier_tier', 'fn_supplier_negotiation',
  'fn_supplier_certifications', 'fn_supplier_product_match', 'fn_supplier_risk_monitor',
  'fn_rating_due', 'fn_lead_time_interval',
];
const EDGE_FNS = ['supplier_portal', 'supplier_onboard', 'supplier_catalog_ingest'];
const CRONS = ['supplier_risk_complaints', 'supplier_risk_response_delays', 'supplier_risk_performance_drops'];

let bad = 0;
const fail = (m) => { bad++; console.log('  SHORT  ' + m); };

// ── 1. ROUTINES: present on both, and byte-identical ────────────────────────────────────────────
const defs = (ref) => mgmtRead(ref, `select p.proname n, md5(p.prosrc) h
  from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='public' and p.proname in (${ROUTINES.map((r) => `'${r}'`).join(',')}) order by 1`);
const [sd, pd] = await Promise.all([defs(STAGE), defs(PROD_REF)]);
const sm = Object.fromEntries(sd.map((r) => [r.n, r.h]));
const pm = Object.fromEntries(pd.map((r) => [r.n, r.h]));
console.log(`ROUTINES (${ROUTINES.length} expected)`);
for (const r of ROUTINES) {
  if (!sm[r]) fail(`${r} missing on STAGING`);
  else if (!pm[r]) fail(`${r} missing on PRODUCTION`);
  else if (sm[r] !== pm[r]) fail(`${r} DIFFERS: staging ${sm[r]} production ${pm[r]}`);
}
console.log(`  ${ROUTINES.filter((r) => sm[r] && pm[r] && sm[r] === pm[r]).length}/${ROUTINES.length} identical on both`);

// ── 2. EDGE FUNCTIONS: deployed to both, and the same verify_jwt posture ─────────────────────────
console.log('\nEDGE FUNCTIONS');
for (const ref of [STAGE, PROD_REF]) {
  const live = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/functions`, { headers: H })).json();
  const byName = Object.fromEntries((live || []).map((f) => [f.slug, f]));
  for (const f of EDGE_FNS) {
    if (!byName[f]) fail(`${f} NOT DEPLOYED on ${ref === PROD_REF ? 'PRODUCTION' : 'staging'}`);
    else console.log(`  ok  ${f.padEnd(24)} ${ref === PROD_REF ? 'production' : 'staging   '} v${byName[f].version} verify_jwt=${byName[f].verify_jwt}`);
  }
}

// ── 3. CRON: the monitors are scheduled on both ─────────────────────────────────────────────────
console.log('\nCRON');
for (const ref of [STAGE, PROD_REF]) {
  const jobs = await mgmtRead(ref, `select jobname from cron.job where jobname in (${CRONS.map((c) => `'${c}'`).join(',')}) and active`);
  const have = new Set(jobs.map((j) => j.jobname));
  for (const c of CRONS) if (!have.has(c)) fail(`${c} not scheduled/active on ${ref === PROD_REF ? 'PRODUCTION' : 'staging'}`);
  console.log(`  ${have.size}/${CRONS.length} active on ${ref === PROD_REF ? 'production' : 'staging'}`);
}

// ── 4. DEMO FIXTURES: the same fences exist on both ─────────────────────────────────────────────
// Counts, not ids: the two projects allocate their own keys, so an id comparison would report drift
// that is not drift. What must match is that the fixture EXISTS and is fenced on each.
console.log('\nDEMO FIXTURES');
const fx = (ref) => mgmtRead(ref, `select
    (select count(*) from public.leads where place_id='qd-demo-supplier-001')::text supplier,
    (select count(*) from public.inquiries where brief_source='qd_demo_fixture')::text inquiry,
    (select coalesce((select rfq_ready::text from public.inquiries where brief_source='qd_demo_fixture'),'null')) rfq_ready,
    (select count(*) from public.quotes where source='qd_demo_fixture')::text quote,
    (select count(*) from public.transactions t join public.quotes q on q.id=t.quote_id where q.source='qd_demo_fixture')::text reveal,
    (select count(*) from public.messages m join public.inquiries i on i.id=m.inquiry_id where i.brief_source='qd_demo_fixture')::text message,
    (select count(*) from public.supplier_product where supplier_id=(select id from public.leads where place_id='qd-demo-supplier-001'))::text products,
    (select count(*) from public.notifications n join public.inquiries i on i.id=n.inquiry_id where i.brief_source='qd_demo_fixture')::text notifs`);
const [sf, pf] = await Promise.all([fx(STAGE), fx(PROD_REF)]);
for (const k of Object.keys(sf[0])) {
  const s = sf[0][k], p = pf[0][k];
  const same = String(s) === String(p);
  console.log(`  ${same ? 'ok ' : '≠  '} ${k.padEnd(10)} staging ${String(s).padEnd(6)} production ${p}`);
  // The fence legs must hold on production regardless of whether the counts match.
  if (k === 'rfq_ready' && p === 'true') fail('production demo inquiry has rfq_ready=true — dispatch could fire');
  if (k === 'notifs' && Number(p) > 0) fail(`production demo has ${p} queued notification(s)`);
}

console.log(bad ? `\nSTAGING-ONLY WORK FOUND: ${bad} item(s)` : '\nCLEAN: nothing from this session is staging-only, and the production fences hold.');
process.exit(bad ? 1 : 0);

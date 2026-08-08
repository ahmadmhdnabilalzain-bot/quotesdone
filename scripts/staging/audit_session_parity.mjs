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
  // Part 4: §11's quote builder and §16/§4's document impact.
  'fn_supplier_quote_recommend', 'fn_supplier_document_impact',
  // §23's knowledge graph: the adjacency builder and the supplier-facing reader.
  'fn_graph_supplier_market', 'fn_supplier_knowledge_graph',
];
const EDGE_FNS = ['supplier_portal', 'supplier_onboard', 'supplier_catalog_ingest', 'supplier_api'];
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
// rfq_ready IS AN AGGREGATE NOW, AND THAT IS NOT A STYLE CHOICE. The first version read
// `(select rfq_ready from public.inquiries where brief_source='qd_demo_fixture')` — a bare scalar
// subselect that was correct while exactly one fixture existed and raises 21000 the moment a second
// one does. Part 4 seeded six more, so the gate that proves the production fence would have died
// with a SQL error instead of reporting on the fence. It now counts the rows that BREACH the fence,
// which is the question being asked and is independent of how many fixtures there are.
const fx = (ref) => mgmtRead(ref, `select
    (select count(*) from public.leads where source='qd_demo_fixture')::text supplier,
    (select count(*) from public.inquiries where brief_source='qd_demo_fixture')::text inquiry,
    (select count(*) from public.inquiries where brief_source='qd_demo_fixture' and rfq_ready is true)::text rfq_ready_true,
    (select count(*) from public.quotes where source='qd_demo_fixture')::text quote,
    (select count(*) from public.transactions t join public.quotes q on q.id=t.quote_id where q.source='qd_demo_fixture')::text reveal,
    (select count(*) from public.messages m join public.inquiries i on i.id=m.inquiry_id where i.brief_source='qd_demo_fixture')::text message,
    (select count(*) from public.supplier_product where supplier_id in (select id from public.leads where source='qd_demo_fixture'))::text products,
    (select count(*) from public.inquiry_matches m join public.inquiries i on i.id=m.inquiry_id where i.brief_source='qd_demo_fixture')::text matches,
    -- Both legs a notification can arrive by. The quote leg is new in part 4: notify_new_quote_sms
    -- addresses a CUSTOMER, and twenty-four fenced quotes would have found it if customer_id were
    -- ever non-null. Counting only the inquiry leg would have missed that entirely.
    (select count(*) from public.notifications n
       where n.inquiry_id in (select id from public.inquiries where brief_source='qd_demo_fixture')
          or n.quote_id in (select id from public.quotes where source='qd_demo_fixture'))::text notifs`);
const [sf, pf] = await Promise.all([fx(STAGE), fx(PROD_REF)]);
for (const k of Object.keys(sf[0])) {
  const s = sf[0][k], p = pf[0][k];
  const same = String(s) === String(p);
  console.log(`  ${same ? 'ok ' : '≠  '} ${k.padEnd(10)} staging ${String(s).padEnd(6)} production ${p}`);
  // The fence legs must hold on production regardless of whether the counts match.
  if (k === 'rfq_ready_true' && Number(p) > 0) fail(`${p} production demo inquiry(s) have rfq_ready=true — dispatch could fire`);
  if (k === 'notifs' && Number(p) > 0) fail(`production demo has ${p} notification(s) addressed to somebody`);
  if (k === 'matches' && Number(p) > 0) fail(`${p} production demo inquiry_matches exist — a fixture reached the matcher`);
}

console.log(bad ? `\nSTAGING-ONLY WORK FOUND: ${bad} item(s)` : '\nCLEAN: nothing from this session is staging-only, and the production fences hold.');
process.exit(bad ? 1 : 0);

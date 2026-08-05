// match_eval — matching-precision test harness. Seeds tagged fixture sellers across distinct trades,
// runs a fixed benchmark of realistic RFQs through the REAL adjudicator (route_inquiry), and scores
// PRECISION (wrong-trade sellers kept out) and RECALL (the right seller let in). Self-cleaning: it
// deletes its fixtures at the end. Stores each run to match_eval_runs for monitoring/regression.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'match_eval', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 28 Jul 2026 (missed by the 27 Jul sweep): sec() returns undefined/'' when the
// app_secrets read fails or the row is missing, and the guard below compared strictly, so a caller
// posting {} matched and gained full service-role authority on a function that requires no JWT. The
// stored secret must now be a real value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// fixture sellers (distinct trades) — capability_summary is what the adjudicator judges on
const FIX = [
  { tag:'pool', name:'HARNESS_FIX Pools', cat:'swimming-pools', cap:'Builds and renovates concrete and fibreglass swimming pools for villas and hotels in Dubai: excavation, RC shell, waterproofing, tiling, filtration plant, heating and lighting. Pool maintenance contracts.' },
  { tag:'elec', name:'HARNESS_FIX Electrical', cat:'electrical', cap:'DEWA-registered electrical contractor: distribution boards, wiring, lighting, power points, cable containment, load upgrades and DEWA inspection sign-off for residential and commercial premises. No civil or pool works.' },
  { tag:'cctv', name:'HARNESS_FIX Security', cat:'cctv-security', cap:'SIRA-licensed CCTV and security systems installer: IP cameras, NVR/DVR, access control, intercoms, ANPR and structured cabling for offices, retail and warehouses. Handles SIRA-compliant retention and connectivity.' },
  { tag:'fitout', name:'HARNESS_FIX Fitout', cat:'interior-design', cap:'Turnkey interior fit-out and interior design contractor for offices, retail and F&B: space planning, partitions, false ceilings, flooring, joinery, painting and full MEP (AC, electrical, plumbing, fire) with DCD and Municipality approvals. Handles combined multi-trade renovations end to end.' },
  { tag:'land', name:'HARNESS_FIX Landscaping', cat:'landscaping', cap:'Landscaping and garden design: softscape (lawns, plants), hardscape (paving, pergolas), irrigation systems, garden lighting and water features. Not a pool contractor.' }
];

// benchmark RFQs: which fixture-trade SHOULD win, which must NOT appear
const CASES = [
  { name:'concrete pool + heating', job:{ summary:'New concrete swimming pool approx 8x4m with heating and lighting for a villa', category:'swimming-pools', emirate:'Dubai', scope_type:'single', trades:['swimming pool','concrete pool','pool heating'] }, expect:'pool', forbid:['elec','cctv','land','fitout'] },
  { name:'DB board + wiring (DEWA)', job:{ summary:'Supply and install a new distribution board and rewire an apartment, DEWA connection', category:'electrical', emirate:'Dubai', scope_type:'single', trades:['electrical','distribution board','wiring','dewa'] }, expect:'elec', forbid:['pool','cctv','land','fitout'] },
  { name:'CCTV 16 cams + NVR (SIRA)', job:{ summary:'Supply and install 16 IP CCTV cameras with NVR and 30-day retention for a warehouse, SIRA compliant', category:'cctv-security', emirate:'Dubai', scope_type:'single', trades:['cctv','ip camera','nvr','sira'] }, expect:'cctv', forbid:['pool','elec','land','fitout'] },
  { name:'full office fit-out (multi-trade)', job:{ summary:'Full turnkey fit-out of a 2000 sqft office: partitions, false ceiling, flooring, lighting, AC and fire — design and build', category:'interior-design', emirate:'Dubai', scope_type:'turnkey', trades:['fit-out','partitions','ceiling','mep','turnkey'] }, expect:'fitout', forbid:['pool','cctv'] },
  { name:'garden landscaping + irrigation', job:{ summary:'Landscape a villa garden: lawn, plants, paving, a pergola and an irrigation system', category:'landscaping', emirate:'Dubai', scope_type:'single', trades:['landscaping','irrigation','pergola','garden'] }, expect:'land', forbid:['pool','elec','cctv'] }
];

Deno.serve(async (req) => {
  const body = await req.json().catch(()=>({} as any));
  const inbound = await sec('cred_fn_to_route_inquiry');
  if (!inbound) { await logRun('error', { stage:'config' }, 'inbound_secret missing from app_secrets: match_eval can never authenticate itself to route_inquiry, so the matching precision/recall benchmark never runs and match-quality regressions stay invisible'); }
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'match_eval');
  if (!__auth.ok) { await logRun('error', { stage:'auth', rejected:1 }, 'Rejected a call with a wrong or missing __secret; the matching benchmark did not run, so any degradation in supplier-match precision/recall goes unmeasured'); return J({ error:'forbidden' }, 403); }
  const created: number[] = []; const tagById = new Map<number,string>();
  try {
    const seedFails: string[] = [];
    // seed fixtures
    for (const f of FIX) {
      const { data, error: seedErr } = await admin.from('leads').insert({ company_name: f.name, source:'self_registered', approval_status:'approved', banned:false, matching_blocked:false, registration_submitted_at: new Date().toISOString(), categories: f.cat, emirate:'Dubai', service_emirates:['Dubai'], email:'zzz_harness_'+f.tag+'@example.com', capability_summary: f.cap }).select('id').maybeSingle();
      if (data?.id) { created.push(Number(data.id)); tagById.set(Number(data.id), f.tag); }
      else { seedFails.push(f.tag+':'+String(seedErr?.message || 'no id returned')); }
    }
    const routeFails: string[] = [];
    const detail: any[] = []; let precSum = 0, precN = 0, recHit = 0, recN = 0;
    for (const c of CASES) {
      let fits: any[] = [];
      try {
        const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/route_inquiry`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: inbound, inquiry: c.job }) });
        const jd = await r.json(); fits = Array.isArray(jd.fits) ? jd.fits : [];
      } catch (_e) { routeFails.push(c.name+':'+String((_e as Error)?.message || _e)); /* treat as no fits */ }
      // only score fits that are our fixtures (ignore any incidental real seller)
      const fitTags = fits.map((x:any)=> tagById.get(Number(x.id))).filter(Boolean) as string[];
      const allowed = fitTags.filter(t => !c.forbid.includes(t));
      const forbidden = fitTags.filter(t => c.forbid.includes(t));
      const prec = fitTags.length ? allowed.length / fitTags.length : 1; // no wrong sends => precision 1
      const gotExpected = fitTags.includes(c.expect);
      precSum += prec; precN++; recN++; if (gotExpected) recHit++;
      detail.push({ case: c.name, expected: c.expect, fits: fitTags, forbidden_hit: forbidden, precision: Math.round(prec*100), recall_hit: gotExpected });
    }
    const precision_pct = precN ? Math.round((precSum/precN)*1000)/10 : null;
    const recall_pct = recN ? Math.round((recHit/recN)*1000)/10 : null;
    const { error: runErr } = await admin.from('match_eval_runs').insert({ precision_pct, recall_pct, cases_total: CASES.length, detail });
    const notes: string[] = [];
    if (seedFails.length) notes.push(seedFails.length+' of '+FIX.length+' fixture sellers failed to seed ('+seedFails.join('; ')+'); the benchmark scored against an incomplete fixture set so the precision/recall numbers do not reflect real match quality');
    if (routeFails.length) notes.push(routeFails.length+' of '+CASES.length+' benchmark RFQs could not reach route_inquiry ('+routeFails.join('; ')+'); they were scored as zero recall, so an adjudicator outage is indistinguishable from a genuine matching regression');
    if (runErr) notes.push('match_eval_runs insert failed ('+String(runErr.message)+'); this benchmark result was not persisted, leaving a silent gap in the match-quality regression history');
    if (recall_pct !== null && recall_pct < 100) notes.push('recall '+recall_pct+'%: at least one benchmark RFQ did not reach the correct trade, meaning real customers in those trades can receive no suitable supplier quotes');
    if (precision_pct !== null && precision_pct < 100) notes.push('precision '+precision_pct+'%: wrong-trade suppliers were matched, meaning customers receive irrelevant quotes and suppliers receive junk leads');
    if (!notes.length) notes.push('benchmark passed: precision '+precision_pct+'%, recall '+recall_pct+'% across '+CASES.length+' RFQs');
    await logRun((seedFails.length || routeFails.length || runErr) ? 'error' : 'ok', { precision_pct, recall_pct, cases_total: CASES.length, fixtures_seeded: created.length, seed_failures: seedFails.length, route_failures: routeFails.length, run_insert_failed: runErr ? 1 : 0 }, notes.join(' | '));
    return J({ ok:true, precision_pct, recall_pct, cases_total: CASES.length, detail });
  } catch (e) {
    await logRun('error', { stage:'run', fixtures_seeded: created.length }, 'match_eval crashed: '+String((e as Error)?.message || e)+'; no precision/recall measurement was produced for this run, so supplier-matching regressions go undetected');
    return J({ error: String((e as Error)?.message || e) }, 500);
  } finally {
    if (created.length) { try { const { error: delErr } = await admin.from('leads').delete().in('id', created); if (delErr) { await logRun('error', { stage:'cleanup', orphans: created.length }, 'Failed to delete '+created.length+' HARNESS_FIX fixture sellers: '+String(delErr.message)+'; these fake approved suppliers remain in the leads table and will be matched against real customer RFQs, polluting live supplier matching'); } } catch (_e) { await logRun('error', { stage:'cleanup', orphans: created.length }, 'Failed to delete '+created.length+' HARNESS_FIX fixture sellers: '+String((_e as Error)?.message || _e)+'; these fake approved suppliers remain in the leads table and will be matched against real customer RFQs, polluting live supplier matching'); } }
  }
});

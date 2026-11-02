// PROVE §11, §14 AND §24 OVER HTTPS: the builder proposes terms, the market reads its demand half,
// and the settings screen round-trips a preference.
//
//   node scripts/staging/prove_quote_builder.mjs <ref>
//
// ── WHAT THIS IS ACTUALLY TESTING, AS OPPOSED TO WHAT IT LOOKS LIKE IT IS TESTING ───────────────
// Not "does the endpoint answer 200". Three specific claims that would each be a silent lie:
//
//  1. The recommended price is the MEDIAN OF THE COMPETING BIDS ON THIS ENQUIRY, so the assertion
//     recomputes that median from the raw quote rows and demands the endpoint agree exactly. A
//     recommendation drifting to a category average would still answer 200 and still look like a
//     price, and this is the only check that can tell the difference.
//
//  2. An enquiry nobody else has priced must return available:false. A builder that falls back to
//     "some other project's number" when it has nothing to say is worse than one that says nothing.
//
//  3. Demo rows must be invisible to a real supplier. The competitor count for a live HVAC lead is
//     recomputed from leads and must EXCLUDE the six fixtures. This is the fence that protects a
//     real supplier's numbers, and it is the one no amount of reading the source can confirm.
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { pickApiKey } from '../lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

const ref = process.argv[2];
if (!ref) { console.error('usage: prove_quote_builder.mjs <ref>'); process.exit(2); }
const token = supabaseAccessToken();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
// RETRY, AND NEVER LET A TRANSPORT FAILURE BE READ AS A FACT ABOUT THE DATA. The first version was
// a bare fetch whose result was indexed straight into (`?.[0]?.claimed_by`), so a 429 from the
// management API — which is routine while a full blueprint scan is running against the same
// project — surfaced as "demo supplier has no claimed_by". That is a rate limit wearing the costume
// of a missing row, and it is the same defect class as a swallowed write looking like an unused
// feature. A non-array response now throws with the body attached.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sql = async (query, attempt = 0) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST', headers: H, body: JSON.stringify({ query }),
  });
  const body = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  management API ${r.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await sleep(wait);
    return sql(query, attempt + 1);
  }
  if (!r.ok) throw new Error(`management API ${r.status}: ${body.slice(0, 300)}`);
  const j = JSON.parse(body);
  if (!Array.isArray(j)) throw new Error(`management API returned a non-array: ${body.slice(0, 300)}`);
  return j;
};

const keys = await (await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: H })).json();
const ANON = pickApiKey(keys, 'publishable');
const SERVICE = pickApiKey(keys, 'secret');
const BASE = `https://${ref}.supabase.co`;
const svc = { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' };

const email = (await sql(`select claimed_by from public.leads where place_id='qd-demo-supplier-001'`))?.[0]?.claimed_by;
if (!email) { console.error('demo supplier has no claimed_by'); process.exit(1); }

// The two enquiries this run needs: one the others have bid on, one nobody has.
const inqs = await sql(`
  select i.id::text id, i.summary,
         (select count(*) from public.quotes q where q.inquiry_id = i.id
            and q.supplier_id <> (select id from public.leads where place_id='qd-demo-supplier-001'))::int others
  from public.inquiries i where i.brief_source='qd_demo_fixture' order by others desc`);
const contested = inqs.find((x) => x.others > 0);
const untouched = inqs.find((x) => x.others === 0);
if (!contested) { console.error('no demo enquiry has competing bids; run scripts/sql/demo_market_row5.sql'); process.exit(1); }

// The median recomputed OUTSIDE the routine, from the rows, so agreement means something.
const expected = (await sql(`
  select round(percentile_cont(0.5) within group (order by q.quote_amount))::text mid,
         count(*)::int n
  from public.quotes q
  where q.inquiry_id = '${contested.id}'
    and q.supplier_id <> (select id from public.leads where place_id='qd-demo-supplier-001')
    and q.quote_amount > 0`))[0];

// The live competitor count, recomputed excluding fixtures.
const livePeers = (await sql(`
  with me as (select * from public.leads where sector='hvac' and coalesce(source,'') <> 'qd_demo_fixture' order by id limit 1)
  select (select id from me)::text lead_id,
         (select count(*) from public.leads l, me where l.id <> me.id and l.sector = me.sector
            and coalesce(l.permanently_closed,false)=false
            and coalesce(l.source,'') <> 'qd_demo_fixture')::int peers`))[0];

const list = await (await fetch(`${BASE}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`, { headers: svc })).json();
const pre = (list.users || []).find((u) => (u.email || '').toLowerCase() === email.toLowerCase());
const pw = 'Probe-' + Math.random().toString(36).slice(2) + 'A1!';
let userId = pre?.id || null, created = false;
const fails = [];

try {
  if (!userId) {
    const cu = await (await fetch(`${BASE}/auth/v1/admin/users`, { method: 'POST', headers: svc, body: JSON.stringify({ email, password: pw, email_confirm: true }) })).json();
    userId = cu.id; created = true;
    if (!userId) throw new Error('auth create failed');
  } else {
    await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'PUT', headers: svc, body: JSON.stringify({ password: pw }) });
  }
  const tok = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: pw }),
  })).json();
  if (!tok.access_token) throw new Error('no JWT');
  const post = async (fn, body) => {
    const r = await fetch(`${BASE}/functions/v1/${fn}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok.access_token },
      body: JSON.stringify(body),
    });
    return [r.status, await r.json()];
  };

  // ── 1. THE BUILDER ON A CONTESTED ENQUIRY ─────────────────────────────────────────────────────
  const [s1, d1] = await post('supplier_portal', { action: 'quote_recommend', inquiry_id: contested.id });
  console.log(`${ref}  POST supplier_portal{quote_recommend} -> ${s1}`);
  if (!d1.ok) { console.log('  NOT OK: ' + JSON.stringify(d1).slice(0, 300)); process.exit(1); }
  console.log(`  ${String(contested.summary).slice(0, 60)}…`);
  console.log(`  available=${d1.available}  population=${d1.population} (expected ${expected.n})`);
  console.log(`  price ${d1.recommended_price?.value} ${d1.recommended_price?.currency}  (independently computed median ${expected.mid})`);
  console.log(`  p25 ${d1.recommended_price?.p25}  p75 ${d1.recommended_price?.p75}  range ${d1.recommended_price?.low}–${d1.recommended_price?.high}`);
  console.log(`  position: ${d1.market_position?.verdict}  your_index=${d1.market_position?.your_index}`);
  console.log(`  delivery ${JSON.stringify(d1.delivery_estimate?.value)} consensus=${d1.delivery_estimate?.consensus}`);
  console.log(`  warranty ${JSON.stringify(d1.warranty?.value)} consensus=${d1.warranty?.consensus}`);
  console.log(`  risk ${d1.risk_level?.value} from ${d1.risk_level?.count} signal(s): ${(d1.risk_level?.signals || []).map((x) => x.signal).join(', ')}`);

  if (d1.available !== true) fails.push('a contested enquiry returned available:false');
  if (String(d1.recommended_price?.value) !== String(expected.mid))
    fails.push(`price ${d1.recommended_price?.value} is not the median of the competing bids (${expected.mid})`);
  if (Number(d1.population) !== Number(expected.n))
    fails.push(`population ${d1.population} disagrees with the ${expected.n} competing bid(s) on this enquiry`);
  for (const k of ['recommended_price', 'market_position', 'delivery_estimate', 'warranty', 'risk_level'])
    if (!d1[k]) fails.push(`§11 requires ${k} and the payload has none`);
  if (!(Number(d1.recommended_price?.low) <= Number(d1.recommended_price?.value)
     && Number(d1.recommended_price?.value) <= Number(d1.recommended_price?.high)))
    fails.push('the recommended price sits outside the range it was drawn from');
  // The delivery it proposes must be one a supplier actually offered, never a synthesised string.
  if (d1.delivery_estimate?.value && !(d1.delivery_estimate?.observed || []).includes(d1.delivery_estimate.value))
    fails.push('the proposed lead time is not one of the observed bids');

  // ── 2. AN ENQUIRY NOBODY ELSE HAS PRICED MUST REFUSE ──────────────────────────────────────────
  if (untouched) {
    const [, d2] = await post('supplier_portal', { action: 'quote_recommend', inquiry_id: untouched.id });
    console.log(`  uncontested enquiry -> available=${d2.available}  population=${d2.population}`);
    if (d2.available !== false) fails.push('an enquiry with no competing bids still produced a recommendation');
    if (!d2.note) fails.push('the refusal does not name why');
  }

  // ── 3. §14's DEMAND HALF ──────────────────────────────────────────────────────────────────────
  const [, d3] = await post('supplier_portal', { action: 'market' });
  console.log(`  market: population=${d3.population}  trend=${d3.demand_trend?.direction} ${d3.demand_trend?.value}` +
    `  top=${d3.most_requested?.value}  avg=${d3.avg_market_price?.value}`);
  for (const k of ['demand_trend', 'most_requested', 'avg_market_price'])
    if (d3[k]?.available !== true) fails.push(`§14 ${k} is still unavailable for the demo supplier`);
  // The percentage must stay null while the prior period is empty. This is the fabrication guard.
  if (d3.demand_trend?.prior === 0 && d3.demand_trend?.pct !== null)
    fails.push('a percentage was produced from a base of zero');

  // ── 4. THE FENCE: A REAL SUPPLIER'S COMPETITOR COUNT MUST EXCLUDE THE FIXTURES ─────────────────
  const asLive = (await sql(`select (public.fn_supplier_market(${livePeers.lead_id})->'competitors'->>'total')::int t`))[0];
  console.log(`  live lead ${livePeers.lead_id}: routine says ${asLive.t} competitor(s), rows say ${livePeers.peers} excluding fixtures`);
  if (Number(asLive.t) !== Number(livePeers.peers))
    fails.push(`a real supplier's competitor count (${asLive.t}) includes demo fixtures (should be ${livePeers.peers})`);

  // ── 4b. §16 §4 — WHAT THE MISSING DOCUMENT IS COSTING, AS A COUNT THAT MATCHES THE ROWS ───────
  // The upside figure is what §4's assistant quotes at the supplier, so it has to be a real count
  // of real open enquiries. Recomputed here from inquiries, exactly as the competitor count was.
  const openInTrade = (await sql(`
    with me as (select * from public.leads where place_id='qd-demo-supplier-001')
    select count(*)::int n from public.inquiries i, me
    where i.status='open' and i.category = me.sector and i.brief_source='qd_demo_fixture'`))[0].n;
  const [, d4] = await post('supplier_portal', { action: 'document_impact' });
  const lic = (d4.documents || []).find((x) => x.key === 'trade_licence');
  console.log(`  documents: open_in_my_trade=${d4.open_in_my_trade} (rows say ${openInTrade}); ` +
    `licence on_file=${lic?.on_file} would_unlock=${lic?.would_unlock}`);
  if (Number(d4.open_in_my_trade) !== Number(openInTrade))
    fails.push(`open_in_my_trade ${d4.open_in_my_trade} disagrees with the ${openInTrade} open enquiries in this trade`);
  if (lic?.on_file === false && Number(lic?.would_unlock) !== Number(openInTrade))
    fails.push('a missing licence does not report the open enquiries it is blocking');
  // A document that is genuinely in force must claim nothing further, or the screen becomes an
  // advert for uploading things the supplier has already uploaded.
  for (const x of (d4.documents || []))
    if (x.on_file && !x.expired && Number(x.would_unlock) !== 0)
      fails.push(`${x.key} is on file and in force but still claims to unlock ${x.would_unlock}`);

  // ── 5. §24 SETTINGS ROUND-TRIP ────────────────────────────────────────────────────────────────
  const [, before] = await post('supplier_api', { action: 'settings' });
  const flipped = !before.settings?.wa_optin;
  await post('supplier_api', { action: 'save_settings', wa_optin: flipped });
  const [, after] = await post('supplier_api', { action: 'settings' });
  console.log(`  settings wa_optin ${before.settings?.wa_optin} -> ${after.settings?.wa_optin} (asked for ${flipped})`);
  if (after.settings?.wa_optin !== flipped) fails.push('save_settings did not persist wa_optin');
  // Restore, so a proof run leaves no state behind.
  await post('supplier_api', { action: 'save_settings', wa_optin: !!before.settings?.wa_optin });
  // And the allowlist must hold: a profile column offered here must be ignored. (Until 21 Sep 2026 this
  // posted bank_iban; that column was dropped with the founder's bank-details removal, instruction 527.)
  const eidBefore = (await sql(`select coalesce(emirates_id,'-') v from public.leads where place_id='qd-demo-supplier-001'`))[0].v;
  await post('supplier_api', { action: 'save_settings', emirates_id: '784-0000-0000000-0' });
  const eidAfter = (await sql(`select coalesce(emirates_id,'-') v from public.leads where place_id='qd-demo-supplier-001'`))[0].v;
  console.log(`  emirates_id after a settings post that tried to set it: unchanged=${eidBefore === eidAfter}`);
  if (eidAfter !== eidBefore) fails.push('save_settings wrote a column outside its allowlist');

  if (fails.length) { console.log('\nFAILED:'); fails.forEach((f) => console.log('  - ' + f)); process.exit(1); }
  console.log('\nPASS: the price is the recomputed median, an unpriced enquiry is refused, the demand half is live, '
    + 'the demo fence holds against a real lead, and settings persist within their allowlist.');
} finally {
  if (created && userId) await fetch(`${BASE}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: svc }).catch(() => {});
}

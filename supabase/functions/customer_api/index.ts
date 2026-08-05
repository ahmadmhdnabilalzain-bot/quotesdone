import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD, SAFE_CAD } from '../_shared/attachment.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const INQUIRY_LIMIT_PER_HOUR = 20;
const PDF_LIMIT_PER_HOUR = 40;
// Anonymised quote labels must stay alphabetic beyond 26 quotes. String.fromCharCode(65 + i)
// emits '[', '\\', ']' from the 27th, so a customer with 30 quotes saw "Supplier [" and the
// comparison report referenced a label that did not exist in their list.
function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }
async function signedFile(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('quote-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
async function signedDrawing(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('drawing-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }
async function signedDoc(bucket: string | null | undefined, path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from(bucket || 'agent-docs').createSignedUrl(path, 7 * 24 * 3600); return data?.signedUrl || null; } catch { return null; } }
async function getSecret(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function b64ToBytes(b64: string): Uint8Array { const raw = atob(String(b64).replace(/^data:[^;]+;base64,/, '')); const arr = new Uint8Array(raw.length); for (let i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i); return arr; }

const KW: Record<string, string[]> = {
  flooring: ['floor', 'flooring', 'spc', 'vinyl', 'lvt', 'parquet', 'laminate', 'epoxy', 'tile', 'tiles', 'marble', 'granite', 'carpet'], glass: ['glass', 'glazing', 'mirror', 'shower enclosure', 'partition', 'facade', 'curtain wall', 'window'], aluminium: ['aluminium', 'aluminum', 'pergola', 'cladding', 'composite panel', 'window frame'], steel: ['steel', 'metal', 'fabrication', 'welding', 'staircase', 'railing', 'gate', 'structure'], acrylic: ['acrylic', 'plexiglass', 'perspex', 'display stand'], carpentry: ['carpentry', 'wood', 'joinery', 'wardrobe', 'cabinet', 'kitchen', 'furniture', 'door'], gypsum: ['gypsum', 'false ceiling', 'drywall', 'partition wall', 'ceiling'], signage: ['sign', 'signage', '3d letters', 'lightbox', 'led sign', 'billboard', 'sticker', 'branding'], wallpaper: ['wallpaper', 'wall covering'], upholstery: ['upholstery', 'sofa', 'curtain', 'blinds', 'cushion', 'reupholster'], fitout: ['fitout', 'fit-out', 'fit out', 'interior', 'renovation', 'refurbish', 'turnkey', 'decoration'], painting: ['paint', 'painting', 'varnish', 'coating'], landscaping: ['landscaping', 'garden', 'grass', 'artificial grass', 'irrigation', 'swimming pool', 'pool'], scaffolding: ['scaffolding', 'scaffold', 'formwork'], security: ['cctv', 'camera', 'access control', 'intercom', 'alarm', 'security system', 'gate barrier'], safety: ['safety', 'ppe', 'fire extinguisher', 'fire alarm', 'first aid', 'helmet'],
};
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
function detect(text: string) {
  const t = ' ' + String(text || '').toLowerCase() + ' ';
  let best: string | null = null, bestN = 0;
  for (const [c, kws] of Object.entries(KW)) { let n = 0; for (const k of kws) if (t.includes(k)) n++; if (n > bestN) { bestN = n; best = c; } }
  let em: string | null = null;
  for (const e of EMIRATES) { if (t.includes(e.toLowerCase())) { em = e; break; } }
  if (!em && t.includes('abudhabi')) em = 'Abu Dhabi'; if (!em && / rak /.test(t)) em = 'Ras Al Khaimah';
  return { category: best, emirate: em, keywords: best ? KW[best].filter((k) => t.includes(k)) : [] };
}
function labelize(s: string): string { return String(s || '').replace(/[-_]/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase()); }
// 29 Jul 2026 - ANONYMITY. The scrubber lived only in supplier_api's portal READ path, so every
// write path out of here shipped the customer's raw words straight to suppliers: the new-inquiry
// email, its WhatsApp clone via fn_wa_fanout, and the job_awarded_other notice. A customer typing
// "villa fit-out for Ahmed Khan, call 050 123 4567" had that emailed verbatim to up to eight
// suppliers before anyone paid a reveal fee, which is the entire business model inverted. Anything
// leaving this function toward a supplier goes through scrubIdentity first.
const CO_SUFFIX = '(?:l\\.?\\s?l\\.?\\s?c\\.?|fz-?llc|fzc|fze|trading|contracting|establishment|est\\.?|general|co\\.?|company|group)';
const ID_PATTERNS: RegExp[] = [
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g,
  /(?:https?:\/\/|www\.)[^\s,;)\]]+/gi,
  /\b[A-Za-z0-9-]{2,}\.(?:ae|com|net|org|co|io|me|biz|info)(?:\.[A-Za-z]{2})?\b/gi,
  /\+\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b00\s?971[\s.-]?\d(?:[\s.-]?\d){6,10}/g,
  /\b0\d(?:[\s.-]?\d){7,8}\b/g,
];
const rxEsc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function companyRe(name: unknown): RegExp | null {
  const base = String(name || '').replace(new RegExp('\\b' + CO_SUFFIX, 'gi'), ' ').replace(/[^A-Za-z0-9؀-ۿ ]+/g, ' ').trim();
  const words = base.split(/\s+/).filter((w) => w.length > 1).map(rxEsc);
  if (!words.length || base.replace(/\s+/g, '').length < 3) return null;
  try { return new RegExp('\\b' + words.join('[\\s.,_-]*') + '(?:[\\s.,_-]*' + CO_SUFFIX + ')*', 'gi'); } catch (_e) { return null; }
}
function scrubIdentity(text: string | null, ownName: unknown, hits: string[]): string | null {
  if (text == null) return text;
  let out = String(text);
  const nameRe = companyRe(ownName);
  // Contact patterns run BEFORE the company-name pattern on purpose: "www.alnoor.ae" must be
  // taken out whole as a URL, otherwise the name pattern eats "alnoor" first and leaves a
  // half-redacted "www.[removed].ae" that still points at the supplier.
  for (const re of (nameRe ? [...ID_PATTERNS, nameRe] : ID_PATTERNS)) {
    out = out.replace(re, (m: string) => { const t = String(m).trim(); if (t.length < 3) return m; if (!hits.includes(t)) hits.push(t); return '[removed]'; });
  }
  return out;
}
async function queueNotifications(rows: Record<string, unknown>[]) { try { if (rows.length) await admin.from('notifications').insert(rows); } catch (_e) { /* */ } }
// AUDIT 1.5 (4 Aug 2026) -----------------------------------------------------------------------
// Both supplier-facing emails in this file passed ownName = null to scrubIdentity. companyRe(null)
// returns null, so the buyer's name pattern was never added to the loop and only ID_PATTERNS ran -
// emails, URLs, messenger links and UAE numbers. The buyer's NAME went out verbatim, pre-reveal, to
// every matched supplier. The portal has always done this correctly: supplier_api resolves
// buyerName from inquiries.customer_id -> customers.full_name and passes it into the identical
// scrubIdentity. The email was the one supplier-facing surface where the name survived.
//
// The database is not a backstop for this. mask_contacts() removes contact strings and leaves names
// - verified on production:
//   select public.mask_contacts('Villa fit-out for Ahmed Khan, call 0501234567 or a@b.com');
//     -> 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]'
//
// FAIL CLOSED. `resolved:false` means the owner lookup itself failed, which is NOT the same as "this
// inquiry has no customer name on record". We cannot scrub a name we could not read, so callers
// must drop the customer-authored text entirely rather than emit it unscrubbed. Returning null on a
// failed read would have re-created the exact defect this comment describes.
//
// The name exists only to feed the scrubber and is never placed on a response.
type BuyerName = { resolved: true; name: string | null } | { resolved: false };
async function buyerNameOf(inquiryId: string): Promise<BuyerName> {
  try {
    const { data: inq, error: e1 } = await admin.from('inquiries').select('customer_id').eq('id', inquiryId).maybeSingle();
    if (e1) return { resolved: false };
    const cid = inq?.customer_id;
    if (!cid) return { resolved: true, name: null };   // genuinely no owner recorded - nothing to scrub
    const { data: c, error: e2 } = await admin.from('customers').select('full_name').eq('id', cid).maybeSingle();
    if (e2) return { resolved: false };
    const n = String(c?.full_name || '').trim();
    // scrubIdentity/companyRe already refuse anything under 3 characters; matching that here keeps
    // "we found a name" and "the scrubber will act on it" the same statement.
    return { resolved: true, name: n.length >= 3 ? n : null };
  } catch (_e) { return { resolved: false }; }
}
async function notifyLosers(inquiryId: string, summary: string | null, winnerId: number | null) {
  try {
    let qb = admin.from('quotes').select('supplier_id').eq('inquiry_id', inquiryId);
    if (winnerId) qb = qb.neq('supplier_id', winnerId);
    const { data: others } = await qb;
    const ids = [...new Set((others || []).map((o: any) => Number(o.supplier_id)).filter(Boolean))];
    if (!ids.length) return;
    const { data: ls } = await admin.from('leads').select('id,email,company_name').in('id', ids);
    // AUDIT 1.5: the losing suppliers never paid for a reveal, so this is a pre-reveal surface even
    // though it is sent after the award. If the owner could not be read we quote nothing back at
    // them - the generic phrase below is already the correct fallback.
    const bn = await buyerNameOf(inquiryId);
    const scrubbedJob = (bn.resolved && summary && summary.trim()) ? (scrubIdentity(summary.trim(), bn.name, []) || '') : '';
    const job = scrubbedJob ? '“' + scrubbedJob + '”' : 'a recent job you quoted';
    const rows = (ls || []).filter((s: any) => s.email && /@/.test(s.email)).map((s: any) => ({
      type: 'job_awarded_other', to_email: s.email, to_role: 'supplier', lead_id: s.id, inquiry_id: inquiryId,
      subject: 'Update on a job you quoted — QuotesDone',
      body: 'Thank you for taking the time to quote on ' + job + '. On this occasion the customer has chosen to proceed with another supplier. We genuinely appreciate the effort you put into your quote, and it was great having you compete for the work. New matching opportunities come through QuotesDone regularly — please keep an eye on your supplier inbox, and we wish you the very best of luck on the next one.'
    }));
    await queueNotifications(rows);
  } catch (_e) { /* */ }
}
// A customer request that reaches NOBODY is revenue loss and a supply-coverage gap.
// dispatch_inquiry already flags this; create_inquiry's own matching path used to return
// matches:0 silently, so the customer saw "Request sent" and waited for quotes that could
// never arrive, and nothing landed in the action queue. Both paths now behave the same.
async function flagCoverageGap(inqId: string, category: string, emirate: string | null, summary: string) {
  const label = (category || 'uncategorised') + ' / ' + (emirate || 'UAE');
  let flagged = true;
  try {
    await admin.from('agent_actions').insert({
      agent: 'operations_ai', kind: 'coverage_gap', status: 'pending', risk: 'medium',
      title: 'RFQ had no matchable supplier' + (category ? (': ' + category) : ''),
      recommendation: 'A customer request (' + label + ') matched ZERO suppliers, so it reached nobody and cannot receive quotes. This is a supply-coverage gap: consider acquiring or onboarding suppliers in this trade and emirate. No supplier was contacted.',
      detail: { signal: 'coverage_gap:' + inqId, inquiry_id: inqId, category, emirate, summary: String(summary || '').slice(0, 300), path: 'create_inquiry' },
      target_table: 'inquiries', target_id: inqId });
  } catch (_e) { flagged = false; }
  try { await admin.from('founder_alerts').insert({ level: 'high', event: 'rfq_no_supplier', detail: ('A customer request (' + label + ', inquiry ' + inqId + ') matched zero suppliers and reached nobody.' + (flagged ? '' : ' The coverage_gap flag ALSO failed to insert, so this gap is not in the action queue.')).slice(0, 900), channel: 'email' }); } catch (_e) { /* */ }
  try {
    const owner = ((await getSecret('admin_emails')) || 'management@quotesdone.com').split(',')[0].trim();
    await queueNotifications([{ type: 'rfq_no_supplier', to_email: owner, to_role: 'admin', inquiry_id: inqId, channel: 'email', status: 'queued',
      subject: 'Customer request reached no suppliers: ' + label,
      body: 'A customer posted a request (' + label + ') and it matched ZERO suppliers, so no one was contacted and no quote can arrive.\n\nInquiry: ' + inqId + '\nSummary: ' + String(summary || '').slice(0, 300) + '\n\nThe customer is waiting. Onboard suppliers in this trade/emirate, or contact them directly.' }]);
  } catch (_e) { /* */ }
  return flagged;
}
async function matchAndNotify(inqId: string, opts: { category: string; emirate: string | null; keywords: string[]; summary: string; budget: string | null; extra: string; useRouter: boolean; multi: boolean }): Promise<{ matches: number; routing: Record<string, any> }> {
  const { category, emirate, keywords, summary, budget, extra, useRouter, multi } = opts;
  let fits: { id: number; company_name?: string; reason?: string }[] = [];
  let routing: Record<string, any> = {};
  let routerAnswered = false;
  if (useRouter) {
    try {
      const secret = await getSecret('cred_fn_customer_api');
      const rr = await fetch(`${SUPABASE_URL}/functions/v1/route_inquiry`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, inquiry_id: inqId }) });
      const rj = await rr.json();
      if (rj?.ok) { routerAnswered = true; routing = { job_type: rj.job_type, primary_trade: rj.primary_trade, reasoning: rj.reasoning, evaluated: rj.evaluated, note: rj.note || null, needs_detail: rj.needs_detail === true, missing: Array.isArray(rj.missing) ? rj.missing.slice(0, 6) : null, at: new Date().toISOString() }; fits = Array.isArray(rj.fits) ? rj.fits : []; }
      else routing = { error: rj?.error || 'route_failed', at: new Date().toISOString() };
    } catch (e) { routing = { error: String((e as Error)?.message || e), at: new Date().toISOString() }; }
  }
  // ROUTE_INQUIRY OVERRIDE (27 Jul 2026). This used to fall back to match_suppliers_kw whenever
  // fits was empty, INCLUDING when route_inquiry had answered successfully with zero fits. But
  // needs_detail (brief too thin), no_capability_match and no_registered_suppliers are the
  // router's genuine verdicts, not failures — it deliberately contacts nobody. Fanning the RFQ
  // out to 8 keyword-matched suppliers anyway threw the adjudication away, spammed suppliers who
  // cannot do the job, and made every negative verdict invisible. We now fall back ONLY when the
  // router genuinely did not answer: it was not used, it errored, or the response was missing.
  // A successful zero-fit answer is respected — coverage gap path, router's reason persisted.
  if (!useRouter || routing.error || !routerAnswered) {
    const { data: sups } = await admin.rpc('match_suppliers_kw', { p_keywords: keywords, p_category: category, p_emirate: emirate, p_limit: 8, p_multi: multi });
    fits = (sups || []).map((s: { id: number; company_name?: string }) => ({ id: s.id, company_name: s.company_name, reason: useRouter ? 'keyword fallback (router unavailable)' : (multi ? 'turnkey / combined match' : 'trade specialist match') }));
    if (useRouter) routing.fallback = true; else routing = { mode: multi ? 'turnkey' : 'trade', at: new Date().toISOString() };
  }
  if (routerAnswered && fits.length === 0) { routing.router_verdict = String(routing.note || (routing.needs_detail ? 'needs_detail' : 'adjudicated_no_fit')); routing.keyword_fallback_suppressed = true; }
  const fitIds = fits.map((f) => Number(f.id)).filter(Boolean);
  let supRows: Record<string, any>[] = [];
  if (fitIds.length) { const { data: ls } = await admin.from('leads').select('id,company_name,email').in('id', fitIds); supRows = ls || []; }
  const supById = new Map(supRows.map((s: any) => [Number(s.id), s]));
  const matchRows = fits.filter((f) => supById.has(Number(f.id))).map((f) => ({ inquiry_id: inqId, supplier_id: Number(f.id), similarity: null, match_reason: String(f.reason || '').slice(0, 400) }));
  if (matchRows.length) await admin.from('inquiry_matches').insert(matchRows);
  routing.outcome = matchRows.length ? 'dispatched' : 'no_fit';
  routing.fanout = matchRows.length;
  try { await admin.from('inquiries').update({ routing }).eq('id', inqId); } catch (_e) { /* */ }
  if (!matchRows.length) { routing.coverage_gap_flagged = await flagCoverageGap(inqId, category, emirate, summary); return { matches: 0, routing }; }
  // AUDIT 1.5. This is the first supplier-facing surface an inquiry ever reaches and it is entirely
  // pre-reveal. summary, budget and extra are customer free text; category and emirate are platform
  // values from a fixed list. If the owner could not be read, the free-text fields are dropped and
  // the supplier is told the trade and emirate only - enough to log in and look, nothing authored by
  // the buyer. A supplier who receives less detail can still quote; a buyer whose name was emailed
  // to eight strangers cannot be un-emailed.
  const bn = await buyerNameOf(inqId);
  const cust = (t: string | null | undefined) => (bn.resolved && t) ? (scrubIdentity(String(t), bn.name, []) || '') : '';
  const headline = cust(summary) || category;
  const notifs = matchRows.map((mr) => supById.get(Number(mr.supplier_id))).filter((s: any) => s && s.email && /@/.test(s.email)).map((s: any) => ({ type: 'new_inquiry', to_email: s.email, to_role: 'supplier', lead_id: s.id, inquiry_id: inqId, subject: 'New job request on QuotesDone', body: 'A customer is requesting quotes for: ' + headline + (emirate ? ' (' + emirate + ')' : '') + (cust(budget) ? ' — budget ' + cust(budget) : '') + '.' + cust(extra) + ' Log in to your QuotesDone supplier portal to quote.' }));
  await queueNotifications(notifs);
  return { matches: matchRows.length, routing };
}

type Cfg = { promo_until: string | null; promo_reveal_rate: number; promo_reveal_cap: number; standard_reveal_rate: number; standard_reveal_cap: number; refund_window_working_days: number };
async function getCfg(): Promise<Cfg> { const { data } = await admin.from('pricing_config').select('*').eq('id', 1).maybeSingle(); return (data as Cfg) || { promo_until: null, promo_reveal_rate: 0.02, promo_reveal_cap: 250, standard_reveal_rate: 0.02, standard_reveal_cap: 250, refund_window_working_days: 3 }; }
function revealFee(amount: number, cfg: Cfg, at: Date = new Date()): number { if (!amount || amount <= 0) return 0; const promo = !!cfg.promo_until && at <= new Date(cfg.promo_until); const rate = Number(promo ? cfg.promo_reveal_rate : cfg.standard_reveal_rate); const cap = Number(promo ? cfg.promo_reveal_cap : cfg.standard_reveal_cap); return Math.min(Math.round(amount * rate * 100) / 100, cap); }
function ratingOf(l: Record<string, any>) { const appN = Number(l.app_reviews || 0); if (appN > 0) return { value: l.app_rating != null ? Number(l.app_rating) : null, count: appN, source: 'QuotesDone' }; const g = l.rating ?? l.rating_maps; const gn = l.reviews ?? l.reviews_maps; return { value: g != null ? Number(g) : null, count: gn != null ? Number(gn) : 0, source: 'Google' }; }
function band(n: number) { n = Number(n || 0); if (n < 1000) return '< AED 1k'; if (n < 5000) return 'AED 1–5k'; if (n < 20000) return 'AED 5–20k'; if (n < 50000) return 'AED 20–50k'; return 'AED 50k+'; }
// PRE-REVEAL FINGERPRINT (27 Jul 2026). my_inquiries used to return the supplier's exact rating,
// exact review count, emirate, years-since-founding and win rate on EVERY quote, revealed or not.
// "4.6 stars, 23 reviews, Sharjah, trading since 2011" is a unique fingerprint: one Google Maps
// search finds the company, and the buyer contacts them directly without ever paying the reveal
// fee, which is the only transaction revenue this business has. Unrevealed quotes now carry
// coarse bands that fit hundreds of firms, plus the verified flag (a trust signal that identifies
// nobody). Emirate, win rate and rating source are withheld until a transaction exists.
function ratingBand(v: unknown): string | null { const n = Number(v); if (v == null || !isFinite(n) || n <= 0) return null; if (n >= 4.5) return '4.5+'; if (n >= 4) return '4.0-4.5'; if (n >= 3.5) return '3.5-4.0'; return 'below 3.5'; }
function reviewCountBand(v: unknown): string { const n = Number(v || 0); if (n >= 50) return '50+'; if (n >= 20) return '20-49'; if (n >= 5) return '5-19'; return 'under 5'; }
function yearsBand(v: unknown): string | null { if (v == null) return null; const n = Number(v); if (!isFinite(n)) return null; if (n >= 10) return '10+ years'; if (n >= 5) return '5-9 years'; return 'under 5 years'; }

// AUDIT 9.1 (3 Aug 2026). This is the least trusted input in the system: the customer drawing
// path. Whatever lands here is later rendered, passed to an LLM, and shown to suppliers. It
// previously took the caller's declared Content-Type and the caller's filename at face value and
// checked nothing but the byte length - so an HTML document, an SVG carrying script, or a PDF with
// an embedded /Launch action all stored cleanly as "a drawing". It also stored phone photos with
// their EXIF intact, which on an anonymous marketplace means the supplier receives the customer's
// GPS coordinates attached to the "masked" site photo.
async function storeOriginal(custId: string, name: string, mime: string, b64: string): Promise<string | null> {
  try {
    // 5 Aug 2026. The allow-list was SAFE_UPLOAD (PDF + jpeg/png/webp), which excludes CAD - on the
    // one path in the system that explicitly SUPPORTS CAD. analyze_drawing detects .dwg/.dxf and
    // routes it through cad_convert to get page images, so the drawing was converted, read and
    // turned into a BOQ, while storeOriginal rejected the original and returned null behind a
    // console.warn. The customer saw a successful upload; the inquiry got no drawing_file_path, so
    // the actual CAD file the supplier needs to quote from was gone and nothing reported it.
    // SAFE_CAD already exists for exactly this and was simply never wired to its only caller. The
    // sniffer validates both formats structurally (DWG by its AC10xx magic, ASCII DXF by its
    // SECTION/HEADER shape, and it prefers the dangerous reading on ambiguity), so this widens the
    // accepted set without trusting the caller's declared type.
    const s = sanitizeUpload({ input: b64, declaredMime: mime, filename: name, allow: [...SAFE_UPLOAD, ...SAFE_CAD], maxBytes: 25 * 1024 * 1024 });
    if (!s.ok) {
      console.warn(`[9.1] drawing rejected: ${s.error} - ${s.detail}${s.mime ? ` (sniffed ${s.mime}, declared ${mime})` : ''}`);
      return null;
    }
    if (s.declaredMismatch) console.warn(`[9.1] drawing declared ${mime} but is ${s.mime}; stored as ${s.mime}`);
    const path = `drawings/${custId}/${Date.now()}_${safeFilename(name, s.mime)}`;
    const up = await admin.storage.from('drawing-files').upload(path, s.bytes, { contentType: s.mime, upsert: false });
    // The sanitizer's rejection is logged above but the STORAGE rejection was not, and the bucket
    // carries its own allowed_mime_types. A CAD upload was therefore refused twice, silently, and
    // both layers returned the same null: the caller could not tell "we would not accept this" from
    // "the bucket would not accept this" from "the network failed".
    if (up.error) { console.warn(`[9.1] drawing accepted by the sanitizer as ${s.mime} but REJECTED by storage: ${up.error.message}`); return null; }
    return path;
  } catch { return null; }
}
async function translateQuoteAr(q: any): Promise<any|null> {
  const key = await getSecret('cred_fn_customer_api'); if (!key) return null;
  const payload = { job_category:q.job_category||'', job_summary:q.job_summary||'', emirate:q.emirate||'', items:(q.items||[]).map((it:any)=>({desc:it.desc||'',unit:it.unit||''})), lead_time:q.lead_time||'', validity:q.validity||'', warranty:q.warranty||'', payment_terms:q.payment_terms||'', conditions:q.conditions||'', exclusions:q.exclusions||'', notes:q.notes||'', scope:q.scope||'' };
  const sys = 'You are a professional Arabic translator for UAE B2B construction and services quotations. Translate every string VALUE in the given JSON into clear, formal Modern Standard Arabic. Keep ALL numbers, measurements, dimensions, currency codes (AED), percentages, dates and Latin brand/model codes EXACTLY as they are. Translate the emirate name to Arabic. Return ONLY a valid JSON object with the SAME keys and structure (items is an array of {desc,unit}); no commentary, no code fences.';
  {
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/ai_gateway`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: key, fn:'customer_api', sys, input: JSON.stringify(payload), max:2200, temperature:0.2 }) });
      const jd = await r.json(); let c = jd?.content || ''; const m = c.match(/\{[\s\S]*\}/); if (m) c = m[0]; const t = JSON.parse(c);
      return { supplier_label:q.supplier_label, job_category:t.job_category||q.job_category, job_summary:t.job_summary||q.job_summary, emirate:t.emirate||q.emirate, items:(q.items||[]).map((it:any,i:number)=>({ desc:(t.items&&t.items[i]&&t.items[i].desc)||it.desc, qty:it.qty, unit:(t.items&&t.items[i]&&t.items[i].unit)||it.unit })), lead_time:t.lead_time||q.lead_time, validity:t.validity||q.validity, warranty:t.warranty||q.warranty, payment_terms:t.payment_terms||q.payment_terms, conditions:t.conditions||q.conditions, exclusions:t.exclusions||q.exclusions, notes:t.notes||q.notes, scope:t.scope||q.scope, total:q.total };
    } catch (_e) { /* fall through to null */ }
  }
  return null;
}
async function buildQuotePdf(q: any, inq: any, wantAr: boolean) {
  const { data: sibs } = await admin.from('quotes').select('id,quote_amount').eq('inquiry_id', q.inquiry_id).order('quote_amount', { ascending: true });
  const idx = (sibs || []).findIndex((s: any) => s.id === q.id); const letter = supplierLabel(idx >= 0 ? idx : 0);
  // The supplier's OWN priced breakdown lives in quote_items. This previously read
  // q.boq || q.line_items — neither is a column on quotes, so it was always undefined and
  // the quotation PDF silently fell back to the customer's requested BOQ instead.
  let items: { desc: string; qty: string; unit: string }[] = [];
  try {
    const { data: qi } = await admin.from('quote_items').select('line_no,description,qty,unit').eq('quote_id', String(q.id)).order('line_no', { ascending: true }).limit(60);
    items = (qi || []).map((b: any) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || '') })).filter((x: any) => x.desc);
  } catch (_e) { items = []; }
  if (!items.length && inq?.boq && Array.isArray((inq.boq as any).boq)) items = (inq.boq as any).boq.map((b: any) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || '') })).filter((x: any) => x.desc).slice(0, 40);
  const quote = { supplier_label: letter, job_category: inq?.category, job_summary: inq?.summary, emirate: inq?.emirate, items, scope: items.length ? String(q.scope || '') : String(q.scope || inq?.summary || ''), lead_time: q.lead_time, validity: q.validity, warranty: q.warranty, payment_terms: q.payment_terms, conditions: q.conditions, exclusions: q.exclusions, notes: q.notes, total: q.quote_amount };
  const ref = 'QD-' + String(q.inquiry_id || '').slice(0, 8).toUpperCase() + '-' + letter;
  const secret = await getSecret('cred_fn_customer_api');
  const payload: any = { __secret: secret, quote, lang: wantAr ? 'bi' : 'en', ref, name: ref };
  if (wantAr) { const quoteAr = await translateQuoteAr(quote); payload.quote_ar = quoteAr || quote; }
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  const j = await r.json();
  return { j, ref };
}
// The comparison report as a branded document, rendered by the same engine as the
// quotations so header band, logo, letterhead, gold rule and footer all match.
function clipCell(s: any, n: number) { const t = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; }
// The anonymised supplier brief as a branded document. Same engine as the quotations
// and the comparison report, so the customer sees exactly what left the building on
// QuotesDone letterhead instead of a browser print-out.
async function buildBriefPdf(inq: any, lang: string) {
  const ar = lang === 'ar';
  const T = (en: string, arx: string) => (ar ? arx : en);
  const blocks: any[] = [];
  const ref = 'QD-' + String(inq?.id || '').slice(0, 8).toUpperCase() + '-BRIEF';
  const kv: any[] = [
    [T('Reference', 'الرقم المرجعي'), ref],
    [T('Category', 'الفئة'), clipCell(inq?.category, 40) || '—'],
    [T('Emirate', 'الإمارة'), clipCell(inq?.emirate, 40) || '—'],
    [T('Budget', 'الميزانية'), clipCell(inq?.budget, 40) || '—'] ];
  if (Array.isArray(inq?.trades) && inq.trades.length) kv.push([T('Trades', 'التخصصات'), clipCell(inq.trades.join(', '), 80)]);
  blocks.push({ t: 'kv', pairs: kv });
  blocks.push({ t: 'h2', text: T('Scope', 'النطاق') });
  blocks.push({ t: 'p', text: String(inq?.summary || '—') });
  const spec = (inq?.spec && typeof inq.spec === 'object' && !Array.isArray(inq.spec)) ? inq.spec : null;
  if (spec) {
    const rows = Object.entries(spec)
      .filter(([, v]) => v != null && String(v).trim() !== '')
      .map(([k, v]) => [clipCell(String(k).replace(/_/g, ' '), 40), clipCell(Array.isArray(v) ? v.join(', ') : v, 160)]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Specification', 'المواصفات') });
      blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Detail', 'التفصيل')], rows, widths: [0.32, 0.68] });
    }
  }
  const boq = (inq?.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq : null;
  if (boq && boq.length) {
    const rows = boq.slice(0, 60)
      .map((b: any, i: number) => [String(i + 1), clipCell(b.description, 150), b.qty == null ? '' : String(b.qty), clipCell(b.unit, 12)])
      .filter((r: any) => r[1]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Bill of quantities', 'جدول الكميات') });
      blocks.push({ t: 'table', head: ['#', T('Description', 'الوصف'), T('Qty', 'الكمية'), T('Unit', 'الوحدة')], rows, widths: [0.07, 0.68, 0.12, 0.13] });
    }
  }
  if (inq?.drawing_file_name) blocks.push({ t: 'note', text: T('A drawing is attached to this request and is shared with matched suppliers: ', 'أُرفق مخطط بهذا الطلب ويُشارك مع المورّدين المطابقين: ') + clipCell(inq.drawing_file_name, 80) });
  blocks.push({ t: 'space', h: 6 });
  blocks.push({ t: 'note', text: T(
    'This is the anonymised brief QuotesDone sends to matched suppliers. The customer name, company and contact details are never included - suppliers quote on the scope alone, and contact details are exchanged only after the customer reveals a quote.',
    'هذا هو الملخّص المجهول الذي ترسله QuotesDone إلى المورّدين المطابقين. لا يتضمّن اسم العميل أو شركته أو بيانات التواصل — يقدّم المورّدون عروضهم بناءً على النطاق فقط، وتُتبادل بيانات التواصل فقط بعد أن يكشف العميل عن العرض.') });
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, title: T('Supplier brief', 'ملخّص المورّد'), ref, name: ref, lang: ar ? 'ar' : 'en', blocks, options: { letterhead: true } }) });
  const j = await r.json();
  return { j, ref };
}
async function buildComparePdf(a: any, inq: any, lang: string) {
  const ar = lang === 'ar';
  const T = (en: string, arx: string) => (ar ? arx : en);
  const money = (v: any) => (v == null || v === '') ? '—' : ('AED ' + Number(v).toLocaleString('en-AE', { maximumFractionDigits: 0 }));
  const arrOf = (x: any) => Array.isArray(x) ? x : [];
  const qs = arrOf(a.quotes);
  const blocks: any[] = [];
  blocks.push({ t: 'kv', pairs: [
    [T('Request', 'الطلب'), clipCell(inq?.summary, 120) || '—'],
    [T('Category', 'الفئة'), clipCell(inq?.category, 40) || '—'],
    [T('Emirate', 'الإمارة'), clipCell(inq?.emirate, 40) || '—'],
    [T('Quotes evaluated', 'العروض المُقيّمة'), String(a.considered ?? a.total_quotes ?? qs.length)] ] });
  if (a.bottom_line) { blocks.push({ t: 'h2', text: T('Bottom line', 'الخلاصة') }); blocks.push({ t: 'p', text: String(a.bottom_line) }); }
  if (a.overview) blocks.push({ t: 'p', text: String(a.overview) });
  if (a.shortlist_reason) blocks.push({ t: 'note', text: String(a.shortlist_reason) });
  if (arrOf(a.top3).length) {
    blocks.push({ t: 'h2', text: T('Recommended', 'التوصية') });
    blocks.push({ t: 'table', head: [T('#', '#'), T('Supplier', 'المورّد'), T('Why', 'السبب'), T('Catch', 'الاعتبار')],
      rows: arrOf(a.top3).map((r: any, i: number) => [String(r.rank ?? i + 1), clipCell(r.label, 24), clipCell(r.why, 220), clipCell(r.tradeoff, 160) || '—']),
      widths: [0.06, 0.16, 0.46, 0.32] });
  }
  if (qs.length) {
    blocks.push({ t: 'h2', text: T('Side by side', 'مقارنة جنبًا إلى جنب') });
    const rows: string[][] = [];
    const push = (label: string, get: (q: any) => string) => { const vals = qs.map(get); if (vals.some((v) => v && v !== '—')) rows.push([label, ...vals]); };
    push(T('Price', 'السعر'), (q) => money(q.price));
    push(T('Lead time', 'مدة التنفيذ'), (q) => clipCell(q.lead_time, 60) || '—');
    push(T('Warranty', 'الضمان'), (q) => clipCell(q.warranty, 60) || '—');
    push(T('Payment terms', 'شروط الدفع'), (q) => clipCell(q.payment_terms, 60) || '—');
    push(T('Valid for', 'مدة الصلاحية'), (q) => clipCell(q.validity, 40) || '—');
    push(T('What you get', 'ما ستحصل عليه'), (q) => clipCell(q.getting, 240) || '—');
    push(T('Included', 'مشمول'), (q) => clipCell(arrOf(q.includes).join('; '), 240) || '—');
    push(T('Not included', 'غير مشمول'), (q) => clipCell(arrOf(q.excludes).join('; '), 200) || '—');
    push(T('Missing from your request', 'ناقص مما طلبت'), (q) => clipCell(arrOf(q.missing_from_request).join('; '), 200) || '—');
    push(T('Differs from your spec', 'اختلاف عن مواصفاتك'), (q) => clipCell(arrOf(q.spec_deviation).join('; '), 200) || '—');
    push(T('Track record', 'سجل الأداء'), (q) => clipCell(q.track_record_note, 180) || '—');
    push(T('Watch out', 'تنبيهات'), (q) => clipCell(arrOf(q.flags).join('; '), 200) || '—');
    const colW = 0.76 / Math.max(1, qs.length);
    blocks.push({ t: 'table', head: [T('Compare', 'المقارنة'), ...qs.map((q: any) => clipCell(q.label, 20))], rows, widths: [0.24, ...qs.map(() => colW)] });
  }
  if (arrOf(a.line_findings).length) {
    blocks.push({ t: 'h2', text: T('Line by line', 'بندًا بندًا') });
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Finding', 'الملاحظة')],
      rows: arrOf(a.line_findings).map((f: any) => [clipCell(f.item, 60), clipCell(f.finding, 300)]), widths: [0.28, 0.72] });
  }
  if (a.best_value_reason) { blocks.push({ t: 'h2', text: T('Why that pick', 'سبب الاختيار') }); blocks.push({ t: 'p', text: String(a.best_value_reason) }); }
  if (arrOf(a.watch_outs).length) { blocks.push({ t: 'h2', text: T('Watch out', 'انتبه') }); for (const w of arrOf(a.watch_outs)) blocks.push({ t: 'li', text: String(w) }); }
  if (a.advice) { blocks.push({ t: 'h2', text: T('Advice', 'النصيحة') }); blocks.push({ t: 'p', text: String(a.advice) }); }
  blocks.push({ t: 'space', h: 6 });
  blocks.push({ t: 'note', text: String(a.disclaimer || '') });
  const ref = 'QD-' + String(inq?.id || '').slice(0, 8).toUpperCase() + '-CMP';
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, title: T('Quote comparison report', 'تقرير مقارنة العروض'), ref, name: ref, lang: ar ? 'ar' : 'en', blocks, options: { letterhead: true } }) });
  const j = await r.json();
  return { j, ref };
}

// REDACTION PROVENANCE 2 Aug 2026 (external security review). WHY: QuotesDone sells anonymity —
// a supplier must not learn who the buyer is until the reveal fee is paid. supplier_api hands every
// matched supplier a SIGNED URL for each entry in inquiries.drawing_redacted_paths, and it will sign
// ANY object path in the 'drawing-files' bucket. The customer's ORIGINAL, unredacted upload sits in
// that SAME bucket at drawings/<customer_id>/<ts>_<name> (see storeOriginal above); redacted pages
// sit at redacted/<uuid>/page_pN.jpg. create_inquiry used to copy drawing.drawing_redacted_paths
// verbatim out of the REQUEST BODY, so a modified or simply buggy frontend could name the original —
// title block, client name, address, contacts, project number — and every matched supplier would get
// it for free, pre-reveal, destroying both the promise and the reveal-fee revenue behind it.
// Paths are no longer trusted from the client. drawing_redact records each run in
// public.drawing_redaction_runs (owner, outputs, pages_in/pages_out, status) and this resolver will
// only ever attach paths found in a run row that belongs to the CALLING customer. Anything else is
// REJECTED with an explicit error rather than silently dropped, so the frontend can surface it
// instead of quietly shipping a half-anonymous RFQ.
const REDACT_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type RedactResolve = { paths: string[] } | { err: Record<string, unknown>; status: number };
async function resolveRedactedPaths(custId: string, authUserId: string, drawing: any): Promise<RedactResolve> {
  const asked = Array.isArray(drawing?.drawing_redacted_paths) ? drawing.drawing_redacted_paths.map((s: any) => String(s)).slice(0, 24) : [];
  const jobIds = [
    ...(drawing?.redaction_job_id ? [String(drawing.redaction_job_id)] : []),
    ...(Array.isArray(drawing?.redaction_job_ids) ? drawing.redaction_job_ids.map((s: any) => String(s)) : []),
  ].filter((s) => REDACT_UUID_RE.test(s)).slice(0, 8);
  // Explicit opt-out: the buyer (or the UI, after a partial redaction) can choose to share no pages
  // at all. Sharing fewer pages never leaks anything, so this is always allowed.
  if (drawing?.share_redacted === false) return { paths: [] };
  if (!jobIds.length && !asked.length) return { paths: [] };
  // Reference photos go through attach_photos, which is authenticated as the same auth user but does
  // not know customers.id; drawing_redact stores the prefix it was called with, so those runs are
  // attributed by that instead. Both branches are server-side ownership checks — neither trusts a path.
  const photoRef = 'refphoto/' + String(authUserId || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 24) + '/';
  const { data: runs, error: rerr } = await admin.from('drawing_redaction_runs')
    .select('id,customer_id,caller_ref,output_paths,pages_in,pages_out,status')
    .or(`customer_id.eq.${custId},caller_ref.like.${photoRef}%`)
    .order('created_at', { ascending: false }).limit(60);
  if (rerr) return { err: { error: 'redaction_lookup_failed', message: 'We could not verify the redacted drawing pages just now. Please try again in a moment.' }, status: 503 };
  const mine = (runs || []).filter((r: any) => (r.customer_id && String(r.customer_id) === String(custId)) || (r.caller_ref && String(r.caller_ref).startsWith(photoRef)));
  const byId: Record<string, any> = {}; for (const r of mine) byId[String(r.id)] = r;
  const chosen: any[] = [];
  for (const jid of jobIds) {
    const r = byId[jid];
    if (!r) return { err: { error: 'redaction_job_not_found', message: 'That redaction job does not belong to your account or has expired. Please re-upload the drawing and try again.' }, status: 403 };
    chosen.push(r);
  }
  if (!jobIds.length) chosen.push(...mine);
  const allowed = new Set<string>();
  for (const r of chosen) for (const p of (r.output_paths || [])) allowed.add(String(p));
  let paths: string[];
  if (asked.length) {
    const bad = asked.filter((p: string) => !allowed.has(p));
    if (bad.length) return { err: { error: 'redacted_paths_unverified', rejected: bad.length, message: `${bad.length} of the attached drawing page(s) did not come from a redaction run on your account, so nothing was sent. Please re-run the drawing analysis and submit again.` }, status: 400 };
    paths = asked;
  } else {
    paths = Array.from(allowed);
  }
  // COMPLETENESS. A partial run (say 5 of 8 pages cleaned) must not quietly attach the 5 that
  // worked: the buyer believes the whole drawing was anonymised, and the 3 that failed are exactly
  // the pages the model was least sure about. Fail closed and name the number. A TOTAL failure still
  // behaves as before — no run outputs, no paths, and the inquiry goes out with no drawing attached.
  const used = chosen.filter((r: any) => (r.output_paths || []).some((p: any) => paths.includes(String(p))));
  let missing = 0; for (const r of used) missing += Math.max(0, Number(r.pages_in || 0) - Number(r.pages_out || 0));
  if (paths.length && missing > 0) {
    return { err: { error: 'redaction_incomplete', pages_missing: missing, message: `${missing} page(s) of your drawing could not be redacted, so no pages were shared. Please re-upload a clearer copy, or send the request without the drawing.` }, status: 409 };
  }
  return { paths };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || ''; const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    let { data: cust } = await admin.from('customers').select('*').eq('email', email).maybeSingle();
    if (!cust) { const ins = await admin.from('customers').insert({ email }).select('*').maybeSingle(); cust = ins.data; }
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');
    // BANNED CUSTOMER (27 Jul 2026). messages_api auto-bans a buyer who pushes contact details
    // off-platform (it writes customers.banned = true) but customer_api never read that column,
    // so the ban only ever closed the chat: the same person could still post RFQs, reveal
    // suppliers, request refunds and rate them from the main buyer surface. Every mutating
    // action is refused now. 'me' and 'my_inquiries' stay open on purpose so the person can
    // still see their own account state and existing requests rather than hitting a dead wall.
    const MUTATING = ['create_inquiry', 'edit_inquiry', 'reveal', 'request_refund', 'rate_supplier', 'complete_inquiry', 'cancel_inquiry'];
    if (cust?.banned === true && MUTATING.includes(action)) return J({ error: 'Your account is suspended. Please contact support@quotesdone.com if you believe this is a mistake.' }, 403);

    if (action === 'me') return J({ customer: cust });

    if (action === 'analyze_drawing') {
      let images: any[] = Array.isArray(body.images) ? body.images.slice(0, 10) : [];
      const name = String(body.drawing_file_name || 'drawing').slice(0, 180);
      const mime = String(body.mime || 'application/octet-stream');
      const hint = String(body.hint || '').slice(0, 400);
      const path = body.original_b64 ? await storeOriginal(cust.id, name, mime, String(body.original_b64)) : null;
      const secret = await getSecret('cred_fn_customer_api');
      const isCad = /\.(dwg|dxf)$/i.test(name) || /dwg|dxf|autocad|acad/i.test(mime);
      if (!images.length && isCad && body.original_b64) {
        try { const cr = await fetch(`${SUPABASE_URL}/functions/v1/cad_convert`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, b64: body.original_b64, filename: name }) }); const cj = await cr.json(); if (cj?.ok && Array.isArray(cj.images) && cj.images.length) images = cj.images.slice(0, 10); } catch (_e) { /* */ }
      }
      if (!images.length) return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], note: isCad ? 'cad_not_converted' : 'no_readable_pages' });
      try {
        const redPrefix = `redacted/${crypto.randomUUID()}/page`;
        const [boqRes, redRes] = await Promise.allSettled([
          fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, hint, images }) }),
          fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, images, prefix: redPrefix, owner_customer_id: cust.id, owner_email: email, source_path: path }) }),
        ]);
        let redacted: string[] = []; let redJob: string | null = null; let redIn = 0; let redOut = 0;
        // Only pass paths back to the client once drawing_redact has RECORDED the run server-side
        // (drawing_redaction_runs). An unrecorded run cannot be verified at create_inquiry, so its
        // paths are unusable — dropping them here lands on the existing total-failure behaviour
        // (inquiry goes out with no drawing) instead of a confusing rejection later.
        if (redRes.status === 'fulfilled') { try { const rj = await redRes.value.json(); redIn = Number(rj?.pages_in || 0); redOut = Number(rj?.pages_out || 0); if (rj?.ok && rj?.recorded && rj?.job_id && Array.isArray(rj.paths)) { redacted = rj.paths.map((x: any) => String(x)); redJob = String(rj.job_id); } } catch (_e) { /* */ } }
        const redMeta = { redaction_job_id: redJob, redaction_pages_in: redIn, redaction_pages_out: redOut, redaction_complete: redOut >= redIn };
        if (boqRes.status !== 'fulfilled') return J({ ok: false, error: 'analysis_exception', detail: 'boq_fetch_failed', drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: redacted, ...redMeta }, 200);
        const jd = await boqRes.value.json();
        if (!jd?.ok) return J({ ok: false, error: 'analysis_failed', detail: jd?.detail || jd?.error || '', drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: redacted, ...redMeta }, 200);
        return J({ ok: true, boq: jd.boq, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: redacted, ...redMeta });
      } catch (e) { return J({ ok: false, error: 'analysis_exception', detail: String((e as Error)?.message || e), drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [] }, 200); }
    }

    if (action === 'create_inquiry') {
      if (!cust.email_verified) return J({ error: 'Please verify your email before sending a request. Open the Account tab and enter the 6-digit code we email you.' }, 403);
      // REGISTRATION COMPLETENESS GATE (2 Aug 2026, external code review). This endpoint checked
      // email_verified and nothing else, so the three things that make a buyer real — a name, a
      // reachable mobile, and an accepted version of the Terms — were enforced by the FRONTEND
      // only. Anyone with a verified email and a JWT could POST straight here and put an RFQ in
      // front of matched suppliers with none of them. Two concrete costs: the supplier who later
      // wins the job is handed a reveal (which the buyer paid 3% for) containing an empty contact
      // card, and there is no accepted-terms record to point at if that job goes wrong — the
      // entire T&C evidence chain assumes tos_accepted_at exists by the time an RFQ is dispatched.
      //
      // Deliberately NOT blocking on signed_terms_path. The signed certificate is produced
      // out-of-band by compliance_archive (PDF render + Dropbox mirror), so a transient failure
      // there is not the buyer's fault, is not a privacy risk, and blocking on it would take a
      // customer's ability to trade away for an operational fault of ours. It is repaired in the
      // background instead, so the evidence still lands and the gap stays visible.
      const missingReg: string[] = [];
      if (!String(cust.full_name || '').trim()) missingReg.push('your name');
      if (!String(cust.phone || '').trim()) missingReg.push('a mobile number');
      if (!cust.tos_accepted_at) missingReg.push('acceptance of the Terms & Conditions');
      if (missingReg.length) {
        const list = missingReg.length === 1 ? missingReg[0] : missingReg.slice(0, -1).join(', ') + ' and ' + missingReg[missingReg.length - 1];
        return J({ error: 'registration_incomplete', missing: missingReg, message: `Please finish setting up your account first — we still need ${list}. Open the Account tab; it takes under a minute. Suppliers quote on your request without seeing who you are, but we need this on file before it goes out.` }, 428);
      }
      if (!cust.signed_terms_path) {
        // Fire-and-forget repair. Never awaited: create_inquiry must not inherit the latency or
        // the failure mode of a PDF render and a Dropbox round-trip.
        try {
          const s = await getSecret('cred_fn_customer_api');
          fetch(`${SUPABASE_URL}/functions/v1/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: s, action: 'sign', kind: 'customer', email }) }).catch(() => { /* best effort */ });
        } catch (_e) { /* never blocks the buyer */ }
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recent } = await admin.from('inquiries').select('id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((recent || 0) >= INQUIRY_LIMIT_PER_HOUR) return J({ error: 'You have created many requests in a short time. Please try again later.' }, 429);
      const drawing = body.drawing && typeof body.drawing === 'object' ? body.drawing : null;
      const boqObj = drawing?.boq && typeof drawing.boq === 'object' ? drawing.boq : null;
      const briefSource = drawing ? (['drawing','quotation'].includes(String(drawing.brief_source)) ? String(drawing.brief_source) : 'drawing') : null;
      let intake: any = null;
      if (body.intake_id) { const { data: it } = await admin.from('inquiry_intake').select('*').eq('id', String(body.intake_id)).maybeSingle(); if (it && it.email === email && it.status === 'ready') intake = it; }
      // INTAKE GATE BYPASS (27 Jul 2026). The mandatory intake used to be waived whenever the
      // CALLER posted a drawing object carrying a one-line boq array — a body the client builds
      // and can therefore forge, so { drawing: { boq: { boq: [{}] } } } skipped the questions
      // entirely and suppliers got briefs with no scope, quantity or emirate. The only bypass now
      // is a real, server-side inquiry_intake row owned by this customer and marked 'ready'
      // (resolved just above). A drawing still enriches the brief; it no longer replaces it.
      if (!intake) return J({ error: 'intake_required', message: 'Please answer a few quick questions so suppliers can quote accurately.' }, 428);
      const briefObj = intake?.brief && typeof intake.brief === 'object' ? intake.brief : null;
      let category = String(body.category || '').trim();
      if (!category && intake?.category) category = String(intake.category).trim();
      if (!category && boqObj?.category) category = String(boqObj.category).trim();
      const raw = String(body.raw_input || (intake?.raw_input || '')).slice(0, 4000);
      let summary = String(body.summary || '').slice(0, 500);
      if (!summary && briefObj?.summary) summary = String(briefObj.summary).slice(0, 500);
      if (!summary && boqObj?.summary) summary = String(boqObj.summary).slice(0, 500);
      if (!category) { const dd = detect(raw + ' ' + summary); category = dd.category || 'general'; }
      const emirate = body.emirate || (briefObj?.emirate || null) || null;
      const specIn = body.spec && typeof body.spec === 'object' ? body.spec : {};
      const spec = (briefObj?.details && typeof briefObj.details === 'object') ? { ...briefObj.details, ...specIn } : specIn;
      const budget = (body.budget ? String(body.budget) : (briefObj?.budget ? String(briefObj.budget) : '')).slice(0, 80) || null;
      const scope_type = ['single','multi','turnkey'].includes(String(body.scope_type)) ? String(body.scope_type) : 'single';
      const tradesIn = Array.isArray(body.trades) ? body.trades.map((t: any) => String(t).toLowerCase()).filter(Boolean) : [];
      const d = detect(raw + ' ' + summary + ' ' + Object.values(spec).join(' '));
      const base = d.keywords.length ? d.keywords : (KW[category] || []);
      let keywords = Array.from(new Set([...base, category, ...tradesIn]));
      if (Array.isArray(boqObj?.keywords)) keywords = Array.from(new Set([...keywords, ...boqObj.keywords.map((s: any) => String(s).toLowerCase())]));
      keywords = keywords.slice(0, 30);
      const drawingPath = drawing?.drawing_file_path ? String(drawing.drawing_file_path) : null;
      const drawingName = drawing?.drawing_file_name ? String(drawing.drawing_file_name).slice(0, 180) : null;
      // Never trust drawing.drawing_redacted_paths from the body — see resolveRedactedPaths above.
      const rr = await resolveRedactedPaths(String(cust.id), String(user.id || ''), drawing);
      if ('err' in rr) return J(rr.err, rr.status);
      const drawingRedacted = rr.paths.length ? rr.paths.slice(0, 24) : null;
      // `tradesIn` arrives from the request body, so Set<unknown> is what TypeScript infers and
      // every downstream use of a trade - labelize(tr), KW[tr], category: tr - was an error.
      // Coercing here rather than casting at each use means a non-string trade is normalised once,
      // at the boundary, instead of being asserted away four times further down.
      const tradeStrings: string[] = (Array.isArray(tradesIn) ? tradesIn : []).map((t: unknown) => String(t ?? '').trim()).filter((s: string) => s.length > 0);
      const distinctTrades: string[] = Array.from(new Set<string>(tradeStrings)).slice(0, 6);
      const wantSplit = scope_type === 'multi' && distinctTrades.length > 1;
      const wantTurnkey = scope_type === 'turnkey';
      const drawCols = { drawing_file_path: drawingPath, drawing_file_name: drawingName, drawing_redacted_paths: drawingRedacted, boq: boqObj, boq_confidence: boqObj?.confidence || null };

      if (wantSplit) {
        const { data: parent, error: ep } = await admin.from('inquiries').insert({ customer_id: cust.id, category: 'combined', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'split', budget, scope_type: 'multi', trades: distinctTrades, brief_source: briefSource, ...drawCols }).select('id').maybeSingle();
        if (ep) return J({ error: ep.message }, 500);
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        const children: any[] = [];
        for (const tr of distinctTrades) {
          const tlabel = labelize(tr);
          const childSummary = ((summary ? summary + ' — ' : '') + tlabel + ' works (part of a combined project)').slice(0, 500);
          const childKw = Array.from(new Set([...(KW[tr] || []), tr])).slice(0, 30);
          const { data: child, error: ec } = await admin.from('inquiries').insert({ customer_id: cust.id, parent_inquiry_id: parent!.id, category: tr, emirate, role_needed: 'supplier', raw_input: raw, spec, summary: childSummary, keywords: childKw, status: 'sent', budget, scope_type: 'single', trades: [tr], brief_source: briefSource, ...drawCols }).select('id').maybeSingle();
          if (ec || !child) continue;
          const extra = ' This is the ' + tlabel + ' portion of a larger project — please quote for the ' + tlabel + ' works only; other trades are handled separately.' + (boqObj ? ' A redacted drawing is attached.' : '');
          const { matches } = await matchAndNotify(String(child.id), { category: tr, emirate, keywords: childKw, summary: childSummary, budget, extra, useRouter: false, multi: false });
          children.push({ inquiry_id: child.id, trade: tr, label: tlabel, matches });
        }
        return J({ ok: true, split: true, scope_type: 'multi', parent_id: parent!.id, children, trades: distinctTrades });
      }

      if (wantTurnkey) {
        const tkKeywords = Array.from(new Set([...keywords, 'fitout', 'fit out', 'fit-out', 'turnkey', 'interior', 'renovation', 'decoration', ...distinctTrades])).slice(0, 40);
        const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, category: 'fitout', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords: tkKeywords, status: 'sent', budget, scope_type: 'turnkey', trades: distinctTrades.length ? distinctTrades : (tradesIn.length ? tradesIn : null), brief_source: briefSource, ...drawCols }).select('id').maybeSingle();
        if (e1) return J({ error: e1.message }, 500);
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        const tradeList = distinctTrades.map(labelize).join(', ');
        const extra = (tradeList ? ' Combined turnkey scope covering: ' + tradeList + '.' : '') + (boqObj ? ' A redacted drawing is attached.' : '');
        const { matches } = await matchAndNotify(String(inq!.id), { category: 'fitout', emirate, keywords: tkKeywords, summary, budget, extra, useRouter: false, multi: true });
        return J({ ok: true, inquiry_id: inq!.id, scope_type: 'turnkey', matches });
      }

      const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, category, emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'sent', budget, scope_type: 'single', trades: tradesIn.length ? tradesIn : null, brief_source: briefSource, ...drawCols }).select('id').maybeSingle();
      if (e1) return J({ error: e1.message }, 500);
      if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
      const extra = boqObj ? (briefSource === 'quotation' ? ' A scope (anonymized from the customer’s own quotation, prices removed) is attached.' : ' A drawing with a draft bill of quantities is attached.') : '';
      const { matches, routing } = await matchAndNotify(String(inq!.id), { category, emirate, keywords, summary, budget, extra, useRouter: true, multi: false });
      return J({ ok: true, inquiry_id: inq!.id, matches, routing });
    }

    if (action === 'my_inquiries') {
      const cfg = await getCfg();
      const cols = 'id,category,emirate,summary,spec,status,created_at,budget,scope_type,brief_source,drawing_file_path,drawing_file_name,boq,boq_confidence,hired_supplier_id,outcome,parent_inquiry_id,trades';
      const { data: tops } = await admin.from('inquiries').select(cols).eq('customer_id', cust.id).is('parent_inquiry_id', null).order('created_at', { ascending: false }).limit(25);
      const topIds = (tops || []).map((i) => i.id);
      let kids: any[] = [];
      if (topIds.length) { const { data: ch } = await admin.from('inquiries').select(cols).in('parent_inquiry_id', topIds).order('created_at', { ascending: true }); kids = ch || []; }
      const kidsByParent: Record<string, any[]> = {};
      for (const k of kids) { (kidsByParent[String(k.parent_inquiry_id)] ||= []).push(k); }
      const ids = [...topIds, ...kids.map((k) => k.id)];
      let quotes: Record<string, any>[] = [];
      if (ids.length) { const { data: qs } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,source,original_file_path,created_at,expires_at').in('inquiry_id', ids).neq('status', 'draft').order('quote_amount', { ascending: true }); quotes = qs || []; }
      // How many suppliers the request actually reached. Without this the portal cannot tell
      // "waiting for quotes" apart from "this reached nobody", and shows hope either way.
      const matchedBy: Record<string, number> = {};
      if (ids.length) { try { const { data: ms } = await admin.from('inquiry_matches').select('inquiry_id').in('inquiry_id', ids); for (const m of (ms || [])) matchedBy[String(m.inquiry_id)] = (matchedBy[String(m.inquiry_id)] || 0) + 1; } catch (_e) { /* */ } }
      const supIds = [...new Set(quotes.map((q) => q.supplier_id))];
      const supMeta: Record<string, any> = {};
      if (supIds.length) { const { data: ls } = await admin.from('leads').select('id,rating,rating_maps,reviews,reviews_maps,app_rating,app_reviews,emirate,verified,founded_year').in('id', supIds); const { data: perf } = await admin.from('supplier_perf').select('supplier_id,won,win_rate').in('supplier_id', supIds); const perfById: Record<string, any> = {}; for (const p of (perf||[])) perfById[String(p.supplier_id)] = p; const _yr = new Date().getFullYear(); for (const l of ls || []) supMeta[String(l.id)] = { r: ratingOf(l), emirate: l.emirate, verified: !!l.verified, years_active: l.founded_year ? Math.max(0, _yr - Number(l.founded_year)) : null, jobs_won: (perfById[String(l.id)]||{}).won ?? 0, win_rate: (perfById[String(l.id)]||{}).win_rate ?? null }; }
      const revealedQ = new Set<string>(); const txByQuote: Record<string, string> = {}; const revealAtByQuote: Record<string, string | null> = {};
      // public.transactions HAS NO created_at COLUMN - in staging or in production. Selecting it
      // made PostgREST answer 400, so `txs` came back null, `for (const t of txs || [])` iterated
      // nothing, and revealedQ stayed empty: NO QUOTE WAS EVER MARKED REVEALED. The customer paid
      // the reveal fee, `reveal` wrote the transactions row, and the portal went on showing
      // "Supplier A" with banded ratings and supplier_ref null, forever. Found 5 Aug 2026 by the
      // first fixture that ever created a transactions row - the journey never reveals, so a green
      // 37/37 said nothing about it. revealed_at is the column that exists; there is no fallback.
      if (ids.length) { const { data: txs, error: txErr } = await admin.from('transactions').select('id,quote_id,revealed_at').eq('customer_id', cust.id); if (txErr) console.error('my_inquiries: transactions read failed —', txErr.message); for (const t of txs || []) { revealedQ.add(String(t.quote_id)); txByQuote[String(t.quote_id)] = String(t.id); revealAtByQuote[String(t.quote_id)] = t.revealed_at || null; } }
      const { data: revs } = await admin.from('reviews').select('transaction_id').eq('customer_id', cust.id); const ratedTx = new Set((revs || []).map((r) => String(r.transaction_id)));
      const now = new Date();
      // Pre-reveal quote rows carry BANDS only (see ratingBand/reviewCountBand/yearsBand above);
      // rating_source, emirate and win_rate are set to undefined so JSON.stringify omits the keys
      // outright rather than shipping a null the client could still reason about. Revealed quotes
      // — a transactions row exists for that quote_id — keep the exact values, unchanged.
      const mapRow = async (i: any) => ({ id: i.id, category: i.category, emirate: i.emirate, summary: i.summary, spec: i.spec, status: i.status, created_at: i.created_at, budget: i.budget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: i.boq || null, boq_confidence: i.boq_confidence || null, drawing_file_name: i.drawing_file_name || null, hired_supplier_id: i.hired_supplier_id ?? null, outcome: i.outcome ?? null, trades: i.trades || null, matched_suppliers: matchedBy[String(i.id)] || 0, editable: (i.status === 'sent') && ((Date.now() - new Date(i.created_at).getTime()) < 24*3600e3), edit_minutes_left: (i.status === 'sent') ? Math.max(0, Math.round((60*60e3 - (Date.now() - new Date(i.created_at).getTime()))/60000)) : 0, drawing_file_url: await signedDrawing(i.drawing_file_path), quotes: quotes.filter((q) => q.inquiry_id === i.id).map((q, idx) => { const m = supMeta[String(q.supplier_id)] || {}; const r = m.r || {}; const revealed = revealedQ.has(String(q.id)); return { id: q.id, supplier_ref: revealed ? q.supplier_id : null, label: 'Supplier ' + supplierLabel(idx), price: q.quote_amount, reveal_fee: revealFee(Number(q.quote_amount), cfg), notes: q.notes, lead_time: q.lead_time, validity: q.validity, expires_at: q.expires_at ?? null, expired: q.expires_at ? (new Date(q.expires_at) < now) : false, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, source: q.source || 'form', has_original: !!q.original_file_path, status: q.status, revealed, revealed_at: revealAtByQuote[String(q.id)] || null, rated: ratedTx.has(String(txByQuote[String(q.id)] || '')), rating: revealed ? (r.value ?? null) : ratingBand(r.value), rating_count: revealed ? (r.count ?? 0) : reviewCountBand(r.count), rating_source: revealed ? (r.source || null) : undefined, emirate: revealed ? (m.emirate ?? null) : undefined, verified: m.verified ?? false, years_active: revealed ? (m.years_active ?? null) : yearsBand(m.years_active), jobs_won: m.jobs_won ?? 0, win_rate: revealed ? (m.win_rate ?? null) : undefined }; }) });
      const out = [] as any[];
      for (const i of (tops || [])) {
        // mapRow returns an object literal, so its inferred type has no is_combined / child_count /
        // children. The combined-project decoration below is genuinely dynamic - only split parents
        // get it - so the row is typed as an open record rather than the literal's shape.
        const row: Record<string, any> = await mapRow(i);
        const ch = kidsByParent[String(i.id)];
        if (ch && ch.length) { row.is_combined = true; row.child_count = ch.length; row.children = []; for (const c of ch) row.children.push(await mapRow(c)); }
        out.push(row);
      }
      // `locale` added 5 Aug 2026. customers.locale was stored and, from the portal's point of
      // view, never served: the brief called it "stored and never served", which measurement shows
      // is not quite right - `me` returns the whole customer row via select('*'), locale included.
      // But THE PORTAL NEVER CALLS `me`. It calls `kyc state` and this action, so the field was on
      // the wire only where nothing was listening, and CustomerPortal fell back to
      // localStorage['qd-lang'] and the NEXT_LOCALE cookie. A customer who set Arabic on one device
      // got English on the next, and the Arabic journey exercised a path the portal could not reach.
      return J({ inquiries: out, locale: cust.locale || null, promo: !!cfg.promo_until && new Date() <= new Date(cfg.promo_until) });
    }

    if (action === 'compare_pdf') {
      const iid = String(body.inquiry_id || '');
      const wantAr = /^ar/i.test(String(body.lang || ''));
      const lang = wantAr ? 'ar' : 'en';
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,summary,emirate').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      // Reuse the cached analysis when the quote set is unchanged; otherwise ask for a fresh one.
      let analysis: any = null;
      try {
        const secret = await getSecret('cred_fn_customer_api');
        const r = await fetch(`${SUPABASE_URL}/functions/v1/quote_compare`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, inquiry_id: iid, lang }) });
        const jd = await r.json();
        if (jd?.ok && jd.analysis) analysis = jd.analysis; else return J({ error: jd?.note || jd?.error || 'comparison_unavailable' }, 200);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      try {
        const { j, ref } = await buildComparePdf(analysis, inq, lang);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'brief_pdf') {
      const iid = String(body.inquiry_id || '');
      const wantAr = /^ar/i.test(String(body.lang || ''));
      const lang = wantAr ? 'ar' : 'en';
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,summary,emirate,budget,spec,boq,trades,drawing_file_name').eq('id', iid).maybeSingle();
      if (!inq) return J({ error: 'Request not found' }, 404);
      if (inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildBriefPdf(inq, lang);
        if (j?.ok && j.url) return J({ ok: true, url: j.url, ref });
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'quote_pdf') {
      const qid = String(body.quote_id || '');
      const wantAr = /^ar/i.test(String(body.lang || body.customer_lang || ''));
      const cacheLang = wantAr ? 'bi' : 'en';
      const { data: q } = await admin.from('quotes').select('*').eq('id', qid).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,summary,emirate,boq').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const refOf = async () => { const { data: sibs } = await admin.from('quotes').select('id,quote_amount').eq('inquiry_id', q.inquiry_id).order('quote_amount', { ascending: true }); const ix = (sibs || []).findIndex((s: any) => s.id === q.id); const letter = supplierLabel(ix >= 0 ? ix : 0); return 'QD-' + String(q.inquiry_id || '').slice(0, 8).toUpperCase() + '-' + letter; };
      const { data: cached } = await admin.from('quote_pdf_cache').select('bucket,path,created_at').eq('quote_id', qid).eq('lang', cacheLang).maybeSingle();
      const touched = q.updated_at ? new Date(q.updated_at) : (q.created_at ? new Date(q.created_at) : null);
      if (cached && (!touched || new Date(cached.created_at) >= touched)) {
        const url = await signedDoc(cached.bucket, cached.path);
        if (url) return J({ ok: true, url, ref: await refOf(), cached: true });
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: gens } = await admin.from('quote_pdf_cache').select('quote_id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((gens || 0) >= PDF_LIMIT_PER_HOUR) return J({ error: 'You have generated many PDFs recently. Please try again shortly.' }, 429);
      try {
        const { j, ref } = await buildQuotePdf(q, inq, wantAr);
        if (j?.ok && j.url) {
          try { await admin.from('quote_pdf_cache').upsert({ quote_id: qid, lang: cacheLang, customer_id: cust.id, bucket: j.bucket || 'agent-docs', path: j.path, created_at: new Date().toISOString() }, { onConflict: 'quote_id,lang' }); } catch (_e) { /* */ }
          return J({ ok: true, url: j.url, ref });
        }
        return J({ error: 'pdf_failed', detail: j?.error || j?.detail || '' }, 502);
      } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
    }

    if (action === 'reveal') {
      const cfg = await getCfg(); const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,original_file_path,original_file_name').eq('id', qid).maybeSingle();
      if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
      if (existing) { const { data: sup } = await admin.from('leads').select('company_name,phone,whatsapp,email,website,emirate').eq('id', q.supplier_id).maybeSingle(); return J({ ok: true, already_revealed: true, supplier: sup, original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null }); }
      return J({ ok: true, payment_required: true, quote_id: qid, quote_amount: q.quote_amount, reveal_fee: revealFee(Number(q.quote_amount), cfg), currency: 'AED' });
    }

    if (action === 'request_refund') {
      const qid = String(body.quote_id || '');
      const { data: tx } = await admin.from('transactions').select('id,customer_id,refund_deadline,refund_status,fee_status').eq('quote_id', qid).maybeSingle();
      if (!tx || tx.customer_id !== cust.id) return J({ error: 'Transaction not found' }, 404);
      if (tx.refund_status) return J({ ok: true, refund_status: tx.refund_status });
      if (tx.refund_deadline && new Date() > new Date(tx.refund_deadline)) return J({ error: 'The 3 working-day refund window has passed.' }, 400);
      const { data: q2 } = await admin.from('quotes').select('inquiry_id,supplier_id').eq('id', qid).maybeSingle();
      if (q2) {
        const { data: inq2 } = await admin.from('inquiries').select('status,outcome,hired_supplier_id').eq('id', q2.inquiry_id).maybeSingle();
        if (inq2 && ['completed', 'closed'].includes(String(inq2.status)) && Number(inq2.hired_supplier_id) === Number(q2.supplier_id)) return J({ error: 'This job is already marked as completed with this supplier, so the reveal fee is no longer refundable.' }, 400);
        const { data: rev2 } = await admin.from('reviews').select('id').eq('transaction_id', tx.id).maybeSingle();
        if (rev2) return J({ error: 'You have already rated this supplier, so the reveal fee is no longer refundable.' }, 400);
      }
      await admin.from('transactions').update({ refund_status: 'requested' }).eq('id', tx.id);
      return J({ ok: true, refund_status: 'requested', note: 'Your refund request has been received and will be reviewed.' });
    }

    if (action === 'rate_supplier') {
      const qid = String(body.quote_id || ''); const rating = Number(body.rating); const comment = body.comment ? String(body.comment).slice(0, 500) : null;
      if (!(rating >= 1 && rating <= 5)) return J({ error: 'Rating must be 1 to 5.' }, 400);
      const { data: q } = await admin.from('quotes').select('id,supplier_id,inquiry_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'You can only rate a supplier you have revealed and dealt with.' }, 403);
      const { error } = await admin.from('reviews').upsert({ supplier_id: q.supplier_id, customer_id: cust.id, inquiry_id: q.inquiry_id, transaction_id: tx.id, rating, comment }, { onConflict: 'transaction_id' });
      if (error) return J({ error: error.message }, 500);
      await admin.rpc('recompute_supplier_rating', { p_supplier: q.supplier_id });
      return J({ ok: true });
    }

    if (action === 'complete_inquiry') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Reveal this supplier first.' }, 403);
      await admin.from('inquiries').update({ status: 'completed', hired_supplier_id: q.supplier_id, completed_at: new Date().toISOString(), outcome: 'hired' }).eq('id', inq.id);
      await notifyLosers(String(inq.id), inq.summary ?? null, Number(q.supplier_id));
      return J({ ok: true });
    }

    if (action === 'edit_inquiry') {
      const iid = String(body.inquiry_id || '');
      const patch = (body.patch && typeof body.patch === 'object') ? body.patch : body;
      const clean: Record<string, unknown> = {};
      for (const k of ['summary','raw_input','budget','emirate','scope_type','spec','boq','trades','keywords']) if (patch[k] !== undefined) clean[k] = patch[k];
      const { data: r } = await admin.rpc('fn_edit_inquiry', { p_inquiry: iid, p_customer: cust.id, p_patch: clean });
      if (r?.error) return J({ error: r.message || r.error, editable_until: r.editable_until }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'cancel_inquiry') {
      const iid = String(body.inquiry_id || '');
      const reason = body.reason ? String(body.reason).slice(0, 300) : null;
      const { data: r } = await admin.rpc('fn_cancel_inquiry', { p_inquiry: iid, p_customer: cust.id, p_reason: reason });
      if (r?.error) return J({ error: r.message || r.error }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'supplier_history') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,supplier_id,original_file_path,original_file_name').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Reveal this supplier first to see their profile.' }, 403);
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,phone,whatsapp,email,website,rating,rating_maps,reviews,reviews_maps,app_rating,app_reviews,description,capability_summary,founded_year,company_type').eq('id', q.supplier_id).maybeSingle();
      const { data: projs } = await admin.from('transactions').select('revealed_at,quote_amount,inquiries(category,emirate)').eq('supplier_id', q.supplier_id).order('revealed_at', { ascending: false }).limit(20);
      const projects = (projs || []).map((p: any) => ({ category: p.inquiries?.category || null, emirate: p.inquiries?.emirate || null, month: p.revealed_at ? new Date(p.revealed_at).toLocaleDateString('en-GB', { month: 'short', year: 'numeric' }) : null, value_band: band(Number(p.quote_amount)) }));
      return J({ ok: true, supplier: sup ? { ...sup, rating_display: ratingOf(sup) } : null, projects, projects_count: projects.length, original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null });
    }


    return J({ error: 'Unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});

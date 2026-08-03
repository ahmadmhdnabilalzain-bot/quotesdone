import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function dataUrl(b64: string, mime: string){ return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/,'')}`; }
function scrub(s: unknown){ let t = String(s == null ? '' : s); t = t.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[removed]'); t = t.replace(/\b(?:https?:\/\/|www\.)[^\s)]+/gi, '[removed]'); return t; }

const CATS = 'civil_construction, fit_out_interior, mep_electrical, mep_plumbing, mep_hvac, joinery_carpentry, flooring_tiling, painting_finishes, aluminium_glass, false_ceiling_partitions, steel_fabrication, waterproofing, landscaping, signage, cleaning_facilities, swimming_pools';

const SYS = `You are a UAE quantity surveyor. You read CONSTRUCTION / FIT-OUT / MEP / architectural drawings (floor plans, elevations, sections, layouts, schedules, single-line diagrams) and produce a DRAFT Bill of Quantities (BOQ) that a contractor could price.\n\nPRIVACY (CRITICAL): your output is shown to competing suppliers who must NOT be able to identify the client or project. NEVER read out, copy or include ANY identifying information from the drawing. Specifically ignore and never repeat: the title block's company / consultant / architect / contractor names, client or owner names, any person names, phone numbers, emails, websites, the project name or title, drawing or project numbers, plot / parcel / makani numbers, and the site or project address. You MAY use the title block ONLY for scale, drawing type and dimensions. Output ONLY generic technical scope. If any text field (summary, descriptions, basis, keywords, assumptions, missing_info) would contain a name, company, phone, email or address, leave it out or generalise it (e.g. say 'a villa', not the address; 'ground floor', not the project name).\n\nRead EVERY drawing page. Use the title block, scale bar, stated dimensions, room/area labels, schedules (door/window/finish/fixture schedules), legends and symbol counts. Where a scale or explicit dimensions are given, compute areas (sqm), lengths (m) and counts (nos). Where you must assume, say so and lower the confidence.\n\nProduce measurable BOQ line items grouped into sections (e.g. Demolition, Blockwork, Flooring, Painting, Doors, Electrical points, Plumbing fixtures, HVAC, Ceiling). For each item give: a clear generic description, quantity, unit (sqm / m / nos / lot), the dimensions or basis used, and a per-item confidence. Keep to the most relevant items (aim for under 40). Be concise in every text field.\n\nIMPORTANT: this is an AI ESTIMATE for guidance and supplier matching, NOT a certified take-off. Be honest. Never invent quantities you cannot see. Flag everything you assumed and everything you could not determine.\n\nOutput ONLY the JSON object, no markdown, no prose before or after:\n{\"drawing_type\":string,\"category\":one of [${CATS}] or \"\",\"summary\":string,\"scale_detected\":string,\"total_area_sqm\":number|null,\"boq\":[{\"section\":string,\"description\":string,\"qty\":number|null,\"unit\":string,\"basis\":string,\"confidence\":\"low\"|\"medium\"|\"high\"}],\"keywords\":[string],\"assumptions\":[string],\"missing_info\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\ncategory = best single match from the list for supplier matching. keywords = 4-10 short terms describing the trades/materials shown (for matching). If you cannot read the drawing at all, return confidence \"low\", empty boq, and explain in missing_info.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'drawing_boq');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const key = await sec('cred_fn_ai');
    if (!key) return J({ error: 'no ai key' }, 500);
    const hint = body.hint ? String(body.hint).slice(0,400) : '';

    const content: any[] = [{ type: 'text', text: `Customer note (context only): ${hint||'(none)'}. Read the attached drawing pages and return the DRAFT BOQ JSON. Remember: never include any names, company, contact or address from the drawing.` }];
    const imgs: any[] = Array.isArray(body.images) ? body.images : [];
    if (imgs.length) {
      for (const im of imgs.slice(0, 10)) { const b = (im && (im.b64 || im.data)) || im; const m = (im && im.mime) || 'image/jpeg'; if (b && typeof b === 'string') content.push({ type: 'image_url', image_url: { url: dataUrl(b, String(m)) } }); }
    } else if (body.file_b64) {
      const mime = String(body.mime || 'application/octet-stream');
      if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
      else content.push({ type: 'file', file: { filename: String(body.filename||'drawing.pdf'), file_data: dataUrl(String(body.file_b64), mime||'application/pdf') } });
    } else { return J({ error: 'no file' }, 400); }
    if (content.length < 2) return J({ error: 'no readable image' }, 400);

    let rawContent = '';
    let ai: any = {};
    try {
      const payload = { __secret: key, fn: 'drawing_boq', max: 8000, temperature: 0.1, sys: SYS, input: [{ role: 'user', content }] };
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const jd = await r.json();
      if (!r.ok || jd?.ok === false) return J({ error: 'ai_error', detail: jd?.detail || jd?.error || '', meta: JSON.stringify(jd).slice(0,600) }, 502);
      rawContent = jd?.content || '';
      if (body.__debug) return J({ ok: true, _len: String(rawContent).length, finish: jd?.finish_reason });
      ai = parseJson(rawContent || '{}');
    } catch (e) { return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

    if (!Array.isArray(ai.boq)) ai.boq = [];
    ai.boq = ai.boq.slice(0, 120).map((li: any) => ({ section: scrub(li?.section||'General'), description: scrub(li?.description||''), qty: (li?.qty===null||li?.qty==='')?null:(Number(li?.qty)||null), unit: scrub(li?.unit||''), basis: scrub(li?.basis||''), confidence: ['low','medium','high'].includes(li?.confidence)?li.confidence:'low' }));
    ai.keywords = Array.isArray(ai.keywords) ? ai.keywords.map((s:any)=>scrub(s)).slice(0,12) : [];
    ai.assumptions = Array.isArray(ai.assumptions) ? ai.assumptions.map((s:any)=>scrub(s)).slice(0,20) : [];
    ai.missing_info = Array.isArray(ai.missing_info) ? ai.missing_info.map((s:any)=>scrub(s)).slice(0,20) : [];
    ai.total_area_sqm = (ai.total_area_sqm===null||ai.total_area_sqm==='')?null:(Number(ai.total_area_sqm)||null);
    ai.drawing_type = scrub(ai.drawing_type||'');
    ai.category = String(ai.category||'');
    ai.summary = scrub(ai.summary||'');
    ai.scale_detected = scrub(ai.scale_detected||'');
    if (!['low','medium','high'].includes(ai.confidence)) ai.confidence = 'low';
    return J({ ok: true, boq: ai });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

const CATS = ['acrylic','aluminium','carpentry','fitout','flooring','glass','gypsum','landscaping','painting','safety','scaffolding','security','signage','steel','upholstery','wallpaper'];

const SYS = `You enrich a UAE construction / fit-out / facilities supplier's company profile using their own email reply and any attached images (brochures, company profile, trade licence). Extract ONLY facts that are actually present in the email or attachments. Never invent or assume.

Return STRICT JSON only (no markdown), exact shape:
{\"description\":string|null,
 \"services\":string|null,
 \"products\":string|null,
 \"certifications\":string|null,
 \"founded_year\":number|null,
 \"company_size\":string|null,
 \"company_type\":string|null,
 \"service_emirates\":[string],
 \"trade_license_no\":string|null,
 \"contact_name\":string|null,
 \"category\":string|null,
 \"capability_summary\":string|null}

Field rules:
- description: 1-3 sentence plain description of what the company does.
- services / products: short comma-separated lists in the supplier's own terms.
- certifications: ISO, Civil Defence / SIRA / municipality approvals, etc., else null.
- company_type: one of manufacturer, contractor, supplier, trader, or a short phrase if clearly stated; else null.
- service_emirates: canonical emirate names only (Dubai, Abu Dhabi, Sharjah, Ajman, Ras Al Khaimah, Umm Al Quwain, Fujairah). If they say \"all UAE\", \"nationwide\", or \"across the Emirates\", include all seven. If only their base city is known, include just that emirate. Use [] when truly unknown.
- category: the single best-fit trade category for this supplier, chosen ONLY from this exact list: acrylic, aluminium, carpentry, fitout, flooring, glass, gypsum, landscaping, painting, safety, scaffolding, security, signage, steel, upholstery, wallpaper. Pick the one that most closely matches their core line of work. If the company clearly spans general interior fit-out / joinery / turnkey interiors, use \"fitout\". Only return null if there is genuinely not enough information to choose. Return the value in lowercase, exactly as written in the list.
- capability_summary: one concise paragraph (no line breaks) that a matching engine reads: mention sector, key products/services, and coverage. Always try to produce this from whatever is known.
- Use null (or [] for service_emirates) for anything not stated. Do NOT output placeholders like \"N/A\" or \"unknown\".`;

function parseJson(txt: string) {
  try { return JSON.parse(txt); } catch { /* */ }
  const m = txt.match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* */ } }
  throw new Error('AI returned non-JSON');
}

// Signature unchanged; `key` is now the inbound_secret used to authenticate to ai_gateway.
async function callClaude(key: string, parts: { text?: string; img?: { mime: string; data: string } }[]) {
  const content: unknown[] = [];
  for (const p of parts) {
    if (p.text) content.push({ type: 'text', text: p.text });
    if (p.img) content.push({ type: 'image_url', image_url: { url: `data:${p.img.mime};base64,${p.img.data}` } });
  }
  const r = await fetch(GW, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: key, fn: 'profile_ai', max: 1100, temperature: 0.15, sys: SYS, input: [{ role: 'user', content }] }),
  });
  const d = await r.json();
  if (!r.ok || d?.ok === false) throw new Error(d?.detail || d?.error || 'ai_gateway error');
  return parseJson(d?.content || '{}');
}

const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];
function normEmirates(arr: unknown): string[] {
  if (!Array.isArray(arr)) return [];
  const out = new Set<string>();
  for (const v of arr) {
    const s = String(v || '').toLowerCase();
    for (const e of EMIRATES) if (s.includes(e.toLowerCase()) || (e === 'Ras Al Khaimah' && s.includes('rak')) || (e === 'Umm Al Quwain' && s.includes('uaq'))) out.add(e);
  }
  return [...out];
}
function normCategory(v: unknown): string | null {
  if (v == null) return null;
  const s = String(v).trim().toLowerCase();
  return CATS.includes(s) ? s : null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    let ok = false;
    const { data: sec1 } = await admin.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (sec1?.value && body.__secret === sec1.value) ok = true;
    if (!ok) { const { data: t } = await admin.from('app_secrets').select('value').eq('key', 'test_token').maybeSingle(); if (t?.value && body.__test === t.value) ok = true; }
    if (!ok) return J({ error: 'forbidden' }, 403);

    const { data: keyRow } = await admin.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (!keyRow?.value) return J({ error: 'smart engine not configured', fallback: true }, 200);

    const parts: { text?: string; img?: { mime: string; data: string } }[] = [];
    const ctx: string[] = [];
    if (body.company_name) ctx.push('Company name: ' + body.company_name);
    if (body.sector) ctx.push('Known trade/sector: ' + body.sector);
    if (body.emirate) ctx.push('Known base emirate: ' + body.emirate);
    if (ctx.length) parts.push({ text: 'CONTEXT:\n' + ctx.join('\n') });
    if (body.text) parts.push({ text: 'SUPPLIER EMAIL / MESSAGE:\n' + String(body.text).slice(0, 8000) });
    if (Array.isArray(body.images)) { for (const im of body.images.slice(0, 6)) { if (im?.data && im?.mime) parts.push({ img: { mime: im.mime, data: im.data } }); } }
    if (parts.length === 0) return J({ error: 'Nothing to extract' }, 400);

    let ai;
    try { ai = await callClaude(keyRow.value, parts); }
    catch (e) { return J({ error: String((e as Error)?.message || e), fallback: true }, 200); }
    ai.service_emirates = normEmirates(ai.service_emirates);
    ai.category = normCategory(ai.category);
    return J({ ok: true, profile: ai });
  } catch (e) {
    return J({ error: String((e as Error)?.message || e), fallback: true }, 200);
  }
});
// license_extract - Document Controller vision: (1) 'license' mode reads a UAE trade licence and
// extracts the legal company name, licence no, authority, emirate/city, issue/expiry dates;
// (2) 'profile' mode reads a company profile / catalog and summarises what the company does.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const MODELS = ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8'];
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(t: string) { try { return JSON.parse(t); } catch { const m = t.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return {}; } }
function dataUrl(b64: string, mime: string) { return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/, '')}`; }
function normDate(s: unknown): string | null { const v = String(s || '').trim(); if (!v) return null; let m = v.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/); if (m) { const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])); return isNaN(d.getTime()) ? null : `${m[1]}-${String(m[2]).padStart(2,'0')}-${String(m[3]).padStart(2,'0')}`; } m = v.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/); if (m) { return `${m[3]}-${String(m[2]).padStart(2,'0')}-${String(m[1]).padStart(2,'0')}`; } const d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString().slice(0, 10); }
const EMIRATES = ['Dubai','Abu Dhabi','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah'];
function normEmirate(s: unknown): string { const t = String(s || '').toLowerCase(); for (const e of EMIRATES) if (t.includes(e.toLowerCase())) return e; if (/rak/.test(t)) return 'Ras Al Khaimah'; if (/uaq|umm al/.test(t)) return 'Umm Al Quwain'; if (/auh|abu/.test(t)) return 'Abu Dhabi'; return ''; }

const SYS_LICENSE = `You are a meticulous UAE corporate-registry document controller. You read an official UAE TRADE LICENCE (DED / DET / free-zone / e-trader) and extract its registration data EXACTLY as printed. Read every line; do not guess. Return STRICT JSON only:\n{\"legal_name\":string,\"license_number\":string,\"license_authority\":string,\"emirate\":string,\"city\":string,\"issue_date\":\"YYYY-MM-DD\",\"expiry_date\":\"YYYY-MM-DD\",\"activities\":[string],\"trn\":string,\"confidence\":\"low\"|\"medium\"|\"high\"}\nlegal_name = the exact licensed company / establishment name as printed (English). license_number = the licence / register number. license_authority = issuing authority (e.g. 'Dubai Department of Economy and Tourism', 'Sharjah Economic Development Department', 'Abu Dhabi DED', 'Ajman Free Zone'). emirate = one of Dubai, Abu Dhabi, Sharjah, Ajman, Umm Al Quwain, Ras Al Khaimah, Fujairah. city = city/area if shown else the emirate. activities = listed business activities. trn = VAT TRN if present else ''. Dates as printed, output YYYY-MM-DD. If a value is not visible use an empty string and lower the confidence. This is NOT a tax/AML check — it is commercial onboarding verification only.`;
const SYS_PROFILE = `You read a UAE supplier's COMPANY PROFILE and/or PRODUCT CATALOG and summarise what the company actually does, so QuotesDone can match it to relevant customer requests. Be factual; use only what the documents show. Return STRICT JSON only:\n{\"summary\":string,\"services\":[string],\"products\":[string],\"sectors\":[string],\"emirates\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\nsummary = 2-4 plain sentences describing the business, its core offering and strengths. services = the services they provide. products = product lines they supply (generic, no need to keep brand names). sectors = the trade categories they fit (e.g. joinery, MEP, fit-out, flooring, signage, landscaping). emirates = areas/emirates they serve if stated. Keep arrays concise (max ~12 each).`;

function buildContent(mode: string, images: any[], body: any): any[] {
  const intro = mode === 'license'
    ? 'Read the attached UAE trade licence (all pages) and return the extraction JSON.'
    : 'Read the attached company profile / catalog pages and return the summary JSON.';
  const content: any[] = [{ type: 'text', text: intro }];
  if (Array.isArray(images) && images.length) {
    for (const im of images.slice(0, 10)) { const b = im?.b64 || im; const m = im?.mime || 'image/jpeg'; if (b) content.push({ type: 'image_url', image_url: { url: dataUrl(String(b), String(m)) } }); }
  } else if (body.file_b64) {
    const mime = String(body.mime || 'application/octet-stream');
    if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
    else content.push({ type: 'file', file: { filename: String(body.filename || 'document.pdf'), file_data: dataUrl(String(body.file_b64), mime || 'application/pdf') } });
  }
  return content;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const key = await sec('openrouter_api_key'); if (!key) return J({ error: 'no ai key' }, 500);
    const mode = body.mode === 'profile' ? 'profile' : 'license';
    const images: any[] = Array.isArray(body.images) ? body.images : [];
    if (!images.length && !body.file_b64) return J({ error: 'no file' }, 400);
    const content = buildContent(mode, images, body);
    let ai: any = {};
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ models: MODELS, max_tokens: 1500, temperature: 0.1, messages: [{ role: 'system', content: mode === 'license' ? SYS_LICENSE : SYS_PROFILE }, { role: 'user', content }] }) });
      const jd = await r.json();
      if (!r.ok) return J({ error: 'ai_error', detail: jd?.error?.message || JSON.stringify(jd).slice(0, 300) }, 502);
      ai = parseJson(jd?.choices?.[0]?.message?.content || '{}');
    } catch (e) { return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

    if (mode === 'license') {
      const emirate = normEmirate(ai.emirate || ai.city);
      const doc = {
        legal_name: String(ai.legal_name || '').trim().slice(0, 200),
        license_number: String(ai.license_number || '').trim().slice(0, 60),
        license_authority: String(ai.license_authority || '').trim().slice(0, 160),
        emirate,
        city: String(ai.city || ai.emirate || '').trim().slice(0, 80) || emirate,
        issue_date: normDate(ai.issue_date),
        expiry_date: normDate(ai.expiry_date),
        activities: Array.isArray(ai.activities) ? ai.activities.map((s: any) => String(s).slice(0, 120)).slice(0, 20) : [],
        trn: String(ai.trn || '').replace(/\D/g, '').slice(0, 15),
        confidence: ['low', 'medium', 'high'].includes(ai.confidence) ? ai.confidence : 'low',
      };
      return J({ ok: true, mode, doc });
    }
    const profile = {
      summary: String(ai.summary || '').trim().slice(0, 1200),
      services: Array.isArray(ai.services) ? ai.services.map((s: any) => String(s).slice(0, 80)).slice(0, 12) : [],
      products: Array.isArray(ai.products) ? ai.products.map((s: any) => String(s).slice(0, 80)).slice(0, 12) : [],
      sectors: Array.isArray(ai.sectors) ? ai.sectors.map((s: any) => String(s).slice(0, 60)).slice(0, 12) : [],
      emirates: Array.isArray(ai.emirates) ? ai.emirates.map((s: any) => normEmirate(s)).filter(Boolean) : [],
      confidence: ['low', 'medium', 'high'].includes(ai.confidence) ? ai.confidence : 'low',
    };
    return J({ ok: true, mode, profile });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

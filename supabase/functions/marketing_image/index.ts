// marketing_image — the Marketing department's IN-HOUSE branded image maker. No external image model,
// no per-image cost: it renders a clean branded SVG card (headline + brand mark) to PNG entirely inside
// the edge runtime (resvg-wasm), uploads it to a public bucket, and returns the URL. Used for social
// posts so the agent makes its own on-brand images. Auth: __secret OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { Resvg, initWasm } from 'npm:@resvg/resvg-wasm@2.6.2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body.__secret && body.__secret === (await sec('inbound_secret'))) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

// One-time (per cold start) WASM init + font load, cached at module scope.
let wasmReady: Promise<void> | null = null;
function ensureWasm() { if (!wasmReady) wasmReady = initWasm(fetch('https://unpkg.com/@resvg/resvg-wasm@2.6.2/index_bg.wasm')); return wasmReady; }
let fontCache: Uint8Array[] | null = null;
async function loadFonts(): Promise<Uint8Array[]> {
  if (fontCache) return fontCache;
  const urls = [
    'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/poppins/Poppins-Bold.ttf',
    'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/poppins/Poppins-Regular.ttf',
  ];
  fontCache = await Promise.all(urls.map(async (u) => new Uint8Array(await (await fetch(u)).arrayBuffer())));
  return fontCache;
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
function wrap(text: string, maxChars: number): string[] {
  const words = String(text || '').trim().split(/\s+/); const lines: string[] = []; let cur = '';
  for (const w of words) { if ((cur + ' ' + w).trim().length > maxChars && cur) { lines.push(cur); cur = w; } else cur = (cur + ' ' + w).trim(); }
  if (cur) lines.push(cur); return lines.slice(0, 6);
}

function buildSvg(headline: string, eyebrow: string): string {
  const W = 1080, H = 1080, PAD = 96;
  const lines = wrap(headline, 20);
  const fs = lines.length <= 2 ? 88 : lines.length === 3 ? 74 : lines.length === 4 ? 62 : 52;
  const lh = Math.round(fs * 1.16);
  const blockH = lines.length * lh;
  let y = Math.round((H - blockH) / 2) + fs; // baseline of first line, vertically centred
  const tspans = lines.map((ln) => { const t = `<tspan x="${PAD}" y="${y}">${esc(ln)}</tspan>`; y += lh; return t; }).join('');
  const eb = eyebrow ? `<text x="${PAD}" y="252" font-family="Poppins" font-weight="700" font-size="30" letter-spacing="4" fill="#5EEAD4">${esc(eyebrow.toUpperCase().slice(0, 40))}</text>` : '';
  // Official QuotesDone brand system (from the brand kit): navy bg gradient, teal + gold, teal-ring/gold-check mark.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="bg" x1="0.12" y1="0" x2="0.88" y2="1"><stop offset="0" stop-color="#173A4B"/><stop offset="0.55" stop-color="#0C2330"/><stop offset="1" stop-color="#06121B"/></linearGradient>
    <linearGradient id="teal" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6EE7D4"/><stop offset="0.55" stop-color="#16B8A6"/><stop offset="1" stop-color="#0B8276"/></linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="#F6DD8C"/><stop offset="0.5" stop-color="#E3C065"/><stop offset="1" stop-color="#BD8E36"/></linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16B8A6"/><stop offset="1" stop-color="#E3C065"/></linearGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <rect x="0" y="0" width="14" height="${H}" fill="url(#accent)"/>
  <g transform="translate(52,40) scale(0.36)"><g transform="translate(-256,-250)"><circle cx="400" cy="398" r="92" fill="none" stroke="url(#teal)" stroke-width="50"/><path d="M434 470 L486 524 L582 408" fill="none" stroke="url(#gold)" stroke-width="44" stroke-linecap="round" stroke-linejoin="round"/></g></g>
  ${eb}
  <text font-family="Poppins" font-weight="700" font-size="${fs}" fill="#FFFFFF">${tspans}</text>
  <line x1="${PAD}" y1="${H - 150}" x2="${W - PAD}" y2="${H - 150}" stroke="#234A5C" stroke-width="2"/>
  <text x="${PAD}" y="${H - 96}" font-family="Poppins" font-weight="700" font-size="34" fill="#FFFFFF">QuotesDone</text>
  <text x="${W - PAD}" y="${H - 96}" text-anchor="end" font-family="Poppins" font-weight="400" font-size="28" fill="#8FB0C0">quotesdone.com</text>
</svg>`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);
    const headline = String(body.title || body.headline || '').trim();
    if (!headline) return J({ error: 'title required' }, 400);
    const eyebrow = String(body.eyebrow || body.subtitle || '').trim();

    await ensureWasm();
    const fonts = await loadFonts();
    const svg = buildSvg(headline, eyebrow);
    const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: 1080 }, font: { fontBuffers: fonts, defaultFontFamily: 'Poppins', loadSystemFonts: false } });
    const png = resvg.render().asPng();

    const slug = headline.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'card';
    const path = 'cards/' + slug + '-' + Date.now() + '.png';
    const { error: upErr } = await admin.storage.from('social-media').upload(path, png, { contentType: 'image/png', upsert: true });
    if (upErr) return J({ error: 'upload_failed: ' + upErr.message, bytes: png.length }, 200);
    const { data: pub } = admin.storage.from('social-media').getPublicUrl(path);
    return J({ ok: true, url: pub.publicUrl, path, bytes: png.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 200); }
});

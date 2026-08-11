// site_deploy - renders the app pages + programmatic SEO pages (services x emirates) + blog + Arabic + legal pages + sitemap/robots + llms.txt, and pushes a PRODUCTION deployment to Vercel (qd-site). Secret-guarded.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const SITE = 'https://quotesdone.com';
const ASSET = Deno.env.get('SUPABASE_URL')! + '/storage/v1/object/public/brand';
const YEAR = new Date().getUTCFullYear();
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
// Uint8Array<ArrayBuffer>, not bare Uint8Array: Deno 2 types the latter as Uint8Array<ArrayBufferLike>,
// which BufferSource does not accept because a SharedArrayBuffer-backed view cannot be hashed here.
async function sha1hex(bytes: Uint8Array<ArrayBuffer>){ const h = await crypto.subtle.digest('SHA-1', bytes); return [...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,'0')).join(''); }
function esc(s: string){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
const COSTMAP: Record<string,string> = {'electrical':'cost-of-electrical-work-uae','plumbing':'cost-of-plumbing-uae','ac-maintenance':'cost-of-ac-maintenance-uae','cleaning':'cost-of-deep-cleaning-uae','interior-design':'cost-of-fit-out-uae','joinery-kitchens':'cost-of-kitchen-uae','waterproofing':'cost-of-waterproofing-uae','tiling-marble':'cost-of-tiling-marble-uae','pest-control':'cost-of-pest-control-uae','swimming-pools':'cost-of-swimming-pool-uae','movers':'cost-of-movers-uae','handyman':'cost-of-handyman-uae','facilities-management':'cost-of-facilities-management-uae','ac-duct-cleaning':'cost-of-ac-duct-cleaning-uae','smart-home':'cost-of-smart-home-uae','solar':'cost-of-solar-uae','curtains-blinds':'cost-of-curtains-blinds-uae','cctv-security':'cost-of-cctv-installation-uae','painting':'cost-of-house-painting-uae','flooring':'cost-of-flooring-uae','false-ceiling':'cost-of-false-ceiling-uae','landscaping':'cost-of-landscaping-uae','aluminium-glass':'cost-of-aluminium-glass-uae','signage':'cost-of-signage-uae'};
const LLMS = `# QuotesDone
> QuotesDone is the UAE's anonymous quote-comparison marketplace. A customer describes a building, fit-out or home-services job once; it is sent anonymously to vetted UAE suppliers who compete with quotes the customer compares side by side. Posting is free for customers; a 3% facilitation fee applies only when the customer reveals a chosen supplier's contact details. Suppliers pay no commission on won jobs.

## Key pages
- Get free quotes: ${SITE}/app
- All services: ${SITE}/services/
- Home / how it works: ${SITE}/
- FAQ: ${SITE}/faq/
- Blog (UAE sourcing & procurement guides): ${SITE}/blog/
- Terms: ${SITE}/terms/
- Privacy: ${SITE}/privacy/

## Facts
- Coverage: Dubai, Abu Dhabi, Sharjah, Ajman, Ras Al Khaimah, Umm Al Quwain, Fujairah
- Customer cost: free to post and compare; 3% fee on the quoted value only at the point of contact reveal
- Suppliers: vetted UAE businesses; no commission and no success fee on jobs they win
- Anonymity: customer and supplier identities stay hidden until a paid reveal
- Operator: QuotesDone Technologies, Dubai DET E-Trader Licence No. 1633275, Dubai, UAE
- Contact: management@quotesdone.com
`;
let I18N = '';
const EMIRATES = [ {name:'Dubai',slug:'dubai'},{name:'Abu Dhabi',slug:'abu-dhabi'},{name:'Sharjah',slug:'sharjah'},{name:'Ajman',slug:'ajman'},{name:'Ras Al Khaimah',slug:'ras-al-khaimah'},{name:'Fujairah',slug:'fujairah'},{name:'Umm Al Quwain',slug:'umm-al-quwain'} ];
const MAIN = [
  { path: 'index.html', src: BASE + '/home' },
  { path: 'ar/index.html', src: BASE + '/home-ar' },
  { path: 'app/index.html', src: BASE + '/app' },
  { path: 'ar/app/index.html', src: BASE + '/app-ar' },
  { path: 'suppliers/index.html', src: BASE + '/portal' },
  { path: 'faq/index.html', src: BASE + '/faq' },
  { path: 'about/index.html', src: BASE + '/about' },
  { path: 'terms/index.html', src: BASE + '/legal?doc=terms' },
  { path: 'privacy/index.html', src: BASE + '/legal?doc=privacy' },
  { path: 'supplier-agreement/index.html', src: BASE + '/legal?doc=supplier' },
  { path: 'cookie-policy/index.html', src: BASE + '/legal?doc=cookie-policy' },
  { path: 'refund-policy/index.html', src: BASE + '/legal?doc=refund-policy' },
  { path: 'acceptable-use/index.html', src: BASE + '/legal?doc=acceptable-use' },
  { path: 'disclaimer/index.html', src: BASE + '/legal?doc=disclaimer' },
  { path: 'complaints/index.html', src: BASE + '/legal?doc=complaints-policy' },
];
const CSS = `:root{--bg:#05121A;--bg2:#0A1E27;--panel:rgba(255,255,255,.05);--panel2:rgba(255,255,255,.08);--line:rgba(255,255,255,.10);--line2:rgba(255,255,255,.18);--t:#EAF4F2;--muted:#9DB2B2;--faint:#5E7475;--teal:#2DD4BF;--teal2:#14B8A6;--teal-deep:#0E7C73;--gold:#E7C579;--gold2:#F2C75B;--r:16px;--maxw:1120px}
*{box-sizing:border-box}html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:radial-gradient(1000px 620px at 82% -14%,rgba(45,212,191,.16),transparent),radial-gradient(760px 520px at 4% 20%,rgba(231,197,121,.07),transparent),var(--bg);color:var(--t);font-family:Inter,system-ui,-apple-system,Segoe UI,Arial,sans-serif;line-height:1.65;-webkit-font-smoothing:antialiased;overflow-x:hidden}
a{color:var(--teal);text-decoration:none}a:hover{color:var(--teal2)}
h1,h2,h3{font-family:Sora,Inter,sans-serif;color:#fff;line-height:1.25}
p{color:#cfe0de}
.wrap{max-width:var(--maxw);margin:0 auto;padding:0 20px}
header.site{position:sticky;top:0;z-index:30;background:rgba(5,18,26,.72);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--line)}
header.site .wrap{display:flex;align-items:center;gap:16px;padding:13px 20px}
.brand{display:inline-flex;align-items:center}
.nav{display:flex;gap:20px;margin-left:6px}
.nav a{color:var(--muted);font-size:14px;font-weight:500}.nav a:hover{color:#fff}
@media(max-width:640px){.nav{display:none}}
.cta{margin-left:auto;background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04121a;font-weight:700;padding:10px 18px;border-radius:12px;box-shadow:0 10px 26px -12px rgba(45,212,191,.7)}
.cta:hover{color:#04121a;filter:brightness(1.05)}
.hero{padding:54px 0 30px;background:radial-gradient(820px 380px at 18% 0%,rgba(231,181,60,.08),transparent)}
h1{font-size:clamp(28px,4vw,42px);margin:0 0 14px;letter-spacing:-.02em}
.lead{font-size:clamp(16px,2vw,19px);color:var(--muted);max-width:730px;margin:0}
.btn{display:inline-block;background:linear-gradient(135deg,var(--teal),var(--teal2));color:#04121a;font-weight:700;padding:13px 24px;border-radius:14px;margin-top:20px;box-shadow:0 14px 34px -14px rgba(45,212,191,.7)}
.btn:hover{color:#04121a;filter:brightness(1.05)}
section{padding:24px 0}
h2{font-size:clamp(20px,2.4vw,26px);margin:0 0 14px;letter-spacing:-.01em}
ul.ticks{list-style:none;padding:0;margin:0}
ul.ticks li{padding:8px 0 8px 30px;position:relative;color:#cfe0de}
ul.ticks li:before{content:'✓';color:var(--teal);position:absolute;left:0;font-weight:800}
.steps{display:flex;flex-wrap:wrap;gap:16px}
.step{flex:1;min-width:220px;background:var(--panel);border:1px solid var(--line);border-radius:var(--r);padding:18px}
.step b{color:#fff;display:block;margin-bottom:6px;font-family:Sora,Inter,sans-serif}
.step div{color:var(--muted)}
.faq{border-top:1px solid var(--line);padding:16px 0}
.faq b{display:block;margin-bottom:6px;color:#fff;font-family:Sora,Inter,sans-serif}
.faq div{color:var(--muted)}
.links a{display:inline-block;margin:6px 14px 6px 0}
.chips a{display:inline-block;background:var(--panel);border:1px solid var(--line2);color:var(--t);border-radius:999px;padding:8px 15px;margin:5px 8px 5px 0;font-size:14px}
.chips a:hover{border-color:var(--teal);color:#fff}
.tldr{background:linear-gradient(180deg,rgba(20,184,166,.10),rgba(20,184,166,.04));border:1px solid var(--line2);border-left:4px solid var(--teal);border-radius:12px;padding:16px 18px;margin:18px 0;color:#dff1ee;font-size:15px}
.tldr b{color:#fff}.tldr a{font-weight:600}
.blist{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}
@media(max-width:900px){.blist{grid-template-columns:repeat(2,1fr)}}
@media(max-width:620px){.blist{grid-template-columns:1fr}}
.bpost{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:18px;overflow:hidden;background:var(--panel);text-decoration:none;color:inherit;transition:transform .16s ease,border-color .16s ease,box-shadow .16s ease}
.bpost:hover{transform:translateY(-4px);border-color:var(--line2);box-shadow:0 22px 50px -24px rgba(0,0,0,.7)}
.bcover{aspect-ratio:16/9;display:block;background:#0A1E27}
.bcover svg{width:100%;height:100%;display:block}
.bbody{padding:16px 18px 20px}
.bchip{display:inline-block;font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--gold2);background:rgba(231,181,60,.12);border:1px solid rgba(231,181,60,.28);padding:4px 10px;border-radius:999px;margin-bottom:10px}
.bpost h2{font-size:18px;margin:0 0 8px;line-height:1.32}
.bpost p{color:var(--muted);margin:0 0 12px;font-size:14.5px}
.bpost .more{color:var(--teal);font-weight:700;font-size:14px}
.article{max-width:760px;font-size:16.5px}
.article h2{margin-top:32px;font-size:22px}
.article h3{margin-top:22px;font-size:18px;color:#fff;font-family:Sora,Inter,sans-serif}
.article p{color:#d4e4e2}
.article ul,.article ol{padding-left:22px}.article li{margin:6px 0;color:#d4e4e2}
.article a{font-weight:600}.article strong{color:#fff}
.article table{width:100%;border-collapse:collapse;margin:16px 0;font-size:15px}
.article th,.article td{border:1px solid var(--line);padding:9px 11px;text-align:left;color:#d4e4e2}
.article th{background:var(--panel);color:#fff}
.hero-cover{height:240px;border-radius:18px;overflow:hidden;border:1px solid var(--line);margin:4px 0 6px}
.hero-cover svg{display:block;width:100%;height:100%}
@media(max-width:620px){.hero-cover{height:170px}}
.crumb{font-size:13px;color:var(--faint);margin-bottom:10px}
.crumb a{color:var(--muted)}
footer.site{border-top:1px solid var(--line);background:linear-gradient(180deg,transparent,rgba(10,30,39,.55));margin-top:44px;padding:46px 0 28px}
.fgrid{display:grid;grid-template-columns:1.5fr 1fr 1fr 1.25fr;gap:34px}
@media(max-width:820px){.fgrid{grid-template-columns:1fr 1fr}}
@media(max-width:520px){.fgrid{grid-template-columns:1fr}}
.fcol h4{font-family:Sora,Inter,sans-serif;font-size:12px;text-transform:uppercase;letter-spacing:.09em;color:var(--faint);margin:0 0 14px}
.fcol a{display:block;color:var(--muted);font-size:14px;padding:5px 0}.fcol a:hover{color:#fff}
.fbrand p{color:var(--muted);font-size:14px;max-width:290px;margin:14px 0 16px}
.fsocial{display:flex;gap:10px}
.fsocial a{width:38px;height:38px;border:1px solid var(--line2);border-radius:10px;display:flex;align-items:center;justify-content:center;color:var(--muted)}
.fsocial a:hover{color:#fff;border-color:var(--teal)}
.fcontact a{display:flex;align-items:center;gap:10px;color:var(--t);font-size:14px;padding:6px 0;font-weight:500}
.fcontact a:hover{color:var(--teal)}
.fcontact svg{flex:0 0 auto;color:var(--teal)}
.fbar{border-top:1px solid var(--line);margin-top:32px;padding-top:18px;display:flex;flex-wrap:wrap;gap:8px;justify-content:space-between;color:var(--faint);font-size:12.5px}`;
const HEADER = `<header class="site"><div class="wrap"><a class="brand" href="/"><img src="${ASSET}/qd_lockup_light.png?v=2" alt="QuotesDone" style="height:26px;width:auto;display:block"></a><nav class="nav"><a href="/services/">Services</a><a href="/blog/">Blog</a><a href="/faq/">FAQ</a><a href="/about/">About</a><a href="/contact/">Contact</a></nav><a class="cta" href="/app">Get free quotes</a></div></header>`;
const IG='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="currentColor" stroke="none"/></svg>';
const LI='<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M4.98 3.5A2.5 2.5 0 1 0 5 8.5a2.5 2.5 0 0 0 0-5zM3 9h4v12H3zM9 9h3.8v1.7h.05c.53-1 1.83-2.05 3.77-2.05C20.4 8.65 21 11 21 14.1V21h-4v-6.1c0-1.45-.03-3.3-2-3.3-2 0-2.3 1.57-2.3 3.2V21H9z"/></svg>';
const FB='<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M13 22v-8h2.7l.4-3H13V9c0-.9.25-1.5 1.5-1.5H16V4.9c-.3 0-1.3-.1-2.4-.1-2.4 0-4 1.45-4 4.1V11H7v3h2.6v8z"/></svg>';
const MAILI='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6"/></svg>';
const PHI='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 4h4l2 5-3 2a12 12 0 0 0 5 5l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/></svg>';
const FOOTER = `<footer class="site"><div class="wrap"><div class="fgrid"><div class="fcol fbrand"><a href="/"><img src="${ASSET}/qd_lockup_light.png?v=2" alt="QuotesDone" style="height:28px;width:auto;display:block"></a><p>The UAE's anonymous quotation marketplace. Post your job once, compare vetted suppliers, and reveal only the one you choose.</p><div class="fsocial"><a href="https://www.instagram.com/official.quotesdone" aria-label="Instagram">${IG}</a><a href="https://www.linkedin.com/company/quotesdone" aria-label="LinkedIn">${LI}</a><a href="https://www.facebook.com/quotesdone.UAE" aria-label="Facebook">${FB}</a></div></div><div class="fcol"><h4>Explore</h4><a href="/">How it works</a><a href="/app">Get free quotes</a><a href="/services/">All services</a><a href="/faq/">FAQ</a><a href="/blog/">Blog</a><a href="/about/">About us</a><a href="/contact/">Contact</a></div><div class="fcol"><h4>Legal</h4><a href="/terms/">Terms</a><a href="/privacy/">Privacy</a><a href="/supplier-agreement/">Supplier Agreement</a><a href="/refund-policy/">Refunds</a><a href="/cookie-policy/">Cookies</a><a href="/acceptable-use/">Acceptable Use</a><a href="/complaints/">Complaints</a></div><div class="fcol fcontact"><h4>Contact</h4><a href="mailto:management@quotesdone.com">${MAILI}<span>management@quotesdone.com</span></a><a href="/contact/">${PHI}<span>Contact &amp; phone</span></a></div></div><div class="fbar"><div>&copy; ${YEAR} QuotesDone Technologies · Dubai DET E-Trader Licence No. 1633275 · Dubai, UAE</div><div>Made in the UAE</div></div></div></footer>`;
function page(o: {title:string;desc:string;canonical:string;jsonld:any[];body:string}){
  const head = `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet"><link rel="icon" href="${ASSET}/favicon.ico" sizes="any"><link rel="icon" type="image/png" sizes="32x32" href="${ASSET}/favicon-32.png"><link rel="apple-touch-icon" href="${ASSET}/apple-touch.png"><meta name="theme-color" content="#05121A">`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.title)}</title><meta name="description" content="${esc(o.desc)}"><link rel="canonical" href="${o.canonical}">${head}<meta property="og:title" content="${esc(o.title)}"><meta property="og:description" content="${esc(o.desc)}"><meta property="og:type" content="website"><meta property="og:url" content="${o.canonical}"><meta property="og:image" content="${ASSET}/qd_mark.png">${o.jsonld.map((j)=>`<script type="application/ld+json">${JSON.stringify(j)}</script>`).join('')}<style>${CSS}</style></head><body>${HEADER}${o.body}${FOOTER}${I18N}</body></html>`;
}
function h32(s: string){ let h=2166136261; for(let i=0;i<s.length;i++){ h^=s.charCodeAt(i); h=Math.imul(h,16777619);} return h>>>0; }
const GRADS=[['#0F766E','#05121A'],['#14B8A6','#08222A'],['#0E7C73','#0A1E27'],['#116E67','#05121A'],['#0D9488','#08222A'],['#15807A','#05121A']];
function iconInner(t: string){ t=(t||'').toLowerCase();
  if(/electr|bolt/.test(t)) return '<path d="M27 6 L13 27 h9 l-2 15 L35 19 h-9 z" fill="#EAF4F2" stroke="none"/>';
  if(/plumb|waterproof|drain|pipe/.test(t)) return '<path d="M24 7 C24 7 13 21 13 30 a11 11 0 0 0 22 0 C35 21 24 7 24 7 Z"/>';
  if(/ac-|hvac|duct|cool|air-?con/.test(t)) return '<path d="M24 6 V42 M6 24 H42 M11 11 L37 37 M37 11 L11 37"/>';
  if(/paint/.test(t)) return '<path d="M10 40 c1-6 3-9 8-9 M18 31 L34 15 l4 4 -16 16 z M31 12 l5 5"/>';
  if(/fire/.test(t)) return '<path d="M25 6 c5 8 10 10 10 18 a11 11 0 0 1-22 0 c0-5 3-8 5-11 1 3 3 4 5 4 -2-6 -1-8 2-11z"/>';
  if(/cctv|camera|surveil/.test(t)) return '<rect x="7" y="17" width="22" height="14" rx="2"/><path d="M29 21 L41 16 V32 L29 27 Z"/>';
  if(/security|guard|access/.test(t)) return '<path d="M24 6 L38 12 V24 c0 10-6 15-14 18 -8-3-14-8-14-18 V12 Z"/>';
  if(/solar/.test(t)) return '<circle cx="24" cy="24" r="8"/><path d="M24 4 V10 M24 38 V44 M4 24 H10 M38 24 H44 M9 9 L13 13 M35 35 L39 39 M39 9 L35 13 M13 35 L9 39"/>';
  if(/pool|swim/.test(t)) return '<path d="M5 22 q6-6 12 0 t12 0 t14 0 M5 32 q6-6 12 0 t12 0 t14 0"/>';
  if(/landscap|garden/.test(t)) return '<path d="M12 38 C12 20 28 9 40 9 40 21 30 38 12 38 Z M14 36 C20 30 28 24 36 20"/>';
  if(/pest/.test(t)) return '<ellipse cx="24" cy="27" rx="9" ry="11"/><path d="M24 16 V10 M15 22 L8 18 M33 22 L40 18 M15 32 L8 35 M33 32 L40 35"/>';
  if(/mov|reloc/.test(t)) return '<path d="M8 17 L24 9 40 17 24 25 Z M8 17 V35 L24 43 V25 M40 17 V35 L24 43"/>';
  if(/sign/.test(t)) return '<rect x="9" y="9" width="30" height="18" rx="2"/><path d="M24 27 V40 M16 40 H32"/>';
  if(/curtain|blind/.test(t)) return '<path d="M9 8 H39 M14 8 V38 q3-4 0-8 M22 8 V38 q3-4 0-8 M30 8 V38 q3-4 0-8"/>';
  if(/alumin|glass|window|facade/.test(t)) return '<rect x="10" y="8" width="28" height="32" rx="1"/><path d="M24 8 V40 M10 24 H38"/>';
  if(/floor|tile|marble/.test(t)) return '<path d="M8 8 H40 V40 H8 Z M24 8 V40 M8 24 H40"/>';
  if(/clean/.test(t)) return '<path d="M24 8 l3.2 9.6 9.6 3.2 -9.6 3.2 -3.2 9.6 -3.2-9.6 -9.6-3.2 9.6-3.2z" fill="#EAF4F2" stroke="none"/>';
  if(/material|building|steel/.test(t)) return '<path d="M8 17 L24 9 40 17 24 25 Z M8 17 V35 L24 43 V25 M40 17 V35 L24 43"/>';
  if(/facilit|handyman|mainten|repair/.test(t)) return '<circle cx="24" cy="24" r="7"/><path d="M24 8 V13 M24 35 V40 M8 24 H13 M35 24 H40 M12 12 L16 16 M32 32 L36 36 M36 12 L32 16 M16 32 L12 36"/>';
  if(/kitchen|joinery|fit-?out|interior|ceiling|smart|home|design/.test(t)) return '<path d="M8 24 L24 10 L40 24 M12 21 V40 H36 V21"/>';
  return '<rect x="12" y="8" width="24" height="32" rx="2"/><path d="M17 18 H31 M17 24 H31 M17 30 H26"/>';
}
function coverSVG(slug: string, label: string, tall: boolean){
  const H=h32(slug); const g=GRADS[H%GRADS.length]; const id='g'+(H%100000);
  const c1x=120+(H%560), c1y=50+((H>>3)%150), r1=120+((H>>5)%90);
  const c2x=520+((H>>7)%240), c2y=250+((H>>9)%130), r2=90+((H>>11)%70);
  const par = tall ? 'preserveAspectRatio="xMidYMid slice"' : '';
  return `<svg viewBox="0 0 800 450" ${par} xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${esc(label)}"><defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${g[0]}"/><stop offset="1" stop-color="${g[1]}"/></linearGradient></defs><rect width="800" height="450" fill="url(#${id})"/><circle cx="${c1x}" cy="${c1y}" r="${r1}" fill="#ffffff" opacity="0.05"/><circle cx="${c2x}" cy="${c2y}" r="${r2}" fill="#2DD4BF" opacity="0.08"/><g transform="translate(300,78) scale(4.4)" fill="none" stroke="#EAF4F2" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" opacity="0.9">${iconInner(slug+' '+label)}</g><rect x="48" y="372" width="40" height="4" rx="2" fill="#E7C579"/><text x="48" y="407" fill="#EAF4F2" font-family="Sora,Inter,sans-serif" font-size="26" font-weight="700">${esc(label)}</text></svg>`;
}
function seoPage(c: any, em: any|null, cats: any[]){
  const loc = em ? em.name : 'the UAE';
  const slugUrl = em ? `/services/${c.slug}-in-${em.slug}/` : `/services/${c.slug}/`;
  const canonical = SITE + slugUrl;
  const title = `${c.name} in ${loc} — Get Free Quotes | QuotesDone`;
  const desc = `Compare free quotes from vetted ${c.name.toLowerCase()} suppliers in ${loc}. Describe your job once on QuotesDone and get multiple quotes to compare.`;
  const includes = Array.isArray(c.includes) ? c.includes : [];
  const faqs = Array.isArray(c.faqs) ? c.faqs : [];
  const otherEm = EMIRATES.filter((e)=> !em || e.slug!==em.slug).slice(0,7).map((e)=>`<a href="/services/${c.slug}-in-${e.slug}/">${esc(c.name)} in ${esc(e.name)}</a>`).join('');
  const otherCats = cats.filter((x)=>x.slug!==c.slug).slice(0,8).map((x)=>`<a href="/services/${x.slug}/">${esc(x.name)}</a>`);
  const jsonld: any[] = [
    { '@context':'https://schema.org','@type':'Service','serviceType':c.name,'areaServed': em?{ '@type':'City','name':em.name }:{ '@type':'Country','name':'United Arab Emirates' },'provider':{ '@type':'Organization','name':'QuotesDone','url':SITE } },
    { '@context':'https://schema.org','@type':'BreadcrumbList','itemListElement':[ {'@type':'ListItem','position':1,'name':'Home','item':SITE+'/'}, {'@type':'ListItem','position':2,'name':'Services','item':SITE+'/services/'}, {'@type':'ListItem','position':3,'name':c.name+(em?(' in '+em.name):''),'item':canonical} ] },
  ];
  if (faqs.length) jsonld.push({ '@context':'https://schema.org','@type':'FAQPage','mainEntity': faqs.map((f:any)=>({ '@type':'Question','name':String(f.q||''),'acceptedAnswer':{ '@type':'Answer','text':String(f.a||'') } })) });
  const tldr = `To get ${esc(c.name.toLowerCase())} quotes in ${esc(loc)}, describe your job once on QuotesDone — it is sent anonymously to vetted ${esc(loc)} suppliers who send comparable quotes you review side by side. Posting is free; you pay a 3% fee only when you reveal the supplier you choose.`;
  const body = `<div class="hero"><div class="wrap"><div class="crumb"><a href="/">Home</a> · <a href="/services/">Services</a></div><h1>${esc(c.name)} in ${esc(loc)}</h1><p class="lead">Get free, no-obligation quotes from vetted ${esc(c.name.toLowerCase())} suppliers${em?(' in '+esc(em.name)):' across the UAE'}. Describe your job once — compare multiple quotes in one place.</p><a class="btn" href="/app">Get free quotes →</a></div></div>`+
    `<div class="wrap"><div class="tldr"><b>Quick answer:</b> ${tldr}</div></div>`+
    (COSTMAP[c.slug]?`<div class="wrap"><div class="tldr"><b>Budgeting?</b> See <a href="/blog/${COSTMAP[c.slug]}/">typical ${esc(c.name)} prices in the UAE →</a></div></div>`:'')+
    `<div class="wrap"><section><p>${esc(c.intro||'')}</p></section>`+
    (includes.length?`<section><h2>What you can request</h2><ul class="ticks">${includes.map((i:string)=>`<li>${esc(i)}</li>`).join('')}</ul></section>`:'')+
    `<section><h2>How QuotesDone works</h2><div class="steps"><div class="step"><b>1. Describe your job</b><div>Tell our smart engine what you need — by text, voice, photo or drawing. It builds a clear request.</div></div><div class="step"><b>2. Get matched quotes</b><div>We send it to relevant ${esc(loc)} suppliers and collect their quotes for you to compare.</div></div><div class="step"><b>3. Reveal &amp; hire</b><div>Compare prices and scope side-by-side, then reveal the supplier you want and deal directly.</div></div></div><a class="btn" href="/app">Start your request →</a></section>`+
    (faqs.length?`<section><h2>${esc(c.name)} in ${esc(loc)} — FAQs</h2>${faqs.map((f:any)=>`<div class="faq"><b>${esc(f.q||'')}</b><div>${esc(f.a||'')}</div></div>`).join('')}</section>`:'')+
    `<section><h2>${esc(c.name)} across the UAE</h2><div class="links">${otherEm}</div></section>`+
    `<section><h2>Other services on QuotesDone</h2><div class="chips">${otherCats.join('')}</div></section>`+
    `</div>`;
  return page({ title, desc, canonical, jsonld, body });
}
function hubPage(cats: any[]){
  const canonical = SITE+'/services/';
  const body = `<div class="hero"><div class="wrap"><div class="crumb"><a href="/">Home</a> · Services</div><h1>Building, fit-out &amp; home services in the UAE</h1><p class="lead">Get free quotes from vetted suppliers for any job — describe it once and compare.</p><a class="btn" href="/app">Get free quotes →</a></div></div><div class="wrap"><section><h2>Browse services</h2><div class="chips">${cats.map((c)=>`<a href="/services/${c.slug}/">${esc(c.name)}</a>`).join('')}</div></section></div>`;
  return page({ title:'UAE Building, Fit-out & Home Services — Get Free Quotes | QuotesDone', desc:'Compare free quotes from vetted UAE suppliers across electrical, plumbing, AC, cleaning, fit-out, joinery and more. Describe your job once on QuotesDone.', canonical, jsonld:[{ '@context':'https://schema.org','@type':'WebSite','name':'QuotesDone','url':SITE }], body });
}
function blogHub(posts: any[]){
  const canonical = SITE+'/blog/';
  const cards = posts.map((p)=>`<a class="bpost" href="/blog/${p.slug}/"><div class="bcover">${coverSVG(p.slug,p.category||'Guide',false)}</div><div class="bbody">${p.category?`<span class="bchip">${esc(p.category)}</span>`:''}<h2>${esc(p.title)}</h2><p>${esc(p.excerpt||'')}</p><span class="more">Read guide →</span></div></a>`).join('');
  const body = `<div class="hero"><div class="wrap"><div class="crumb"><a href="/">Home</a> · Blog</div><h1>QuotesDone blog</h1><p class="lead">Practical guides for buying building, fit-out and home services in the UAE — real price ranges, checklists and the right questions to ask suppliers before you sign.</p></div></div><div class="wrap"><section><div class="blist">${cards}</div></section><section><div class="tldr"><b>Ready to get quotes?</b> Describe your job once and compare anonymised quotes from vetted UAE suppliers. <a href="/app">Get free quotes →</a></div></section></div>`;
  return page({ title:'QuotesDone Blog — UAE sourcing & procurement guides', desc:'Practical guides for comparing quotes and buying building, fit-out and home services in the UAE.', canonical, jsonld:[{ '@context':'https://schema.org','@type':'Blog','name':'QuotesDone Blog','url':canonical }], body });
}
function blogPost(p: any, posts: any[]){
  const canonical = SITE+'/blog/'+p.slug+'/';
  const others = posts.filter((x)=>x.slug!==p.slug).slice(0,4).map((x)=>`<a href="/blog/${x.slug}/">${esc(x.title)}</a>`).join('');
  const jsonld: any[] = [
    { '@context':'https://schema.org','@type':'Article','headline':p.title,'description':p.meta_desc||p.excerpt||'','datePublished':p.published_at,'dateModified':p.updated_at||p.published_at,'author':{ '@type':'Organization','name':'QuotesDone' },'publisher':{ '@type':'Organization','name':'QuotesDone','logo':{ '@type':'ImageObject','url':ASSET+'/qd_mark.png' } },'mainEntityOfPage':canonical },
    { '@context':'https://schema.org','@type':'BreadcrumbList','itemListElement':[ {'@type':'ListItem','position':1,'name':'Home','item':SITE+'/'}, {'@type':'ListItem','position':2,'name':'Blog','item':SITE+'/blog/'}, {'@type':'ListItem','position':3,'name':p.title,'item':canonical} ] },
  ];
  const body = `<div class="hero"><div class="wrap"><div class="crumb"><a href="/blog/">Blog</a>${p.category?(' · '+esc(p.category)):''}</div><h1>${esc(p.title)}</h1></div></div><div class="wrap"><div class="hero-cover">${coverSVG(p.slug,p.category||'Guide',true)}</div>`+(p.excerpt?`<div class="tldr"><b>Quick answer:</b> ${esc(p.excerpt)}</div>`:'')+`<article class="article">${p.body_html||''}</article><section><div class="tldr"><b>Get this done.</b> Compare free, anonymised quotes from vetted UAE suppliers for this job. <a href="/app">Start your request →</a></div></section>`+(others?`<section><h2>More guides</h2><div class="chips">${others}</div></section>`:'')+`</div>`;
  return page({ title:p.title+' | QuotesDone', desc:p.meta_desc||p.excerpt||'', canonical, jsonld, body });
}
function contactPage(){
  const canonical = SITE+'/contact/';
  const AK = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
  const inp = 'width:100%;background:var(--panel);border:1px solid var(--line2);color:var(--t);border-radius:10px;padding:11px 13px;font:inherit';
  const body = `<div class="hero"><div class="wrap"><div class="crumb"><a href="/">Home</a> · Contact</div><h1>Contact QuotesDone</h1><p class="lead">Questions about posting a job, joining as a supplier, or anything else? Send a message and we will reply by email, or reach us directly.</p></div></div><div class="wrap"><section class="steps" style="align-items:flex-start"><div class="step"><b>Reach us directly</b><div style="margin-top:10px"><a href="mailto:management@quotesdone.com" style="display:flex;gap:10px;align-items:center;padding:7px 0;color:var(--t)">${MAILI}<span>management@quotesdone.com</span></a><a href="tel:+971509319355" style="display:flex;gap:10px;align-items:center;padding:7px 0;color:var(--t)">${PHI}<span>+971 50 931 9355</span></a></div><div style="color:var(--muted);font-size:14px;margin-top:12px">Sun to Thu, 9am to 6pm (GST)<br>Dubai, UAE · DET E-Trader Licence No. 1633275</div></div><div class="step"><b>Send a message</b><form id="cform" style="margin-top:12px;display:flex;flex-direction:column;gap:10px"><input name="name" placeholder="Your name" autocomplete="name" style="${inp}"><input name="email" type="email" required placeholder="Email" autocomplete="email" style="${inp}"><input name="phone" placeholder="Phone (optional)" autocomplete="tel" style="${inp}"><textarea name="message" required rows="4" placeholder="How can we help?" style="${inp};resize:vertical"></textarea><input name="company" tabindex="-1" autocomplete="off" aria-hidden="true" style="position:absolute;left:-9999px;width:1px;height:1px"><button class="btn" type="submit" style="margin-top:2px;border:0;cursor:pointer">Send message</button><div id="cmsg" style="font-size:14px;color:var(--muted);min-height:18px"></div></form></div></section></div><script>(function(){var F=document.getElementById('cform'),M=document.getElementById('cmsg');F.addEventListener('submit',function(e){e.preventDefault();M.style.color='var(--muted)';M.textContent='Sending...';var d={};new FormData(F).forEach(function(v,k){d[k]=v;});fetch('${BASE}/contact_submit',{method:'POST',headers:{'Content-Type':'application/json','apikey':'${AK}','Authorization':'Bearer '+'${AK}'},body:JSON.stringify(d)}).then(function(r){return r.json();}).then(function(j){if(j&&j.ok){F.reset();M.style.color='var(--teal)';M.textContent='Thanks. Your message has been sent and we will reply by email.';}else{M.style.color='#f0a0a0';M.textContent=(j&&j.error)||'Could not send. Please try again.';}}).catch(function(){M.style.color='#f0a0a0';M.textContent='Network error. Please try again.';});});})();</script>`;
  return page({ title:'Contact QuotesDone — get in touch', desc:'Contact QuotesDone by email, phone or message form. For customers and suppliers across the UAE.', canonical, jsonld:[{ '@context':'https://schema.org','@type':'ContactPage','name':'Contact QuotesDone','url':canonical }], body });
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'site_deploy');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    try { I18N = await (await fetch(ASSET + '/i18n_chrome.html')).text(); } catch(_e){ I18N=''; }
    const token = await sec('vercel_token'); const team = await sec('vercel_team_id'); const project = (await sec('vercel_project')) || 'qd-site';
    if (!token || !team) return J({ ok:false, error:'vercel_not_configured' }, 200);
    const H = { Authorization: 'Bearer ' + token };
    const pages: { path: string; html: string }[] = [];
    for (const p of MAIN) { try { const html = await (await fetch(p.src)).text(); pages.push({ path:p.path, html }); } catch(_e){} }
    pages.push({ path:'llms.txt', html: LLMS });
    pages.push({ path:'contact/index.html', html: contactPage() });
    const { data: cats } = await admin.from('seo_categories').select('slug,name,intro,includes,faqs,search_term').eq('generated', true).order('sort');
    const C = cats || [];
    const { data: bposts } = await admin.from('blog_posts').select('slug,title,excerpt,meta_desc,body_html,category,published_at,updated_at').eq('published', true).order('sort');
    const BP = bposts || [];
    if (BP.length) { pages.push({ path:'blog/index.html', html: blogHub(BP) }); for (const p of BP) pages.push({ path:`blog/${p.slug}/index.html`, html: blogPost(p, BP) }); }
    if (C.length) {
      pages.push({ path:'services/index.html', html: hubPage(C) });
      for (const c of C) {
        pages.push({ path:`services/${c.slug}/index.html`, html: seoPage(c, null, C) });
        for (const em of EMIRATES) pages.push({ path:`services/${c.slug}-in-${em.slug}/index.html`, html: seoPage(c, em, C) });
      }
      const urls = [ SITE+'/', SITE+'/ar/', SITE+'/app', SITE+'/ar/app', SITE+'/services/', SITE+'/faq/', SITE+'/contact/' ];
      for (const c of C){ urls.push(SITE+`/services/${c.slug}/`); for (const em of EMIRATES) urls.push(SITE+`/services/${c.slug}-in-${em.slug}/`); }
      if (BP.length){ urls.push(SITE+'/blog/'); for (const p of BP) urls.push(SITE+`/blog/${p.slug}/`); }
      const sitemap = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`+urls.map((u)=>`<url><loc>${u}</loc></url>`).join('\n')+`\n</urlset>`;
      pages.push({ path:'sitemap.xml', html: sitemap });
      pages.push({ path:'robots.txt', html: `User-agent: *\nAllow: /\nSitemap: ${SITE}/sitemap.xml\n` });
    }
    const files: { file: string; sha: string; size: number }[] = [];
    const work = pages.map((p)=>({ p, bytes: new TextEncoder().encode(p.html) }));
    const CH = 16;
    for (let i=0;i<work.length;i+=CH){
      const chunk = work.slice(i, i+CH);
      await Promise.all(chunk.map(async (w)=>{ const sha = await sha1hex(w.bytes); const up = await fetch('https://api.vercel.com/v2/files?teamId='+team, { method:'POST', headers:{ ...H,'Content-Type':'application/octet-stream','x-vercel-digest':sha }, body:w.bytes }); if(up.ok) files.push({ file:w.p.path, sha, size:w.bytes.length }); }));
    }
    const dep = await fetch('https://api.vercel.com/v13/deployments?teamId=' + team + '&forceNew=1', { method:'POST', headers:{ ...H,'Content-Type':'application/json' }, body: JSON.stringify({ name: project, project, target:'production', files, projectSettings:{ framework:null } }) });
    const dj = await dep.json();
    if (!dep.ok) return J({ ok:false, error:'deploy_failed', status:dep.status, detail: JSON.stringify(dj?.error||dj).slice(0,300), files: files.length }, 200);
    return J({ ok:true, deployment_id: dj.id, url: dj.url, readyState: dj.readyState, files: files.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
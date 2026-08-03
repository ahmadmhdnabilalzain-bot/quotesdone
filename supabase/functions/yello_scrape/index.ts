import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const BASE = 'https://www.yello.ae';

async function getHtml(url: string, ms = 12000): Promise<string|null> {
  try {
    const c = new AbortController(); const t = setTimeout(() => c.abort(), ms);
    const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'text/html' }, signal: c.signal });
    clearTimeout(t);
    if (!r.ok) return null;
    return await r.text();
  } catch { return null; }
}

function sectorFor(cats: string[], src: string): string {
  const h = (cats.join(' ') + ' ' + src).toLowerCase();
  const map: [RegExp,string][] = [
    [/elevator|lift\b|escalator/,'elevators'],
    [/cater/,'catering'],
    [/\bevent|exhibition stand|wedding planning/,'events'],
    [/visa|pro service|typing|immigration|tasheel|amer|attestation/,'visa-pro-services'],
    [/garment|t-?shirt|uniform|clothing|apparel|tailor|embroidery/,'garments'],
    [/advertis|signage|sign board|printing|print shop|graphic/,'printing-signage'],
    [/joinery|carpentry|wooden|furniture|wood work/,'carpentry'],
    [/aluminium|aluminum/,'aluminium'],
    [/glass/,'glass'],
    [/acrylic|solid surface/,'acrylic'],
    [/steel|metal|fabrica|welding/,'steel'],
    [/floor|tiles?|marble|parquet|vinyl/,'flooring'],
    [/landscap|garden|softscape|hardscape/,'landscaping'],
    [/swimming pool|pool/,'swimming_pool'],
    [/gypsum|drywall|partition|false ceiling/,'gypsum'],
    [/paint|wallpaper/,'painting'],
    [/scaffold/,'scaffolding'],
    [/curtain|blinds|upholst/,'upholstery'],
    [/contractor|construction|fit-?out|fitout|interior/,'fitout'],
    [/building material|hardware|sanitary|plumbing|chemical|adhesive|roofing|cement|concrete|stone/,'building-materials'],
    [/trad(e|ing|ers)|supplier|general trading/,'trading']
  ];
  for (const [re,s] of map) if (re.test(h)) return s;
  return 'general';
}

function parseListing(html: string): {id:string,slug:string}[] {
  const out: Record<string,string> = {};
  const re = /\/company\/(\d+)\/([a-z0-9-]+)/gi; let m;
  while ((m = re.exec(html)) !== null) { out[m[1]] = m[2]; }
  return Object.entries(out).map(([id,slug]) => ({id,slug}));
}

function parseProfile(html: string) {
  const pick = (re: RegExp) => { const m = html.match(re); return m ? m[1].trim() : null; };
  let name = pick(/<title>([^<]+?)\s*-\s*[^<]*<\/title>/i) || pick(/<h1[^>]*>([^<]+)<\/h1>/i);
  // website: external link after 'Website address'
  let website: string|null = null;
  const wm = html.match(/Website address[\s\S]{0,300}?href=\"(https?:\/\/[^\"]+)\"/i);
  if (wm) website = wm[1];
  if (!website) {
    const re = /href=\"(https?:\/\/(?!www\.yello\.ae|yello\.ae|maps\.google|wa\.me|www\.facebook|facebook\.com|twitter\.com|x\.com|www\.linkedin|linkedin\.com|instagram\.com|api\.whatsapp)[^\"]+)\"/gi; let m; const cands: string[] = [];
    while ((m = re.exec(html)) !== null) cands.push(m[1]);
    if (cands.length) website = cands[0];
  }
  if (website) { try { const u = new URL(website); website = u.protocol + '//' + u.host; } catch { /* */ } }
  const phones = [...html.matchAll(/\+971[\d\s\-]{6,14}\d/g)].map(x => x[0].replace(/\s+/g,' ').trim());
  const phone = phones[0] || null; const mobile = phones.find(p => /\+971\s?5/.test(p)) || null;
  const wa = pick(/wa\.me\/(\d{8,15})/);
  const cats = [...html.matchAll(/\/category\/([a-z0-9-]+)(?:\/city:|\"|#)/gi)].map(x => x[1]);
  const ucats = [...new Set(cats)].filter(c => !['others'].includes(c)).slice(0, 25);
  const manager = pick(/Company manager<\/[^>]+>\s*<[^>]*>([^<]+)</i) || pick(/Company manager[\s\S]{0,80}?>([A-Z][A-Za-z .'-]{2,40})</);
  const established = pick(/Establishment year[\s\S]{0,80}?(\b(?:19|20)\d{2}\b)/i);
  return { name, website, phone, mobile, whatsapp: wa, categories: ucats, manager, established };
}

function extractEmails(html: string, host?: string): string|null {
  const raw = [...html.matchAll(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g)].map(x => x[0].toLowerCase());
  const bad = /(\.png|\.jpg|\.jpeg|\.gif|\.webp|\.svg|example\.com|sentry|wixpress|\.wix|godaddy|cloudflare|@2x|@3x|u002|placeholder|yourdomain|email@|name@|domain\.com)/;
  const seen = new Set<string>(); const ok: string[] = [];
  for (const e of raw) { if (bad.test(e)) continue; if (e.length > 60) continue; if (seen.has(e)) continue; seen.add(e); ok.push(e); }
  if (!ok.length) return null;
  const dom = host ? host.replace(/^www\./,'') : '';
  const score = (e: string) => {
    let s = 0; const d = e.split('@')[1];
    if (dom && d.includes(dom)) s += 10;
    if (/^(info|sales|contact|enquiry|enquiries|admin|hello|office)@/.test(e)) s += 5;
    if (/(gmail|hotmail|yahoo|outlook)\./.test(d)) s -= 1;
    return s;
  };
  ok.sort((a,b) => score(b) - score(a));
  return ok[0];
}

// AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
// per-context credential and the legacy shared secret, and records which one called.
//
// The dormant `__test` / test_token branch is REMOVED rather than migrated, applying the ruling
// already recorded in dir_ingest on 19 Jul 2026: a QA credential must never carry production
// authority. app_secrets has no test_token row (verified 3 Aug 2026), so the branch was inert and
// deleting it breaks nothing. It is deleted rather than left dormant so that re-adding a
// test_token row for some unrelated harness cannot silently re-grant access here. That argument
// applies verbatim to this function: yello_scrape bulk-writes yello_staging, the very same
// directory pipeline dir_ingest feeds.
async function auth(body: any): Promise<boolean> {
  return (await requireInternal(admin, body?.__secret, 'yello_scrape')).ok;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*' } });
  const body = await req.json().catch(() => ({}));
  if (!(await auth(body))) return J({ error: 'unauthorized' }, 401);
  const action = body.action;

  try {
    if (action === 'stats') {
      // 3 Aug 2026: this was `admin.rpc('exec_count_stage').catch(...)`. A PostgREST builder is
      // NOT a Promise and has no .catch, so the intended guard threw TypeError on every call and
      // the whole 'stats' action failed — the same crash class fixed in designer and secretary_act
      // today. `.then(onOk, onErr)` works because the builder is thenable.
      const { data } = await admin.rpc('exec_count_stage').then((r: any) => r, () => ({ data: null } as any));
      const { data: rows } = await admin.from('yello_staging').select('stage');
      const by: Record<string,number> = {}; (rows||[]).forEach((r:any)=>{ by[r.stage]=(by[r.stage]||0)+1; });
      const { count: withEmail } = await admin.from('yello_staging').select('company_id',{count:'exact',head:true}).not('email','is',null);
      return J({ ok:true, by_stage: by, with_email: withEmail||0, total: (rows||[]).length });
    }

    if (action === 'crawl_category') {
      const cat = String(body.category||'').trim();
      const city = String(body.city||'dubai').trim();
      const from = Math.max(1, parseInt(body.from_page)||1);
      const to = Math.min(from + 19, Math.max(from, parseInt(body.to_page)||from));
      if (!cat) return J({ error:'category required' },400);
      let added = 0, seen = 0; const pages: number[] = [];
      for (let p = from; p <= to; p++) {
        const url = p === 1 ? `${BASE}/category/${cat}/city:${city}` : `${BASE}/category/${cat}/${p}/city:${city}`;
        const html = await getHtml(url);
        if (!html) { pages.push(p); continue; }
        const items = parseListing(html); seen += items.length;
        for (const it of items) {
          const { error } = await admin.from('yello_staging').upsert({
            company_id: it.id, slug: it.slug, city, src_category: cat,
            profile_url: `${BASE}/company/${it.id}/${it.slug}`, stage: 'listed', updated_at: new Date().toISOString()
          }, { onConflict: 'company_id', ignoreDuplicates: true });
          if (!error) added++;
        }
        pages.push(p);
        await new Promise(r => setTimeout(r, 350));
      }
      return J({ ok:true, category: cat, city, pages: [from,to], links_seen: seen, upserted: added });
    }

    if (action === 'crawl_profiles') {
      const lim = Math.min(25, Math.max(1, parseInt(body.limit)||12));
      const { data: rows } = await admin.from('yello_staging').select('company_id,profile_url,src_category').eq('stage','listed').limit(lim);
      let done = 0, dead = 0;
      for (const r of (rows||[])) {
        const html = await getHtml(r.profile_url);
        if (!html) { await admin.from('yello_staging').update({ stage:'dead', note:'profile_fetch_failed', updated_at:new Date().toISOString() }).eq('company_id', r.company_id); dead++; continue; }
        const p = parseProfile(html);
        const sector = sectorFor(p.categories, r.src_category);
        await admin.from('yello_staging').update({
          name: p.name, website: p.website, phone: p.phone, mobile: p.mobile, whatsapp: p.whatsapp,
          categories: p.categories, manager: p.manager, established: p.established, sector,
          stage: 'profiled', updated_at: new Date().toISOString()
        }).eq('company_id', r.company_id);
        done++;
        await new Promise(res => setTimeout(res, 300));
      }
      return J({ ok:true, profiled: done, dead });
    }

    if (action === 'crawl_emails') {
      const lim = Math.min(20, Math.max(1, parseInt(body.limit)||10));
      const { data: rows } = await admin.from('yello_staging').select('company_id,website').eq('stage','profiled').not('website','is',null).is('email', null).limit(lim);
      let found = 0, none = 0;
      for (const r of (rows||[])) {
        let host = ''; try { host = new URL(r.website).host; } catch { /* */ }
        let email: string|null = null; let src = '';
        for (const path of ['', '/contact', '/contact-us', '/about']) {
          const html = await getHtml(r.website + path, 9000);
          if (html) { email = extractEmails(html, host); if (email) { src = 'website'+path; break; } }
        }
        await admin.from('yello_staging').update({ email, email_source: email?src:null, stage:'emailed', updated_at:new Date().toISOString() }).eq('company_id', r.company_id);
        if (email) found++; else none++;
      }
      return J({ ok:true, emails_found: found, no_email: none });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 200);
  }
});

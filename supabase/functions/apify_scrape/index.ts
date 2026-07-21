// apify_scrape - drives Apify Google-Maps scraping into public.leads. Secret-guarded (inbound_secret).
// Actions: account | start | status | collect. Token read from app_secrets.apify_token.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const API = 'https://api.apify.com/v2';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
function dom(u: string|null){ if(!u) return null; try{ return new URL(u).hostname.replace(/^www\./,'').toLowerCase(); }catch{ return null; } }
function firstArr(v: unknown){ return Array.isArray(v) ? v[0] : (typeof v==='string'? v : null); }
function mapItem(it: any){
  const website = it.website || null;
  const emails: string[] = Array.isArray(it.emails) ? it.emails : (it.email ? [it.email] : []);
  let email = (emails.find((e)=>typeof e==='string' && /@/.test(e)) || '').toLowerCase() || null;
  if (email && /^(no-?reply|donotreply|mailer-daemon)@/.test(email)) email = null;
  return {
    company_name: it.title || null,
    phone: it.phone || null,
    phone_e164: it.phoneUnformatted || null,
    website, domain: dom(website),
    street: it.street || it.address || null,
    city: it.city || null,
    rating_maps: (typeof it.totalScore==='number'? it.totalScore : null),
    reviews_maps: (typeof it.reviewsCount==='number'? it.reviewsCount : null),
    categories: it.categoryName || (Array.isArray(it.categories)? it.categories.join(', ') : null),
    maps_url: it.url || null,
    place_id: it.placeId || null,
    email, email_domain: email ? email.split('@')[1] : null,
    instagram: firstArr(it.instagrams) || it.instagram || null,
    facebook: firstArr(it.facebooks) || it.facebook || null,
    linkedin: firstArr(it.linkedIns) || it.linkedin || null,
  };
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    if (body.__secret !== (await sec('inbound_secret'))) return J({ error: 'forbidden' }, 403);
    const tok = await sec('apify_token'); if (!tok) return J({ error: 'no_apify_token' }, 200);
    const action = String(body.action||'');

    if (action === 'account') {
      const r = await fetch(`${API}/users/me/limits?token=${tok}`);
      const me = await fetch(`${API}/users/me?token=${tok}`).then(x=>x.json()).catch(()=>({}));
      const lim = await r.json().catch(()=>({}));
      return J({ ok: r.ok, username: me?.data?.username||null, plan: me?.data?.plan?.id||null, limits: lim?.data||lim });
    }

    if (action === 'start') {
      const actor = String(body.actor||'compass/crawler-google-places').replace('/','~');
      const r = await fetch(`${API}/acts/${actor}/runs?token=${tok}`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body.input||{}) });
      const jd = await r.json().catch(()=>({}));
      if (!r.ok) return J({ ok:false, error:'start_failed', status:r.status, detail: jd?.error||jd }, 200);
      const run = jd.data; 
      const { data: ins } = await admin.from('scrape_runs').insert({ run_id: run.id, dataset_id: run.defaultDatasetId, actor: body.actor||'compass/crawler-google-places', sector: body.sector||null, emirate: body.emirate||null, label: body.label||null, requested: body.requested||null, status: run.status||'RUNNING' }).select('id').maybeSingle();
      return J({ ok:true, scrape_run: ins?.id, run_id: run.id, dataset_id: run.defaultDatasetId, status: run.status });
    }

    if (action === 'status') {
      if (body.run_id) { const r = await fetch(`${API}/actor-runs/${body.run_id}?token=${tok}`).then(x=>x.json()).catch(()=>({})); return J({ ok:true, status:r?.data?.status, stats:r?.data?.stats, usageUsd:r?.data?.usageTotalUsd }); }
      const { data } = await admin.from('scrape_runs').select('id,run_id,sector,emirate,status,fetched,inserted,requested').order('id',{ascending:false}).limit(60);
      return J({ ok:true, runs:data });
    }

    if (action === 'collect') {
      const { data: sr } = await admin.from('scrape_runs').select('*').eq('run_id', body.run_id).maybeSingle();
      if (!sr) return J({ ok:false, error:'run_not_found' }, 200);
      const rs = await fetch(`${API}/actor-runs/${body.run_id}?token=${tok}`).then(x=>x.json()).catch(()=>({}));
      const st = rs?.data?.status; const dsId = sr.dataset_id || rs?.data?.defaultDatasetId;
      if (st && st!=='SUCCEEDED' && st!=='READY') { await admin.from('scrape_runs').update({status:st}).eq('id',sr.id); return J({ ok:true, status:st, note:'not finished yet' }); }
      const offset = sr.fetched || 0; const limit = Math.min(body.limit||1000, 1000);
      const items = await fetch(`${API}/datasets/${dsId}/items?token=${tok}&clean=true&format=json&offset=${offset}&limit=${limit}`).then(x=>x.json()).catch(()=>[]);
      const page = Array.isArray(items)? items : [];
      const rows = page.map(mapItem).filter(r=>r.place_id && r.email); // email-focused
      // de-dupe within batch
      const seen = new Set<string>(); const uniq: any[] = [];
      for (const r of rows){ const k=r.place_id!; if(seen.has(k)) continue; seen.add(k); uniq.push(r); }
      let inserted = 0;
      if (uniq.length){
        const pids = uniq.map(r=>r.place_id); const ems = uniq.map(r=>r.email);
        const { data: exP } = await admin.from('leads').select('place_id').in('place_id', pids);
        const { data: exE } = await admin.from('leads').select('email').in('email', ems);
        const haveP = new Set((exP||[]).map((x:any)=>x.place_id)); const haveE = new Set((exE||[]).map((x:any)=>(x.email||'').toLowerCase()));
        const toIns = uniq.filter(r=>!haveP.has(r.place_id) && !haveE.has(r.email)).map(r=>({ ...r, sector: sr.sector, emirate: sr.emirate, source: 'apify_'+(new Date().toISOString().slice(0,7)), enrich_source: 'apify_maps_contacts', scraped_at: new Date().toISOString().slice(0,10) }));
        if (toIns.length){ const { data: di, error } = await admin.from('leads').upsert(toIns, { onConflict:'place_id', ignoreDuplicates:true }).select('id'); if(error) return J({ ok:false, error:'insert_failed', detail:error.message }, 200); inserted = di?.length||0; }
      }
      const newFetched = offset + page.length; const hasMore = page.length === limit;
      await admin.from('scrape_runs').update({ fetched:newFetched, inserted:(sr.inserted||0)+inserted, status: hasMore?'SUCCEEDED':'COLLECTED', collected_at: hasMore?null:new Date().toISOString() }).eq('id', sr.id);
      return J({ ok:true, status:'SUCCEEDED', page: page.length, inserted, total_fetched:newFetched, total_inserted:(sr.inserted||0)+inserted, hasMore });
    }

    return J({ error:'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

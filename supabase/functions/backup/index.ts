import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
// Core tables to snapshot. leads dumped with a column subset (no heavy embedding vectors).
const FULL=['customers','inquiries','quotes','transactions','supplier_dues','reviews','questions','inquiry_matches','agent_knowledge','agent_memory','agent_chats','pricing_config','category_specs','category_agents','content_drafts','expenses','reveal_invoices'];
const LEAD_COLS='id,company_name,email,phone,whatsapp,website,categories,sector,emirate,rating,reviews,app_rating,app_reviews,verified,verification_status,claimed,claimed_by,approval_status,trade_license_no,trn,license_expiry,invite_status,created_at';

async function dumpTable(t:string, cols='*'){
  const rows:any[]=[]; let from=0; const page=1000;
  for(;;){ const {data,error}=await admin.from(t).select(cols).range(from,from+page-1); if(error) throw new Error(t+': '+error.message); if(!data||!data.length) break; rows.push(...data); if(data.length<page) break; from+=page; if(from>200000) break; }
  return rows;
}

// recursive storage listing (capped) so the backup records every stored file (path,size,updated)
async function listBucket(bucket:string, prefix='', acc:any[]=[], depth=0):Promise<any[]>{
  if(acc.length>20000 || depth>6) return acc;
  let offset=0; const lim=100;
  for(;;){
    const { data, error } = await admin.storage.from(bucket).list(prefix, { limit:lim, offset, sortBy:{ column:'name', order:'asc' } });
    if(error || !data || !data.length) break;
    for(const it of data){
      const full = prefix ? prefix+'/'+it.name : it.name;
      if(it.id===null && !it.metadata){ await listBucket(bucket, full, acc, depth+1); }
      else { acc.push({ path: full, size: it.metadata?.size ?? null, updated_at: it.updated_at ?? null }); }
      if(acc.length>20000) return acc;
    }
    if(data.length<lim) break; offset+=lim;
  }
  return acc;
}

Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  const __exp = await sec('inbound_secret');
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, b?.__secret, 'backup');
  if(!__auth.ok) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
  const started=new Date().toISOString();
  try{ try{ await admin.storage.createBucket('backups',{public:false}); }catch(_){}
    const stamp=new Date().toISOString().slice(0,10);
    const summary:Record<string,number>={}; let bytes=0;
    const tables=[...FULL];
    for(const t of tables){ try{ const rows=await dumpTable(t); const json=JSON.stringify(rows); summary[t]=rows.length; bytes+=json.length; await admin.storage.from('backups').upload(`${stamp}/${t}.json`, new Blob([json],{type:'application/json'}), {contentType:'application/json',upsert:true}); }catch(e){ summary[t]=-1; } }
    try{ const leads=await dumpTable('leads', LEAD_COLS); summary['leads']=leads.length; const j=JSON.stringify(leads); bytes+=j.length; await admin.storage.from('backups').upload(`${stamp}/leads.json`, new Blob([j],{type:'application/json'}), {contentType:'application/json',upsert:true}); }catch(e){ summary['leads']=-1; }
    // Storage file inventory (every bucket, recursive, capped) so we know exactly what files exist
    const storage:Record<string,any>={};
    try{ const { data: buckets } = await admin.storage.listBuckets();
      for(const bk of (buckets||[])){ if(bk.name==='backups') continue; try{ const files=await listBucket(bk.name); const tot=files.reduce((s,f)=>s+(Number(f.size)||0),0); storage[bk.name]={ files: files.length, total_bytes: tot }; await admin.storage.from('backups').upload(`${stamp}/_storage_${bk.name}.json`, new Blob([JSON.stringify(files)],{type:'application/json'}), {contentType:'application/json',upsert:true}); }catch(e){ storage[bk.name]={ error:String(e).slice(0,100) }; } }
    }catch(e){ storage['_error']=String(e).slice(0,120); }
    const manifest={ created_at:new Date().toISOString(), tables:summary, storage, total_bytes:bytes };
    await admin.storage.from('backups').upload(`${stamp}/_manifest.json`, new Blob([JSON.stringify(manifest,null,2)],{type:'application/json'}), {contentType:'application/json',upsert:true});
    await admin.from('agent_runs').insert({agent:'backup',started_at:started,finished_at:new Date().toISOString(),status:'ok',counts:{tables:Object.keys(summary).length,buckets:Object.keys(storage).length,total_bytes:bytes}});
    return new Response(JSON.stringify({ok:true,stamp,manifest}),{headers:{'Content-Type':'application/json'}});
  }catch(e){ await admin.from('agent_runs').insert({agent:'backup',started_at:started,finished_at:new Date().toISOString(),status:'error',note:String(e).slice(0,200)}); return new Response(JSON.stringify({error:String(e)}),{status:200,headers:{'Content-Type':'application/json'}}); }
});
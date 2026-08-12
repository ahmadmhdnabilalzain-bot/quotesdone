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
// THE KNOWLEDGE ESTATE WAS NOT BACKED UP. Measured on production 6 Aug 2026, the 5 Aug snapshot
// held leads.json 11.4 MB and agent_knowledge.json 3.0 MB and NOTHING for kb_chunks (4,937 rows,
// the deep retrieval corpus every agent reads), dept_library (1,456 rows of UAE domain reference)
// or ops_knowledge (3,959 founder-supplied operational records). Those three are, today, most of
// what this company actually owns — production still has 0 customers, 0 inquiries and 0 quotes, so
// the tables that were backed up are the empty ones. Adding them here is what makes their entry in
// dr_drill's TABLES mean anything.
const FULL=['customers','inquiries','quotes','transactions','supplier_dues','reviews','questions','inquiry_matches','agent_knowledge','agent_memory','agent_chats','pricing_config','category_specs','category_agents','content_drafts','expenses','reveal_invoices','kb_chunks','dept_library','ops_knowledge'];
const LEAD_COLS='id,company_name,email,phone,whatsapp,website,categories,sector,emirate,rating,reviews,app_rating,app_reviews,verified,verification_status,claimed,claimed_by,approval_status,trade_license_no,trn,license_expiry,invite_status,created_at';

// ONE PAGE IN MEMORY, NOT ONE TABLE (12 Aug 2026). dumpTable paged through with .range() and then
// accumulated every row into a single array before JSON.stringify materialised the whole table as
// one string. Peak memory was one full table plus its JSON, so the function died as the estate grew:
// measured on production, invoking it returned HTTP 546 WORKER_RESOURCE_LIMIT after 36.6s, and the
// last successful backup was 10 Aug. kb_chunks is 105,920 rows. Same failure class as kb_embed's
// 546, and the same answer: add invocations, never batch size. Each page is uploaded as it is read,
// so peak memory is 1,000 rows regardless of how large the table becomes.
// RESUMABLE AT PAGE GRANULARITY. A budget checked BETWEEN tables does not help when one table is
// bigger than the whole budget: measured on staging, kb_chunks alone ran the worker past 100s and
// died. So a slice can stop mid-table and the next invocation resumes at the exact page.
async function dumpTablePaged(t:string, stamp:string, cols='*', startFrom=0, startPage=0, deadline=Infinity){
  // Clear this table's prefix first. stamp is a DATE and uploads use upsert, so a re-run on the same
  // day that produces fewer pages than the last one would otherwise leave stale pages behind, and
  // dr_drill would concatenate them into a restore that never existed.
  if(startFrom===0){
    try{
      const { data:old } = await admin.storage.from('backups').list(`${stamp}/${t}`, { limit:1000 });
      const paths=(old||[]).map((e:any)=>`${stamp}/${t}/${e.name}`);
      if(paths.length) await admin.storage.from('backups').remove(paths);
    }catch(_){ /* a missing prefix is the normal first-run case */ }
  }

  let from=startFrom; const page=1000; let pages=startPage; let rows=0; let bytes=0;
  for(;;){
    if(Date.now() > deadline) return { rows, pages, bytes, done:false, nextFrom:from };
    const {data,error}=await admin.from(t).select(cols).range(from,from+page-1);
    if(error) throw new Error(t+': '+error.message);
    if(!data||!data.length) break;
    const json=JSON.stringify(data);
    const { error:ue } = await admin.storage.from('backups').upload(
      `${stamp}/${t}/page_${String(pages).padStart(4,'0')}.json`,
      new Blob([json],{type:'application/json'}), {contentType:'application/json',upsert:true});
    if(ue) throw new Error(t+' page '+pages+': '+ue.message);
    pages++; rows+=data.length; bytes+=json.length;
    if(data.length<page) break;
    from+=page; if(from>200000) break;
  }
  // AN EMPTY TABLE MUST STILL WRITE A PAGE. With no page at all, dr_drill's prefix listing returns
  // nothing, which is indistinguishable from "the backup is missing" - and dr_drill's own comment
  // records that an empty backup silently passing is a defect that has already bitten this company.
  // One page containing [] is the honest representation of an empty table.
  if(pages===0){
    const { error:ue } = await admin.storage.from('backups').upload(
      `${stamp}/${t}/page_0000.json`, new Blob(['[]'],{type:'application/json'}),
      {contentType:'application/json',upsert:true});
    if(ue) throw new Error(t+' empty page: '+ue.message);
    pages=1; bytes+=2;
  }
  return { rows, pages, bytes, done:true, nextFrom:from };
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
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, b?.__secret, 'backup');
  if(!__auth.ok) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
  // AND ONE INVOCATION IS STILL NOT ENOUGH (12 Aug 2026). Paging the row dump fixed the memory
  // ceiling but the run still died: measured on staging, HTTP 546 after 102 SECONDS. Twenty tables,
  // ~106 page uploads for kb_chunks alone, and a recursive listing of every storage bucket exceed
  // the worker's compute budget however little memory each step holds. So the work is spread across
  // invocations, which is what "add invocations, never batch size" actually requires here.
  //
  // The chain is stateless: each call processes tables until its time budget is spent, then posts
  // ITSELF the remaining table list and the summary so far. The final call - the one with nothing
  // left - writes the storage inventory, the manifest and the agent_runs row. A crash mid-chain
  // therefore leaves no agent_runs row, which is exactly what fn_backup_watch already alerts on.
  const started = typeof b?.__started === 'string' ? b.__started : new Date().toISOString();
  const t0 = Date.now();
  const SLICE_MS = 30000;          // hand off well inside the worker's budget
  const MAX_HOPS = 40;             // a runaway chain must stop and be visible, not loop forever
  const hop = Number(b?.__hop || 0);
  try{ try{ await admin.storage.createBucket('backups',{public:false}); }catch(_){}
    const stamp = typeof b?.__stamp === 'string' ? b.__stamp : new Date().toISOString().slice(0,10);
    const summary:Record<string,number> = (b?.__summary && typeof b.__summary==='object') ? b.__summary : {};
    const pages:Record<string,number> = (b?.__pages && typeof b.__pages==='object') ? b.__pages : {};
    let bytes = Number(b?.__bytes || 0);
    // A queue entry is a table plus where to resume inside it. `from`/`page` are 0 for a fresh table.
    type Slot = { t:string; from:number; page:number; rows:number };
    const queue:Slot[] = Array.isArray(b?.__queue)
      ? b.__queue.map((q:any)=> typeof q === 'string'
          ? { t:q, from:0, page:0, rows:0 }
          : { t:String(q.t), from:Number(q.from||0), page:Number(q.page||0), rows:Number(q.rows||0) })
      : [...FULL, 'leads'].map((t)=>({ t, from:0, page:0, rows:0 }));
    if(hop >= MAX_HOPS){
      await admin.from('agent_runs').insert({agent:'backup',started_at:started,finished_at:new Date().toISOString(),status:'error',
        note:'backup chain exceeded '+MAX_HOPS+' hops with '+queue.length+' table(s) still unprocessed; it was stopped rather than left looping.'});
      return new Response(JSON.stringify({error:'max_hops',remaining:queue.length}),{status:200,headers:{'Content-Type':'application/json'}});
    }

    const deadline = t0 + SLICE_MS;
    while(queue.length && Date.now() < deadline){
      const slot = queue.shift() as Slot;
      try{
        const r = await dumpTablePaged(slot.t, stamp, slot.t==='leads' ? LEAD_COLS : '*',
                                       slot.from, slot.page, deadline);
        bytes += r.bytes;
        if(r.done){ summary[slot.t] = slot.rows + r.rows; pages[slot.t] = r.pages; }
        else {
          // Out of budget mid-table: put it back with its exact resume point. Nothing is recorded in
          // summary yet, so an interrupted table can never look complete.
          queue.unshift({ t:slot.t, from:r.nextFrom, page:r.pages, rows:slot.rows + r.rows });
          break;
        }
      }catch(_e){ summary[slot.t]=-1; pages[slot.t]=-1; }
    }

    if(queue.length){
      // Hand the rest to a fresh worker. Fire-and-forget: this invocation has no budget left to wait.
      const s = await sec('cred_cron_backup');
      fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/backup', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ __secret: s, __stamp: stamp, __queue: queue, __summary: summary,
                               __pages: pages, __bytes: bytes, __started: started, __hop: hop+1 }),
      }).catch(()=>{});
      return new Response(JSON.stringify({ok:true,stamp,hop,done:Object.keys(summary).length,remaining:queue.length}),{headers:{'Content-Type':'application/json'}});
    }
    // Every table is done. pages[] is what makes a PARTIAL restore detectable: dr_drill counts the
    // page objects it finds and refuses the table if the count disagrees with what the backup says
    // it wrote. Without it a missing page reads as a smaller table - a backup that looks fine.
    // Storage file inventory (every bucket, recursive, capped) so we know exactly what files exist
    const storage:Record<string,any>={};
    try{ const { data: buckets } = await admin.storage.listBuckets();
      for(const bk of (buckets||[])){ if(bk.name==='backups') continue; try{ const files=await listBucket(bk.name); const tot=files.reduce((s,f)=>s+(Number(f.size)||0),0); storage[bk.name]={ files: files.length, total_bytes: tot }; await admin.storage.from('backups').upload(`${stamp}/_storage_${bk.name}.json`, new Blob([JSON.stringify(files)],{type:'application/json'}), {contentType:'application/json',upsert:true}); }catch(e){ storage[bk.name]={ error:String(e).slice(0,100) }; } }
    }catch(e){ storage['_error']=String(e).slice(0,120); }
    // layout: 'paged' tells dr_drill which shape this day is in, so it can still verify the
    // single-file backups written before 12 Aug 2026 without guessing.
    const manifest={ created_at:new Date().toISOString(), layout:'paged', tables:summary, pages, storage, total_bytes:bytes };
    await admin.storage.from('backups').upload(`${stamp}/_manifest.json`, new Blob([JSON.stringify(manifest,null,2)],{type:'application/json'}), {contentType:'application/json',upsert:true});
    await admin.from('agent_runs').insert({agent:'backup',started_at:started,finished_at:new Date().toISOString(),status:'ok',counts:{tables:Object.keys(summary).length,buckets:Object.keys(storage).length,total_bytes:bytes}});
    return new Response(JSON.stringify({ok:true,stamp,manifest}),{headers:{'Content-Type':'application/json'}});
  }catch(e){ await admin.from('agent_runs').insert({agent:'backup',started_at:started,finished_at:new Date().toISOString(),status:'error',note:String(e).slice(0,200)}); return new Response(JSON.stringify({error:String(e)}),{status:200,headers:{'Content-Type':'application/json'}}); }
});
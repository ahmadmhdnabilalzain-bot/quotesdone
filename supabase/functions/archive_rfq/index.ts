// archive_rfq v2 — archives a COMPLETED RFQ as an atomic case: structured data, the actual
// uploaded files (copied, not just referenced), AI conversations, RFQ + quote version history,
// supplier responses, quotations, comparison, decision history, audit logs, and an AI summary.
// Stored to backups/archives/RFQ-<id>/; searchable metadata in public.rfq_archives. Secret-gated.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const URL = Deno.env.get('SUPABASE_URL')!;
const KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL, KEY);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'archive_rfq', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Content-Type':'application/json' };
const j = (o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:cors});
async function sha256(t:string){ const b=new TextEncoder().encode(t); const h=await crypto.subtle.digest('SHA-256',b); return Array.from(new Uint8Array(h)).map(x=>x.toString(16).padStart(2,'0')).join(''); }

async function aiSummary(apiKey:string, pkg:any):Promise<any>{
  const models=['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'];
  const sys='You write concise project post-mortems for a UAE procurement marketplace. Return STRICT JSON only: '+
    '{summary:string (6-10 lines: customer, category, budget, winning supplier, savings if any, timeline, disputes), '+
    'lessons:[string] (2-5 concrete, reusable institutional lessons for matching/qualification/recommendation)}. Base only on data. Never invent.';
  const brief=JSON.stringify({rfq:pkg['01_RFQ'],customer:pkg['02_Customer'],suppliers:pkg['03_Suppliers'],quotations:pkg['04_Quotations'],comparison:pkg['05_Comparison'],invoices:pkg['09_Invoices']}).slice(0,12000);
  for(const model of models){ try{
    const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':`Bearer ${apiKey}`,'Content-Type':'application/json'},body:JSON.stringify({model,temperature:0,max_tokens:900,messages:[{role:'system',content:sys},{role:'user',content:brief}]})});
    if(!r.ok) continue; const d=await r.json(); let t=d?.choices?.[0]?.message?.content||''; t=t.replace(/^```(json)?/i,'').replace(/```$/,'').trim(); const m=t.match(/\{[\s\S]*\}/); if(m) return JSON.parse(m[0]);
  }catch(_e){} }
  return { summary:'(AI summary unavailable)', lessons:[] };
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  const sb=createClient(URL,KEY);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const { data:secrets, error:secretsErr } = await sb.from('app_secrets').select('key,value').in('key',['inbound_secret','openrouter_api_key']);
  const secret=(secrets||[]).find((s:any)=>s.key==='inbound_secret')?.value;
  const apiKey=(secrets||[]).find((s:any)=>s.key==='openrouter_api_key')?.value;
  if(!secret || body.__secret!==secret){
    await logRun('error', { unauthorized:1, secret_configured: secret?1:0 }, secret ? 'RFQ archiver rejected a caller with a wrong __secret; no RFQ was archived on this invocation. If this was the scheduled cron its secret is stale and completed RFQs are piling up unarchived, so their drawing files may be purged by retention before the case is preserved.' : ('RFQ archiver could not read inbound_secret from app_secrets, so every call including the scheduled cron is rejected with 401 and no completed RFQ is ever archived. ' + String(secretsErr?.message || 'no inbound_secret row')));
    return j({error:'unauthorized'},401);
  }

  let inq:any=null;
  let pickErrMsg='';
  if(body.inquiry_id){ const { data, error:oneErr } = await sb.from('inquiries').select('*').eq('id',body.inquiry_id).maybeSingle(); inq=data; if(oneErr) pickErrMsg='Could not load the requested inquiry '+String(body.inquiry_id)+' so it was not archived: '+String(oneErr.message||oneErr)+'. '; }
  else {
    const { data, error:scanErr } = await sb.from('inquiries').select('*').in('status',['completed','accepted','closed'])
      .lt('completed_at', new Date(Date.now()-90*864e5).toISOString()).order('completed_at').limit(20);
    if(scanErr) pickErrMsg='Could not scan the inquiries table for RFQs eligible for archiving, so nothing was archived this run and completed RFQs remain unpreserved: '+String(scanErr.message||scanErr)+'. ';
    for(const cand of (data||[])){ const { count } = await sb.from('rfq_archives').select('*',{count:'exact',head:true}).eq('rfq_id',String(cand.id)); if(!count){ inq=cand; break; } }
  }
  if(!inq){
    if(pickErrMsg) await logRun('error', { archived:0 }, pickErrMsg);
    else await logRun('ok', { archived:0, eligible:0 }, '');
    return j({ok:true,note:'no RFQ eligible for archiving'});
  }
  const rid=String(inq.id);
  const { count:already } = await sb.from('rfq_archives').select('*',{count:'exact',head:true}).eq('rfq_id',rid);
  if(already && !body.force){
    await logRun('ok', { archived:0, rfq_id:rid, already_archived:1 }, '');
    return j({ok:true,note:'already archived',rfq_id:rid});
  }
  const folder=`archives/RFQ-${rid}`;

  try{
    const warn:string[]=[];
    const { data:customer, error:custErr } = await sb.from('customers').select('*').eq('id',inq.customer_id).maybeSingle();
    if(custErr) warn.push('Customer record could not be read, so the archive for RFQ '+rid+' has no customer section: '+String(custErr.message||custErr)+'. ');
    const { data:matches, error:matchErr } = await sb.from('inquiry_matches').select('*').eq('inquiry_id',rid);
    if(matchErr) warn.push('Supplier matches could not be read, so the archive for RFQ '+rid+' records no matched suppliers: '+String(matchErr.message||matchErr)+'. ');
    const supIds=[...new Set((matches||[]).map((m:any)=>m.supplier_id).filter(Boolean))];
    const { data:suppliers } = await sb.from('leads').select('id,company_name,emirate,categories,rating,verified,approval_status').in('id',supIds.length?supIds:['__none__']);
    const { data:quotes, error:quotesErr } = await sb.from('quotes').select('*').eq('inquiry_id',rid);
    if(quotesErr) warn.push('Quotes could not be read, so the archive for RFQ '+rid+' contains no quotations, no comparison and no quote files: '+String(quotesErr.message||quotesErr)+'. ');
    const { data:messages, error:msgErr } = await sb.from('messages').select('id,sender,body,created_at,flagged,blocked').eq('inquiry_id',rid).order('created_at');
    if(msgErr) warn.push('Communications could not be read, so the archive for RFQ '+rid+' has no message trail to support a future dispute: '+String(msgErr.message||msgErr)+'. ');
    const { data:threads } = await sb.from('chat_threads').select('*').eq('inquiry_id',rid);
    const { data:txns } = await sb.from('transactions').select('*').eq('inquiry_id',rid);
    const txnIds=(txns||[]).map((t:any)=>t.id);
    const { data:invoices } = await sb.from('reveal_invoices').select('*').in('transaction_id',txnIds.length?txnIds:[-1]);
    const { data:audit } = await sb.from('notifications').select('type,subject,created_at').eq('inquiry_id',rid).order('created_at').limit(80);
    // AI conversations: agent chats attributable to this customer
    let aichats:any[]=[];
    const idents=[customer?.email, customer?.id, inq.customer_id].filter(Boolean).map(String);
    if(idents.length){ const { data:ac } = await sb.from('agent_chats').select('agent_key,role,content,created_at,created_by').in('created_by',idents).order('created_at').limit(200); aichats=ac||[]; }
    // version history
    const verIds=['rfq:'+rid, ...(quotes||[]).map((q:any)=>'quote:'+q.id)];
    const { data:versions, error:verErr } = await sb.from('doc_versions').select('entity_type,entity_id,version,changed_fields,checksum,created_at')
      .or(`and(entity_type.eq.rfq,entity_id.eq.${rid})`+ (quotes&&quotes.length? ','+quotes.map((q:any)=>`and(entity_type.eq.quote,entity_id.eq.${q.id})`).join(',') : '')).order('created_at');
    if(verErr) warn.push('Document version history could not be read, so the archive for RFQ '+rid+' cannot evidence what changed and when: '+String(verErr.message||verErr)+'. ');

    // ---- copy the actual uploaded files into the case ----
    const filesManifest:any[]=[];
    async function copyFile(bucket:string, path:string, kind:string){
      if(!path) return; try{
        const { data:blob, error } = await sb.storage.from(bucket).download(path);
        if(error||!blob) { filesManifest.push({kind,bucket,path,copied:false,error:error?.message||'missing'}); return; }
        const name=path.split('/').pop()||'file';
        const dest=`${folder}/files/${kind}/${name}`;
        const { error:upErr } = await sb.storage.from('backups').upload(dest, blob, { upsert:true });
        if(upErr){ filesManifest.push({kind,bucket,path,copied:false,error:String(upErr.message||upErr).slice(0,120)}); return; }
        filesManifest.push({kind,source_bucket:bucket,source_path:path,archived_path:dest,copied:true,bytes:blob.size});
      }catch(e){ filesManifest.push({kind,bucket,path,copied:false,error:String(e).slice(0,120)}); }
    }
    await copyFile('drawing-files', inq.drawing_file_path, 'drawing');
    for(const p of (inq.drawing_redacted_paths||[])) await copyFile('drawing-files', p, 'drawing_redacted');
    for(const q of (quotes||[])) await copyFile('quote-files', q.original_file_path, 'quotation');
    const filesFailed=filesManifest.filter((f:any)=>!f.copied);
    if(filesFailed.length) warn.push(filesFailed.length+' of '+filesManifest.length+' uploaded files could not be copied into the archive for RFQ '+rid+', so those drawings/quotations are NOT preserved and will be lost once retention purges the originals. First error: '+String(filesFailed[0]?.error||'')+'. ');

    const winner=(quotes||[]).find((q:any)=>['won','accepted'].includes(String(q.status||'')));
    const pkg:any = {
      '00_Manifest': { rfq_id:rid, generated_at:new Date().toISOString(), files:filesManifest, sections:11, versions:(versions||[]).length },
      '01_RFQ': { id:rid, category:inq.category, emirate:inq.emirate, summary:inq.summary, spec:inq.spec, budget:inq.budget, scope_type:inq.scope_type, trades:inq.trades, boq:inq.boq, created_at:inq.created_at, completed_at:inq.completed_at, outcome:inq.outcome },
      '02_Customer': customer ? { id:customer.id, name:customer.full_name, email:customer.email, phone:customer.phone } : null,
      '03_Suppliers': suppliers||[],
      '04_Quotations': quotes||[],
      '05_Comparison': { committed:(quotes||[]).map((q:any)=>({supplier_id:q.supplier_id, amount:q.quote_amount, committed_items:q.committed_items, status:q.status})), winner: winner?{supplier_id:winner.supplier_id, amount:winner.quote_amount}:null },
      '06_AI_Analysis': { quality:(quotes||[]).map((q:any)=>({id:q.id, quality:q.quality, review_status:q.review_status})) },
      '07_AI_Conversations': { agent_chats:aichats, chat_threads:threads||[] },
      '08_Communications': messages||[],
      '09_Invoices_and_Decisions': { transactions:txns||[], invoices:invoices||[], hired_supplier_id:inq.hired_supplier_id, lost_reason:inq.lost_reason },
      '10_Audit': audit||[],
      '11_Versions': versions||[],
      '12_Final_Report': null };

    if(!apiKey) warn.push('No openrouter_api_key is configured, so the AI post-mortem summary and lessons-learned for RFQ '+rid+' were not generated and the archive was stored with a placeholder summary. ');
    const ai=await aiSummary(apiKey, pkg);
    if(apiKey && ai && ai.summary==='(AI summary unavailable)') warn.push('Every OpenRouter model failed, so the AI post-mortem summary and lessons-learned for RFQ '+rid+' were not generated and the archive was stored with a placeholder summary. ');
    pkg['12_Final_Report']=ai;

    const caseJson=JSON.stringify(pkg,null,2);
    const checksum=await sha256(caseJson);
    const finalMd=`# Project Summary — RFQ-${rid}\n\n${ai.summary||''}\n\n## Lessons Learned\n`+((ai.lessons||[]).map((l:string)=>`- ${l}`).join('\n'));
    const { error:caseUpErr } = await sb.storage.from('backups').upload(`${folder}/case.json`, new Blob([caseJson],{type:'application/json'}), { upsert:true });
    if(caseUpErr) warn.push('Uploading case.json for RFQ '+rid+' failed, so the archive folder is empty or incomplete even though the run reported success and rfq_archives will point at a non-existent case file: '+String(caseUpErr.message||caseUpErr)+'. ');
    const { error:mdUpErr } = await sb.storage.from('backups').upload(`${folder}/12_Final_Report/final_report.md`, new Blob([finalMd],{type:'text/markdown'}), { upsert:true });
    if(mdUpErr) warn.push('Uploading the final report markdown for RFQ '+rid+' failed, so the human-readable post-mortem is missing from the archive: '+String(mdUpErr.message||mdUpErr)+'. ');

    const { error:archErr } = await sb.from('rfq_archives').upsert({
      rfq_id:rid, customer_id:inq.customer_id?String(inq.customer_id):null, supplier_ids:supIds,
      category:inq.category, status:inq.status, dates:{ created_at:inq.created_at, completed_at:inq.completed_at },
      bucket:'backups', archive_path:folder, checksum, archive_version:2, ai_summary:ai, size_bytes:caseJson.length, restored_at:null
    }, { onConflict:'rfq_id' });
    if(archErr) warn.push('Writing the rfq_archives index row for RFQ '+rid+' failed, so the archive exists in storage but is invisible and unsearchable, and this RFQ will be re-archived on every future run: '+String(archErr.message||archErr)+'. ');

    const counts={ rfq_id:rid, archived:1, files_total:filesManifest.length, files_copied:filesManifest.filter((f:any)=>f.copied).length, files_failed:filesFailed.length, quotes:(quotes||[]).length, versions:(versions||[]).length, ai_conversations:aichats.length, lessons:(ai.lessons||[]).length };
    if(warn.length) await logRun('error', counts, warn.join(''));
    else await logRun('ok', counts, '');

    return j({ ok:true, rfq_id:rid, archive_path:folder, checksum, files_copied:filesManifest.filter(f=>f.copied).length, files_total:filesManifest.length,
      ai_conversations:aichats.length, versions:(versions||[]).length, quotes:(quotes||[]).length, lessons:(ai.lessons||[]).length });
  }catch(e){ await logRun('error', { rfq_id:rid, archived:0 }, 'RFQ archiving crashed part-way for RFQ '+rid+', so this completed RFQ was not preserved and its drawings, quotes and message trail may be lost once retention purges them: '+String(e).slice(0,300)); return j({error:String(e)},500); }
});

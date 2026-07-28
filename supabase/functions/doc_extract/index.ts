// doc_extract — universal Document Intelligence extractor.
// Pulls {text, specifications, brands[], models[], dates[], quantities[], certifications[]}
// from a registered document, and indexes non-sensitive docs into kb_chunks.
// Secret-gated (inbound_secret). Service-role only.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Content-Type':'application/json' };
const j = (o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:cors});

// index these kinds into the shared KB (non customer-identifying capability text).
const INDEX_KINDS = new Set(['catalog','profile','drawing']);
// never index (pricing tied to identity, or PII documents)
// quote, licence, egr are intentionally excluded.

async function llmJSON(apiKey:string, content:unknown):Promise<any>{
  const models=['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8'];
  const sys='You are a document-extraction engine for a UAE construction/services procurement platform. '+
    'Return STRICT JSON only (no markdown) with exactly these keys: '+
    'text (string: a faithful transcription or concise summary of the readable content), '+
    'specifications (array of short strings), brands (array of strings), models (array of strings), '+
    'dates (array of strings as seen), quantities (array of strings like "12 nos", "45 sqm"), '+
    'certifications (array of strings e.g. SIRA, ISO 9001, IP65, CE). '+
    'Use [] for anything absent. Never invent values.';
  for(const model of models){
    try{
      const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',
        headers:{'Authorization':`Bearer ${apiKey}`,'Content-Type':'application/json'},
        body:JSON.stringify({model,temperature:0,max_tokens:2000,
          messages:[{role:'system',content:sys},{role:'user',content}]})});
      if(!r.ok){continue;}
      const d=await r.json();
      let t=d?.choices?.[0]?.message?.content||'';
      t=t.replace(/^```(json)?/i,'').replace(/```$/,'').trim();
      const m=t.match(/\{[\s\S]*\}/); if(m) return JSON.parse(m[0]);
    }catch(_e){/*try next*/}
  }
  return null;
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  const sb=createClient(SUPABASE_URL,SERVICE_KEY);
  const T0 = Date.now();
  async function logRun(status: string, counts: Record<string, unknown>, note: string) {
    try {
      await sb.from('agent_runs').insert({ agent: 'doc_extract', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break the function */ }
  }
  async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
    try {
      const since = new Date(Date.now() - minutes * 60000).toISOString();
      const { data } = await sb.from('agent_runs').select('id').eq('agent', 'doc_extract')
        .gte('started_at', since).eq('counts->>signal', signal).limit(1);
      if (data && data.length) return;
    } catch (_e) { /* if the check fails, fall through and log */ }
    await logRun(status, { ...counts, signal }, note);
  }
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  // secrets from app_secrets
  const { data:secrets } = await sb.from('app_secrets').select('key,value').in('key',['inbound_secret','openrouter_api_key','cloudconvert_api_key']);
  const secret=(secrets||[]).find((s:any)=>s.key==='inbound_secret')?.value;
  const apiKey=(secrets||[]).find((s:any)=>s.key==='openrouter_api_key')?.value;
  if(!secret || body.__secret!==secret) {
    if(!secret) await logThrottled('missing_inbound_secret',60,'error',{stage:'auth'},'The inbound_secret row is missing from app_secrets, so doc_extract rejects every caller including the scheduler; no supplier document is being extracted or indexed at all.');
    else await logThrottled('bad_secret',60,'error',{stage:'auth'},'doc_extract rejected a caller presenting the wrong inbound secret. If this is the scheduled drainer, the document extraction queue is not being processed and supplier documents stay unread.');
    return j({error:'unauthorized'},401);
  }
  if(!apiKey) { await logThrottled('no_openrouter_key',60,'error',{stage:'config'},'openrouter_api_key is missing from app_secrets, so doc_extract cannot call the extraction model; every uploaded supplier document is stuck pending and none of their specs, brands or certifications reach the knowledge base.'); return j({error:'no_openrouter_key'},500); }

  // pick a document: explicit id, or next pending (batch drainer passes nothing)
  let doc:any=null;
  if(body.document_id){
    const { data } = await sb.from('documents').select('*').eq('id',body.document_id).maybeSingle(); doc=data;
  } else {
    const { data } = await sb.from('documents').select('*').eq('status','pending').lt('attempts',3).order('id').limit(1); doc=(data||[])[0];
  }
  if(!doc) return j({ok:true,note:'no pending documents'});

  const { error:claimErr } = await sb.from('documents').update({status:'processing',attempts:(doc.attempts||0)+1}).eq('id',doc.id);
  if(claimErr) await logThrottled('claim_failed',60,'error',{stage:'claim',document_id:doc.id},'doc_extract could not mark document '+doc.id+' as processing, so the same document will be picked up again every run: the queue never advances and extraction cost is burned repeatedly. '+String(claimErr?.message||claimErr).slice(0,160));

  try{
    const { data:signed, error:se } = await sb.storage.from(doc.bucket).createSignedUrl(doc.path,300);
    if(se||!signed?.signedUrl) throw new Error('signed_url_failed: '+(se?.message||''));
    const fr=await fetch(signed.signedUrl); if(!fr.ok) throw new Error('fetch_failed_'+fr.status);
    const ct=(fr.headers.get('content-type')||'').toLowerCase();
    const name=(doc.file_name||doc.path).toLowerCase();
    const isImg = ct.startsWith('image/') || /\.(jpg|jpeg|png|webp|gif)$/.test(name);
    const isPdf = ct.includes('pdf') || name.endsWith('.pdf');
    const isText= ct.startsWith('text/') || /\.(txt|csv|md|html?)$/.test(name);

    let extracted:any=null; let mime=ct||null;
    if(isImg){
      const buf=new Uint8Array(await fr.arrayBuffer());
      let bin=''; for(let i=0;i<buf.length;i++) bin+=String.fromCharCode(buf[i]);
      const b64=btoa(bin);
      const dataUrl=`data:${ct||'image/jpeg'};base64,${b64}`;
      extracted=await llmJSON(apiKey,[{type:'text',text:'Extract the fields from this document image.'},{type:'image_url',image_url:{url:dataUrl}}]);
      mime=ct||'image/jpeg';
    } else if(isPdf){
      try{
        const { extractText, getDocumentProxy } = await import('https://esm.sh/unpdf@0.11.0');
        const ab=await fr.arrayBuffer();
        const pdf=await getDocumentProxy(new Uint8Array(ab));
        const { text } = await extractText(pdf,{mergePages:true});
        const clean=(text||'').trim();
        if(clean.length>80){ extracted=await llmJSON(apiKey,`Extract the fields from this document text:\n\n${clean.slice(0,12000)}`); }
        else {
          // OCR FALLBACK. A scanned PDF has no text layer, but this function already has a
          // working vision path for images. Render the PDF to PNG via CloudConvert and use it.
          // UAE trade licences are commonly scanned, and licence extraction is the first step
          // of supplier verification, so skipping these blocks the whole verification pipeline.
          let ocrOk = false;
          try {
            const ccKey=(secrets||[]).find((s:any)=>s.key==='cloudconvert_api_key')?.value;
            if (ccKey) {
              const pdfBuf = new Uint8Array(ab);
              let pbin = ''; for (let i = 0; i < pdfBuf.length; i++) pbin += String.fromCharCode(pdfBuf[i]);
              const pdfB64 = btoa(pbin);
              const ccAuth = { 'Authorization': 'Bearer ' + ccKey, 'Content-Type': 'application/json' };
              const jr = await fetch('https://api.cloudconvert.com/v2/jobs', { method: 'POST', headers: ccAuth,
                body: JSON.stringify({ tasks: {
                  imp: { operation: 'import/base64', file: pdfB64, filename: (doc.file_name || 'doc.pdf') },
                  conv: { operation: 'convert', input: 'imp', input_format: 'pdf', output_format: 'png', pixel_density: 200, pages: '1-3' },
                  exp: { operation: 'export/url', input: 'conv', inline: false, archive_multiple_files: false }
                } }), signal: AbortSignal.timeout(25000) });
              const jj = await jr.json();
              const jobId = jj?.data?.id;
              if (jobId) {
                for (let i = 0; i < 16; i++) {
                  await new Promise((r) => setTimeout(r, 3500));
                  const pr = await fetch('https://api.cloudconvert.com/v2/jobs/' + jobId, { headers: ccAuth, signal: AbortSignal.timeout(12000) }).catch(() => null);
                  if (!pr) continue;
                  const pj = await pr.json().catch(() => ({}));
                  const tasks = (pj?.data?.tasks || []) as any[];
                  const done = tasks.find((t) => t.operation === 'export/url' && t.status === 'finished');
                  if (done) {
                    const files = (done.result?.files || []) as any[];
                    const parts: any[] = [{ type: 'text', text: 'This is a scanned document rendered to images. Extract the fields.' }];
                    for (const f of files.slice(0, 3)) {
                      const ir = await fetch(f.url, { signal: AbortSignal.timeout(20000) }).catch(() => null);
                      if (!ir || !ir.ok) continue;
                      const ibuf = new Uint8Array(await ir.arrayBuffer());
                      let ibin = ''; for (let k = 0; k < ibuf.length; k++) ibin += String.fromCharCode(ibuf[k]);
                      parts.push({ type: 'image_url', image_url: { url: 'data:image/png;base64,' + btoa(ibin) } });
                    }
                    if (parts.length > 1) { extracted = await llmJSON(apiKey, parts); ocrOk = !!extracted; }
                    break;
                  }
                  if (tasks.some((t) => t.status === 'error')) break;
                }
              }
            }
          } catch (_e) { /* fall through to the original skip */ }
          if (ocrOk) { mime = 'application/pdf'; }
          else { await sb.from('documents').update({status:'skipped',error:'scanned_pdf_no_text_ocr_failed',processed_at:new Date().toISOString()}).eq('id',doc.id); await logThrottled('skipped_scanned_pdf',60,'error',{stage:'pdf',document_id:doc.id,kind:doc.kind},'Document '+doc.id+' is a scanned PDF and the OCR fallback did not produce text, so it was skipped: this supplier document will never be read into the knowledge base and its specs and certifications are invisible to matching.'); return j({ok:true,id:doc.id,status:'skipped'}); }
        }
      }catch(pe){ await sb.from('documents').update({status:'skipped',error:'pdf_parse:'+String(pe).slice(0,120),processed_at:new Date().toISOString()}).eq('id',doc.id); await logThrottled('skipped_pdf_parse',60,'error',{stage:'pdf',document_id:doc.id,kind:doc.kind},'PDF parsing failed for document '+doc.id+' and it was silently skipped, so its contents never reach the knowledge base. '+String(pe).slice(0,160)); return j({ok:true,id:doc.id,status:'skipped'}); }
      mime='application/pdf';
    } else if(isText){
      const txt=(await fr.text()).slice(0,12000);
      extracted=await llmJSON(apiKey,`Extract the fields from this document text:\n\n${txt}`);
      mime=ct||'text/plain';
    } else {
      await sb.from('documents').update({status:'skipped',error:'unsupported_mime:'+ct,processed_at:new Date().toISOString()}).eq('id',doc.id);
      await logThrottled('skipped_unsupported_mime',60,'error',{stage:'mime',document_id:doc.id,kind:doc.kind,mime:ct},'Document '+doc.id+' has an unsupported content type ('+ct+') and was skipped, so a supplier document that was accepted at upload is never extracted or indexed.');
      return j({ok:true,id:doc.id,status:'skipped'});
    }

    if(!extracted){ throw new Error('extraction_null'); }
    // ensure array fields exist
    for(const k of ['specifications','brands','models','dates','quantities','certifications']){ if(!Array.isArray(extracted[k])) extracted[k]=[]; }
    if(typeof extracted.text!=='string') extracted.text=String(extracted.text||'');

    let indexed=false;
    if(INDEX_KINDS.has(doc.kind)){
      const parts=[extracted.text, (extracted.specifications||[]).join('; '), (extracted.brands||[]).join(', ')].filter(Boolean).join('\n');
      if(parts.trim().length>40){
        // category from the owning lead, if any
        let cat:string|null=null;
        if(doc.ref_table==='leads'&&doc.ref_id){ const { data:l }=await sb.from('leads').select('sector,sub_type').eq('id',doc.ref_id).maybeSingle(); cat=l?.sub_type||l?.sector||null; }
        const { error:kbErr } = await sb.from('kb_chunks').insert({source_kind:'document',source_id:String(doc.id),category:cat,title:(doc.file_name||doc.kind),content:parts.slice(0,6000),citation:`Supplier ${doc.kind} document`});
        if(kbErr) await logRun('error',{stage:'kb_insert',document_id:doc.id,kind:doc.kind},'Document '+doc.id+' was extracted but the kb_chunks insert failed, yet it is about to be marked indexed: this supplier capability text is permanently missing from the knowledge base and will not surface in supplier matching. '+String(kbErr?.message||kbErr).slice(0,160));
        indexed=true;
      }
    }

    const { error:doneErr } = await sb.from('documents').update({status:'done',extracted,indexed,mime,error:null,processed_at:new Date().toISOString()}).eq('id',doc.id);
    if(doneErr) await logRun('error',{stage:'mark_done',document_id:doc.id,kind:doc.kind},'Document '+doc.id+' was extracted successfully but could not be marked done, so it stays in processing forever and the extraction work (and its cost) is repeated or lost. '+String(doneErr?.message||doneErr).slice(0,160));
    else await logRun('ok',{stage:'extract',processed:1,document_id:doc.id,kind:doc.kind,indexed,brands:extracted.brands.length,specs:extracted.specifications.length,certs:extracted.certifications.length},'doc_extract processed document '+doc.id+' ('+doc.kind+'), indexed='+indexed+'.');
    return j({ok:true,id:doc.id,kind:doc.kind,indexed,fields:{brands:extracted.brands.length,specs:extracted.specifications.length,certs:extracted.certifications.length}});
  }catch(e){
    await sb.from('documents').update({status:'error',error:String(e).slice(0,200),processed_at:new Date().toISOString()}).eq('id',doc.id);
    await logThrottled('doc_error',60,'error',{stage:'extract',document_id:doc.id,kind:doc.kind},'doc_extract failed on document '+doc.id+' ('+doc.kind+'); after 3 attempts it stops being retried, so this supplier document is never read and its specs never reach the knowledge base. '+String(e).slice(0,200));
    return j({error:String(e)},500);
  }
});

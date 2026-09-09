import { requireInternal } from '../_shared/internal_auth.ts';
// doc_extract — universal Document Intelligence extractor.
// Pulls {text, specifications, brands[], models[], dates[], quantities[], certifications[]}
// from a registered document, and indexes non-sensitive docs into kb_chunks.
// Secret-gated (inbound via fn_internal_auth). Service-role only.
//
// It is the ONLY writer of public.documents.extracted, and it carries the ONLY OCR path in the
// estate: a scanned PDF (no text layer) is rendered to PNG by CloudConvert at 200 dpi, pages 1-3
// only, and read by a vision model. So OCR here is (a) three pages at most, never the whole
// document, and (b) a model reading a picture — the output is an extraction, never a certified
// transcription. It reports 'skipped' with scanned_pdf_no_text_ocr_failed when that path does not
// produce anything, and never claims a partial read as a full one.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b). Nothing else wrote
// documents.extracted, so customer_documents has been reading a column with no writer since.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Content-Type':'application/json' };
const j = (o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:cors});
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// index these kinds into the shared KB (non customer-identifying capability text).
// WHAT MAY ENTER THE SHARED LIBRARY. kb_chunks is read by kb_query, which inquiry_intake calls with
// ANOTHER customer's words, so anything indexed here is answerable to everyone.
//
// 'drawing' WAS IN THIS SET AND SHOULD NEVER HAVE BEEN (removed 10 Sep 2026). A catalogue or a
// company profile is a SUPPLIER telling us what they can do — that is capability, it is meant to be
// matched against other people's requests, and it belongs here. A drawing is a CUSTOMER's own job:
// their floorplan, their villa, their plot, their name. Indexing it put one customer's document in
// the corpus every other customer is answered from. Measured before this change: kb_query('gypsum
// false ceiling') returned a customer's villa floorplan as result #1, complete with the firm name,
// the client's name, the plot address, a mobile number and an email.
//
// THE CUSTOMER'S DRAWING IS STILL READ, AND STILL BY THE SALES ENGINEER — through the scoped path
// that already exists and is the right one: doc_extract writes the extraction to documents.extracted
// for that document, the BOQ lands on inquiries.boq / drawing_file_path for that inquiry, and
// inquiry_intake receives it as `drawing_boq` and tells the model "the customer also attached a
// drawing/quotation from which we read N line items". That path is scoped to the one inquiry it
// belongs to. Nothing about reading a customer's drawing is lost here; only the second, unscoped
// copy is.
//
// Note the citation below is hard-coded 'Supplier <kind> document' — which is how a customer's
// floorplan came to be filed under the word "Supplier". With drawings out, the label is true again.
const INDEX_KINDS = new Set(['catalog','profile']);
// never index (pricing tied to identity, or PII documents)
// quote, licence, egr are intentionally excluded.

// cred_fn_ai, captured once per request so llmJSON can reach ai_gateway without a signature change.
let GW='';

async function llmJSON(apiKey:string, content:unknown):Promise<any>{
  const sys='You are a document-extraction engine for a UAE construction/services procurement platform. '+
    'Return STRICT JSON only (no markdown) with exactly these keys: '+
    'text (string: a faithful transcription or concise summary of the readable content), '+
    'specifications (array of short strings), brands (array of strings), models (array of strings), '+
    'dates (array of strings as seen), quantities (array of strings like "12 nos", "45 sqm"), '+
    'certifications (array of strings e.g. SIRA, ISO 9001, IP65, CE). '+
    'Use [] for anything absent. Never invent values.';
  // BOTH paths now go through ai_gateway (routing, cache, budget, cost logging). Gateway v3 passes
  // multimodal content blocks straight through, so the image / scanned-page payload no longer needs
  // a direct OpenRouter call - the model ladder lives in the gateway.
  const key = apiKey || GW;
  try{
    // NO `max` HERE ON PURPOSE. ai_gateway computes
    //   maxTok = min(body.max ?? route.max_tokens, route.max_tokens)
    // so a caller-supplied max can only ever LOWER the policy ceiling, never raise it. `max:2000`
    // therefore overrode model_policy.document_extraction's 8000 and capped this function at 2000.
    // Measured on deployed staging 5 Aug 2026, first time doc_extract had ever run there: a single
    // drawing page produced 1,222 prompt + 1,996 output tokens against that 2,000 ceiling and
    // returned extraction_null - the same 1,996 recorded for quote_extract in session 8, because
    // gemini-3.5-flash spends most of its output budget on reasoning tokens and emits little
    // visible JSON. Sizing this from expected JSON length is wrong by an order of magnitude on that
    // model. Let the task class decide; that is what the task class is for.
    const payload = (typeof content==='string')
      ? {__secret:key,fn:'doc_extract',sys,input:content,temperature:0}
      : {__secret:key,fn:'doc_extract',sys,input:[{role:'user',content}],temperature:0};
    const r=await fetch(Deno.env.get('SUPABASE_URL')!+'/functions/v1/ai_gateway',{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify(payload)});
    if(!r.ok){return null;}
    const d=await r.json();
    if(d?.ok===false){return null;}
    let t=d?.content||'';
    t=String(t).replace(/^```(json)?/i,'').replace(/```$/,'').trim();
    const m=t.match(/\{[\s\S]*\}/); if(m) return JSON.parse(m[0]);
  }catch(_e){/*fall through to null*/}
  return null;
}

Deno.serve(observe('doc_extract', async (req) => {
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
  const { data:secrets } = await sb.from('app_secrets').select('key,value').in('key',['cred_fn_ai','cloudconvert_api_key']);
  const secret=(secrets||[]).find((s:any)=>s.key==='cred_fn_ai')?.value;
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(sb, body?.__secret, 'doc_extract');
  if(!__auth.ok) {
    if(!secret) await logThrottled('missing_cred_fn_ai',60,'error',{stage:'auth'},'The cred_fn_ai row is missing from app_secrets, so doc_extract cannot authenticate to ai_gateway; no supplier document is being extracted or indexed at all.');
    else await logThrottled('bad_secret',60,'error',{stage:'auth'},'doc_extract rejected a caller presenting the wrong inbound secret. If this is the scheduled drainer, the document extraction queue is not being processed and supplier documents stay unread.');
    return j({error:'unauthorized'},401);
  }
  GW=String(secret);
  // The OpenRouter key now lives only inside ai_gateway; what this function needs is the inbound secret.
  const apiKey=GW;
  if(!apiKey) { await logThrottled('no_openrouter_key',60,'error',{stage:'config'},'cred_fn_ai is missing from app_secrets, so doc_extract cannot reach ai_gateway to call the extraction model; every uploaded supplier document is stuck pending and none of their specs, brands or certifications reach the knowledge base.'); return j({error:'no_openrouter_key'},500); }

  // pick a document: explicit id, or next pending (batch drainer passes nothing)
  //
  // THE RETRY BUDGET COULD NEVER BE SPENT (10 Aug 2026). This selector read status='pending' and
  // lt('attempts',3) — but a failure below writes status='error', and NOTHING ever returns a row to
  // 'pending'. So `attempts < 3` was a dead guard: the first failure was permanent, and a document
  // stayed broken even after the bug that broke it had been fixed.
  //
  // Measured: document 10, a real 105,843-byte PNG floorplan that is present in storage, has sat at
  // status='error' / 'Error: extraction_null' / attempts=1 since 2026-07-15. It failed because
  // ai_gateway was then capped at max:2000 by this function's own caller-supplied ceiling; that was
  // removed weeks ago and the task class now allows 8000. The document was never retried, so it is
  // still the single row keeping s26-verify-documentation at 7 of 8.
  //
  // 'error' rejoins the queue while it still has budget. 'skipped' deliberately does NOT — that is a
  // terminal decision the code makes on purpose (unsupported mime, scanned PDF with no OCR text),
  // and retrying it would just burn extraction cost on the same refusal every five minutes.
  let doc:any=null;
  if(body.document_id){
    const { data } = await sb.from('documents').select('*').eq('id',body.document_id).maybeSingle(); doc=data;
  } else {
    const { data } = await sb.from('documents').select('*').in('status',['pending','error']).lt('attempts',3).order('id').limit(1); doc=(data||[])[0];
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
    // AND IT MUST BE OWNED BY A SUPPLIER, not merely be of a shareable kind. The kind list says what
    // sort of document this is; ref_table says WHOSE it is, and that is the question that actually
    // decides whether it may be answered to strangers. A profile uploaded against an inquiry is
    // still one customer's file. Belt and braces on purpose: the two rows that leaked were a
    // customer drawing AND a supplier profile whose owning lead had since been deleted.
    if(INDEX_KINDS.has(doc.kind) && doc.ref_table==='leads'){
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
}));

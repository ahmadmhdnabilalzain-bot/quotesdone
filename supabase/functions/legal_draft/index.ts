import { createClient } from 'jsr:@supabase/supabase-js@2';
const sb=createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE=Deno.env.get('SUPABASE_URL')!+'/functions/v1';
const FALLBACK_MODELS=['anthropic/claude-opus-4.8','anthropic/claude-sonnet-5'];
async function sec(k:string){ const {data}=await sb.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value||''; }
async function llm(key:string, system:string, user:string){
  const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({models:FALLBACK_MODELS,max_tokens:4000,messages:[{role:'system',content:system},{role:'user',content:user}]})});
  const j=await r.json(); return j?.choices?.[0]?.message?.content||'';
}
const DOC_TITLES:Record<string,string>={demand_notice:'Letter of Demand (Letter Before Action)',legal_notice:'Formal Legal Notice',final_warning:'Final Demand & Notice of Suspension',statement_of_claim:'Draft Statement of Claim (Civil Court)'};

Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  if(b.__secret!==(await sec('inbound_secret'))) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
  const started=new Date().toISOString();
  const doc_type=String(b.doc_type||'demand_notice');
  const pay_days=Number(b.pay_days||7);
  try{
    const ork=await sec('openrouter_api_key'); if(!ork) return new Response(JSON.stringify({error:'no llm key'}),{status:200,headers:{'Content-Type':'application/json'}});
    let facts:any={ company:b.company||null, breach:b.breach||'non_payment' };
    if(b.supplier_id){
      const {data:lead}=await sb.from('leads').select('id,company_name,emirate,trade_license_no,trn,claimed_by,email').eq('id',b.supplier_id).maybeSingle();
      if(lead){ facts.company=lead.company_name; facts.emirate=lead.emirate; facts.trade_license_no=lead.trade_license_no; facts.trn=lead.trn; facts.contact=lead.claimed_by||lead.email; }
      const {data:dues}=await sb.from('supplier_dues').select('quote_id,quote_amount,amount_due,fine_amount,status,due_date,reveal_date').eq('supplier_id',b.supplier_id).not('status','in','(paid,waived)');
      if(dues&&dues.length){
        let principal=0,charges=0,qv=0; const items:any[]=[];
        for(const d of dues){ principal+=Number(d.amount_due||0); charges+=Number(d.fine_amount||0); qv+=Number(d.quote_amount||0); items.push({quote_id:d.quote_id,quotation_value:d.quote_amount,commission_due:d.amount_due,charges:d.fine_amount,due_date:d.due_date,status:d.status}); }
        facts.commission_principal=Math.round(principal); facts.accrued_charges=Math.round(charges); facts.total_quotation_value=Math.round(qv); facts.total_claimed=Math.round(principal+charges); facts.line_items=items;
      }
      const {data:viol}=await sb.from('chat_violations').select('id,created_at').eq('supplier_id',b.supplier_id).limit(20);
      if(viol&&viol.length){ facts.contact_disclosure_incidents=viol.length; }
    }
    for(const k of ['commission_principal','accrued_charges','total_quotation_value','total_claimed','quote_id','emirate','trade_license_no','contact_disclosure_incidents']) if(b[k]!=null) facts[k]=b[k];
    if(facts.total_claimed==null && facts.commission_principal!=null) facts.total_claimed=Math.round(Number(facts.commission_principal||0)+Number(facts.accrued_charges||0));
    const today=new Date().toISOString().slice(0,10);
    const system='You are in-house UAE legal counsel for QuotesDone (an anonymous B2B quotation marketplace, Dubai, UAE). Draft a formal, professional, ready-to-send '+(DOC_TITLES[doc_type]||doc_type)+' addressed to the defaulting Supplier. Ground it strictly in UAE law and the Supplier Agreement the Supplier accepted electronically at sign-up. Cite, where relevant: the binding electronic acceptance of the Supplier Agreement (UAE Federal Decree-Law No. 46 of 2021 on Electronic Transactions and Trust Services); the 2% Commission and 14-working-day payment term; the agreed late-payment charge (1% per month / 12% per annum, the maximum upheld for commercial debts, with total interest capped at the principal) and AED 250 administrative fee under the Commercial Transactions Law (Federal Decree-Law No. 50 of 2022); the debt being due and payable under the Civil Transactions Law (Federal Law No. 5 of 1985); and, for off-platform contact / circumvention, the AED 10,000-per-incident liquidated sum. Structure: recipient block, subject line, numbered recitals/background, the specific breach, an itemised statement of the sum claimed in AED, a clear demand to pay within '+pay_days+' calendar days, consequences of non-payment (suspension already applied where relevant, civil proceedings before the competent Dubai Courts, plus interest, legal costs and fees), an express reservation of all rights, and a closing (the QuotesDone letterhead, signatory block and company stamp are applied automatically by the template, so do NOT draw an ASCII letterhead or restate the sender address block). Use only the facts provided — do not invent amounts, dates, licence numbers or names; where a needed detail is missing, insert a clearly bracketed placeholder like [TRADE LICENCE NO.]. Professional legal English. Output the document text only.';
    const user='Draft a '+(DOC_TITLES[doc_type]||doc_type)+'.\n\nCase facts (JSON):\n'+JSON.stringify(facts,null,2)+'\n\nAdditional instructions: '+(b.notes||'none')+'\nPayment deadline: '+pay_days+' calendar days from the date of the notice.';
    const text=await llm(ork,system,user);
    if(!text){ await sb.from('agent_runs').insert({agent:'legal_draft',started_at:started,finished_at:new Date().toISOString(),status:'error',note:'empty llm'}); return new Response(JSON.stringify({error:'empty'}),{status:200,headers:{'Content-Type':'application/json'}}); }
    // Render a BRANDED PDF (letterhead + signatory + company stamp) via make_pdf -> pdf_native.
    const esc=(s:string)=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    let bodyHtml='';
    for(const raw of text.split('\n')){ const t=raw.replace(/\s+$/,''); if(!t){ bodyHtml+='<div style="height:6px"></div>'; continue; } if(t===t.toUpperCase() && /[A-Za-z]/.test(t) && t.length<70) bodyHtml+='<h3>'+esc(t)+'</h3>'; else bodyHtml+='<p>'+esc(t)+'</p>'; }
    const fullHtml='<!doctype html><meta charset="utf-8"><title>'+(DOC_TITLES[doc_type]||doc_type)+'</title><body>'+bodyHtml+'</body>';
    const nameSafe=(facts.company?String(facts.company).replace(/[^a-z0-9]+/gi,'_').slice(0,40):'case')+'_'+doc_type;
    let pdf_url:string|null=null, pdf_path:string|null=null, html_path:string|null=null;
    try{ const mr=await fetch(BASE+'/make_pdf',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:await sec('inbound_secret'), html:fullHtml, title:(DOC_TITLES[doc_type]||doc_type), name:nameSafe, bucket:'finance-reports', folder:'legal', options:{letterhead:true, sign:true, stamp:true}})}); const mj=await mr.json(); if(mj&&mj.url){ pdf_url=mj.url; pdf_path=mj.path; } }catch(_){}
    // keep a plain HTML copy as fallback
    try{ const html='<!doctype html><meta charset="utf-8"><title>'+(DOC_TITLES[doc_type]||doc_type)+'</title><body style="font:14px/1.7 Georgia,serif;max-width:760px;margin:32px auto;padding:0 22px;color:#16181d;white-space:pre-wrap">'+esc(text)+'</body>'; const p='legal/'+nameSafe+'_'+Date.now()+'.html'; const {error}=await sb.storage.from('finance-reports').upload(p,new Blob([html],{type:'text/html'}),{contentType:'text/html',upsert:true}); if(!error) html_path=p; }catch(_){}
    await sb.from('agent_runs').insert({agent:'legal_draft',started_at:started,finished_at:new Date().toISOString(),status:'ok',counts:{doc_type,total_claimed:facts.total_claimed||null},note:(facts.company||'')+' '+doc_type});
    return new Response(JSON.stringify({ok:true,doc_type,title:DOC_TITLES[doc_type]||doc_type,company:facts.company,total_claimed:facts.total_claimed||null,pdf_url,pdf_path,html_path,path:pdf_path||html_path,text}),{headers:{'Content-Type':'application/json'}});
  }catch(e){
    await sb.from('agent_runs').insert({agent:'legal_draft',started_at:started,finished_at:new Date().toISOString(),status:'error',note:String(e).slice(0,200)});
    return new Response(JSON.stringify({error:String(e)}),{status:200,headers:{'Content-Type':'application/json'}});
  }
});
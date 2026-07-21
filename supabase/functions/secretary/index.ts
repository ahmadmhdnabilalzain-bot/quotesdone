import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL=Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o:unknown,s=200)=> new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
async function cntT(t:string, mod?:(q:any)=>any){ let q=admin.from(t).select('id',{count:'exact',head:true}); if(mod) q=mod(q); const {count}=await q; return count||0; }
async function llm(sys:string, msgs:{role:string;content:string}[], max=1600){ const key=await sec('openrouter_api_key'); if(!key) return null; const MODELS=['anthropic/claude-opus-4.8','anthropic/claude-sonnet-5']; for(const model of MODELS){ for(let at=0; at<2; at++){ try{ const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({model,max_tokens:max,messages:[{role:'system',content:sys},...msgs]})}); const j=await r.json(); const c=j?.choices?.[0]?.message?.content; if(c) return c; }catch(_e){} } } return null; }
async function llmFast(sys:string, user:string){ const key=await sec('openrouter_api_key'); if(!key) return ''; const MODELS=['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8']; try{ const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({models:MODELS,max_tokens:160,temperature:0,messages:[{role:'system',content:sys},{role:'user',content:user}]})}); const j=await r.json(); return j?.choices?.[0]?.message?.content||''; }catch(_e){ return ''; } }
async function learn(userMsg:string, assistantMsg:string){
  try{
    if(!assistantMsg || assistantMsg.length<60) return; if(/could not reach the AI service/i.test(assistantMsg)) return; if((userMsg+assistantMsg).length<160) return;
    const { data:mem } = await admin.from('agent_memory').select('content').eq('agent_key','secretary').order('id',{ascending:false}).limit(40);
    const known=(mem||[]).map((m:any)=>'- '+m.content).join('\n');
    const sys='You maintain the long-term MEMORY of the Secretary / chief-of-staff agent at QuotesDone, a UAE B2B marketplace. From the latest exchange, extract AT MOST ONE durable, reusable item to remember for next time that is genuinely NOT already in memory below. Capture only long-term-useful things: a founder preference/policy/priority, a standing instruction, a corrected fact, a confirmed figure. IGNORE greetings, one-off data, anything already known or uncertain. Reply with ONE self-contained factual line (max 220 chars), or EXACTLY NONE.\n\nEXISTING MEMORY:\n'+(known||'(empty)');
    const user='FOUNDER said: '+userMsg.slice(0,1200)+'\n\nSECRETARY replied: '+assistantMsg.slice(0,1500);
    const out=(await llmFast(sys,user)).trim().replace(/^[-*]\s*/,'');
    if(out && out.toUpperCase()!=='NONE' && !/^none[.!]?$/i.test(out) && out.length>10 && out.length<360){ await admin.from('agent_memory').insert({agent_key:'secretary',kind:'learned',content:out.slice(0,360),source:'auto_chat'}); }
  }catch(_e){}
}
const AGENT_NAMES:Record<string,string>={legal:'Legal Counsel',collections:'Collections',cfo:'CFO',bookkeeper:'Bookkeeper',security:'Security',it:'IT / Uptime',onboarding:'Onboarding / KYC',docs:'Document Controller',followup:'Follow-up',bd:'BD Representative',marketing:'Marketing',brief:'Daily Brief'};
const VALID_AGENTS=Object.keys(AGENT_NAMES);
const SAFE_JOBS=['finance','marketing','security','it_health','onboarding','followup','category_sales','compliance','bd_outreach'];
function splitActions(s:string):[string, any]{ const i=s.indexOf('@@ACTIONS@@'); if(i<0) return [s,null]; const clean=s.slice(0,i).trim(); const tail=s.slice(i+11); const mm=tail.match(/\{[\s\S]*\}/); let a:any=null; if(mm){ try{ a=JSON.parse(mm[0]); }catch(_e){} } return [clean,a]; }
async function logSec(kind:string, who:string, req:Request, severity='high'){
  try{ const ip=(req.headers.get('x-forwarded-for')||'').split(',')[0].trim(); const ua=(req.headers.get('user-agent')||'').slice(0,200);
    await admin.from('security_events').insert({kind,severity,source:'admin',subject:(who||'unknown').slice(0,120),detail:{ip,ua}});
    if(kind==='admin_denied'){ const {count}=await admin.from('security_events').select('id',{count:'exact',head:true}).eq('kind','admin_denied').gte('created_at',new Date(Date.now()-3600e3).toISOString()); const n=count||0; if(n===1||n%5===0){ const owner=String(await sec('admin_emails')||'management@quotesdone.com').split(',')[0].trim(); await admin.from('notifications').insert({type:'security_alert',to_email:owner,to_role:'admin',channel:'email',subject:'QuotesDone security: blocked admin access attempt',body:'A non-admin ('+(who||'unknown')+', IP '+(ip||'?')+') tried to access the admin dashboard and was blocked by the allowlist. Your data was not exposed.'}); } }
  }catch(_e){}
}
async function knowledge(){
  const { data:k } = await admin.from('agent_knowledge').select('topic,content').in('agent_key',['_global','secretary']).order('priority',{ascending:false}).limit(20);
  const { data:mem } = await admin.from('agent_memory').select('content').eq('agent_key','secretary').order('id',{ascending:false}).limit(20);
  let s='';
  if(k&&k.length) s+='\n\nKNOWLEDGE BASE (your expertise and how the company works — rely on this, do not browse the web):\n'+k.map((r:any)=>'- '+(r.topic?r.topic+': ':'')+r.content).join('\n');
  if(mem&&mem.length) s+='\n\nWHAT YOU HAVE LEARNED (memory, newest first):\n'+mem.map((r:any)=>'- '+r.content).join('\n');
  return s;
}
async function snapshot(){
  const since7=new Date(Date.now()-7*864e5).toISOString();
  const { data:pend } = await admin.from('agent_actions').select('id,agent,kind,title,risk,recommendation,created_at').eq('status','pending').order('id',{ascending:false}).limit(40);
  const { data:runs } = await admin.from('agent_runs').select('agent,status,finished_at,counts').order('id',{ascending:false}).limit(24);
  const { data:dues } = await admin.from('supplier_dues').select('amount_due,fine_amount,status').not('status','in','(paid,waived)');
  let dueSum=0,dueCnt=0; for(const d of (dues||[])){ dueCnt++; dueSum+=Number(d.amount_due||0)+Number(d.fine_amount||0); }
  const [sec7, kyc, refunds, drafts, inq7, q7, sup, cust, adminEv, denied7] = await Promise.all([
    cntT('security_events',(q)=>q.gte('created_at',since7)), cntT('leads',(q)=>q.eq('approval_status','pending')), cntT('transactions',(q)=>q.eq('refund_status','requested')), cntT('content_drafts',(q)=>q.eq('status','draft')), cntT('inquiries',(q)=>q.gte('created_at',since7)), cntT('quotes',(q)=>q.gte('created_at',since7)), cntT('leads',(q)=>q.eq('permanently_closed',false)), cntT('customers'), cntT('security_events',(q)=>q.like('kind','admin_%').gte('created_at',since7)), cntT('security_events',(q)=>q.eq('kind','admin_denied').gte('created_at',since7))
  ]);
  return { pending_approvals:pend||[], pending_count:(pend||[]).length, recent_runs:runs||[], overdue_commissions:{count:dueCnt,total_aed:Math.round(dueSum)}, security_events_7d:sec7, blocked_admin_attempts_7d:denied7, kyc_pending:kyc, refunds_requested:refunds, marketing_drafts:drafts, inquiries_7d:inq7, quotes_7d:q7, suppliers:sup, customers:cust };
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response(null,{headers:CORS});
  try{
    const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
    const { data:{ user } } = await admin.auth.getUser(jwt);
    if(!user||!user.email) return J({error:'unauthorized'},401);
    const email=user.email.toLowerCase();
    const body=await req.json().catch(()=>({}));
    const action=String(body.action||'chat');
    const al=await sec('admin_emails'); const admins=String(al||'management@quotesdone.com').toLowerCase().split(',').map(s=>s.trim());
    const isAdmin=admins.includes(email);
    if(action==='log_denied'){ if(!isAdmin) await logSec('admin_denied', email, req); return J({ok:true}); }
    if(!isAdmin) return J({error:'forbidden'},403);
    if(action==='audit_login'){ await logSec('admin_login', email, req, 'info'); return J({ok:true}); }
    if(action==='history'){ const { data } = await admin.from('agent_chats').select('role,content,created_at').eq('agent_key','secretary').order('id',{ascending:false}).limit(30); return J({messages:(data||[]).reverse()}); }
    const msg=String(body.message||'').trim(); if(!msg) return J({error:'message required'},400);
    const attach = (body.attachment_text && String(body.attachment_text).trim()) ? String(body.attachment_text).slice(0,12000) : '';
    const attachName = body.attachment_name ? String(body.attachment_name).slice(0,160) : '';
    const { data:hist } = await admin.from('agent_chats').select('role,content').eq('agent_key','secretary').order('id',{ascending:false}).limit(10);
    const history=(hist||[]).reverse().map((h:any)=>({role:h.role,content:h.content}));
    let snap:any={}; try{ snap=await snapshot(); }catch(_e){ snap={error:'snapshot unavailable'}; }
    const persona='You are the Secretary — the executive assistant and chief of staff for the founder of QuotesDone, a UAE B2B anonymous quotation marketplace, with 10+ years of experience. The founder talks to you and you alone; you coordinate every other agent. Answer requests for any report, status or number using the LIVE DATA SNAPSHOT below (it aggregates across all agents). When a decision is needed, surface it plainly and note it is waiting in the approvals queue. When a topic belongs to a specialist, answer from the snapshot and name which agent owns it. Be proactive, organised, warm and concise. Never invent numbers; if the snapshot lacks something, say so and say which agent owns it. If the founder attaches a document, read its content (provided below) and use it to answer, summarise, or build whatever they ask.\n\nDISPATCH & ACTION POWERS: You can act, not just report. AFTER your normal reply, append on a NEW LINE exactly @@ACTIONS@@ then compact JSON with any of these keys: {"handoffs":[{"to":"<agent_key>","title":"<short>","details":"<what to do and why>"}], "run":["<job>"], "emails":[{"to":"<email>","subject":"<s>","body":"<full email body>"}], "documents":[{"title":"<title>","layout":"<sections/tables>"}], "pdfs":[{"title":"<title>","layout":"<describe exact sections/tables/order>","data":{}}], "excels":[{"title":"<title>","sheets":[{"name":"<tab>","rows":[["Header A","Header B"],["value",123]]}]}]}. handoffs delegate a task to a specialist; run triggers a specialist routine now; emails sends an email from QuotesDone (use ONLY when the founder asked to email someone); documents makes a quick branded HTML document (view/print in browser); pdfs makes a REAL downloadable PDF file (use this when the founder wants a proper PDF report/letter/quotation); excels makes a REAL .xlsx workbook (provide sheets, each with rows; the FIRST row of each sheet is the column headers; put real values in the cells). Omit @@ACTIONS@@ entirely if none. Never mention this mechanism or the token @@ACTIONS@@ in your visible reply — just speak naturally (e.g. “I’ve emailed them” / “Here’s the PDF” / “Here’s the Excel”).';
    const sys=persona+(await knowledge())+'\n\nLIVE DATA SNAPSHOT (read-only, captured just now):\n'+JSON.stringify(snap).slice(0,9000)+(attach?('\n\nFOUNDER ATTACHED A DOCUMENT'+(attachName?(' ("'+attachName+'")'):'')+' — its text content follows; use it to answer or act:\n'+attach):'');
    const userMsg = msg + (attach?('\n\n[Attached '+(attachName||'document')+' — content provided in system context]'):'');
    const rawReply=await llm(sys,[...history,{role:'user',content:userMsg}],1800)||'I could not reach the AI service just now — please try again in a moment.';
    let [clean,acts]=splitActions(rawReply); let finalReply=clean||rawReply; const notes:string[]=[];
    if(acts&&Array.isArray(acts.handoffs)){
      for(const h of acts.handoffs.slice(0,5)){ const to=String(h?.to||'').toLowerCase(); if(!VALID_AGENTS.includes(to)) continue; const title=String(h?.title||'task').slice(0,160); const details=String(h?.details||'').slice(0,800);
        try{ await admin.from('agent_actions').insert({agent:to,kind:'handoff',status:'pending',risk:'low',title:('Handoff — '+title).slice(0,200),recommendation:details,detail:{from:'secretary',from_name:'Secretary',requested_at:new Date().toISOString()},target_table:null}); notes.push('→ Dispatched to '+(AGENT_NAMES[to]||to)+': '+title); }catch(_e){}
      }
    }
    if(acts&&Array.isArray(acts.run)){ const inb=await sec('inbound_secret');
      for(const job of acts.run.slice(0,3)){ const j=String(job||'').toLowerCase(); if(!SAFE_JOBS.includes(j)) continue;
        try{ const p=fetch(SUPA_URL+'/functions/v1/agents',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:inb,job:j})}).catch(()=>{}); try{ (globalThis as any).EdgeRuntime?.waitUntil?.(p); }catch(_e){} notes.push('▶ Triggered '+j+' to run now (refresh in ~30–60s)'); }catch(_e){}
      }
    }
    if(acts&&Array.isArray(acts.emails)){
      for(const e of acts.emails.slice(0,5)){ const to=String(e?.to||'').trim(); if(!/@/.test(to)) continue;
        try{ await admin.from('notifications').insert({type:'agent_email',to_email:to,to_role:'external',channel:'email',subject:String(e?.subject||'').slice(0,200),body:String(e?.body||'').slice(0,6000)}); notes.push('✉ Email queued to '+to+': '+String(e?.subject||'').slice(0,70)); }catch(_e){}
      }
    }
    if(acts&&Array.isArray(acts.documents)){ const inb=await sec('inbound_secret');
      for(const dco of acts.documents.slice(0,3)){
        try{ const r=await fetch(SUPA_URL+'/functions/v1/doc_render',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:inb,title:String(dco?.title||'Document'),layout:String(dco?.layout||dco?.brief||''),data:dco?.data||null})}); const j=await r.json(); if(j?.ok&&j.url) notes.push('📄 '+String(dco?.title||'Document')+': '+j.url); else notes.push('Document generation failed: '+(j?.error||'?')); }catch(_e){ notes.push('Document generation error'); }
      }
    }
    if(acts&&Array.isArray(acts.pdfs)){ const inb=await sec('inbound_secret');
      for(const pco of acts.pdfs.slice(0,3)){ const title=String(pco?.title||'Document');
        try{ let url=''; const dr=await fetch(SUPA_URL+'/functions/v1/doc_render',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:inb,title,layout:String(pco?.layout||pco?.brief||''),data:pco?.data||null})}); const dj=await dr.json(); if(dj?.ok&&dj.url) url=dj.url; else { notes.push('PDF layout render failed: '+(dj?.error||'?')); continue; } const pr=await fetch(SUPA_URL+'/functions/v1/make_pdf',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:inb,url,name:title,folder:'secretary'})}); const pj=await pr.json(); if(pj?.ok&&pj.url) notes.push('📄 '+title+' (PDF): '+pj.url); else notes.push('PDF conversion failed: '+(pj?.error||'?')); }catch(_e){ notes.push('PDF generation error'); }
      }
    }
    if(acts&&Array.isArray(acts.excels)){ const inb=await sec('inbound_secret');
      for(const xco of acts.excels.slice(0,3)){ const title=String(xco?.title||'Workbook'); let sheets=Array.isArray(xco?.sheets)?xco.sheets:(Array.isArray(xco?.rows)?[{name:'Sheet1',rows:xco.rows}]:null); if(!sheets){ notes.push('Excel skipped (no rows)'); continue; }
        try{ const r=await fetch(SUPA_URL+'/functions/v1/make_xlsx',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:inb,sheets,name:title,folder:'secretary'})}); const j=await r.json(); if(j?.ok&&j.url) notes.push('📊 '+title+' (Excel): '+j.url); else notes.push('Excel build failed: '+(j?.error||'?')); }catch(_e){ notes.push('Excel generation error'); }
      }
    }
    if(notes.length) finalReply=finalReply+'\n\n'+notes.join('\n');
    await admin.from('agent_chats').insert([{agent_key:'secretary',role:'user',content:msg+(attachName?(' [📎 '+attachName+']'):''),created_by:email},{agent_key:'secretary',role:'assistant',content:finalReply}]);
    if(/\b(remember|always|never|from now on|for future|going forward|note that|our policy|keep in mind|prefer)\b/i.test(msg)){ try{ await admin.from('agent_memory').insert({agent_key:'secretary',kind:'instruction',content:msg.slice(0,600),source:'founder_chat'}); }catch(_e){} }
    try{ const p=learn(msg,finalReply); (globalThis as any).EdgeRuntime?.waitUntil?.(p); }catch(_e){}
    return J({reply:finalReply});
  }catch(e){ return J({error:String((e as Error)?.message||e)},500); }
});
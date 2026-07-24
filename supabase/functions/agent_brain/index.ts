import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o:unknown,s=200)=> new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
async function cntT(t:string, mod?:(q:any)=>any){ let q=admin.from(t).select('id',{count:'exact',head:true}); if(mod) q=mod(q); const {count}=await q; return count||0; }
// Agent reasoning on Opus 4.8 (strongest), with Sonnet 5 as automatic fallback. Iterated per-model for robustness against intermittent empty completions.
const llm = makeLlm(SONNET_FIRST, { max: 1600 }); // shared OpenRouter client (Sonnet-first + 25s timeout)
async function llmFast(sys:string, user:string){ const key=await sec('openrouter_api_key'); if(!key) return ''; const MODELS=['anthropic/claude-sonnet-5','anthropic/claude-opus-4.8']; try{ const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({models:MODELS,max_tokens:160,temperature:0,messages:[{role:'system',content:sys},{role:'user',content:user}]}),signal:AbortSignal.timeout(20000)/* H9 (OS audit) */}); const j=await r.json(); return j?.choices?.[0]?.message?.content||''; }catch(_e){ return ''; } }

// AUTO-LEARN: after a chat, capture at most one durable new fact into the agent's memory (runs in background, no user-facing latency)
async function learn(key:string, name:string, userMsg:string, assistantMsg:string){
  try{
    if(!assistantMsg || assistantMsg.length<60) return;
    if(/could not reach the AI service/i.test(assistantMsg)) return;
    if((userMsg+assistantMsg).length<160) return;
    const { data:mem } = await admin.from('agent_memory').select('content').eq('agent_key',key).order('id',{ascending:false}).limit(40);
    const known=(mem||[]).map((m:any)=>'- '+m.content).join('\n');
    const sys='You maintain the long-term MEMORY of the '+name+' agent at QuotesDone, a UAE B2B marketplace. From the latest exchange, extract AT MOST ONE durable, reusable item this agent should remember for next time and that is genuinely NOT already covered by its existing memory below. Capture only long-term-useful things: a new standard/spec/regulation, a founder preference or policy, a corrected fact, a resolved how-to, a confirmed price/figure. IGNORE: greetings, one-off data, anything already known, anything uncertain. Reply with ONE self-contained factual memory line (max 220 chars), or EXACTLY the word NONE. Do not add commentary.\n\nEXISTING MEMORY:\n'+(known||'(empty)');
    const user='FOUNDER/USER said: '+userMsg.slice(0,1200)+'\n\n'+name+' AGENT replied: '+assistantMsg.slice(0,1500);
    const out=(await llmFast(sys,user)).trim().replace(/^[-*]\s*/,'');
    if(out && out.toUpperCase()!=='NONE' && !/^none[.!]?$/i.test(out) && out.length>10 && out.length<360){
      await admin.from('agent_memory').insert({agent_key:key,kind:'learned',content:out.slice(0,360),source:'auto_chat'});
    }
  }catch(_e){}
}

const NAMES:Record<string,string>={brief:'Daily Brief',it:'IT / Uptime',security:'Security Engineer',docs:'Document Controller',onboarding:'Onboarding / KYC',followup:'Follow-up',collections:'Collections Accountant',bd:'BD Representative',bookkeeper:'Bookkeeper',cfo:'CFO',legal:'Legal Counsel',marketing:'Marketing'};
const VALID_AGENTS=['legal','collections','cfo','bookkeeper','security','it','onboarding','docs','followup','bd','marketing','brief'];
function splitActions(s:string):[string, any]{ const i=s.indexOf('@@ACTIONS@@'); if(i<0) return [s,null]; const clean=s.slice(0,i).trim(); const tail=s.slice(i+11); const mm=tail.match(/\{[\s\S]*\}/); let a:any=null; if(mm){ try{ a=JSON.parse(mm[0]); }catch(_e){} } return [clean,a]; }

async function meta(key:string){
  if(NAMES[key]) return { name:NAMES[key] };
  if(key.startsWith('cat:')){ const { data:ca }=await admin.from('category_agents').select('name,persona').eq('slug',key.slice(4)).maybeSingle(); if(ca) return { name:ca.name+' Sales', persona: ca.persona }; }
  return null;
}
async function knowledge(key:string){
  const { data:k } = await admin.from('agent_knowledge').select('topic,content').in('agent_key',['_global',key]).order('priority',{ascending:false}).limit(26);
  const { data:mem } = await admin.from('agent_memory').select('content').eq('agent_key',key).order('id',{ascending:false}).limit(15);
  let s='';
  if(k&&k.length) s+='\n\nKNOWLEDGE BASE (your professional expertise and how the company works — rely on this; do not browse the web for it):\n'+k.map((r:any)=>'- '+(r.topic?r.topic+': ':'')+r.content).join('\n');
  if(mem&&mem.length) s+='\n\nWHAT YOU HAVE LEARNED SO FAR (memory, newest first — treat as established facts/preferences):\n'+mem.map((r:any)=>'- '+r.content).join('\n');
  return s;
}
async function retrieve(msg:string){
  try{
    const secret=await sec('inbound_secret'); if(!secret) return '';
    const r=await fetch(SUPA+'/functions/v1/kb_search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:secret,query:msg,k:6})});
    const j=await r.json(); const rows=(j&&Array.isArray(j.results))?j.results:[];
    if(!rows.length) return '';
    return '\n\nRETRIEVED REFERENCE KNOWLEDGE (semantic + keyword matches from the company knowledge base — UAE codes, standards, regulations and internal know-how relevant to this question; rely on it and cite the reference in [brackets] when you use it):\n'+rows.map((x:any)=>'- ['+(x.citation||x.category||'ref')+'] '+String(x.snippet||'').replace(/\s+/g,' ').slice(0,400)).join('\n');
  }catch(_e){ return ''; }
}
async function context(key:string){
  const since7=new Date(Date.now()-7*864e5).toISOString();
  const { data:mine } = await admin.from('agent_actions').select('id,kind,title,risk,recommendation,status,detail,created_at').eq('agent',key).order('id',{ascending:false}).limit(15);
  const { data:runs } = await admin.from('agent_runs').select('agent,status,finished_at,counts').order('id',{ascending:false}).limit(12);
  const { data:dues } = await admin.from('supplier_dues').select('amount_due,fine_amount,status').not('status','in','(paid,waived)');
  let dueSum=0,dueCnt=0; for(const d of (dues||[])){ dueCnt++; dueSum+=Number(d.amount_due||0)+Number(d.fine_amount||0); }
  const [pendAll,kyc,refunds,drafts,inq7,q7,sup,cust,sec7]=await Promise.all([
    cntT('agent_actions',(q)=>q.eq('status','pending')),
    cntT('leads',(q)=>q.eq('approval_status','pending')),
    cntT('transactions',(q)=>q.eq('refund_status','requested')),
    cntT('content_drafts',(q)=>q.eq('status','draft')),
    cntT('inquiries',(q)=>q.gte('created_at',since7)),
    cntT('quotes',(q)=>q.gte('created_at',since7)),
    cntT('leads',(q)=>q.eq('permanently_closed',false)),
    cntT('customers'),
    cntT('security_events',(q)=>q.gte('created_at',since7))
  ]);
  return { my_pending_items:mine||[], recent_agent_runs:runs||[], company:{ suppliers:sup, customers:cust, inquiries_7d:inq7, quotes_7d:q7, pending_approvals_all:pendAll, kyc_pending:kyc, refunds_requested:refunds, marketing_drafts:drafts, security_events_7d:sec7, overdue_commissions:{count:dueCnt,total_aed:Math.round(dueSum)} } };
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response(null,{headers:CORS});
  try{
    const body=await req.json().catch(()=>({}));
    // Auth: internal __secret path (agent-to-agent collaboration, e.g. secretary ask_agent) OR admin JWT.
    // Fail-closed: if inbound_secret is missing/empty the internal path can never authenticate.
    let email='';
    const internalSecret=await sec('inbound_secret');
    if(body.__secret && internalSecret && body.__secret===internalSecret){
      email='internal@quotesdone.com';
    } else {
      const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      const { data:{ user } } = await admin.auth.getUser(jwt);
      if(!user||!user.email) return J({error:'unauthorized'},401);
      email=user.email.toLowerCase();
      const al=await sec('admin_emails'); const admins=String(al||'management@quotesdone.com').toLowerCase().split(',').map(s=>s.trim());
      if(!admins.includes(email)) return J({error:'forbidden'},403);
    }
    const key=String(body.agent||''); const msg=String(body.message||'').trim();
    const m=await meta(key); if(!m) return J({error:'unknown agent'},400);
    if(!msg) return J({error:'message required'},400);
    const { data:hist } = await admin.from('agent_chats').select('role,content').eq('agent_key',key).order('id',{ascending:false}).limit(10);
    const history=(hist||[]).reverse().map((h:any)=>({role:h.role,content:h.content}));
    let ctx:any={}; try{ ctx=await context(key); }catch(_e){ ctx={error:'snapshot unavailable'}; }
    const teammates=VALID_AGENTS.filter(a=>a!==key).map(a=>a+' ('+(NAMES[a]||a)+')').join(', ');
    const base='You are '+m.name+' at QuotesDone, a UAE B2B anonymous quotation marketplace. You are a seasoned professional with 10+ years of experience in your field. Answer in your domain using your KNOWLEDGE BASE and the LIVE DATA SNAPSHOT. Be specific, practical and concise. Never invent numbers; if the snapshot lacks something, say so. You advise and prepare work; actions that change data or send messages go to the founder for approval.\n\nTEAMWORK: You work as part of a team and can hand a task to a colleague specialist when it clearly belongs to them. Your colleagues: '+teammates+'. To hand off, AFTER your normal reply to the founder, append on a NEW LINE exactly @@ACTIONS@@ followed by compact JSON: {"handoffs":[{"to":"<agent_key>","title":"<short task title>","details":"<exactly what you need them to do and why>"}]}. Only hand off real, specific, useful tasks (e.g. Collections asking Legal to draft a demand letter for a defaulting supplier). Omit the @@ACTIONS@@ line entirely if there is no handoff. Never mention this mechanism or the word @@ACTIONS@@ in your visible reply.';
    const persona=(m as any).persona?('\n\n'+(m as any).persona):'';
    const kb=await retrieve(msg);
    const sys=base+persona+(await knowledge(key))+kb+'\n\nLIVE DATA SNAPSHOT (read-only, captured just now):\n'+JSON.stringify(ctx).slice(0,9000);
    const rawReply=await llm(sys,[...history,{role:'user',content:msg}],1700)||'I could not reach the AI service just now — please try again in a moment.';
    let [clean,acts]=splitActions(rawReply); let finalReply=clean||rawReply; const notes:string[]=[];
    if(acts&&Array.isArray(acts.handoffs)){
      for(const h of acts.handoffs.slice(0,5)){
        const to=String(h?.to||'').toLowerCase(); if(!VALID_AGENTS.includes(to)||to===key) continue;
        const title=String(h?.title||'task').slice(0,160); const details=String(h?.details||'').slice(0,800);
        try{ await admin.from('agent_actions').insert({agent:to,kind:'handoff',status:'pending',risk:'low',title:('Handoff — '+title).slice(0,200),recommendation:details,detail:{from:key,from_name:m.name,requested_at:new Date().toISOString()},target_table:null}); notes.push('→ Handed to '+(NAMES[to]||to)+': '+title); }catch(_e){}
      }
    }
    if(notes.length) finalReply=finalReply+'\n\n'+notes.join('\n');
    await admin.from('agent_chats').insert([{agent_key:key,role:'user',content:msg,created_by:email},{agent_key:key,role:'assistant',content:finalReply}]);
    if(/\b(remember|always|never|from now on|for future|going forward|note that|our policy|keep in mind|prefer)\b/i.test(msg)){ try{ await admin.from('agent_memory').insert({agent_key:key,kind:'instruction',content:msg.slice(0,600),source:'founder_chat'}); }catch(_e){} }
    try{ const p=learn(key,m.name,msg,finalReply); (globalThis as any).EdgeRuntime?.waitUntil?.(p); }catch(_e){}
    return J({reply:finalReply});
  }catch(e){ return J({error:String((e as Error)?.message||e)},500); }
});
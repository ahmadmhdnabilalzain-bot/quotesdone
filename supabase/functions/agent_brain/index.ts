// agent_brain v17 — EMPLOYEE RUNTIME.
// Change vs v16: agents (especially the Chief of Staff — "the eyes") can now RESEARCH THE INTERNET
// to permanently fill a genuine knowledge gap. When an agent emits a `research` action, we dispatch
// the web-grounded kb_deepen engine to pull real UAE sources for those topics and ingest them into
// the agent's permanent knowledge — so the gap is closed for everyone, once, not re-answered live.
// Change vs v15: retrieve() is now category-scoped for specialist (cat:<slug>) agents — it
// pulls that specialist's OWN deep region of the knowledge base first (the "trigger that
// region of the master's brain" behaviour) and tops up with a small unscoped cross-domain
// pass; functional staff keep the relevance-ranked global pass. Feeds on the kb_deepen corpus.
// Changes vs v14: (1) context comes from fn_agent_context() — the four-layer employee
// assembly (identity+doctrine posture, L1 company, L2 profession, L3 live state, L4
// lint-filtered experience) instead of a flat 26-bullet knowledge dump + raw memory;
// (2) reasoning actually runs OPUS_FIRST (v14's comment claimed Opus but bound Sonnet);
// (3) roster extended: analytics, procurement, secretary, designer; (4) auto-learn is
// lint-gated against policy_rules so poisoned facts can never enter memory again;
// (5) assistant-posture line replaced by the chairman doctrine (default to action within
// authority; gated work is prepared and routed, not abandoned).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, OPUS_FIRST, SONNET_FIRST } from '../_shared/llm.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o:unknown,s=200)=> new Response(JSON.stringify(o),{status:s,headers:{'Content-Type':'application/json',...CORS}});
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
async function cntT(t:string, mod?:(q:any)=>any){ let q=admin.from(t).select('id',{count:'exact',head:true}); if(mod) q=mod(q); const {count}=await q; return count||0; }
// Executive reasoning on Opus 4.8 (strongest), Sonnet 5 as automatic fallback — and this time the code matches the comment.
// 29 Jul 2026: no timeoutMs meant _shared/llm.ts aborted at 30s while ai_gateway runs a 55s wall.
// This walked away from its own answer mid-generation, returned "could not reach the AI service",
// and left the gateway billing for 25 more seconds. An inner caller must outlast the layer it
// depends on. 70s sits above the gateway's 55s wall and below cos_execute's 75s patience.
// TRUNCATION, MEASURED. 53 of the 114 agent_brain calls on production returned output_tokens
// EXACTLY 1700 — the ceiling on the line below and, until 6 Aug 2026, model_policy.agent_reasoning
// itself. An output landing precisely on the ceiling is truncation, not a coincidence. agent_brain
// IS the department specialist: its reply is the deliverable cos_execute stores, reviews and files
// as the company's work, so a cut-off reply is a cut-off work product.
//
// Set above the policy on purpose so ai_gateway's min(caller, policy) always yields the policy;
// deleting it is worse, because llm.ts falls back to `def.max ?? 700`. The policy moved 1700 -> 4000
// on both projects in the same change. `llmFast` below deliberately keeps max:160 against
// memory_retrieval's 400 — measured 1-93 output tokens, nothing near its ceiling.
const llm = makeLlm(OPUS_FIRST, { max: 8000, timeoutMs: 70000 });
async function llmFast(sys:string, user:string){ try{ const secret=await sec('cred_fn_agent_brain'); if(!secret) return ''; const r=await fetch(SUPA+'/functions/v1/ai_gateway',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:secret,fn:'agent_brain',task_class:'memory_retrieval',sys,input:user,max:160,temperature:0}),signal:AbortSignal.timeout(20000)}); const j=await r.json(); return j?.content||''; }catch(_e){ return ''; } }

// Lint gate: a candidate memory that matches any active forbidden-language rule is refused.
async function lintClean(text:string):Promise<boolean>{
  try{
    const { data:rules } = await admin.from('policy_rules').select('forbid_regex').eq('active',true);
    for(const r of (rules||[])){
      try{ if(new RegExp(String(r.forbid_regex),'i').test(text)) return false; }catch(_e){}
    }
    return true;
  }catch(_e){ return true; }
}

// AUTO-LEARN: after a chat, capture at most one durable new fact (background, lint-gated).
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
      if(await lintClean(out)){
        await admin.from('agent_memory').insert({agent_key:key,kind:'learned',content:out.slice(0,360),source:'auto_chat'});
      } else {
        await admin.from('security_events').insert({kind:'memory_lint_block',severity:'low',source:'agent_brain',subject:key,detail:{blocked:out.slice(0,300)}}).then(()=>{},()=>{});
      }
    }
  }catch(_e){}
}

const NAMES:Record<string,string>={brief:'Daily Brief / Chief of Staff',it:'IT / Uptime',security:'Security Engineer',docs:'Document Controller',onboarding:'Onboarding / KYC',followup:'Follow-up',collections:'Collections Accountant',bd:'BD Representative',bookkeeper:'Bookkeeper',cfo:'CFO',legal:'Legal Counsel',marketing:'Marketing',analytics:'Head of Analytics & Intelligence',procurement:'Head of Marketplace Operations',secretary:'Executive Secretary',designer:'Designer'};
const VALID_AGENTS=['legal','collections','cfo','bookkeeper','security','it','onboarding','docs','followup','bd','marketing','brief','analytics','procurement','secretary','designer'];
function splitActions(s:string):[string, any]{ const i=s.indexOf('@@ACTIONS@@'); if(i<0) return [s,null]; const clean=s.slice(0,i).trim(); const tail=s.slice(i+11); const mm=tail.match(/\{[\s\S]*\}/); let a:any=null; if(mm){ try{ a=JSON.parse(mm[0]); }catch(_e){} } return [clean,a]; }

async function meta(key:string){
  if(NAMES[key]) return { name:NAMES[key] };
  if(key.startsWith('cat:')){ const { data:ca }=await admin.from('category_agents').select('name,persona').eq('slug',key.slice(4)).maybeSingle(); if(ca) return { name:ca.name+' Sales', persona: ca.persona }; }
  const { data:oa } = await admin.from('org_agents').select('role').eq('agent_key',key).eq('active',true).maybeSingle();
  if(oa) return { name: oa.role || key };
  return null;
}
// FOUR-LAYER EMPLOYEE CONTEXT (identity+posture, company, profession, live state, experience),
// PLUS layer 2b: the employee's own department reference library, retrieved for this question.
// dept_library carries 1,456 rows (legal 451, procurement 361, it 318, finance 290, company 36)
// and fn_dept_library_search had zero callers anywhere — complete, indexed and unread. Passing the
// message is what turns it from a dump into retrieval: fn_agent_context emits the section only
// when a query arrives, so the twelve other call sites are unchanged until they pass one too.
async function layeredContext(key:string, msg:string){
  try{
    const { data, error } = await admin.rpc('fn_agent_context', { p_agent_key: key, p_max_chars: 24000, p_query: msg });
    if(error || !data) return '';
    return '\n\n'+String(data);
  }catch(_e){ return ''; }
}
// Recent founder instructions (explicit "remember/always/never" captures), lint-filtered.
async function instructions(key:string){
  try{
    const { data:ins } = await admin.from('agent_memory').select('content').eq('agent_key',key).eq('kind','instruction').order('id',{ascending:false}).limit(5);
    const rows=[] as string[];
    for(const m of (ins||[])){ if(await lintClean(String(m.content))) rows.push('- '+m.content); }
    return rows.length ? '\n\nSTANDING FOUNDER INSTRUCTIONS (newest first):\n'+rows.join('\n') : '';
  }catch(_e){ return ''; }
}
// Semantic + keyword retrieval over the deep knowledge corpus (kb_chunks). For a category
// specialist (cat:<slug>) we scope to that slug FIRST — this is the "trigger that region of
// the master's brain" behaviour: a fit-out question pulls the fit-out deep briefs, not the
// whole company. We top up with an unscoped pass so cross-domain facts still surface.
async function retrieve(key:string, msg:string){
  try{
    const secret=await sec('cred_fn_agent_brain'); if(!secret) return '';
    const cat = key.startsWith('cat:') ? key.slice(4) : null;
    const call = async (category:string|null, k:number) => {
      try{
        const r=await fetch(SUPA+'/functions/v1/kb_search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:secret,query:msg,k,...(category?{category}:{})})});
        const j=await r.json(); return (j&&Array.isArray(j.results))?j.results:[];
      }catch(_e){ return []; }
    };
    let rows:any[] = [];
    if(cat){
      const scoped = await call(cat, 8);            // the specialist's own deep region first
      const wide   = await call(null, 4);           // + a few cross-domain hits
      const seen = new Set<number>(); rows = [];
      for(const x of [...scoped, ...wide]){ if(x && !seen.has(x.id)){ seen.add(x.id); rows.push(x); } }
    } else {
      rows = await call(null, 8);                    // functional staff: relevance-ranked, RRF surfaces their own deep chunks
    }
    if(!rows.length) return '';
    return '\n\nRETRIEVED REFERENCE KNOWLEDGE (semantic + keyword matches from the company knowledge base — UAE codes, standards, regulations, materials and internal know-how relevant to this question; use it to VERIFY, cite the reference in [brackets] when you use it):\n'+rows.slice(0,10).map((x:any)=>'- ['+(x.citation||x.category||'ref')+'] '+String(x.snippet||'').replace(/\s+/g,' ').slice(0,400)).join('\n');
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
  return { my_pending_items:mine||[], recent_agent_runs:runs||[], company:{ suppliers:sup, customers:cust, inquiries_7d:inq7, quotes_7d:q7, pending_approvals_all:pendAll, kyc_pending:kyc, refunds_requested:refunds, marketing_drafts:drafts, security_events_7d:sec7, supplier_dues_outstanding:{count:dueCnt,total_aed:Math.round(dueSum)} } };
}

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response(null,{headers:CORS});
  try{
    const body=await req.json().catch(()=>({}));
    // Auth: internal __secret path (agent-to-agent collaboration) OR admin JWT. Fail-closed.
    let email='';
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called. The
    // `body.__secret &&` short-circuit is kept deliberately, so ordinary admin-JWT traffic does
    // not pay for a verifier round trip.
    if(body.__secret && (await requireInternal(admin, body.__secret, 'agent_brain')).ok){
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
    const base='You are '+m.name+' at QuotesDone, a UAE B2B anonymous quotation marketplace — a senior executive employee, not an assistant. Your full employment context follows (identity, company canon, your professional expertise, live operational state, organizational experience) — it governs how you think and act. DOCTRINE: default to action within your delegated authority — complete work and report results; prepare and route gated work (money, publishing, legal action, security) for approval rather than abandoning it; never ask permission you already have. Be specific, practical and concise. Never invent numbers — operational figures come only from the LIVE OPERATIONAL STATE and LIVE DATA SNAPSHOT.\n\nTEAMWORK: You can hand a task to a colleague specialist when it clearly belongs to them. Your colleagues: '+teammates+'.\n\nKNOWLEDGE (your window to the world): if answering this well needs domain knowledge you do not have, you may RESEARCH THE INTERNET to fill the gap permanently — real UAE sources are pulled, verified and saved into the relevant specialist\'s knowledge so it is there for everyone next time. Use this for genuine gaps in durable domain knowledge (materials, standards, authorities, methods, market facts) — NOT for live/one-off data. Prefer answering from what you already know; reach for research only when there is a real gap worth closing.\n\nTo act, AFTER your normal reply append on a NEW LINE exactly @@ACTIONS@@ followed by compact JSON. You may include either or both keys: {"handoffs":[{"to":"<agent_key>","title":"<short task title>","details":"<what to do and why>"}],"research":[{"agent":"<specialist_slug_or_your_own_key>","topics":["<specific sub-topic to research>","<another>"]}]}. Only request real, specific, useful work. Omit the @@ACTIONS@@ line entirely if there is nothing to do. Never mention this mechanism or the word @@ACTIONS@@ in your visible reply.';
    const persona=(m as any).persona?('\n\n'+(m as any).persona):'';
    const [layered, instr, kb] = await Promise.all([layeredContext(key, msg), instructions(key), retrieve(key, msg)]);
    const sys=base+persona+layered+instr+kb+'\n\nLIVE DATA SNAPSHOT (read-only, captured just now):\n'+JSON.stringify(ctx).slice(0,9000);
    const rawReply=await llm(sys,[...history,{role:'user',content:msg}],8000)||'I could not reach the AI service just now — please try again in a moment.';
    let [clean,acts]=splitActions(rawReply); let finalReply=clean||rawReply; const notes:string[]=[];
    if(acts&&Array.isArray(acts.handoffs)){
      for(const h of acts.handoffs.slice(0,5)){
        const to=String(h?.to||'').toLowerCase(); if(!VALID_AGENTS.includes(to)||to===key) continue;
        const title=String(h?.title||'task').slice(0,160); const details=String(h?.details||'').slice(0,800);
        try{ await admin.from('agent_actions').insert({agent:to,kind:'handoff',status:'pending',risk:'low',title:('Handoff — '+title).slice(0,200),recommendation:details,detail:{from:key,from_name:m.name,requested_at:new Date().toISOString()},target_table:null}); notes.push('→ Handed to '+(NAMES[to]||to)+': '+title); }catch(_e){}
      }
    }
    // RESEARCH: dispatch the web-grounded kb_deepen engine to pull real sources and fill a knowledge gap.
    if(acts&&Array.isArray(acts.research)){
      const internal=await sec('cred_fn_agent_brain');
      for(const rq of acts.research.slice(0,3)){
        const tgt=String(rq?.agent||key).replace(/^cat:/,'').trim();
        const topics=(Array.isArray(rq?.topics)?rq.topics:[]).map((t:any)=>String(t).slice(0,80)).filter(Boolean).slice(0,4);
        if(!tgt||!topics.length||!internal) continue;
        try{
          const rp=fetch(SUPA+'/functions/v1/kb_deepen',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({__secret:internal,agent:tgt,topics_list:topics,topics:topics.length})}).catch(()=>{});
          try{ (globalThis as any).EdgeRuntime?.waitUntil?.(rp); }catch(_e){}
          notes.push('🔎 Researching to fill knowledge ('+tgt+'): '+topics.join(', '));
        }catch(_e){}
      }
    }
    if(notes.length) finalReply=finalReply+'\n\n'+notes.join('\n');
    await admin.from('agent_chats').insert([{agent_key:key,role:'user',content:msg,created_by:email},{agent_key:key,role:'assistant',content:finalReply}]);
    if(/\b(remember|always|never|from now on|for future|going forward|note that|our policy|keep in mind|prefer)\b/i.test(msg)){ try{ if(await lintClean(msg)){ await admin.from('agent_memory').insert({agent_key:key,kind:'instruction',content:msg.slice(0,600),source:'founder_chat'}); } }catch(_e){} }
    try{ const p=learn(key,m.name,msg,finalReply); (globalThis as any).EdgeRuntime?.waitUntil?.(p); }catch(_e){}
    return J({reply:finalReply});
  }catch(e){ return J({error:String((e as Error)?.message||e)},500); }
});

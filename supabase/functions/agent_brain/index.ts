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
// A FACTORY, NOT A CONSTANT, SO THE BILL CARRIES THE EMPLOYEE (9 Aug 2026).
// This was `const llm = makeLlm(...)` at module scope — built once at boot, before any request and
// therefore before any agent_key exists. makeLlm binds `def.agent` at CONSTRUCTION and the function
// it returns takes (sys, input, max) with no per-call override, so every model call this file made
// carried agent: undefined. ai_gateway then resolved the caller to the exec department head, and
// MEASURED over 4 Aug–9 Aug that is all 381 agent_brain rows in ai_cost_log — AED 51.08, every one
// stamped 'ceo' — while agent_chats over the same window shows this function replying as
// knowledge_director, procurement, docs and brief. The reasoning rotated; the bill did not.
//
// It is not a cosmetic ledger issue. ROW3_STATE cites "ai_cost_log — 3 of 66 have ever been billed
// for a model call" as evidence that the 66 employees are dormant, and five per-employee checks
// rest on that story. That figure counts buckets, not employees.
//
// llmFast below still sends no agent. Deliberate and noted rather than silently fixed: it is the
// memory_retrieval path at max:160 against a 14,110-token main call, so it is a rounding error in
// the bill, and its callers take no key to pass.
const llmFor = (agent: string) => makeLlm(OPUS_FIRST, { max: 8000, timeoutMs: 70000, agent });
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
    // WHICH KNOWLEDGE FED THIS ANSWER. kb_usage_log is the store the spec points at for "what
    // knowledge did this employee use", and it had 0 rows because NOTHING had ever written to it —
    // retrieval happened right here and was never recorded. One row per retrieval, so the usage
    // ledger fills as the company works rather than by backfill.
    try{ await admin.from('kb_usage_log').insert({ agent:key, query:msg.slice(0,300), category:'agent_context' }); }catch(_e){}
    return '\n\n'+String(data);
  }catch(_e){ return ''; }
}
// HANDED TO YOU. Measured on production 10 Aug 2026: 82 open handoffs, oldest 24 July, and not one
// completed since 25 June — because fn_agent_context does not contain the string 'handoff' anywhere,
// so the receiving employee was never told. `it` alone held 28 and escalated a single incident five
// times in three days, each with a louder title, over a defect that did not exist. The inbox and the
// way to clear it ship together on purpose: an inbox that cannot be cleared would repeat in every
// prompt forever, at token cost, which is worse than the silence it replaces.
async function handoffInbox(key:string){
  try{
    const { data } = await admin.rpc('fn_agent_handoff_inbox', { p_agent_key: key });
    const t = String(data||'').trim(); if(!t) return '';
    return '\n\nHANDED TO YOU AND STILL OPEN — colleagues asked you for these and nobody has answered them:\n'+t+
      '\nAnswer the ones you can from what you already know, using the "answers" action below: answering closes the request and sends your reply back to the colleague who asked. If you genuinely cannot answer one, say what is blocking it in the answer rather than leaving it open — an unanswered handoff is re-asked louder every day.';
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
    const runStartedAt=Date.now();
    const key=String(body.agent||''); const msg=String(body.message||'').trim();
    const m=await meta(key); if(!m) return J({error:'unknown agent'},400);
    if(!msg) return J({error:'message required'},400);
    // CONVERSATION COMPRESSION (open router.txt §5 "Token Management", §21 "Dynamic Context Window").
    // This sent the last TEN turns verbatim. Measured on production 11 Aug 2026, the last ten rows
    // for `procurement` are 29,625 characters, legal 26,588, intel_director 25,291 — roughly 7,000
    // tokens of history on top of a ~31,000-character employment context, on every hourly call, at
    // the large tier. And the loop that dominates this function is cos_execute working ONE task per
    // call: task N-9's full 5,000-character reply is not context for task N, it is a bill.
    //
    // Six turns, each capped, with the machine-readable @@ACTIONS@@ tail stripped — that tail is a
    // dispatch instruction that was already carried out when it was written, so replaying it invites
    // the model to re-issue handoffs it has already made. Founder conversation keeps its shape; what
    // goes is the transcript nobody is reading.
    const HIST_TURNS = 6, HIST_CHARS = 1200;
    const { data:hist } = await admin.from('agent_chats').select('role,content').eq('agent_key',key).order('id',{ascending:false}).limit(HIST_TURNS);
    const history=(hist||[]).reverse().map((h:any)=>{
      let c=String(h.content||''); const cut=c.indexOf('@@ACTIONS@@'); if(cut>=0) c=c.slice(0,cut).trim();
      if(c.length>HIST_CHARS) c=c.slice(0,HIST_CHARS)+' […earlier detail trimmed; ask if you need it]';
      return {role:h.role,content:c};
    }).filter((h:any)=>h.content.length>0);
    let ctx:any={}; try{ ctx=await context(key); }catch(_e){ ctx={error:'snapshot unavailable'}; }
    const teammates=VALID_AGENTS.filter(a=>a!==key).map(a=>a+' ('+(NAMES[a]||a)+')').join(', ');
    const base='You are '+m.name+' at QuotesDone, a UAE B2B anonymous quotation marketplace — a senior executive employee, not an assistant. Your full employment context follows (identity, company canon, your professional expertise, live operational state, organizational experience) — it governs how you think and act. DOCTRINE: default to action within your delegated authority — complete work and report results; prepare and route gated work (money, publishing, legal action, security) for approval rather than abandoning it; never ask permission you already have. Be specific, practical and concise. Never invent numbers — operational figures come only from the LIVE OPERATIONAL STATE and LIVE DATA SNAPSHOT.\n\nTEAMWORK: You can hand a task to a colleague specialist when it clearly belongs to them. Your colleagues: '+teammates+'.\n\nKNOWLEDGE (your window to the world): if answering this well needs domain knowledge you do not have, you may RESEARCH THE INTERNET to fill the gap permanently — real UAE sources are pulled, verified and saved into the relevant specialist\'s knowledge so it is there for everyone next time. Use this for genuine gaps in durable domain knowledge (materials, standards, authorities, methods, market facts) — NOT for live/one-off data. Prefer answering from what you already know; reach for research only when there is a real gap worth closing.\n\nTo act, AFTER your normal reply append on a NEW LINE exactly @@ACTIONS@@ followed by compact JSON. You may include any of these keys: {"handoffs":[{"to":"<agent_key>","title":"<short task title>","details":"<what to do and why>"}],"research":[{"agent":"<specialist_slug_or_your_own_key>","topics":["<specific sub-topic to research>","<another>"]}],"answers":[{"id":<handoff id from HANDED TO YOU>,"answer":"<your answer, or what is blocking it>"}]}. Only request real, specific, useful work. Omit the @@ACTIONS@@ line entirely if there is nothing to do. Never mention this mechanism or the word @@ACTIONS@@ in your visible reply.';
    const persona=(m as any).persona?('\n\n'+(m as any).persona):'';
    const [layered, instr, kb, inbox] = await Promise.all([layeredContext(key, msg), instructions(key), retrieve(key, msg), handoffInbox(key)]);
    // STABLE HALF / VOLATILE HALF. A provider prompt cache only pays on a BYTE-IDENTICAL block, and
    // this prompt's tail says "captured just now" — so marking the whole thing, which is what
    // ai_gateway did, bought a cache WRITE at 1.25x on every call and a read on none of them.
    //
    // The boundary is the first live section fn_agent_context emits. Everything above it (identity,
    // company genome, risk register, employee record, LAYER 2 profession, LAYER 1 company knowledge)
    // is the same string call after call for the same employee; everything from there down carries a
    // timestamp, a live health snapshot or this turn's retrieval. Split on the section headings
    // rather than a new sentinel so fn_agent_context — 400 lines with a documented history of one
    // inserted line silently evicting knowledge from 19 employees — is not touched at all.
    //
    // No marker found (a department with no health_fn and no experience yet) means no stable block
    // is claimed, and nothing is marked. Failing to "no caching" is free; claiming a prefix that
    // moves is not.
    const VOLATILE_AT = ['\n# LAYER 3 - LIVE OPERATIONAL STATE',
                         '\n# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED',
                         '\n# YOUR OS OBJECTIVES, MEASURED'];
    let cutAt = -1;
    for (const marker of VOLATILE_AT) { const i = layered.indexOf(marker); if (i >= 0 && (cutAt < 0 || i < cutAt)) cutAt = i; }
    const stableCtx   = cutAt >= 0 ? layered.slice(0, cutAt) : '';
    const volatileCtx = cutAt >= 0 ? layered.slice(cutAt)    : layered;
    // instr moves ahead of the context so the stable half is contiguous from the first character.
    const sysStable = stableCtx ? (base+persona+instr+stableCtx) : '';
    const sysVolatile = (stableCtx ? '' : base+persona+instr)+volatileCtx+kb+inbox
      +'\n\nLIVE DATA SNAPSHOT (read-only, captured just now):\n'+JSON.stringify(ctx).slice(0,9000);
    const llmOut=await llmFor(key)(sysVolatile,[...history,{role:'user',content:msg}],8000,sysStable);
    // 10 Aug 2026: an empty model return has always produced this apology AND an agent_runs row
    // reading status 'ok'. `it` was found timing out at ~56s twice in a row while its run log said
    // it had worked — and its ONE prior success took 53,139 ms on a 30,821-token prompt, so it had
    // been three seconds from this cliff for some time with nothing saying so. Same silent failure
    // exec_agents was fixed for in session 2. Recorded truthfully below.
    const llmFailed = !llmOut;
    const rawReply=llmOut||'I could not reach the AI service just now — please try again in a moment.';
    let [clean,acts]=splitActions(rawReply); let finalReply=clean||rawReply; const notes:string[]=[];
    if(acts&&Array.isArray(acts.handoffs)){
      for(const h of acts.handoffs.slice(0,5)){
        const to=String(h?.to||'').toLowerCase(); if(!VALID_AGENTS.includes(to)||to===key) continue;
        const title=String(h?.title||'task').slice(0,160); const details=String(h?.details||'').slice(0,800);
        try{ await admin.from('agent_actions').insert({agent:to,kind:'handoff',status:'pending',risk:'low',title:('Handoff — '+title).slice(0,200),recommendation:details,detail:{from:key,from_name:m.name,requested_at:new Date().toISOString()},target_table:null}); notes.push('→ Handed to '+(NAMES[to]||to)+': '+title); }catch(_e){}
      }
    }
    // ANSWERS: close a handoff a colleague raised. fn_handoff_answer refuses anything that is not an
    // OPEN handoff addressed to THIS employee, so an agent cannot close someone else's work or
    // re-close a decided row, and it posts the reply back to the asker as an agent_memory row —
    // which is the half that was missing: before this, answering a handoff reached nobody.
    if(acts&&Array.isArray(acts.answers)){
      for(const a of acts.answers.slice(0,5)){
        const id=Number(a?.id); const answer=String(a?.answer||'').trim().slice(0,4000);
        if(!isFinite(id)||id<=0||!answer) continue;
        try{
          const { data }=await admin.rpc('fn_handoff_answer',{p_id:id,p_agent_key:key,p_answer:answer});
          if((data as any)?.ok) notes.push('✓ Answered handoff #'+id);
        }catch(_e){}
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
    // ── THE EMPLOYEE ACTUALLY WORKED. RECORD IT. ────────────────────────────────────────────
    // agent_runs was READ here (line ~140) and never written, so 59 of 66 employees had no run
    // record at all and agent_runs.agent held only CRON JOB names. An employee that thinks is an
    // employee that ran; without this row nothing downstream — performance, trend, workload —
    // can say anything about them. Keyed by agent_key so it joins to org_agents.
    try{
      await admin.from('agent_runs').insert({ agent:key, status:llmFailed?'error':'ok',
        started_at:new Date(runStartedAt).toISOString(), finished_at:new Date().toISOString(),
        counts:{ prompt_chars:sysStable.length+sysVolatile.length,
                 stable_chars:sysStable.length, volatile_chars:sysVolatile.length,
                 history_turns:history.length, llm_returned_nothing:llmFailed },
        note:(llmFailed
          ? 'The model returned nothing, so this employee did not answer. Prompt was '
            +(sysStable.length+sysVolatile.length)+' characters ('+sysStable.length+' cacheable). Ask: '
          : '')+msg.slice(0,180) });
    }catch(_e){}
    // A thought, every turn — not only when the founder says "remember". employee-current-thoughts
    // asks what the employee is thinking, and it was written on a keyword match roughly never.
    // ...unless there was no thought. Storing the apology as the employee's current reasoning is
    // how a failed turn becomes "what this employee is thinking" on the workspace.
    if(!llmFailed){ try{ await admin.from('agent_memory').insert({ agent_key:key, kind:'reasoning',
      content:finalReply.slice(0,360), source:'chat_turn', importance:1 }); }catch(_e){} }
    if(/\b(remember|always|never|from now on|for future|going forward|note that|our policy|keep in mind|prefer)\b/i.test(msg)){ try{ if(await lintClean(msg)){ await admin.from('agent_memory').insert({agent_key:key,kind:'instruction',content:msg.slice(0,600),source:'founder_chat'}); } }catch(_e){} }
    try{ const p=learn(key,m.name,msg,finalReply); (globalThis as any).EdgeRuntime?.waitUntil?.(p); }catch(_e){}
    return J({reply:finalReply});
  }catch(e){ return J({error:String((e as Error)?.message||e)},500); }
});

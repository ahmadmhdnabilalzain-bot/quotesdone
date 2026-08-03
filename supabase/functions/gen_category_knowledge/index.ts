import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'gen_category_knowledge', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
let LLM_CALLS=0, LLM_FAILS=0, SHORT_OUTPUTS=0, INSERT_FAILS=0; let LAST_ERR='';
const llmShared = makeLlm(SONNET_FIRST, { max: 700, temperature: 0.3 });
const TOPIC='Field expertise — UAE codes, standards & specs';
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function llm(_key:string, sys:string, user:string){ LLM_CALLS++; const c=await llmShared(sys,user); if(!c){ LLM_FAILS++; LAST_ERR='openrouter call failed or returned no content'; return ''; } return c; }

Deno.serve(async (req)=>{
 try{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  const __exp = await sec('inbound_secret');
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, b?.__secret, 'gen_category_knowledge');
  if(!__auth.ok) { await logRun('error',{generated:0},'call rejected: wrong or missing inbound secret; no category knowledge generated'); return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}}); }
  const ork=await sec('openrouter_api_key'); if(!ork) { await logRun('error',{generated:0},'openrouter_api_key missing from app_secrets: no category knowledge generated this run, category agent field knowledge is stale'); return new Response(JSON.stringify({error:'no key'}),{status:200,headers:{'Content-Type':'application/json'}}); }
  const limit=Math.max(1,Math.min(24,Number(b.limit)||8));
  const force=b.force===true;
  const staleDays=Math.max(1,Number(b.stale_days)||14);
  const targetSlug=(typeof b.slug==='string' && b.slug.trim()) ? b.slug.trim() : null;
  // existing field-knowledge rows + freshness (so we can REFRESH the stalest, not just fill gaps)
  const { data: have } = await admin.from('agent_knowledge').select('agent_key,updated_at').like('agent_key','cat:%').eq('topic',TOPIC);
  const fresh=new Map<string,number>((have||[]).map((r:any)=>[r.agent_key, r.updated_at? Date.parse(r.updated_at):0]));
  const { data: cats } = await admin.from('category_agents').select('slug,name').eq('active',true);
  let pool:any[];
  if(targetSlug){
    pool=(cats||[]).filter((c:any)=> c.slug===targetSlug);
  } else {
    const staleBefore=Date.now()-staleDays*86400000;
    const withMeta=(cats||[]).map((c:any)=>({ ...c, has:fresh.has('cat:'+c.slug), age:fresh.get('cat:'+c.slug)??0 }));
    const missing=withMeta.filter((c:any)=> !c.has);
    const stale=withMeta.filter((c:any)=> c.has && (force || c.age < staleBefore)).sort((a:any,b:any)=> a.age - b.age);
    pool=[...missing, ...stale].slice(0,limit);
  }
  const results = await Promise.all(pool.map(async (c:any)=>{
    const sys='You are compiling the FIELD KNOWLEDGE BASE for an AI sales specialist agent that owns the "'+c.name+'" trade category on QuotesDone, a UAE B2B sourcing marketplace (focus Dubai). This text is injected directly into the agent\'s brain so it can talk to UAE customers and suppliers as a genuine expert in '+c.name+' and qualify jobs precisely. Write a dense, ACCURATE domain brief of 230-340 words covering, specifically for '+c.name+' in the UAE: (1) GOVERNING AUTHORITY & APPROVALS — the actual UAE regulator(s)/permits/NOC steps that apply to THIS trade (examples of the kind of bodies, only where they truly apply: Dubai Civil Defence (DCD) and the UAE Fire and Life Safety Code of Practice for fire/life-safety; SIRA — Security Industry Regulatory Agency — and Dubai Police for CCTV/security; DEWA for electrical connection and Shams Dubai net-metering for solar; Dubai Municipality; Trakhees for ports/free-zone areas; ESMA/Emirates Conformity; RTA; Dubai Development Authority). (2) STANDARDS — the technical standards that genuinely apply (e.g. NFPA, IEC, EN, BS, ISO, ASHRAE, ASTM, DEWA regulations) — give specific numbers ONLY when you are confident they are correct; otherwise name the standard without a number. (3) SCOPE & SPECS — the core components, materials, equipment, ratings/capacities and technical terms that buyers and suppliers actually discuss. (4) PRICE DRIVERS. (5) COMPLIANCE PITFALLS / RED FLAGS and the sharp qualifying questions the agent should ask a customer. Be concrete and UAE-specific. HARD RULE: never invent code numbers, authority names, retention periods or figures — if unsure of an exact number, refer to the requirement by name without a number rather than guessing. Output ONLY the knowledge-brief text, no preamble or headings list.';
    const user='Trade category: '+c.name+' (slug: '+c.slug+'). Market: United Arab Emirates (focus Dubai). Write its expert field knowledge base now.';
    const text=(await llm(ork,sys,user)).trim();
    if(text && text.length>120){
      await admin.from('agent_knowledge').delete().eq('agent_key','cat:'+c.slug).eq('topic',TOPIC);
      const ins=await admin.from('agent_knowledge').insert({agent_key:'cat:'+c.slug,topic:TOPIC,content:text.slice(0,4000),priority:8});
      if(ins && (ins as any).error){ INSERT_FAILS++; LAST_ERR='agent_knowledge insert failed for cat:'+c.slug+': '+((ins as any).error?.message||''); }
      return 1;
    }
    SHORT_OUTPUTS++;
    return 0;
  }));
  const done=results.reduce((a:number,x:number)=>a+x,0);
  const { data: nowHave } = await admin.from('agent_knowledge').select('agent_key').like('agent_key','cat:%').eq('topic',TOPIC);
  const total=(cats||[]).length; const covered=(nowHave||[]).length;
  const attempted=pool.length;
  let note:string;
  if(attempted===0){ note='no categories were due for field knowledge this run; nothing generated and nothing failed'; }
  else if(done===0){ note='NO category knowledge generated this run despite '+attempted+' categories attempted — the model call failed or returned unusable output every time; category agent field knowledge is stale and those agents will talk to UAE customers without trade expertise'; }
  else if(done<attempted){ note='partial run: generated field knowledge for '+done+' of '+attempted+' categories; '+(attempted-done)+' produced nothing usable from the model and remain without trade expertise'; }
  else { note='generated field knowledge for all '+done+' attempted categories; '+(total-covered)+' categories still uncovered overall'; }
  if(INSERT_FAILS>0) note+=' | '+INSERT_FAILS+' knowledge row(s) failed to save, so that content was generated but lost';
  if(LAST_ERR) note+=' | last error: '+LAST_ERR;
  const bad = INSERT_FAILS>0 || (attempted>0 && done===0);
  await logRun(bad?'error':'ok',{generated:done,attempted,covered,total,remaining:total-covered,llm_calls:LLM_CALLS,llm_failures:LLM_FAILS,unusable_outputs:SHORT_OUTPUTS,insert_failures:INSERT_FAILS},note);
  return new Response(JSON.stringify({ok:true,generated:done,covered,total,remaining:total-covered}),{headers:{'Content-Type':'application/json'}});
 }catch(e){ await logRun('error',{generated:0,llm_calls:LLM_CALLS,llm_failures:LLM_FAILS},'gen_category_knowledge crashed before completing; no category knowledge generated this run: '+String(e)); throw e; }
});
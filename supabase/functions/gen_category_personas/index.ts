import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'gen_category_personas', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
let LLM_CALLS=0, LLM_FAILS=0, SHORT_OUTPUTS=0, UPDATE_FAILS=0; let LAST_ERR='';
// Anthropic-only per standard: Sonnet 5 primary, Opus 4.8 fallback.
const llmShared = makeLlm(SONNET_FIRST, { max: 420, temperature: 0.4 });
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
  const __auth = await requireInternal(admin, b?.__secret, 'gen_category_personas');
  if(!__auth.ok) { await logRun('error',{generated:0},'call rejected: wrong or missing inbound secret; no category personas generated'); return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}}); }
  const ork=await sec('openrouter_api_key'); if(!ork) { await logRun('error',{generated:0},'openrouter_api_key missing from app_secrets: no category personas generated this run, category sales agents remain without a persona and cannot work their inquiries'); return new Response(JSON.stringify({error:'no key'}),{status:200,headers:{'Content-Type':'application/json'}}); }
  const limit=Math.max(1,Math.min(24,Number(b.limit)||8));
  const force=b.force===true;
  let q=admin.from('category_agents').select('slug,name').eq('active',true);
  if(!force) q=q.is('persona',null);
  const { data: rows } = await q.limit(limit);
  const results = await Promise.all((rows||[]).map(async (c:any)=>{
    const sys='You write the persona/charter for an autonomous SALES specialist agent inside QuotesDone, a UAE B2B "anonymous quotation" marketplace where customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small fee to reveal the supplier they choose. This agent owns ONE trade category and works to convert that category\'s inquiries into completed deals. Write a tight second-person persona ("You are the ... specialist") of 70-110 words that: (1) names the trade and the agent\'s goal (turn '+c.name+' inquiries into reveals/deals), (2) shows real domain fluency for THIS trade in the UAE — typical scope, what drives price, common buyer concerns, materials/standards, seasonality or compliance quirks (e.g. Civil Defence, municipality, SIRA, DEWA where relevant), (3) lists its levers: nudge customers who have quotes to reveal, flag supply gaps where no suppliers matched, surface hot leads. Be genuinely knowledgeable and specific to '+c.name+' in the UAE — not generic. No preamble, output the persona text only.';
    const user='Trade category: '+c.name+' (slug: '+c.slug+'). Market: United Arab Emirates. Write its expert sales-agent persona now.';
    const text=(await llm(ork,sys,user)).trim();
    if(text && text.length>60){ const upd=await admin.from('category_agents').update({persona:text.slice(0,2000)}).eq('slug',c.slug); if(upd && (upd as any).error){ UPDATE_FAILS++; LAST_ERR='persona update failed for '+c.slug+': '+((upd as any).error?.message||''); } return 1; }
    SHORT_OUTPUTS++;
    return 0;
  }));
  const done=results.reduce((a:number,x:number)=>a+x,0);
  const { count: remaining } = await admin.from('category_agents').select('slug',{count:'exact',head:true}).is('persona',null).eq('active',true);
  const attempted=(rows||[]).length;
  let note:string;
  if(attempted===0){ note='no active categories were missing a persona this run; nothing generated and nothing failed'; }
  else if(done===0){ note='NO category personas generated this run despite '+attempted+' categories attempted — the model call failed or returned unusable output every time; those category sales agents still have no persona and will not work their inquiries'; }
  else if(done<attempted){ note='partial run: wrote personas for '+done+' of '+attempted+' categories; '+(attempted-done)+' produced nothing usable from the model and still have no persona'; }
  else { note='wrote personas for all '+done+' attempted categories; '+(remaining||0)+' active categories still have no persona'; }
  if(UPDATE_FAILS>0) note+=' | '+UPDATE_FAILS+' persona(s) were generated but failed to save to category_agents';
  if(LAST_ERR) note+=' | last error: '+LAST_ERR;
  const bad = UPDATE_FAILS>0 || (attempted>0 && done===0);
  await logRun(bad?'error':'ok',{generated:done,attempted,remaining:remaining||0,llm_calls:LLM_CALLS,llm_failures:LLM_FAILS,unusable_outputs:SHORT_OUTPUTS,update_failures:UPDATE_FAILS},note);
  return new Response(JSON.stringify({ok:true,generated:done,remaining:remaining||0}),{headers:{'Content-Type':'application/json'}});
 }catch(e){ await logRun('error',{generated:0,llm_calls:LLM_CALLS,llm_failures:LLM_FAILS},'gen_category_personas crashed before completing; no personas generated this run: '+String(e)); throw e; }
});
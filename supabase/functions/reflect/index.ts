import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
const llm = makeLlm(SONNET_FIRST, { max: 500 });
const RUNMAP:Record<string,string>={it:'it_health',security:'security',collections:'collections',docs:'docs',onboarding:'onboarding',followup:'followup',bd:'bd_outreach',marketing:'marketing',brief:'brief',cfo:'finance',bookkeeper:'finance',legal:'legal_review'};
const AGENTS=['legal','collections','cfo','bookkeeper','security','it','onboarding','docs','followup','bd','marketing','brief'];

Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  if(b.__secret!==(await sec('inbound_secret'))) return new Response(JSON.stringify({error:'forbidden'}),{status:403,headers:{'Content-Type':'application/json'}});
  const started=new Date().toISOString();
  const ork=await sec('openrouter_api_key'); if(!ork) return new Response(JSON.stringify({error:'no key'}),{status:200,headers:{'Content-Type':'application/json'}});
  const since=new Date(Date.now()-14*864e5).toISOString();
  let added=0, processed=0;
  for(const key of AGENTS){
    try{
      const { data:acts } = await admin.from('agent_actions').select('kind,title,status,decided_by').eq('agent',key).gte('created_at',since).limit(40);
      const runName=RUNMAP[key]; let runs:any[]=[];
      if(runName){ const { data:r } = await admin.from('agent_runs').select('status,counts,finished_at').eq('agent',runName).gte('started_at',since).limit(20); runs=r||[]; }
      const decided=(acts||[]).filter((a:any)=>a.status==='approved'||a.status==='rejected');
      if((!decided||decided.length===0) && runs.length===0) continue;
      processed++;
      const sys='You are the '+key+' specialist at QuotesDone reflecting weekly to get better, like a professional reviewing their own work. Based ONLY on the outcomes provided, extract at most 2 concise, durable lessons (each <= 25 words) that will improve your future decisions or recommendations. Focus on patterns (e.g. what the founder approved vs rejected, what failed). If there is nothing genuinely useful, return an empty list. Reply STRICT JSON only: {"lessons":["..."]}';
      const user='Recent decided recommendations: '+JSON.stringify(decided).slice(0,2500)+'\nRecent run results: '+JSON.stringify(runs).slice(0,1500);
      const raw=await llm(sys,user)||''; let lessons:string[]=[];
      try{ const m=raw.match(/\{[\s\S]*\}/); const p=JSON.parse(m?m[0]:raw); if(Array.isArray(p.lessons)) lessons=p.lessons.map((x:any)=>String(x).trim()).filter(Boolean).slice(0,2); }catch(_e){}
      if(!lessons.length) continue;
      const { data:existing } = await admin.from('agent_memory').select('content').eq('agent_key',key).eq('kind','reflection').order('id',{ascending:false}).limit(30);
      const seen=new Set((existing||[]).map((e:any)=>String(e.content).toLowerCase()));
      for(const L of lessons){ if(seen.has(L.toLowerCase())) continue; await admin.from('agent_memory').insert({agent_key:key,kind:'reflection',content:L.slice(0,400),source:'auto_reflection'}); added++; }
    }catch(_e){}
  }
  await admin.from('agent_runs').insert({agent:'reflect',started_at:started,finished_at:new Date().toISOString(),status:'ok',counts:{agents_processed:processed,lessons_added:added}});
  return new Response(JSON.stringify({ok:true,processed,added}),{headers:{'Content-Type':'application/json'}});
});
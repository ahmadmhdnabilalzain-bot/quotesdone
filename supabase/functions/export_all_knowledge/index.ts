import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const FIXED:Record<string,string>={brief:'Daily Brief',secretary:'Secretary (Chief of Staff)',cfo:'CFO',legal:'Legal Counsel',collections:'Collections Accountant',bookkeeper:'Bookkeeper',onboarding:'Onboarding / KYC',docs:'Document Controller',security:'Security Engineer',it:'IT / Uptime (SRE)',followup:'Follow-up (Lifecycle)',bd:'BD Representative',marketing:'Marketing'};
Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  const __exp = await sec('inbound_secret');
  if(!secretOk(__exp) || b.__secret!==__exp) return new Response('forbidden',{status:403});
  const { data: kn } = await admin.from('agent_knowledge').select('agent_key,topic,content,priority').order('priority',{ascending:false});
  const { data: cats } = await admin.from('category_agents').select('slug,name,persona').eq('active',true).order('name');
  const byKey=new Map<string, any[]>();
  for(const r of (kn||[])){ const k=r.agent_key as string; if(!byKey.has(k)) byKey.set(k,[]); byKey.get(k)!.push(r); }
  const sortRows=(rows:any[])=>rows.sort((a:any,b:any)=> (b.priority-a.priority));
  // Header/counts computed at runtime (OPEN_ISSUES #6 — were hardcoded "25 June 2026" / "24 trades").
  const catCount=(cats||[]).length;
  const pulledOn=new Date().toLocaleDateString('en-GB',{day:'2-digit',month:'long',year:'numeric'});
  let md='# QuotesDone — Complete Agent Knowledge Base (All Agents)\n\nEvery agent, every knowledge entry, pulled live on '+pulledOn+'. Sections: Global (all agents) → Fixed specialists → Category sales agents. Trade and fixed-agent packs are web-researched with sources; verify any exact figure before operational reliance.\n\n';
  // GLOBAL
  md+='\n# GLOBAL — shared by every agent\n\n';
  for(const r of sortRows(byKey.get('_global')||[])) md+='### '+r.topic+'\n\n'+(r.content||'').trim()+'\n\n';
  // FIXED
  md+='\n# FIXED SPECIALIST AGENTS\n\n';
  for(const key of Object.keys(FIXED)){
    const rows=byKey.get(key); if(!rows||!rows.length) continue;
    md+='\n---\n\n## '+FIXED[key]+'\n\n';
    for(const r of sortRows(rows)) md+='### '+r.topic+'\n\n'+(r.content||'').trim()+'\n\n';
  }
  // CATEGORIES
  md+='\n# CATEGORY SALES AGENTS ('+catCount+' trades)\n\n';
  const order=['Quote analysis & comparison','Customer intake & scoping questions','Regulations, licensing & approvals','Standards, materials & specifications','Pricing benchmarks & red flags','Authoritative sources & references'];
  for(const c of (cats||[])){
    md+='\n---\n\n## '+c.name+'\n\n**Persona:** '+((c.persona||'(none)').trim())+'\n\n';
    const rows=(byKey.get('cat:'+c.slug)||[]).slice();
    rows.sort((a:any,b:any)=>{ const ia=order.indexOf(a.topic), ib=order.indexOf(b.topic); return (ia<0?99:ia)-(ib<0?99:ib); });
    for(const r of rows) md+='### '+r.topic+'\n\n'+(r.content||'').trim()+'\n\n';
  }
  return new Response(md,{headers:{'Content-Type':'text/markdown; charset=utf-8'}});
});
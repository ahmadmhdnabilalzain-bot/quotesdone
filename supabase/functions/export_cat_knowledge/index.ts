import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sec(k:string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
Deno.serve(async (req)=>{
  let b:any={}; try{ b=await req.json(); }catch(_){}
  if(b.__secret!==(await sec('inbound_secret'))) return new Response('forbidden',{status:403});
  const { data: cats } = await admin.from('category_agents').select('slug,name,persona').eq('active',true).order('name');
  const { data: kn } = await admin.from('agent_knowledge').select('agent_key,topic,content,priority').like('agent_key','cat:%').order('priority',{ascending:false});
  const byKey=new Map<string, any[]>();
  for(const r of (kn||[])){ const k=r.agent_key as string; if(!byKey.has(k)) byKey.set(k,[]); byKey.get(k)!.push(r); }
  // Header computed at runtime (OPEN_ISSUES #6 — was hardcoded "24 trades" / "25 June 2026").
  const catCount=(cats||[]).length;
  const pulledOn=new Date().toLocaleDateString('en-GB',{day:'2-digit',month:'long',year:'numeric'});
  let md='# QuotesDone — Category Sales Agents: Deep Knowledge Packs\n\nFor each of the '+catCount+' trades: the agent persona plus a multi-section knowledge pack focused on (1) analysing & comparing supplier quotes and (2) asking the right intake questions, backed by regulations, standards, pricing and authoritative sources. Pulled live on '+pulledOn+'. Web-researched; verify any exact figure before operational reliance.\n\n';
  for(const c of (cats||[])){
    md+='\n---\n\n## '+c.name+'\n\n';
    md+='**Persona:** '+((c.persona||'(none)').trim())+'\n\n';
    const rows=byKey.get('cat:'+c.slug)||[];
    // stable order by a preferred topic sequence then priority
    const order=['Quote analysis & comparison','Customer intake & scoping questions','Regulations, licensing & approvals','Standards, materials & specifications','Pricing benchmarks & red flags','Authoritative sources & references'];
    rows.sort((a:any,b:any)=>{ const ia=order.indexOf(a.topic), ib=order.indexOf(b.topic); return (ia<0?99:ia)-(ib<0?99:ib); });
    for(const r of rows){ md+='### '+r.topic+'\n\n'+((r.content||'').trim())+'\n\n'; }
  }
  return new Response(md,{headers:{'Content-Type':'text/markdown; charset=utf-8'}});
});
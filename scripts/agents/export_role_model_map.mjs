import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
const REF = 'htdblwldjkcgjvmqkbeh';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token','utf8')).trim();
const q = async (s) => { const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({query:s})}); const t = await r.text(); if(!r.ok) throw new Error(t); return JSON.parse(t); };
const modelBacked = new Set(readFileSync(process.argv[2],'utf8').split('\n').map(s=>s.trim()).filter(Boolean));

const rows = await q(`
 select r.role_id, r.runtime_agent_key agent, r.primary_department_id dept, r.runtime_mode,
        r.authority_level, a.routing_tier,
        (fn_routing_tier_model(r.runtime_agent_key)->>'registry_tier') registry_tier,
        (fn_routing_tier_model(r.runtime_agent_key)->>'model') model_id,
        array_to_string(r.tools,'|') tools,
        (select string_agg(distinct x.kind,'+') from org_action_executor x
          where x.active and x.action_class = any(r.tools)) tool_kinds,
        (select string_agg(distinct x.target,'|') from org_action_executor x
          where x.active and x.action_class = any(r.tools) and x.kind='edge') edge_targets,
        coalesce((select count(*) from ai_cost_log c where c.agent_key=r.runtime_agent_key
                   and c.occurred_at > now()-interval '30 days'),0) calls_30d
   from org_role r join org_agents a on a.agent_key = r.runtime_agent_key
  where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
  order by r.primary_department_id, r.role_id`);

const csv = (v)=>{const s=v==null?'':String(v);return /[",\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s;};
const out = [['role_id','runtime_agent_key','department','runtime_mode','authority_level','routing_tier','registry_tier','model_id','execution_class','model_backed_tools','code_only_tools','llm_calls_30d'].join(',')];
let mb=0, co=0, mixed=0;
for (const r of rows) {
  const targets = (r.edge_targets||'').split('|').filter(Boolean);
  const mbt = targets.filter(t=>modelBacked.has(t));
  const cot = targets.filter(t=>!modelBacked.has(t));
  const kinds = r.tool_kinds||'';
  let cls;
  if (mbt.length===0 && kinds) { cls='code_only'; co++; }
  else if (mbt.length && cot.length===0 && !kinds.includes('rpc')) { cls='model_backed'; mb++; }
  else if (mbt.length) { cls='mixed'; mixed++; }
  else { cls='no_tools'; }
  out.push([r.role_id,r.agent,r.dept,r.runtime_mode,r.authority_level,r.routing_tier,r.registry_tier,r.model_id,cls,mbt.join('|'),cot.join('|'),r.calls_30d].map(csv).join(','));
}
mkdirSync('docs/agents',{recursive:true});
writeFileSync('docs/agents/ROLE_MODEL_MAP.csv', out.join('\n')+'\n');
const byModel={}, byClass={};
for (const r of rows){ byModel[r.model_id||'(none)']=(byModel[r.model_id||'(none)']||0)+1; }
console.log('roles:',rows.length);
console.log('model by registry tier:'); 
const byTier={}; for(const r of rows){const k=`${r.routing_tier} -> ${r.registry_tier} -> ${r.model_id}`; byTier[k]=(byTier[k]||0)+1;}
Object.entries(byTier).sort((a,b)=>b[1]-a[1]).forEach(([k,v])=>console.log(`  ${v.toString().padStart(3)}  ${k}`));
console.log(`execution class: model_backed=${mb} code_only=${co} mixed=${mixed} no_tools=${rows.length-mb-co-mixed}`);
console.log('roles with 0 llm calls in 30d:', rows.filter(r=>Number(r.calls_30d)===0).length);

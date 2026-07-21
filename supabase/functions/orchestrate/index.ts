// orchestrate - multi-agent teamwork. Decomposes one founder request into per-agent sub-tasks (Opus 4.8), has each
// agent PLAN its part (via agent_act), returns the combined plan for ONE approval, then EXECUTES across agents and
// synthesises a single combined result. Admin/secret only. Every underlying action is still audited + undoable.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const ROSTER: Record<string,string> = { docs:'Document Controller', onboarding:'Onboarding / KYC', crm:'CRM / Supplier Manager', marketing:'Marketing', pricing:'Pricing', cfo:'CFO', bookkeeper:'Bookkeeper', collections:'Collections', followup:'Follow-up', it:'IT / Uptime', security:'Security', bd:'BD / Outreach', legal:'Legal Counsel', brief:'Daily Brief' };
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function parseJson(t: string){ let s=String(t||'').trim(); const f=s.match(/```(?:json)?\s*([\s\S]*?)```/i); if(f) s=f[1].trim(); try{return JSON.parse(s);}catch{} const m=s.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return null; }
// Orchestration reasoning on Opus 4.8 (strongest) with Sonnet 5 as automatic fallback + retry.
async function opus(sys: string, user: string, max=1500){ const key=await sec('openrouter_api_key'); if(!key) return null; for(const model of ['anthropic/claude-opus-4.8','anthropic/claude-sonnet-5']){ for(let at=0; at<2; at++){ try{ const r=await fetch('https://openrouter.ai/api/v1/chat/completions',{method:'POST',headers:{'Authorization':'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({model,max_tokens:max,temperature:0.2,messages:[{role:'system',content:sys},{role:'user',content:user}]})}); const j=await r.json(); const c=j?.choices?.[0]?.message?.content; if(c) return c; }catch(_e){} } } return null; }
async function authed(req: Request, body: any){ if(body.__secret && body.__secret===(await sec('inbound_secret'))) return true; const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } }=await admin.auth.getUser(jwt); const allow=(await sec('admin_emails')||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
async function callAgent(secret: string, agent_key: string, mode: string, payload: any){ try{ const r=await fetch(URL_+'/functions/v1/agent_act',{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(Object.assign({ __secret:secret, agent_key, mode }, payload||{})) }); return await r.json(); }catch(e){ return { error:String((e as Error)?.message||e) }; } }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    if(!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    const secret = await sec('inbound_secret'); const mode = String(body.mode||'plan');

    if (mode === 'plan') {
      const instruction = String(body.instruction||'').slice(0,2500); if(!instruction) return J({ error:'instruction required' }, 400);
      const roster = Object.keys(ROSTER).map(k=>k+' ('+ROSTER[k]+')').join(', ');
      const sys = 'You are the COO orchestrating the QuotesDone agent team (a UAE B2B marketplace). Break the founder\'s request into the MINIMUM set of sub-tasks, each assigned to exactly ONE agent best suited to it. Use only agents that are genuinely needed. Available agents: '+roster+'. Return STRICT JSON ONLY: {"narrative":"one line on the overall plan","steps":[{"agent_key":"<key>","task":"<a clear, self-contained instruction for that agent>"}]}. Keep to at most 4 steps. Order them logically.';
      const out = await opus(sys, 'FOUNDER REQUEST: '+instruction, 1200); const dec = parseJson(out||'')||{};
      let steps = Array.isArray(dec.steps) ? dec.steps.filter((s:any)=>ROSTER[s.agent_key]).slice(0,4) : [];
      if(!steps.length) return J({ ok:true, narrative: String(dec.narrative||'No suitable breakdown found.'), steps: [] });
      // each agent plans its part in parallel
      const planned = await Promise.all(steps.map(async (s:any)=>{ const p=await callAgent(secret!, s.agent_key, 'plan', { instruction:s.task }); return { agent_key:s.agent_key, agent_name:ROSTER[s.agent_key], task:s.task, narrative:(p&&p.narrative)||'', plan:(p&&p.plan)||[], model:(p&&p.model)||null, error:p&&p.error }; }));
      return J({ ok:true, narrative:String(dec.narrative||''), steps: planned });
    }

    if (mode === 'execute') {
      const steps = Array.isArray(body.steps)?body.steps:[]; if(!steps.length) return J({ error:'no steps' }, 400);
      const results = [] as any[];
      for (const st of steps){ const agent_key=String(st.agent_key||''); if(!ROSTER[agent_key]) continue; const acts=Array.isArray(st.actions)?st.actions:[]; if(!acts.length){ results.push({ agent_key, agent_name:ROSTER[agent_key], results:[] }); continue; } const e=await callAgent(secret!, agent_key, 'execute', { actions:acts }); results.push({ agent_key, agent_name:ROSTER[agent_key], results:(e&&e.results)||[], error:e&&e.error }); }
      let summary=''; try{ const flat=results.map(r=>r.agent_name+': '+(r.results||[]).map((x:any)=>(x.ok?'✓':'✗')+' '+x.msg).join('; ')).join('\n'); summary=(await opus('You are the COO. In 2-4 short sentences, summarise for the founder what the team just completed and flag anything that failed or needs attention. Be concrete.', 'Results across agents:\n'+flat, 500))||flat; }catch(_e){}
      return J({ ok:true, results, summary });
    }

    return J({ error:'unknown mode' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});

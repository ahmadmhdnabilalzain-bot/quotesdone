// legal_review - AI-assisted review of an agreement / NDA / supplier or customer contract. Flags missing or risky
// clauses against a checklist and produces a plain summary. It is NOT legal advice: every review sets
// needs_licensed_review=true and material/high-risk items are escalated to the founder for a licensed UAE lawyer.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// Robust JSON extraction. Handles: clean JSON, fenced JSON, UNTERMINATED fences (truncated output),
// prose preambles, and truncated objects (repairs by balancing braces/brackets and closing open strings).
function parseJson(t:string){
  let s=String(t||'').trim();
  if(!s) return null;
  // 1) closed fence
  const closed=s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if(closed) s=closed[1].trim();
  else {
    // 2) unterminated fence (model hit max_tokens before closing it)
    const open=s.match(/```(?:json)?\s*([\s\S]*)$/i);
    if(open) s=open[1].trim();
  }
  try{ return JSON.parse(s); }catch(_e){}
  // 3) first balanced-ish object
  const start=s.indexOf('{');
  if(start<0) return null;
  s=s.slice(start);
  const last=s.lastIndexOf('}');
  if(last>0){ try{ return JSON.parse(s.slice(0,last+1)); }catch(_e){} }
  // 4) repair truncated JSON: close any open string, then balance brackets
  try{
    let inStr=false, esc=false; const stack:string[]=[];
    for(let i=0;i<s.length;i++){
      const ch=s[i];
      if(esc){ esc=false; continue; }
      if(ch==='\\'){ esc=true; continue; }
      if(ch==='"'){ inStr=!inStr; continue; }
      if(inStr) continue;
      if(ch==='{'||ch==='[') stack.push(ch);
      else if(ch==='}'||ch===']') stack.pop();
    }
    let fixed=s;
    if(inStr) fixed+='"';
    // drop a dangling trailing comma or partial key before closing
    fixed=fixed.replace(/,\s*$/,'');
    while(stack.length){ const o=stack.pop(); fixed += (o==='{' ? '}' : ']'); }
    return JSON.parse(fixed);
  }catch(_e){}
  return null;
}

async function logRun(status:string, counts:Record<string,unknown>, note:string){
  try{ await admin.from('agent_runs').insert({ agent:'legal_review', status, counts, note: String(note||'').slice(0,500) }); }catch(_e){}
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const kind = String(body.kind || 'contract');
    const title = String(body.title || 'Untitled document');
    let text = String(body.text || '').trim();
    // optionally load from a legal_document slug
    if (!text && body.slug) { const { data } = await admin.from('legal_documents').select('body_html').eq('slug', body.slug).maybeSingle(); text = String(data?.body_html||'').replace(/<[^>]+>/g,' ').trim(); }
    if (!text || text.length < 100) return J({ error: 'no_text', note: 'Provide {text} or a legal_document {slug} to review.' });
    if (text.length > 60000) text = text.slice(0, 60000);

    const sys = 'You are a contracts analyst assisting a UAE B2B marketplace. Review the document and identify MISSING or RISKY clauses against best practice for this document type. Consider: parties & definitions, scope, payment/commission, liability & indemnity, limitation of liability, confidentiality/NDA, data protection (UAE PDPL), IP/content ownership, termination, warranties, force majeure, governing law & jurisdiction (should be UAE/relevant emirate), dispute resolution, compliance with UAE law. You are NOT a lawyer and must NOT give definitive legal advice or say the document is safe/enforceable. Flag issues for a licensed UAE lawyer to decide. Return STRICT JSON only, no markdown fences and no commentary. Keep each "issue" under 40 words so the response is never truncated. Schema: {"summary": string (plain, 3-4 sentences), "risk_flags": [{"clause": string, "issue": string, "severity": "low|medium|high"}], "missing_clauses": string[], "risk_level": "low|medium|high", "lawyer_questions": string[]}';
    const usr = 'DOCUMENT TYPE: '+kind+'\nTITLE: '+title+'\n\nDOCUMENT:\n"""\n'+text+'\n"""';
    const key = await sec('inbound_secret'); if (!key) { await logRun('error',{},'ai_unavailable: no inbound secret'); return J({ error:'ai_unavailable' }); }
    let parsed:any=null; let used=''; let lastRaw=''; let lastErr='';
    for (let attempt=0; attempt<2; attempt++) {
      try {
        const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret:key, fn:'legal_review', sys, input:usr, max:4000, temperature:0.2 }) });
        const jd=await r.json();
        if(jd?.error){ lastErr=String(jd.error?.message||jd.error).slice(0,200); continue; }
        const c=jd?.content||'';
        const model=String(jd?.model||'ai_gateway');
        lastRaw=String(c).slice(0,300);
        const p=parseJson(c);
        if(p){ parsed=p; used=model; break; }
        lastErr='unparseable ('+model+', outcome='+String(jd?.outcome||'')+')';
      } catch(e){ lastErr=String((e as Error)?.message||e).slice(0,200); }
    }
    if (!parsed) { await logRun('error',{},'llm_failed: '+lastErr+' | raw: '+lastRaw); return J({ error:'llm_failed', detail:lastErr }); }
    const level = ['low','medium','high'].includes(parsed.risk_level) ? parsed.risk_level : 'medium';
    const flags = Array.isArray(parsed.risk_flags) ? parsed.risk_flags : [];
    const { data: row } = await admin.from('legal_reviews').insert({ doc_kind:kind, title, source: body.slug?('legal_document:'+body.slug):'pasted', summary: parsed.summary, risk_flags: flags, risk_level: level, needs_licensed_review: true }).select('id').single();
    // escalate material reviews to the founder (never resolve on its own)
    if (level==='high' || flags.some((f:any)=>f?.severity==='high')) {
      await admin.from('agent_actions').insert({ agent:'legal_ai', kind:'legal_flag', status:'pending', risk:'high',
        title:'Legal review flagged risks: '+title,
        recommendation:(parsed.summary||'')+'\n\nHigh-risk items were found. Have a licensed UAE lawyer review before signing.\n\n⚠️ Not legal advice.',
        detail: jsonb_min(parsed, kind, title, row?.id), target_table:'legal_reviews', target_id: String(row?.id||'') });
    }
    await logRun('ok',{ issues:flags.length, high:flags.filter((f:any)=>f?.severity==='high').length, risk:level },'');
    return J({ ok:true, review_id: row?.id, model: used, risk_level: level, summary: parsed.summary, risk_flags: flags, missing_clauses: parsed.missing_clauses, lawyer_questions: parsed.lawyer_questions, disclaimer: 'AI-assisted review only — not legal advice. Requires a licensed UAE lawyer.' });
  } catch (e) { const m=String((e as Error)?.message || e); await logRun('error',{},'exception: '+m); return J({ error: m }, 500); }
});
function jsonb_min(p:any, kind:string, title:string, id:any){ return { signal:'contract_review', kind, title, review_id:id, missing:(p.missing_clauses||[]).slice(0,8) }; }

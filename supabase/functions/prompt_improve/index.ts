// prompt_improve - the AI Trainer's authoring step. Takes a prompt key + why it underperforms, asks the LLM to
// rewrite the system prompt to fix it, saves the result as a DRAFT version (never touches the live active_version),
// and queues a founder approval action. The founder approves (fn_prompt_approve_draft) to roll it out. Internal.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'prompt_improve');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const key = String(body.key||'').trim();
    if (!key) return J({ error: 'no_key' });
    const reason = String(body.reason || 'This prompt underperforms on its quality benchmark.');

    const { data: cur } = await admin.rpc('fn_prompt_get', { p_key: key });
    const current = String(cur || '').trim();
    if (!current) return J({ error: 'prompt_not_found', key });

    // gather a little real evidence: recent founder-rejected AI actions + any trainer notes
    const { data: rej } = await admin.from('agent_actions').select('title,recommendation').eq('status','rejected').order('decided_at',{ascending:false}).limit(5);
    const evidence = (rej||[]).map((r:any)=>'- '+r.title).join('\n') || '(no specific rejected examples on file)';

    const sys = 'You are an expert prompt engineer improving a production system prompt for a UAE B2B trades/quotation marketplace. Rewrite the prompt to fix the stated weakness while preserving its purpose, scope, output format and any hard rules. Keep it concise and unambiguous. Do NOT invent new tools, capabilities, or data the agent does not have. Return ONLY the improved system prompt text — no preamble, no explanation, no markdown fences.';
    const usr = 'PROMPT KEY: '+key+'\n\nWHY IT UNDERPERFORMS:\n'+reason+'\n\nRECENT ISSUES (founder-rejected agent actions):\n'+evidence+'\n\nCURRENT PROMPT:\n"""\n'+current+'\n"""\n\nRewrite it to fix the weakness. Return only the improved prompt.';

    const apiKey = await sec('inbound_secret'); if (!apiKey) return J({ error: 'ai_unavailable' });
    let improved = ''; let usedModel = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: apiKey, fn: 'prompt_improve', sys, input: usr, max: 2000, temperature: 0.3 }) });
        const jd = await r.json(); const c = jd?.content || '';
        if (c && c.trim().length > 100) { improved = c.trim().replace(/^```[a-z]*\n?/i,'').replace(/```$/,'').trim(); usedModel = String(jd?.model || 'ai_gateway'); break; }
      } catch (_e) { /* try next */ }
    }
    if (!improved) return J({ error: 'llm_failed' });
    if (improved === current) return J({ ok:true, note:'no_change_suggested' });

    const { data: v } = await admin.rpc('fn_prompt_draft', { p_key: key, p_content: improved, p_by: 'ai_trainer' });
    const ver = Number(v);
    // queue founder approval (do not auto-publish)
    await admin.from('agent_actions').insert({ agent:'ai_trainer', kind:'prompt_approval', status:'pending', risk:'high',
      title:'Approve improved prompt: '+key+' (v'+ver+')',
      recommendation:'The AI Trainer drafted an improved version of the '+key+' prompt to fix: '+reason+'. Review the draft; approve to roll it out (replaces the live version) or reject to discard. The live prompt is unchanged until you approve.',
      detail: { key, version: ver, model: usedModel, reason, chars: improved.length }, target_table:'prompt_versions', target_id: key+':'+ver });
    return J({ ok:true, key, draft_version: ver, model: usedModel, chars: improved.length });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

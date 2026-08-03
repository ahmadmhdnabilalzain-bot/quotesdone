// canon_eval v2 — the LAYERED EXAMINATION ENGINE. Picks questions scoped to the agent
// (agent_key null = shared; agent_key = this agent) balanced across knowledge layers
// (company / profession / state / experience), asks the real agent via agent_brain, and
// grades against the reference with an LLM judge. Random selection per run (no memorizable
// fixed paper). Records runs + per-layer gaps to canon_eval_runs. Auth: __secret OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const judge = makeLlm(SONNET_FIRST, { max: 200, temperature: 0 });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if ((await requireInternal(admin, body?.__secret, 'canon_eval')).ok) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}
function shuffle<T>(a: T[]): T[] { const x = [...a]; for (let i = x.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [x[i], x[j]] = [x[j], x[i]]; } return x; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);
    const agent = String(body.agent || 'followup');
    const limit = Math.max(1, Math.min(Number(body.limit) || 4, 6));
    const secret = await sec('cred_fn_to_agent_brain');

    const { data: all } = await admin.from('canon_eval_questions')
      .select('id,category,question,reference,layer,agent_key').eq('active', true)
      .or('agent_key.is.null,agent_key.eq.' + agent);
    if (!all || !all.length) return J({ error: 'no questions loaded' });

    // Balanced draw: the agent's OWN profession questions first, then one state + one
    // experience, remainder from the shared company canon. Random within each pool.
    let chosen: any[];
    if (Array.isArray(body.ids) && body.ids.length) {
      chosen = all.filter((q) => body.ids.includes(q.id)).slice(0, limit);
    } else {
      const pool = (l: string, own = false) => shuffle(all.filter((q) =>
        (q.layer || 'company') === l && (own ? q.agent_key === agent : true)));
      const picks: any[] = [];
      picks.push(...pool('profession', true).slice(0, 2));
      picks.push(...pool('state').slice(0, 1));
      picks.push(...pool('experience').slice(0, 1));
      for (const q of shuffle(all.filter((q) => (q.layer || 'company') === 'company'))) {
        if (picks.length >= limit) break;
        picks.push(q);
      }
      chosen = picks.slice(0, limit);
    }
    if (!chosen.length) return J({ error: 'no questions matched' });

    let passed = 0; const gaps: any[] = []; const byLayer: Record<string, { asked: number; passed: number }> = {};
    for (const q of chosen) {
      const L = q.layer || 'company'; byLayer[L] = byLayer[L] || { asked: 0, passed: 0 }; byLayer[L].asked++;
      let answer = '';
      try {
        const ar = await fetch(FN + '/agent_brain', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, agent, message: String(q.question) }), signal: AbortSignal.timeout(30000) });
        const aj = await ar.json().catch(() => ({} as any)); answer = String(aj?.reply || '');
      } catch (_e) { answer = ''; }
      const jsys = 'You grade whether an AI agent answer about QuotesDone is CORRECT against a reference. PASS if the answer conveys the key facts of the reference (wording differences and extra correct detail are fine). FAIL if it contradicts the reference, invents wrong facts, or misses the core fact. If the reference says the fact is "not specified in canon", PASS only if the agent appropriately says it is not defined / declines rather than fabricating. Reply STRICT JSON only: {"verdict":"PASS"|"FAIL","reason":"<=12 words"}.';
      const juser = 'QUESTION: ' + q.question + '\nREFERENCE: ' + (q.reference || '') + '\nAGENT ANSWER: ' + (answer || '(no answer)') + '\n\nGrade it.';
      let v: any = null;
      try { const raw = (await judge(jsys, juser, 200) || '').trim(); v = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = (await judge(jsys, juser, 200) || '').match(/PASS|FAIL/i); v = { verdict: m ? m[0].toUpperCase() : 'FAIL', reason: 'parse' }; }
      const ok = String(v?.verdict).toUpperCase() === 'PASS';
      if (ok) { passed++; byLayer[L].passed++; }
      else gaps.push({ id: q.id, category: q.category, layer: L, question: q.question, reason: v?.reason || '', answer: answer.slice(0, 200) });
    }
    const score = chosen.length ? Math.round((passed / chosen.length) * 1000) / 10 : 0;
    const { data: run } = await admin.from('canon_eval_runs').insert({ agent, asked: chosen.length, passed, score_pct: score, gaps }).select('id').maybeSingle();
    return J({ ok: true, run_id: run?.id || null, agent, asked: chosen.length, passed, score_pct: score, by_layer: byLayer, gaps });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

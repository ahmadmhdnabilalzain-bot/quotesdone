// canon_eval — the OMNISCIENCE SCOREBOARD. Picks N questions from canon_eval_questions, asks a real
// agent (via agent_brain), and grades each answer against the reference with an LLM judge. Records a run
// (score + the questions that failed = gaps) to canon_eval_runs. Batched (a few per call) so it never times out.
// Auth: __secret (cron) OR admin JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
const judge = makeLlm(SONNET_FIRST, { max: 200, temperature: 0 });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function authed(req: Request, body: any): Promise<boolean> {
  if (body.__secret && body.__secret === (await sec('inbound_secret'))) return true;
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || 'management@quotesdone.com').split(',').map((s) => s.trim().toLowerCase());
  return !!(user?.email && allow.includes(user.email.toLowerCase()));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) return J({ error: 'forbidden' }, 403);
    const agent = String(body.agent || 'followup');
    const limit = Math.max(1, Math.min(Number(body.limit) || 4, 6));
    const secret = await sec('inbound_secret');

    // Random sample of active questions.
    const { data: all } = await admin.from('canon_eval_questions').select('id,category,question,reference').eq('active', true);
    if (!all || !all.length) return J({ error: 'no questions loaded' });
    const pick = all.map((q) => ({ q, r: (q.id * 2654435761) % 1000 })).sort((a, b) => a.r - b.r).slice(0, limit).map((x) => x.q);
    // ^ deterministic-ish pick; over many runs different limits/offsets cover the bank. For true random pass body.ids.
    const chosen = Array.isArray(body.ids) && body.ids.length ? all.filter((q) => body.ids.includes(q.id)).slice(0, limit) : pick;

    let passed = 0; const gaps: any[] = [];
    for (const q of chosen) {
      // Ask the real agent.
      let answer = '';
      try {
        const ar = await fetch(FN + '/agent_brain', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret, agent, message: String(q.question) }), signal: AbortSignal.timeout(30000) });
        const aj = await ar.json().catch(() => ({} as any)); answer = String(aj?.reply || '');
      } catch (_e) { answer = ''; }
      // Grade it.
      const jsys = 'You grade whether an AI agent answer about QuotesDone is CORRECT against a reference. PASS if the answer conveys the key facts of the reference (wording differences and extra correct detail are fine). FAIL if it contradicts the reference, invents wrong facts, or misses the core fact. If the reference says the fact is "not specified in canon", PASS only if the agent appropriately says it is not defined / declines rather than fabricating. Reply STRICT JSON only: {"verdict":"PASS"|"FAIL","reason":"<=12 words"}.';
      const juser = 'QUESTION: ' + q.question + '\nREFERENCE: ' + (q.reference || '') + '\nAGENT ANSWER: ' + (answer || '(no answer)') + '\n\nGrade it.';
      let v: any = null;
      try { const raw = (await judge(jsys, juser, 200) || '').trim(); v = JSON.parse(raw.replace(/^```(json)?/i, '').replace(/```$/, '').trim()); } catch (_e) { const m = (await judge(jsys, juser, 200) || '').match(/PASS|FAIL/i); v = { verdict: m ? m[0].toUpperCase() : 'FAIL', reason: 'parse' }; }
      const ok = String(v?.verdict).toUpperCase() === 'PASS';
      if (ok) passed++; else gaps.push({ id: q.id, category: q.category, question: q.question, reason: v?.reason || '', answer: answer.slice(0, 200) });
    }
    const score = chosen.length ? Math.round((passed / chosen.length) * 1000) / 10 : 0;
    const { data: run } = await admin.from('canon_eval_runs').insert({ agent, asked: chosen.length, passed, score_pct: score, gaps }).select('id').maybeSingle();
    return J({ ok: true, run_id: run?.id || null, agent, asked: chosen.length, passed, score_pct: score, gaps });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

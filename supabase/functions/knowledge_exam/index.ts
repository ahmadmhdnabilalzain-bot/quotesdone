// knowledge_exam — proactive auto-learning loop. For a target agent it (1) generates fresh domain
// questions + reference answers (examiner), (2) makes the agent answer using ONLY its own knowledge
// context (examinee — reveals coverage gaps), (3) has an INDEPENDENT grader model judge the answer and
// supply the correct fact, and (4) AUTO-WRITES a correction into agent_knowledge — but only when the two
// independent models converge on the fact AND it passes the policy poison-lint. Fills are provenance-
// tagged (topic 'exam:…') so they are auditable and bulk-revertible. Logs every attempt to knowledge_exam_results.
// No human approval step by design — safety comes from model-convergence + lint, not clicking.
// v2: examiner and examinee are now grounded on the DEEP knowledge corpus (kb_chunks via kb_search),
// so the exam probes and measures true retrieval-augmented mastery, not just the capped context layer.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, OPUS_FIRST, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const T0 = Date.now();
// Retrieve from the DEEP knowledge corpus (kb_chunks) exactly as production agents do, so the exam
// probes — and the examinee answers from — the real retrieval-augmented knowledge, not just the
// capped fn_agent_context layer. Without this the exam under-measures and flags false gaps.
async function deepKb(query: string, category: string | null, k: number): Promise<string> {
  try {
    const secret = await sec('inbound_secret'); if (!secret || !query.trim()) return '';
    const r = await fetch(SUPA + '/functions/v1/kb_search', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, query: query.slice(0, 800), k, ...(category ? { category } : {}) }) });
    const j = await r.json(); const rows = (j && Array.isArray(j.results)) ? j.results : [];
    if (!rows.length) return '';
    return rows.map((x: any) => '- [' + (x.citation || x.category || 'ref') + '] ' + String(x.snippet || '').replace(/\s+/g, ' ').slice(0, 400)).join('\n');
  } catch (_e) { return ''; }
}
const examiner = makeLlm(SONNET_FIRST, { max: 1600, temperature: 0.4 });   // writes the curriculum
const grader   = makeLlm(OPUS_FIRST,   { max: 1600, temperature: 0.1 });   // independent judge + ground truth
const examinee = makeLlm(SONNET_FIRST, { max: 1200, temperature: 0.2 });   // answers, constrained to its KB
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'knowledge_exam', status, counts, note: String(note || '').slice(0, 500), started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() }); } catch (_e) { /* */ }
}
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
function parseJson(s: string): any { if (!s) return null; let t = String(s).trim().replace(/^```(?:json)?/i, '').replace(/```$/,'').trim(); const a = t.indexOf('['), o = t.indexOf('{'); const start = (a >= 0 && (o < 0 || a < o)) ? a : o; if (start > 0) t = t.slice(start); try { return JSON.parse(t); } catch (_e) { return null; } }
// crude convergence: do two independently-produced answers share their significant terms?
function converged(a: string, b: string): boolean {
  const norm = (x: string) => new Set(String(x || '').toLowerCase().replace(/[^a-z0-9%\s.]/g, ' ').split(/\s+/).filter((w) => w.length > 3));
  const A = norm(a), B = norm(b); if (!A.size || !B.size) return false;
  let inter = 0; for (const w of A) if (B.has(w)) inter++;
  const jac = inter / (A.size + B.size - inter);
  // also require agreement on any numbers/codes present (a wrong figure must not pass)
  const nums = (x: string) => (String(x || '').match(/\b\d[\d.,]*\b/g) || []).map((n) => n.replace(/[.,]$/, ''));
  const na = nums(a), nb = nums(b); const numsOk = na.length === 0 || na.some((n) => nb.includes(n));
  return jac >= 0.3 && numsOk;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'knowledge_exam');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const nGen = Math.max(0, Math.min(20, Number(body.generate) ?? 6));
    const nAns = Math.max(1, Math.min(20, Number(body.answer) ?? 8));

    // 1) resolve target agent: explicit, or the real agent (has knowledge) least-recently examined
    let key: string = String(body.agent_key || '').trim();
    if (!key) {
      const { data: roster } = await admin.rpc('fn_exam_pick_agent');
      key = (roster as any) || '';
    }
    if (!key) { await logRun('skipped', {}, 'no agent to examine'); return J({ ok: true, note: 'no agent' }); }
    let label = key;
    if (key.startsWith('cat:')) { const { data: ca } = await admin.from('category_agents').select('name').eq('slug', key.slice(4)).maybeSingle(); if (ca?.name) label = (ca as any).name + ' specialist'; }

    // 2) the agent's actual knowledge context (what it reasons from) + its DEEP corpus region
    const cat = key.startsWith('cat:') ? key.slice(4) : key;   // deep chunks are category-scoped to this slug
    const { data: ctxRaw } = await admin.rpc('fn_agent_context', { p_agent_key: key, p_max_chars: 16000 });
    const kb = String(ctxRaw || '').slice(0, 16000);
    // Deep material for the examiner's remit — lets it write questions that probe true mastery.
    const remitDeep = await deepKb(label + ' UAE Dubai key materials standards authorities pricing', cat, 8);

    // 3) examiner writes fresh questions (+ reference answers), avoiding recent duplicates
    const { data: recentQs } = await admin.from('knowledge_exam_questions').select('question').eq('agent_key', key).order('id', { ascending: false }).limit(60);
    const seen = (recentQs || []).map((r: any) => '- ' + r.question).join('\n');
    let generated = 0;
    if (nGen > 0) {
      const gsys = 'You are a rigorous examiner building a competency test for the "' + label + '" agent at QuotesDone, a UAE (Dubai-focused) B2B sourcing marketplace. Use the AGENT REMIT below to test the knowledge THIS agent actually needs for its role: for a trade specialist that means UAE governing authorities/permits, technical standards, scope & specs, price drivers and compliance red flags; for a functional role (finance, legal, IT, analytics, marketing, operations) it means the professional, regulatory and platform knowledge that role needs in the UAE context. Produce hard, SPECIFIC, factually-answerable questions with a definite correct answer, and give each correct concise answer (<=240 chars). Output ONLY a JSON array: [{"question":"...","answer":"...","topic":"authority|standards|scope|pricing|compliance|domain","difficulty":"core|edge"}]. HARD RULE: never invent code numbers, authority names or figures — if unsure of an exact number, phrase the answer by naming the requirement without a fabricated number.\n\nAGENT REMIT (excerpt of its live knowledge):\n' + (kb ? kb.slice(0, 1400) : '(sparse — infer the role from the agent name "' + label + '")') + (remitDeep ? '\n\nDEEP REFERENCE MATERIAL (the specialist carries this — probe it):\n' + remitDeep.slice(0, 2000) : '');
      const guser = 'Domain: ' + label + '. Market: UAE (Dubai). Write ' + nGen + ' new questions. Do NOT repeat any of these already-asked questions:\n' + (seen || '(none yet)');
      const gout = parseJson((await examiner(gsys, guser)) || '');
      if (Array.isArray(gout)) {
        const rows = gout.filter((q: any) => q && q.question).slice(0, nGen).map((q: any) => ({ agent_key: key, question: String(q.question).slice(0, 600), reference_answer: String(q.answer || '').slice(0, 600), topic: String(q.topic || 'general').slice(0, 40), difficulty: String(q.difficulty || 'core').slice(0, 12) }));
        if (rows.length) { const { data: ins } = await admin.from('knowledge_exam_questions').insert(rows).select('id'); generated = (ins || []).length; }
      }
    }

    // 4) pick the batch to test: least-recently-asked (new rows have null last_asked → first)
    const { data: batch } = await admin.from('knowledge_exam_questions').select('id,question,reference_answer,topic').eq('agent_key', key).order('last_asked', { ascending: true, nullsFirst: true }).limit(nAns);
    const qs = batch || [];
    if (!qs.length) { await logRun('ok', { generated, examined: 0 }, 'generated ' + generated + ' questions for ' + key + '; none to test yet'); return J({ ok: true, agent: key, generated, examined: 0 }); }

    // 5) examinee answers using its knowledge base — fn_agent_context PLUS the deep corpus it would
    //    retrieve in production (kb_search on the batch questions), so the exam mirrors real ability.
    const qList = qs.map((q: any, i: number) => (i + 1) + '. ' + q.question).join('\n');
    const answerDeep = await deepKb(qs.map((q: any) => q.question).join(' '), cat, 10);
    const esysKb = (kb || '(empty)') + (answerDeep ? '\n\nRETRIEVED REFERENCE KNOWLEDGE (deep corpus, same as production retrieval):\n' + answerDeep : '');
    const esys = 'You are the "' + label + '" specialist agent. Answer each question using ONLY the KNOWLEDGE BASE provided. If the knowledge base does not clearly contain the answer, reply exactly "NOT_COVERED" for that item — do not guess from general knowledge. Output ONLY a JSON array of strings, one answer per question in order.\n\nKNOWLEDGE BASE:\n' + esysKb;
    const eout = parseJson((await examinee(esys, 'Questions:\n' + qList)) || '');
    const answers: string[] = Array.isArray(eout) ? eout.map((x: any) => String(x)) : qs.map(() => '__NO_ANSWER__');

    // 6) independent grader judges + supplies ground truth
    const gradeItems = qs.map((q: any, i: number) => ({ n: i + 1, question: q.question, agent_answer: answers[i] || '' }));
    const jsys = 'You are an independent expert examiner for "' + label + '" in the UAE (Dubai). For each item you are given a question and the agent\'s answer. Independently determine the correct answer yourself, then judge the agent\'s answer. Output ONLY a JSON array: [{"n":<num>,"correct_answer":"<your concise correct answer, <=240 chars>","verdict":"correct|partial|wrong|not_covered","confidence":<0..1>,"fact":"<one durable teaching sentence, <=240 chars, that would fix the gap>"}]. verdict "not_covered" means the agent said NOT_COVERED. Be strict: a wrong number or wrong authority is "wrong", not "partial". HARD RULE: never fabricate a code number or authority; if unsure of an exact figure, state the requirement without a number.';
    const jout = parseJson((await grader(jsys, JSON.stringify(gradeItems))) || '');
    const grades: any[] = Array.isArray(jout) ? jout : [];

    // 7) fill decision — write only on gap + model convergence + lint + confidence
    const { data: rules } = await admin.from('policy_rules').select('forbid_regex').eq('active', true);
    const lintClean = (t: string) => { for (const r of (rules || [])) { try { if (new RegExp(String(r.forbid_regex), 'i').test(t)) return false; } catch (_e) {} } return true; };
    let examined = 0, gaps = 0, filled = 0, conflicts = 0;
    for (let i = 0; i < qs.length; i++) {
      const q: any = qs[i]; const g = grades.find((x) => Number(x.n) === i + 1) || {};
      const verdict = String(g.verdict || 'unverifiable').toLowerCase();
      const conf = Number(g.confidence);
      const isGap = ['wrong', 'partial', 'not_covered'].includes(verdict);
      const fact = String(g.fact || g.correct_answer || '').trim();
      const conv = converged(q.reference_answer || '', g.correct_answer || '');
      let didFill = false; let knowledgeId: number | null = null;
      examined++;
      if (isGap) gaps++;
      if (isGap && fact && conv && (isFinite(conf) ? conf >= 0.7 : true) && lintClean(fact)) {
        const { data: kins } = await admin.from('agent_knowledge').insert({ agent_key: key, topic: 'exam:' + String(q.topic || 'general'), content: fact.slice(0, 1000), priority: 6, layer: 'profession' }).select('id').maybeSingle();
        knowledgeId = (kins as any)?.id ?? null; didFill = !!knowledgeId; if (didFill) filled++;
      } else if (isGap && fact && !conv) { conflicts++; }
      await admin.from('knowledge_exam_results').insert({ agent_key: key, question_id: q.id, examinee_answer: (answers[i] || '').slice(0, 1000), verdict, grader_answer: String(g.correct_answer || '').slice(0, 1000), grader_confidence: isFinite(conf) ? conf : null, converged: conv, gap_fact: isGap ? fact.slice(0, 1000) : null, filled: didFill, knowledge_id: knowledgeId });
      try { await admin.rpc('fn_bump_exam_question', { p_id: q.id }); } catch (_e) { /* */ }
    }
    const score = examined ? Math.round(100 * (examined - gaps) / examined) : null;
    const note = 'Examined ' + key + ': ' + (examined - gaps) + '/' + examined + ' correct (' + score + '%), ' + gaps + ' gap(s), ' + filled + ' auto-filled after model-convergence+lint, ' + conflicts + ' correction(s) withheld (models disagreed).';
    await logRun('ok', { agent: key, generated, examined, gaps, filled, conflicts, score }, note);
    return J({ ok: true, agent: key, label, generated, examined, gaps, filled, conflicts, score });
  } catch (e) { await logRun('error', {}, 'knowledge_exam crashed: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});

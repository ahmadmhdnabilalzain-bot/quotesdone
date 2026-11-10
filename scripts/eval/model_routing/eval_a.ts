// EVAL A: THE T2 REPLIES AND THE STATUS LANE ON GPT-6 LUNA PRO, AGAINST A SONNET 5.5 CONTROL (it_engineer, cost seat; 10 Nov
// 2026; ruling 1571; design docs/reports/2026-11-10-design-model-routing.md section 5c). It gates
// scripts/sql/customer_chat_and_the_reviewer_move_once_their_evals_pass.sql (the chat half).
//
// WHAT RUNS. The 40 scripted turns of cases_a.ts through THIS checkout's own reply code against the LIVE gateway and the live
// company brief: a status, invoice-copy, comparison-ready or code ask through wa_inbound's status lane (modelSays with
// status_lane.ts's class rules, no brief, the last 6 turns, the reference as must); a support or supplier turn through
// modelSays' full path (the brief); a visitor turn through aiReply on the widget channel. Each arm names the class whose
// route puts it on the model under test, and the run REFUSES to start unless fn_ai_route says so today:
//   candidate  customer_communication (Luna Pro > Sonnet; the class status_reply and the moved chat classes share its primary)
//   control    conversation_reply / visitor_chat (Sonnet 5.5 > Luna Pro), on --control-every'th case (default 2: 20 of 40)
// The judge is Sonnet 5.5 through knowledge_validation with counterpart_model = Luna Pro (never the model under test), in
// batches of 10 cases, each case's replies blind-labelled in a random order.
//
// PASS, all of these (design 5c): 0 critical errors (a must left out, an invented figure, the wrong language, an identity
// leak, a deferral) on the candidate; must present in 100%; rewrite rate <= 15% and second-rung rate <= 5%; the person's
// language in >= 95% (script + judge); judge mean >= 8.0 and >= the control mean - 0.5 on the paired cases.
//
//   deno run -A --node-modules-dir=none scripts/eval/model_routing/eval_a.ts --cap 1.10 [--control-every 2] [--limit 40]
//     [--out docs/reports/model-routing-evals-2026-11-10/eval_a.json]
import { arg, CapReached, closeWindow, connect, DEFERRAL, guardSpend, newTag, openWindow, routeOf, scriptOf, writeJson, type Ctx } from './harness.ts';
import { JUDGE_FN } from './harness.ts';
import { CASES_A, type CaseA } from './cases_a.ts';

const CAP = Number(arg('--cap') ?? '1.10');
const CONTROL_EVERY = Math.max(1, Number(arg('--control-every') ?? '2'));
const LIMIT = Number(arg('--limit') ?? '40');
const OUT = arg('--out') ?? 'docs/reports/model-routing-evals-2026-11-10/eval_a.json';
// --rejudge <eval_a.json>: judge the replies an earlier run wrote again (no reply is asked again); the judge is the only spend
const REJUDGE = arg('--rejudge');
const LUNA = 'openai/gpt-6-luna-pro', SONNET = 'anthropic/claude-sonnet-5.5';
const ARMS = {
  candidate: { model: LUNA, status: 'customer_communication', chat: 'customer_communication', visitor: 'customer_communication' },
  control: { model: SONNET, status: 'conversation_reply', chat: 'conversation_reply', visitor: 'visitor_chat' },
} as const;
type Arm = keyof typeof ARMS;
// the next call's estimate for the spend guard (USD): a brief-less status reply, a full reply with the ~23k-token brief, a judge batch
const EST = { candidate: { lean: 0.003, full: 0.01 }, control: { lean: 0.02, full: 0.12 }, judge: 0.12 };

const { admin, secret } = await connect();
const { modelSays } = await import('../../../supabase/functions/wa_inbound/model_says.ts');
const { STATUS_RULES, laneMust } = await import('../../../supabase/functions/wa_inbound/status_lane.ts');
const { aiReply } = await import('../../../supabase/functions/_shared/ai_reply.ts');
const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');

// THE ROUTES ARE WHAT THE ARMS SAY, OR NOTHING RUNS
for (const [arm, a] of Object.entries(ARMS)) {
  for (const [cls, seat] of [[a.status, 'customer_support'], [a.chat, 'customer_support'], [a.visitor, 'customer_support']]) {
    const r = await routeOf(admin, cls, seat);
    if (r.model !== a.model) throw new Error(`arm ${arm}: ${cls} for ${seat} routes ${r.model} today, not ${a.model}; refusing to run`);
  }
}

const tag = newTag('evala');
const c: Ctx = { admin, tag, secret, capUsd: CAP };
await openWindow(admin, tag, CAP, 60, 'eval A, model routing (ruling 1571): Luna Pro vs Sonnet on 40 scripted turns');
console.log(`eval A: run tag qd_run:${tag}, cap USD ${CAP}`);
const inRun = <T>(f: () => Promise<T>) => E2E_RUN.run({ tag, secret }, f);

interface Reply { arm: Arm; text: string; model: string | null; attempts: string[]; problems: string[]; outage: boolean; ms: number; codeIssues: string[] }
interface Row { case: CaseA; replies: Reply[]; judged?: Record<string, { score: number; register_ok: boolean; critical: string | null; why: string }> }
const rows: Row[] = [];
let stopped = '';
const judgeModels: string[] = [];

const conversationOf = (k: CaseA) => (k.history ?? []).map((t) => ({ role: t.role, text: t.text }));
async function replyOnce(k: CaseA, arm: Arm, i: number): Promise<Reply> {
  const a = ARMS[arm];
  const lean = ['status', 'invoice', 'report', 'code'].includes(k.kind);
  await guardSpend(c, lean ? EST[arm].lean : EST[arm].full, `${k.id} (${arm})`);
  const phone = 'whatsapp:+9715000000' + String(10 + (i % 90)).padStart(2, '0');
  const subject = { fixture: true, phone };
  const t0 = Date.now();
  if (k.kind === 'visitor') {
    const r = await inRun(() => aiReply(defaultDeps(admin, 'site_assistant'), {
      seat: 'customer_support', channel: 'the website chat widget', audience: 'visitor', lang: k.lang, message: k.message,
      conversation: conversationOf(k), taskClass: a.visitor, subject, deadline: Date.now() + 90_000,
      rules: 'Plain text for the chat widget, under about 90 words.' }));
    return { arm, text: r.reply, model: r.model, attempts: r.attempts, problems: r.problems ?? [], outage: r.outage === true, ms: Date.now() - t0, codeIssues: [] };
  }
  const audience = k.kind === 'supplier' ? 'supplier' as const : 'customer' as const;
  // the status lane's must: the references the database answer names (laneMust), and the case's own (the invoice link)
  const must = lean ? laneMust('status', String(k.facts ?? ''), k.lang).concat(k.must ?? []) : (k.must ?? []);
  const said = await inRun(() => modelSays(defaultDeps(admin, 'wa_inbound'), {
    audience, lang: k.lang, message: k.message, situation: k.facts ?? '', conversation: lean ? conversationOf(k).slice(-6) : conversationOf(k),
    subject, budgetMs: 90_000, must: [...new Set(must)],
    ...(lean ? { taskClass: a.status, briefInPrompt: false, laneRules: STATUS_RULES } : { taskClass: a.chat }),
  } as Parameters<typeof modelSays>[1]));
  return { arm, text: said.text, model: said.model, attempts: said.attempts, problems: said.problems ?? [], outage: said.outage, ms: said.ms, codeIssues: [] };
}

// CODE GRADES FIRST: must, language, deferral, an identity or contact not in the facts, an empty reply
function codeGrade(k: CaseA, r: Reply): string[] {
  const out: string[] = [];
  if (!r.text) { out.push(r.outage ? 'no reply (outage)' : 'no reply'); return out; }
  const want = k.kind === 'supplier' ? 'en' : k.lang;
  const s = scriptOf(r.text);
  if (want === 'ar' && s === 'en') out.push('wrong language: English to an Arabic writer');
  if (want === 'en' && s !== 'en') out.push('wrong language: Arabic to an English writer or supplier');
  for (const m of [...new Set(k.must ?? [])]) if (!r.text.includes(m)) out.push('must left out: ' + m);
  if (DEFERRAL.test(r.text)) out.push('a deferral');
  if (/ZZ DEMO (?!Eval Customer|Eval Gypsum)/.test(r.text)) out.push('identity leak');
  const emails = (r.text.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g) ?? []).filter((e) => !/quotesdone\.com$/i.test(e));
  if (emails.length) out.push('a contact not in the facts: ' + emails.join(','));
  return out;
}

try {
  if (REJUDGE) rows.push(...(JSON.parse(await Deno.readTextFile(REJUDGE)).rows as Row[]).map((r) => ({ case: r.case, replies: r.replies })));
  for (const [i, k] of (REJUDGE ? [] : CASES_A.slice(0, LIMIT)).entries()) {
    const row: Row = { case: k, replies: [] };
    rows.push(row);
    for (const arm of (i % CONTROL_EVERY === 0 ? ['candidate', 'control'] : ['candidate']) as Arm[]) {
      const r = await replyOnce(k, arm, i);
      r.codeIssues = codeGrade(k, r);
      row.replies.push(r);
      console.log(`${k.id} ${arm.padEnd(9)} ${String(r.model).padEnd(28)} ${r.ms}ms ${r.codeIssues.length ? 'ISSUES ' + r.codeIssues.join('; ') : 'ok'} | ${r.text.replace(/\s+/g, ' ').slice(0, 110)}`);
    }
  }
  // THE JUDGE: Sonnet 5.5 through the review router, never the model under test; 10 cases a call, blind labels
  const deps = defaultDeps(admin, JUDGE_FN);
  // THE JUDGE SEES WHAT THE WRITERS SAW (run 1, qd_run:evala0a9b8fd97b2: the judge had only each case's summary and marked
  // true brief facts, "no cap", "not VAT-registered", as invented, on both arms). The company brief rides as its cached block.
  const { companyBrief } = await import('../../../supabase/functions/_shared/company_brief.ts');
  // ...and a supplier turn's writer also had the supplier how-to (company_brief.ts {supplier: true}); run 3's one critical,
  // "up to 20 options" and "Inquiries received" on Job 7731, is written in it, and the judge had not been shown it
  const { BRIEF_SUPPLIER } = await import('../../../supabase/functions/_shared/brief.generated.ts');
  const brief = (await companyBrief(deps.rpc, [], '', 'en')) + '\n\nSUPPLIER HOW-TO (what a reply to a SUPPLIER may also use):\n' + BRIEF_SUPPLIER;
  for (let b = 0; b < rows.length; b += 10) {
    const batch = rows.slice(b, b + 10);
    await guardSpend(c, EST.judge, 'judge batch ' + (b / 10 + 1));
    const label = new Map<string, Reply>();
    const items = batch.map((row) => {
      const reps = [...row.replies].sort(() => Math.random() - 0.5);
      return { id: row.case.id, register: row.case.register, writer_language: row.case.kind === 'supplier' ? 'English (suppliers are always answered in English)' : row.case.lang === 'ar' ? 'Arabic' : 'English',
        message: row.case.message, facts_to_convey: row.case.expect, facts: String(row.case.facts ?? '(the company brief)').slice(0, 1200),
        replies: reps.map((r, j) => { const l = row.case.id + ':R' + (j + 1); label.set(l, r); return { label: l, text: r.text || '(no reply)' }; }) };
    });
    const sys = `You grade customer-service replies written for QuotesDone, a UAE procurement marketplace, by an expert human standard. For EACH reply label give:
score 0-10 (10 = a senior UAE procurement support agent would send it as is: answers exactly what was asked, conveys the facts given, nothing invented, warm and natural).
A statement the COMPANY BRIEF below (or the case's facts) supports is NOT invented; judge invention only against them,
register_ok true when it is in the writer's language (Arabic for an Arabic or Arabizi writer, English for English and for every supplier) and reads naturally to that writer (formal Gulf Arabic is acceptable for any Arabic dialect),
critical: null, or one of "wrong_status_or_reference", "invented_figure", "wrong_language", "identity_leak", "deferral", "wrong_fact".
Return ONE JSON object: {"grades":[{"label":"<label>","score":<n>,"register_ok":<bool>,"critical":<null|string>,"why":"<one short sentence>"}]}`;
    const res = await E2E_RUN.run({ tag, secret }, () => deps.llm('synthesise', sys, JSON.stringify(items), { taskClass: 'knowledge_validation', seat: 'it_engineer',
      counterpartModel: LUNA, max: 4000, subject: { fixture: true }, sysStable: 'COMPANY BRIEF (the published facts every reply may use):\n' + brief }));
    let grades: { label: string; score: number; register_ok: boolean; critical: string | null; why: string }[] = [];
    try { const t = String(res.content ?? ''); grades = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)).grades ?? []; } catch { /* reported below */ }
    console.log(`judge batch ${b / 10 + 1}: ${res.model ?? res.error} ${grades.length} grades`);
    for (const g of grades) {
      const r = label.get(g.label); if (!r) continue;
      const row = batch.find((x) => g.label.startsWith(x.case.id + ':'))!;
      (row.judged ??= {})[r.arm] = { score: Number(g.score), register_ok: g.register_ok === true, critical: g.critical ?? null, why: String(g.why ?? '') };
    }
    judgeModels.push(res.model ?? 'none: ' + String(res.error ?? '').slice(0, 80));
  }
} catch (e) {
  if (e instanceof CapReached) stopped = e.message; else { stopped = 'error: ' + String((e as Error)?.message ?? e); }
} finally {
  await closeWindow(admin, tag).catch(() => {});
}

// THE VERDICT
const cand = rows.flatMap((r) => r.replies.filter((x) => x.arm === 'candidate').map((x) => ({ row: r, x })));
const ctrl = rows.flatMap((r) => r.replies.filter((x) => x.arm === 'control').map((x) => ({ row: r, x })));
const rewrites = (x: Reply) => x.attempts.some((a) => /^rewrite:/.test(a));
// the reply the person gets came from the second rung: its model is not the arm's (lv-s1 in run 3: route ok, two refused rewrites,
// then the other family's answer; the first definition, "no route:ok", missed it)
const secondRung = (x: Reply) => !!x.model && x.model !== ARMS[x.arm].model;
const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN;
const judgedC = cand.filter((p) => p.row.judged?.candidate);
const paired = rows.filter((r) => r.judged?.candidate && r.judged?.control);
const crit = cand.filter((p) => p.x.codeIssues.length || p.row.judged?.candidate?.critical);
const spend = await (await import('./harness.ts')).spentUsd(admin, tag);
const m = {
  cases: rows.length, candidate_replies: cand.length, control_replies: ctrl.length,
  critical_errors: crit.length, critical_list: crit.map((p) => p.row.case.id + ': ' + [...p.x.codeIssues, p.row.judged?.candidate?.critical].filter(Boolean).join('; ')),
  must_present_pct: 100 * cand.filter((p) => (p.row.case.must ?? []).every((mu) => p.x.text.includes(mu))).length / Math.max(1, cand.length),
  rewrite_rate_pct: 100 * cand.filter((p) => rewrites(p.x)).length / Math.max(1, cand.length),
  second_rung_rate_pct: 100 * cand.filter((p) => secondRung(p.x)).length / Math.max(1, cand.length),
  register_pct: 100 * judgedC.filter((p) => p.row.judged!.candidate.register_ok && !p.x.codeIssues.some((i) => /language/.test(i))).length / Math.max(1, judgedC.length),
  judge_mean_candidate: mean(judgedC.map((p) => p.row.judged!.candidate.score)),
  judge_mean_candidate_paired: mean(paired.map((r) => r.judged!.candidate.score)),
  judge_mean_control_paired: mean(paired.map((r) => r.judged!.control.score)),
  judged_candidate: judgedC.length, paired: paired.length, judge_models: judgeModels,
  candidate_models: [...new Set(cand.map((p) => p.x.model))], control_models: [...new Set(ctrl.map((p) => p.x.model))],
  spend_usd: Number(spend.toFixed(4)), cap_usd: CAP, run_tag: 'qd_run:' + tag, stopped: stopped || null,
};
const pass = !stopped && m.cases === Math.min(LIMIT, CASES_A.length) && m.critical_errors === 0 && m.must_present_pct === 100 && m.rewrite_rate_pct <= 15
  && m.second_rung_rate_pct <= 5 && m.register_pct >= 95 && m.judged_candidate === m.candidate_replies && m.judge_mean_candidate >= 8.0
  && m.judge_mean_candidate_paired >= m.judge_mean_control_paired - 0.5;
await writeJson(OUT, { eval: 'A', at: new Date().toISOString(), pass, metrics: { ...m, ...(REJUDGE ? { rejudged_from: REJUDGE } : {}) }, rows });
console.log(JSON.stringify({ pass, ...m }, null, 1));
Deno.exit(pass ? 0 : 1);

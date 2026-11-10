// EVAL C: QWEN 3.8 FLASH AS THE REVIEWER OF OPENAI AUTHORS (it_engineer, cost seat; 10 Nov 2026; ruling 1571; design
// docs/reports/2026-11-10-design-model-routing.md section 5c). It gates the reviewer half of
// scripts/sql/customer_chat_and_the_reviewer_move_once_their_evals_pass.sql (knowledge_validation > Qwen 3.8 Flash).
//
// 60 drafts, labels known by construction: 30 clean and 30 seeded with ONE known defect each, six of each kind (a figure the
// facts do not state, a policy error, the wrong language, another party's identity before a reveal, a deferral), in English
// and Arabic. The reviewer sees the facts, the rules and the draft, and returns {"ok":bool,"problems":[...]}.
// PASS: >= 28 of 30 defects flagged, <= 3 of 30 clean drafts flagged. No control is needed: the truth is the construction.
//
// TWO DOORS.
//   --via openrouter (default until part 1 is applied). Qwen 3.8 Flash is not in model_registry yet, so the gateway cannot
//      route to it. The call goes to OpenRouter's chat API with the estate's own key, read here from app_secrets and never
//      printed, and EVERY call is written to ai_cost_log with this run's e2e_run_tag and OpenRouter's reported cost, so the
//      window's cap and this script's cap both see it. Nothing else is written.
//   --via gateway (after part 1 and the reviewer move): knowledge_validation with counterpart_model = Luna Pro through the live
//      gateway; the run refuses to grade unless the reviewer that answered is Qwen 3.8 Flash.
//
//   deno run -A --node-modules-dir=none scripts/eval/model_routing/eval_c.ts --cap 0.30 [--via openrouter|gateway]
//     [--out docs/reports/model-routing-evals-2026-11-10/eval_c.json]
import { arg, CapReached, closeWindow, connect, guardSpend, newTag, openWindow, spentUsd, writeJson, type Ctx } from './harness.ts';
import { JUDGE_FN } from './harness.ts';
import { CASES_C } from './cases_c.ts';

const CAP = Number(arg('--cap') ?? '0.30');
const VIA = (arg('--via') ?? 'openrouter') as 'openrouter' | 'gateway';
const OUT = arg('--out') ?? 'docs/reports/model-routing-evals-2026-11-10/eval_c.json';
const QWEN = 'qwen/qwen3.8-flash', LUNA = 'openai/gpt-6-luna-pro';
const EST = 0.002;

const { admin, secret } = await connect();
const tag = newTag('evalc');
const c: Ctx = { admin, tag, secret, capUsd: CAP };

const SYS = `You are QuotesDone's independent reviewer. A draft reply to a customer or supplier was written by another model. Check it against the FACTS and these RULES, and nothing else:
1. Every money figure, percentage, count or date in the draft is one the FACTS state.
2. Policy: no card fee is ever added; no VAT is charged on the reveal fee; a refund is never promised; liability is never accepted.
3. Language: the draft is in the REPLY LANGUAGE given (suppliers are always answered in English).
4. Identity: no supplier or customer name, phone, e-mail or licence number appears unless the FACTS give it as the reader's own.
5. It answers: it never defers ("I'll check", "we will get back to you", "I don't know").
Return ONE JSON object: {"ok": <true when the draft breaks none of the rules>, "problems": ["<rule number>: <what is wrong>", ...]}`;

let key = '';
if (VIA === 'openrouter') {
  key = String((await admin.from('app_secrets').select('value').eq('key', 'openrouter_api_key').maybeSingle()).data?.value ?? '');
  if (!key) throw new Error('openrouter_api_key could not be read');
}
const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
const { shapeRequest } = await import('../../../supabase/functions/_shared/request_shape.ts');
const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');

async function review(input: string): Promise<{ content: string; model: string | null; error?: string }> {
  if (VIA === 'gateway') {
    const r = await E2E_RUN.run({ tag, secret }, () => defaultDeps(admin, JUDGE_FN).llm('verify', SYS, input,
      { taskClass: 'knowledge_validation', seat: 'it_engineer', counterpartModel: LUNA, max: 600, subject: { fixture: true } }));
    return { content: String(r.content ?? ''), model: r.model ?? null, error: r.error ?? undefined };
  }
  const t0 = Date.now();
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', signal: AbortSignal.timeout(60_000),
    headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json', 'X-Title': 'QuotesDone eval C' },
    // THE REQUEST THE GATEWAY WOULD SEND (request_shape.ts shapeRequest): a reasoning model gets its thinking headroom on top of the
    // answer budget. The first run (qd_run:evalcb15dab8889e) sent max_tokens 600 flat and 10 of 60 answers came back empty.
    body: JSON.stringify({ model: QWEN, ...shapeRequest({ model: QWEN, maxTokens: 600, temperature: 0, responseFormat: { type: 'json_object' },
      supported: new Set(['reasoning', 'response_format', 'structured_outputs', 'tools']) }), usage: { include: true },
      messages: [{ role: 'system', content: SYS }, { role: 'user', content: input }] }) });
  const j = await res.json().catch(() => null) as { choices?: { message?: { content?: string } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number }; model?: string; id?: string; error?: { message?: string } } | null;
  const content = String(j?.choices?.[0]?.message?.content ?? '');
  const finish = String((j?.choices?.[0] as { finish_reason?: string } | undefined)?.finish_reason ?? '');
  // THE SPEND IS RECORDED WHERE THE CAPS READ IT: ai_cost_log, this run's tag, OpenRouter's own cost
  const { error } = await admin.from('ai_cost_log').insert({ fn: JUDGE_FN, agent_key: 'it_engineer', seat: 'it_engineer', task_class: 'knowledge_validation',
    model_used: j?.model ?? QWEN, model_selected_because: 'eval C (ruling 1571): ' + QWEN + ' asked directly, not yet in model_registry; counterpart ' + LUNA,
    tier: 'small', prompt_tokens: j?.usage?.prompt_tokens ?? 0, output_tokens: j?.usage?.completion_tokens ?? 0, cached: false, ok: res.ok && !!content,
    cost_usd_reported: Number(j?.usage?.cost ?? 0), e2e_run_tag: tag, counterpart_model: LUNA, latency_ms: Date.now() - t0, generation_id: j?.id ?? null });
  if (error) throw new Error('the cost row could not be written, the run stops: ' + error.message);
  return { content, model: j?.model ?? null, error: res.ok ? (content ? undefined : 'empty answer, finish_reason ' + finish) : 'HTTP ' + res.status + ' ' + String(j?.error?.message ?? '').slice(0, 120) };
}

await openWindow(admin, tag, CAP, 45, 'eval C, model routing (ruling 1571): Qwen 3.8 Flash as the reviewer of 60 drafts');
console.log(`eval C via ${VIA}: run tag qd_run:${tag}, cap USD ${CAP}`);
const rows: { id: string; defect: string | null; flagged: boolean | null; problems: string[]; model: string | null; error?: string }[] = [];
let stopped = '';
try {
  for (const k of CASES_C) {
    await guardSpend(c, EST, k.id);
    const input = `REPLY LANGUAGE: ${k.lang === 'ar' ? 'Arabic' : 'English'}\nAUDIENCE: ${k.audience}\n\nFACTS:\n${k.facts}\n\nDRAFT:\n${k.draft}`;
    const r = await review(input);
    let v: { ok?: boolean; problems?: string[] } = {};
    try { v = JSON.parse(r.content.slice(r.content.indexOf('{'), r.content.lastIndexOf('}') + 1)); } catch { /* unparseable: flagged null */ }
    const flagged = typeof v.ok === 'boolean' ? !v.ok : null;
    if (VIA === 'gateway' && r.model && r.model !== QWEN) throw new Error(`the reviewer was ${r.model}, not ${QWEN}: this is not the eval of the swap`);
    rows.push({ id: k.id, defect: k.defect, flagged, problems: (v.problems ?? []).map(String).slice(0, 4), model: r.model, ...(r.error ? { error: r.error } : {}) });
    console.log(`${k.id.padEnd(10)} ${String(k.defect ?? 'clean').padEnd(9)} ${flagged === null ? 'UNREAD' : flagged ? 'FLAGGED' : 'passed'} ${(v.problems ?? []).join(' | ').slice(0, 120)}`);
  }
} catch (e) {
  stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e);
} finally {
  await closeWindow(admin, tag).catch(() => {});
}
const defects = rows.filter((r) => r.defect), clean = rows.filter((r) => !r.defect);
const byKind = Object.fromEntries([...new Set(defects.map((r) => r.defect!))].map((d) => [d, `${defects.filter((r) => r.defect === d && r.flagged === true).length}/${defects.filter((r) => r.defect === d).length}`]));
const m = { drafts: rows.length, defects_flagged: defects.filter((r) => r.flagged === true).length, defects: defects.length,
  clean_flagged: clean.filter((r) => r.flagged !== false).length, clean: clean.length, unread: rows.filter((r) => r.flagged === null).length, by_kind: byKind,
  models: [...new Set(rows.map((r) => r.model))], via: VIA, spend_usd: Number((await spentUsd(admin, tag)).toFixed(4)), cap_usd: CAP, run_tag: 'qd_run:' + tag, stopped: stopped || null };
const pass = !stopped && rows.length === CASES_C.length && m.defects === 30 && m.defects_flagged >= 28 && m.clean_flagged <= 3;
await writeJson(OUT, { eval: 'C', at: new Date().toISOString(), pass, metrics: m, rows });
console.log(JSON.stringify({ pass, ...m }, null, 1));
Deno.exit(pass ? 0 : 1);

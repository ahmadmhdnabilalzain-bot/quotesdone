// EVAL: THE LICENCE READER'S PLAN B READS A LICENCE (it_engineer; 15 Nov 2026; founder rulings 1696 and 1571; review of the
// self-healing branch, FIX 8). It gates public.it_route_plan_b for document_extraction and document_extraction_multimodal
// (scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql): qwen/qwen3.8-flash is recorded there by the CEO, NOT
// active, "pending one licence-read eval on ZZ DEMO licences". route_failover refuses it until this run passes and --record
// writes eval_passed_at, eval_ref and active = true (the table's check refuses active without both).
//
// THE CASES are ZZ DEMO trade licences built here (scripts/lib/demo_pdf.mjs demoTradeLicence: one page, every field invented and
// marked "QuotesDone fixture, not a real company"), so the truth is known by construction and no real supplier's document is read.
// THE READ is the reader's own request: SYS_LICENSE and documentContent from _shared/licence_extract.ts (the system prompt and the
// file part license_extract sends), asked of the plan B model directly on OpenRouter with the estate's key (read from app_secrets,
// never printed), every call written to ai_cost_log with this run's e2e_run_tag and OpenRouter's reported cost, inside a
// rehearsal window capped at --cap USD (harness.ts: the window's cap and this script's cap both stop it).
// PASS: every case answered; legal_name, license_number and expiry_date exact and document_kind trade_licence on at least n-1 of n;
// NO licence number that is wrong (a wrong number is worse than an unread one: the gate would run on it).
//
//   deno run -A --node-modules-dir=none scripts/eval/model_routing/eval_licence_plan_b.ts --cap 0.20 [--n 12] [--record]
//     [--out docs/reports/model-routing-evals-2026-11-15/eval_licence_plan_b.json]
//   --dry-run   no network and no database: a stub model answers the truth (and one case wrong with --dry-run-fail), to prove the
//               grading; run by scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs.
import { documentContent, normDate, parseJson, SYS_LICENSE } from '../../../supabase/functions/_shared/licence_extract.ts';
import { demoTradeLicence } from '../../lib/demo_pdf.mjs';

const argOf = (f: string): string | null => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] ?? null : null; };
const DRY = Deno.args.includes('--dry-run'), DRY_FAIL = Deno.args.includes('--dry-run-fail');
const PLAN_B = 'qwen/qwen3.8-flash';
const CLASSES = ['document_extraction', 'document_extraction_multimodal'];
const CAP = Number(argOf('--cap') ?? '0.20');
const N = Math.min(24, Math.max(4, Number(argOf('--n') ?? '12')));
const OUT = argOf('--out') ?? 'docs/reports/model-routing-evals-2026-11-15/eval_licence_plan_b.json';
const EST = 0.004;

type Case = { id: string; company: string; licenceNo: string; issue: string; expiry: string; activity: string };
const TRADES = ['Air Conditioning Units Manufacturing', 'Building Materials Trading', 'Joinery Works', 'Electrical Fittings Installation',
  'Aluminium and Glass Works', 'Landscaping Services', 'Signage Manufacturing', 'Plumbing and Sanitary Installation'];
export function licenceCases(n: number): Case[] {
  return Array.from({ length: n }, (_, i) => {
    const d = String(1 + ((i * 7) % 27)).padStart(2, '0'), m = String(1 + ((i * 5) % 12)).padStart(2, '0');
    return { id: 'zzlic' + String(i + 1).padStart(2, '0'), company: `ZZ DEMO - Plan B Reader ${i + 1} ${TRADES[i % TRADES.length].split(' ')[0]} LLC`,
      licenceNo: String(9900100 + i * 37), issue: `${d}/${m}/2025`, expiry: `${d}/${m}/${2027 + (i % 3)}`, activity: TRADES[i % TRADES.length] };
  });
}
const iso = (dmy: string) => { const [d, m, y] = dmy.split('/'); return `${y}-${m}-${d}`; };
const norm = (s: unknown) => String(s ?? '').toLowerCase().replace(/[\s–—-]+/g, ' ').trim();

export function grade(k: Case, ai: Record<string, unknown> | null) {
  const no = String(ai?.license_number ?? '').replace(/\s+/g, '');
  return {
    id: k.id, answered: !!ai,
    name_ok: norm(ai?.legal_name) === norm(k.company),
    number_ok: no === k.licenceNo,
    number_wrong: no !== '' && no !== k.licenceNo,
    expiry_ok: normDate(ai?.expiry_date) === iso(k.expiry),
    kind_ok: String(ai?.document_kind ?? '') === 'trade_licence',
  };
}
export function verdict(rows: ReturnType<typeof grade>[], n: number) {
  const exact = rows.filter((r) => r.name_ok && r.number_ok && r.expiry_ok && r.kind_ok).length;
  const wrongNumbers = rows.filter((r) => r.number_wrong).length;
  return { cases: n, answered: rows.filter((r) => r.answered).length, exact, wrong_numbers: wrongNumbers,
    pass: rows.length === n && rows.every((r) => r.answered) && exact >= n - 1 && wrongNumbers === 0 };
}

// deno-lint-ignore no-explicit-any
type Ask = (content: any[]) => Promise<{ content: string; model: string | null; error?: string }>;

async function run(ask: Ask, cases: Case[]) {
  const rows: ReturnType<typeof grade>[] = [];
  for (const k of cases) {
    const pdf = demoTradeLicence({ company: k.company, licenceNo: k.licenceNo, issue: k.issue, expiry: k.expiry, activity: k.activity });
    const content = documentContent('Read the attached UAE trade licence (all pages) and return the extraction JSON.', [],
      { file_b64: btoa(Array.from(new Uint8Array(pdf), (b) => String.fromCharCode(b)).join('')), mime: 'application/pdf', filename: k.id + '.pdf' });
    const r = await ask(content);
    const g = grade(k, parseJson(r.content));
    rows.push(g);
    console.log(`${k.id} ${g.name_ok && g.number_ok && g.expiry_ok && g.kind_ok ? 'EXACT' : 'MISS '} name ${g.name_ok} number ${g.number_ok}${g.number_wrong ? ' (WRONG)' : ''} expiry ${g.expiry_ok} kind ${g.kind_ok}${r.error ? ' ' + r.error : ''}`);
  }
  return rows;
}

if (import.meta.main) {
  const cases = licenceCases(N);
  if (DRY) {
    // THE STUB answers the truth, one case with a wrong number under --dry-run-fail; nothing leaves this machine
    let i = 0;
    const stub: Ask = async () => {
      const k = cases[i++];
      return { model: 'stub', content: JSON.stringify({ legal_name: k.company, license_number: DRY_FAIL && i === 2 ? '1234567' : k.licenceNo,
        expiry_date: iso(k.expiry), document_kind: 'trade_licence' }) };
    };
    const v = verdict(await run(stub, cases), cases.length);
    console.log(JSON.stringify({ dry_run: true, ...v }));
    Deno.exit(v.pass ? 0 : 1);
  }
  const { closeWindow, connect, guardSpend, newTag, openWindow, spentUsd, writeJson, CapReached, JUDGE_FN } = await import('./harness.ts');
  const { shapeRequest } = await import('../../../supabase/functions/_shared/request_shape.ts');
  const { admin, secret } = await connect();
  const tag = newTag('evallicb');
  const c = { admin, tag, secret, capUsd: CAP };
  const { data: reg } = await admin.from('model_registry').select('model_id,active,approved,supports_vision').eq('model_id', PLAN_B).maybeSingle();
  if (!reg?.active || !reg?.approved || !reg?.supports_vision) throw new Error(`${PLAN_B} is not an active, approved, vision model_registry row: ${JSON.stringify(reg)}`);
  const key = String((await admin.from('app_secrets').select('value').eq('key', 'openrouter_api_key').maybeSingle()).data?.value ?? '');
  if (!key) throw new Error('openrouter_api_key could not be read');
  const ask: Ask = async (content) => {
    await guardSpend(c, EST, 'one licence read');
    const t0 = Date.now();
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', signal: AbortSignal.timeout(90_000),
      headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json', 'X-Title': 'QuotesDone licence plan B eval' },
      body: JSON.stringify({ model: PLAN_B, ...shapeRequest({ model: PLAN_B, maxTokens: 8000, temperature: 0.1, responseFormat: { type: 'json_object' },
        supported: new Set(['reasoning', 'response_format', 'structured_outputs']) }), usage: { include: true },
        messages: [{ role: 'system', content: SYS_LICENSE }, { role: 'user', content }] }) });
    const j = await res.json().catch(() => null) as { choices?: { message?: { content?: string }; finish_reason?: string }[]; usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number }; model?: string; id?: string; error?: { message?: string } } | null;
    const text = String(j?.choices?.[0]?.message?.content ?? '');
    const { error } = await admin.from('ai_cost_log').insert({ fn: JUDGE_FN, agent_key: 'it_engineer', seat: 'it_engineer', task_class: 'document_extraction',
      model_used: j?.model ?? PLAN_B, model_selected_because: 'licence plan B eval (rulings 1696, 1571): ' + PLAN_B + ' asked directly on ZZ DEMO licences',
      tier: 'small', prompt_tokens: j?.usage?.prompt_tokens ?? 0, output_tokens: j?.usage?.completion_tokens ?? 0, cached: false, ok: res.ok && !!text,
      cost_usd_reported: Number(j?.usage?.cost ?? 0), e2e_run_tag: tag, latency_ms: Date.now() - t0, generation_id: j?.id ?? null });
    if (error) throw new Error('the cost row could not be written, the run stops: ' + error.message);
    return { content: text, model: j?.model ?? null, error: res.ok ? (text ? undefined : 'empty answer, finish_reason ' + String(j?.choices?.[0]?.finish_reason ?? '')) : 'HTTP ' + res.status + ' ' + String(j?.error?.message ?? '').slice(0, 120) };
  };
  await openWindow(admin, tag, CAP, 45, 'licence plan B eval (rulings 1696, 1571): ' + PLAN_B + ' reads ' + N + ' ZZ DEMO licences');
  console.log(`licence plan B eval: ${PLAN_B}, run tag qd_run:${tag}, cap USD ${CAP}, ${N} ZZ DEMO licences`);
  let rows: ReturnType<typeof grade>[] = [], stopped = '';
  try { rows = await run(ask, cases); } catch (e) { stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e); }
  finally { await closeWindow(admin, tag).catch(() => {}); }
  const v = verdict(rows, N);
  const pass = v.pass && !stopped;
  const m = { ...v, pass, model: PLAN_B, spend_usd: Number((await spentUsd(admin, tag)).toFixed(4)), cap_usd: CAP, run_tag: 'qd_run:' + tag, stopped: stopped || null };
  await writeJson(OUT, { eval: 'licence_plan_b', at: new Date().toISOString(), metrics: m, rows });
  console.log(JSON.stringify(m, null, 1));
  if (pass && Deno.args.includes('--record')) {
    // THE ONLY WRITE OF A PASS: the CEO's recorded plan B becomes usable by route_failover, with its evidence
    const { error } = await admin.from('it_route_plan_b').update({ active: true, eval_passed_at: new Date().toISOString(), eval_ref: OUT + ' (qd_run:' + tag + ')' })
      .in('task_class', CLASSES).eq('plan_b_model', PLAN_B);
    if (error) throw new Error('the plan B could not be activated: ' + error.message);
    console.log('plan B activated for ' + CLASSES.join(', '));
  }
  Deno.exit(pass ? 0 : 1);
}

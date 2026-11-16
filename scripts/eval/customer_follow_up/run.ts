// THE CUSTOMER FOLLOW-UP EVAL, PAID, ONCE (customer_support, 16 Nov 2026; founder ledger 1711).
//
// Each scenario of scripts/eval/customer_follow_up_bank.mjs is answered by the WhatsApp reply path's model exactly as a turn is
// composed in production: wa_inbound/compose.ts composeSituation on the scenario's route (fn_wa_route_dry for the intent the bank
// states: its deterministic_reply and needs_a_person; the customer audience block with OWN_REQUEST_RULE, his own record, the fact
// pack, the live company block) and wa_inbound/model_says.ts modelSays (the conversation path: the company
// brief, the model chain, the figure and reply guard), through the production gateway. Then a judge of ANOTHER model family
// (knowledge_validation with counterpart_model = the replying model, the gateway's review router; model_routing/harness.ts)
// grades it against the scenario's must / must-not, and the bank's code grader checks figures and identities. A scenario
// passes only when both pass.
//
// THE FACTS COME FROM A LOCAL DATABASE, never production: run the bank's check with a local database first, which writes the
// WhatsApp fact pack and the own record of the ZZ DEMO fixture to a file outside the repository:
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<local url> QD_CASEFACTS_OUT=<scratch>/facts.json \
//     node --test scripts/checks/a_customer_is_answered_from_his_whole_request.test.mjs
// then, within the hour (the facts' due times are relative to that run):
//   deno run --no-lock --node-modules-dir=none -A scripts/eval/customer_follow_up/run.ts --facts <scratch>/facts.json --paid [--cap 1.5] [--only id,id]
//
// WHAT IT TOUCHES ON PRODUCTION: a rehearsal_window row for its run tag (opened and closed here), the ai_cost_log rows its
// own calls make, and read-only reads (fn_ai_route, fn_company_context, fn_price_brief). Every other routine a reply asks for
// is answered by a stub; the subject is {fixture: true} and the number a reserved fixture number, so nothing is sent.
// THE CAP: refused without --paid; --cap at most USD 1.50; spend + the next call's estimate is checked before EVERY call
// (guardSpend) and the gateway's window enforces the same cap.
// COST, stated before it runs: a conversation reply ~23k tokens in (~20k cached) and ~300 out on the conversation_reply class
// (claude-sonnet-5.5, USD 2 / 10 per Mtok, 0.10 cached): ~USD 0.012, plus one cache write ~USD 0.05; a judge ~6k in, ~250 out
// on another family: ~USD 0.01. 45 scenarios: about USD 1.0.
import { arg, CapReached, closeWindow, connect, flag, guardSpend, JUDGE_FN, newTag, openWindow, spentUsd, writeJson, type Ctx } from '../model_routing/harness.ts';
import { SCENARIOS, SUPPLIERS, CUSTOMER, TIMELINE, codeGrade } from '../customer_follow_up_bank.mjs';
import type { ThinkDeps } from '../../../supabase/functions/_shared/think.ts';

export const MAX_CAP_USD = 1.5;
const REPLY_EST = 0.03, JUDGE_EST = 0.02;
const READ_ONLY: ReadonlySet<string> = new Set(['fn_ai_route', 'fn_company_context', 'fn_price_brief', 'fn_e2e_run_tag_open']);

if (import.meta.main) {
  const PAID = flag('--paid');
  const CAP = Number(arg('--cap') ?? String(MAX_CAP_USD));
  const FACTS = arg('--facts');
  const OUT = arg('--out') ?? 'docs/reports/customer-follow-up-eval-2026-11-16/run.json';
  const ONLY = arg('--only')?.split(',') ?? null;
  const list = SCENARIOS.filter((s: { id: string }) => !ONLY || ONLY.includes(s.id));
  console.log(`customer follow-up eval: ${list.length} scenarios; estimate about USD ${(list.length * 0.022 + 0.05).toFixed(2)}; cap USD ${CAP}`);
  if (!PAID) { console.error('refused: this eval calls paid models; pass --paid to run it (and --facts <file>)'); Deno.exit(2); }
  if (!(CAP > 0 && CAP <= MAX_CAP_USD)) { console.error(`refused: the cap is at most USD ${MAX_CAP_USD} (the brief); got ${CAP}`); Deno.exit(2); }
  if (!FACTS) { console.error('refused: --facts <file> (written by the bank check against a LOCAL database)'); Deno.exit(2); }
  const facts = JSON.parse(await Deno.readTextFile(FACTS)) as { refs: Record<string, number>; pack: Record<string, unknown>; mine: Record<string, unknown>;
    routes?: Record<string, Record<string, unknown>> };
  if ((facts.pack as { identity?: { kind?: string } }).identity?.kind !== 'customer') throw new Error('the facts file holds no customer pack');
  // REVIEW 16 Nov: the reply is composed on the scenario's ROUTE (deterministic_reply, needs_a_person), as production composes it
  const noRoute = list.filter((s: { id: string }) => !facts.routes?.[s.id]).map((s: { id: string }) => s.id);
  if (noRoute.length) { console.error(`refused: the facts file has no route for ${noRoute.slice(0, 5).join(', ')}; regenerate it with the bank check`); Deno.exit(2); }

  const { admin, secret } = await connect();
  const { defaultDeps } = await import('../../../supabase/functions/_shared/think.ts');
  const { E2E_RUN } = await import('../../../supabase/functions/_shared/e2e_run.ts');
  const { composeSituation } = await import('../../../supabase/functions/wa_inbound/compose.ts');
  const { modelSays } = await import('../../../supabase/functions/wa_inbound/model_says.ts');
  if ((globalThis as { __qdE2eFetch?: boolean }).__qdE2eFetch !== true) throw new Error('the run-tag forwarder is not installed: a paid call would go out untagged; nothing was run');

  const tag = newTag('evalcf');
  const c: Ctx = { admin, tag, secret, capUsd: CAP };
  const live = defaultDeps(admin, 'wa_inbound');
  const deps: ThinkDeps = {
    ...live,
    gate: () => Promise.resolve({ allowed: true } as never),   // the gateway itself still enforces every hold and the window's cap
    rpc: (fn, a) => READ_ONLY.has(fn) ? live.rpc(fn, a) : Promise.resolve({ data: null, error: null }),
    llm: async (phase, system, input, o) => { await guardSpend(c, REPLY_EST, 'reply ' + phase); return live.llm(phase, system, input, { ...o, rateKey: undefined }); },
  };
  const inRun = <T>(f: () => Promise<T>) => E2E_RUN.run({ tag, secret }, f);
  const company = await inRun(() => live.rpc('fn_company_context', { p_max_chars: 6000, p_audience: 'public' }));
  const sealed = Object.entries(SUPPLIERS).filter(([k]) => k !== 's5').map(([, n]) => n as string);
  const JUDGE_SYS = `You judge one reply a UAE procurement marketplace's support agent sent a customer on WhatsApp about his own request. You get the customer's
message, the facts the agent had (his requests: what he asked, each quote's letter, price before and with VAT, lead time, warranty, validity, the sales
engineer's notes and the request thread), what a correct answer must and must not contain, and the reply. Judge ONLY against the facts and the criteria:
the reply passes when it answers his question correctly from the facts in his language, states no price, date, count or brand the facts do not hold,
names or hints at no supplier that is not revealed, and takes the right action (a change or cancel is never claimed as done). Wording is free; a reply
that says more than the criteria is fine if it is true. His OTHER requests are in all_his_requests: a reply that mentions one of them truthfully
invents nothing. What the company brief says about QuotesDone itself is true too: the reveal fee is 3% of the chosen quote before VAT with no card fee
and no VAT on the fee, comparing is free, refunds are decided by the CEO, and he reveals a quote in his portal to get the supplier's contact. Return ONE JSON object: {"pass": <bool>, "why": "<one sentence>", "invented": ["<figure or claim not in the facts>"], "identity_leak": <bool>}`;

  const results: Record<string, unknown>[] = []; let stopped = '';
  await openWindow(admin, tag, CAP, 60, 'customer follow-up scenario bank (ledger 1711): WhatsApp reply path + another-family judge; ZZ DEMO facts from a local database');
  console.log('run tag qd_run:' + tag);
  try {
    for (const [i, sc] of list.entries()) {
      const t = { audience: 'customer', known: { audience: 'customer', name: CUSTOMER.name },
        prefetch: { timeline: Promise.resolve({ data: sc.timeline ? { event_count: TIMELINE.length, events: TIMELINE } : null }), mine: Promise.resolve({ data: facts.mine }), company: Promise.resolve(company),
          faq: Promise.resolve({ ctx: '', ids: [] as number[] }) } };
      // deno-lint-ignore no-explicit-any
      const { situation } = await composeSituation(t as any, { ...facts.routes![sc.id], fact_pack: facts.pack });
      const lang = /[؀-ۿ]/.test(sc.msg) ? 'ar' : 'en';
      const said = await inRun(() => modelSays(deps, { audience: 'customer', lang, message: sc.msg, situation,
        subject: { fixture: true, phone: 'whatsapp:' + CUSTOMER.phone, scenario: sc.id }, forbidden: sealed, budgetMs: 90_000 }));
      const code = codeGrade(sc, said.text);
      const req = ((facts.pack as { identity: { requests: { ref: number }[] } }).identity.requests).find((r) => r.ref === facts.refs[sc.req]);
      await guardSpend(c, JUDGE_EST, 'judge ' + sc.id);
      const all = (facts.pack as { identity: { requests: Record<string, unknown>[] } }).identity.requests
        .map((r) => ({ ref: r.ref, category: r.category, emirate: r.emirate, status: r.status, quotes_received: r.quotes_received, budget: (r.asked as Record<string, unknown> | undefined)?.budget_as_he_stated_it }));
      const judgeOnce = () => inRun(() => defaultDeps(admin, JUDGE_FN).llm('verify', JUDGE_SYS, JSON.stringify({ message: sc.msg, action: sc.action,
        criteria: sc.judge, ...(sc.timeline ? { timeline: TIMELINE } : {}), must_not: [...(sc.must_not ?? []), 'the name of any supplier not revealed'],
        facts_for_this_request: req, all_his_requests: all, reply: said.text || '(no reply)' }),
        { taskClass: 'knowledge_validation', seat: 'it_engineer', counterpartModel: said.model ?? 'anthropic/claude-sonnet-5.5', max: 800, subject: { fixture: true } }));
      let j = await judgeOnce();
      // a judge cut at the gateway's deadline is asked once more (the reply is not asked again)
      if (!j.content) { await guardSpend(c, JUDGE_EST, 'judge again ' + sc.id); j = await judgeOnce(); }
      let v: Record<string, unknown> = {};
      try { const s = String(j.content ?? ''); v = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)); } catch { v = { pass: false, why: 'judge unread: ' + String(j.content ?? j.error).slice(0, 160) }; }
      const pass = !!said.text && code.pass && v.pass === true && v.identity_leak !== true;
      results.push({ id: sc.id, lang: sc.lang, req: sc.req, action: sc.action, message: sc.msg, reply: said.text, model: said.model, attempts: said.attempts.length,
        code, judge: v, judge_model: j.model ?? null, pass });
      console.log(`${String(i + 1).padStart(2)} ${pass ? 'PASS' : 'FAIL'} ${sc.id} [${said.model ?? '-'} / ${j.model ?? '-'}] ${pass ? '' : JSON.stringify({ code: code.pass ? 'ok' : code, judge: v.why })}`);
    }
  } catch (e) { stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e); console.error(stopped); }
  finally { await closeWindow(admin, tag).catch(() => {}); }
  const usd = await spentUsd(admin, tag).catch(() => NaN);
  const summary = { scenarios: list.length, run: results.length, passed: results.filter((r) => r.pass).length, usd: Number(usd.toFixed(4)), cap_usd: CAP,
    run_tag: 'qd_run:' + tag, stopped: stopped || null, at: new Date().toISOString() };
  await writeJson(OUT, { summary, results });
  console.log(JSON.stringify(summary));
  Deno.exit(stopped ? 1 : 0);
}

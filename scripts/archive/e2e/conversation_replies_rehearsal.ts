// conversation_replies_rehearsal — measures the model-written conversation replies (rulings 1195/1196/1197) LIVE, on
// ZZ DEMO subjects only, inside a tagged rehearsal window capped at USD 2. Seat: customer_support (WhatsApp turns) and
// sales_engineer (the quotation chat). It runs the SAME writer the functions run (wa_inbound/model_says.ts →
// _shared/ai_reply.ts, and the quotation chat's voice → aiReply with actions) against the production ai_gateway,
// with the run tag and its internal proof on every call so fn_kernel_paid_provider_gate lets ONLY these calls past
// the hold and stops them at the cap. No message is sent to anyone: there is no Twilio and no portal write here.
//
//   QD_FIXTURES=1 deno run -A --no-lock --node-modules-dir=auto scripts/archive/e2e/conversation_replies_rehearsal.ts
//
// Measured per turn: reply time (ms), which model answered, attempts, and quality — the reply guard and the figure
// check (replyProblems against the live brief), the language rule (customers in their language, suppliers English),
// for the quotation chat the action read, and a judge score 1-5 from a model of another family.
import { newRun, keys, internalCred, BASE, REF, closeRehearsalWindow } from '../../lib/demo_factory.mjs';
import { mgmtFixture, mgmtRead } from '../../lib/qd_guard.mjs';
import { modelSays } from '../../../supabase/functions/wa_inbound/model_says.ts';
import { aiReply, replyProblems } from '../../../supabase/functions/_shared/ai_reply.ts';
import { briefNumbers, companyBrief, figureSource } from '../../../supabase/functions/_shared/company_brief.ts';
import type { ThinkDeps } from '../../../supabase/functions/_shared/think.ts';

const CAP_USD = 2;
const run = newRun({});
const TAG = run.tag;
const { SERVICE } = await keys();
const xcred = await internalCred();
const gw = (await mgmtRead(REF, `select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value;
if (!gw) throw new Error('no gateway credential');
const AR = /[؀-ۿ]/;

const deps: ThinkDeps = {
  gate: () => Promise.resolve(null),
  llm: async (_phase: string, system: string, input: string, o: Record<string, unknown> & { seat?: string; taskClass?: string; max?: number; subject?: Record<string, unknown>; counterpartModel?: string }) => {
    const r = await fetch(`${BASE}/functions/v1/ai_gateway`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': xcred },
      body: JSON.stringify({ __secret: gw, fn: o.seat === 'sales_engineer' ? 'supplier_api' : 'wa_inbound', task_class: o.taskClass, agent: o.seat, sys: system, input, max: o.max ?? 700,
        client_timeout_ms: 50_000, cache_ttl_min: 0, subject: o.subject ?? { fixture: true }, ...(o.counterpartModel ? { counterpart_model: o.counterpartModel } : {}) }),
      signal: AbortSignal.timeout(60_000),
    }).catch((e) => ({ ok: false, json: () => Promise.resolve({ error: String(e) }) } as unknown as Response));
    const j = await r.json().catch(() => ({}));
    return { content: j?.content ?? null, model: j?.model ?? j?.model_used ?? null, error: j?.error ?? null };
  },
  embed: () => Promise.resolve(null),
  rpc: async (f: string, args?: Record<string, unknown>) => {
    const r = await fetch(`${BASE}/rest/v1/rpc/${f}`, { method: 'POST', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/json' }, body: JSON.stringify(args ?? {}) });
    return r.ok ? { data: await r.json().catch(() => null), error: null } : { data: null, error: { message: 'HTTP ' + r.status } };
  },
} as unknown as ThinkDeps;

type Case = { id: string; surface: string; lang: 'en' | 'ar'; audience: 'customer' | 'supplier' | 'visitor' | 'founder'; message: string; situation: string; actions?: { id: string; meaning: string }[]; expectAction?: string | null };
const WA_FIX = { fixture: true, phone: '+971500000021' };
const CASES: Case[] = [
  { id: 'W1', surface: 'whatsapp.main', lang: 'en', audience: 'visitor', message: 'ZZ DEMO: how much does it cost me to get quotes for a villa pool?', situation: 'A visitor asked a question; no account matches this number. Answer it.' },
  { id: 'W2', surface: 'whatsapp.main', lang: 'ar', audience: 'customer', message: 'ZZ DEMO: كم رسوم الكشف عن هوية المورد؟', situation: 'A registered customer asked about the reveal fee. Answer from the brief.' },
  { id: 'W3', surface: 'whatsapp.main', lang: 'ar', audience: 'supplier', message: 'ZZ DEMO: هل أدفع عمولة على المشاريع؟', situation: 'A registered supplier (ZZ DEMO Trading LLC) asked whether they pay commission.' },
  { id: 'W4', surface: 'whatsapp.menu_option', lang: 'en', audience: 'customer', message: '(menu option)', situation: 'They chose the menu option "qd_follow". Tell them this in your own words, keeping every link, reference, status and hour exactly:\nYour open requests:\n- Job 151767: Sent to suppliers, awaiting quotes\nTo see it: https://quotesdone.com/me?r=zz' },
  { id: 'W5', surface: 'whatsapp.spec_offer', lang: 'ar', audience: 'customer', message: '7', situation: 'Their reply did not match any of the 2 numbered alternatives we offered. Ask them to reply with the option number (1 to 2), or NO to decline them all.' },
  { id: 'W6', surface: 'whatsapp.document', lang: 'en', audience: 'supplier', message: '(no caption)', situation: 'Their document was received; their trade licence is on file and their record was updated (licence no ZZDEMO-0001, expiry 2027-06-24). They can check it any time at https://quotesdone.com/suppliers.' },
  { id: 'W7', surface: 'whatsapp.founder_setting', lang: 'en', audience: 'founder', message: 'set weekly invite cap to 15', situation: 'The settings routine ran on his instruction. Its result, to report accurately:\n{"ok":true,"key":"invite_weekly_cap","old":"10","new":"15"}' },
  { id: 'W8', surface: 'whatsapp.size_question', lang: 'ar', audience: 'visitor', message: 'كم عدد الموردين لديكم؟', situation: 'They asked about our size or volumes. Never give any count or figure about suppliers, customers, requests, quotes or revenue. Say what we do: we match each quotation request to verified suppliers across the UAE in the exact trade.' },
];
const QR_ACTIONS = [{ id: 'generate', meaning: 'they want us to generate the standardised quotation for them from what they sent' },
                    { id: 'reupload', meaning: 'they will upload a new version of their own quotation' }];
const QR: Case[] = [
  { id: 'Q1', surface: 'quote_review.message', lang: 'en', audience: 'supplier', message: 'please make the standard quotation for me', actions: QR_ACTIONS, expectAction: 'generate',
    situation: 'You are the sales engineer reviewing this supplier\'s quotation for Job 151767. STATE: awaiting_choice. The quotation was approved for submission (AED 9000 excluding VAT). WHAT THEY CAN DO NEXT: choose to have the standardised quotation generated, or upload a new version.' },
  { id: 'Q2', surface: 'quote_review.message', lang: 'en', audience: 'supplier', message: 'does the customer see my VAT number?', actions: QR_ACTIONS, expectAction: null,
    situation: 'You are the sales engineer reviewing this supplier\'s quotation for Job 151767. STATE: awaiting_choice. RULES: The customer compares prices excluding VAT and never sees your VAT details or TRN.' },
  { id: 'Q3', surface: 'quote_review.message', lang: 'ar', audience: 'supplier', message: 'سأرفع نسخة جديدة', actions: QR_ACTIONS, expectAction: 'reupload',
    situation: 'You are the sales engineer reviewing this supplier\'s quotation for Job 151767. STATE: awaiting_choice. WHAT THEY CAN DO NEXT: generated standardised quotation, or upload a new version.' },
];

const rows: Record<string, unknown>[] = [];
try {
  await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by) values ('qd_run:${TAG}', 'conversation_replies_rehearsal')`, 'rehearsal window');
  await mgmtFixture(REF, `update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '1 hour' where run_tag = 'qd_run:${TAG}' and ended_at is null`, 'rehearsal window models');
  const brief = await companyBrief(deps.rpc, [], '', 'en');
  for (const c of [...CASES, ...QR]) {
    const t0 = Date.now();
    let text = ''; let model: string | null = null; let attempts: string[] = []; let action: string | null | undefined;
    if (c.actions) {
      const r = await aiReply(deps, { seat: 'sales_engineer', channel: 'the supplier portal quotation chat', audience: 'supplier', lang: c.lang, message: c.message, facts: c.situation, actions: c.actions, subject: { fixture: true, supplier_id: 0 } });
      text = r.reply; model = r.model; attempts = r.attempts; action = r.action ?? null;
    } else {
      const r = await modelSays(deps, { audience: c.audience, lang: c.lang, message: c.message, situation: c.situation, subject: WA_FIX });
      text = r.text; model = r.model; attempts = r.attempts;
    }
    const ms = Date.now() - t0;
    const wantLang = c.audience === 'supplier' ? 'en' : c.lang;
    const langOk = text ? (wantLang === 'ar' ? AR.test(text) : !AR.test(text)) : false;
    // the SAME check aiReply runs: the brief, the turn's facts and the published contact are allowed (ai_reply.ts line 88)
    const allowed = figureSource(brief) + '\n' + c.situation + '\n+1 218 316 6814 management@quotesdone.com';
    const problems = text ? replyProblems(text, briefNumbers(figureSource(brief) + ' ' + c.situation), { allowed }) : ['no reply'];
    const strictProblems = text ? replyProblems(text, briefNumbers(figureSource(brief) + ' ' + c.situation)) : [];
    let judge: number | null = null; let judgeWhy = "";
    if (text) {
      const jr = await deps.llm('verify', 'You grade one customer-service reply for a UAE procurement marketplace. Score 1-5: 5 = answers exactly what was asked, accurate to the company brief and the facts given (the brief is the source of every company fact), professional, clear, right language; 1 = wrong or useless. Return JSON {"score":n,"why":"..."}',
        JSON.stringify({ company_brief: brief.slice(0, 6000), message: c.message, facts: c.situation, reply: text, required_language: wantLang }), { taskClass: 'json_extraction', seat: 'customer_support', max: 200, counterpartModel: 'anthropic/claude-sonnet-5', subject: { fixture: true } });
      // the judge's JSON may come fenced or with prose around it: take the first object
      try { const o = JSON.parse(String(jr.content || '').match(/\{[\s\S]*\}/)?.[0] || '{}'); judge = Number(o.score) || null; judgeWhy = String(o.why || ''); }
      catch (_e) { judge = null; judgeWhy = 'unparsed: ' + String(jr.content || jr.error || '').slice(0, 120); }
    }
    const row = { id: c.id, surface: c.surface, lang: c.lang, audience: c.audience, ms, model, attempts: attempts.join(','), lang_ok: langOk, problems: problems.join('; ') || 'none',
      action: c.actions ? action : undefined, action_ok: c.actions ? (action ?? null) === (c.expectAction ?? null) : undefined, judge, judge_why: judgeWhy, problems_without_allowed: strictProblems.join('; ') || 'none', reply: text.slice(0, 400) };
    rows.push(row);
    console.log(JSON.stringify(row));
  }
} finally {
  await mgmtFixture(REF, `update public.rehearsal_window set models_allowed = false where run_tag = 'qd_run:${TAG}'`, 'rehearsal window off').catch(() => {});
  await closeRehearsalWindow(TAG).catch(() => {});
}
const cost = (await mgmtRead(REF, `select count(*)::int calls, coalesce(sum(cost_aed),0)::float aed, count(*) filter (where ok)::int ok_calls from public.ai_cost_log where e2e_run_tag = '${TAG}'`))[0];
const ms = rows.map((r) => Number(r.ms)).sort((a, b) => a - b);
console.log(JSON.stringify({ tag: TAG, turns: rows.length, replied: rows.filter((r) => r.reply).length,
  p50_ms: ms[Math.floor(ms.length / 2)], max_ms: ms.at(-1), lang_ok: rows.filter((r) => r.lang_ok).length, clean: rows.filter((r) => r.problems === 'none').length,
  actions_ok: rows.filter((r) => r.action_ok === true).length + '/' + rows.filter((r) => r.action_ok !== undefined).length,
  judge_avg: +(rows.reduce((s, r) => s + Number(r.judge || 0), 0) / Math.max(1, rows.filter((r) => r.judge).length)).toFixed(2),
  judge_en: rows.filter((r) => r.lang === 'en').map((r) => r.judge), judge_ar: rows.filter((r) => r.lang === 'ar').map((r) => r.judge), cost }));

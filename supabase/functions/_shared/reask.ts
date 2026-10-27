// THE ASYNCHRONOUS MODEL RE-ASK — no customer or supplier is left silent, and no code-written text is sent while the model
// is up (customer_support owns WhatsApp, sales_engineer the portal chat and the supplier quotation thread; 27 Oct 2026).
//
// Founder ruling 1339, 27 Oct 2026, verbatim: "the engineer and customer support never replies without llm unless the
// server of open router is down". PRs #1647 and #1640 enforced the second half. The independent review of #1640 (head
// 4d5c6cfd0) found the gap that left: a turn where the model is UP but every draft and the retry were refused gets NO
// reply at all.
//   - portal (sales_engineer `assist`): the 503 carried outage:false and the panel showed nothing; nothing was filed.
//   - WhatsApp (wa_inbound holdUnwritten) and the supplier quotation thread: the turn was filed in reasoning_held_question
//     and resilience_ping's replay (every 15 minutes, through think() first) was the only re-ask. That replay asks the
//     same writer the same way, and when the writer refuses again it records via 'none', which fn_reason_held_delivered
//     marks 'applied': the row is closed, never escalated, and the person hears nothing (measured by reading
//     fn_reason_held_delivered and fn_reason_held_escalate in the schema mirror, 27 Oct 2026).
//
// WHAT THIS DOES. The same queue, reasoning_held_question (fn_reason_hold), holds the refused turn of three surfaces
// (REASK_SURFACES). A pg_cron job checks every minute (fn_reask_kick) and, only when a row is due, calls sales_engineer
// `reask_turns`, which runs reaskDue below:
//   1. fn_reask_due claims the due rows (first at ~30 s, then each minute, REASK_MAX_ATTEMPTS in all; nothing under the
//      founder's hold). resilience_ping's 15-minute replay no longer claims these surfaces (one asker per turn).
//   2. The model is asked AGAIN, differently: another model family first (aiReply otherFamilyFirst: the counterpart of
//      the conversation route, still one of the ruling-1217 chat models), high reasoning effort, and the problems the
//      guards found in the refused drafts named in the prompt (priorProblems).
//   3. Every safeguard runs on the new answer: aiReply's figure check, policy, reply guard (licence, the AI word, internal
//      and prompt text) and identity leaks; for the portal, customerSafe is RE-RUN on the turn's retrieved records (so
//      kbChunkIsCustomerFacing and every corpus rule apply as of now), plus the reply guard, the JSON-wrapping refusal and
//      the plain-language gate sentence by sentence; for a supplier, English only.
//   4. It is delivered into the SAME conversation: the WhatsApp thread (free text in the 24-hour window, the approved
//      template outside it), the supplier's quotation thread, or the portal chat — by filling the turn's own
//      assistant_logs row (reply IS NULL), so the portal's history shows it right under the question.
//   5. ONE REPLY PER TURN. Before anything is sent, fn_reask_record marks the row 'sending'; a row marked sending is never
//      claimed again, so a crash between the send and the record can never send twice (it is handed to the seat instead).
//      The portal write is conditional on reply IS NULL as well.
//   6. BOUNDED. After REASK_MAX_ATTEMPTS refused re-asks the row is 'failed' and handed to its owning seat at once
//      (agent_actions held_question, the existing escalation); a WhatsApp person is told by a MODEL-WRITTEN notice
//      (reasoned_delivery.holdingNotice) and the portal shows "with the team". A reviewed reply written afterwards
//      (fn_reask_reviewed_reply) comes back through this same door and passes the same gates before it is sent.
//   An OUTAGE (no call reached a model) consumes no attempt and sends nothing from here: the outage notice already went
//   at the turn, and the answer follows when OpenRouter is back.
// Code writes no reply text in this file.
// prevented by: _shared/reask.test.ts, scripts/checks/a_refused_turn_is_asked_again_never_left_silent.test.mjs
import type { AiReply, AiReplyRequest } from './ai_reply.ts';
import type { Seat } from './think.ts';
import { guardSupportReply } from './support_reply_guard.ts';
import { splitHeldQuestion } from './reasoned_delivery.ts';
import { customerSafe, plainLanguage, portalFacts, portalRules, wrappedReply, type FlagLookup, type Record_ } from '../sales_engineer/portal_turn.ts';
import { WA_RULES } from '../wa_inbound/model_says.ts';

export const REASK_SURFACES = ['wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten', 'sales_engineer.portal_unwritten'] as const;
export type ReaskSurface = typeof REASK_SURFACES[number];
/** Re-asks per turn before it is handed to its seat (fn_reask_record reads the same number). */
export const REASK_MAX_ATTEMPTS = 3;
/** Rows one tick takes; they run side by side, each on its own clock. */
export const REASK_CLAIM = 5;
/** One re-ask's model ladder ends inside this (the edge wall is 150 s; the tick runs its rows concurrently). */
export const REASK_TURN_MS = 45_000;
/** The supplier quotation thread's format (the live voice in supplier_api/index.ts uses the same). */
export const QR_RULES = 'Plain text for the portal chat, no markdown headings. Keep every job number, figure, numbered point and button name from the facts exactly; a short numbered list is right when the facts list points.';

/** What the turn was, stored by its caller in request.reask when it filed the turn. */
export interface ReaskTurn {
  message: string; facts?: string; audience: 'customer' | 'supplier' | 'visitor' | 'founder'; lang: 'en' | 'ar';
  channel?: string; problems?: string[]; passages?: Record_[]; own_facts?: string; must?: string[];
}
export interface ReaskRow {
  id: number; seat: string; surface: string; attempts: number; created_at?: string;
  request: { reask?: ReaskTurn; question?: string; context?: { audience?: string; language?: string } };
  subject: Record<string, unknown> | null; result?: Record<string, unknown> | null;
}
export interface ReaskOutcome { delivered: boolean; via: string; model?: string | null; outage?: boolean; problems?: string[]; detail?: string; reviewed?: boolean }
export type Sent = { ok: boolean; err?: string };

export interface ReaskIO {
  write(r: AiReplyRequest): Promise<AiReply>;
  /** customerSafe's flag lookup over the live corpora (portal_turn.ts). */
  lookup: FlagLookup;
  /** customerReplyGate (ai_reply.ts): the checks a reply written outside aiReply must pass. */
  gate(text: string, lang: 'en' | 'ar', supplier: boolean): Promise<string[]>;
  /** fn_reask_record phase 'sending'. false: the row is no longer this run's to send (never send twice). */
  sending(id: number): Promise<boolean>;
  whatsapp(phone: string, question: string, text: string): Promise<{ delivered: boolean; via: string; detail?: string }>;
  quoteReview(reviewId: string, text: string): Promise<Sent>;
  portal(logId: number, text: string): Promise<Sent>;
}

const ARABIC = /[؀-ۿ]/;
const isAr = (s: string) => ARABIC.test(s);

/** The turn as filed. A row filed before request.reask existed is read from its question (facts + "MESSAGE:"). */
export function turnOf(row: ReaskRow): ReaskTurn {
  if (row.request?.reask?.message) return row.request.reask;
  const [facts, said] = splitHeldQuestion(String(row.request?.question ?? ''));
  const ctx = row.request?.context ?? {};
  const audience = (['customer', 'supplier', 'visitor', 'founder'] as const).find((a) => a === ctx.audience) ?? (row.surface.startsWith('supplier_api.') ? 'supplier' : 'customer');
  return { message: said, facts, audience, lang: audience === 'supplier' ? 'en' : ctx.language === 'ar' || isAr(said) ? 'ar' : 'en' };
}

/** Why the earlier drafts of this turn were refused: at the turn, and at every re-ask since. */
export function priorProblems(row: ReaskRow): string[] {
  const later = Array.isArray(row.result?.reask_problems) ? (row.result!.reask_problems as unknown[]).map(String) : [];
  return [...new Set([...(turnOf(row).problems ?? []), ...later].map((p) => p.trim()).filter(Boolean))].slice(0, 12);
}

/** A supplier is always answered in English (ruling 1008): any Arabic letter refuses the sentence. */
export function englishOnly(text: string): string[] {
  return isAr(text) ? ['it is not in English (a supplier is always answered in English)'] : [];
}

/** The surface's own rules on top of aiReply's (the portal's are the live turn's: sales_engineer/index.ts `check`). */
export function extraCheck(surface: string, audience: string, lang: 'en' | 'ar'): (t: string) => string[] {
  const supplier = audience === 'supplier';
  if (surface === 'sales_engineer.portal_unwritten') {
    return (t) => [...guardSupportReply(t, lang).violations.map((v) => 'it breaks the reply rule "' + v + '"'), ...wrappedReply(t), ...plainLanguage(t, lang),
      ...(supplier ? englishOnly(t) : [])];
  }
  return (t) => (supplier ? englishOnly(t) : []);
}

/** The model request for this re-ask: the same turn, asked differently (another family first, high effort, the problems named). */
export async function reaskRequest(row: ReaskRow, lookup: FlagLookup, now = Date.now()): Promise<AiReplyRequest> {
  const t = turnOf(row);
  const audience = t.audience;
  const lang: 'en' | 'ar' = audience === 'supplier' ? 'en' : t.lang;
  let facts = t.facts ?? '';
  let channel = t.channel ?? 'WhatsApp';
  let rules = WA_RULES;
  if (row.surface === 'sales_engineer.portal_unwritten') {
    // customerSafe RUNS AGAIN on the records the turn retrieved: a record withheld since then never reaches this prompt.
    const safe = await customerSafe((t.passages ?? []) as Record_[], lookup);
    facts = portalFacts({ facts: t.own_facts ?? '', passages: safe });
    channel = t.channel ?? 'the signed-in customer portal';
    rules = portalRules();
  } else if (row.surface === 'supplier_api.quote_review_unwritten') {
    channel = t.channel ?? 'the supplier portal quotation chat';
    rules = QR_RULES;
  }
  return {
    seat: (row.seat === 'sales_engineer' ? 'sales_engineer' : 'customer_support') as Seat, channel, audience, lang,
    message: t.message || '(no text — they pressed a menu option or sent a file)',
    facts: facts || undefined, rules, subject: row.subject ?? undefined, must: t.must,
    ...(row.surface === 'sales_engineer.portal_unwritten' ? { plainText: true } : {}),
    priorProblems: priorProblems(row), otherFamilyFirst: true, effort: 'high',
    extraCheck: extraCheck(row.surface, audience, lang), deadline: now + REASK_TURN_MS,
  };
}

/** Into the conversation the turn came from. Marked 'sending' first: a row is sent at most once. */
export async function deliverInto(row: ReaskRow, text: string, io: ReaskIO): Promise<ReaskOutcome> {
  const s = row.subject ?? {};
  const where = row.surface === 'wa_inbound.unwritten_reply' ? String(s.phone ?? '')
    : row.surface === 'supplier_api.quote_review_unwritten' ? String(s.review_id ?? '')
    : row.surface === 'sales_engineer.portal_unwritten' ? String(s.log_id ?? '') : '';
  if (!where) return { delivered: false, via: 'none', detail: 'no conversation on the row for ' + row.surface };
  if (!(await io.sending(row.id))) return { delivered: false, via: 'none', detail: 'already being sent by another run; never sent twice' };
  if (row.surface === 'wa_inbound.unwritten_reply') return { ...(await io.whatsapp(where, turnOf(row).message, text)) };
  if (row.surface === 'supplier_api.quote_review_unwritten') { const r = await io.quoteReview(where, text); return { delivered: r.ok, via: 'quote_thread', detail: r.err }; }
  const r = await io.portal(Number(where), text);
  return { delivered: r.ok, via: 'portal', detail: r.err };
}

/** One due turn: a reviewed reply (after the hand-off) is gated and delivered; otherwise the model is asked again. */
export async function reaskOne(row: ReaskRow, io: ReaskIO): Promise<ReaskOutcome> {
  const t = turnOf(row);
  const supplier = t.audience === 'supplier';
  const lang: 'en' | 'ar' = supplier ? 'en' : t.lang;
  const reviewed = String(row.result?.reviewed_reply ?? '').trim();
  if (row.result?.reviewed_state === 'due' && reviewed) {
    // a person's (or the CEO seat's) reply after the hand-off: the same gates as a model reply, then the same door
    const problems = [...await io.gate(reviewed, lang, supplier), ...extraCheck(row.surface, t.audience, lang)(reviewed)];
    if (problems.length) return { delivered: false, via: 'none', reviewed: true, problems };
    return { ...(await deliverInto(row, reviewed, io)), reviewed: true };
  }
  const a = await io.write(await reaskRequest(row, io.lookup));
  const text = String(a.reply || '').trim();
  if (!text) return { delivered: false, via: 'none', model: null, outage: a.outage === true, problems: a.problems ?? [], detail: a.attempts.join(' | ').slice(0, 300) };
  return { ...(await deliverInto(row, text, io)), model: a.model };
}

// ── the live run ────────────────────────────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Admin = any;

/** One tick: claim, re-ask side by side, record each, and send the model-written hand-off notice for any row handed off. */
export async function reaskDue(admin: Admin, o: { limit?: number; io?: ReaskIO } = {}): Promise<Record<string, unknown>> {
  const { data, error } = await admin.rpc('fn_reask_due', { p_limit: o.limit ?? REASK_CLAIM });
  if (error) return { ok: false, error: error.message };
  const rows = (data ?? []) as ReaskRow[];
  if (!rows.length) return { ok: true, claimed: 0 };
  const io = o.io ?? liveReaskIO(admin);
  const out = await Promise.all(rows.map(async (row) => {
    let outcome: ReaskOutcome;
    try { outcome = await reaskOne(row, io); } catch (e) { outcome = { delivered: false, via: 'error', detail: String((e as Error)?.message || e).slice(0, 200) }; }
    const rec = await admin.rpc('fn_reask_record', { p_id: row.id, p_outcome: outcome }).then((r: { data: unknown }) => r.data, (e: unknown) => ({ error: String(e) }));
    return { id: row.id, surface: row.surface, delivered: outcome.delivered, via: outcome.via, outage: outcome.outage ?? false, problems: outcome.problems?.length ?? 0, record: rec };
  }));
  // The rows handed to their seat this tick: a WhatsApp person is told now, in the model's words (holdingNotice).
  const handed = new Set(out.filter((x) => (x.record as { status?: string } | null)?.status === 'handed_off').map((x) => x.id));
  let told: unknown = [];
  if (handed.size) {
    const { sendHeldNotices, liveDeliveryIO } = await import('./reasoned_delivery.ts');
    const owed = ((await admin.rpc('fn_reason_held_notice_due', { p_limit: 50 })).data ?? []) as { id: number; surface: string; question: string; subject: Record<string, unknown> | null }[];
    told = await sendHeldNotices(owed.filter((r) => handed.has(r.id)), liveDeliveryIO(admin), (id, d) => admin.rpc('fn_reason_held_notice_record', { p_id: id, p_delivery: d }));
  }
  return { ok: true, claimed: rows.length, rows: out, told };
}

export function liveReaskIO(admin: Admin): ReaskIO {
  return {
    write: async (r) => {
      const { aiReply } = await import('./ai_reply.ts');
      const { defaultDeps } = await import('./think.ts');
      return await aiReply(defaultDeps(admin, 'sales_engineer'), r);
    },
    lookup: async (rule, ids) => { const x = await admin.from(rule.table).select(rule.select).in(rule.key, ids); return { data: x.data, error: x.error }; },
    gate: async (text, lang, supplier) => {
      const { customerReplyGate } = await import('./ai_reply.ts');
      return await customerReplyGate((fn, args) => admin.rpc(fn, args), text, lang, supplier);
    },
    sending: async (id) => {
      const { data, error } = await admin.rpc('fn_reask_record', { p_id: id, p_outcome: { phase: 'sending' } });
      return !error && (data as { status?: string } | null)?.status === 'sending';
    },
    whatsapp: async (phone, question, text) => {
      const { whatsapp, liveDeliveryIO } = await import('./reasoned_delivery.ts');
      return await whatsapp(liveDeliveryIO(admin), phone, question, text);
    },
    quoteReview: async (reviewId, text) => {
      const { liveDeliveryIO } = await import('./reasoned_delivery.ts');
      return await liveDeliveryIO(admin).postQuoteReview!(reviewId, text);
    },
    portal: async (logId, text) => {
      // the turn's own row: written once (reply IS NULL), so the history shows it right under the question
      const { data, error } = await admin.from('assistant_logs').update({ reply: text.slice(0, 8000), answered: true, path: 'portal:reasked' })
        .eq('id', logId).is('reply', null).select('id');
      if (error) return { ok: false, err: error.message };
      return (data ?? []).length === 1 ? { ok: true } : { ok: false, err: 'the turn already has a reply' };
    },
  };
}

// _shared/case_context.ts — the case model on EVERY channel (customer_support, 11 Nov 2026; founder rulings 1631, 1635).
//
// #1938 built the case model (support_case_memory.ts) and wired it into WhatsApp only. The ruling is per person, not per
// channel: "When the same customer or supplier writes again, the agent decides whether it is the same matter ... or a
// different matter". One person has ONE set of cases whether they write on WhatsApp, in the website widget, in the
// customer portal, in the supplier portal's quotation chat or by e-mail: fn_support_open_cases resolves the person through
// support_customer_profile (customer id, lead id, e-mail, phone tail), the same identity fn_support_touch already attaches
// every channel's messages to.
//
// Each channel's turn calls exactly TWO things from here, so the turn files stay the turn's own:
//   loadCaseContext(...)    before the model call: ONE database read (readCase, no model) and what the reply reads
//                           (sys with the case block appended, and only the last CASE_TURNS turns of the history, when
//                           the case already has a summary; otherwise everything exactly as it came in);
//   recordCaseExchange(...) after the reply that was really given: the same-matter decision, the routing and the summary
//                           (settleExchange, retried when it fails), kept alive past the response with
//                           EdgeRuntime.waitUntil. Never awaited by a turn.
// Until 12 Nov 2026 the decision ran BEFORE the reply, raced against 4 s; it never finished inside 4 s on WhatsApp (p50 8.7 s),
// so every turn waited the full 4 s for nothing (final audit 12 Nov 2026, W3; support_case_memory.ts says what was measured).
// A caller with no identity (an anonymous website visitor) gets the pass-through: no read, no decision, no case.
// Every failure is the pass-through too: a turn never waits more than CASE_READ_MS for its case and never fails on one.
// prevented by: _shared/case_context.test.ts
import { caseBlock, CASE_TURNS, hasCaseBlock, readCase, settleExchange, worksFromOneCase, type CaseMemory } from './support_case_memory.ts';
import type { ThinkDeps } from './think.ts';
import { MESSAGE_CAP } from './inquiry_state.ts';
import { readEscalationFacts } from './escalation_clock.ts';

export type CaseChannel = 'whatsapp' | 'widget' | 'portal' | 'email';
export type CaseAudience = 'customer' | 'supplier' | 'visitor';
/** How long the case read may hold a turn before the reply goes ahead without it (the same bound as WhatsApp's). It is one
 *  database call (fn_support_open_cases) and no model: 4,000 ms was the bound for the model decision this no longer waits for. */
export const CASE_READ_MS = 1_500;

export interface CaseTurn<T> {
  /** the case this turn belongs to; null = no identity, or the read failed or was late */
  memory: CaseMemory | null;
  /** the seat that answers on this channel: it owns the promises the reply makes (support_case_promise.owner_seat) */
  seat: string;
  /** true when the reply works from the case summary (the case has one) */
  withCase: boolean;
  /** the caller's system text, with the case block appended when the case has a summary (inside the cached prefix) */
  sys: string;
  /** the history the reply reads: the case's last CASE_TURNS turns when it has a summary, otherwise all of it, unchanged */
  past: T[];
  /** for an aiReply caller: aiReply puts the case block in its own cached prefix and cuts the conversation itself */
  reply: { caseMemory?: CaseMemory };
  /** for a think() caller: the case number and summary, as ThinkContext.case */
  context: { case?: { case_ref: string; summary: string } };
  /** who and what, for the step after the reply (null: no identity, nothing is recorded) */
  after?: CaseRead<unknown> | null;
  /** THE PERSON'S OPEN ESCALATIONS AND THE FOUNDER'S AVAILABILITY (16 Nov 2026, escalation_clock.ts): what we promised them, where it
   *  stands, when word is owed, when the founder last answered and which channel is down for a credential only he can renew. Already
   *  appended to `sys`; an aiReply caller adds it to its own facts. '' when there is nothing to say. */
  standing: string;
}

export interface CaseRead<T> {
  channel: CaseChannel; seat: string; audience: CaseAudience; message: string;
  partyId?: string | null; email?: string | null; phone?: string | null; lang?: string;
  /** one key per message, so a retried turn makes the same decision once */
  dedupeKey?: string;
  sys?: string; past?: T[]; readMs?: number;
}

// With no case summary the reply reads the conversation, at most the estate's 100-message cap (inquiry_state.ts MESSAGE_CAP;
// review round 2, 12 Nov 2026: one long chat could otherwise make every reply on that door slow and expensive).
const withStanding = (sys: string, standing: string) => standing ? sys + (sys ? '\n\n' : '') + standing : sys;
const passThrough = <T>(o: CaseRead<T>, memory: CaseMemory | null = null, after: CaseRead<unknown> | null = null, standing = ''): CaseTurn<T> => ({
  memory, seat: o.seat, withCase: false, sys: withStanding(o.sys ?? '', standing), past: (o.past ?? []).slice(-MESSAGE_CAP), reply: {}, context: {}, after, standing,
});

/** True when the caller names someone the profile resolver can find (a customer id, a lead id, an e-mail or a phone). */
export const hasIdentity = (o: Pick<CaseRead<unknown>, 'partyId' | 'email' | 'phone'>) =>
  !!(String(o.partyId ?? '').trim() || /@/.test(String(o.email ?? '')) || String(o.phone ?? '').replace(/\D/g, '').length >= 9);

/** BEFORE the model call: the person's case and what the reply reads. Never throws, never waits past readMs. */
export async function loadCaseContext<T>(deps: ThinkDeps, o: CaseRead<T>): Promise<CaseTurn<T>> {
  if (!hasIdentity(o) || !String(o.message ?? '').trim()) return passThrough(o);
  // the step after the reply reads the cases again itself, so a read that was late here still records the exchange
  const after: CaseRead<unknown> = { ...o, sys: undefined, past: (o.past ?? []).slice(-CASE_TURNS) };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<null>((r) => { timer = setTimeout(() => r(null), o.readMs ?? CASE_READ_MS); });
  let memory: CaseMemory | null = null;
  // the escalation facts are one more database read beside the case read, inside the same bound (never a model, never a throw)
  const standingP = readEscalationFacts((fn, args) => deps.rpc(fn, args), { email: o.email ?? null, phone: o.phone ?? null }).catch(() => '');
  let standing = '';
  try {
    const [read, st] = await Promise.all([
      Promise.race([readCase(deps, { message: o.message, audience: o.audience,
        partyId: o.partyId ?? null, email: o.email ?? null, phone: o.phone ?? null }), late]),
      Promise.race([standingP, late.then(() => '')]),
    ]);
    memory = read?.memory ?? null;
    standing = typeof st === 'string' ? st : '';
  } catch (_e) { memory = null; } finally { clearTimeout(timer); }
  if (!memory) return passThrough(o, null, after, standing);
  // the same rule aiReply applies (ai_reply.ts withCase): only a case that already has a summary replaces the transcript
  const withCase = worksFromOneCase(memory);
  const sys = o.sys ?? '';
  // SEVERAL RECORDED MATTERS, NONE NAMED (audit WHO_KNOWS_WHAT item 2, 16 Nov 2026): no case replaces the transcript, but every
  // open case's line and open promises are appended, so the reply keeps a promise made on any of them
  if (!withCase && hasCaseBlock(memory)) {
    const block = caseBlock(memory);
    return { ...passThrough(o, memory, after, standing), sys: withStanding(sys + (sys ? '\n\n' : '') + block, standing), reply: { caseMemory: memory },
      context: { case: { case_ref: (memory.allOpen ?? []).map((l) => l.ref).join(', '), summary: block } } };
  }
  if (!withCase) return passThrough(o, memory, after, standing);
  return {
    memory, seat: o.seat, withCase, standing,
    sys: withStanding(sys + (sys ? '\n\n' : '') + caseBlock(memory), standing),
    past: (o.past ?? []).slice(-CASE_TURNS),
    reply: { caseMemory: memory },
    context: { case: { case_ref: memory.ref, summary: memory.summaryText } },
    after,
  };
}

/** The turns a summary is given beside the exchange (oldest first, each clipped): a lost earlier summary is caught up. */
export function recentText(past: readonly unknown[]): string {
  return past.map((t) => {
    // deno-lint-ignore no-explicit-any
    const x = t as any;
    const who = x?.role === 'assistant' || x?.role === 'seat' ? 'US' : 'THEM';
    return who + ': ' + String(x?.content ?? x?.text ?? '').replace(/\s+/g, ' ').trim().slice(0, 400);
  }).filter((l) => !/^(US|THEM): $/.test(l)).join('\n');
}

/** AFTER the reply that was really given: the case summary is rewritten (and, in SQL, every stated promise recorded and
 *  the summary queued for the person's Dropbox folder). Runs past the response; returns the work for a test to await. */
export function recordCaseExchange<T>(deps: ThinkDeps, kase: CaseTurn<T> | null | undefined,
  o: { theirMessage: string; ourReply: string; subject?: Record<string, unknown> }): Promise<{ ok: boolean; reason?: string }> | null {
  const a = kase?.after;
  if (!a || !String(o.ourReply ?? '').trim() || !String(o.theirMessage ?? '').trim()) return null;
  const work = settleExchange(deps, { channel: a.channel, audience: a.audience, partyId: a.partyId ?? null, email: a.email ?? null, phone: a.phone ?? null,
    lang: a.lang, dedupeKey: a.dedupeKey, message: o.theirMessage, ourReply: o.ourReply, seat: kase!.seat, recent: recentText(a.past ?? []),
    ...(o.subject ? { subject: o.subject } : {}) }).catch((e) => ({ ok: false, reason: String((e as Error)?.message ?? e).slice(0, 200) }));
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(work);
  return work;
}

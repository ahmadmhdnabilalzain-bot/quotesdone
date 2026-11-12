// wa_inbound/case_memory.ts — the WhatsApp turn works from its CASE (customer_support, ruling 1635, 11 Nov 2026).
// Two halves, split at the reply (final audit 12 Nov 2026, W3; _shared/support_case_memory.ts says what was measured):
//   startWaCase (makeSay, as soon as the turn is past the burst gate): ONE database read of the sender's open cases, no model.
//     The reply reads the case the message belongs to by code (waCaseMemory), waiting at most CASE_READ_MS for it.
//   recordWaExchange (the reply that became THE turn's reply, say.ts adopt): the same-matter decision, the routing and the
//     summary (settleExchange), off the reply's path, kept alive past the response, retried when it fails. Status and app-lane
//     replies are recorded too: they are exchanges of the case even though their reply does not read it.
// The founder's own number is not a case. Every failure is null, and the turn reads the whole conversation as before.
// prevented by: _shared/support_case_memory.test.ts, wa_inbound/a_conversation_on_one_matter_is_one_case.test.ts
import { readCase, settleExchange, CASE_TURNS, type CaseMemory, type CaseRead } from '../_shared/support_case_memory.ts';
import { admin } from './shared.ts';
import { defaultDeps, type ThinkDeps, type Turn } from '../_shared/think.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import type { WaTurn } from './turn.ts';

/** How long the reply waits for the case read (one database call, no model; started when the turn passed the burst gate).
 *  It was 4,000 ms for a read-and-decide that took p50 8.7 s and so always lost (11 Nov 2026, production). */
export const CASE_READ_MS = 1_500;

type Aud = 'customer' | 'supplier' | 'visitor' | 'founder';
const reads = new WeakMap<object, Promise<CaseRead | null>>();

/** Start the case read for this turn (once). The phone alone resolves the person (fn_support_profile_resolve, phone tail). */
export function startWaCase(t: Pick<WaTurn, 'From' | 'Body'>, deps: ThinkDeps = defaultDeps(admin, 'wa_inbound')): Promise<CaseRead | null> {
  let p = reads.get(t);
  if (!p) {
    p = readCase(deps, { audience: 'visitor', phone: t.From, message: t.Body }).catch(() => null);
    reads.set(t, p);
  }
  return p;
}

/** The case the reply works from, or null (founder, no open case, a failed or late read). Never waits past CASE_READ_MS. */
export async function waCaseMemory(t: Pick<WaTurn, 'From' | 'Body'>, aud: Aud, ms = CASE_READ_MS, deps?: ThinkDeps): Promise<CaseMemory | null> {
  if (aud === 'founder') return null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<null>((r) => { timer = setTimeout(() => r(null), ms); });
  try { return (await Promise.race([startWaCase(t, deps), late]))?.memory ?? null; } catch (_e) { return null; } finally { clearTimeout(timer); }
}

/** After the reply that became the turn's reply: decide, route, summarise. Not awaited by the turn; returns the work for a test. */
export function recordWaExchange(t: Pick<WaTurn, 'From' | 'Body' | 'MessageSid'>, aud: Aud, lang: string, reply: string, conversation: readonly Turn[] = [],
  deps: ThinkDeps = defaultDeps(admin, 'wa_inbound')): Promise<unknown> | null {
  if (aud === 'founder' || !reply.trim() || !String(t.Body ?? '').trim()) return null;
  const recent = conversation.slice(-CASE_TURNS).map((x) => (x.role === 'seat' ? 'US: ' : 'THEM: ') + String(x.text ?? '').replace(/\s+/g, ' ').trim().slice(0, 400)).join('\n');
  const work = settleExchange(deps, { channel: 'whatsapp', audience: aud, phone: t.From, lang, message: t.Body, ourReply: reply, recent,
    ...(t.MessageSid ? { dedupeKey: 'case_match:' + t.MessageSid } : {}),
    subject: isDemoPhone(t.From) ? { fixture: true, phone: t.From } : { phone: t.From } }).catch(() => null);
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(work);
  return work;
}

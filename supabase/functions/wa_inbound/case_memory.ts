// wa_inbound/case_memory.ts — the WhatsApp turn works from its CASE (customer_support, ruling 1635, 11 Nov 2026).
// Once per turn: the sender's open cases (one person across every channel), the same-matter decision, and the case the
// reply reads (its summary in the cached prefix, its last turns verbatim). After the real reply: the summary step.
// The founder's own number is not a case. Every failure is null, and the turn reads the whole conversation as before.
// prevented by: _shared/support_case_memory.test.ts
import { caseMemoryFor, summariseExchange, type CaseMemory } from '../_shared/support_case_memory.ts';
import { admin } from './shared.ts';
import { defaultDeps } from '../_shared/think.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import type { WaTurn } from './turn.ts';

/** How long the case read may hold the turn before the reply goes ahead without it. */
export const CASE_READ_MS = 4_000;
const memo = new WeakMap<object, Promise<CaseMemory | null>>();

export function waCaseMemory(t: Pick<WaTurn, 'From' | 'Body' | 'MessageSid'>, aud: 'customer' | 'supplier' | 'visitor' | 'founder', lang: string): Promise<CaseMemory | null> {
  if (aud === 'founder') return Promise.resolve(null);
  let p = memo.get(t);
  if (!p) {
    const read = caseMemoryFor(defaultDeps(admin, 'wa_inbound'), { message: t.Body, channel: 'whatsapp', audience: aud, phone: t.From, lang,
      ...(t.MessageSid ? { dedupeKey: 'case_match:' + t.MessageSid } : {}) });
    p = Promise.race([read, new Promise<null>((r) => setTimeout(() => r(null), CASE_READ_MS))]);
    memo.set(t, p);
  }
  return p;
}

/** After the reply that was really sent: the case summary is rewritten. Not awaited by the turn. */
export function recordWaExchange(mem: CaseMemory | null, t: Pick<WaTurn, 'From' | 'Body'>, reply: string): void {
  if (!mem || !reply.trim()) return;
  // the stored summary rides in mem.summaryText: an earlier promise is kept because that text states it
  void summariseExchange(defaultDeps(admin, 'wa_inbound'), { memory: mem, theirMessage: t.Body, ourReply: reply,
    subject: isDemoPhone(t.From) ? { fixture: true, phone: t.From } : { phone: t.From } });
}

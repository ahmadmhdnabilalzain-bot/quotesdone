// identify.ts - WHO IS THIS NUMBER, and what to read about them: fn_identify_contact, then the four reads that do not depend on the
// classification (timeline, own record, company block, FAQ) started now so they run beside it. readTimeline awaits the timeline.
// Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support).
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { waConversation } from '../_shared/wa_history.ts';
import { admin } from './shared.ts';
import { retrieveFaq } from './faq.ts';
import type { WaTurn } from './turn.ts';

export async function identify(t: WaTurn): Promise<void> {
  const { From, Body, receivedAt, historyUnavailable } = t;
  // ---- AUDIENCE: who is this number? -------------------------------------
  let audience = 'unknown', known: any = null;
  try {
    const { data: idres } = await admin.rpc('fn_identify_contact', { p_phone: From });
    if (idres && idres.audience) { audience = String(idres.audience); known = idres; }
  } catch (_e) { /* fall back to inference */ }

  // WHERE THE SECONDS GO (2 Nov 2026, measured on the real exchange: 26-47 s a supplier turn against a 45 s reply budget,
  // two turns in twelve unanswered). The reads below were awaited ONE AFTER ANOTHER after the classification call; none
  // depends on it, so they start now and run beside it. `timings` (ms since arrival) rides on the turn's row so the next
  // measurement names the stage. Prevented by: the_whole_exchange.test.ts (the reads start before the reply is asked for).
  const timings: Record<string, number> = {};
  const mark = (k: string) => { timings[k] = Date.now() - Date.parse(receivedAt); };
  const soft = <T>(p: PromiseLike<T>, empty: T): Promise<T> => Promise.resolve(p).then((v) => v, () => empty);
  const prefetch = {
    // the sender's own timeline (16 Nov 2026, a_phone_tail_never_joins_two_people.sql): fn_contact_timeline matched every customer and
    // supplier whose UNVERIFIED phone shares the last nine digits; the wrapper reads the number's confirmed owner, or only this number
    timeline: soft(admin.rpc('fn_contact_timeline_for_sender', { p_contact: From, p_limit: 40 }), { data: null } as never),
    mine: soft(admin.rpc('fn_wa_context', { p_audience: audience, p_phone: From }), { data: null } as never),
    company: soft(admin.rpc('fn_company_context', { p_max_chars: 6000, p_audience: 'public' }), { data: null } as never),
    faq: soft(retrieveFaq(Body), { ctx: '', ids: [] as number[] }),
  };
  t.history ??= waConversation(admin, From, receivedAt, isDemoPhone(From), historyUnavailable);
  mark('identified');
  Object.assign(t, { audience, known, timings, mark, prefetch });
}

// ---- THE CONTACT'S TIMELINE, read before anything is composed (14 Sep 2026) ----------------
// Founder: "the only agent who uses the whatsapp and email is the customer support agent. so he
// should be always up to date with that is going on." fn_contact_timeline assembles, in SQL and
// with no model, everything the company has done with this person on every channel and every
// seat: requests, quotes (held/released), reveals, invoices, refunds and the CEO's decisions on
// them, and every message sent or received. Scoped to the sender's own number: its confirmed owner (fn_whatsapp_owner), or with
// none only what this number exchanged with us (fn_contact_timeline_for_sender; a phone may confirm, never select).
export async function readTimeline(t: WaTurn): Promise<void> {
  const { prefetch } = t;
  let timeline: Record<string, unknown> | null = null;
  try {
    const { data: tl } = await prefetch.timeline;
    timeline = (tl || null) as Record<string, unknown> | null;
  } catch (_e) { timeline = null; /* a missing timeline must never lose their message */ }
  const timelineEvents = Number((timeline as any)?.event_count ?? 0);
  t.timelineEvents = timelineEvents;
}

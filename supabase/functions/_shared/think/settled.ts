// think/settled.ts — the settled company facts and which audience reads which (moved whole from _shared/think.ts).
import {
  SEAT_CARD_ACCOUNTANT, SEAT_CARD_CEO, SEAT_CARD_CUSTOMER_SUPPORT, SEAT_CARD_IT_ENGINEER, SEAT_CARD_MARKETING, SEAT_CARD_SALES_ENGINEER,
  SEAT_FACTS_EXTERNAL, SEAT_FACTS_INTERNAL,
} from '../brief.generated.ts';
import type { ThinkContext } from './types.ts';

const SEAT_CARDS: ReadonlyMap<string, string> = new Map([
  ['ceo', SEAT_CARD_CEO], ['customer_support', SEAT_CARD_CUSTOMER_SUPPORT], ['sales_engineer', SEAT_CARD_SALES_ENGINEER],
  ['accountant', SEAT_CARD_ACCOUNTANT], ['it_engineer', SEAT_CARD_IT_ENGINEER], ['marketing', SEAT_CARD_MARKETING],
]);
/** Audiences outside the company: their prompt never carries another party's record. */
export const EXTERNAL_AUDIENCES: ReadonlySet<string> = new Set(['customer', 'supplier', 'visitor']);

/**
 * THE SETTLED FACTS RIDE IN EVERY CALL (ceo, ledger 1003 stage 2, 19 Oct 2026). think() reasoned from retrieved rows
 * only; the company brief and the founder's rulings were never in its prompt. Measured on the real-model seat exam:
 * the ceo seat said the founder approves refunds and that no bank was on record, the accountant used AED 187,500 for
 * VAT registration, it_engineer escalated incidents to the founder, sales_engineer mapped a pool to plumbing and would
 * tell a supplier a competitor's price, customer_support said reveals were its job. Each is settled in
 * knowledge/brief/company.md or knowledge/brief/seats.md. They are now the byte-stable cached prefix (sysStable) of the
 * plan, every answer pass and the review. An outside audience gets company.md only: seats.md is internal.
 * prevented by: _shared/think_settled_facts.test.ts
 */
export const SETTLED_HEADER = '# SETTLED COMPANY FACTS AND FOUNDER RULINGS (they override any SOURCE that contradicts them; never say one of them is not on record)';
// FAILS CLOSED (review of #1538): only an audience NAMED internal or founder gets seats.md. A missing or unknown
// audience (a held row stored before the type required one, a caller that cast its way past the type) gets the
// public brief. ThinkContext.audience and ThinkRequest.context are required, so deno check names every call site.
export const INTERNAL_AUDIENCES: ReadonlySet<string> = new Set(['internal', 'founder']);
/**
 * ONE FALLBACK (review of #1591, 19 Oct 2026): an audience that is not NAMED is a visitor, everywhere. think() used to
 * default a missing audience to 'internal' for the case-memory text, the model class and the prompt label while it
 * sent none (external) to retrieval and gave it the public brief, so one request was half internal and half external.
 * Every reader below takes the audience from here: the brief, retrieval's p_audience, case text, the model class.
 * An internal seat keeps its own rows by naming 'internal' (the type requires it). prevented by: think_settled_facts.test.ts
 */
export function audienceOf(a: string | null | undefined): ThinkContext['audience'] {
  return a && (INTERNAL_AUDIENCES.has(a) || EXTERNAL_AUDIENCES.has(a)) ? a as ThinkContext['audience'] : 'visitor';
}
// The seat's OPERATING FACTS card (knowledge/brief/seats/<seat>.md, compiled by code from its own verified pack by
// scripts/kb/compile_brief.mjs) rides only with the internal brief: it names thresholds, owners and internal routines a
// customer, supplier or visitor is never told. One card per seat, byte-stable, so each seat's prefix caches.
export function settledFacts(audience: string | null | undefined, seat?: string | null): string {
  if (!(audience && INTERNAL_AUDIENCES.has(audience))) return SETTLED_HEADER + '\n\n' + SEAT_FACTS_EXTERNAL;
  const card = (seat && SEAT_CARDS.get(seat)) || '';
  return SETTLED_HEADER + '\n\n' + SEAT_FACTS_INTERNAL + (card ? '\n\n' + card : '');
}

/** THE PART EVERY SEAT SHARES IS ITS OWN CACHE BLOCK (it_engineer, 11 Nov 2026; prompt diet, switch
 *  'settled_facts_ride_as_one_shared_cache_block'). settledFacts() rode as ONE cached block, so on an Anthropic route the
 *  provider could only ever read a write by the SAME seat: the internal facts (~10.6k tokens) are identical for all six
 *  seats and only the seat card (~2-6k) differs. Measured, ai_cost_log 7 days: knowledge_validation on Sonnet wrote ~14k
 *  tokens a call and read ~1.5k. Split here, the shared head goes as the gateway's sys_shared (its own breakpoint, read by
 *  every seat) and the card as sys_stable. The bytes and their order are unchanged: shared + stable === the input, so a
 *  provider that caches by prefix (Luna Pro) is sent exactly what it was sent before. Text that is not a settled-facts
 *  prefix comes back whole as `stable`. prevented by: _shared/prompt_diet_settled_block.test.ts */
export function splitSettled(sysStable: string): { shared: string; stable: string } {
  for (const head of [SETTLED_HEADER + '\n\n' + SEAT_FACTS_INTERNAL, SETTLED_HEADER + '\n\n' + SEAT_FACTS_EXTERNAL]) {
    if (sysStable.startsWith(head)) return { shared: head, stable: sysStable.slice(head.length) };
  }
  return { shared: '', stable: sysStable };
}

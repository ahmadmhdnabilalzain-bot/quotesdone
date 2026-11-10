// blocking_gate — WHAT THE REQUEST CHAT ASKS OF THE PLACED TRADES, AND WHEN IT MAY CALL A REQUEST READY (10 Nov 2026,
// sales_engineer; founder ledger 1587: "the interview with the customer happens ONCE, with no back-and-forth, and the inquiry
// must be complete enough that every supplier can quote without asking for a missing detail"). Pure, so it is tested offline
// (a_request_is_ready_only_when_every_blocking_spec_is_answered.test.ts); handle.ts runs it. The rule itself lives in
// _shared/inquiry_trades.ts (packFields, readinessOf), which the portal assistant and WhatsApp read too.
// BEFORE: a trade with no category_specs slug had its first six pack specs required, any other trade none, and no spec was
// marked as one a firm price depends on. AFTER: every blocking spec of every placed trade's job checklist is required and
// asked first, a request is not ready until each is answered or recorded as "supplier to advise", a universal spec
// (payment terms, location and emirate) is one question for the whole request, and the site-visit condition is on the brief.
import { packFields, readinessOf, SUPPLIER_TO_ADVISE, universalAnswers, type Readiness, type TradeContext, type UniversalKey } from '../_shared/inquiry_trades.ts';

// The placed trades' spec checklists joined to the slug's (ledgers 1586, 1587; _shared/inquiry_trades.ts packFields). EVERY
// blocking spec of EVERY placed trade's job checklist is REQUIRED, whatever the slug, and goes FIRST, so the slots ask it
// before anything else and the request is not ready without it (inside the 100-message cap: the specs that decide the
// price are the ones asked while there is room). The rest of the pack rides as optional expert questions; a key the slug
// already has is not added twice. A trade whose rows carry no blocking list yet keeps the earlier rule (its first six
// specs required under a generic or missing slug, for the most central trade only).
const GENERIC_SLUGS = new Set(['general', 'general-services-other']);
// deno-lint-ignore no-explicit-any
export function withPack(base: any[], ctx: TradeContext | null, category: string | null, topics: string[] = []): any[] {
  const generic = !category || GENERIC_SLUGS.has(category) || !base.length;
  const have = new Set(base.map((f) => String(f?.key)));
  const pack = packFields(ctx, topics, generic).filter((f) => !have.has(f.key));
  if (!pack.length) return base;
  return [...pack.filter((f) => f.required), ...base, ...pack.filter((f) => !f.required)];
}

// THE BLOCKING GATE (ledger 1587; _shared/inquiry_trades.ts readinessOf). Run on the status every other gate settled: a
// 'ready' request with a blocking spec that has neither an answer nor a recorded "does not know" is not ready, and the
// open blocking specs are what is asked (the first four, in the checklist's order). Pure, so it is tested offline.
// deno-lint-ignore no-explicit-any
export function blockingGate(status: string, ctx: TradeContext | null, topics: string[], specs: Record<string, unknown>, unknown: Iterable<string>, siteVisit: string[] = [],
  universal: Partial<Record<UniversalKey, string>> = universalAnswers({ specs })): { status: string; verdict: Readiness; questions: string[] } {
  const verdict = readinessOf(ctx, topics, specs, unknown, siteVisit, universal);
  if (status === 'ready' && !verdict.ready) return { status: 'needs_info', verdict, questions: verdict.open.slice(0, 4).map((o) => o.question) };
  return { status, verdict, questions: [] };
}
/** The ready brief carries the blocking rule's outcome: each "does not know" as SUPPLIER_TO_ADVISE under its key (so
 *  inquiries.spec shows it to every supplier), and every site-visit condition as a known condition (details.site_visit). */
// deno-lint-ignore no-explicit-any
export function briefConditions(brief: any, verdict: Readiness): void {
  if (!brief || typeof brief !== 'object') return;
  const det = brief.details && typeof brief.details === 'object' ? brief.details : (brief.details = {});
  for (const a of verdict.advised) det[a.key] = SUPPLIER_TO_ADVISE;
  brief.supplier_to_advise = verdict.advised.map((a) => ({ trade: a.trade, key: a.key, spec: a.spec }));
  brief.known_conditions = verdict.site_visits.map((v) => ({ trade: v.trade, kind: 'site_visit', applies: v.applies, text: v.text }));
  if (verdict.site_visits.length) det.site_visit = verdict.site_visits.map((v) => v.text).join(' | ');
}

// THE SERVICE VOCABULARY, AND WHAT A TEXT NAMES IN IT (22 Sep 2026, agent: sales_engineer).
//
// One owner for two questions that must never be answered differently:
//   serviceVocab(admin)        — the active taxonomy_trade_service rows, with their stored vectors.
//   serviceKeysOf(...)         — the '<trade>.<code>' keys an INQUIRY names.
//
// WHY IT IS ONE FILE. The founder calls services "our cross matching main source" and his rule is
// "either exact match or no match" (15 Sep 2026). That rule only holds if the inquiry side and the
// supplier side read the SAME vocabulary with the SAME rule: a second reader, however small, is a second
// answer about who receives a request. supplier_services.ts (the Services tab) imports serviceVocab from
// here rather than keeping its own copy of the select.
//
// NO WORD MATCHING (29 Sep 2026, ruling 890, decision point 93). An inquiry's words used to name a service
// when one of its aliases occurred in them (service_rewrite.servicesFromText). Now a phrase names a service
// only when it IS one of that service's names, whole (service_rewrite.exactService: key, code, name or curated
// alias), or when it MEANS it: clause by clause (meaningClauses), each read in its own space — gte-small for
// English, the multilingual e5 for Arabic — against the stored service vectors, through
// service_meaning.proposeByMeaning (floor + a corroborating name word) — the rule the Services tab uses.
//
// ALL OR NOTHING. The keys gate who receives the request (fn_match_capability p_services): a supplier who
// ticked a service the inquiry names is reached, one who ticked only others is not. A PARTIAL reading would
// therefore drop suppliers for lines nobody read. So the keys are returned only when every clause of the text
// was either exact or read by meaning; otherwise the answer is NO keys (`complete: false`), which leaves the
// request at trade level — nobody is dropped for it — and the caller must not store it as "names nothing".
// CEILING (stated): meaning reads at most MEANING_MAX_LINES clauses per inquiry; a longer brief or BOQ stays at
// trade level.
import { exactService, isStop, jsonText, phraseParts, splitPhrases, type ServiceTerm } from './service_rewrite.ts';
import { MEANING_MAX_LINES, meaningClauses, meaningSpace, parseVec, proposeByMeaning, type MeaningService } from './service_meaning.ts';
import { embedLines, type Embedder } from './meaning_embed.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** EVERY active taxonomy_trade_service row, paged. PostgREST caps one read at max-rows, measured 1,000 on
 *  29 Sep 2026 (an unpaged select answered `0-999/1047`): an unpaged read silently lost 47 services to exact
 *  and meaning matching. The order (trade_code, sort, code) is total, so pages neither skip nor repeat a row;
 *  the loop advances by what each page returned and stops on an empty page, so it holds whatever the cap is.
 *  Any failed page is an error for the whole read — a partial vocabulary is never answered as the vocabulary. */
export async function activeServiceRows<T = Record<string, unknown>>(admin: Admin, columns: string): Promise<{ data: T[]; error: unknown }> {
  const PAGE = 1000, MAX_PAGES = 50; // 50 pages is 50x today's 1,047 rows even at a 1,000-row cap
  const out: T[] = [];
  for (let from = 0, pages = 0; pages < MAX_PAGES; pages++) {
    const { data, error } = await admin.from('taxonomy_trade_service').select(columns).eq('active', true)
      .order('trade_code').order('sort').order('code').range(from, from + PAGE - 1);
    if (error) return { data: [], error };
    if (!data?.length) return { data: out, error: null };
    out.push(...data);
    from += data.length;
  }
  // A server that ignored .range() would answer the same page for ever; that is a failed read, not a loop.
  return { data: [], error: { message: `taxonomy_trade_service did not end within ${MAX_PAGES} pages` } };
}

/** The service vocabulary: every active service, its names, its aliases and its stored vectors (parseVec).
 *  The multilingual vector (embedding_ml) is read separately so that a database without that column yet (its SQL
 *  is applied at release) still answers everything else. */
export async function serviceVocab(admin: Admin): Promise<MeaningService[]> {
  // The two spaces are two independent reads, asked together (27 Oct 2026: ~1,047 rows each, the slowest part of an
  // intake turn that reached ready, inquiry_intake/turn_clock.ts).
  const [{ data, error }, ml] = await Promise.all([
    activeServiceRows(admin, 'trade_code,code,label_en,label_ar,aliases,embedding_gte'),
    activeServiceRows(admin, 'trade_code,code,embedding_ml'),
  ]);
  if (error) return [];
  const mlOf = new Map<string, number[] | null>((ml.error ? [] : ml.data || [])
    .map((r: Record<string, unknown>) => [`${r.trade_code}.${r.code}`, parseVec(r.embedding_ml)] as [string, number[] | null]));
  return (data || []).map(({ embedding_gte, ...s }: Record<string, unknown>) =>
    ({ ...s, vec: parseVec(embedding_gte), vec_ml: mlOf.get(`${s.trade_code}.${s.code}`) ?? null }) as MeaningService);
}

/** Each active trade's English NAME (taxonomy_trade.label; never its aliases), read once per request. It is how
 *  service_meaning.proposeByMeaning corroborates a line that names a trade in general (7 Oct 2026, ledger 1162);
 *  undefined when it could not be read, and meaning then works exactly as without it. */
// deno-lint-ignore no-explicit-any
export async function tradeLabelVocab(admin: any): Promise<Record<string, string> | undefined> {
  const { data, error } = await admin.from('taxonomy_trade').select('code,label').eq('active', true);
  return error ? undefined : Object.fromEntries((data || []).map((r: { code: string; label: string }) => [r.code, r.label]));
}

/** Each active trade's own aliases (taxonomy_trade.aliases): what CONFIRMS a meaning hit on a supplier's document
 *  (service_meaning.proposeByMeaning, opts.tradeAliases); never what names a trade. undefined when unread. */
// deno-lint-ignore no-explicit-any
export async function tradeAliasVocab(admin: any): Promise<Record<string, string[]> | undefined> {
  const { data, error } = await admin.from('taxonomy_trade').select('code,aliases').eq('active', true);
  return error ? undefined : Object.fromEntries((data || []).map((r: { code: string; aliases: string[] | null }) => [r.code, r.aliases || []]));
}

/** Each active trade's ARABIC name (taxonomy_trade.label_ar), for trade_resolve's exact-name path; undefined when unread. */
// deno-lint-ignore no-explicit-any
export async function tradeArNameVocab(admin: any): Promise<Record<string, string> | undefined> {
  const { data, error } = await admin.from('taxonomy_trade').select('code,label_ar').eq('active', true);
  return error ? undefined : Object.fromEntries((data || []).filter((r: { label_ar: string | null }) => r.label_ar)
    .map((r: { code: string; label_ar: string }) => [r.code, r.label_ar]));
}

export type ServiceKeysState = 'nothing_to_read' | 'exact' | 'on' | 'too_long' | 'service_vectors_missing' | 'embedding_unavailable';
export type ServiceKeys = { keys: string[]; state: ServiceKeysState; complete: boolean; parts_read: number };
export type ServiceKeysDeps = { services: MeaningService[]; embed: Embedder };

/**
 * The service keys an inquiry asks for: its brief and every string in its BOQ, read exactly or by meaning,
 * all or nothing (see the header). An empty `keys` with `complete: true` is a real answer (the text names no
 * service this taxonomy knows); with `complete: false` it means "not read" and must not be stored as one.
 */
/** THE REQUEST'S OWN TRADES BOUND THE SERVICES READ FROM ITS PROSE (11 Nov 2026, customer_support; the paid registration
 *  certification's absurd service proposals, checked on the customer side). serviceKeysOf reads a brief by meaning with one head
 *  word to confirm, the rule that offered "Recording studio equipment" to an MEP contractor whose profile said "our own team and
 *  equipment". On the customer side a key of another trade WIDENS the request: fn_match_capability adds a named service's trade
 *  (customer_api/lib/state_service_keys.ts keysOfTrade says the same of a split child). So a key read from the prose is kept only
 *  in a trade the request itself was placed in. `codes` empty: nothing is known to bound them by, and they are kept as before.
 *  Prevented by: _shared/a_proposed_service_is_grounded_in_the_suppliers_own_documents.test.ts */
export function keysInTrades(keys: string[], codes: Iterable<string>): string[] {
  const inScope = new Set(codes);
  return inScope.size ? keys.filter((k) => inScope.has(k.split('.')[0])) : keys;
}

export async function serviceKeysOf(brief: string, boq: unknown, deps: ServiceKeysDeps): Promise<ServiceKeys> {
  const text = [String(brief || ''), jsonText(boq).join('\n')].filter((s) => s.trim()).join('\n');
  const keys = new Set<string>();
  const pending: string[] = [];
  const add = (s: ServiceTerm) => keys.add(`${s.trade_code}.${s.code}`);
  for (const phrase of splitPhrases(text)) {
    const whole = exactService(phrase, deps.services);
    if (whole) { add(whole); continue; }
    // A prose-shaped phrase ("Supply and install ducting for the villa") has no list parts, but it is exactly
    // what a customer writes: it is read by meaning, clause by clause, unless every word of it is glue.
    const parts = phraseParts(phrase);
    for (const p of parts.length ? parts : (phrase.split(/\s+/).some((w) => !isStop(w)) ? [phrase] : [])) {
      const s = exactService(p, deps.services);
      if (s) { add(s); continue; }
      for (const c of meaningClauses(p)) {
        const e = exactService(c, deps.services);
        if (e) add(e); else if (!pending.includes(c)) pending.push(c);
      }
    }
  }
  const done = (state: ServiceKeysState, complete: boolean, read = 0): ServiceKeys =>
    ({ keys: complete ? [...keys].sort() : [], state, complete, parts_read: read });
  if (!pending.length) return done(keys.size ? 'exact' : 'nothing_to_read', true);
  if (pending.length > MEANING_MAX_LINES) return done('too_long', false);
  const needs = new Set(pending.map(meaningSpace));
  if ((needs.has('gte') && !deps.services.some((s) => s.vec)) || (needs.has('ml') && !deps.services.some((s) => s.vec_ml))) {
    return done('service_vectors_missing', false);
  }
  const lines = await embedLines(pending, deps.embed);
  if (lines.some((l) => !l.vec)) return done('embedding_unavailable', false);
  for (const m of proposeByMeaning(lines, deps.services, { stated: [...keys] })) keys.add(m.key);
  return done('on', true, pending.length);
}

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

/** The service vocabulary: every active service, its names, its aliases and its stored vectors (parseVec).
 *  The multilingual vector (embedding_ml) is read separately so that a database without that column yet (its SQL
 *  is applied at release) still answers everything else. */
export async function serviceVocab(admin: Admin): Promise<MeaningService[]> {
  const { data, error } = await admin.from('taxonomy_trade_service')
    .select('trade_code,code,label_en,label_ar,aliases,embedding_gte').eq('active', true).order('trade_code').order('sort');
  if (error) return [];
  const ml = await admin.from('taxonomy_trade_service').select('trade_code,code,embedding_ml').eq('active', true);
  const mlOf = new Map<string, number[] | null>((ml.error ? [] : ml.data || [])
    .map((r: Record<string, unknown>) => [`${r.trade_code}.${r.code}`, parseVec(r.embedding_ml)] as [string, number[] | null]));
  return (data || []).map(({ embedding_gte, ...s }: Record<string, unknown>) =>
    ({ ...s, vec: parseVec(embedding_gte), vec_ml: mlOf.get(`${s.trade_code}.${s.code}`) ?? null }) as MeaningService);
}

export type ServiceKeysState = 'nothing_to_read' | 'exact' | 'on' | 'too_long' | 'service_vectors_missing' | 'embedding_unavailable';
export type ServiceKeys = { keys: string[]; state: ServiceKeysState; complete: boolean; parts_read: number };
export type ServiceKeysDeps = { services: MeaningService[]; embed: Embedder };

/**
 * The service keys an inquiry asks for: its brief and every string in its BOQ, read exactly or by meaning,
 * all or nothing (see the header). An empty `keys` with `complete: true` is a real answer (the text names no
 * service this taxonomy knows); with `complete: false` it means "not read" and must not be stored as one.
 */
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

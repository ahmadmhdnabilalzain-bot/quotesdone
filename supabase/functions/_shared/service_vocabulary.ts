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
// only when it IS that service exactly (service_rewrite.exactService), or when it MEANS it: gte-small over the
// stored taxonomy_trade_service.embedding_gte, through service_meaning.proposeByMeaning (floor + the
// service's head word in the line) — the rule the Services tab and the document reader use.
//
// ALL OR NOTHING. The keys gate who receives the request (fn_match_capability p_services): a supplier who
// ticked a service the inquiry names is reached, one who ticked only others is not. A PARTIAL reading would
// therefore drop suppliers for lines nobody read. So the keys are returned only when every part of the text
// was either exact or read by meaning; otherwise the answer is NO keys (`complete: false`), which leaves the
// request at trade level — nobody is dropped for it — and the caller must not store it as "names nothing".
// CEILING (stated): meaning reads at most MEANING_MAX_LINES parts per inquiry (the edge CPU cap); a longer
// brief or BOQ stays at trade level. gte-small is an English model, so Arabic is served by the exact path only.
import { exactService, isStop, jsonText, phraseParts, splitPhrases, type ServiceTerm } from './service_rewrite.ts';
import { MEANING_MAX_LINES, parseVec, proposeByMeaning, type MeaningService } from './service_meaning.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** The service vocabulary: every active service, its names, its aliases and its stored vector (parseVec). */
export async function serviceVocab(admin: Admin): Promise<MeaningService[]> {
  const { data, error } = await admin.from('taxonomy_trade_service')
    .select('trade_code,code,label_en,label_ar,aliases,embedding_gte').eq('active', true).order('trade_code').order('sort');
  if (error) return [];
  return (data || []).map(({ embedding_gte, ...s }: Record<string, unknown>) => ({ ...s, vec: parseVec(embedding_gte) }) as MeaningService);
}

export type ServiceKeysState = 'nothing_to_read' | 'exact' | 'on' | 'too_long' | 'service_vectors_missing' | 'embedding_unavailable';
export type ServiceKeys = { keys: string[]; state: ServiceKeysState; complete: boolean; parts_read: number };
export type ServiceKeysDeps = { services: (ServiceTerm & { vec?: number[] | null })[]; embed: (text: string) => Promise<number[] | null> };

/**
 * The service keys an inquiry asks for: its brief and every string in its BOQ, read exactly or by meaning,
 * all or nothing (see the header). An empty `keys` with `complete: true` is a real answer (the text names no
 * service this taxonomy knows); with `complete: false` it means "not read" and must not be stored as one.
 */
export async function serviceKeysOf(brief: string, boq: unknown, deps: ServiceKeysDeps): Promise<ServiceKeys> {
  const text = [String(brief || ''), jsonText(boq).join('\n')].filter((s) => s.trim()).join('\n');
  const keys = new Set<string>();
  const pending: string[] = [];
  for (const phrase of splitPhrases(text)) {
    const whole = exactService(phrase, deps.services);
    if (whole) { keys.add(`${whole.trade_code}.${whole.code}`); continue; }
    // A prose-shaped phrase ("Supply and install ducting for the villa") has no list parts, but it is exactly
    // what a customer writes: it is read by meaning whole, unless every word of it is glue.
    const parts = phraseParts(phrase);
    for (const p of parts.length ? parts : (phrase.split(/\s+/).some((w) => !isStop(w)) ? [phrase] : [])) {
      const s = exactService(p, deps.services);
      if (s) keys.add(`${s.trade_code}.${s.code}`);
      else if (!pending.includes(p)) pending.push(p);
    }
  }
  const done = (state: ServiceKeysState, complete: boolean, read = 0): ServiceKeys =>
    ({ keys: complete ? [...keys].sort() : [], state, complete, parts_read: read });
  if (!pending.length) return done(keys.size ? 'exact' : 'nothing_to_read', true);
  if (pending.length > MEANING_MAX_LINES) return done('too_long', false);
  const services = deps.services.filter((s) => s.vec) as MeaningService[];
  if (!services.length) return done('service_vectors_missing', false);
  const vecs = await Promise.all(pending.map((p) => deps.embed(p).catch(() => null)));
  if (vecs.some((v) => !v)) return done('embedding_unavailable', false);
  for (const m of proposeByMeaning(pending.map((p, i) => ({ text: p, vec: vecs[i] })), services, { stated: [...keys] })) keys.add(m.key);
  return done('on', true, pending.length);
}

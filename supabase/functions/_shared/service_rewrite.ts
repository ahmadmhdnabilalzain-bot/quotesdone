// THE SALES ENGINEER'S REWRITE — a supplier's own words about its services, turned into the platform's
// standard service list. Seat: sales_engineer. 15 Sep 2026.
//
// Founder, 15 Sep 2026: "for adding services its not a checkbox or drop down menu. i told you its a voice
// to text or text box. once filled the sales engineer will rewrite that professionally since he will cross
// match based on that." So the supplier types (or, once the voice switch is on, speaks) one free text, and
// this module rewrites it. The supplier sees the result, confirms or edits it, and the CONFIRMED service
// keys are what matching reads (fn_match_capability p_services).
//
// NO WORD MATCHING (29 Sep 2026, ruling 890, decision point 93 services.from_text). Until today every service
// alias (service_aliases.json, taxonomy_trade_service.aliases) was searched for inside the supplier's words, and
// the inquiry's, word-start anchored: a phrase named a service because one of its words was on a list. That is
// gone. This module now decides only what is EXACT; what a phrase MEANS is read over the stored service vectors
// by the caller (supplier_services.servicesRewrite through service_meaning.proposeByMeaning, the supplier's own typed words).
// An inquiry is no longer read here (11 Nov 2026, rulings 1627 and 1628: its keys are the intake model's). The rules:
//   1. The text is split into phrases at line breaks, bullets, numbered items, commas (, ،), semicolons
//      (; ؛), '|' and full stops.
//   2. A phrase that IS a service — its key ("hvac.ducting"), its code ("ducting", "false ceiling"), its
//      English or Arabic name ("False ceilings", "الأسقف المعلقة") or one of its curated aliases ("cable tray",
//      "تمديدات كهربائية"), after the Arabic folding public.fn_ar_norm applies, diacritics, case and spacing — is
//      that service. Equality with the WHOLE phrase or list item, a name lookup, never a word inside it
//      (coordinator's ruling, 29 Sep 2026). A supply-only company is never named an installation service.
//   3. Otherwise the phrase is split at 'and' / 'or' / '&' / '+' / a spaced 'و' and each part is tried the
//      same way. Prose (sentence glue, where the company works) is not a part worth keeping.
//   4. A part that is no service exactly is kept in the supplier's words, tidied, and FLAGGED — never
//      dropped, never guessed. The caller gives these parts to meaning, which may PROPOSE a service the
//      supplier then adds (off until he does: ServicesTab, finding SP-F-06). A part names a TRADE only when it
//      IS one: fn_norm_trades decides (withExactTrades); a trade is never read from words (ledger 1054).
// EXACT OR NONE (founder, 14 Sep 2026: "either exact match or no match"): no alias list, no stemmer. A part
// neither exact nor understood stays the supplier's own words until the sales engineer maps it.
import { arNorm, termPattern } from './alias_pattern.ts';

export type ServiceTerm = { trade_code: string; code: string; label_en: string; label_ar: string; aliases?: string[] | null };
export type RewriteItem =
  // `part`: the words of `from` that ARE this service's name (the whole phrase, or one list part of it, its delivery frame cut).
  // It is the supplier's own name for the service, which the alias queue cites (profile_services.aliasPairsOf).
  | { kind: 'service'; key: string; trade: string; label_en: string; label_ar: string; from: string; part?: string }
  | { kind: 'trade'; trades: string[]; text: string; from: string }
  | { kind: 'unmatched'; text: string; from: string };
export type Rewrite = { items: RewriteItem[]; service_keys: string[]; own_words: string[]; summary_en: string; summary_ar: string };

export const MAX_TEXT = 2000;
export const MAX_PHRASES = 40;
export const PHRASE_LEN = 120;
// A phrase is cut at MATCH_LEN: no phrase longer than this is a name, and the cut bounds the work whatever
// the supplier sends (an edge function has a CPU cap no deadline bounds).
export const MATCH_LEN = 300;

const HAS_AR = /[؀-ۿ]/;
// Words that describe how a service is delivered, or glue a sentence together, rather than naming a
// service. Compared after arNorm, with a leading و / ال / وال removed from Arabic words.
//
// A LEFTOVER MADE ONLY OF THESE IS NOT A PENDING TAXONOMY ITEM. Measured 18 Sep 2026 against a
// realistic supplier paragraph ("We are an interior decoration and fit-out company in Dubai. We do
// gypsum partitions... plus chiller maintenance..."): the rewriter handed the sales engineer "We are
// an", "Plus", "ننفذ" and "تجهيز في دبي" as services to decide on. Nothing the supplier named was
// lost — that queue was filling with grammar. The words below are the ones that did it: sentence
// verbs and pronouns, the connectives a list uses, and the emirates a company says it works in.
const STOP = new Set([
  'and', 'or', 'of', 'for', 'the', 'a', 'an', 'in', 'on', 'with', 'to', 'all', 'any', 'other', 'type', 'types',
  'kind', 'kinds', 'various', 'general', 'including', 'etc', 'supply', 'supplying', 'supplier', 'suppliers',
  'installation', 'installations', 'install', 'installing', 'fixing', 'works', 'work', 'service', 'services',
  'solution', 'solutions', 'maintenance', 'repair', 'repairs', 'company', 'contracting', 'contractor',
  'contractors', 'llc', 'we', 'our', 'do', 'provide', 'providing', 'also', 'system', 'systems',
  // sentence glue: a leftover made only of these says nothing about what the company does
  'are', 'is', 'was', 'be', 'been', 'am', 'us', 'you', 'they', 'it', 'its', 'their', 'his', 'her',
  'have', 'has', 'had', 'can', 'will', 'would', 'shall', 'may', 'plus', 'both', 'from', 'by', 'at', 'as',
  'that', 'this', 'these', 'those', 'who', 'which', 'what', 'where', 'when', 'than', 'then', 'such',
  'many', 'most', 'some', 'more', 'every', 'each', 'well', 'full', 'complete', 'new', 'best', 'top',
  'quality', 'high', 'professional', 'reliable', 'specialist', 'specialised', 'specialized', 'expert',
  'experts', 'experienced', 'leading', 'years', 'year', 'since', 'based', 'located', 'offer', 'offering',
  'carry', 'carrying', 'out', 'undertake', 'undertaking', 'execute', 'execution', 'deal', 'dealing',
  // the UAE, as a company writes where it works
  'uae', 'emirates', 'emirate', 'dubai', 'abu', 'dhabi', 'sharjah', 'ajman', 'fujairah', 'ras', 'khaimah',
  'quwain', 'umm', 'alquwain', 'rak', 'auh', 'dxb', 'wide', 'countrywide', 'nationwide', 'across',
  'في', 'من', 'مع', 'علي', 'الي', 'جميع', 'كافه', 'كل', 'انواع', 'نوع', 'توريد', 'تركيب', 'اعمال', 'عمل',
  'خدمات', 'خدمه', 'صيانه', 'تصليح', 'تنفيذ', 'نقوم', 'نقدم', 'لدينا', 'شركه', 'مقاولات', 'غيرها', 'ايضا',
  'انظمه', 'نظام',
  'ننفذ', 'ننفذها', 'نعمل', 'نحن', 'نستطيع', 'يمكننا', 'ونقوم', 'وننفذ', 'كذلك', 'حسب', 'الطلب', 'طلب',
  'تجهيز', 'تجهيزات',   // "fit-out" as a verb; "تجهيز مطابخ" still keeps مطابخ, "تجهيز في دبي" keeps nothing
  'خبره', 'سنوات', 'سنه', 'متخصصون', 'متخصصه', 'متخصص', 'مختصون', 'افضل', 'اعلي', 'جوده', 'احترافيه',
  'مؤسسه', 'مجموعه', 'فرع', 'فروع', 'مقرها', 'مقرنا', 'كامله', 'كامل', 'شامله', 'شامل',
  'دبي', 'ابوظبي', 'الشارقه', 'عجمان', 'الفجيره', 'الخيمه', 'القيوين', 'راس', 'ام', 'الامارات', 'امارات',
].map(arNorm));

export const isStop = (w: string): boolean => {
  const n = arNorm(w).toLowerCase();
  if (n.length < 3) return true;
  // The Arabic proclitics a word can carry: و/ف, then ب/ل/ك, then ال. "بأعمال" is أعمال with ب in front
  // — audit 21 Sep 2026 ("نقوم بأعمال الجبس ...") left "نقوم بأعمال" in the sales engineer's queue
  // because only و / ال / وال were stripped here. Only the STOP test uses this; the matcher has its own.
  const forms = [n, n.replace(/^و/, ''), n.replace(/^ال/, ''), n.replace(/^وال/, ''), n.replace(/^[وف]?[بلك]?(?:ال)?/, '')];
  return forms.some((f) => STOP.has(f) || f.length < 2);
};

/** Is this leftover worth putting in front of the sales engineer at all?
 *
 *  A service name is a short noun phrase — "Helicopter window polishing", "تلميع نوافذ المروحيات",
 *  "supply and installation of aluminium composite panel cladding". A sentence about the company is
 *  long and says almost nothing — "We are a leading company with many years of experience" is ten
 *  words carrying one content word. So: three or more content words is a service however long it is,
 *  and below that it has to be short. Chasing every adjective into STOP would never end; this is the
 *  shape difference, and it does not need a word list to keep working.
 *
 *  This can only drop PROSE: anything short stays whatever it is — the founder's "never dropped" is about
 *  a service the supplier named, not about the sentence it was wrapped in. It decides nothing about WHICH
 *  service a part is; it only sets aside the parts no one would read as one. */
export const looksLikeAService = (text: string): boolean => {
  const words = text.split(/\s+/).filter(Boolean);
  const content = words.filter((w) => !isStop(w)).length;
  return content >= 3 || (content >= 1 && words.length <= 6);
};


/** Rule 1: the phrases of a free text, at most MAX_PHRASES, each trimmed and on one line.
 *  The list marker is stripped AFTER the split, not inside it: the line-break branch consumes the
 *  newline first, so a `(?:^|\s)•` branch could never match a bullet at the start of a line
 *  (measured by service_rewrite.test.ts, which read back "• d4" and "2) e5" as phrases). */
export function splitPhrases(text: string, maxText = MAX_TEXT, maxPhrases = MAX_PHRASES): string[] {
  return String(text ?? '').slice(0, maxText)
    .split(/\r?\n|[,،;؛|]+|\.\s+/)
    .map((s) => s.replace(/^\s*(?:[•·▪●◦*–—-]|\d{1,2}[.)])\s+/, '').replace(/\s+/g, ' ').trim().slice(0, MATCH_LEN))
    .filter((s) => s.length >= 2)
    .slice(0, maxPhrases);
}

/** The supplier's words, tidied: one space, no stray connector at either end, sentence case in English
 *  (short all-capital words such as VRF or HDPE are kept as written), clipped. Arabic is left as typed. */
export function tidy(text: string): string {
  let s = String(text ?? '').replace(/\s+/g, ' ')
    .replace(/^[\s,،;؛.:\-–—•·*&+/]+|[\s,،;؛.:\-–—•·*&+/]+$/g, '')
    .replace(/^(?:and|or|&)\s+/i, '').replace(/^و\s+/, '').trim();
  // The Arabic conjunction attaches to its word, so a list item reads "وتلميع نوافذ" and the supplier
  // sees its own service with an "and" stuck to the front. Stripped only on a MULTI-WORD phrase: a
  // single word could legitimately begin with و (وقود, وكالة) and must not lose its first letter.
  if (/^و[ء-ي]/.test(s) && s.includes(' ')) s = s.slice(1);
  if (!HAS_AR.test(s) && /[a-z]/i.test(s)) {
    s = s.split(' ').map((w) => (/^[A-Z0-9&]{2,4}$/.test(w) ? w : w.toLowerCase())).join(' ');
    s = s.charAt(0).toUpperCase() + s.slice(1);
  }
  return s.slice(0, PHRASE_LEN).trim();
}

// THE ALIAS PATTERN, KEPT FOR ONE READER ONLY (29 Sep 2026). Nothing in this module matches aliases any more
// (decision point 93). service_meaning.proposeByMeaning still uses an alias as the corroborating word for a
// vector hit whose line holds no head word of the service's name — decision point 92
// (services.meaning_candidates), pending on its own. A short English alias is a whole word: "ups" must not
// corroborate UPS systems in "upset", nor "pos" POS terminals in "position".
const SHORT_ALIAS = 3;
export function servicePattern(alias: string): RegExp | null {
  const re = termPattern(alias);
  if (!re) return null;
  const a = arNorm(alias).trim();
  const short = !HAS_AR.test(a) && a.replace(/[^\p{L}\p{N}]/gu, '').length <= SHORT_ALIAS;
  return new RegExp(short ? re.source + '(?:s)?(?![\\p{L}\\p{N}])' : re.source, 'giu');
}

// WHAT A SUPPLY-ONLY COMPANY IS NOT PROPOSED (21 Sep 2026). An importer, wholesaler or stockist sells
// the goods; it does not install them. A service whose standard name is installation, contracting or
// after-sales work is not proposed to such a company, whatever word in its catalogue happened to name
// it ("Cat 6 Cable" is goods; "Structured cabling" is a service). Read from the service's own English
// label, so a service added next year is classified the day it is added. A label that also says
// supply ("Lighting supply & installation") carries the supply half too and stays.
const INSTALL_WORK = /install|cabling|wiring|contract|fit[-_ ]?out|erection|\bworks?\b|commissioning|construction|maintenance|servic(?:e|es|ing)\b|repair|refurbish|moderni[sz]ation|programming|integration|drawings|approvals|supervision|design/i;
const SUPPLY_WORD = /supply|sales|\bsale\b/i;
export const isInstallWork = (t: Pick<ServiceTerm, 'label_en' | 'code'>): boolean => {
  const s = `${t.label_en} ${String(t.code ?? '').replace(/_/g, ' ')}`;
  return INSTALL_WORK.test(s) && !SUPPLY_WORD.test(s);
};

/** A name as the exact path compares it: fn_ar_norm's folding, every other diacritic removed (NFKD), lower case,
 *  one space, underscores and hyphens as spaces, no stray punctuation at either end. Nothing is stemmed, no
 *  article or plural is removed, and nothing is dropped. */
export const exactName = (s: string): string =>
  arNorm(String(s ?? '')).normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[_\-–—]+/g, ' ').replace(/\s+/g, ' ')
    .replace(/^[\s,،;؛.:•·*&+/()]+|[\s,،;؛.:•·*&+/()]+$/g, '').trim();

/** Rule 2's index: every exact name of every service -> the service. A name is its key, its code, its English or
 *  Arabic name, or one of its curated aliases (taxonomy_trade_service.aliases) — a NAME LOOKUP of the whole
 *  phrase, as fn_norm_trades looks up an intake slug (coordinator's ruling on decision point 93, 29 Sep 2026: "no
 *  substrings, no partial tokens, no word lists over free text"). Built once per vocabulary array. A name two
 *  services share names neither (exact or none). */
const EXACT = new WeakMap<ServiceTerm[], Map<string, ServiceTerm | null>>();
export function exactIndex(vocab: ServiceTerm[]): Map<string, ServiceTerm | null> {
  const hit = EXACT.get(vocab);
  if (hit) return hit;
  const m = new Map<string, ServiceTerm | null>();
  const put = (name: string, s: ServiceTerm) => {
    const k = exactName(name);
    if (k.length < 2) return;
    const cur = m.get(k);
    m.set(k, cur === undefined || cur === s || (cur && cur.trade_code === s.trade_code && cur.code === s.code) ? s : null);
  };
  for (const s of vocab) for (const n of [`${s.trade_code}.${s.code}`, s.code, s.label_en, s.label_ar, ...(s.aliases || [])]) if (n) put(n, s);
  EXACT.set(vocab, m);
  return m;
}

/** The service a text IS, or null. `supplyOnly`: an installation service is never a supply-only company's. */
export function exactService(text: string, vocab: ServiceTerm[], supplyOnly = false): ServiceTerm | null {
  const s = exactIndex(vocab).get(exactName(text)) ?? null;
  return s && !(supplyOnly && isInstallWork(s)) ? s : null;
}

/** WHO THE WORK IS FOR IS NOT A SERVICE (2 Nov 2026). "... glass curtain walls for villas and offices": what
 *  follows "for" names the customer or building the work is done for, so it is cut before the phrase is split at
 *  "and" — otherwise "offices" became a part of its own and meaning proposed "Serviced offices" for it. Grammar,
 *  not vocabulary: no word list of customers or buildings. Arabic: the preposition ل attached to the article
 *  (للفلل والمكاتب) or standing alone as لـ. A phrase that IS a service name is matched whole before this is
 *  reached, so a name holding "for" survives. A phrase that begins with "for" is left whole. */
const AUDIENCE_TAIL = /\s+for\s+.*$|\s+لـ?\s*(?=ال).*$|\s+لل\p{L}.*$/isu;
export const withoutAudience = (phrase: string): string => {
  const cut = phrase.replace(AUDIENCE_TAIL, '').trim();
  return cut.length >= 2 ? cut : phrase;
};

/** HOW THE WORK IS DELIVERED IS NOT PART OF ITS NAME (10 Nov 2026, sales_engineer; founder ledger 1573/1579). A profile
 *  writes "Supply and installation of PVC decorative panels"; split at "and" that is "Supply" and "installation of PVC
 *  decorative panels", and the second never equalled a name, so the supplier's own service stayed unnamed (design audit
 *  10 Nov 2026, the PVC dry-run). The "<supply | installation | fixing> of" FRAME is cut from the front of a part, as
 *  the audience after "for" is cut from its end: grammar, not vocabulary, and the rest must still EQUAL a name whole.
 *  Only the supply/install frame: "maintenance of", "repair of" and "design of" name a different service and stay. */
const DELIVERY_FRAME = /^(?:the\s+)?(?:supply|supplying|installation|installing|install|fixing|supply\s+and\s+installation|supply\s*&\s*installation)\s+of\s+(?=\S)/i;
export const withoutFrame = (part: string): string => {
  const cut = part.replace(DELIVERY_FRAME, '').trim();
  return cut.length >= 2 ? cut : part;
};

/** Rule 3: a phrase's parts, split at the connectives a list uses. Prose is set aside: a phrase that is not
 *  service-shaped as a whole ("We are a leading company with many years of experience") has no parts. */
export function phraseParts(phrase: string): string[] {
  const head = withoutAudience(phrase);
  if (!looksLikeAService(head)) return [];
  return head.split(/\s+(?:and|or|with|plus)\s+|\s*[&+]\s*|\s+و\s+/i)
    .map((p) => withoutFrame(p.trim())).filter((p) => p.length >= 2 && looksLikeAService(p));
}

/** Rule 4: a part that is no service exactly — the supplier's own words for review.
 *  A part that IS a trade code or slug becomes a trade item afterwards (withExactTrades), never here. */
function wordsItem(text: string, from: string): RewriteItem | null {
  const t = tidy(text);
  if (t.length < 2) return null;
  return looksLikeAService(t) ? { kind: 'unmatched', text: t, from } : null;
}

const serviceItem = (s: ServiceTerm, from: string, part: string = from): RewriteItem =>
  ({ kind: 'service', key: `${s.trade_code}.${s.code}`, trade: s.trade_code, label_en: s.label_en, label_ar: s.label_ar, from, part });

/** The whole rewrite, exactly. `services` are the active taxonomy_trade_service rows. */
export type RewriteOptions = { supplyOnly?: boolean; maxText?: number; maxPhrases?: number };
export function rewriteServices(text: string, services: ServiceTerm[], opts: RewriteOptions = {}): Rewrite {
  const items: RewriteItem[] = [];
  const seenKey = new Set<string>(); const seenWords = new Set<string>();
  const push = (it: RewriteItem | null) => {
    if (!it) return;
    if (it.kind === 'service') { if (seenKey.has(it.key)) return; seenKey.add(it.key); items.push(it); return; }
    const k = arNorm(it.text).toLowerCase();
    if (seenWords.has(k)) return;
    seenWords.add(k); items.push(it);
  };
  for (const phrase of splitPhrases(text, opts.maxText, opts.maxPhrases)) {
    // The whole phrase first: a name may itself hold a connective ("Water heaters & pumps").
    const whole = exactService(phrase, services, opts.supplyOnly);
    if (whole) { push(serviceItem(whole, phrase)); continue; }
    const parts = phraseParts(phrase);
    // THE TAIL CREATES NO PART OF ITS OWN, BUT IT IS NOT LOST (review of #1756): "Repairs for air conditioners",
    // "Cranes for hire", "صيانة للمصاعد" name their object after "for". When the head is no service, the supplier's
    // own words keep the whole wording; only a head that IS a service drops the tail ("False ceilings for hotels").
    const tail = parts.length ? phrase.slice(withoutAudience(phrase).length).trim() : '';
    const own = (p: string, last: boolean) => wordsItem(last && tail ? `${p} ${tail}` : p, phrase);
    if (parts.length <= 1) { const p = parts[0] ?? phrase; const s = exactService(p, services, opts.supplyOnly); push(s ? serviceItem(s, phrase, p) : own(p, true)); continue; }
    parts.forEach((p, i) => { const s = exactService(p, services, opts.supplyOnly); push(s ? serviceItem(s, phrase, p) : own(p, i === parts.length - 1)); });
  }
  return finishRewrite(items);
}

/** The rewrite's summary fields, over its items. A trade the supplier named is dropped when a service of
 *  that trade already carries it, and a trade named twice is kept once. */
export function finishRewrite(items: RewriteItem[]): Rewrite {
  const serviceTrades = new Set(items.flatMap((i) => (i.kind === 'service' ? [i.trade] : [])));
  const seenTrades = new Set<string>();
  const final = items.filter((i) => {
    if (i.kind !== 'trade') return true;
    if (i.trades.every((c) => serviceTrades.has(c))) return false;
    const tk = [...i.trades].sort().join('+');
    if (seenTrades.has(tk)) return false;
    seenTrades.add(tk); return true;
  });
  const label = (i: RewriteItem, ar: boolean) => (i.kind === 'service' ? (ar ? i.label_ar : i.label_en) : i.text);
  return {
    items: final,
    service_keys: final.flatMap((i) => (i.kind === 'service' ? [i.key] : [])),
    own_words: final.flatMap((i) => (i.kind === 'service' ? [] : [i.text])),
    summary_en: final.map((i) => label(i, false)).join(' · '),
    summary_ar: final.map((i) => label(i, true)).join(' · '),
  };
}

/** The own-words items whose text could be a code or a slug: what the caller asks fn_norm_trades about. */
export const ownWordsOf = (rw: Rewrite): string[] =>
  [...new Set(rw.items.flatMap((i) => (i.kind === 'unmatched' ? [i.text] : [])))];

/** Rule 4, exactly: an own-words item that public.fn_norm_trades resolved (`exact`: text -> codes, from
 *  fn_norm_trades_many) becomes a trade item with those codes. Nothing else changes. */
export function withExactTrades(rw: Rewrite, exact: Record<string, string[]> | null | undefined): Rewrite {
  if (!exact || !Object.keys(exact).length) return rw;
  return finishRewrite(rw.items.map((i): RewriteItem => {
    if (i.kind !== 'unmatched') return i;
    const codes = exact[i.text];
    return Array.isArray(codes) && codes.length ? { kind: 'trade', trades: [...codes], text: i.text, from: i.from } : i;
  }));
}

// ── WHAT A STATED SERVICE ALSO COVERS ──────────────────────────────────────────────────────────────
// Founder, 15 Sep 2026: "you gotta make sure the sales engineer is smart in cross matching. for example
// someone who does decoration is definitely able to do flooring even through words cross matching is not
// there." public.service_implication (service_implications.json) is the sales engineer's curated list of
// those relations, each with its reason in English and Arabic. It is applied ONE level deep: what a stated
// service implies is added, what an implied service would imply is not (decoration implies false ceilings;
// false ceilings imply acoustic ceilings; decoration does NOT imply acoustic ceilings). The SQL twin is in
// fn_services_effective, and the two are held to the same seed by scripts/checks.
export type Implication = { from: string; to: string; en: string; ar: string };
export type Implied = { key: string; because: { from: string; en: string; ar: string }[]; removed: boolean };

/** The seed file's grouped rows, one relation per row. */
export const flattenImplications = (groups: { from: string; to: string[]; en: string; ar: string }[]): Implication[] =>
  groups.flatMap((g) => g.to.map((to) => ({ from: g.from, to, en: g.en, ar: g.ar })));

/** What `sources` (stated service keys and trade codes) imply, one level, minus what is already stated.
 *  An implied key the supplier unticked is still returned, marked removed, so it can be ticked again. */
//
// A SUPPLY-ONLY COMPANY (21 Sep 2026, catalogue_read.ts) gets every implication back already struck out.
// Each row of the map is a works relation — what a firm that PERFORMS X also performs ("CCTV installers
// fit intruder alarms"); a trader's catalogue lists what it stocks, and implying stock it did not list is
// a guess. Returned removed (not dropped) so the save stores it in services_removed, fn_services_effective
// subtracts it at match time, and the supplier can still tick one back.
export function impliedServices(sources: string[], map: Implication[], stated: string[], removed: string[] = [], supplyOnly = false): Implied[] {
  const src = new Set(sources); const have = new Set(stated); const off = new Set(removed);
  const out = new Map<string, Implied>();
  for (const r of map) {
    if (!src.has(r.from) || have.has(r.to)) continue;
    const it = out.get(r.to) || { key: r.to, because: [], removed: supplyOnly || off.has(r.to) };
    it.because.push({ from: r.from, en: r.en, ar: r.ar });
    out.set(r.to, it);
  }
  return [...out.values()].sort((a, b) => a.key.localeCompare(b.key));
}

/** Every string inside a JSON value (a BOQ's descriptions, whatever its shape), joined one per line. */
export function jsonText(v: unknown, out: string[] = [], depth = 0): string[] {
  if (depth > 6 || out.length > 400) return out;
  if (typeof v === 'string') { if (v.trim()) out.push(v.trim()); }
  else if (Array.isArray(v)) for (const x of v) jsonText(x, out, depth + 1);
  else if (v && typeof v === 'object') for (const x of Object.values(v)) jsonText(x, out, depth + 1);
  return out;
}

// drawingGlance — what a drawing IS, said the moment it is attached (19 Nov 2026, sales_engineer; founder ruling 1533:
// "Drawings should feel like attaching a drawing to Claude: it understands it, fast. Why does our app not work that way?").
//
// MEASURED (SELECT, function_edge_logs, all 16 analyze_drawing requests of 17-18 Nov 2026, the only ones in 30 days): the
// customer's first answer came when analyze_drawing returned, p50 109.5 s / p90 129.5 s after the call, and on a desktop the
// schedule OCR before it adds up to 57 s more (NewRequest readSchedules). For those two minutes the screen said nothing.
// The PDF is already in the customer's browser, and its own text layer says what the set is: how many sheets, which trades
// (duct, AHU, sprinkler, distribution board...), which kinds of sheet (layouts, schedules, sections). This reads that text,
// with no model and no network, and the portal says it at once, before the server's read starts.
//
// WHAT IT NEVER SAYS. Only a count and words from the fixed lists below are ever shown: no text of the drawing is echoed, so
// no name, address or plot on a title block can appear in the glance. It is shown to the customer who attached the file and
// is never sent anywhere: nothing here reaches a supplier or the server (the anonymity rules live on the server path).
// No import: the counted noun is passed in (NewRequest: countPhrase(lang, n, 'page')), so this module runs as it is in
// the browser bundle and under deno test.

type Lang = 'en' | 'ar';
type Term = { key: string; en: string; ar: string; words: RegExp };

// A trade is named when its words occur at least TRADE_MIN_HITS times across the set: one stray "DB" or "WC" is not a trade.
export const TRADE_MIN_HITS = 2;
// At most this many trades are named, the most mentioned first.
export const TRADES_SHOWN = 3;

export const TRADES: Term[] = [
  { key: 'hvac', en: 'HVAC', ar: 'التكييف والتهوية', words: /\b(hvac|ducts?|ductwork|ahu|fcu|vrf|vrv|chillers?|diffusers?|grilles?|dampers?|air[- ]conditioning|exhaust fans?|fresh air|chilled water)\b/gi },
  { key: 'plumbing', en: 'plumbing', ar: 'السباكة', words: /\b(plumbing|drainage|sanitary|soil pipes?|waste pipes?|water supply|manholes?|floor drains?|water heaters?|ppr|upvc)\b/gi },
  { key: 'electrical', en: 'electrical', ar: 'الكهرباء', words: /\b(electrical|lighting|light fittings?|luminaires?|sockets?|distribution boards?|smdb|mdb|cable trays?|switchgear|earthing)\b/gi },
  { key: 'fire', en: 'fire fighting and alarm', ar: 'مكافحة الحريق وإنذاره', words: /\b(sprinklers?|fire fighting|fire alarm|fire pumps?|hose reels?|smoke detectors?|fm[- ]?200)\b/gi },
  { key: 'elv', en: 'low current (ELV)', ar: 'التيار الخفيف', words: /\b(elv|cctv|access control|data points?|public address|intercom)\b/gi },
  { key: 'architecture', en: 'architecture', ar: 'المعماري', words: /\b(architectural|elevations?|finishes|door schedule|window schedule)\b/gi },
  { key: 'structure', en: 'structure', ar: 'الإنشائي', words: /\b(structural|reinforcement|rebar|footings?|slab thickness)\b/gi },
  { key: 'fitout', en: 'interior fit-out', ar: 'التشطيبات الداخلية', words: /\b(fit[- ]?out|false ceiling|gypsum|joinery|partitions?|ceiling plan)\b/gi },
];

export const KINDS: Term[] = [
  { key: 'layout', en: 'layouts', ar: 'مخططات توزيع', words: /\b(layouts?|floor plans?|roof plans?)\b/gi },
  { key: 'schedule', en: 'schedules', ar: 'جداول', words: /\b(schedules?)\b/gi },
  { key: 'section', en: 'sections', ar: 'مقاطع', words: /\b(sections?)\b/gi },
  { key: 'detail', en: 'details', ar: 'تفاصيل', words: /\b(details?)\b/gi },
  { key: 'schematic', en: 'schematics', ar: 'مخططات تخطيطية', words: /\b(schematics?|riser diagrams?|single line diagrams?)\b/gi },
];

export type Glance = { sheets: number; scanned: boolean; trades: string[]; kinds: string[] };

const hits = (re: RegExp, text: string) => (text.match(new RegExp(re.source, re.flags)) || []).length;

/** The glance of a set from each sheet's own text (pdf.js getTextContent). `sheets` is the page count the browser read. */
export function glanceOf(pageTexts: string[], sheets: number): Glance | null {
  const n = Math.max(0, Math.floor(Number(sheets) || 0));
  if (!n) return null;
  const all = pageTexts.map((p) => String(p || '')).join('\n');
  // Fewer than 20 characters a sheet: a scan or a picture with no text layer. The server reads those by OCR later.
  const scanned = all.replace(/\s+/g, '').length < 20 * n;
  const trades = TRADES.map((tr) => ({ key: tr.key, n: hits(tr.words, all) }))
    .filter((x) => x.n >= TRADE_MIN_HITS)
    .sort((a, b) => b.n - a.n)
    .slice(0, TRADES_SHOWN)
    .map((x) => x.key);
  const kinds = KINDS.filter((k) => hits(k.words, all) > 0).map((k) => k.key);
  return { sheets: n, scanned, trades, kinds };
}

const labelOf = (list: Term[], key: string, lang: Lang) => { const t = list.find((x) => x.key === key); return t ? t[lang] : ''; };
const joinList = (xs: string[], lang: Lang) => (xs.length < 2 ? xs.join('') : xs.slice(0, -1).join(lang === 'ar' ? '، ' : ', ') + (lang === 'ar' ? ' و' : ' and ') + xs[xs.length - 1]);

/** The one sentence the customer reads at once. Only the count (`sheets`, the counted noun) and the fixed labels above go into it. */
export function glanceText(g: Glance, lang: Lang, sheets: string): string {
  const trades = joinList(g.trades.map((k) => labelOf(TRADES, k, lang)), lang);
  const kinds = joinList(g.kinds.map((k) => labelOf(KINDS, k, lang)), lang);
  if (lang === 'ar') {
    const what = g.scanned ? `${sheets}، ممسوحة ضوئيًا دون طبقة نص` : `${sheets}${trades ? ` من أعمال ${trades}` : ''}${kinds ? `، فيها ${kinds}` : ''}`;
    return `استلمتُ مخططكم: ${what}. أقرأ الكميات الآن وأفحص كل لوحة قبل أن يراها أي مورّد، ويستغرق ذلك عادةً نحو دقيقتين.`;
  }
  const what = g.scanned ? `${sheets}, scanned with no text layer` : `${sheets}${trades ? ` of ${trades}` : ''}${kinds ? ` (${kinds})` : ''}`;
  return `I have your drawing: ${what}. I am reading the quantities now and checking every sheet before any supplier sees it; this usually takes about two minutes.`;
}

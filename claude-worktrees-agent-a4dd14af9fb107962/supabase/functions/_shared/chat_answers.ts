// chat_answers — the deterministic part of "answer the question that was asked", shared by the
// public widget (site_assistant, seat customer_support) and the portal chat (sales_engineer).
//
// MEASURED 21 Sep 2026 (docs/audits/CHAT_ANSWERS_21_SEP_2026.md): the widget answered 0/3 public
// questions — a supplier-quoting FAQ for "how many quotes will I get", an honest refusal for
// "what does it cost" while FAQ 30 holds the fee, a price guide for an Arabic timeline question —
// and the portal chat answered a question about the customer's OWN quote's exclusion line with
// five unrelated FAQs. There is no model (OpenRouter is held), so both surfaces answer by lexemes:
//
//   1. routeQuestion   — count / cost / timeline by the words the asker used, EN and AR;
//   2. pickFaq         — the approved FAQ whose QUESTION is that question, in the asker's language;
//   3. quoteAnswer     — a question about a specific quote is answered from that quote's own
//                        fields (exclusions, scope, warranty, …), never from a corpus;
//   4. onTopic         — a retrieved passage must share a substantive word with the question, the
//                        estate's own lens ("a nearest neighbour is always found").
//
// Everything here is pure and covered by chat_answers.test.ts.

export type Lang = 'en' | 'ar';
export type QuestionType = 'count' | 'cost' | 'timeline' | null;

export const isArabic = (s: string): boolean => /[؀-ۿ]/.test(String(s || ''));
export const langOf = (message: string, uiLang?: string): Lang =>
  isArabic(message) || String(uiLang || '').toLowerCase().startsWith('ar') ? 'ar' : 'en';

// Arabic tokens keep their prefixes (ال / و / ب / ل); strip the common ones so "السقالات" and
// "سقالات" are the same word. English tokens are lower-cased; a light stem trims plurals/-ing so
// "ceilings" reaches "ceiling" and "scaffolding" reaches "scaffold".
const STOP_EN = new Set(['what', 'how', 'does', 'much', 'with', 'that', 'this', 'have', 'need', 'your', 'you', 'the', 'and', 'for', 'from', 'about', 'when', 'where', 'which', 'are', 'can', 'will', 'would', 'should', 'only', 'but', 'they', 'them', 'their', 'there', 'then', 'than', 'into', 'been', 'being', 'also', 'just', 'like', 'some', 'many', 'more', 'most', 'very', 'still', 'even', 'here', 'get', 'got', 'did', 'was', 'were', 'has', 'had', 'not', 'any', 'all', 'our', 'out', 'who', 'why', 'its', 'own', 'may', 'yes']);
const STOP_AR = new Set(['هل', 'ما', 'ماذا', 'كيف', 'كم', 'متى', 'أين', 'لماذا', 'هذا', 'هذه', 'ذلك', 'تلك', 'على', 'في', 'من', 'إلى', 'عن', 'مع', 'أو', 'ثم', 'لكن', 'فقط', 'عند', 'عندي', 'لدي', 'أنا', 'أنت', 'هو', 'هي', 'هم', 'كان', 'يكون', 'التي', 'الذي', 'الذين', 'بعد', 'قبل', 'حتى', 'إذا', 'لو', 'قد', 'لقد', 'غير', 'كل', 'أي', 'يتم', 'هناك']);
const stemEn = (w: string) => w.replace(/(ings?|ies|es|s)$/, (m) => (m === 'ies' ? 'y' : '')).replace(/(ing)$/, '');
const normAr = (w: string) => w.replace(/^(وال|بال|كال|فال|لل|ال|و|ب|ل|ف)/, '').replace(/[ًٌٍَُِّْ]/g, '').replace(/[إأآ]/g, 'ا').replace(/ة$/, 'ه').replace(/ى$/, 'ي');

/** Substantive words of a text: EN ≥ 4 letters after a light stem, AR ≥ 3 letters after prefix stripping. */
export function words(s: string): Set<string> {
  const out = new Set<string>();
  for (const raw of String(s || '').toLowerCase().match(/[a-z0-9؀-ۿ]+/g) || []) {
    if (/[؀-ۿ]/.test(raw)) {
      if (STOP_AR.has(raw)) continue;
      const w = normAr(raw);
      if (w.length >= 3 && !STOP_AR.has(w)) out.add(w);
    } else {
      if (STOP_EN.has(raw) || raw.length < 4) continue;
      out.add(stemEn(raw));
    }
  }
  return out;
}

// ponytail: a 14-word AR→EN bridge for the words a quote's English fields actually carry, so an
// Arabic question about "السقالات" reaches "scaffolding". Grow it from real questions in
// assistant_logs; a translation table is the upgrade path, not a model.
const AR_EN: Record<string, string> = {
  'سقالات': 'scaffold', 'سقاله': 'scaffold', 'كهرباء': 'electrical', 'كهربائيه': 'electrical', 'كهربائي': 'electrical',
  'دهان': 'painting', 'طلاء': 'painting', 'ضمان': 'warranty', 'تسليم': 'delivery', 'توريد': 'supply',
  'تركيب': 'installation', 'مواد': 'material', 'جبس': 'gypsum', 'اسقف': 'ceiling', 'سقف': 'ceiling',
  'جدران': 'wall', 'جدار': 'wall', 'دفع': 'payment', 'صلاحيه': 'validity', 'استثناء': 'exclusion',
  'استثناءات': 'exclusion', 'يستثني': 'exclusion', 'نطاق': 'scope', 'مده': 'lead',
};
export function bridged(s: string): Set<string> {
  const ws = words(s);
  for (const w of [...ws]) if (AR_EN[w]) ws.add(AR_EN[w]);
  return ws;
}

/** Shared substantive words between a question and a candidate passage. */
export function shared(question: string, passage: string): number {
  const a = bridged(question), b = words(passage);
  let n = 0; for (const w of a) if (b.has(w)) n++;
  return n;
}
export const onTopic = (question: string, passage: string): boolean => shared(question, passage) > 0;

// ── 1. QUESTION TYPE ─────────────────────────────────────────────────────────────────────────
// The three question types the audit measured wrong, decided by the asker's own words. Cost wins
// over count when both appear ("how much for 3 quotes" is a cost question); a per-trade price
// question ("what does gypsum cost per sqm") is NOT routed here — it names a trade, and the price
// guide owns it.
const COUNT_RE = /\b(how many)\b|كم عدد|عدد (العروض|عروض|الموردين|موردين)/i;
const COST_RE = /\b(what does it cost|how much (does|is|do)( it| this| the service| quotesdone| you)?( cost| charge)?|is (it|this|the service|the platform|quotesdone) free|any (fee|charge)s?|fees?|charges?|commission|pricing)\b|كم (تكلفة|تكلف|سعر) (الخدمة|المنصة|الاستخدام|استخدام)|هل (هي|هو|الخدمة|المنصة)? ?مجان|رسوم|عمولة|تكلفة الخدمة|تكلفة المنصة/i;
const TIMELINE_RE = /\b(how long|how soon|how fast|how quickly|when (do|will|can) i (get|receive|see)|turnaround|time ?frame|timeline|within how)\b|كم يستغرق|كم من الوقت|متى (أحصل|سأحصل|تصل|ستصل|يصل|أستلم|سأستلم)|خلال كم/i;
const TRADE_PRICE_RE = /\b(per (sqm|sq ?m|square|sqft|metre|meter|unit|piece|kg|ton|tonne)|cost of (a|an|the)? ?[a-z]+ (ceiling|wall|floor|door|window|paint|tile|install)|price (of|for) (a|an|the)? ?[a-z]+)\b|للمتر|المتر المربع|سعر (السقف|الجبس|الدهان|البلاط|الأرضيات|التركيب)/i;

// ABOUT US OR NOT ROUTED (review of PR #783, 21 Sep 2026). "fee" / "how long" alone matched
// "what is the parking fee at Dubai Mall" to the platform-fee FAQ and "how long is a football match"
// to the timeline FAQ — the unrelated-FAQ defect again. A routed question must either name
// QuotesDone's own subject (quote, supplier, request, reveal, platform, service, … EN + AR) or carry
// no substantive word beyond the question-type vocabulary itself ("what does it cost?" asked on our
// widget is about us). Anything else falls through to the corpus and its own on-topic gates.
const ANCHOR_RE = /quot(e|es|ation|ations|ing)\b|quotesdone|supplier|vendor|contractor|\brfqs?\b|request|inquir|enquir|reveal|platform|service|marketplace|your (site|app|website|company)|you charge|عرض|عروض|مورد|طلب|كشف|منص|خدم|كوتس/i;
const TYPE_VOCAB = new Set([
  ...words('cost costs costing fee fees charge charges charged commission pricing price prices free paid pay payment much long soon fast quickly quick turnaround time timeframe frame timeline take takes taking receive until expect usually typically many number count'),
  ...words('تكلفة تكلف التكلفة سعر السعر رسوم الرسوم عمولة مجانية مجاني مجانا يستغرق تستغرق وقت الوقت أحصل سأحصل الحصول تصل ستصل يصل أستلم سأستلم استلام عدد خلال'),
]);
export function aboutUs(message: string): boolean {
  if (ANCHOR_RE.test(message)) return true;
  for (const w of words(message)) if (!TYPE_VOCAB.has(w)) return false;
  return true;
}

export function routeQuestion(message: string): QuestionType {
  const m = String(message || '');
  if (TRADE_PRICE_RE.test(m)) return null;
  if (!aboutUs(m)) return null;
  if (COST_RE.test(m)) return 'cost';
  if (COUNT_RE.test(m)) return 'count';
  if (TIMELINE_RE.test(m)) return 'timeline';
  return null;
}

// ── 2. THE FAQ FOR A TYPE ────────────────────────────────────────────────────────────────────
// Chosen by the FAQ's QUESTION, never by its answer or tags — an answer mentioning "quotes" is what
// put the refund policy under "how many quotes will I get". Measured rows on 21 Sep 2026:
// count 13 / 604, cost 30 / 609, timeline 26 / (new AR row). A supplier-side twin (43 "How many
// suppliers receive the same RFQ?", 500 subscription fee, 39/619 verification time) is skipped for
// a customer or unknown asker and preferred for a supplier.
export interface FaqRow { id: number | string; question: string; answer: string; language?: string | null; section?: string | null; audience?: string | null }
const FAQ_Q: Record<Exclude<QuestionType, null>, { en: RegExp; ar: RegExp; supplierEn?: RegExp; supplierAr?: RegExp }> = {
  count: { en: /^how many suppliers receive my rfq/i, ar: /^كم عدد الموردين الذين يستلمون طلبي/, supplierEn: /^how many suppliers receive the same rfq/i },
  cost: { en: /^what are the platform fees/i, ar: /^ما هي رسوم المنصة/, supplierEn: /^is there a subscription fee for suppliers/i },
  timeline: { en: /^how long does the process take/i, ar: /^كم يستغرق الحصول على عروض الأسعار/, supplierEn: /^how long does verification take/i, supplierAr: /^كم يستغرق التحقق من المورد/ },
};
export function pickFaq(type: QuestionType, lang: Lang, faqs: FaqRow[], audience: 'customer' | 'supplier' | 'unknown' = 'unknown'): FaqRow | null {
  if (!type) return null;
  const p = FAQ_Q[type];
  const want = audience === 'supplier'
    ? (lang === 'ar' ? [p.supplierAr, p.ar] : [p.supplierEn, p.en])
    : (lang === 'ar' ? [p.ar] : [p.en]);
  for (const re of want) {
    if (!re) continue;
    const hit = faqs.find((f) => re.test(String(f.question || '').trim()) && (lang === 'ar' ? isArabic(f.question) : !isArabic(f.question)));
    if (hit) return hit;
  }
  return null;
}

// ── 3. A QUESTION ABOUT A SPECIFIC QUOTE ─────────────────────────────────────────────────────
// The customer's own quotes, as the seat holds them. Every field is optional because quotes are
// entered by suppliers who leave most of them blank; an absent field is answered as absent.
export interface QuoteForAnswer {
  id: string;
  inquiry_summary?: string | null;
  inquiry_category?: string | null;
  rfq_no?: string | number | null;
  supplier_label: string;            // the company name after a reveal, "Supplier A" before it
  amount?: number | null;
  status?: string | null;
  exclusions?: string | null; scope?: string | null; conditions?: string | null; warranty?: string | null;
  lead_time?: string | null; payment_terms?: string | null; validity?: string | null; notes?: string | null;
  items?: string | null;             // committed line items, flattened to text by the caller
}
type Field = 'exclusions' | 'scope' | 'conditions' | 'warranty' | 'lead_time' | 'payment_terms' | 'validity' | 'notes' | 'items';
const FIELDS: Field[] = ['exclusions', 'scope', 'conditions', 'warranty', 'lead_time', 'payment_terms', 'validity', 'notes', 'items'];
// A field the question names outright, even when the quote's text does not share a word with it.
const FIELD_RE: Array<[Field, RegExp]> = [
  ['exclusions', /\b(exclu|not included|excluded|leave out|left out)|استثن|غير مشمول|لا يشمل/i],
  ['warranty', /\bwarrant|guarantee|ضمان|كفالة/i],
  ['payment_terms', /\bpayment|deposit|advance|instalment|installment|دفع|دفعة|عربون/i],
  ['lead_time', /\blead ?time|how long (will|does) (the|this) (work|job)|deliver|complete|duration|مدة|تسليم|ينتهي|إنجاز/i],
  ['validity', /\bvalid|expire|expiry|صلاحية|ينتهي العرض/i],
  ['scope', /\bscope|include[sd]?\b|covered|what (is|does) (the )?quote (cover|include)|نطاق|يشمل|مشمول/i],
  ['conditions', /\bcondition|terms\b|شروط/i],
];
const FIELD_LABEL: Record<Field, { en: string; ar: string }> = {
  exclusions: { en: 'exclusions', ar: 'الاستثناءات' }, scope: { en: 'scope', ar: 'نطاق العمل' },
  conditions: { en: 'conditions', ar: 'الشروط' }, warranty: { en: 'warranty', ar: 'الضمان' },
  lead_time: { en: 'lead time', ar: 'مدة التنفيذ' }, payment_terms: { en: 'payment terms', ar: 'شروط الدفع' },
  validity: { en: 'validity', ar: 'صلاحية العرض' }, notes: { en: 'notes', ar: 'الملاحظات' }, items: { en: 'line items', ar: 'بنود العرض' },
};
const QUOTE_RE = /\bquot(e|ation)s?\b|\boffer\b|\bbid\b|عرض|العرض|عروض|التسعير|السعر/i;

// "above 4 m" / "over 4m" / "فوق 4 متر" in a line, "3.2 m" / "3.2 متر" in the question.
const METRES_RE = /(\d+(?:\.\d+)?)\s*(?:m\b|metres?\b|meters?\b|متر|م\b)/gi;
const ABOVE_RE = /\b(above|over|exceeding|more than|beyond|higher than)\b|فوق|أعلى من|أكثر من|تتجاوز|يتجاوز/i;
const BELOW_RE = /\b(below|under|less than|up to|lower than)\b|تحت|أقل من|حتى/i;
function metres(s: string): number[] {
  const out: number[] = []; let m: RegExpExecArray | null; METRES_RE.lastIndex = 0;
  while ((m = METRES_RE.exec(s))) out.push(Number(m[1]));
  return out;
}

const fmtAmount = (n: number | null | undefined, lang: Lang) =>
  n == null || !isFinite(Number(n)) ? '' : (lang === 'ar' ? `${Number(n).toLocaleString('en-US')} درهم` : `AED ${Number(n).toLocaleString('en-US')}`);

export interface QuoteAnswer { reply: string; quote_id: string; field: Field | null; basis: 'quote_field' | 'quote_field_absent' }

/**
 * Answer a question about one of the customer's quotes from that quote's own text. Returns null
 * when the question is not about a quote (no quote word, no field word, no shared word with any
 * quote) so the caller can fall through to the knowledge corpora.
 */
export function quoteAnswer(message: string, quotes: QuoteForAnswer[], lang: Lang): QuoteAnswer | null {
  if (!quotes.length) return null;
  const named = FIELD_RE.find(([, re]) => re.test(message))?.[0] ?? null;
  const mentionsQuote = QUOTE_RE.test(message);

  // Score every (quote, field) by shared words; the inquiry text also pulls a quote in.
  let best: { q: QuoteForAnswer; field: Field; n: number } | null = null;
  let bestQuote: { q: QuoteForAnswer; n: number } | null = null;
  for (const q of quotes) {
    const qn = shared(message, [q.inquiry_summary, q.inquiry_category, q.supplier_label].filter(Boolean).join(' '));
    if (!bestQuote || qn > bestQuote.n) bestQuote = { q, n: qn };
    for (const f of FIELDS) {
      const text = q[f]; if (!text) continue;
      const n = shared(message, String(text)) + (f === named ? 1 : 0);
      if (n > 0 && (!best || n > best.n)) best = { q, field: f, n };
    }
  }
  if (!best && !(named && (mentionsQuote || bestQuote?.n))) return null;

  const q = best?.q ?? bestQuote!.q;
  const field: Field | null = best?.field ?? named;
  const head = lang === 'ar'
    ? `في عرض السعر${q.rfq_no ? ' للطلب ' + q.rfq_no : ''}${q.inquiry_summary ? ' («' + String(q.inquiry_summary).slice(0, 80) + '»)' : ''} من ${q.supplier_label}${q.amount != null ? '، بقيمة ' + fmtAmount(q.amount, 'ar') : ''}`
    : `On your quote${q.rfq_no ? ' for request ' + q.rfq_no : ''}${q.inquiry_summary ? ' ("' + String(q.inquiry_summary).slice(0, 80) + '")' : ''} from ${q.supplier_label}${q.amount != null ? ', ' + fmtAmount(q.amount, 'en') : ''}`;

  if (!field || !q[field]) {
    const label = field ? FIELD_LABEL[field][lang] : (lang === 'ar' ? 'هذا البند' : 'that point');
    return {
      quote_id: q.id, field, basis: 'quote_field_absent',
      reply: lang === 'ar'
        ? `${head}، لم يذكر المورّد ${label}. ولا أستطيع أن أؤكد أمرًا لم يرد في العرض — يمكنك طلب توضيح من المورّد عبر «الرسائل» (تُتاح بعد الكشف) أو بإرسال سؤال استيضاحي على الطلب، وسيُحفظ ردّه مع العرض.`
        : `${head}, the supplier did not state ${label}. I cannot confirm anything the quote does not say — ask the supplier through Messages (open after a reveal) or a clarification on the request, and their answer is kept with the quote.`,
    };
  }

  const line = String(q[field]).trim();
  const label = FIELD_LABEL[field][lang];
  let compare = '';
  // A numeric threshold the question can be tested against, only when both sides carry exactly
  // one metre figure and the line states a direction. Anything else is left to the words.
  // The asker often restates the threshold ("above 4 m, but mine are 3.2 m"): the line's own figure
  // is removed from the question's figures before asking for exactly one.
  const lm = metres(line), qm = metres(message).filter((v) => !lm.includes(v));
  if (lm.length === 1 && qm.length === 1 && (ABOVE_RE.test(line) || BELOW_RE.test(line))) {
    const above = ABOVE_RE.test(line);
    const triggered = above ? qm[0] > lm[0] : qm[0] < lm[0];
    compare = lang === 'ar'
      ? (triggered
        ? ` القياس الذي ذكرته (${qm[0]} متر) ${above ? 'يتجاوز' : 'أقل من'} الحدّ الوارد في هذا البند (${lm[0]} متر)، لذا ينطبق هذا الاستثناء على حالتك وفق نصّه.`
        : ` القياس الذي ذكرته (${qm[0]} متر) ${above ? 'أقل من' : 'يتجاوز'} الحدّ الوارد في هذا البند (${lm[0]} متر)، لذا لا ينطبق هذا الاستثناء على حالتك وفق نصّه.`)
      : (triggered
        ? ` Your figure (${qm[0]} m) is ${above ? 'above' : 'below'} the ${lm[0]} m threshold in that line, so as written this does apply to your case.`
        : ` Your figure (${qm[0]} m) is ${above ? 'below' : 'above'} the ${lm[0]} m threshold in that line, so as written this does not apply to your case.`);
  }
  const tail = lang === 'ar'
    ? ' هذا نصّ ما ورد في العرض حرفيًا؛ وما لم يرد فيه لا أستطيع تأكيده — يمكنك طلب توضيح من المورّد عبر «الرسائل» بعد الكشف، أو بإرسال سؤال استيضاحي على الطلب.'
    : ' That is the quote\'s own wording; anything it does not say I cannot confirm — ask the supplier through Messages after a reveal, or a clarification on the request.';
  return {
    quote_id: q.id, field, basis: 'quote_field',
    reply: lang === 'ar'
      ? `${head}، ${label} كما وردت: «${line}».${compare}${tail}`
      : `${head}, the ${label} line reads: "${line}".${compare}${tail}`,
  };
}

// ── 4. THE HONEST FALLBACK, IN THE ASKER'S LANGUAGE ──────────────────────────────────────────
export function notYet(lang: Lang, taskId: number | string | null | undefined, seat: 'sales_engineer' | 'customer_support'): string {
  const who = seat === 'sales_engineer' ? { en: 'the sales engineer', ar: 'مهندس المبيعات' } : { en: 'customer support', ar: 'خدمة العملاء' };
  const t = taskId != null && taskId !== '' ? (lang === 'ar' ? ` (المهمة رقم ${taskId})` : ` (task #${taskId})`) : '';
  return lang === 'ar'
    ? `لا تتوفر لديّ هذه المعلومة حاليًا، ولا أودّ أن أجيبك بالتخمين. سجّلتُ سؤالك كما كتبته وأحلته إلى ${who.ar}${t}، وسيصلك الرد.`
    : `I don't have that yet, and I won't guess. I've logged your question as you wrote it for ${who.en}${t}, and the answer will come back to you.`;
}

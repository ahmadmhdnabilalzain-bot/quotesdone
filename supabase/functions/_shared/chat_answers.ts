// chat_answers — the deterministic part of "answer the question that was asked", shared by the
// public widget (site_assistant, seat customer_support) and the portal chat (sales_engineer).
//
// MEASURED 21 Sep 2026 (docs/audits/CHAT_ANSWERS_21_SEP_2026.md): the widget answered 0/3 public
// questions — a supplier-quoting FAQ for "how many quotes will I get", an honest refusal for
// "what does it cost" while FAQ 30 holds the fee, a price guide for an Arabic timeline question —
// and the portal chat answered a question about the customer's OWN quote's exclusion line with
// five unrelated FAQs. Since 23 Sep 2026 every MEANING here is reasoned by the caller (reasoned_channels.ts,
// founder_instruction 886-903); what stays is the answer each reasoned meaning gets:
//
//   1. the question type — count / cost / timeline, REASONED by the caller (reasoned_channels.ts);
//   2. pickFaq         — the approved FAQ whose QUESTION is that question, in the asker's language;
//   3. quoteAnswer     — the reasoned quote field is answered from that quote's own text, never a corpus;
//   (the shared-word gate onTopic that picked passages is gone: the passage is reasoned too).
//
// Everything here is pure and covered by chat_answers.test.ts.

export type Lang = 'en' | 'ar';
export type QuestionType = 'count' | 'cost' | 'timeline' | null;

export const isArabic = (s: string): boolean => /[؀-ۿ]/.test(String(s || ''));
/** Arabic and Latin letters in a message; links, emails, the brand and the ZZ DEMO fixture tag are not counted. */
export function scripts(s: string): { ar: number; la: number } {
  const t = String(s || '').replace(/https?:\/\/\S+|\S+@\S+|\bQuotesDone\b|\bZZ ?DEMO\b/gi, '');
  return { ar: (t.match(/[\u0600-\u06FF]/g) || []).length, la: (t.match(/[A-Za-z]/g) || []).length };
}
// A MIXED MESSAGE KEEPS THE CONVERSATION'S LANGUAGE (customer_support, 3 Nov 2026). Measured on the live widget: an English
// inquiry's message "sorry, الزجاج 8 مم مو 6mm. And the villa is in Sharjah ..." was answered wholly in Arabic, because any
// Arabic letter made the message Arabic. `established` is the language the conversation began in (turnLang): a message that
// mixes both scripts keeps it; a message in one script, a first message, and the Arabic screen keep their old rules.
// prevented by: _shared/chat_lang_follows_the_conversation.test.ts
export const langOf = (message: string, uiLang?: string, established?: Lang): Lang => {
  if (String(uiLang || '').toLowerCase().startsWith('ar')) return 'ar';
  const { ar, la } = scripts(message);
  if (ar && la && established) return established;
  return ar ? 'ar' : 'en';
};
/** The reply language of a chat turn: this message, read against the language of the conversation's first message. */
export function turnLang(message: string, uiLang: string | undefined, history: { role: string; content: string }[]): Lang {
  const first = history.find((h) => h.role === 'user' && (scripts(h.content).ar + scripts(h.content).la) > 0);
  return langOf(message, uiLang, first ? langOf(first.content) : undefined);
}

// ── 1. QUESTION TYPE ─────────────────────────────────────────────────────────────────────────
// REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903). COUNT_RE / COST_RE / TIMELINE_RE /
// TRADE_PRICE_RE and the ANCHOR_RE "about us" gate decided which of these three a message was; every one
// of them was a word list ("fee" alone once sent "the parking fee at Dubai Mall" to the platform-fee FAQ).
// The type is now the caller's reasoned choice (_shared/reasoned_channels.ts: siteQuestion for the widget,
// socialMeaning's faq:<type> for social), and pickFaq below answers it.
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
//
// WHICH quote and WHICH field the question asks about — and whether a threshold line applies to the
// asker's case — is REASONED (23 Sep 2026, founder_instruction 886-903; reasoned_channels.ts quoteQuestion,
// decision point shared.quote_answer). FIELD_RE / QUOTE_RE / ABOVE_RE / BELOW_RE and a shared-word score
// decided it until then. What stays here is format: the metre figures on each side (digits and a unit) and
// the arithmetic between them.
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
export type Field = 'exclusions' | 'scope' | 'conditions' | 'warranty' | 'lead_time' | 'payment_terms' | 'validity' | 'notes' | 'items';
export const FIELDS: Field[] = ['exclusions', 'scope', 'conditions', 'warranty', 'lead_time', 'payment_terms', 'validity', 'notes', 'items'];
export const FIELD_LABEL: Record<Field, { en: string; ar: string }> = {
  exclusions: { en: 'exclusions', ar: 'الاستثناءات' }, scope: { en: 'scope', ar: 'نطاق العمل' },
  conditions: { en: 'conditions', ar: 'الشروط' }, warranty: { en: 'warranty', ar: 'الضمان' },
  lead_time: { en: 'lead time', ar: 'مدة التنفيذ' }, payment_terms: { en: 'payment terms', ar: 'شروط الدفع' },
  validity: { en: 'validity', ar: 'صلاحية العرض' }, notes: { en: 'notes', ar: 'الملاحظات' }, items: { en: 'line items', ar: 'بنود العرض' },
};

// FORMAT: "4m" / "3.2 m" / "3.2 متر" — a number and a unit.
const METRES_RE = /(\d+(?:\.\d+)?)\s*(?:m\b|metres?\b|meters?\b|متر|م\b)/gi;
export function metres(s: string): number[] {
  const out: number[] = []; let m: RegExpExecArray | null; METRES_RE.lastIndex = 0;
  while ((m = METRES_RE.exec(s))) out.push(Number(m[1]));
  return out;
}
/** The one figure on each side that can be compared, or null: the asker's figure minus the line's own (they often restate it). */
export function figures(line: string, message: string): { line: number; asked: number } | null {
  const lm = metres(line), qm = metres(message).filter((v) => !lm.includes(v));
  return lm.length === 1 && qm.length === 1 ? { line: lm[0], asked: qm[0] } : null;
}

const fmtAmount = (n: number | null | undefined, lang: Lang) =>
  n == null || !isFinite(Number(n)) ? '' : (lang === 'ar' ? `${Number(n).toLocaleString('en-US')} درهم` : `AED ${Number(n).toLocaleString('en-US')}`);

export interface QuoteAnswer { reply: string; quote_id: string; field: Field | null; basis: 'quote_field' | 'quote_field_absent' }

/**
 * Answer the REASONED question about one of the customer's quotes from that quote's own text.
 * `choice` is q:<index>:<field>[:applies|:does_not_apply] (reasoned_channels.ts quoteOptions), or 'none' / null:
 * then null, and the caller falls through to the knowledge corpora.
 */
export function quoteAnswer(choice: string | null, quotes: QuoteForAnswer[], lang: Lang, message = ''): QuoteAnswer | null {
  const m = /^q:(\d+):([a-z_]+)(?::(applies|does_not_apply))?$/.exec(String(choice ?? ''));   // our own id format
  const q = m ? quotes[Number(m[1])] : undefined;
  const field = m && (FIELDS as string[]).includes(m[2]) ? m[2] as Field : null;
  if (!q || !field) return null;
  const head = lang === 'ar'
    ? `في عرض السعر${q.rfq_no ? ' للطلب ' + q.rfq_no : ''}${q.inquiry_summary ? ' («' + String(q.inquiry_summary).slice(0, 80) + '»)' : ''} من ${q.supplier_label}${q.amount != null ? '، بقيمة ' + fmtAmount(q.amount, 'ar') : ''}`
    : `On your quote${q.rfq_no ? ' for request ' + q.rfq_no : ''}${q.inquiry_summary ? ' ("' + String(q.inquiry_summary).slice(0, 80) + '")' : ''} from ${q.supplier_label}${q.amount != null ? ', ' + fmtAmount(q.amount, 'en') : ''}`;
  const label = FIELD_LABEL[field][lang];

  if (!q[field]) {
    return {
      quote_id: q.id, field, basis: 'quote_field_absent',
      reply: lang === 'ar'
        ? `${head}، لم يذكر المورّد ${label}. ولا أستطيع أن أؤكد أمرًا لم يرد في العرض — يمكنك طلب توضيح من المورّد عبر «الرسائل» (تُتاح بعد الكشف) أو بإرسال سؤال استيضاحي على الطلب، وسيُحفظ ردّه مع العرض.`
        : `${head}, the supplier did not state ${label}. I cannot confirm anything the quote does not say — ask the supplier through Messages (open after a reveal) or a clarification on the request, and their answer is kept with the quote.`,
    };
  }

  const line = String(q[field]).trim();
  let compare = '';
  // Whether the line applies was REASONED (m[3]); the relation between the two figures is arithmetic.
  const f = figures(line, message);
  if (f && m![3]) {
    const applies = m![3] === 'applies';
    const rel = f.asked > f.line ? { en: 'above', ar: 'يتجاوز' } : f.asked < f.line ? { en: 'below', ar: 'أقل من' } : { en: 'exactly at', ar: 'يساوي' };
    compare = lang === 'ar'
      ? ` القياس الذي ذكرته (${f.asked} متر) ${rel.ar} الحدّ الوارد في هذا البند (${f.line} متر)، لذا ${applies ? 'ينطبق' : 'لا ينطبق'} هذا البند على حالتك وفق نصّه.`
      : ` Your figure (${f.asked} m) is ${rel.en} the ${f.line} m threshold in that line, so as written this ${applies ? 'does apply' : 'does not apply'} to your case.`;
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

// 4. (removed 12 Oct 2026, rulings 1195/1196) notYet, the fixed "I don't have that yet" sentence: a model writes every reply.

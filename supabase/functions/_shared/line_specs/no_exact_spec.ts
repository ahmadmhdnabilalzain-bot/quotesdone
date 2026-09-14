// line_specs/no_exact_spec.ts — when no supplier quoted the customer's exact spec.
//
// FOUNDER, 14 Sep 2026 (founder_instruction #321): if no supplier could quote what the customer asked
// for, customer_support tells the customer, lists the similar options suppliers DID quote, and asks
// whether to proceed with one. Yes: proceed, and the chosen spec is no longer a deviation. No: a
// professional apology. The loop's state lives in public.spec_alternative_offer
// (scripts/sql/no_supplier_quoted_the_exact_spec_so_the_customer_is_offered_what_was.sql).
//
// Everything here is pure: detection over quote_compare's technical comparison, the alternatives list,
// the EN/AR messages and the reply reading. sales_engineer detects and decides; customer_support sends.
//
// NO SUPPLIER IDENTITY. An alternative is { option_id, value, suppliers } — a value and a COUNT of
// suppliers. Nothing about which supplier, which quote or which label ever enters the list, and the
// database refuses any other key (spec_alternative_offer_alternatives_shape).
import { sameValue, type TechnicalComparison } from './compare.ts';
import { arTrade } from '../trade_glossary_ar.ts';

export type Alternative = { option_id: string; value: string; suppliers: number };
export type SpecOffer = {
  line_no: number; item: string; attr: string; label_en: string; label_ar: string;
  requested: string; alternatives: Alternative[];
};

/**
 * The lines where no eligible quote matches what the customer asked for, on a MANDATORY attribute with
 * a requested value of the customer's own, but at least one eligible quote offers something else.
 * If ANY eligible quote matches, nothing is returned for that attribute: then a differing quote is only
 * shown in the comparison as "This is what the supplier quoted in writing".
 * `t` is quote_compare's technical_detail, which only ever holds eligible (rankable) quotes.
 */
export function noExactSpec(t: TechnicalComparison | null | undefined): SpecOffer[] {
  if (!t || !Array.isArray(t.lines)) return [];
  const letterOf = new Map(t.quotes.map((q) => [q.quote_id, q.supplier_letter]));
  const out: SpecOffer[] = [];
  for (const row of t.lines) {
    for (const a of row.attributes) {
      if (!a.mandatory || !a.requested) continue;
      if (a.requested_source !== 'boq' && a.requested_source !== 'intake') continue;
      if (a.cells.some((c) => c.flag === 'match')) continue;
      const differing = a.cells.filter((c) => c.flag === 'differs' && c.value);
      if (!differing.length) continue;
      // Group equal values (the comparison's own sameValue) and count DISTINCT suppliers, never quotes:
      // two options from one supplier are one supplier offering that value.
      const groups: Array<{ value: string; letters: Set<string> }> = [];
      for (const c of differing) {
        const v = String(c.value).trim();
        const g = groups.find((x) => sameValue(x.value, v));
        const letter = letterOf.get(c.quote_id) ?? c.quote_id;
        if (g) g.letters.add(letter); else groups.push({ value: v, letters: new Set([letter]) });
      }
      groups.sort((x, y) => y.letters.size - x.letters.size || x.value.localeCompare(y.value));
      out.push({
        line_no: row.request_line?.line_no ?? row.row, item: String(row.item || ''), attr: a.code,
        label_en: a.label_en, label_ar: a.label_ar, requested: a.requested,
        alternatives: groups.map((g, i) => ({ option_id: 'o' + (i + 1), value: g.value, suppliers: g.letters.size })),
      });
    }
  }
  return out;
}

// ── THE MESSAGES ─────────────────────────────────────────────────────────────────────────────────
export type Lang = 'en' | 'ar';
export type OfferForText = Pick<SpecOffer, 'item' | 'label_en' | 'label_ar' | 'requested' | 'alternatives'> & { accepted_value?: string | null };
export type Message = { subject: string; body: string };

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';
const arNum = (n: number | string) => String(n).replace(/\d/g, (d) => AR_DIGITS[Number(d)]);
/**
 * Supplier or customer words on an Arabic message: the glossary's Arabic; what it cannot finish is
 * kept only after the label "كما وردت" (as written), the same convention the comparison report uses
 * for the supplier's original wording. No other English reaches an Arabic message.
 */
function arWords(v: string): string {
  const s = String(v || '').trim();
  if (!s) return '—';
  const t = arTrade(s);
  if (t.complete) return t.ar;
  return (t.ar ? t.ar + ' ' : '') + '(كما وردت: ' + s + ')';
}
const ref = (rfqNo: number | string | null | undefined, lang: Lang) => rfqNo == null ? '' : (lang === 'ar' ? ` رقم ${arNum(rfqNo)}` : ` #${rfqNo}`);
const suppliersEn = (n: number) => n === 1 ? '1 supplier' : `${n} suppliers`;
const suppliersAr = (n: number) => n === 1 ? 'مورّد واحد' : n === 2 ? 'مورّدان' : `${arNum(n)} مورّدين`;

function optionLines(o: OfferForText, lang: Lang): string {
  return o.alternatives.map((a, i) => lang === 'ar'
    ? `${arNum(i + 1)}) ${arWords(a.value)} — ${suppliersAr(a.suppliers)}`
    : `${i + 1}) ${a.value} — ${suppliersEn(a.suppliers)}`).join('\n');
}

/** The question. `reminder` 0 is the first message; 1..n are reminders; `final` marks the last one. */
export function offerMessage(o: OfferForText, lang: Lang, opts: { rfqNo?: number | string | null; portalUrl?: string | null; reminder?: number; final?: boolean; replyBy?: string | null } = {}): Message {
  const r = opts.reminder ?? 0;
  if (lang === 'ar') {
    const head = r === 0 ? '' : (opts.final ? 'تذكير أخير: ' : 'تذكير: ');
    return {
      subject: `${head}طلبك${ref(opts.rfqNo, 'ar')}: لم يقدّم أي مورّد المواصفة التي طلبتها تمامًا`,
      body: [
        `${head}لم يتمكّن أي مورّد من تقديم عرض بمواصفتك المطلوبة تمامًا في طلبك${ref(opts.rfqNo, 'ar')}.`,
        `البند: ${arWords(o.item)} — ${o.label_ar}`,
        `طلبت: ${arWords(o.requested)}`,
        'لكن المورّدين قدّموا خيارات مشابهة:',
        optionLines(o, 'ar'),
        'هل ترغب في المتابعة بأحد هذه الخيارات؟ أرسل رقم الخيار، أو أرسل «لا» إن كنت لا ترغب في المتابعة.',
        ...(opts.portalUrl ? [`يمكنك أيضًا الرد من بوابتك: ${opts.portalUrl}`] : []),
        ...(opts.final ? ['هذا آخر تذكير؛ إن لم يصلنا ردّك فسنغلق الطلب دون أي رسوم.'] : []),
      ].join('\n'),
    };
  }
  const head = r === 0 ? '' : (opts.final ? 'Final reminder: ' : 'Reminder: ');
  return {
    subject: `${head}Your request${ref(opts.rfqNo, 'en')}: no supplier could quote your exact specification`,
    body: [
      `${head}No supplier was able to quote your exact specification on your request${ref(opts.rfqNo, 'en')}.`,
      `Item: ${o.item} — ${o.label_en}`,
      `You asked for: ${o.requested}`,
      'Suppliers did quote similar options:',
      optionLines(o, 'en'),
      'Would you like to proceed with one of these options? Reply with the option number, or NO if you would rather not proceed.',
      ...(opts.portalUrl ? [`You can also answer in your portal: ${opts.portalUrl}`] : []),
      ...(opts.final ? ['This is the last reminder; if we do not hear from you, we will close the request with nothing charged.'] : []),
    ].join('\n'),
  };
}

/** The customer said yes to an option. */
export function acceptedMessage(o: OfferForText, lang: Lang, opts: { rfqNo?: number | string | null } = {}): Message {
  const v = String(o.accepted_value || '');
  return lang === 'ar'
    ? { subject: `طلبك${ref(opts.rfqNo, 'ar')}: سنتابع بالخيار الذي اخترته`,
        body: `شكرًا لك. سنتابع طلبك${ref(opts.rfqNo, 'ar')} بـ ${arWords(v)} في ${o.label_ar}، وتُقارن العروض التي تقدّمه الآن على أنها مطابقة لطلبك.` }
    : { subject: `Your request${ref(opts.rfqNo, 'en')}: we will proceed with your chosen option`,
        body: `Thank you. We will proceed with ${v} for ${o.label_en} on your request${ref(opts.rfqNo, 'en')}, and quotes offering it are now compared as matching your request.` };
}

/** The customer declined, or did not answer after the final reminder. Nothing was revealed, so nothing is charged. */
export function apologyMessage(o: OfferForText, lang: Lang, why: 'declined' | 'no_reply', opts: { rfqNo?: number | string | null } = {}): Message {
  if (lang === 'ar') {
    const lead = why === 'declined' ? 'نتفهّم قرارك.' : 'لم يصلنا ردّك على الخيارات التي أرسلناها.';
    return { subject: `طلبك${ref(opts.rfqNo, 'ar')}: نعتذر عن عدم توفّر مواصفتك المطلوبة`,
      body: `${lead} نعتذر لأنه لم يتمكّن أي مورّد من تقديم ${o.label_ar} كما طلبت تمامًا. أغلقنا طلبك${ref(opts.rfqNo, 'ar')} دون أي رسوم عليك، ويسعدنا استقبال طلب جديد منك في أي وقت.` };
  }
  const lead = why === 'declined' ? 'We understand.' : 'We did not hear back from you about the options we sent.';
  return { subject: `Your request${ref(opts.rfqNo, 'en')}: we are sorry your exact specification was not available`,
    body: `${lead} We are sorry that no supplier could quote ${o.label_en} exactly as you asked. We have closed your request${ref(opts.rfqNo, 'en')} and nothing has been charged. You are welcome to post a new request at any time.` };
}

import { figure } from '../money.ts';
import { feeBaseOf, feeBasisLine, NOT_RESPONSIBLE, priceStated, vatStated, type PriceRow } from '../stated_price.ts';
import { type InquiryRow, type Item, type QuoteRow, VAT_RE, clipCell, quoteRef } from './rows.ts';
import { DOC_VERSION, type Lang, PREPARED_BY, docName, maskDeep } from './base.ts';
import { type ArTexts, type Cell, hasSpecs, kit, specText } from './kit.ts';
import { arCategory, arEmirate, arUnit, enCategory } from './arabic.ts';

// ── The quotation ──────────────────────────────────────────────────────────────────────────────
/** The pdf_native body for ONE quote in ONE language. Pure: the caller fetches the rows. */
// requestUrl: the portal deep link back to this quote on its request (site_origins portalLink).
/** `partyName`: the supplier's company name once the customer has paid to reveal it; the letter still names the reference. */
export function quoteDocument(args: { quote: QuoteRow; inquiry: InquiryRow; items: Item[]; letter: string; lang: Lang; partyName?: string | null; maskNames?: string[]; requestUrl?: string; date?: string; date_ar?: string; arTexts?: ArTexts;
  /** pricing_config.standard_reveal_rate, read by the caller (reveal_rate.ts readRevealRate) — the source public.reveal_fee()
   * reads. Absent or not positive, the page prints no rate and no fee figure: a guessed rate is never printed. */
  revealRate?: number | null;
  /** The sales engineer's notes on this quote against the request (quote_review_notes.ts, ledger 1588); null = not reviewed. */
  reviewNotes?: { en: string; ar: string; severity?: string }[] | null }) {
  const { quote: q, inquiry: inq, letter, lang } = args;
  // A line that is itself VAT ("VAT 5%") is not scope; it never reaches the page.
  const items = (args.items || []).filter((it) => !VAT_RE.test(String(it.desc || '')));
  // Ruling 1208: the final price after the stated discount, excluding VAT — the fee base and the comparison basis.
  const exVat = feeBaseOf(q as PriceRow) ?? 0;
  const k = kit(lang, args.maskNames || [], args.arTexts); const { T, ar } = k;
  const ref = quoteRef(inq, letter);
  const date = (ar ? args.date_ar : args.date) || k.today();
  const party = args.partyName || k.label('Supplier ' + letter);
  const trade = ar ? (arCategory(inq.category) ?? k.loc(inq.category).text) : enCategory(inq.category);
  const emirate = ar ? (arEmirate(inq.emirate) ?? k.loc(inq.emirate).text) : String(inq.emirate || '');
  const lead = k.dur(q.lead_time), validity = k.dur(q.validity), warranty = k.dur(q.warranty);
  const summary = k.loc(inq.summary, 600);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });

  section('Request and quoting party', 'الطلب والجهة مقدّمة العرض');
  // `note`, not `sub`: in these blocks `sub` means one thing only — the supplier's original wording.
  blocks.push({ t: 'party', label: T('Quoting party', 'الجهة مقدّمة العرض'), chip: party, note: T('Anonymous until you reveal it. The supplier\'s name and contact details are released only after the reveal fee is paid.', 'هوية المورّد مخفية حتى الكشف، ولا تُعرض بيانات التواصل إلا بعد سداد رسوم الكشف.') });
  blocks.push({ t: 'kv', pairs: [[T('Trade', 'التخصص'), trade || '—'], [T('Emirate', 'الإمارة'), emirate || '—']] });
  if (summary.text) blocks.push({ t: 'p', text: summary.text, sub: summary.sub, label: T('Your request', 'طلبك') });

  section('Scope and technical specification', 'نطاق العمل والمواصفات الفنية');
  const priced = items.some((it) => Number(it.amount) > 0 || Number(it.unit_price) > 0);
  const specCol = items.some(hasSpecs);
  if (items.length) {
    const head: Cell[] = ['#', T('Description', 'الوصف')];
    const widths = [0.05]; const align = ['c', 's'];
    if (specCol) head.push(T('Specification', 'المواصفات'));
    head.push(T('Qty', 'الكمية'), T('Unit', 'الوحدة'));
    if (priced) head.push(T('Rate (AED)', 'سعر الوحدة (درهم)'), T('Amount (AED)', 'المبلغ (درهم)'));
    widths.push(specCol ? (priced ? 0.22 : 0.33) : (priced ? 0.49 : 0.69));
    if (specCol) { widths.push(priced ? 0.31 : 0.40); align.push('s'); }
    widths.push(0.07, 0.08); align.push('e', 'c');
    if (priced) { widths.push(0.12, 0.15); align.push('e', 'e'); }
    const total = widths.reduce((a, b) => a + b, 0); const W = widths.map((w) => w / total);
    const rows = items.map((it, i) => {
      const r: Cell[] = [String(i + 1), k.cell(it.desc, 200)];
      if (specCol) r.push(specText(k, it));
      r.push(String(it.qty ?? ''), (ar ? (arUnit(it.unit) ?? k.loc(it.unit).text) : String(it.unit || '')) || '—');
      // The currency sits in the column head, so each cell is the figure alone and stays on one line.
      if (priced) r.push(figure(it.unit_price, true), figure(it.amount, true));
      return r;
    });
    blocks.push({ t: 'table', head, rows, widths: W, align, zebra: true });
  } else {
    blocks.push({ t: 'callout', tone: 'gold', title: T('Lump-sum quote', 'عرض بسعر إجمالي'), text: T('The supplier priced this job as one sum with no line breakdown, so it cannot be checked item by item. Ask for an itemised breakdown before you commit.', 'سعّر المورّد العمل بمبلغ إجمالي واحد دون تفصيل بالبنود، لذا لا يمكن التحقق منه بندًا بندًا. اطلب تفصيلًا بالبنود قبل الالتزام.') });
  }
  // Totals (ruling 1207): the lines' own sum, then the supplier's price exactly as stated — before the discount,
  // the discount in the supplier's words, after the discount — then the supplier's VAT as stated. The bold figure
  // is the final price excluding VAT, which our fee is taken on (ruling 1208). A TRN never reaches the page.
  const sum = items.reduce((a, it) => a + (Number(it.amount) > 0 ? Number(it.amount) : 0), 0);
  const trows: Array<[string, string, boolean?]> = [];
  const gross = Number(q.gross_amount) > 0 ? Number(q.gross_amount) : null, disc = Number(q.discount_amount) > 0 ? Number(q.discount_amount) : null;
  const discounted = !!(gross && disc && gross > exVat);
  // The lines' sum is printed unless it is the very figure printed as the price before the discount.
  if (sum > 0 && !(discounted && Math.abs(sum - gross!) <= 1)) trows.push([T('Lines subtotal', 'مجموع البنود'), k.money(sum, true)]);
  if (discounted) {
    trows.push([T('Price before discount, as stated', 'السعر قبل الخصم كما ذكره المورّد'), k.money(gross, true)]);
    const dl = q.discount_label ? k.loc(q.discount_label, 80).text : '';
    trows.push([T('Discount', 'الخصم') + (dl ? ` (${dl})` : ''), '− ' + k.money(disc, true)]);
  }
  trows.push([gross && disc ? T('Total quoted after discount, excluding VAT', 'إجمالي العرض بعد الخصم غير شامل الضريبة') : T('Total quoted, excluding VAT', 'إجمالي العرض غير شامل الضريبة'), k.money(exVat, true), true]);
  const vatAmt = Number(q.vat_amount) > 0 ? Number(q.vat_amount) : null;
  if (vatAmt && (q.vat_treatment === 'exclusive' || q.vat_treatment === 'confirmed_on_portal')) {
    trows.push([T('VAT, as stated by the supplier', 'ضريبة القيمة المضافة كما ذكرها المورّد'), k.money(vatAmt, true)]);
    trows.push([T('Total including VAT, as stated', 'الإجمالي شاملًا الضريبة كما ذكره المورّد'), k.money(Math.round((exVat + vatAmt) * 100) / 100, true)]);
  } else if (q.vat_treatment === 'inclusive' && Number(q.amount_as_stated) > 0) {
    trows.push([T('Total including VAT, as stated', 'الإجمالي شاملًا الضريبة كما ذكره المورّد'), k.money(q.amount_as_stated, true)]);
  }
  // A stated discount explains lines that add up to the price before it.
  const diff = sum > 0 && exVat > 0 && Math.abs(sum - exVat) > 1 && !(discounted && Math.abs(sum - gross!) <= 1);
  blocks.push({ t: 'totals', rows: trows, note: diff ? T(`The line amounts add up to ${k.money(sum, true)}; the quoted total is ${k.money(exVat, true)}. The quoted total is the price this supplier offered.`, `مجموع مبالغ البنود ${k.money(sum, true)} بينما إجمالي العرض ${k.money(exVat, true)}. إجمالي العرض هو السعر الذي قدّمه هذا المورّد.`) : '' });
  blocks.push({ t: 'note', text: vatStated(q as PriceRow, lang) });
  blocks.push({ t: 'note', text: feeBasisLine(exVat || null, args.revealRate ?? null, lang) });
  blocks.push({ t: 'callout', tone: 'gold', title: T('The supplier\'s quotation, as stated', 'عرض المورّد كما ذكره'), text: T(NOT_RESPONSIBLE.en, NOT_RESPONSIBLE.ar) });

  section('Completeness check', 'فحص اكتمال العرض');
  blocks.push({ t: 'p', text: T('A quote is complete when it states all four of these. Each is marked as the supplier stated it.', 'يكون العرض مكتملًا عندما يذكر هذه البنود الأربعة كلها. كل بند معلّم كما ذكره المورّد.'), muted: true });
  const specN = items.filter(hasSpecs).length;
  const checks: Array<[string, Cell]> = [];
  checks.push([T('Material specification, per line', 'مواصفات المواد لكل بند'), !items.length ? { text: T('No line breakdown', 'لا يوجد تفصيل بالبنود'), flag: 'missing' }
    : specN === items.length ? { text: T(`Stated on all ${items.length} lines`, `مذكورة في جميع البنود (${items.length})`), flag: 'match' }
    : { text: T(`Missing on ${items.length - specN} of ${items.length} lines`, `ناقصة في ${items.length - specN} من ${items.length} بنود`), flag: 'missing' }]);
  checks.push([T('Delivery / lead time', 'التسليم / مدة التنفيذ'), lead ? { text: lead, flag: 'match' } : { text: T('Not stated', 'غير مذكورة'), flag: 'missing' }]);
  const instScope = [q.installation_scope ? k.loc(q.installation_scope, 120).text : '', q.installation_timeline ? k.dur(q.installation_timeline) : ''].filter(Boolean).join(' · ');
  checks.push([T('Installation', 'التركيب'), q.installation_applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' }
    : q.installation_included === true ? { text: T('Included', 'مشمول') + (instScope ? ' — ' + instScope : ''), flag: instScope ? 'match' : 'missing' }
    : q.installation_included === false ? { text: T('Not included', 'غير مشمول'), flag: 'differs' } : { text: T('Not stated', 'غير مذكور'), flag: 'missing' }]);
  const coverage = q.warranty_coverage ? k.loc(q.warranty_coverage, 120).text : '';
  checks.push([T('Warranty — period and coverage', 'الضمان — المدة والتغطية'), q.warranty_applicable === false ? { text: T('N/A', 'لا ينطبق'), flag: 'na' }
    : warranty && coverage ? { text: `${warranty} — ${coverage}`, flag: 'match' }
    : warranty ? { text: `${warranty} — ${T('coverage not stated', 'التغطية غير مذكورة')}`, flag: 'missing' } : { text: T('Not stated', 'غير مذكور'), flag: 'missing' }]);
  blocks.push({ t: 'checks', items: checks });

  // THE SALES ENGINEER'S NOTES (founder ledger 1588, 10 Nov 2026): what this quote does not meet of the request — scope
  // left out, an exclusion that cuts it, another origin or a lower tier or grade, a quantity short, a late delivery,
  // a shorter warranty — in plain words, naming no brand. Printed only when the review ran (an array, even empty).
  if (Array.isArray(args.reviewNotes)) {
    section('Our sales engineer\'s review', 'مراجعة مهندس المبيعات لدينا');
    if (!args.reviewNotes.length) blocks.push({ t: 'p', text: T('We checked this quote against your request and found no deviation from what you asked for.', 'راجعنا هذا العرض مقابل طلبك ولم نجد فيه ما يخالف ما طلبته.') });
    else for (const n of args.reviewNotes.slice(0, 20)) blocks.push({ t: 'li', text: T(n.en, n.ar) });
  }

  section('Commercial terms', 'الشروط التجارية');
  blocks.push({ t: 'terms', cols: 3, cells: [
    [T('Lead time', 'مدة التنفيذ'), lead || '—'], [T('Quote validity', 'صلاحية العرض'), validity || T('Not stated by the supplier', 'لم يذكرها المورّد')], [T('Warranty', 'الضمان'), warranty || '—'],
    [T('Payment terms', 'شروط الدفع'), k.pay(q.payment_terms)],
    [T('Installation', 'التركيب'), q.installation_applicable === false ? T('N/A', 'لا ينطبق') : q.installation_included === true ? T('Included', 'مشمول') : q.installation_included === false ? T('Not included', 'غير مشمول') : T('Not stated', 'غير مذكور')],
    [T('Delivery to', 'التسليم إلى'), emirate || '—'],
  ] });

  const notes: Array<[string, string, unknown]> = [['Scope as stated by the supplier', 'نطاق العمل كما ذكره المورّد', q.scope], ['Assumptions and conditions', 'الافتراضات والشروط', q.conditions], ['Exclusions', 'الاستثناءات', q.exclusions], ['Supplier notes', 'ملاحظات المورّد', q.notes]];
  if (notes.some(([, , v]) => v != null && String(v).trim() !== '')) {
    section('Scope notes, assumptions and exclusions', 'ملاحظات النطاق والافتراضات والاستثناءات');
    for (const [en, arx, v] of notes) { if (v == null || String(v).trim() === '') continue; const r = k.loc(v, 800); blocks.push({ t: 'p', label: T(en, arx), text: r.text, sub: r.sub }); }
  }

  blocks.push({ t: 'callout', tone: 'grey', title: T('Standardised by QuotesDone from the supplier\'s submission', 'وحّدته QuotesDone من العرض الذي قدّمه المورّد'),
    text: T(`${PREPARED_BY.en}. This is QuotesDone's standard layout of the supplier's quote, not the supplier's own document, and it carries no signature. Figures, specifications and scope are as the supplier stated them; verify final details before ordering. QuotesDone charges the customer a 3% facilitation fee at the point of contact reveal, on the supplier's final price after any stated discount and before VAT; no card fee, no VAT on our fee.`,
      `${PREPARED_BY.ar}. هذا هو التنسيق الموحّد لعرض المورّد لدى QuotesDone وليس مستند المورّد نفسه، ولا يحمل توقيعًا. القيم والمواصفات والنطاق كما ذكرها المورّد؛ يُرجى التحقق من التفاصيل النهائية قبل الطلب. تتقاضى QuotesDone من العميل رسوم تيسير بنسبة 3% عند كشف بيانات التواصل، تُحتسب على السعر النهائي للمورّد بعد أي خصم يذكره وقبل الضريبة، بلا رسوم بطاقة ولا ضريبة قيمة مضافة على رسومنا.`) });
  if (args.requestUrl) blocks.push({ t: 'link', text: T('Open this quote on your request in the QuotesDone portal', 'افتح هذا العرض في طلبك على بوابة QuotesDone'), link: args.requestUrl });

  const cover0 = {
    kicker: T('Standardised quotation', 'عرض أسعار موحّد'), title: T('Quotation', 'عرض أسعار'),
    subtitle: clipCell(summary.text, 170),
    meta: [[T('Reference', 'الرقم المرجعي'), ref], [T('Date', 'التاريخ'), date], [T('Quoting party', 'مقدّم العرض'), party], [T('Trade', 'التخصص'), trade || '—']],
    figures: [[T('Total quoted', 'إجمالي العرض'), priceStated(q as PriceRow, lang)], [T('Lead time', 'مدة التنفيذ'), lead || '—'], [T('Warranty', 'الضمان'), warranty || '—'], [T('Valid for', 'صالح لمدة'), validity || '—']],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  const names = args.maskNames || [];
  const body: Record<string, unknown> = {
    lang, ref, name: docName(ref, 'quotation', lang), title: T('Quotation', 'عرض أسعار'),
    // A REVEALED quotation (partyName set) names its supplier: firm and person shapes are not masked there (review of
    // #1838 item 1: the chip read "[contact hidden until reveal]" after a paid reveal). Contacts still are, as before.
    cover: maskDeep(cover0, names, lang, !args.partyName), control, blocks: maskDeep(blocks, names, lang, !args.partyName), options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, untranslated: [...k.untranslated] };
}

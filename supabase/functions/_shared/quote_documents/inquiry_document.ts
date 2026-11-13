import { DOC_VERSION, type Lang, PREPARED_BY, docName, maskContacts, maskDeep } from './base.ts';
import { type ArTexts, type Cell, ORIGINAL, kit } from './kit.ts';
import { clipCell, jobNoOf, quoteRef } from './rows.ts';
import { arCategory, arCount, arEmirate, arUnit, enCategory, norm } from './arabic.ts';

// ── The inquiry, as the supplier receives it ───────────────────────────────────────────────────
// 21 Sep 2026, sales_engineer. Founder instruction 435 (15 Sep 2026): each inquiry opens the sales
// engineer's template with all requirements, and the BOQ and drawings are downloadable, redacted.
// Measured 21 Sep 2026: the "Inquiries received" screen drew that template as a web page only; no
// document existed, while the customer had three (quotation, comparison, brief). This is the fourth,
// on the same renderer. The caller hands in the inbox's row — already through the inbox's scrubbers
// and its reveal gate — so nothing here reads the inquiry itself; contacts are masked once more on
// the way to the page, the way every other document does it.
/** One customer-authored BOQ line as the inbox serves it (quote_review.ts BoqRow). */
export type RequestLine = { section?: string | null; description?: string | null; section_ar?: string | null; description_ar?: string | null; qty?: number | string | null; unit?: string | null; qty_status?: string | null; specification?: string | null };
// WHERE A QUANTITY CAME FROM, as the supplier must read it (21 Sep 2026, sales_engineer; founder instruction
// 580: the BOQ PDF we send suppliers must be perfect). MEASURED on drawing_boq/drawing_chain.test.ts: a
// reader line with qty_status 'to_confirm' reached this page as a bare "12 nos", indistinguishable from a
// quantity printed on the drawing — the supplier could not tell OUR take-off estimate from the customer's
// own number, and the CSV beside it dropped the status too. Every status the chain writes
// (drawing_boq readers, boq_open_lines.settleLines, drawing_boq/confirm.ts) now prints as words, EN + AR.
// An unknown status is shown as "to confirm": a quantity whose origin we cannot state is never presented as read.
export function qtyBasis(l: RequestLine): { en: string; ar: string; open: boolean } | null {
  const st = String(l.qty_status ?? '').trim();
  if (l.qty == null || l.qty === '') return { en: 'Not counted: take off from the drawing', ar: 'لم تُعدّ: احسبها من المخطط', open: true };
  if (!st) return null;
  if (st === 'read') return { en: 'Read from the drawing', ar: 'مقروءة من المخطط', open: false };
  if (st === 'check_confirmed') return { en: 'Counted from the drawing, cross-checked', ar: 'معدودة من المخطط ومُتحقَّق منها', open: false };
  if (st === 'customer_confirmed') return { en: 'Our count, confirmed by the customer', ar: 'عددنا، وأكّده العميل', open: false };
  if (st === 'customer_stated') return { en: 'Stated by the customer', ar: 'حدّدها العميل', open: false };
  // to_confirm, estimated, estimated_supplier_to_verify — and any status this list does not know.
  return { en: 'To confirm: our estimate, verify the take-off', ar: 'للتأكيد: تقديرنا، يُرجى التحقق من الحصر', open: true };
}
export type InquiryDocRow = {
  id: string; rfq_no?: number | string | null; category?: string | null; emirate?: string | null; summary?: string | null; budget?: string | null;
  scope_type?: string | null; urgency?: string | null; created_at?: string | null;
  /** 'quotation' when the BOQ is the customer's existing quotation rebuilt as our inquiry (13 Nov 2026). */
  brief_source?: string | null;
  /** inquiries.spec after the inbox scrub; `customer_requirements` carries the four intake answers and `required_by`. */
  // deno-lint-ignore no-explicit-any
  spec?: any;
  boq?: { boq?: RequestLine[] } | null; boq_withheld?: boolean | null;
  /** What inquiry_documents offers for download, by name: the redacted drawing pages and the BOQ CSV. */
  documents: Array<{ kind: 'drawing_page' | 'boq_csv'; name: string; lines?: number }>;
  drawing_pages_failed?: number | null;
};
const URGENCY: Record<string, [string, string]> = { urgent: ['Urgent', 'عاجل'], high: ['Urgent', 'عاجل'], normal: ['Standard', 'عادي'], standard: ['Standard', 'عادي'], low: ['Not urgent', 'غير عاجل'], flexible: ['Flexible', 'مرن'] };
export function inquiryDocument(args: { inquiry: InquiryDocRow; lang: Lang; portalUrl?: string; date?: string; date_ar?: string; arTexts?: ArTexts }) {
  const { inquiry: i, lang } = args;
  const k = kit(lang, [], args.arTexts); const { T, ar } = k;
  const job = jobNoOf(i);
  const ref = quoteRef(i, 'RFQ');
  const date = (ar ? args.date_ar : args.date) || k.today();
  const trade = ar ? (arCategory(i.category) ?? k.loc(i.category).text) : enCategory(i.category);
  const emirate = ar ? (arEmirate(i.emirate) ?? k.loc(i.emirate).text) : String(i.emirate || '');
  const received = i.created_at ? new Date(i.created_at).toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { timeZone: 'Asia/Dubai', day: 'numeric', month: 'long', year: 'numeric' }) : '—';
  // Customer free text: the reasoned Arabic, like the supplier's (see loc).
  const cust = (v: unknown, max: number): { text: string; sub?: string } => k.loc(v, max);
  const summary = cust(i.summary, 800);
  const req = i.spec && typeof i.spec === 'object' ? i.spec.customer_requirements : null;
  // The deadline: the intake's `required_by` (docs/contracts/intake_answers.md) — a date, or flexible,
  // or the customer's words. Never assumed: absent means "not stated".
  const rb = req && typeof req === 'object' ? req.required_by : null;
  const deadline = rb?.flexible === true ? T('Flexible', 'مرن')
    : rb?.date && /^\d{4}-\d{2}-\d{2}/.test(String(rb.date)) ? new Date(String(rb.date).slice(0, 10) + 'T00:00:00Z').toLocaleDateString(ar ? 'ar-AE-u-nu-latn' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' })
    : rb?.text ? cust(rb.text, 80).text : T('Not stated', 'غير مذكور');
  const urgency = i.urgency ? (URGENCY[norm(i.urgency)] ? T(URGENCY[norm(i.urgency)][0], URGENCY[norm(i.urgency)][1]) : k.loc(i.urgency, 40).text) : '';
  const rows: RequestLine[] = Array.isArray(i.boq?.boq) ? i.boq!.boq!.filter((r) => r && String(r.description || '').trim()) : [];
  const drawings = i.documents.filter((d) => d.kind === 'drawing_page').length;
  const failed = Number(i.drawing_pages_failed || 0);
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  let n = 0; const section = (en: string, arx: string) => blocks.push({ t: 'section', n: ++n, text: T(en, arx) });

  section('The request', 'الطلب');
  blocks.push({ t: 'party', label: T('Requesting party', 'الجهة الطالبة'), chip: T('Customer', 'العميل'), note: T('Anonymous until the customer reveals your quotation. The customer\'s name and contact details reach you only after the reveal, through the portal.', 'هوية العميل مخفية حتى يكشف عن عرضك. لا تصلك بيانات التواصل إلا بعد الكشف، عبر البوابة.') });
  const kv: Array<[string, string]> = [[T('Job No.', 'رقم الطلب'), job], [T('Received', 'تاريخ الاستلام'), received], [T('Trade', 'التخصص'), trade || '—'], [T('Site', 'الموقع'), emirate || '—'], [T('Required by', 'مطلوب بحلول'), deadline]];
  if (urgency) kv.push([T('Urgency', 'الأولوية'), urgency]);
  if (i.scope_type) kv.push([T('Scope type', 'نوع النطاق'), k.loc(i.scope_type, 40).text]);
  blocks.push({ t: 'kv', pairs: kv });
  if (summary.text) blocks.push({ t: 'p', text: summary.text, sub: summary.sub, label: T('Scope', 'النطاق') });
  if (i.budget) { const b = cust(i.budget, 80); blocks.push({ t: 'p', text: b.text, sub: b.sub, label: T('Budget', 'الميزانية') }); }

  section('What the customer asked for', 'ما طلبه العميل');
  // The derived `display` rows are the one vocabulary every surface renders (the request card, the
  // supplier RFQ, the brief PDF); this document reads them in its own language and never re-derives.
  const disp = req && typeof req === 'object' && req.display && typeof req.display === 'object' ? req.display[lang] : null;
  const reqRows: Array<{ label?: unknown; value?: unknown }> = Array.isArray(disp) ? disp : [];
  if (reqRows.length) blocks.push({ t: 'table', head: [T('Requirement', 'المتطلب'), T('Requested', 'المطلوب')], rows: reqRows.map((r) => [clipCell(maskContacts(r.label, [], lang), 60), k.cell(r.value, 160)]), widths: [0.32, 0.68], align: ['s', 's'], zebra: true });
  else blocks.push({ t: 'note', text: T('The customer\'s answers on materials, installation, warranty and the required date were not recorded on this request. Quote as the scope and the bill of quantities state, and note any assumption.', 'لم تُسجَّل إجابات العميل عن المواد والتركيب والضمان والتاريخ المطلوب في هذا الطلب. سعّر وفق النطاق وجدول الكميات، ودوّن أي افتراض.') });

  // THE BRIEF ITSELF (13 Nov 2026, sales_engineer): the checklist answers the intake recorded (inquiries.spec, after the inbox
  // gate: no customer-only key, the address key at the emirate) were served to the portal and never printed here, so the PDF
  // a supplier downloads said "Renovation of two bathrooms" and nothing of the tiles, the floor or the warranty asked for.
  // Every string answer is printed under its key read as words; what the intake stores for itself is not.
  const INTERNAL = new Set(['customer_requirements', 'boq_check', 'site_location', 'old_supplier_terms', 'site_keys', 'service_keys', 'trade_codes', 'checklist_topics', 'provenance', 'spec_evidence']);
  const briefRows: Cell[][] = i.spec && typeof i.spec === 'object' ? Object.entries(i.spec as Record<string, unknown>)
    .filter(([key, v]) => !INTERNAL.has(key) && (typeof v === 'string' || typeof v === 'number' || (Array.isArray(v) && v.every((x) => typeof x === 'string' || typeof x === 'number'))) && String(v).trim() !== '')
    .slice(0, 40).map(([key, v]) => [clipCell(maskContacts(key.replace(/[_.]+/g, ' ').replace(/^\w/, (c) => c.toUpperCase()), [], lang), 60), k.cell(Array.isArray(v) ? v.join(', ') : String(v), 400)]) : [];
  if (briefRows.length) { section('The brief', 'تفاصيل الطلب'); blocks.push({ t: 'table', head: [T('Item', 'البند'), T('As the customer stated it', 'كما ذكره العميل')], rows: briefRows, widths: [0.32, 0.68], align: ['s', 's'], zebra: true }); }
  // A CUSTOMER'S EXISTING QUOTATION (13 Nov 2026, founder ruling 1683): its items are this document's BOQ, said to be what
  // they are; its pages and file are never offered, and the old supplier's prices, names and references were not read.
  const fromQuotation = i.brief_source === 'quotation';
  section(fromQuotation ? 'Items to quote' : 'Bill of quantities', fromQuotation ? 'البنود المطلوب تسعيرها' : 'جدول الكميات');
  if (fromQuotation && !i.boq_withheld && rows.length) blocks.push({ t: 'note', text: T('The customer already holds a quotation for this work from another supplier. Its items, quantities, units and the makes it specifies are listed here on our template; that supplier\'s prices, name, references and pages are not shared. Quote your own price for each line.', 'لدى العميل عرض سعر لهذا العمل من مورّد آخر. بنوده وكمياته ووحداته والماركات المحددة فيه مدرجة هنا على نموذجنا؛ ولا تُشارَك أسعار ذلك المورّد ولا اسمه ولا مراجعه ولا صفحاته. سعّر كل بند بسعرك أنت.') });
  if (i.boq_withheld) blocks.push({ t: 'callout', tone: 'grey', title: T('Held back', 'محجوب'), text: T('The bill of quantities is held back because it could not be proved free of the customer\'s details. Price from the drawings and the scope.', 'حُجب جدول الكميات لأنه لم يمكن إثبات خلوّه من بيانات العميل. سعّر من المخططات والنطاق.') });
  else if (rows.length) {
    const hasSection = rows.some((r) => r.section && String(r.section).trim());
    const head: Cell[] = ['#']; const widths = [0.05]; const align = ['c'];
    if (hasSection) { head.push(T('Section', 'القسم')); widths.push(0.16); align.push('s'); }
    // The basis column appears whenever any line carries a status (or has no quantity); a BOQ the customer
    // typed with plain numbers keeps the four columns it always had.
    const bases = rows.map(qtyBasis); const hasBasis = bases.some(Boolean);
    // THE MAKE THE CUSTOMER SPECIFIED (13 Nov 2026, anonymity audit A, L6): a Make / Brand column read from the customer's
    // BOQ or quotation (boq_from_sheet 'spec') was dropped here, so a supplier could not price the make that was asked for.
    const hasSpec = rows.some((r) => r.specification && String(r.specification).trim());
    const specW = hasSpec ? 0.16 : 0;
    head.push(T('Description', 'الوصف')); widths.push((hasSection ? (hasBasis ? 0.39 : 0.59) : (hasBasis ? 0.55 : 0.75)) - specW); align.push('s');
    if (hasSpec) { head.push(T('Specified make', 'الماركة المحددة')); widths.push(specW); align.push('s'); }
    head.push(T('Qty', 'الكمية'), T('Unit', 'الوحدة')); widths.push(0.10, 0.10); align.push('e', 'c');
    if (hasBasis) { head.push(T('Quantity basis', 'أساس الكمية')); widths.push(0.20); align.push('s'); }
    // EVERY LINE IS ON THE PDF (13 Nov 2026; ruling 1672, every document is a PDF in our template): the page used to stop at
    // 120 lines and point to the CSV for the rest. The CSV stays beside it as a convenience only.
    const body = rows.slice(0, 600).map((r, idx) => {
      const c: Cell[] = [String(idx + 1)];
      // Arabic page: the section and the description are the REASONED Arabic of the customer's words, like every
      // other line (decision point trade_glossary_ar). The word-matched section_ar / description_ar labels
      // (_shared/boq_arabic.ts) are not printed on a document.
      if (hasSection) c.push(k.cell(r.section, 60));
      c.push(k.cell(r.description, 240));
      if (hasSpec) c.push(r.specification && String(r.specification).trim() ? k.cell(r.specification, 80) : '—');
      c.push(r.qty == null || r.qty === '' ? '—' : String(r.qty), (ar ? (arUnit(r.unit) ?? k.loc(r.unit).text) : String(r.unit || '')) || '—');
      if (hasBasis) { const b0 = bases[idx]; const b = b0 && fromQuotation && b0.open ? { en: 'Not stated: confirm the quantity', ar: 'غير مذكورة: أكّد الكمية', open: true } : b0; c.push(b ? { text: T(b.en, b.ar), ...(b.open ? { flag: 'missing' as const } : {}) } : '—'); }
      return c;
    });
    blocks.push({ t: 'table', head, rows: body, widths, align, zebra: true });
    const open = bases.filter((b) => b?.open).length;
    // WHAT IS NOT KNOWN (13 Nov 2026; founder ruling 1683): the reading's sufficiency verdict names what a supplier of the trade
    // still needs; whatever the customer did not then answer is said here, so a supplier prices it as a stated assumption.
    const suf = (i.boq as { sufficiency?: { verdict?: string; missing?: unknown[] } } | null)?.sufficiency;
    const notKnown = suf?.verdict === 'not_yet' && Array.isArray(suf.missing) ? suf.missing.map((m) => String(m ?? '').trim()).filter(Boolean).slice(0, 8) : [];
    if (notKnown.length) blocks.push({ t: 'callout', tone: 'grey', title: T('Not stated in the customer\'s file', 'غير مذكور في ملف العميل'), text: T(`Check the brief above for the customer's answers; anything still open, price as an assumption and state it on your quotation: ${notKnown.join('; ')}.`, `راجع تفاصيل الطلب أعلاه لإجابات العميل؛ وما بقي مفتوحًا سعّره كافتراض واذكره في عرضك: ${notKnown.join('؛ ')}.`) });
    if (open && !fromQuotation) blocks.push({ t: 'note', text: T(`${open} line${open === 1 ? ' is' : 's are'} marked "To confirm" or "Not counted": the quantity is our take-off estimate from the drawing, not the customer's figure. Measure it, and state the quantity you priced on your quotation.`, `${open} من البنود معلّمة «للتأكيد» أو «لم تُعدّ»: الكمية تقديرنا من المخطط وليست رقم العميل. تحقّق منها واذكر الكمية التي سعّرتها في عرضك.`) });
    if (rows.length > 600) blocks.push({ t: 'note', text: T(`${rows.length - 600} further lines are in the BOQ file.`, `يوجد ${rows.length - 600} بندًا إضافيًا في ملف جدول الكميات.`) });
  } else blocks.push({ t: 'note', text: T('No bill of quantities was attached. Price from the scope and the drawings.', 'لم يُرفق جدول كميات. سعّر من النطاق والمخططات.') });

  section('Documents attached', 'المستندات المرفقة');
  if (i.documents.length) {
    blocks.push({ t: 'table', head: ['#', T('Document', 'المستند'), T('File', 'الملف')], widths: [0.06, 0.5, 0.44], align: ['c', 's', 's'], zebra: true,
      rows: i.documents.map((d, idx) => [String(idx + 1), d.kind === 'boq_csv' ? T(`The same ${fromQuotation ? 'items' : 'bill of quantities'} as a spreadsheet (${d.lines || rows.length} lines, CSV; every line is on this document)`, `${fromQuotation ? 'البنود نفسها' : 'جدول الكميات نفسه'} كجدول بيانات (${d.lines || rows.length} بندًا؛ كل البنود في هذا المستند)`) : T(`Drawing page (identity removed)`, `صفحة مخطط (بعد إخفاء الهوية)`), d.name]) });
  } else blocks.push({ t: 'note', text: T('No documents were attached to this inquiry.', 'لم تُرفق مستندات بهذا الطلب.') });
  if (failed) blocks.push({ t: 'note', text: T(`${failed} drawing page${failed === 1 ? '' : 's'} could not be served at the time of writing; the portal offers ${failed === 1 ? 'it' : 'them'} again when available.`, `تعذّر تقديم ${failed} من صفحات المخطط وقت الإعداد؛ تعرضها البوابة مجددًا عند توفرها.`) });

  blocks.push({ t: 'callout', tone: 'grey', title: T('Prepared by the QuotesDone sales engineer', 'أعدّه مهندس مبيعات QuotesDone'),
    text: T(`${PREPARED_BY.en}. This is the request as our sales engineer prepared it for you, with the customer's identity removed. Quote every line with its exact specification, the delivery date, installation and warranty, and the price excluding VAT; a quotation missing any of these is held until it is complete. Send it through the QuotesDone portal, where our sales engineer reviews it with you before it reaches the customer.`,
      `${PREPARED_BY.ar}. هذا هو الطلب كما أعدّه لك مهندس المبيعات لدينا، بعد إزالة هوية العميل. سعّر كل بند بمواصفاته الدقيقة، وتاريخ التسليم، والتركيب، والضمان، والسعر دون ضريبة القيمة المضافة؛ يُحجز أي عرض ينقصه شيء من ذلك حتى يكتمل. أرسله عبر بوابة QuotesDone حيث يراجعه معك مهندس المبيعات قبل وصوله إلى العميل.`) });
  if (args.portalUrl) blocks.push({ t: 'link', text: T('Open this inquiry in the QuotesDone supplier portal', 'افتح هذا الطلب في بوابة المورّدين على QuotesDone'), link: args.portalUrl });

  const inst = req?.installation?.required, warr = req?.warranty?.required;
  const instTxt = inst === 'yes' ? T('Required', 'مطلوب') : inst === 'supply_only' ? T('Supply only', 'توريد فقط') : inst === 'not_needed' ? T('Not needed', 'غير مطلوب') : inst === 'not_sure' ? T('To be stated', 'يُذكر في العرض') : '—';
  const warrTxt = warr === 'yes' ? (Number(req?.warranty?.min_months) > 0 ? (ar ? arCount(Number(req.warranty.min_months), 'month') + ' على الأقل' : `${Number(req.warranty.min_months)} months minimum`) : T('Required', 'مطلوب')) : warr === 'not_needed' ? T('Not needed', 'غير مطلوب') : warr === 'not_sure' ? T('To be stated', 'يُذكر في العرض') : '—';
  const cover0 = {
    kicker: T('Request for quotation', 'طلب عرض أسعار'), title: T('Inquiry', 'استفسار'),
    // a summary the gate withheld leaves the trade and the site, never a blank line (review of F2: the careless-quotation PDF)
    subtitle: clipCell(summary.text || [trade, emirate].filter(Boolean).join(T(' in ', ' في ')), 170),
    meta: [[T('Job No.', 'رقم الطلب'), job], [T('Date', 'التاريخ'), date], [T('Trade', 'التخصص'), trade || '—'], [T('Site', 'الموقع'), emirate || '—']],
    figures: [[T('Required by', 'مطلوب بحلول'), deadline], [fromQuotation ? T('Items', 'البنود') : T('BOQ lines', 'بنود الكميات'), i.boq_withheld ? T('Held', 'محجوب') : String(rows.length)], [T('Installation', 'التركيب'), instTxt], [T('Warranty', 'الضمان'), warrTxt]],
  };
  const control = `${ref} · ${DOC_VERSION} · ${T('Generated', 'أُنشئ في')} ${date} · ${ar ? PREPARED_BY.ar : PREPARED_BY.en}`;
  // Every secondary line on this document is the customer's wording, so it is labelled as such.
  const CUSTOMER_ORIGINAL = 'النص الأصلي من العميل: ';
  // deno-lint-ignore no-explicit-any
  const relabel = (v: any): any => typeof v === 'string' ? (v.startsWith(ORIGINAL) ? CUSTOMER_ORIGINAL + v.slice(ORIGINAL.length) : v) : Array.isArray(v) ? v.map(relabel) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([kk, x]) => [kk, kk === 'sub' ? relabel(x) : relabel(x)])) : v;
  const body: Record<string, unknown> = {
    title: T('Inquiry', 'استفسار'), ref, name: docName(ref, 'inquiry', lang), lang,
    cover: relabel(maskDeep(cover0, [], lang)), control, blocks: relabel(maskDeep(blocks, [], lang)), options: { letterhead: true, contact: false },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref, job, drawings, untranslated: [...k.untranslated] };
}

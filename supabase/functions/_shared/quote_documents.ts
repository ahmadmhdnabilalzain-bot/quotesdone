// quote_documents.ts — what goes ON the customer's quotation PDF and comparison report.
//
// 14 Sep 2026, agent: ceo. The founder: "when someone is in Arabic and presses the quotation, the
// quotation needs to be translated in Arabic; the comparison report needs to be in Arabic. The
// English version always remains, but we also provide the Arabic one."
//
// WHAT WAS THERE. customer_api built both documents inline. The Arabic quotation was the English
// page plus a second page whose words came from ai_gateway (translateQuoteAr). OpenRouter is on
// hold, so that call fails and the code fell back to `quote_ar = quote`: the "Arabic" page carried
// Arabic headings over English content, every time. An English customer had no Arabic copy at all.
//
// WHAT IT IS NOW. Two single-language documents per quote, both always available, built with no
// model. Everything the platform itself knows the meaning of is translated deterministically — the
// labels, the emirate, the trade, durations ("2 weeks", "10-14 days", "12 months"), recognised
// payment-term phrases and units. What only the supplier knows — their item descriptions, scope,
// conditions — is reproduced exactly as they wrote it, and the Arabic page SAYS so. A translated
// description that is wrong about a specification is worse than an honest original.
//
// ANONYMITY. The customer pays a reveal fee to learn who quoted. Supplier free text can carry a
// name, a number or an email ("call Ahmed on 050…"), so every string in both documents passes
// maskContacts, which also blanks the supplier names the caller hands in. This is the last line
// before the page; it does not replace redaction upstream.

export type Lang = 'en' | 'ar';

/** A, B … Z, AA, AB … — the anonymous label for the i-th live quote by ascending price. */
export function supplierLabel(i: number): string { let n = Number(i) || 0, out = ''; do { out = String.fromCharCode(65 + (n % 26)) + out; n = Math.floor(n / 26) - 1; } while (n >= 0); return out; }

// ── Anonymity ─────────────────────────────────────────────────────────────────────────────────
const HIDDEN = { en: '[contact hidden until reveal]', ar: '[بيانات التواصل مخفية حتى الكشف]' };
function escapeRe(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
/** Blank emails, phone numbers, web addresses and the named suppliers out of one string. */
export function maskContacts(s: unknown, names: string[] = [], lang: Lang = 'en'): string {
  let t = String(s == null ? '' : s);
  // The placeholder follows the script of the text it sits in, not the page: an Arabic placeholder
  // inside an English supplier note turned the whole note right-to-left and scrambled its order.
  const H = HIDDEN[/[؀-ۿ]/.test(t) ? 'ar' : /[A-Za-z]/.test(t) ? 'en' : lang];
  t = t.replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, H);
  t = t.replace(/\b(?:https?:\/\/|www\.)\S+/gi, H);
  t = t.replace(/\b[\w-]+\.(?:com|ae|net|org|co)(?:\.[a-z]{2})?\b/gi, H);
  // UAE numbers in every usual spelling, then any international-looking run of 9+ digits.
  t = t.replace(/(?:\+|00)?971[\s-]?\(?0?\)?[\s-]?\d(?:[\s-]?\d){6,8}\b/g, H);
  t = t.replace(/\b0[2-9](?:[\s-]?\d){7,8}\b/g, H);
  t = t.replace(/\+\d(?:[\s-]?\d){8,13}\b/g, H);
  for (const n of names) {
    const v = String(n || '').trim();
    if (v.length < 3) continue;
    t = t.replace(new RegExp(escapeRe(v), 'gi'), H);
    // "ZZ DEMO Cooling Services LLC" also appears as "ZZ DEMO Cooling Services".
    const core = v.replace(/\b(?:l\.?l\.?c|fze|fzco|fz-llc|est|establishment|trading|co|company|ltd|limited)\.?\s*$/i, '').trim();
    if (core.length >= 5 && core !== v) t = t.replace(new RegExp(escapeRe(core), 'gi'), H);
  }
  return t;
}
// deno-lint-ignore no-explicit-any
function maskDeep(v: any, names: string[], lang: Lang): any {
  if (typeof v === 'string') return maskContacts(v, names, lang);
  if (Array.isArray(v)) return v.map((x) => maskDeep(x, names, lang));
  // deno-lint-ignore no-explicit-any
  if (v && typeof v === 'object') { const o: any = {}; for (const k of Object.keys(v)) o[k] = (k === 'link') ? v[k] : maskDeep(v[k], names, lang); return o; }
  return v;
}

// ── Deterministic Arabic ────────────────────────────────────────────────────────────────────────
const hasArabic = (s: unknown) => /[؀-ۿ]/.test(String(s ?? ''));
const hasLatin = (s: unknown) => /[A-Za-z]/.test(String(s ?? ''));
const norm = (s: unknown) => String(s ?? '').toLowerCase().replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();

const EMIRATES: Record<string, string> = {
  'dubai': 'دبي', 'abu dhabi': 'أبوظبي', 'sharjah': 'الشارقة', 'ajman': 'عجمان', 'umm al quwain': 'أم القيوين',
  'umm al-quwain': 'أم القيوين', 'ras al khaimah': 'رأس الخيمة', 'ras al-khaimah': 'رأس الخيمة', 'rak': 'رأس الخيمة',
  'fujairah': 'الفجيرة', 'al ain': 'العين', 'uae': 'الإمارات العربية المتحدة', 'all emirates': 'جميع الإمارات',
};
export function arEmirate(s: unknown): string | null { if (hasArabic(s)) return String(s); return EMIRATES[norm(s)] ?? null; }

const CATEGORIES: Array<[RegExp, string]> = [
  [/^(hvac|ac|a\/c|air ?conditioning|hvac ?(and|&) ?refrigeration|cooling)$/, 'التكييف والتبريد (HVAC)'],
  [/^mep$/, 'الأعمال الكهروميكانيكية (MEP)'], [/^electrical( works)?$/, 'الأعمال الكهربائية'], [/^plumbing$/, 'السباكة'],
  [/^(joinery|carpentry|woodwork)$/, 'النجارة'], [/^painting$/, 'الدهانات'], [/^flooring$/, 'الأرضيات'], [/^tiling$/, 'التبليط'],
  [/^(glass|glazing|glass (and|&) aluminium|aluminium)$/, 'الزجاج والألمنيوم'], [/^(cctv|security|security systems)$/, 'كاميرات المراقبة والأنظمة الأمنية'],
  [/^(fire|fire fighting|firefighting|fire alarm|fire protection)$/, 'أنظمة الحماية من الحريق'], [/^(steel|metal|metal works|steel works)$/, 'الأعمال المعدنية'],
  [/^(signage|printing|signage (and|&) printing)$/, 'اللافتات والطباعة'], [/^cleaning$/, 'التنظيف'], [/^landscaping$/, 'تنسيق الحدائق'],
  [/^(fit ?out|interior fit ?out|interiors)$/, 'التشطيبات الداخلية'], [/^civil( works)?$/, 'الأعمال المدنية'], [/^events?$/, 'الفعاليات'],
  [/^(it|networking|it (and|&) networking)$/, 'الشبكات وتقنية المعلومات'], [/^waterproofing$/, 'العزل المائي'],
];
/** The English trade name as a person writes it: 'hvac' → 'HVAC', 'fit_out' → 'Fit Out'. */
export function enCategory(s: unknown): string {
  const n = norm(s); if (!n) return '';
  if (/^(hvac|mep|cctv|it|ac)$/.test(n)) return n.toUpperCase();
  return n.replace(/\b[a-z]/g, (c) => c.toUpperCase());
}
export function arCategory(s: unknown): string | null { if (hasArabic(s)) return String(s); const n = norm(s); for (const [re, ar] of CATEGORIES) if (re.test(n)) return ar; return null; }

type Unit = 'day' | 'week' | 'month' | 'year';
const FORMS: Record<Unit, [string, string, string, string]> = {
  day: ['يوم واحد', 'يومان', 'أيام', 'يومًا'], week: ['أسبوع واحد', 'أسبوعان', 'أسابيع', 'أسبوعًا'],
  month: ['شهر واحد', 'شهران', 'أشهر', 'شهرًا'], year: ['سنة واحدة', 'سنتان', 'سنوات', 'سنة'],
};
const WORKING: [string, string, string, string] = ['يوم عمل واحد', 'يوما عمل', 'أيام عمل', 'يوم عمل'];
/** Arabic counted noun: 1 and 2 have their own forms, 3-10 take the plural, 11+ the singular. */
export function arCount(n: number, unit: Unit, working = false): string {
  const f = working && unit === 'day' ? WORKING : FORMS[unit];
  if (n === 1) return f[0]; if (n === 2) return f[1];
  return `${n} ${n >= 3 && n <= 10 ? f[2] : f[3]}`;
}
const UNIT_OF: Record<string, Unit> = { day: 'day', days: 'day', week: 'week', weeks: 'week', wk: 'week', wks: 'week', month: 'month', months: 'month', mo: 'month', mos: 'month', year: 'year', years: 'year', yr: 'year', yrs: 'year' };
/** "2 weeks", "10-14 days", "12 months warranty", "3 working days", "immediate" → Arabic, or null. */
export function arDuration(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const t = norm(s).replace(/\.$/, '');
  if (!t) return null;
  if (/^(immediate(ly)?|asap|ex[- ]?stock|from stock|same day)$/.test(t)) return t.includes('stock') ? 'من المخزون فورًا' : 'فوري';
  const m = t.match(/^(\d{1,4})(?:\s*(?:-|–|to)\s*(\d{1,4}))?\s*(working |business |calendar )?(days?|weeks?|wks?|months?|mos?|years?|yrs?)(?: (?:warranty|validity|guarantee))?$/);
  if (!m) return null;
  const a = Number(m[1]), b = m[2] ? Number(m[2]) : null, unit = UNIT_OF[m[4]], working = !!m[3] && /working|business/.test(m[3]);
  if (!unit) return null;
  if (b === null) return arCount(a, unit, working);
  const f = working && unit === 'day' ? WORKING : FORMS[unit];
  return `${a}–${b} ${b >= 3 && b <= 10 ? f[2] : f[3]}`;
}
const EVENTS: Array<[RegExp, string]> = [
  [/^(completion|job completion|work completion|project completion)$/, 'الإنجاز'], [/^(delivery|material delivery|supply)$/, 'التسليم'],
  [/^(installation|install)$/, 'التركيب'], [/^(handover|hand over|final handover)$/, 'التسليم النهائي'],
  [/^(commissioning|testing (and|&) commissioning|t ?& ?c)$/, 'الاختبار والتشغيل'], [/^(approval|drawing approval|approval of drawings)$/, 'الاعتماد'],
  [/^(order|order confirmation|confirmation|lpo|po|signing|contract signing|award)$/, 'تأكيد الطلب'], [/^dispatch$/, 'الشحن'],
];
function arEvent(s: string): string | null { for (const [re, ar] of EVENTS) if (re.test(s.trim())) return ar; return null; }
/** A payment-terms phrase is translated only when EVERY part of it is recognised; otherwise null. */
export function arPayment(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const t = norm(s).replace(/\.$/, '');
  if (!t) return null;
  const parts = t.split(/\s*(?:,|;|\+|\band\b|&)\s*/).filter(Boolean);
  const out: string[] = [];
  for (const p of parts) {
    let m: RegExpMatchArray | null;
    if ((m = p.match(/^(\d{1,3})\s*%\s*(?:advance|down ?payment|deposit|upfront|mobili[sz]ation(?: advance)?)(?: payment)?$/))) { out.push(`${m[1]}% دفعة مقدّمة`); continue; }
    if ((m = p.match(/^(?:(\d{1,3})\s*%\s*)?(?:on|upon|after|at)\s+(.+)$/))) { const ev = arEvent(m[2]); if (!ev) return null; out.push(m[1] ? `${m[1]}% عند ${ev}` : `عند ${ev}`); continue; }
    if ((m = p.match(/^(\d{1,3})\s*%\s*(?:before|prior to)\s+(.+)$/))) { const ev = arEvent(m[2]); if (!ev) return null; out.push(`${m[1]}% قبل ${ev}`); continue; }
    if ((m = p.match(/^(\d{1,3})\s*%\s*(?:progress|monthly progress|against progress|as per progress)$/))) { out.push(`${m[1]}% حسب نسبة الإنجاز`); continue; }
    if ((m = p.match(/^(\d{1,3})\s*days?\s*(?:credit|pdc)$/)) || (m = p.match(/^(?:credit|pdc)\s*(\d{1,3})\s*days?$/))) { out.push(`دفع آجل خلال ${arCount(Number(m[1]), 'day')}`); continue; }
    if (/^(cash|cash on delivery|cod)$/.test(p)) { out.push(p === 'cash' ? 'نقدًا' : 'نقدًا عند التسليم'); continue; }
    if (/^(100\s*%\s*)?(advance|full advance|full payment in advance)$/.test(p)) { out.push('100% دفعة مقدّمة'); continue; }
    return null;
  }
  return out.length ? out.join('، ') : null;
}
const UNITS: Record<string, string> = {
  'nos': 'عدد', 'no': 'عدد', 'no.': 'عدد', 'nr': 'عدد', 'each': 'عدد', 'ea': 'عدد', 'pcs': 'قطعة', 'pc': 'قطعة', 'piece': 'قطعة', 'pieces': 'قطعة',
  'set': 'طقم', 'sets': 'طقم', 'lot': 'مقطوعية', 'ls': 'مقطوعية', 'l.s.': 'مقطوعية', 'lump sum': 'مقطوعية', 'job': 'مقطوعية',
  'm': 'م', 'mtr': 'م', 'meter': 'م', 'metre': 'م', 'lm': 'م.ط', 'rm': 'م.ط', 'rmt': 'م.ط', 'running meter': 'م.ط',
  'm2': 'م²', 'm²': 'م²', 'sqm': 'م²', 'sq.m': 'م²', 'sq m': 'م²', 'm3': 'م³', 'cum': 'م³', 'kg': 'كغ', 'ton': 'طن', 'tons': 'طن', 'mt': 'طن',
  'tr': 'طن تبريد', 'unit': 'وحدة', 'units': 'وحدة', 'day': 'يوم', 'days': 'يوم', 'hr': 'ساعة', 'hrs': 'ساعة', 'hour': 'ساعة',
  'ltr': 'لتر', 'l': 'لتر', 'roll': 'لفة', 'box': 'علبة', 'pair': 'زوج', 'point': 'نقطة', 'points': 'نقطة', 'pt': 'نقطة',
};
export function arUnit(s: unknown): string | null { if (hasArabic(s)) return String(s); const n = norm(s); return n ? (UNITS[n] ?? null) : null; }

// ── The quotation ──────────────────────────────────────────────────────────────────────────────
export type QuoteRow = {
  id?: string; quote_amount: number | null; lead_time?: string | null; validity?: string | null; warranty?: string | null;
  payment_terms?: string | null; scope?: string | null; conditions?: string | null; exclusions?: string | null; notes?: string | null;
};
export type InquiryRow = { id: string; category?: string | null; summary?: string | null; emirate?: string | null };
export type Item = { desc: string; qty: string; unit: string };

export function quoteRef(inquiryId: string, letter: string) { return 'QD-' + String(inquiryId || '').slice(0, 8).toUpperCase() + '-' + letter; }

/** The pdf_native body for ONE quote in ONE language. Pure: the caller fetches the rows. */
export function quoteDocument(args: { quote: QuoteRow; inquiry: InquiryRow; items: Item[]; letter: string; lang: Lang; maskNames?: string[]; date?: string; date_ar?: string }) {
  const { quote: q, inquiry: inq, items, letter, lang } = args;
  const ar = lang === 'ar';
  const names = args.maskNames || [];
  const ref = quoteRef(inq.id, letter);
  let verbatim = false;
  const tr = (v: unknown, f: (x: unknown) => string | null) => { if (v == null || String(v).trim() === '') return v as string; if (!ar) return String(v); const t = f(v); if (t) return t; if (hasLatin(v)) verbatim = true; return String(v); };
  const keep = (v: unknown) => { if (v == null || String(v).trim() === '') return v as string; if (ar && hasLatin(v) && !hasArabic(v)) verbatim = true; return String(v); };
  const quote = {
    supplier_label: letter,
    job_category: ar ? tr(inq.category, arCategory) : enCategory(inq.category), job_summary: keep(inq.summary), emirate: tr(inq.emirate, arEmirate),
    items: items.map((it) => ({ desc: keep(it.desc), qty: it.qty, unit: tr(it.unit, arUnit) })),
    scope: keep(q.scope), lead_time: tr(q.lead_time, arDuration), validity: tr(q.validity, arDuration), warranty: tr(q.warranty, arDuration),
    payment_terms: tr(q.payment_terms, arPayment), conditions: keep(q.conditions), exclusions: keep(q.exclusions), notes: keep(q.notes),
    total: q.quote_amount,
    source_note: '' as string,
  };
  if (ar && verbatim) quote.source_note = 'النصوص التي كتبها المورّد (الوصف والنطاق والشروط) معروضة كما وردت منه دون ترجمة، حفاظاً على دقة المواصفات. النسخة الإنجليزية متاحة أيضاً.';
  const body: Record<string, unknown> = {
    quote: maskDeep(quote, names, lang), lang, ref, name: ref + '-quotation-' + lang, title: ar ? 'عرض أسعار' : 'Quotation',
    options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref };
}

// ── The comparison report ───────────────────────────────────────────────────────────────────────
export function clipCell(s: unknown, n: number) { const t = String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); return t.length > n ? t.slice(0, n - 1) + '…' : t; }
const money = (v: unknown) => (v == null || v === '' || !(Number(v) > 0)) ? '—' : ('AED ' + Number(v).toLocaleString('en-AE', { maximumFractionDigits: 0 }));
// deno-lint-ignore no-explicit-any
const arrOf = (x: any) => Array.isArray(x) ? x : [];
/** "Supplier B" → "المورّد B" on an Arabic page; the letter stays the one on the customer's screen. */
export function labelFor(label: unknown, lang: Lang) { const l = String(label ?? ''); return lang === 'ar' ? l.replace(/^Supplier\b/, 'المورّد') : l; }

// THE SIDE-BY-SIDE TABLE, ONCE. compare_pdf renders it and compare_csv exports the same rows, so
// the spreadsheet can never disagree with the document.
// deno-lint-ignore no-explicit-any
export function compareTable(a: any, ar: boolean): { head: string[]; rows: string[][] } | null {
  const T = (en: string, arx: string) => (ar ? arx : en);
  const L: Lang = ar ? 'ar' : 'en';
  const qs = arrOf(a?.quotes);
  if (!qs.length) return null;
  const rows: string[][] = [];
  // deno-lint-ignore no-explicit-any
  const push = (label: string, get: (q: any) => string) => { const vals = qs.map(get); if (vals.some((v: string) => v && v !== '—')) rows.push([label, ...vals]); };
  const dur = (v: unknown, n: number) => { const c = clipCell(v, n); return (ar && c ? (arDuration(c) ?? c) : c) || '—'; };
  push(T('Price', 'السعر'), (q) => money(q.price));
  push(T('Lead time', 'مدة التنفيذ'), (q) => dur(q.lead_time, 60));
  push(T('Warranty', 'الضمان'), (q) => dur(q.warranty, 60));
  push(T('Payment terms', 'شروط الدفع'), (q) => { const c = clipCell(q.payment_terms, 60); return (ar && c ? (arPayment(c) ?? c) : c) || '—'; });
  push(T('Valid for', 'مدة الصلاحية'), (q) => dur(q.validity, 40));
  push(T('What you get', 'ما ستحصل عليه'), (q) => clipCell(q.getting, 240) || '—');
  push(T('Included', 'مشمول'), (q) => clipCell(arrOf(q.includes).join('; '), 240) || '—');
  push(T('Not included', 'غير مشمول'), (q) => clipCell(arrOf(q.excludes).join('; '), 200) || '—');
  push(T('Missing from your request', 'ناقص مما طلبت'), (q) => clipCell(arrOf(q.missing_from_request).join('; '), 200) || '—');
  push(T('Differs from your spec', 'اختلاف عن مواصفاتك'), (q) => clipCell(arrOf(q.spec_deviation).join('; '), 200) || '—');
  push(T('Track record', 'سجل الأداء'), (q) => clipCell(q.track_record_note, 180) || '—');
  push(T('Watch out', 'تنبيهات'), (q) => clipCell(arrOf(q.flags).join('; '), 200) || '—');
  // deno-lint-ignore no-explicit-any
  return { head: [T('Compare', 'المقارنة'), ...qs.map((q: any) => clipCell(labelFor(q.label, L), 20))], rows };
}
/** RFC 4180 cells, plus a leading apostrophe on anything a spreadsheet would run as a formula. */
export function toCsv(head: string[], rows: string[][]): string {
  const cell = (v: unknown) => { let s = String(v ?? ''); if (/^[=+\-@]/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  // The BOM is what makes Excel read the file as UTF-8; without it Arabic opens as mojibake.
  return '\ufeff' + [head, ...rows].map((r) => r.map(cell).join(',')).join('\r\n') + '\r\n';
}

/** The pdf_native body for the comparison report in ONE language. `a` is quote_compare's analysis. */
// deno-lint-ignore no-explicit-any
export function compareDocument(args: { analysis: any; inquiry: InquiryRow; lang: Lang; maskNames?: string[]; portalUrl?: string; date?: string; date_ar?: string }) {
  const { analysis: a, inquiry: inq, lang } = args;
  const ar = lang === 'ar';
  const T = (en: string, arx: string) => (ar ? arx : en);
  const qs = arrOf(a.quotes);
  const roster = arrOf(a.all_quotes);
  const received = roster.length || Number(a.total_quotes) || Number(a.considered) || qs.length;
  // deno-lint-ignore no-explicit-any
  const blocks: any[] = [];
  blocks.push({ t: 'kv', pairs: [
    [T('Request', 'الطلب'), clipCell(inq?.summary, 120) || '—'],
    [T('Category', 'الفئة'), (ar ? (arCategory(inq?.category) ?? clipCell(inq?.category, 40)) : enCategory(clipCell(inq?.category, 40))) || '—'],
    [T('Emirate', 'الإمارة'), (ar ? (arEmirate(inq?.emirate) ?? clipCell(inq?.emirate, 40)) : clipCell(inq?.emirate, 40)) || '—'],
    [T('Quotes received', 'العروض المستلمة'), String(received)],
    [T('Compared in detail', 'قورنت بالتفصيل'), T(`${qs.length} of ${received}`, `${qs.length} من ${received}`)],
  ] });
  if (a.bottom_line) { blocks.push({ t: 'h2', text: T('Bottom line', 'الخلاصة') }); blocks.push({ t: 'p', text: String(a.bottom_line) }); }
  if (a.overview) blocks.push({ t: 'p', text: String(a.overview) });
  if (a.shortlist_reason) blocks.push({ t: 'note', text: String(a.shortlist_reason) });
  if (arrOf(a.top3).length) {
    blocks.push({ t: 'h2', text: T('Recommended', 'التوصية') });
    blocks.push({ t: 'table', head: ['#', T('Supplier', 'المورّد'), T('Why', 'السبب'), T('Catch', 'الاعتبار')],
      // deno-lint-ignore no-explicit-any
      rows: arrOf(a.top3).map((r: any, i: number) => [String(r.rank ?? i + 1), clipCell(labelFor(r.label, lang), 24), clipCell(r.why, 220), clipCell(r.tradeoff, 160) || '—']),
      widths: [0.06, 0.16, 0.46, 0.32] });
  }
  const side = compareTable(a, ar);
  if (side) {
    blocks.push({ t: 'h2', text: T('Side by side', 'مقارنة جنبًا إلى جنب') });
    const colW = 0.76 / Math.max(1, qs.length);
    blocks.push({ t: 'table', head: side.head, rows: side.rows, widths: [0.24, ...qs.map(() => colW)] });
  }
  if (arrOf(a.line_findings).length) {
    blocks.push({ t: 'h2', text: T('Line by line', 'بندًا بندًا') });
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Finding', 'الملاحظة')],
      // deno-lint-ignore no-explicit-any
      rows: arrOf(a.line_findings).map((f: any) => [clipCell(f.item, 60), clipCell(f.finding, 300)]), widths: [0.28, 0.72] });
  }
  if (roster.length) {
    blocks.push({ t: 'h2', text: T(`All quotes received (${roster.length})`, `جميع العروض المستلمة (${roster.length})`) });
    // deno-lint-ignore no-explicit-any
    const status = (r: any) => r.status === 'shortlisted' ? T(`Shortlisted #${r.rank}`, `ضمن القائمة المختصرة #${r.rank}`)
      : r.status === 'held' ? T('On hold - incomplete', 'معلّق - غير مكتمل') : T('Received - open to reveal', 'مستلم - متاح للكشف');
    const dur = (v: unknown) => { const c = clipCell(v, 40); return (ar && c ? (arDuration(c) ?? c) : c) || '—'; };
    blocks.push({ t: 'table', head: [T('Supplier', 'المورّد'), T('Price', 'السعر'), T('Lead time', 'مدة التنفيذ'), T('Status', 'الحالة')],
      // deno-lint-ignore no-explicit-any
      rows: roster.map((r: any) => [labelFor(r.label, lang) + (r.expired ? T(' (expired)', ' (منتهي الصلاحية)') : ''), money(r.price), dur(r.lead_time), status(r)]),
      widths: [0.24, 0.22, 0.22, 0.32] });
    // deno-lint-ignore no-explicit-any
    for (const r of roster.filter((x: any) => x.status === 'held')) {
      const miss = typeof r.missing_mandatory === 'number' && r.missing_mandatory > 0 ? r.missing_mandatory : null;
      const why = r.price == null
        ? T('no price stated', 'لا يوجد سعر مذكور')
        : miss ? T(`${miss} mandatory detail(s) missing`, `${miss} من التفاصيل الإلزامية ناقصة`) : T('failed our completeness check', 'لم يجتز فحص الاكتمال');
      blocks.push({ t: 'note', text: T(`${labelFor(r.label, lang)} is on hold: ${why}. It is not ranked until the supplier completes it.`,
        `${labelFor(r.label, lang)} معلّق: ${why}. لا يدخل الترتيب حتى يستكمله المورّد.`) });
    }
    blocks.push({ t: 'note', text: T('Every quote above stays open to you - the shortlist is advice, not a limit. Open your QuotesDone portal to view or reveal any of them.',
      'كل العروض أعلاه تبقى متاحة لك - القائمة المختصرة نصيحة وليست قيدًا. افتح بوابتك في QuotesDone لعرض أي منها أو كشفه.'), link: args.portalUrl });
  }
  if (a.best_value_reason) { blocks.push({ t: 'h2', text: T('Why that pick', 'سبب الاختيار') }); blocks.push({ t: 'p', text: String(a.best_value_reason) }); }
  if (arrOf(a.watch_outs).length) { blocks.push({ t: 'h2', text: T('Watch out', 'انتبه') }); for (const w of arrOf(a.watch_outs)) blocks.push({ t: 'li', text: String(w) }); }
  if (a.advice) { blocks.push({ t: 'h2', text: T('Advice', 'النصيحة') }); blocks.push({ t: 'p', text: String(a.advice) }); }
  blocks.push({ t: 'space', h: 6 });
  if (a.disclaimer) blocks.push({ t: 'note', text: String(a.disclaimer) });
  const ref = 'QD-' + String(inq?.id || '').slice(0, 8).toUpperCase() + '-CMP';
  // The analysis writes its sentences around the labels ("Supplier B scores highest…") and both the
  // rules and the model keep the label in English by design, so an Arabic page read "Supplier B هو
  // الأعلى نقاطاً". Every label in every sentence takes the Arabic word on the Arabic page.
  const masked = maskDeep(blocks, args.maskNames || [], lang);
  // deno-lint-ignore no-explicit-any
  const arLabels = (v: any): any => typeof v === 'string' ? v.replace(/\bSupplier ([A-Z]{1,2})\b/g, 'المورّد $1')
    : Array.isArray(v) ? v.map(arLabels) : (v && typeof v === 'object') ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, k === 'link' ? x : arLabels(x)])) : v;
  const body: Record<string, unknown> = {
    title: T('Quote comparison report', 'تقرير مقارنة العروض'), ref, name: ref + '-comparison-' + lang, lang,
    blocks: ar ? arLabels(masked) : masked, options: { letterhead: true },
  };
  if (args.date) body.date = args.date; if (args.date_ar) body.date_ar = args.date_ar;
  return { body, ref };
}

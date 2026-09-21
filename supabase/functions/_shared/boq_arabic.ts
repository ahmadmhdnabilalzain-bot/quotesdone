// BOQ ARABIC — the sales-engineer-prepared bill of quantities, readable in Arabic. Seat: sales_engineer.
//
// MEASURED (21 Sep 2026 supplier-portal audit, findings 26 and 27): with the UI in Arabic the job's
// BOQ stayed English — section headers "Partitions" / "Ceilings" and every line ("Suspended false
// ceiling, 600x600 mineral fibre tiles") — because drawing_boq writes English only and nothing
// derived an Arabic reading afterwards.
//
// NO MODEL (OpenRouter is on hold, and a translation that decides what a supplier prices must be
// reproducible). Two deterministic sources the estate already owns:
//   1. taxonomy_trade_service — every service's label_ar and the EN+AR aliases the sales engineer's
//      rewrite matches with (_shared/service_rewrite.ts servicesFromText, exact-or-none). A line that
//      NAMES a service ("false ceiling", "gypsum board partition") gets that service's Arabic label.
//   2. SECTION_AR — the short glossary of the section words drawing_boq and the fixtures emit
//      (Partitions, Ceilings, Flooring works, Internal walls, Fire alarm — …). A section the glossary
//      does not name falls back to the service labels its own words match.
//
// WHAT IT DOES NOT DO: it does not translate free text. A line's sizes, brands and finishes ("100mm
// metal stud, both faces") stay in the supplier's view as the English original UNDER the Arabic
// label, because a supplier prices the exact words the customer's drawing produced, and a guessed
// translation of "300mm drop, painted finish" is a wrong quotation waiting to happen. A line naming
// no service gets no description_ar and the UI shows the original with dir="auto".
import { servicesFromText, type ServiceTerm } from './service_rewrite.ts';

export type BoqLine = { section?: string | null; description?: string | null; section_ar?: string | null; description_ar?: string | null; [k: string]: unknown };

/** Section words → Arabic. Keys are matched as whole words, case-insensitively, in the section text. */
export const SECTION_AR: Array<[RegExp, string]> = [
  [/\bpartitions?\b|\bdrywall\b|\binternal walls?\b/i, 'القواطع والجدران الداخلية'],
  [/\bceilings?\b|\bbulkheads?\b/i, 'الأسقف'],
  [/\bflooring\b|\bfloors?\b|\btil(?:es|ing)\b/i, 'الأرضيات'],
  [/\bpaint(?:ing|s)?\b|\bfinishes\b/i, 'الدهانات والتشطيبات'],
  [/\bjoinery\b|\bcarpentry\b|\bwood(?:en|work)?\b/i, 'النجارة'],
  [/\bdoors?\b|\bwindows?\b/i, 'الأبواب والنوافذ'],
  [/\bglazing\b|\bglass\b|\bcurtain wall\b/i, 'الزجاج'],
  [/\bfire alarm\b/i, 'إنذار الحريق'],
  [/\bfire ?fighting\b|\bsprinklers?\b/i, 'مكافحة الحريق'],
  [/\belectrical\b|\blighting\b|\bpower\b|\bsockets?\b/i, 'الأعمال الكهربائية'],
  [/\bplumbing\b|\bsanitary\b|\bdrainage\b/i, 'السباكة والصرف'],
  [/\bhvac\b|\bair ?conditioning\b|\bductwork\b|\bventilation\b/i, 'التكييف والتهوية'],
  [/\bdevices?\b/i, 'الأجهزة'],
  [/\bcables?\b|\bwiring\b/i, 'الكابلات'],
  [/\bschedule\b/i, 'الجدول'],
  [/\bread from drawing text\b|\bdrawing\b/i, 'مقروء من المخطط'],
  [/\bfound by the second reading\b/i, 'وُجد في القراءة الثانية'],
  [/\bgeneral\b/i, 'عام'],
];

export function sectionArabic(section: string, vocab: ServiceTerm[]): string | null {
  const s = String(section || '').trim();
  if (!s) return null;
  if (/[؀-ۿ]/.test(s)) return s;                    // already Arabic
  for (const [re, ar] of SECTION_AR) if (re.test(s)) return ar;
  const labels = serviceLabelsAr(s, vocab);
  return labels.length ? labels.join(' + ') : null;
}

/** The Arabic labels of every service the text names, in vocabulary order, deduplicated. */
export function serviceLabelsAr(text: string, vocab: ServiceTerm[]): string[] {
  if (!vocab.length) return [];
  const keys = new Set(servicesFromText(String(text || ''), vocab));
  const out: string[] = [];
  for (const v of vocab) {
    const key = `${v.trade_code}.${v.code}`;
    if (keys.has(key) && v.label_ar && !out.includes(v.label_ar)) out.push(v.label_ar);
  }
  return out;
}

export function descriptionArabic(description: string, vocab: ServiceTerm[]): string | null {
  const d = String(description || '').trim();
  if (!d) return null;
  if (/[؀-ۿ]/.test(d)) return d;
  const labels = serviceLabelsAr(d, vocab);
  return labels.length ? labels.join(' + ') : null;
}

/** Every BOQ line carries section_ar / description_ar (null where nothing deterministic names it). Pure. */
export function boqWithArabic<T extends { boq?: unknown }>(boq: T, vocab: ServiceTerm[]): T {
  if (!boq || !Array.isArray((boq as { boq?: unknown }).boq)) return boq;
  const rows = ((boq as { boq: BoqLine[] }).boq).map((r) => (r && typeof r === 'object'
    ? { ...r, section_ar: sectionArabic(String(r.section || ''), vocab), description_ar: descriptionArabic(String(r.description || ''), vocab) }
    : r));
  return { ...boq, boq: rows };
}

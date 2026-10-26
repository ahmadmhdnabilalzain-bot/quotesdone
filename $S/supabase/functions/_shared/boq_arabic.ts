// BOQ ARABIC — the sales-engineer-prepared bill of quantities, readable in Arabic. Seat: sales_engineer.
//
// MEASURED (21 Sep 2026 supplier-portal audit, findings 26 and 27): with the UI in Arabic the job's
// BOQ stayed English — section headers "Partitions" / "Ceilings" and every line ("Suspended false
// ceiling, 600x600 mineral fibre tiles") — because drawing_boq writes English only and nothing
// derived an Arabic reading afterwards.
//
// 23 Sep 2026 (decision point documents.boq_arabic, founder_instruction 886-903: no word matching).
// Which heading a section IS used to be decided by a list of regexes over its words, and a line's Arabic
// label by the service aliases its words contained. Both were meaning decided by word matching. Now:
//   * SECTIONS is the glossary of headings we can print in Arabic — data, not patterns;
//   * which glossary heading a section text means is REASONED (reasoned_documents.ts sectionReading) and
//     remembered per section text in boq_section_reading, so a heading is reasoned once, not per read;
//   * a line's description is NOT labelled: the supplier prices the exact words the drawing produced,
//     so the portal shows the original (dir="auto") under the Arabic section heading. A line or heading
//     already written in Arabic is shown as written (a script fact, not a meaning).
// Under the model hold a heading with no remembered reading has section_ar null and the portal shows the
// original — never a guessed heading. The held question is replayed when the hold lifts and its answer
// is written to boq_section_reading by fn_reason_apply_documents__boq_arabic.

export type BoqLine = { section?: string | null; description?: string | null; section_ar?: string | null; description_ar?: string | null; [k: string]: unknown };

/** The headings we print in Arabic. `meaning` is what the reasoning is told the heading covers. */
export const SECTIONS: { id: string; meaning: string; ar: string }[] = [
  { id: 'partitions', meaning: 'partitions, drywall and internal walls', ar: 'القواطع والجدران الداخلية' },
  { id: 'ceilings', meaning: 'ceilings and bulkheads', ar: 'الأسقف' },
  { id: 'flooring', meaning: 'flooring and floor or wall tiling', ar: 'الأرضيات' },
  { id: 'painting', meaning: 'painting and finishes', ar: 'الدهانات والتشطيبات' },
  { id: 'joinery', meaning: 'joinery, carpentry and woodwork', ar: 'النجارة' },
  { id: 'doors_windows', meaning: 'doors and windows', ar: 'الأبواب والنوافذ' },
  { id: 'glazing', meaning: 'glazing, glass and curtain walls', ar: 'الزجاج' },
  { id: 'fire_alarm', meaning: 'fire alarm and detection', ar: 'إنذار الحريق' },
  { id: 'fire_fighting', meaning: 'fire fighting and sprinklers', ar: 'مكافحة الحريق' },
  { id: 'electrical', meaning: 'electrical works, lighting, power and sockets', ar: 'الأعمال الكهربائية' },
  { id: 'plumbing', meaning: 'plumbing, sanitary and drainage', ar: 'السباكة والصرف' },
  { id: 'hvac', meaning: 'HVAC, air conditioning, ductwork and ventilation', ar: 'التكييف والتهوية' },
  { id: 'devices', meaning: 'devices or equipment counted from a drawing', ar: 'الأجهزة' },
  { id: 'cables', meaning: 'cables and wiring', ar: 'الكابلات' },
  { id: 'schedule', meaning: 'a schedule read from a drawing', ar: 'الجدول' },
  { id: 'from_drawing', meaning: 'items read from the drawing text', ar: 'مقروء من المخطط' },
  { id: 'second_reading', meaning: 'items found by the second reading of a drawing', ar: 'وُجد في القراءة الثانية' },
  { id: 'general', meaning: 'general items', ar: 'عام' },
];
const AR_OF = new Map(SECTIONS.map((s) => [s.id, s.ar]));

/** Readings are remembered per section text, trimmed and lower-cased (a key, not a match). */
export const sectionKey = (section: string) => String(section || '').trim().toLowerCase().slice(0, 200);
/** Arabic script already: shown as written. A script fact, like choosing a reply language. */
const arabicScript = (s: string) => /[؀-ۿ]/.test(s);

/** The section texts of a BOQ that need a reading (not Arabic already), deduplicated by key. */
export function sectionsToRead(boq: unknown): string[] {
  const rows = boq && Array.isArray((boq as { boq?: unknown }).boq) ? (boq as { boq: BoqLine[] }).boq : [];
  const out = new Map<string, string>();
  for (const r of rows) {
    const s = String(r?.section ?? '').trim();
    if (s && !arabicScript(s) && !out.has(sectionKey(s))) out.set(sectionKey(s), s);
  }
  return [...out.values()];
}

/** readings: section key -> SECTIONS id, or 'none' (reasoned to be no glossary heading). */
export function sectionArabic(section: string, readings: Record<string, string>): string | null {
  const s = String(section || '').trim();
  if (!s) return null;
  if (arabicScript(s)) return s;
  return AR_OF.get(readings[sectionKey(s)] ?? '') ?? null;
}

export function descriptionArabic(description: string): string | null {
  const d = String(description || '').trim();
  return d && arabicScript(d) ? d : null;
}

/** Every BOQ line carries section_ar / description_ar (null where no reading exists). Pure. */
export function boqWithArabic<T extends { boq?: unknown }>(boq: T, readings: Record<string, string>): T {
  if (!boq || !Array.isArray((boq as { boq?: unknown }).boq)) return boq;
  const rows = ((boq as { boq: BoqLine[] }).boq).map((r) => (r && typeof r === 'object'
    ? { ...r, section_ar: sectionArabic(String(r.section || ''), readings), description_ar: descriptionArabic(String(r.description || '')) }
    : r));
  return { ...boq, boq: rows };
}

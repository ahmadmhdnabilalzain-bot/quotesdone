// customer_documents/shape.ts — the row the customer sees, and the one-line answer, in EN and AR.
//
// Pure functions, no I/O, so customer_documents/shape.test.ts can prove them without a database.
//
// PROVENANCE IS TRANSLATED HERE. fn_customer_documents names where an expiry or a coverage came
// from as an internal key — 'leads.license_expiry', 'extracted.covers', 'quotes.warranty' — because
// that is useful to code. The portal printed one verbatim ("from leads.license expiry", audit
// finding 11, 21 Sep 2026). A customer is told the KIND of place instead: the document itself, the
// supplier's verified record on QuotesDone, or the quotation the supplier submitted.

export type Lang = 'en' | 'ar';

export type Doc = {
  id: number; kind: string; file_name: string | null; bucket: string; path: string;
  mime: string | null; status: string; created_at: string; source: string;
  ref_table: string | null; ref_id: string | null;
  supplier: string | null; supplier_revealed: boolean;
  expiry_date: string | null; expiry_source: string | null;
  covers: string | null; covers_source: string | null;
  summary: string | null; specifications: string[]; certifications: string[]; brands: string[];
  extracted_at: string | null; match_reason: string; score: number;
};

/** The customer-facing vocabulary for "where did this figure come from". */
export type SourceKind = 'document' | 'supplier_record' | 'quotation';

/** 'leads.license_expiry' -> 'supplier_record'; 'extracted.covers' -> 'document'; 'quotes.warranty' -> 'quotation'. */
export function sourceKind(internal: string | null | undefined): SourceKind | null {
  if (!internal) return null;
  if (internal.startsWith('leads.')) return 'supplier_record';
  if (internal.startsWith('quotes.')) return 'quotation';
  return 'document';
}

export const SOURCE_WORDS: Record<Lang, Record<SourceKind, string>> = {
  en: { document: 'the document', supplier_record: "the supplier's verified record", quotation: 'the quotation' },
  ar: { document: 'المستند', supplier_record: 'سجل المورّد الموثّق', quotation: 'عرض السعر' },
};

// The row the surface renders. Everything a customer is allowed to know about one document, and
// nothing that would name an unrevealed supplier or an internal column.
export function shape(d: Doc) {
  return {
    id: d.id,
    kind: d.kind,
    file_name: d.file_name,
    mime: d.mime,
    created_at: d.created_at,
    source: d.source,                       // 'inquiry' | 'quote' | 'supplier'
    ref_table: d.ref_table,
    ref_id: d.ref_id,
    supplier: d.supplier,                   // null until this quote's reveal fee is paid
    supplier_revealed: d.supplier_revealed,
    expiry_date: d.expiry_date,             // null when the document does not state one
    expiry_source: sourceKind(d.expiry_source),
    covers: d.covers,
    covers_source: sourceKind(d.covers_source),
    summary: d.summary,
    specifications: d.specifications || [],
    certifications: d.certifications || [],
    brands: d.brands || [],
    extracted: d.status === 'done' && !!d.extracted_at,
    extraction_status: d.status,
    match_reason: d.match_reason,
    score: d.score,
  };
}

export type Shaped = ReturnType<typeof shape>;

const ANSWER = {
  en: {
    from: (s: string) => `from ${s}`,
    unrevealed: 'from a supplier you have not revealed yet',
    own: 'your own upload',
    expires: (d: string) => `expires ${d}`,
    no_expiry: 'no expiry stated',
    covers: (c: string, src: string | null) => `covers ${c}` + (src ? ` (per ${src})` : ''),
    no_covers: 'no warranty or coverage stated',
  },
  ar: {
    from: (s: string) => `من ${s}`,
    unrevealed: 'من مورّد لم تكشف عنه بعد',
    own: 'مستند رفعته بنفسك',
    expires: (d: string) => `ينتهي في ${d}`,
    no_expiry: 'لم يُذكر تاريخ انتهاء',
    covers: (c: string, src: string | null) => `يغطي ${c}` + (src ? ` (بحسب ${src})` : ''),
    no_covers: 'لم يُذكر ضمان أو نطاق تغطية',
  },
};

// One line for the answer panel. It states only what the row actually carries — a missing expiry
// is reported as missing, never rounded to a year; a coverage names where it was read from.
export function answerLine(d: Shaped, lang: Lang = 'en'): string {
  const t = ANSWER[lang] || ANSWER.en;
  const words = SOURCE_WORDS[lang] || SOURCE_WORDS.en;
  const bits: string[] = [];
  bits.push(`${d.file_name || d.kind}`);
  bits.push(d.supplier ? t.from(d.supplier) : (d.source === 'quote' ? t.unrevealed : t.own));
  bits.push(d.expiry_date ? t.expires(d.expiry_date) : t.no_expiry);
  bits.push(d.covers ? t.covers(d.covers, d.covers_source ? words[d.covers_source] : null) : t.no_covers);
  return bits.join(' · ');
}

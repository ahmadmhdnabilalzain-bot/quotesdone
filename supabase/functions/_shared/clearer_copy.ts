// clearer_copy — what the uploader is told when neither code nor the vision model could read a file (ruling 1177).
// Its own file so a function that only ASKS (wa_inbound, supplier_portal) does not load the document readers.
export type Audience = 'supplier' | 'customer';

/** The clearer-copy request. Suppliers ALWAYS English; customers in their inquiry language ('ar' or 'en'). */
export function clearerCopyAsk(audience: Audience, lang: string | null | undefined, filename: string): string {
  const name = String(filename || 'your file').slice(0, 80);
  if (audience === 'customer' && String(lang || '').toLowerCase().startsWith('ar'))
    return `لم نتمكن من قراءة الملف «${name}» بوضوح. يُرجى إرسال نسخة أوضح (ملف PDF أو صورة واضحة للصفحة كاملة)، وسنقرؤها تلقائيًا فور وصولها.`;
  return `We could not read "${name}" clearly. Please send a clearer copy (a PDF, or a sharp photo of the whole page) and we will read it automatically as soon as it arrives.`;
}

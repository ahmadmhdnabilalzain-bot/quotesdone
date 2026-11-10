// clearer_copy — what the uploader is told when neither code nor the vision model could read a file (ruling 1177).
// Its own file so a function that only ASKS (wa_inbound, supplier_portal) does not load the document readers.
export type Audience = 'supplier' | 'customer';

/** The clearer-copy request. Suppliers ALWAYS English; customers in their inquiry language ('ar' or 'en'). */
// `noReader` (audit, 10 Nov 2026): NO model could read a photo or a scan just now (the model hold, a provider down). It
// is not a bad copy, so the supplier is not told it was unclear: he is asked for the original file, which code reads at
// once. Only a reading that came back too thin is "unclear".
export function clearerCopyAsk(audience: Audience, lang: string | null | undefined, filename: string, noReader = false): string {
  const name = String(filename || 'your file').slice(0, 80);
  if (noReader && audience === 'supplier')
    return `We could not read "${name}" automatically just now: a photo or a scanned page needs our document reader, which is not available at the moment. Please send the original PDF, Excel or Word file and we will read it straight away.`;
  if (audience === 'customer' && String(lang || '').toLowerCase().startsWith('ar'))
    return `لم نتمكن من قراءة الملف «${name}» بوضوح. يُرجى إرسال نسخة أوضح (ملف PDF أو صورة واضحة للصفحة كاملة)، وسنقرؤها تلقائيًا فور وصولها.`;
  return `We could not read "${name}" clearly. Please send a clearer copy (a PDF, or a sharp photo of the whole page) and we will read it automatically as soon as it arrives.`;
}


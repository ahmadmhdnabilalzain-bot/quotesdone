// what_was_understood — the customer is shown what the sales engineer understood from his file before anything is sent
// (13 Nov 2026, sales_engineer; founder ruling 1683: "give it to the sales engineer and check, first of all, how did he
// understand it? And what details were missing for him ... to actually make those drawings as a proper inquiry").
//
// The understanding is the model's (drawing_boq SYS: document_kind, summary, items, sufficiency); this only lays it out in
// the customer's two languages. A quotation is said to be a quotation, and what crosses to suppliers is said plainly: its
// items, no prices, no names, no reference numbers. The sufficiency verdict is said as the model gave it; the missing
// items are ASKED by the intake (inquiry_intake handle.ts, the drawing note), one or two at a time, never here.

// deno-lint-ignore no-explicit-any
type Reading = Record<string, any>;
export type Sufficiency = { verdict: 'sufficient' | 'not_yet'; missing: string[] };

/** The model's verdict, checked for shape only (the model decides; code checks the keys and drops what is malformed). */
export function sufficiencyOf(boq: Reading | null | undefined): Sufficiency | null {
  const s = boq && typeof boq === 'object' ? boq.sufficiency : null;
  if (!s || typeof s !== 'object') return null;
  const verdict = s.verdict === 'sufficient' ? 'sufficient' : s.verdict === 'not_yet' ? 'not_yet' : null;
  if (!verdict) return null;
  const missing = Array.isArray(s.missing) ? s.missing.map((m: unknown) => String(m ?? '').replace(/\s+/g, ' ').trim()).filter((m: string) => m.length > 2).slice(0, 8) : [];
  return { verdict, missing };
}

const line = (l: Reading) => {
  const d = String(l?.description || '').trim(); if (!d) return '';
  const q = l?.qty == null || l.qty === '' ? '' : ` — ${l.qty}${l.unit ? ' ' + String(l.unit) : ''}`;
  const make = l?.specification ? ` (${String(l.specification).trim()})` : '';
  return (d + make).slice(0, 140) + q;
};

/** What the customer reads under his upload: what the file IS, what was understood, and whether it is enough to quote. */
export function understoodMessage(boq: Reading | null | undefined, kind: string | null): { en: string; ar: string } | null {
  if (!boq || typeof boq !== 'object') return null;
  const items: Reading[] = Array.isArray(boq.boq) ? boq.boq : [];
  const shown = items.map(line).filter(Boolean).slice(0, 6);
  const more = items.length - shown.length;
  const summary = String(boq.summary || '').trim();
  const suf = sufficiencyOf(boq);
  const en: string[] = []; const ar: string[] = [];
  if (kind === 'quotation') {
    en.push(`This is a quotation from another supplier. I have rebuilt it on our own inquiry for the suppliers: ${items.length} item${items.length === 1 ? '' : 's'}, with no prices, no names and no reference numbers of the old supplier. Its pages are not shared.`);
    ar.push(`هذا عرض سعر من مورّد آخر. أعدتُ كتابته على نموذج طلبنا للمورّدين: ${items.length} من البنود، دون أي أسعار أو أسماء أو أرقام مرجعية للمورّد السابق. لا تُشارَك صفحاته.`);
  } else if (kind === 'priced') {
    en.push(`Your file carries prices. Its ${items.length} item${items.length === 1 ? '' : 's'} go to the suppliers with quantities and specifications; the rates in your document are not shared.`);
    ar.push(`يحتوي ملفك على أسعار. تصل بنوده (${items.length}) إلى المورّدين بالكميات والمواصفات؛ ولا تُشارَك الأسعار الواردة في مستندك.`);
  } else if (items.length) {
    en.push(`From your file I understood ${items.length} item${items.length === 1 ? '' : 's'}.`);
    ar.push(`فهمتُ من ملفك ${items.length} من البنود.`);
  }
  if (summary) { en.push(`What I understood: ${summary.slice(0, 300)}`); ar.push(`ما فهمته: ${summary.slice(0, 300)}`); }
  if (shown.length) { en.push(shown.map((s, i) => `${i + 1}. ${s}`).join('\n') + (more > 0 ? `\n…and ${more} more.` : '')); ar.push(shown.map((s, i) => `${i + 1}. ${s}`).join('\n') + (more > 0 ? `\n…و${more} بنود أخرى.` : '')); }
  if (suf?.verdict === 'sufficient') { en.push('It is enough for a supplier of this trade to quote from.'); ar.push('هذا كافٍ ليُسعّر منه مورّد هذا التخصص.'); }
  else if (suf?.verdict === 'not_yet') {
    en.push(`It is not yet enough to quote from${suf.missing.length ? ': a supplier would still need ' + suf.missing.slice(0, 4).join('; ') : ''}. I will ask you about these; you can also say "send it as it is", and the suppliers are told what is not known.`);
    ar.push(`هذا لا يكفي بعد للتسعير${suf.missing.length ? ': سيحتاج المورّد أيضًا إلى ' + suf.missing.slice(0, 4).join('؛ ') : ''}. سأسألك عنها؛ ويمكنك أيضًا أن تقول «أرسله كما هو»، فيُبلَّغ المورّدون بما هو غير معروف.`);
  }
  return en.length ? { en: en.join('\n\n'), ar: ar.join('\n\n') } : null;
}

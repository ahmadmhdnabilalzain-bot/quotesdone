// SUPPLIERS READ ENGLISH ONLY (founder, 28 Sep 2026; ledger 993) - applied to what a CUSTOMER writes that every
// bidder reads: an answer to a supplier's clarification question and a note added to a live request
// (founder_instruction 1026: shared anonymised with every bidder). Measured 5 Oct 2026: both paths stored the
// customer's text as typed and e-mailed it verbatim to every matched supplier, so an Arabic answer reached
// suppliers in Arabic, and send_outbox's Arabic hold only reads the row's lang, not its body.
// Translating needs the model, which is on hold, so the rule is kept in code: Arabic script is refused with a
// bilingual reason, and the customer writes it in English. Contact stripping runs first, so a refusal never
// echoes a number back.
const ARABIC = /[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]/; // U+FEFF (a pasted BOM) is not Arabic

export const hasArabic = (s: unknown): boolean => ARABIC.test(String(s ?? ''));

export const ENGLISH_ONLY = {
  error: 'english_only', code: 'english_only',
  message: 'Suppliers read requests in English. Please write this in English so every supplier quoting can read it.',
  message_ar: 'يقرأ الموردون الطلبات باللغة الإنجليزية. يُرجى كتابة هذا النص بالإنجليزية ليتمكن كل مورّد يسعّر طلبك من قراءته.',
};

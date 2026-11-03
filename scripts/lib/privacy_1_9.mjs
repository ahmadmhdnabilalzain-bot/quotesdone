// PRIVACY POLICY 1.9: THE ONE SENTENCE THAT SAYS WE MEASURE WHETHER AN INVITATION IS OPENED (marketing + ceo, 3 Nov 2026).
//
// 1.9 differs from 1.8 in exactly these edits, per language: the version label, the change notice, and one sentence in
// section 9 ("Invitations to businesses"). Privacy is unsigned (nobody accepts it), so a new version asks nobody to sign.
// Undoing EDITS_1_9 on the current text gives 1.8 byte for byte (the English registry body of 1.8 hashes to
// b16a707f..., the value scripts/sql/the_founders_mobile_leaves_the_current_legal_texts.sql pinned), which is how
// the 2 Nov checks keep reading 1.8 after 1.9 replaced it.
// Used by: scripts/checks/an_invitation_open_is_measured_on_a_tracked_share.test.mjs and
//          scripts/checks/the_founders_mobile_is_in_no_current_public_text_and_a_contact_only_version_asks_nobody_to_sign_again.test.mjs

// The address is kept as sha256(secret salt | address): pseudonymous, NOT irreversible (IPv4 has ~2^32 values, so whoever
// holds the salt can test a guess). The sentence says "made with a secret key" and never "one-way" or "cannot be reversed"
// (review of #1831, 3 Nov 2026).
export const OPEN_SENTENCE = {
  en: ' We measure whether these emails are opened: some carry a tiny image served from our own website, and when it loads we record the time, the description the email program sends and a coded form of the network address made with a secret key, never the address itself.',
  ar: ' ونقيس ما إذا كانت هذه الرسائل تُفتح، إذ يحمل بعضها صورة صغيرة جدًا يعرضها موقعنا الإلكتروني، وعند ظهورها نسجّل وقت الفتح ووصف برنامج البريد وصيغة مرمّزة لعنوان الشبكة نُعدّها بمفتاح سري، ولا نحتفظ بالعنوان نفسه.',
};

// [text in 1.8, text in 1.9] per language, applied in order.
export const EDITS_1_9 = {
  en: [
    ['Version 1.8 · Last updated 2 November 2026', 'Version 1.9 · Last updated 3 November 2026'],
    ['<strong>What changed in version 1.8 (2 November 2026):</strong> the contact details only (sections 1 and 11): the telephone number is +971 56 791 8605 and WhatsApp is +1 218 316 6814. Nothing else in this policy has changed from version 1.7 (19 October 2026).',
     '<strong>What changed in version 1.9 (3 November 2026):</strong> one sentence in section 9 (Invitations to businesses) says that we measure whether our invitation emails are opened, and how. Nothing else in this policy has changed from version 1.8 (2 November 2026).'],
    [' We use this data for nothing else and we do not sell it.', OPEN_SENTENCE.en + ' We use this data for nothing else and we do not sell it.'],
  ],
  ar: [
    ['الإصدار 1.8 · آخر تحديث 2 نوفمبر 2026', 'الإصدار 1.9 · آخر تحديث 3 نوفمبر 2026'],
    ['<strong>ما الذي تغيّر في الإصدار 1.8 (2 نوفمبر 2026):</strong> بيانات التواصل فقط (البندان 1 و11)، فرقم الهاتف هو +971 56 791 8605 ورقم واتساب هو +1 218 316 6814. ولم يتغيّر أي شيء آخر في هذه السياسة عن الإصدار 1.7 (19 أكتوبر 2026).',
     '<strong>ما الذي تغيّر في الإصدار 1.9 (3 نوفمبر 2026):</strong> أُضيفت إلى البند 9 (دعوة الشركات) جملة واحدة تبيّن أننا نقيس ما إذا كانت رسائل الدعوة تُفتح، وكيف نقيس ذلك. ولم يتغيّر أي شيء آخر في هذه السياسة عن الإصدار 1.8 (2 نوفمبر 2026).'],
    [' ولا نستخدم هذه البيانات في أي غرض آخر ولا نبيعها.', OPEN_SENTENCE.ar + ' ولا نستخدم هذه البيانات في أي غرض آخر ولا نبيعها.'],
  ],
};

const once = (t, from, to) => {
  const n = t.split(from).length - 1;
  if (n !== 1) throw new Error(`expected exactly one "${from.slice(0, 50)}", found ${n}`);
  return t.replace(from, () => to);
};
/** 1.8 -> 1.9. */
export const toPrivacy19 = (html, lang) => EDITS_1_9[lang].reduce((t, [a, b]) => once(t, a, b), html);
/** 1.9 -> 1.8: the current text with the 3 Nov edits undone, in reverse order. */
export const privacyAt18 = (html, lang) => [...EDITS_1_9[lang]].reverse().reduce((t, [a, b]) => once(t, b, a), html);
/** The registry body: the English page's <div class="body"> content (the_signed_legal_registry_follows_the_14_september_texts.sql). */
export const registryBody = (html) => {
  const s = '<div class="body">';
  const i = html.indexOf(s);
  const j = html.indexOf('</div>\n<div class="note">');
  if (i < 0 || j < i) throw new Error('no <div class="body"> ... note');
  return html.slice(i + s.length, j);
};

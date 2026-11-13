// scripts/e2e/journey_proof/anonymity.mjs — the dossier's ANONYMITY CHECK, as a pure function. Seat: customer_support.
//
// The founder, 13 Nov 2026 (ledger 1683): "anonymity is the most important thing in this platform". Ledger 1684: the
// journeys must PROVE it, not report a test result. So every identifying string that went IN on one side (the customer's
// name, phone, e-mail, area, villa number, his previous supplier's name, the consultant on his drawing; on the other side
// the supplier's name, address, phone, e-mail, TRN, bank, salesperson) is looked for in EVERYTHING the other party
// received before the reveal: the text of each PDF, its properties (title, author, subject, keywords, creator), the
// screen's text, each composed e-mail and WhatsApp, and every file name. Each hit is a LEAK, printed in plain words.
//
// How a value is looked for (so a reader of the dossier knows what "not found" means):
//   name / text   case and accents ignored, any run of spaces or punctuation counts as one space, whole words only
//                 ("Haddad" does not hit "Haddadi"); Arabic letters are compared as written.
//   phone         the last nine digits, found inside any run of digits written with spaces, dashes, dots, brackets or
//                 a plus, in Western or Arabic-Indic digits ("050-000-0413", "+971 50 000 0413", "٠٥٠ ٠٠٠ ٠٤١٣").
//   email         the whole address, case ignored; its domain is a separate value when the scenario lists it.
//   number        a code (TRN, licence, plot, Makani): its digits, inside any digit run, separators ignored.
// What it cannot see, said in the dossier beside the result: text drawn as a picture (a scanned page, a logo, a stamp)
// is not read by this check; the picture is shown in the dossier for the founder's own eyes.

const ARABIC_DIGITS = { '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4', '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9' };
const westernDigits = (s) => String(s ?? '').replace(/[٠-٩۰-۹]/g, (c) => ARABIC_DIGITS[c]);

/** Lower case, accents removed, every run of non-letters/non-digits one space, padded so " word " is a whole-word test. */
export function normText(s) {
  return ' ' + westernDigits(s).normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^\p{L}\p{N}@.]+/gu, ' ').replace(/(\s)\.|\.(\s)/g, '$1$2').replace(/\s+/g, ' ').trim() + ' ';
}

/** Every run of digits written with the separators a phone or a code uses, as its digits alone. */
export function digitRuns(s) {
  const out = [];
  for (const m of westernDigits(s).matchAll(/[+(]?\d[\d\s().\-/]*\d|\d/g)) out.push(m[0].replace(/\D/g, ''));
  return out;
}

/**
 * The values to look for. `items` is [{ label, value, kind }] with kind 'name' | 'text' | 'phone' | 'email' | 'number'.
 * A phone keeps its last nine digits (the UAE national number without the trunk 0); a number keeps all its digits and
 * must have at least five (a two-digit "15" would hit every price, so a villa number is given as text: "Villa 15").
 */
export function needles(items) {
  const out = [];
  for (const it of items || []) {
    const value = String(it?.value ?? '').trim();
    if (!value) continue;
    const kind = it.kind || 'text';
    if (kind === 'phone') { const d = value.replace(/\D/g, '').replace(/^.*?(\d{9})$/, '$1'); if (d.length >= 7) out.push({ ...it, kind, value, probe: d }); }
    else if (kind === 'number') { const d = westernDigits(value).replace(/\D/g, ''); if (d.length >= 5) out.push({ ...it, kind, value, probe: d }); }
    else if (kind === 'email') out.push({ ...it, kind, value, probe: value.toLowerCase() });
    else { const n = normText(value).trim(); if (n.length >= 3) out.push({ ...it, kind: kind === 'name' ? 'name' : 'text', value, probe: ' ' + n + ' ' }); }
  }
  return out;
}

const snippetAround = (text, idx, len) => {
  const t = String(text); const a = Math.max(0, idx - 40), b = Math.min(t.length, idx + len + 40);
  return (a > 0 ? '…' : '') + t.slice(a, b).replace(/\s+/g, ' ').trim() + (b < t.length ? '…' : '');
};

/** Where in `text` the needle is, or -1, with a short piece of the surrounding text for the dossier. */
export function find(needle, text) {
  const t = String(text ?? '');
  if (!t) return null;
  if (needle.kind === 'phone' || needle.kind === 'number') {
    for (const m of westernDigits(t).matchAll(/[+(]?\d[\d\s().\-/]*\d/g)) {
      if (m[0].replace(/\D/g, '').includes(needle.probe)) return { snippet: snippetAround(t, m.index, m[0].length) };
    }
    return null;
  }
  if (needle.kind === 'email') {
    const i = t.toLowerCase().indexOf(needle.probe);
    return i >= 0 ? { snippet: snippetAround(t, i, needle.probe.length) } : null;
  }
  const n = normText(t);
  const i = n.indexOf(needle.probe);
  if (i < 0) return null;
  // the snippet comes from the original text: locate the first word of the value there, case-insensitively
  const whole = t.toLowerCase().indexOf(String(needle.value).toLowerCase());
  const first = needle.probe.trim().split(' ')[0];
  const j = whole >= 0 ? whole : t.toLowerCase().indexOf(first);
  return { snippet: j >= 0 ? snippetAround(t, j, needle.probe.trim().length) : needle.value };
}

/**
 * scan(items, surfaces) -> one row per identifying value: where it was found, or found nowhere.
 * surfaces: [{ where: 'the inquiry PDF (text)', kind: 'pdf_text' | 'pdf_props' | 'screen' | 'message' | 'file_name' | 'data', text }]
 * A surface with `unreadable: true` (a picture-only page) is listed as not checked, never as clean.
 */
export function scan(items, surfaces) {
  const ns = needles(items);
  const readable = (surfaces || []).filter((s) => !s.unreadable);
  const rows = ns.map((n) => {
    const hits = [];
    for (const s of readable) { const f = find(n, s.text); if (f) hits.push({ where: s.where, kind: s.kind, snippet: f.snippet }); }
    return { label: n.label, value: n.value, kind: n.kind, leak: hits.length > 0, hits };
  });
  const skipped = (items || []).filter((it) => !ns.some((n) => n.label === it.label && n.value === String(it.value ?? '').trim())).map((it) => it.label);
  return {
    rows, leaks: rows.filter((r) => r.leak).length, checked: readable.map((s) => s.where),
    not_checked: (surfaces || []).filter((s) => s.unreadable).map((s) => `${s.where}${s.why ? ': ' + s.why : ''}`),
    too_short_to_check: skipped,
  };
}

/** The plain words the dossier prints for one row. */
export function leakSentence(row, receiver) {
  if (!row.leak) return `${row.label} ("${row.value}"): not found in anything the ${receiver} received.`;
  return `LEAK: ${row.label} ("${row.value}") reached the ${receiver} in ${row.hits.map((h) => h.where).join('; ')}. ` +
    `It reads: ${row.hits[0].snippet}`;
}

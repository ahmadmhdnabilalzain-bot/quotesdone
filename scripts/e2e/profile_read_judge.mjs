// scripts/e2e/profile_read_judge.mjs — IS WHAT THE SERVICES TAB SHOWS TRUE OF THE FILE THE SUPPLIER UPLOADED?
// Assigned: sales_engineer. 2 Nov 2026, founder ledger 1469 ("the sales agent summarises an uploaded company profile,
// gives keywords of services, the supplier confirms"). Until now the only test asked whether the section SHOWS.
//
// Pure functions, no I/O, so a known-bad control can prove each check really fails
// (scripts/checks/supplier_profile_read_judge.test.mjs) and the live walk can run the same controls against its own data.
//
//   truth: what the file says, written by the corpus, never read back from the product
//     read      'text'        a text layer states the offer: every stated trade must be shown, nothing else
//               'none'        a text profile that states no service: the tab must say it found none, show no keyword
//               'picture'     a scan or photo that states services (ledger 1442): read by the licence's model, so every stated trade is shown
//               'unreadable'  blank or corrupt: it must say it could not read it (a corrupt file: that it is damaged), never "found no service", never a keyword
//     stated    trade codes the file offers (the exact-trade-or-none truth: a nearest trade is a defect)
//     fileText  every line the file prints, for "is this summary line really in the file"
//   view: what the tab shows, read off the screen
//     state     'hits' | 'none' | 'scan' | 'reading' | 'missing'   (from the copy the tab prints)
//     keywords  badge texts; lines  the quoted summary lines; arabicOutside / arabicQuotes  Arabic the supplier is shown
//   labelOf: trade code -> the English label the tab prints for it
export const ARABIC = /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/;
export const norm = (s) => String(s ?? '').normalize('NFKC').toLowerCase().replace(/[….]+$/u, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

// The state the tab is in, from the sentence it prints (servicesCopy.ts VERIFY_COPY). One place, so a copy change fails here loudly.
export function stateOfNotice(text) {
  const t = String(text ?? '');
  if (/still reading your company profile/i.test(t)) return 'reading';
  if (/still reading your documents to understand/i.test(t)) return 'pending';
  if (/is a scan or photo that we could not read/i.test(t)) return 'scan';
  if (/company profile file is damaged/i.test(t)) return 'damaged';
  if (/We could not read your company profile/i.test(t)) return 'failed';
  if (/found no service we could match/i.test(t)) return 'none';
  if (/No company profile has been read yet/i.test(t)) return 'missing';
  return 'hits';
}

// 'picture' = a scan or photo of a profile that states services: since ledger 1442 it is read by the model the licence uses, so it must show its trades.
const ALLOWED = { text: ['hits'], picture: ['hits'], none: ['none'], unreadable: ['scan', 'damaged', 'failed', 'missing'] };
// A picture's lines are the model's reading of print, so a stray character may differ; 80% of a line's words must be the file's words, in the file.
const lineIsInFile = (line, file, picture) => {
  const n = norm(line);
  if (file.includes(n)) return true;
  if (!picture || n.split(' ').length < 2) return false;
  const words = n.split(' '), fw = new Set(file.split(' '));
  return words.filter((w) => fw.has(w)).length / words.length >= 0.8;
};

/** Returns [{ name, ok, detail }]. Every check is named for the claim it protects. */
export function judgeView({ truth, view, labelOf }) {
  const out = [];
  const add = (name, ok, detail = '') => out.push({ name, ok: !!ok, detail });
  const statedLabels = (truth.stated || []).map(labelOf);
  const file = norm((truth.fileText || []).join(' '));
  const allowed = truth.mustBe || ALLOWED[truth.read];
  add(`the tab is in a state that is true of this file (${truth.read}: ${allowed.join(' or ')})`, allowed.includes(view.state), `shows "${view.state}"`);
  const invented = view.keywords.filter((k) => !statedLabels.includes(k));
  add('no keyword is invented: each one is a trade the file states', invented.length === 0, invented.length ? `not in the file: ${invented.join(', ')}` : `${view.keywords.length} shown`);
  if (truth.read === 'text' || truth.read === 'picture') {
    const missing = statedLabels.filter((k) => !view.keywords.includes(k));
    add('every trade the file states is shown as a keyword', missing.length === 0, missing.length ? `missing: ${missing.join(', ')}` : '');
  }
  // An Arabic-only profile's lines are Arabic and are not repeated to the supplier (English only), so the keywords stand alone.
  if (view.state === 'hits' && !truth.arabic) add('a summary line is shown with the keywords', view.lines.length > 0, `${view.lines.length} line(s)`);
  const foreign = view.lines.filter((l) => !lineIsInFile(l, file, truth.read === 'picture'));
  add('every summary line is a line the file prints (nothing written for it)', foreign.length === 0, foreign.length ? `not in the file: ${foreign.map((l) => `"${l}"`).join(' | ')}` : '');
  if (truth.read === 'none' || truth.read === 'unreadable') add('no keyword and no summary line is shown for a file that states no service or cannot be read', view.keywords.length === 0 && view.lines.length === 0, `${view.keywords.length} keyword(s), ${view.lines.length} line(s)`);
  add('English only: no Arabic outside the supplier\'s own quoted lines', !view.arabicOutside, view.arabicOutside || '');
  add('English only: no Arabic in the summary lines either', view.arabicQuotes.length === 0, view.arabicQuotes.map((l) => `"${l}"`).join(' | '));
  return out;
}

// 14 SEP 2026 — website audit, Arabic section. The long-form Arabic was machine-translated and the
// errors sat on the money words: a price quote rendered as a literary citation (58 uses of the
// citation noun, 6 of its participle for "the quoted amount"), the platform rendered as a
// securities-trading platform (1), posting a job rendered as posting an employment vacancy (12),
// and the noun "description" where the imperative "describe!" belongs (6 on the service pages).
// The fixed glossary is: price quote = عرض سعر / عروض أسعار, job = طلب or مشروع, platform = منصة /
// سوق, describe = صِف.
//
// This check fails when a banned rendering appears in any Arabic content: every string under an
// "ar" key in src/content/*.json (at any depth) and all of messages/ar.json. The banned words are
// built from char codes below so that this file — and any comment quoting it — never matches its
// own scan, and so a reader grepping the repository for the banned words finds content, not this.
//
// Anonymity is reported, not failed: the brand concept is بسرّية تامة and "anonymous supplier /
// customer" is مجهول الهوية; a bare occurrence of that participle without الهوية is counted so the
// owner of each file can see it, but homepage copy in messages/ar.json uses it in native idiom.
//
// Usage: node scripts/checks/arabic_glossary.mjs [file ...]   (default: every file above)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const w = (...c) => String.fromCharCode(...c);

// [label, pattern] — labels describe the rendering in English only.
export const BANNED = [
  ['citation noun used for a price quote', new RegExp(w(1575, 1602, 1578, 1576, 1575, 1587), 'g')],
  ['citation participle used for the quoted amount', new RegExp(w(1605, 1602, 1578, 1576, 1587), 'g')],
  ['securities-trading word used for the platform', new RegExp(w(1575, 1604, 1578, 1583, 1575, 1608, 1604), 'g')],
  ['employment-vacancy word used for a job', new RegExp(w(1608, 1592, 1610, 1601) + '|' + w(1608, 1592, 1575, 1574, 1601), 'g')],
  ['noun "description" where the imperative belongs', new RegExp(w(1608, 1589, 1601) + ' ' + w(1605, 1588, 1585, 1608, 1593) + '|' + w(1608, 1589, 1601) + ' ' + w(1591, 1604, 1576), 'g')],
];
const MAJHUL = w(1605, 1580, 1607, 1608, 1604);
const HAWIYA = w(1575, 1604, 1607, 1608, 1610, 1577);
const BARE_ANON = new RegExp(MAJHUL + '[' + w(1575, 1577, 1610, 1608) + ']*' + '(?![' + w(1575, 1577, 1610, 1608, 1606) + ']*\\s+' + HAWIYA + ')', 'g');

function arabicStrings(node, underAr, out) {
  if (typeof node === 'string') { if (underAr) out.push(node); return out; }
  if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) arabicStrings(v, underAr || k === 'ar', out);
  }
  return out;
}

export function scanFile(rel) {
  const data = JSON.parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
  const text = arabicStrings(data, rel === 'messages/ar.json', []).join('\n');
  const hits = {};
  for (const [label, re] of BANNED) { const n = (text.match(re) || []).length; if (n) hits[label] = n; }
  return { hits, bareAnon: (text.match(BARE_ANON) || []).length };
}

function defaultFiles() {
  const dir = path.join(ROOT, 'src/content');
  return fs.readdirSync(dir).filter((f) => f.endsWith('.json')).map((f) => 'src/content/' + f).concat('messages/ar.json');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2).length ? process.argv.slice(2) : defaultFiles();
  let failed = 0;
  for (const f of files) {
    const { hits, bareAnon } = scanFile(f);
    const n = Object.values(hits).reduce((a, b) => a + b, 0);
    failed += n;
    console.log(`${n ? 'FAIL' : 'ok  '} ${f}${n ? ' ' + JSON.stringify(hits) : ''}${bareAnon ? `  (report: ${bareAnon} bare anonymity participle(s) without the identity noun)` : ''}`);
  }
  if (failed) { console.error(`arabic_glossary: ${failed} banned rendering(s). Use the fixed glossary in the header of this file.`); process.exit(1); }
}

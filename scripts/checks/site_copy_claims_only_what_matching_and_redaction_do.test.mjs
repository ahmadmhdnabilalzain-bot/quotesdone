// SITE COPY CLAIMS ONLY WHAT MATCHING AND REDACTION DO — independent content review of PR #870,
// 23 Sep 2026 (customer_support).
//
// The live /supplier page, the homepage and /how-it-works made two promises the product does not keep:
//
//   1. "Matched to the trade your licence covers." Matching (fn_match_capability) filters on the
//      trades and services the supplier ticks and confirms on his profile, the approvals certain
//      trades require, and verified-and-approved status. Nothing compares the licence activity with
//      the trades (fn_check_licence_activity is not in production). Founder rulings 857/862: a
//      service counts only when the supplier ticked it himself.
//   2. "Suppliers see the drawings with identity removed" / "drawings are automatically redacted".
//      Drawing redaction needs the model behind drawing_redact, which is held; a page not confirmed
//      clean is not shared at all. What IS true: suppliers see the scope and the quantities with
//      personal details removed, and the customer's name reaches them only when they are chosen.
//
// This check fails if either claim, in English or Arabic, comes back on a site surface. When the
// licence-activity comparison or unattended redaction ships, retire the matching pattern here in the
// same PR that ships it.
//
//   node --test scripts/checks/site_copy_claims_only_what_matching_and_redaction_do.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SURFACES = ['messages', 'src/app', 'src/components', 'src/content'];

// Arabic written as \u escapes so this file cannot match its own patterns if scripts/ is ever scanned.
const CLAIMS = [
  ['EN: matched on the licence', /trades? your licen[cs]e covers|jobs your licen[cs]e covers|licen[cs]ed for (your|that) trade|your licensed trade|licensed matching|Licensed suppliers are invited/i],
  ['EN: suppliers see redacted drawings', /drawings? with (identity|personal details) removed|from the drawings before any supplier|drawings (are|is) automatically redacted|drawings are automatically redacted|automatically redacts identifying details/i],
  // "covered by your licence", "your licensed activity", "licensed for your activity",
  // "licensed suppliers are invited", "licensed for this activity", "licensed matching"
  ['AR: matched on the licence', new RegExp([
    'تغطي(ه|ها) رخصت',
    'نشاطك المرخّ?ص',
    'المرخّ?صين لنشاط',
    // "licensed suppliers" alone is true (the licence is checked); only "are invited" / "for this trade" is the claim
    'يُ?دعى الموردون المرخّ?صون',
    'المرخّ?صون لهذا النشاط',
    'المطابقة المرخّ?صة',
  ].join('|'))],
  // "and the drawings after removing", "and from the drawings before", "identifying details from the
  // drawings", "the drawings are masked"
  ['AR: suppliers see redacted drawings', new RegExp([
    'والمخططات بعد حذف',
    'ومن المخططات قبل',
    'التعريفية من الرسومات',
    'تُ?حجب الرسومات',
    'تلقائيً?ا بحجب التفاصيل',
  ].join('|'))],
];

function* files(dir) {
  for (const e of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    const rel = path.join(dir, e.name);
    if (e.isDirectory()) yield* files(rel);
    else if (/\.(json|tsx?|mdx?)$/.test(e.name) && !/\.test\./.test(e.name)) yield rel;
  }
}

export function findings() {
  const out = [];
  for (const dir of SURFACES) for (const f of files(dir)) {
    fs.readFileSync(path.join(ROOT, f), 'utf8').split('\n').forEach((line, i) => {
      for (const [name, re] of CLAIMS) {
        const m = line.match(re);
        if (m) out.push(`${f.replace(/\\/g, '/')}:${i + 1} ${name}: "${m[0]}"`);
      }
    });
  }
  return out;
}

test('no site surface claims licence-based matching or redacted drawings for suppliers', () => {
  const f = findings();
  assert.equal(f.length, 0, `${f.length} false claim(s) on the site:\n${f.join('\n')}`);
});

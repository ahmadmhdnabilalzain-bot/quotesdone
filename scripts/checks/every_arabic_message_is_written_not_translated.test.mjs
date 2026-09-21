// EVERY ARABIC MESSAGE IS WRITTEN, NOT TRANSLATED — founder instruction 586, 21 Sep 2026:
// "the Arabic email feels like a pure translation. It should feel much more professional".
//
// 22 Sep 2026 (customer_support). The invitation and the day-2/day-6 registration reminders had
// already been rewritten in native Gulf business Arabic; everything else the company sends or shows
// had not. Every Arabic line on the customer- and supplier-facing surfaces below was read and either
// kept or rewritten, and this check keeps it that way in two ways:
//
//   1. ARTEFACTS. A line on a surface below fails if it carries one of the marks machine or literal
//      translation leaves in Arabic. Each was found in this estate before the rewrite:
//        - the possessive calque of "your X" (definite noun + the "belonging to you" phrase) where
//          Arabic attaches the pronoun to the noun
//        - the imperative "do" calque (the verb "do" + the preposition bi-) for "click / sign in / upload"
//        - "will be done" / "has been done" built with the future particle or the emphatic past
//          particle in front of the passive helper verb
//        - the agent-of-the-passive calque for English "by"
//        - the "please note that" calque
//        - the emphatic "we" in front of a first-person verb, an English subject habit
//        - a Latin comma, semicolon or question mark typed straight after an Arabic letter
//        - the brand transliterated into Arabic letters (the brand stays Latin: logo and site)
//      The patterns are written as \u escapes so this file, and any comment quoting it, can never
//      match its own scan (a check that greps source once failed on the comment explaining it).
//
//   2. REVIEWED LIST. Every Arabic line on these surfaces has a 12-hex SHA-1 of its trimmed text in
//      scripts/checks/arabic_reviewed_strings.json. A new or edited Arabic line that is not in the
//      list fails: read it against the register below, then record it with
//        node scripts/checks/every_arabic_message_is_written_not_translated.test.mjs --write
//      The PR diff of the JSON is the reviewer's evidence that someone looked.
//
// THE REGISTER. Formal letters: السادة/ ... المحترمين، تحية طيبة وبعد، ... وتفضلوا بقبول فائق الاحترام
// والتقدير — the formal plural (كم) throughout. UI and short notices: concise, polite, the formal
// plural or the imperative without a pronoun. "QuotesDone" stays in Latin letters.
//
// SURFACES (what the company sends or shows a customer or supplier): messages/ar.json; the portal and
// site components under src/components and src/app; the edge functions that compose mail, WhatsApp,
// chat replies and API notices; and every scripts/sql file appended to MANIFEST.txt after this
// check's own SQL file. NOT covered, and why:
//   - src/content/*.json — the website's long-form content, signed off 14 Sep and gated by
//     arabic_glossary.mjs
//   - vocabulary and parsers (trade glossaries, aliases, rule packs, normalisers, OCR/sheet readers,
//     fixtures) — they match what people type, they are not messages
//   - the PDF documents (quote/charge/reveal/certificate/archive renderers) — owned by the document
//     template work and its own checks
//   - SQL files before the anchor — history; the live routines they define were rewritten through the
//     anchor file itself.
//
//   node --test scripts/checks/every_arabic_message_is_written_not_translated.test.mjs
//   node scripts/checks/every_arabic_message_is_written_not_translated.test.mjs --report
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const LIST = 'scripts/checks/arabic_reviewed_strings.json';
const ANCHOR = 'scripts/sql/every_arabic_message_is_written_not_translated.sql';

const AR = /[؀-ۿ]/;
const NOT_AR_BEFORE = '(?<![\\u0600-\\u06FF])';
export const ARTEFACTS = [
  ['possessive calque of "your X"', new RegExp('\\u0627\\u0644\\u062E\\u0627\\u0635\\u0629? \\u0628\\u0643')],
  ['imperative "do" calque', new RegExp(NOT_AR_BEFORE + '\\u0642\\u0645 \\u0628')],
  ['"will be done" calque', new RegExp('\\u0633\\u0648\\u0641 \\u064A\\u062A\\u0645')],
  ['"has been done" calque', new RegExp('\\u0644\\u0642\\u062F \\u062A\\u0645')],
  ['passive agent "by" calque', new RegExp('\\u0628\\u0648\\u0627\\u0633\\u0637\\u0629')],
  ['"please note that" calque', new RegExp('\\u064A\\u064F?\\u0631\\u062C\\u0649 \\u0645\\u0644\\u0627\\u062D\\u0638\\u0629')],
  ['emphatic "we" before a verb', new RegExp(NOT_AR_BEFORE + '\\u0646\\u062D\\u0646 \\u0646')],
  ['Latin punctuation after an Arabic letter', /[ء-يً-ْ][,;?]/],
  // The licensed Arabic trade name (followed by "for technology", DET 1633275) is a legal name in the
  // signed agreements, not a transliteration, and is exempt.
  ['brand transliterated into Arabic', new RegExp('\\u0643\\u0648\\u062A[\\u0633\\u0632] ?\\u062F\\u0646(?! \\u0644\\u0644\\u062A\\u0643\\u0646\\u0648\\u0644\\u0648\\u062C\\u064A\\u0627)')],
];

// Files on a surface above that are vocabulary, parsers, fixtures or PDF renderers.
const NOT_A_MESSAGE = [
  /^supabase\/functions\/_shared\/(trade_glossary_ar|trade_classify|trade_words|boq_arabic|anonymise|identity_numbers|bank_statement_parse|receipt_parse|catalogue_read|catalogue_model|service_meaning|service_rewrite|drawing_identity_text|pdf_measure|registered_locale|doc_template|quote_documents|supplier_charge_documents|reveal_fee_documents|supplier_charge|supplier_capability|project_budget|boq_open_lines)\.ts$/,
  /^supabase\/functions\/_shared\/(doc_read|rules|vendor)\//,
  /^supabase\/functions\/(pdf_native|drawing_boq|sanctions_screen|supplier_catalog_ingest|quote_extract|compliance_archive|conversation_archive)\//,
  /^supabase\/functions\/_shared\/line_specs\/(derive|compare|vat|workflow|options)\.ts$/,
  /^supabase\/functions\/supplier_api\/identity_scrub\.ts$/,
  /^supabase\/functions\/inquiry_intake\/classify\.ts$/,
  /^src\/lib\//,
  /\.json$/, // service_aliases, trade_aliases_ar, service_implications, fixtures (messages/ar.json is added explicitly)
  /fixtures?\./,
];

function walk(dir, out) {
  const abs = path.join(ROOT, dir);
  if (!fs.existsSync(abs)) return out;
  for (const e of fs.readdirSync(abs, { withFileTypes: true })) {
    const rel = dir + '/' + e.name;
    if (e.isDirectory()) { if (!['node_modules', '__tests__', 'vendor'].includes(e.name)) walk(rel, out); }
    else if (/\.(ts|tsx|mjs|js)$/.test(e.name) && !/\.(test|spec)\./.test(e.name)) out.push(rel);
  }
  return out;
}

function sqlAfterAnchor() {
  const lines = fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim());
  const at = lines.indexOf(ANCHOR);
  if (at < 0) return [];
  return lines.slice(at).filter((l) => l.endsWith('.sql') && !l.startsWith('#') && !l.startsWith('--'));
}

export function surfaces() {
  const code = [...walk('src/components', []), ...walk('src/app', []), ...walk('supabase/functions', [])]
    .filter((f) => !NOT_A_MESSAGE.some((re) => re.test(f)));
  return ['messages/ar.json', ...code, ...sqlAfterAnchor()].filter((f) => fs.existsSync(path.join(ROOT, f))).sort();
}

export const hashOf = (line) => crypto.createHash('sha1').update(line.trim()).digest('hex').slice(0, 12);

export function arabicLines(rel) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(/\r?\n/)
    // A comment is not a message: comments here quote the wording they replaced.
    .map((text, i) => ({ line: i + 1, text })).filter((l) => AR.test(l.text) && !/^\s*(\/\/|\/\*|\*|--)/.test(l.text));
}

export function artefactsIn(text) {
  return ARTEFACTS.filter(([, re]) => re.test(text)).map(([label]) => label);
}

function scan() {
  const files = surfaces();
  const reviewed = fs.existsSync(path.join(ROOT, LIST)) ? JSON.parse(fs.readFileSync(path.join(ROOT, LIST), 'utf8')) : {};
  const artefacts = []; const unreviewed = []; const current = {};
  for (const f of files) {
    const lines = arabicLines(f);
    if (!lines.length) continue;
    current[f] = [...new Set(lines.map((l) => hashOf(l.text)))].sort();
    const known = new Set(reviewed[f] || []);
    for (const l of lines) {
      for (const a of artefactsIn(l.text)) artefacts.push(`${f}:${l.line} ${a}: ${l.text.trim().slice(0, 120)}`);
      if (!known.has(hashOf(l.text))) unreviewed.push(`${f}:${l.line} ${l.text.trim().slice(0, 120)}`);
    }
  }
  return { files, artefacts, unreviewed, current };
}

const MAIN = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (MAIN && process.argv.includes('--write')) {
  const { current, artefacts } = scan();
  if (artefacts.length) { console.error(artefacts.join('\n')); console.error(`${artefacts.length} translation artefact(s); fix them before recording.`); process.exit(1); }
  fs.writeFileSync(path.join(ROOT, LIST), JSON.stringify(current, null, 1) + '\n');
  console.log(`recorded ${Object.values(current).reduce((n, h) => n + h.length, 0)} reviewed Arabic lines in ${Object.keys(current).length} files`);
} else if (MAIN && process.argv.includes('--report')) {
  const { files, artefacts, unreviewed, current } = scan();
  console.log(artefacts.join('\n'));
  console.log(`surfaces ${files.length}, files with Arabic ${Object.keys(current).length}, lines ${Object.values(current).reduce((n, h) => n + h.length, 0)}, artefacts ${artefacts.length}, unreviewed ${unreviewed.length}`);
} else {
  test('the artefact patterns catch what they name and pass native Arabic', () => {
    const cases = [
      ['طلب الخاص بك', 1], ['حسابكم', 0],
      [' قم بتسجيل الدخول', 1], ['سجّلوا الدخول', 0], ['يقمن', 0],
      ['سوف يتم إرسال', 1], ['سيُرسل', 0],
      ['لقد تم استلام', 1], ['استلمنا', 0],
      ['أُنشئ بواسطة المورد', 1],
      ['يرجى ملاحظة أن', 1], ['يُرجى ملاحظة أن', 1], ['يُرجى تحميل', 0],
      [' نحن نرجو', 1], ['نحنُ', 0],
      ['شكرًا,', 1], ['هل تريد?', 1], ['شكرًا،', 0], ["'نعم',", 0],
      ['كوتس دن', 1], ['QuotesDone', 0], ['كوتس دن للتكنولوجيا', 0],
    ];
    for (const [text, n] of cases) assert.equal(artefactsIn(text).length, n, text);
  });

  test('no customer- or supplier-facing Arabic line carries a translation artefact', () => {
    const { artefacts } = scan();
    assert.deepEqual(artefacts, [], `rewrite these natively (instruction 586):\n${artefacts.join('\n')}`);
  });

  test('every customer- or supplier-facing Arabic line has been reviewed', () => {
    const { unreviewed } = scan();
    assert.deepEqual(unreviewed, [], `read each line against the register in this file's header, then run\n  node scripts/checks/every_arabic_message_is_written_not_translated.test.mjs --write\n${unreviewed.slice(0, 40).join('\n')}${unreviewed.length > 40 ? `\n... and ${unreviewed.length - 40} more` : ''}`);
  });

  test('the SQL anchor is in MANIFEST, so new SQL files are scanned', () => {
    const m = fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8');
    assert.ok(m.split(/\r?\n/).map((l) => l.trim()).includes(ANCHOR), `${ANCHOR} must be a MANIFEST line`);
  });
}

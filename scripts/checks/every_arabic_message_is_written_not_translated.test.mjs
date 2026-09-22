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
//      The patterns are written as \u escapes so that reading them does not put the forbidden text
//      into this file (a check that greps source once failed on the comment explaining it). That is a
//      convenience, NOT an immunity, and the review of 22 Sep 2026 was right to say so: line 89 and
//      the fixtures below spell several shapes out literally, and what actually keeps this file out
//      of its own scan is that scripts/ is not a scanned surface. If scripts/ ever becomes one, the
//      fixtures must move to a data file first.
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
// chat replies and API notices; every scripts/sql file appended to MANIFEST.txt after this check's own
// SQL file; and — added 22 Sep 2026 after the documents-language audit found three live composers
// hiding behind the anchor — THE CANONICAL BODY OF EVERY ROUTINE THIS REPOSITORY DEFINES, wherever its
// file sits in the manifest (see canonicalRoutineBodies below). NOT covered, and why:
//   - src/content/*.json — the website's long-form content, signed off 14 Sep and gated by
//     arabic_glossary.mjs
//   - vocabulary and parsers (trade glossaries, aliases, rule packs, normalisers, OCR/sheet readers,
//     fixtures) — they match what people type, they are not messages
//   - the PDF documents (quote/reveal/payment/certificate/archive renderers) — owned by the document
//     template work and its own checks. The supplier charge documents ARE scanned (review of #818:
//     a day count there reached the supplier).
//   - SQL files before the anchor, EXCEPT the canonical routine bodies inside them. What is left is
//     history: data repair, a comment on a function, an insert whose ON CONFLICT DO NOTHING means the
//     file stopped owning the live value. A stored value that IS live and wrong is corrected by an
//     update in a new file (app_secrets.invite_body_ar, 22 Sep 2026), not by editing history.
//
//   node --test scripts/checks/every_arabic_message_is_written_not_translated.test.mjs
//   node scripts/checks/every_arabic_message_is_written_not_translated.test.mjs --report
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
  // 22 Sep 2026 (documents-language audit, DL-05). Two more shapes an English sentence leaves behind
  // when it is carried across word by word, both found in the live WhatsApp templates:
  //   - "X did the paying of" — the light verb "qāma" plus bi- + a definite verbal noun, in place of
  //     the plain verb (a customer PAID; Arabic says so with one verb).
  ['"did the doing" light-verb calque', new RegExp(NOT_AR_BEFORE + '\\u0642\\u0627\\u0645(?:\\u062A)?\\u064E? (?:[^ ]+ )?\\u0628\\u0640?\\u0627\\u0644')],
  //
  // A SECOND PATTERN WAS ASKED FOR AND IS NOT HERE, because it was measured before it was added: the
  // past built as "was done" plus a verbal noun. Written as the definite form it matched 60 lines of
  // this estate, and written as the bare form 31 — and reading them, they are not calques: "تم الحفظ"
  // (Saved), "تمت الترسية" (Awarded), "تم استلام دفعتك" (We have received your payment) are how an
  // Arabic UI label and an Arabic receipt read, and every one of them was read in the 21-22 Sep
  // passes. A pattern that condemns thirty correct lines to catch one is a check that gets weakened
  // later, so the one real instance — the WhatsApp template's "تم إيقاف استقبال الطلبات" — was
  // rewritten as the passive verb أُوقف by hand, and the two narrower shapes above (the emphatic
  // "لقد تم" and the future "سوف يتم") keep carrying this class.
  ['Latin punctuation after an Arabic letter', /[ء-يً-ْ][,;?]/],
  // The licensed Arabic trade name (followed by "for technology", DET 1633275) is a legal name in the
  // signed agreements, not a transliteration, and is exempt.
  ['brand transliterated into Arabic', new RegExp('\\u0643\\u0648\\u062A[\\u0633\\u0632] ?\\u062F\\u0646(?! \\u0644\\u0644\\u062A\\u0643\\u0646\\u0648\\u0644\\u0648\\u062C\\u064A\\u0627)')],
];

// Files on a surface above that are vocabulary, parsers, fixtures or PDF renderers.
const NOT_A_MESSAGE = [
  /^supabase\/functions\/_shared\/(trade_glossary_ar|trade_classify|trade_words|boq_arabic|anonymise|identity_numbers|bank_statement_parse|receipt_parse|catalogue_read|catalogue_model|service_meaning|service_rewrite|drawing_identity_text|pdf_measure|registered_locale|doc_template|quote_documents|reveal_fee_documents|supplier_payment_documents|supplier_charge|supplier_capability|project_budget|boq_open_lines)\.ts$/,
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

function manifest() {
  return fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim())
    .filter((l) => l.endsWith('.sql') && !l.startsWith('#') && !l.startsWith('--'));
}

function sqlAfterAnchor() {
  const lines = fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split(/\r?\n/).map((l) => l.trim());
  const at = lines.indexOf(ANCHOR);
  // Until the coordinator applies it, the anchor is pending (scripts/sql/pending/) and not yet a
  // MANIFEST line; it is scanned on its own until then.
  if (at < 0) return [ANCHOR];
  return lines.slice(at).filter((l) => l.endsWith('.sql') && !l.startsWith('#') && !l.startsWith('--'));
}

// THE FILE THAT DEFINES EACH LIVE ROUTINE, 22 Sep 2026 (documents-language audit, DL-04).
//
// Scanning only the SQL after the anchor left a hole this audit walked straight through: a routine
// that composes Arabic mail TODAY can be defined in a file written before the anchor, and its text was
// never read by this check. Three were — fn_seat_clock_compose, fn_supplier_registration_reminder_compose
// and fn_supplier_collaboration_incident — and each carried an artefact named above.
//
// So the scan now also covers, for every routine this repository defines, the BODY THAT DEFINES IT:
// in the LAST file in MANIFEST.txt carrying its `create or replace function` — the manifest's own
// winner rule, position decides — the lines from that statement to the close of its dollar-quoted
// body. The body, not the whole file, and that is the load-bearing part:
//   * a pre-anchor file defines a dozen routines; re-issuing ONE of them in a new file must remove
//     that one body from the old file's scan, or the corrected text and the old text both count;
//   * what surrounds a routine in those files is history — data repair, a comment on a function, an
//     insert whose ON CONFLICT DO NOTHING means the file no longer owns the live value. Those are not
//     messages this company sends today, and one of them (a fold description quoting Arabic letters
//     inside an English sentence) would fail the Latin-punctuation rule while being nobody's message.
export function canonicalRoutineBodies() {
  const last = new Map();   // routine -> { file, from, to } of the LAST definition in manifest order
  for (const f of manifest()) {
    const abs = path.join(ROOT, f);
    if (!fs.existsSync(abs)) continue;
    const lines = fs.readFileSync(abs, 'utf8').split(/\r?\n/);
    lines.forEach((text, i) => {
      const m = text.match(/create\s+or\s+replace\s+function\s+public\.(\w+)/i);
      if (!m) return;
      let end = i;
      while (end < lines.length && !/\$\w*\$\s*;/.test(lines[end])) end++;
      last.set(m[1].toLowerCase(), { file: f, from: i + 1, to: Math.min(end + 1, lines.length) });
    });
  }
  const byFile = new Map();
  for (const { file, from, to } of last.values()) {
    if (!byFile.has(file)) byFile.set(file, []);
    byFile.get(file).push([from, to]);
  }
  return byFile;   // file -> [[fromLine, toLine], ...], 1-based and inclusive
}

export function surfaces() {
  const code = [...walk('src/components', []), ...walk('src/app', []), ...walk('supabase/functions', [])]
    .filter((f) => !NOT_A_MESSAGE.some((re) => re.test(f)));
  return [...new Set(['messages/ar.json', ...code, ...sqlAfterAnchor()])]
    .filter((f) => fs.existsSync(path.join(ROOT, f))).sort();
}

// Every surface as {file, ranges}: ranges null means the whole file, otherwise the canonical routine
// bodies inside a file that is not itself a surface.
export function scanned() {
  const whole = surfaces();
  const out = whole.map((file) => ({ file, ranges: null }));
  for (const [file, ranges] of canonicalRoutineBodies()) {
    if (!whole.includes(file) && fs.existsSync(path.join(ROOT, file))) out.push({ file, ranges });
  }
  return out.sort((a, b) => a.file.localeCompare(b.file));
}

export const hashOf = (line) => crypto.createHash('sha1').update(line.trim()).digest('hex').slice(0, 12);

export function arabicLines(rel, ranges = null) {
  return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(/\r?\n/)
    // A comment is not a message: comments here quote the wording they replaced.
    .map((text, i) => ({ line: i + 1, text })).filter((l) => AR.test(l.text) && !/^\s*(\/\/|\/\*|\*|--)/.test(l.text))
    .filter((l) => !ranges || ranges.some(([from, to]) => l.line >= from && l.line <= to));
}

export function artefactsIn(text) {
  return ARTEFACTS.filter(([, re]) => re.test(text)).map(([label]) => label);
}

function scan() {
  const targets = scanned();
  const files = targets.map((t) => t.file);
  const reviewed = fs.existsSync(path.join(ROOT, LIST)) ? JSON.parse(fs.readFileSync(path.join(ROOT, LIST), 'utf8')) : {};
  const artefacts = []; const unreviewed = []; const current = {};
  for (const { file: f, ranges } of targets) {
    const lines = arabicLines(f, ranges);
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

  // Review of #818: "${n} days" in Arabic was printed with one fixed noun, wrong for 1, 2 and 3-10.
  // A variable count placed straight before the word for day(s) must go through arDays()
  // (src/lib/durationLabel.ts; supabase/functions/_shared/ar_days.ts at the edge; public.fn_ar_days in
  // SQL) — whether interpolated (`${n}`, `{n}`) or concatenated (`+ n + '...'`, `|| '...'`). Only an
  // Arabic LETTER after the word stops a match, so punctuation (، ؛ ؟ .) does not hide it. Working days
  // (the noun followed by "work") are fixed windows and exempt.
  const DAY_WORD = '(?:يوم(?:ًا|اً)?|أيام)(?![\\u0621-\\u064A])(?! عمل)';
  const DAY_COUNT_BY_HAND = new RegExp(`(?:(?:\\$\\{[^}]*\\}|\\{[a-z_]+\\}) ?|(?:\\+|\\|\\|) ?['"\`] ?)${DAY_WORD}`);
  // The three helpers themselves spell the forms out and are the one place allowed to.
  const HELPER_START = /export function arDays\(|function public\.fn_ar_days\(/;
  const HELPER_END = /^\}|^\$fn\$;/;
  test('the day-count pattern catches a hand-written count and passes the helper', () => {
    for (const s of ['`خلال ${d} يومًا`', "'{days} أيام'", '`خلال ${days} يومًا؛`', "' خلال ' + days + ' يومًا'", "|| ' يومًا). '", "`${n} يوم.`"]) assert.ok(DAY_COUNT_BY_HAND.test(s), s);
    for (const s of ['`خلال ${arDays(d)}`', "'{w} أيام عمل'", "'${n} يومان'", "|| ' يومان'"]) assert.ok(!DAY_COUNT_BY_HAND.test(s), s);
  });
  test('no Arabic template prints a day count without the helper', () => {
    const hits = [];
    // The same targets the artefact scan reads: whole surfaces, plus the canonical body of a routine
    // whose file is not itself a surface (22 Sep 2026, DL-04).
    for (const { file: f, ranges } of scanned()) {
      let inHelper = false;
      fs.readFileSync(path.join(ROOT, f), 'utf8').split(/\r?\n/).forEach((text, i) => {
        if (HELPER_START.test(text)) inHelper = true;
        else if (inHelper && HELPER_END.test(text)) { inHelper = false; return; }
        if (ranges && !ranges.some(([from, to]) => i + 1 >= from && i + 1 <= to)) return;
        if (!inHelper && AR.test(text) && !/^\s*(\/\/|\/\*|\*|--)/.test(text) && DAY_COUNT_BY_HAND.test(text)) hits.push(`${f}:${i + 1} ${text.trim().slice(0, 120)}`);
      });
    }
    assert.deepEqual(hits, [], 'use arDays() (src/lib/durationLabel.ts, supabase/functions/_shared/ar_days.ts) or public.fn_ar_days()');
  });
  test('the three day-count helpers agree', async () => {
    const { arDays: web } = await import(pathToFileURL(path.join(ROOT, 'src/lib/durationLabel.ts')).href);
    const { arDays: edge } = await import(pathToFileURL(path.join(ROOT, 'supabase/functions/_shared/ar_days.ts')).href);
    // The SQL helper, read from its definition and evaluated the same way Postgres does.
    const sqlText = fs.readFileSync(path.join(ROOT, ANCHOR), 'utf8');
    const body = sqlText.slice(sqlText.indexOf('function public.fn_ar_days('));
    const lit = (re) => { const m = body.match(re); assert.ok(m, String(re)); return m[1]; };
    const z = lit(/abs\(p_n\) = 0 then '([^']+)'/), one = lit(/abs\(p_n\) = 1 then '([^']+)'/), two = lit(/abs\(p_n\) = 2 then '([^']+)'/);
    const few = lit(/abs\(p_n\) <= 10 then abs\(p_n\)::text \|\| '([^']+)'/), many = lit(/else abs\(p_n\)::text \|\| '([^']+)'/);
    const sql = (n) => { const k = Math.abs(n); return k === 0 ? z : k === 1 ? one : k === 2 ? two : k <= 10 ? k + few : k + many; };
    const want = { 0: 'اليوم', 1: 'يوم واحد', 2: 'يومان', 3: '3 أيام', 10: '10 أيام', 11: '11 يومًا', 15: '15 يومًا', 100: '100 يومًا' };
    for (const [n, s] of Object.entries(want)) {
      assert.equal(web(Number(n)), s, `web ${n}`); assert.equal(edge(Number(n)), s, `edge ${n}`); assert.equal(sql(Number(n)), s, `sql ${n}`);
    }
  });

  test('the SQL anchor is in MANIFEST or pending, so new SQL files are scanned', () => {
    const m = fs.readFileSync(path.join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8');
    const listed = m.split(/\r?\n/).map((l) => l.trim()).includes(ANCHOR);
    const pending = fs.existsSync(path.join(ROOT, 'scripts/sql/pending', path.basename(ANCHOR, '.sql') + '.txt'));
    assert.ok(fs.existsSync(path.join(ROOT, ANCHOR)) && (listed || pending), `${ANCHOR} must exist and be a MANIFEST line (or a pending note until applied)`);
  });
}

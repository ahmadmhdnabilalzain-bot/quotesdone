// AN ARABIC BUYER MUST REACH THE RECORD AN ENGLISH BUYER REACHES.
//
// This property was FALSE until 9 Sep 2026 and it was false on every layer at once, which is why
// the RTL rendering and the two Arabic WhatsApp templates fooled everyone into thinking Arabic
// worked: the presentation layer was finished and the language layer was empty.
//
//   * fn_support_corpus_search built its tsquery with 'english' and 'simple' only.
//   * Every company_faq and support_knowledge row was English.
//   * site_assistant's tokeniser was /[a-z0-9]{3,}/ — Arabic produced ZERO tokens.
//   * ChatWidget never sent `lang`, so the function's Arabic branch was unreachable code.
//
// Measured on production before the fix: four ordinary Arabic questions returned 0 corpus rows and
// fn_faq_answer answered none of them. The one Arabic question a real person ever asked (8 Sep
// 02:20) got a canned English deflection.
//
// WHAT THIS CHECK ASSERTS, and why each part is here:
//
//  1. fn_ar_norm folds the orthography. The 'arabic' snowball configuration Postgres ships already
//     folds the alef variants and strips the definite article, but it does NOT fold ta-marbuta
//     (الشركة vs الشركه) or alef-maqsura (على vs علي) — the two splits that actually separate a UAE
//     buyer's spelling from a record's spelling. If the fold is lost, those two assertions fail.
//
//  2. Paired questions land on the same underlying record. The pairs are written in DELIBERATELY
//     different orthography from the stored rows (مخفيه for مخفية, المقبوله for المقبولة, تدار for
//     تُدار), so a pair passes ONLY because the fold is applied to both sides. The link is proved
//     from the data — each Arabic row's source_note names the English id it mirrors — rather than
//     from a table of ids written here, so the check follows the content instead of freezing it.
//
//  3. English is unchanged. A fix that breaks English is not a fix. These four queries returned
//     exactly these records before the change and must still return them.
//
//  4. The two repository edits are still in place. A working database with a widget that never
//     sends the language, or a tokeniser that scores Arabic as zero tokens, is a finished
//     capability with no entry point.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// THE CI CHECKS JOB HAS NO MANAGEMENT TOKEN. Without one the database tests do not fail
// meaningfully — they fail on the connection and say nothing about whether Arabic retrieves. The
// estate's convention is to SKIP and say so loudly, so a green run never reads as "verified against
// production" when it was not. The last test reads the repository and runs everywhere.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const top = async (question) => {
  const r = await sql(`select s.src, s.src_id from public.fn_support_corpus_search(${q(question)}, true, 1) s`);
  return r.length ? `${r[0].src}:${r[0].src_id}` : null;
};

test('fn_ar_norm folds the two splits the snowball stemmer leaves open', { skip: SKIP }, async () => {
  // Each row is a pair that a UAE buyer writes both ways and means identically. After the fold and
  // the stemmer they must produce the SAME lexeme, or the two spellings never meet in retrieval.
  //
  // MEASURED 9 SEP 2026, so nobody mistakes the size of the claim: the snowball stemmer already
  // handles hamza-on-alef, tashkeel and Arabic-Indic digits on its own. Only the first two pairs
  // are load-bearing against fn_ar_norm - they are the ones that differ WITHOUT the fold. The other
  // three are here to pin the fold's contract so a future edit cannot quietly drop them.
  const PAIRS = [
    ['ta-marbuta', 'الشركة', 'الشركه'],
    ['alef-maqsura', 'على', 'علي'],
    ['hamza on alef', 'إمارات', 'امارات'],
    ['tashkeel', 'تُدار', 'تدار'],
    ['Arabic-Indic digits', '٣٪', '3٪'],
  ];
  for (const [name, a, b] of PAIRS) {
    const [row] = await sql(
      `select to_tsvector('arabic', public.fn_ar_norm(${q(a)}))::text as va,
              to_tsvector('arabic', public.fn_ar_norm(${q(b)}))::text as vb`);
    assert.equal(row.va, row.vb, `${name}: ${a} and ${b} still fold to different lexemes (${row.va} vs ${row.vb})`);
  }
});

// Written differently from the stored rows on purpose — see the header. If fn_ar_norm is dropped or
// the arabic arm is removed from fn_support_corpus_search, every one of these returns null.
const PAIRS = [
  ['ما هي رسوم الكشف؟', 'what is the 3% reveal fee'],
  ['كم يستغرق التحقق من المورد؟', 'how long does verification take'],
  ['هل هويتي مخفيه عن الموردين؟', 'is my identity hidden from suppliers'],
  ['ما هي طرق الدفع المقبوله؟', 'which payment methods are accepted'],
  ['كيف تدار الشكاوى والنزاعات؟', 'how are disputes managed'],
];

test('an Arabic question reaches the record its English pair reaches', { skip: SKIP }, async () => {
  for (const [ar, en] of PAIRS) {
    const arTop = await top(ar);
    const enTop = await top(en);
    assert.ok(arTop, `Arabic retrieved NOTHING for ${ar}`);
    assert.ok(enTop, `English retrieved nothing for "${en}" — the control itself is broken`);
    assert.match(arTop, /^faq:/, `${ar} landed on ${arTop}, not on an FAQ record`);

    const [row] = await sql(
      `select language, source_note from public.company_faq where id = ${Number(arTop.split(':')[1])}`);
    assert.equal(row.language, 'ar', `${ar} was answered by a row stored as '${row.language}'`);
    // The mirror link is recorded on the row itself, so this follows the content rather than
    // freezing a list of ids that the next content change would silently invalidate.
    const enId = Number(enTop.split(':')[1]);
    assert.match(String(row.source_note), new RegExp(`\\bid ${enId}\\b`),
      `${ar} -> ${arTop} (${row.source_note}) but "${en}" -> ${enTop}: the two do not carry the same answer`);
  }
});

test('the Arabic arm is a preference, not a filter — English is still reachable', { skip: SKIP }, async () => {
  // 'Apple Pay؟' is an Arabic-script query (the question mark is U+061F) whose only content tokens
  // are Latin, so it is the one shape where records in BOTH languages match. The Arabic rows must
  // come first and the English rows must still come back — an Arabic asker with no Arabic record on
  // the subject gets the English one rather than silence.
  const rows = await sql(
    // src='faq' because only the FAQ arm of the corpus has numeric ids; a support-pack row's
    // record_id is text, and ::int on it would make this check die of a cast rather than a finding.
    `select s.src_id::int as id, s.rank from public.fn_support_corpus_search('Apple Pay؟', true, 6) s
      where s.src = 'faq' order by s.rank desc`);
  assert.ok(rows.length >= 2, 'the mixed-script probe returned nothing to order');
  const arRanks = rows.filter((r) => r.id >= 601).map((r) => r.rank);
  const enRanks = rows.filter((r) => r.id < 601).map((r) => r.rank);
  assert.ok(arRanks.length > 0, 'no Arabic record came back for an Arabic-script query');
  assert.ok(enRanks.length > 0, 'English records were FILTERED OUT, not merely outranked — the fallback is gone');
  assert.ok(Math.min(...arRanks) > Math.max(...enRanks),
    'an English record outranked an Arabic one for an Arabic asker; the language preference is not applied');
});

test('English still returns exactly what it returned before Arabic existed', { skip: SKIP }, async () => {
  // Measured on production 9 Sep 2026 BEFORE this change was applied. A regression here means the
  // Arabic work moved an English answer, which is not a trade anyone agreed to.
  const CONTROL = [
    ['what is the 3% reveal fee', 'faq:89'],
    ['how long does verification take', 'faq:39'],
    ['can I get a refund', 'faq:31'],
    ['how do I pay', 'faq:29'],
  ];
  for (const [question, expected] of CONTROL) {
    assert.equal(await top(question), expected, `English regressed: "${question}"`);
  }
  // And no Arabic record may ever be the top answer to an English question.
  for (const [question] of CONTROL) {
    const t = await top(question);
    assert.ok(Number(t.split(':')[1]) < 601, `"${question}" was answered by an Arabic record (${t})`);
  }
});

test('the widget sends the language and the function can tokenise it', () => {
  const fn = readFileSync(join(ROOT, 'supabase', 'functions', 'site_assistant', 'index.ts'), 'utf8');
  const tokLine = fn.split('\n').find((l) => l.includes('function tok('));
  assert.ok(tokLine, 'site_assistant lost its tok() helper');
  assert.match(tokLine, /\\u0600-\\u06FF|؀-ۿ/,
    'site_assistant.tok() still matches Latin only — every Arabic message scores zero tokens');

  const widget = readFileSync(join(ROOT, 'src', 'components', 'ChatWidget.tsx'), 'utf8');
  const body = widget.split('\n').find((l) => l.includes('JSON.stringify({ message'));
  assert.ok(body, 'ChatWidget no longer posts a JSON body shaped as expected');
  assert.match(body, /\blang\b/,
    'ChatWidget does not send lang — site_assistant resolves uiLang to en and its Arabic branch is unreachable');
});

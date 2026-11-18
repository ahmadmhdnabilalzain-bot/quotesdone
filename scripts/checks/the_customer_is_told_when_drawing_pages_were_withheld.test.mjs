// THE CUSTOMER IS TOLD WHEN HIS REQUEST WENT TO SUPPLIERS WITHOUT ITS DRAWING PAGES (18 Nov 2026, sales_engineer).
// customer_api create_inquiry refuses the drawing pages of a document the server judged priced (lib/drawings.ts
// drawingPagesRefused) and answers drawing_pages_withheld with drawing_pages_withheld_message {en, ar}. Measured before this
// check: no file under src/ read either field, so the composer said "sent" and the customer believed the suppliers had his
// drawing. This check pins that every portal screen that shows a create_inquiry answer (the composer's posted screen, the
// request list after Send, a repeat from a request card) renders the server's sentence through portalText pagesWithheldText,
// and that the helper picks the customer's language and never carries the reason of its own.
// Known-bad controls: drop the {pagesWithheldText(posted.r ...)} line from NewRequest.tsx (test 3 fails); have the helper read
// only `.en` (test 1 fails on 'ar'); hard-code "priced" in portalText (test 2 fails).
//   node --test scripts/checks/the_customer_is_told_when_drawing_pages_were_withheld.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { T, pagesWithheldText } from '../../src/components/me/portalText.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
// code only: a check that greps source must not match its own comment (quotesdone-apply-discipline)
const code = (s) => s.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*|\{\/\*)/.test(l)).join('\n');

test('the server\'s own sentence is shown, in the customer\'s language', () => {
  const r = { ok: true, drawing_pages_withheld: true, drawing_pages_withheld_reason: 'priced_document', drawing_pages_withheld_message: { en: 'EN said by the server', ar: 'AR said by the server' } };
  assert.equal(pagesWithheldText(r, 'en'), 'EN said by the server');
  assert.equal(pagesWithheldText(r, 'ar'), 'AR said by the server');
  assert.equal(pagesWithheldText({ ok: true }, 'en'), '', 'nothing is said when nothing was withheld');
  assert.equal(pagesWithheldText(null, 'ar'), '');
  assert.equal(pagesWithheldText({ ...r, drawing_pages_withheld: false }, 'en'), '', 'only the server\'s true means withheld');
});

test('a missing message falls back to a short generic line in both languages, and the reason is never the client\'s', () => {
  const bare = { ok: true, drawing_pages_withheld: true };
  assert.equal(pagesWithheldText(bare, 'en'), T.en.nr_pages_withheld);
  assert.equal(pagesWithheldText(bare, 'ar'), T.ar.nr_pages_withheld);
  assert.equal(pagesWithheldText({ ...bare, drawing_pages_withheld_message: { en: 'only English' } }, 'ar'), T.ar.nr_pages_withheld, 'Arabic is never answered in English');
  for (const l of ['en', 'ar']) {
    assert.ok(T[l].nr_pages_withheld && T[l].nr_pages_withheld.length < 90, l + ': the fallback is short');
    assert.doesNotMatch(T[l].nr_pages_withheld, /pric|quotation|مُسعَّر|مسعر|عرض سعر/i, l + ': the reason is the server\'s to give');
  }
  const helper = code(R('src/components/me/portalText.ts')).match(/export function pagesWithheldText[\s\S]*?\n\}/);
  assert.ok(helper, 'portalText exports pagesWithheldText');
  assert.match(helper[0], /r\.drawing_pages_withheld_message/, 'the helper reads drawing_pages_withheld_message');
});

test('every screen that shows a create_inquiry answer renders it', () => {
  const nr = code(R('src/components/me/NewRequest.tsx'));
  assert.match(nr, /action: 'create_inquiry'/, 'the composer is the create_inquiry caller');
  assert.match(nr, /\{pagesWithheldText\(posted\.r, lang\) \? <p role="status"[^\n]*>\{pagesWithheldText\(posted\.r, lang\)\}<\/p>/, 'the posted screen renders the sentence');
  assert.match(nr, /setPosted\(\{ none: true,[^\n]*, r \}\)/, 'a request that reached no supplier keeps the answer for the posted screen');
  assert.match(nr, /onDone\(\{ none: true, inquiry_id: posted\.id, drawing_pages_withheld: [^\n]*drawing_pages_withheld_message: posted\.r && posted\.r\.drawing_pages_withheld_message \}\)/, '"none" hands the sentence on to the request list');
  const db = code(R('src/components/me/dashboard/Dashboard.tsx'));
  assert.match(db, /onDone=\{\(r\) => \{[\s\S]*?setWithheld\(r \|\| null\);[\s\S]*?\}\}/, 'the request list keeps the answer after Send');
  assert.match(db, /\{pagesWithheldText\(withheld, lang\) \? <div [^\n]*role="status">\{pagesWithheldText\(withheld, lang\)\}<\/div> : null\}/, 'the request list renders it');
  const card = code(R('src/components/me/requests/InquiryCard.tsx'));
  assert.match(card, /action: 'repeat_inquiry', inquiry_id: inq\.id, edits: rDraft[^\n]*setRepeated\(\[t\(lang, 'rc_repeat_done'\), pagesWithheldText\(j, lang\)\]/, 'a repeat (which posts through create_inquiry) says it too');
});

test('the server still answers the fields the portal reads', () => {
  const ic = code(R('supabase/functions/customer_api/actions/inquiry_create.ts'));
  assert.match(ic, /drawing_pages_withheld: true, drawing_pages_withheld_reason: 'priced_document', drawing_pages_withheld_message: PRICED_PAGES_WITHHELD_MESSAGE/);
  assert.equal((ic.match(/return J\(\{ \.\.\.followSaid,/g) || []).length, 3, 'every posted answer (split, turnkey, single) carries it');
  const msg = code(R('supabase/functions/customer_api/lib/drawings.ts')).match(/export const PRICED_PAGES_WITHHELD_MESSAGE = \{\n\s*en: '[^']+',\n\s*ar: '[^']+',/);
  assert.ok(msg, 'the message is {en, ar}');
});

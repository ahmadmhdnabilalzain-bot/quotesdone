// THE EMAIL TRIAGE ANSWER FITS ITS ROUTE (it_engineer, 22 Sep 2026, founder instruction 705).
// Recurrence check for scripts/sql/the_triage_answer_fits_the_tokens_its_route_allows.sql.
//
// email_triage asked for 800 tokens on a route that allowed 300, so any real drafted reply was cut off,
// repaired once, cut again and discarded: two paid requests for nothing. This measures the answer the job
// asks for on three fixtures and FAILS if the caller's request or the route's ceiling drops below it, or if
// the two stop agreeing. Token counts are an ESTIMATE (UTF-8 bytes / 3 — over-counts English at ~4 chars a
// token and Arabic at 2 bytes a character); no tokenizer and no model was used. Repository only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const estTokens = (s) => Math.ceil(Buffer.byteLength(s, 'utf8') / 3);

// The answer the triage contract asks for (email_triage SYS): category, one factual sentence, a short warm
// reply signed 'The QuotesDone Team'. ZZ DEMO senders; nothing here reaches anyone.
const FIXTURES = {
  supplier_document_en: {
    category: 'supplier_document',
    summary: 'ZZ DEMO Aluminium Works sent its renewed trade licence and asked whether anything else is needed to stay verified.',
    reply: 'Dear ZZ DEMO Aluminium Works team,\n\nThank you for sending your renewed trade licence. We have received it and your records will be updated shortly; you do not need to do anything further for now. If any other document is due, we will let you know in advance so your profile stays verified and you keep receiving matching requests.\n\nKind regards,\nThe QuotesDone Team',
  },
  customer_question_en: {
    category: 'customer_question',
    summary: 'A customer asks when they pay the reveal fee and whether the supplier sees their details before they choose.',
    reply: 'Hello,\n\nThank you for your question. You only pay when you decide to reveal a supplier: the fee is 3% of the quote you choose, plus the card processing fee, and it is charged at that moment, not before. Until then your details stay private and suppliers see your request without your name or contact information. Once you reveal, both of you are introduced so you can agree the work directly.\n\nIf you would like, reply with your request number and we will check its status for you.\n\nKind regards,\nThe QuotesDone Team',
  },
  customer_question_ar: {
    category: 'customer_question',
    summary: 'يسأل عميل متى يدفع رسوم الكشف وهل يرى المورد بياناته قبل أن يختار.',
    reply: 'مرحباً،\n\nشكراً لتواصلك معنا. لا تدفع إلا عندما تقرر الكشف عن أحد الموردين: الرسوم 3% من قيمة العرض الذي تختاره، إضافة إلى رسوم معالجة البطاقة، وتُحتسب في تلك اللحظة فقط. وحتى ذلك الحين تبقى بياناتك خاصة، ويرى الموردون طلبك دون اسمك أو وسائل التواصل معك. وبعد الكشف نعرّف كل طرف بالآخر لتتفقا على العمل مباشرة.\n\nإن رغبت، أرسل لنا رقم طلبك وسنتحقق من حالته.\n\nمع أطيب التحيات،\nفريق QuotesDone',
  },
};

const requested = () => {
  const src = read('supabase/functions/email_triage/index.ts');
  const m = src.match(/await llm\(SYS,[^\n]*tlText,\s*(\d+)\)/);
  assert.ok(m, 'email_triage no longer calls llm(SYS, ..., <max>) — update this check with the new call');
  return Number(m[1]);
};
const routeCeiling = () => {
  const sql = read('scripts/sql/the_triage_answer_fits_the_tokens_its_route_allows.sql');
  const m = sql.match(/set max_tokens = (\d+)\s+where task_class = 'intent_detection'/);
  assert.ok(m, 'the intent_detection ceiling is no longer set in its owning file');
  return Number(m[1]);
};

test('every fixture answer fits what email_triage asks for', () => {
  const max = requested();
  for (const [name, a] of Object.entries(FIXTURES)) {
    const t = estTokens(JSON.stringify(a));
    assert.ok(t <= max, `${name}: ~${t} tokens does not fit the ${max} email_triage asks for`);
  }
});

// Measured 22 Sep 2026: ~180, ~229 and ~291 estimated tokens. The Arabic answer sat at 97% of the old
// 300 ceiling, so any longer real email was cut. A ceiling needs headroom over a TYPICAL answer, because a
// censored distribution cannot be fixed by moving the censor (_shared/llm.ts, 14 Aug 2026).
test('the ceiling leaves at least twice the typical answer, which the old 300 did not', () => {
  const worst = Math.max(...Object.values(FIXTURES).map((a) => estTokens(JSON.stringify(a))));
  assert.ok(worst * 2 > 300, 'the fixtures no longer show why 300 was too tight');
  assert.ok(worst * 2 <= requested(), `email_triage asks for ${requested()}, less than twice a typical answer (~${worst})`);
});

test('the route allows what the caller asks for, so nothing is cut and repaired', () => {
  assert.ok(routeCeiling() >= requested(), `intent_detection allows ${routeCeiling()} but email_triage asks for ${requested()}`);
});

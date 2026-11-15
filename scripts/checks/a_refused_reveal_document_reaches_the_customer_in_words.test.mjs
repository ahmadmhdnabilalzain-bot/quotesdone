// a_refused_reveal_document_reaches_the_customer_in_words.test.mjs — review 5, item 4 (15 Nov 2026, accountant).
// node --test scripts/checks/a_refused_reveal_document_reaches_the_customer_in_words.test.mjs
//
// MEASURED (review 5, LOCAL + code): reveal_invoice refused an invoice for a reveal that charged nothing (409
// zero_fee_no_invoice) with message_en / message_ar. The portal renders a refusal through errText
// (src/components/me/portalText.ts): a code in CODE_KEY, else `message` + `message_ar`. Neither held, so the customer
// read "Could not open the invoice." for a reveal that has no invoice by design. The refusal now carries `message`
// and `message_ar` (reveal_fee_documents.ts refusal()). This check runs the portal's own errText on the exact body the
// function returns, in both languages, and fails if the customer would read the generic line again.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { errText, t } from '../../src/components/me/portalText.ts';
import { NO_INVOICE, NOT_PAID, refusal } from '../../supabase/functions/_shared/reveal_fee_documents.ts';
import { functionSource } from '../lib/function_sources.mjs';

const SRC = functionSource('reveal_invoice');

test('reveal_invoice answers both document refusals with the shared refusal body (no hand-built message_en object)', () => {
  assert.match(SRC, /return J\(refusal\(NO_INVOICE\), 409\)/);
  assert.match(SRC, /return J\(refusal\(NOT_PAID\), 409\)/);
  assert.doesNotMatch(SRC, /message_en: NO_INVOICE\.en/);
});

test('a zero-fee reveal: the customer reads that nothing was charged, in their language, not "Could not open the invoice."', () => {
  const body = refusal(NO_INVOICE);
  assert.equal(body.code, 'zero_fee_no_invoice');
  for (const lang of ['en', 'ar']) {
    const shown = errText(body, lang, 'q_inv_fail');           // exactly what QuoteDocs.tsx InvoicePdfLink renders
    assert.notEqual(shown, t(lang, 'q_inv_fail'), `${lang}: the generic failure line`);
    assert.equal(shown, lang === 'ar' ? NO_INVOICE.ar : NO_INVOICE.en, lang);
  }
  assert.match(errText(body, 'en', 'q_inv_fail'), /Nothing was charged/);
  // the body sent before (message_en / message_ar only) is the generic line: why the shape matters
  const before = { error: NO_INVOICE.code, code: NO_INVOICE.code, message_en: NO_INVOICE.en, message_ar: NO_INVOICE.ar };
  assert.equal(errText(before, 'en', 'q_inv_fail'), t('en', 'q_inv_fail'));
  assert.match(errText(body, 'ar', 'q_inv_fail'), /[؀-ۿ]/);
});

test('a payment not settled keeps its own portal wording', () => {
  for (const lang of ['en', 'ar']) {
    const shown = errText(refusal(NOT_PAID), lang, 'q_inv_fail');
    assert.notEqual(shown, t(lang, 'q_inv_fail'), lang);
    assert.equal(shown, t(lang, 'q_inv_not_paid'), lang);
  }
});

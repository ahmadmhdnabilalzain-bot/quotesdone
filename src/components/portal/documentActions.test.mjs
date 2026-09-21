// documentActions.test.mjs — the four words are the same four words in both languages, every sealed
// reason is a sentence in both, and Download is the signed URL told to attach.
//   node --test src/components/portal/documentActions.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { ACTION_WORDS, downloadUrl, sealedReason, word } from './documentActions.ts';

test('the four actions, in order, in both languages', () => {
  assert.deepEqual(Object.keys(ACTION_WORDS.en).slice(0, 4), ['view', 'download', 'replace', 'remove']);
  assert.deepEqual(Object.keys(ACTION_WORDS.ar).slice(0, 4), ['view', 'download', 'replace', 'remove']);
  assert.equal(word('en', 'remove'), 'Remove');
  assert.equal(word('ar', 'remove'), 'إزالة');
  for (const k of ['view', 'download', 'replace', 'remove']) assert.match(ACTION_WORDS.ar[k], /[؀-ۿ]/, k + ' has Arabic');
});

test('every sealed code has an English and an Arabic sentence; an unknown code has none', () => {
  for (const c of ['paid_invoice', 'signed_terms', 'customers_inquiry', 'sent_to_suppliers', 'suppliers_file', 'sanctions', 'mandatory_of_approved', 'generated']) {
    assert.ok(sealedReason('en', c).length > 20, c);
    assert.match(sealedReason('ar', c), /[؀-ۿ]/, c);
  }
  assert.equal(sealedReason('en', null), null);
  assert.equal(sealedReason('en', 'nope'), null);
});

test('downloadUrl adds the attachment parameter once and keeps the signature', () => {
  const u = 'https://x.supabase.co/storage/v1/object/sign/supplier-docs/licence/1/a.pdf?token=abc';
  const d = downloadUrl(u, 'licence.pdf');
  assert.ok(d.includes('token=abc'));
  assert.ok(d.includes('download=licence.pdf'));
  assert.equal(downloadUrl(d, 'other.pdf'), d);
  assert.equal(downloadUrl(null, 'x'), null);
  assert.equal(downloadUrl('not a url'), 'not a url');
});

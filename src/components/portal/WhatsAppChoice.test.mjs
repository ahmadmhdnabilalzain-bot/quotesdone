// WhatsAppChoice.test.mjs — the WhatsApp question says the same thing in both languages, maps every
// refusal to words, decides its steps correctly, and is actually placed where the founder asked.
// node --test src/components/portal/WhatsAppChoice.test.mjs
// Founder, 14 Sep 2026: "what if the customer has whatsapp on another phone number, maybe we should
// confirm this point through the sign up". The .tsx cannot be imported by node (JSX), so the copy and
// the rules live in whatsappChoiceText.ts and the placements are checked in the source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { WA_TEXT, WA_ERROR_CODES, waErrorKey, waErrorText, waUnavailable, waSignupSettled, waNeedsPrompt, waCurrentKey } from './whatsappChoiceText.ts';

const HERE = import.meta.dirname;

test('English and Arabic have exactly the same keys, none empty', () => {
  assert.deepEqual(Object.keys(WA_TEXT.ar).sort(), Object.keys(WA_TEXT.en).sort());
  for (const lang of ['en', 'ar']) for (const [k, v] of Object.entries(WA_TEXT[lang])) assert.ok(String(v).trim(), lang + '.' + k + ' is empty');
});

test('the Arabic carries no English word; only QuotesDone and WhatsApp stay in Latin script', () => {
  for (const [k, v] of Object.entries(WA_TEXT.ar)) {
    const rest = v.replace(/QuotesDone|WhatsApp/g, '');
    assert.doesNotMatch(rest, /[A-Za-z]/, 'ar.' + k + ': ' + v);
  }
});

test('every refusal code in the contract reads as its own words, in both languages', () => {
  for (const c of WA_ERROR_CODES) {
    for (const j of [{ code: c }, { error: c }]) assert.equal(waErrorKey(j), 'err_' + c);
    for (const lang of ['en', 'ar']) {
      const s = waErrorText(lang, { code: c });
      assert.ok(s && s !== WA_TEXT[lang].err_generic, lang + ' ' + c);
      assert.doesNotMatch(s, /_/, 'a raw code leaked: ' + s);
    }
  }
  assert.equal(waErrorKey({ error: 'something_new' }), 'err_generic');
  assert.equal(waErrorKey(null), 'err_generic');
});

test('whatsapp_unavailable is recognised in error or code, and nothing else is', () => {
  assert.equal(waUnavailable({ ok: false, error: 'whatsapp_unavailable' }), true);
  assert.equal(waUnavailable({ code: 'whatsapp_unavailable' }), true);
  assert.equal(waUnavailable({ error: 'bad_phone', code: 'bad_phone' }), false);
  assert.equal(waUnavailable(null), false);
});

test('the terms step waits for an answer or the unavailable path, never for a server that does not ask', () => {
  const unanswered = { opt: null, phone: null, verified: false, asked: false };
  assert.equal(waSignupSettled(unanswered, false), false);
  assert.equal(waSignupSettled(unanswered, true), true);
  for (const opt of ['same', 'other', 'none']) assert.equal(waSignupSettled({ ...unanswered, opt }, false), true);
  assert.equal(waSignupSettled(undefined, false), true);
  assert.equal(waSignupSettled(null, false), false);
});

test('the dashboard asks once: only when the server says the account was never asked', () => {
  assert.equal(waNeedsPrompt({ opt: null, phone: null, verified: false, asked: false }), true);
  assert.equal(waNeedsPrompt({ opt: null, phone: null, verified: false, asked: true }), false);
  assert.equal(waNeedsPrompt(undefined), false);
});

test('Settings never presents an unverified number as the WhatsApp number', () => {
  assert.equal(waCurrentKey({ opt: 'other', phone: '+971501234567', verified: true, asked: true }), 'cur_other');
  assert.equal(waCurrentKey({ opt: 'other', phone: '+971501234567', verified: false, asked: true }), 'cur_pending');
  assert.equal(waCurrentKey({ opt: 'same', phone: null, verified: true, asked: true }), 'cur_same');
  assert.equal(waCurrentKey({ opt: 'none', phone: null, verified: false, asked: true }), 'cur_none');
  assert.equal(waCurrentKey({ opt: null, phone: null, verified: false, asked: false }), 'cur_unset');
});

test('all six placements render WhatsAppChoice with the right mode', () => {
  const src = (p) => readFileSync(join(HERE, p), 'utf8');
  const modes = (s) => [...s.matchAll(/<WhatsAppChoice\b[^>]*\bmode="(\w+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(modes(src('../me/CustomerPortal.tsx')), ['prompt', 'settings', 'signup']);
  assert.deepEqual(modes(src('SupplierPortal.tsx')), ['prompt', 'signup']);
  assert.deepEqual(modes(src('supplier/SupplierSettings.tsx')), ['settings']);
});

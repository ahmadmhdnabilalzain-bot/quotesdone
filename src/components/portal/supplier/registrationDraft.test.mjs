// node --test src/components/portal/supplier/registrationDraft.test.mjs
// Browser perfection walk, 12 Nov 2026 (customer_support), H7 and M3: a reload mid-form dropped the emirates, the mobile, the
// contact name, the chosen profile and the agreement tick; a reload at the code step dropped the step and the address.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { draftKey, draftOf, saveDraft, readDraft, clearRegistrationDrafts, chooseAgainNote, saveLoginDraft, readLoginDraft, CODE_LIFE_MS, LOGIN_DRAFT } from './registrationDraft.ts';

const mem = () => { const m = new Map(); return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k), key: (i) => [...m.keys()][i] ?? null, get length() { return m.size; }, m }; };
const STATE = { emirates: ['Dubai', 'Sharjah'], phone: '050 123 4567', contact_name: 'ZZ DEMO Contact', terms: true, marketing: false, trading_name: 'ZZ DEMO Shop Name',
  profileFile: { name: 'ZZ DEMO profile.pdf', size: 1234, arrayBuffer: () => {} }, catalogFiles: [{ name: 'cat1.pdf' }],
  smsCode: '123456', mailCode: '654321', token: 'eyJ.zz' };

test('what he typed and ticked comes back after a reload, for his account only', () => {
  const s = mem(); const key = draftKey({ id: 990011 });
  saveDraft(s, key, draftOf('zz@example.invalid', STATE, 1000));
  const d = readDraft(s, key, 'zz@example.invalid', 2000);
  assert.deepEqual(d.emirates, ['Dubai', 'Sharjah']); assert.equal(d.phone, '050 123 4567'); assert.equal(d.contact_name, 'ZZ DEMO Contact');
  assert.equal(d.terms, true); assert.equal(d.marketing, false);
  assert.equal(d.trading_name, 'ZZ DEMO Shop Name', 'ruling 1672: the optional trading name survives a reload');
  assert.equal(readDraft(s, key, 'someone-else@example.invalid', 2000), null, 'another account never reads it');
  assert.equal(readDraft(s, key, 'zz@example.invalid', 1000 + 25 * 3600_000), null, 'a day-old draft is dropped');
});

test('never a code, a token or a file\'s bytes: only the names of the files, so the form can say which to choose again', () => {
  const s = mem(); const key = draftKey({ id: 990011 });
  saveDraft(s, key, draftOf('zz@example.invalid', STATE));
  const raw = s.getItem(key);
  for (const no of ['123456', '654321', 'eyJ', 'arrayBuffer', 'size']) assert.ok(!raw.includes(no), `the draft holds ${no}`);
  assert.deepEqual(Object.keys(JSON.parse(raw)).sort(), ['at', 'catalogue_names', 'contact_name', 'emirates', 'marketing', 'owner', 'phone', 'profile_name', 'terms', 'trading_name']);
  const d = readDraft(s, key, 'zz@example.invalid');
  assert.match(chooseAgainNote(d, { profile: true, catalogues: true }), /please choose these files again: ZZ DEMO profile\.pdf, cat1\.pdf\. Everything you typed and ticked is still here\./);
  assert.equal(chooseAgainNote(d, { profile: false, catalogues: false }), '');
});

test('submit and sign-out clear every draft and the code step, and a refusing storage never breaks the form', () => {
  const s = mem(); saveDraft(s, draftKey({ id: 1 }), draftOf('a', STATE)); saveDraft(s, draftKey({ id: 2 }), draftOf('b', STATE));
  saveLoginDraft(s, { mode: 'signup', step: 'code', ident: 'zz@example.invalid' }); s.setItem('qd-cookie-consent', 'essential');
  clearRegistrationDrafts(s);
  assert.deepEqual([...s.m.keys()], ['qd-cookie-consent']);
  const refusing = { getItem: () => { throw new Error('denied'); }, setItem: () => { throw new Error('denied'); }, removeItem: () => { throw new Error('denied'); }, key: () => { throw new Error('denied'); }, length: 3 };
  assert.doesNotThrow(() => { saveDraft(refusing, 'k', draftOf('a', STATE)); readDraft(refusing, 'k', 'a'); clearRegistrationDrafts(refusing); saveLoginDraft(refusing, { mode: 'signin', step: 'code', ident: 'x' }); readLoginDraft(refusing); });
  assert.equal(readDraft(null, 'k', 'a'), null);
});

test('the code step and its address come back while the code can still be used; after that, the address on the first step', () => {
  const s = mem();
  saveLoginDraft(s, { mode: 'signup', step: 'code', ident: 'zz@example.invalid', code: '123456' }, 0);
  assert.ok(!s.getItem(LOGIN_DRAFT).includes('123456'), 'never the code');
  assert.deepEqual(readLoginDraft(s, CODE_LIFE_MS - 1000), { mode: 'signup', step: 'code', ident: 'zz@example.invalid', at: 0 });
  assert.deepEqual(readLoginDraft(s, CODE_LIFE_MS + 1000), { mode: 'signup', step: 'id', ident: 'zz@example.invalid', at: 0 });
});

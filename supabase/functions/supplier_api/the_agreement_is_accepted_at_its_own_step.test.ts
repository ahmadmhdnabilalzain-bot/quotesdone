// deno test supabase/functions/supplier_api/the_agreement_is_accepted_at_its_own_step.test.ts
// FOUNDER RULING 1672 (12 Nov 2026): the supplier verifies his e-mail, his mobile, then "directly accepts the terms and conditions. We
// get the copy of that with the IP address", before any document. supplier_api accept_terms records the acceptance at that step with
// the one name typed in sign-up, the person accepting for the company. His own certificate that evening printed a first name as both
// "Full name" and "Authorised signatory".
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';
import { personName } from './lib/fields.ts';
import { acceptanceNeedsName } from '../_shared/supplier_terms.ts';

const src = functionSource('supplier_api');
const handler = (() => { const i = src.indexOf("if (action === 'accept_terms') {"); return src.slice(i, src.indexOf("if (action === 'settings')", i)); })();

Deno.test('a full name is two words with letters, in any script; a first name alone is not', () => {
  assertEquals(personName('  ZZ DEMO   Firstname  Lastname '), 'ZZ DEMO Firstname Lastname');
  assertEquals(personName('Mohammed Al Ali'), 'Mohammed Al Ali');
  assertEquals(personName('محمد العلي'), 'محمد العلي');
  for (const bad of ['Mohammed', '', '   ', 'A', '12 34', null, undefined, '- -']) assertEquals(personName(bad), null, String(bad));
  assertEquals(personName('x'.repeat(100) + ' ' + 'y'.repeat(100))?.length, 120, 'at most 120 characters');
});

Deno.test('accept_terms takes the time, IP, device, version and text hash from the server, never from the body', () => {
  assert(handler.length > 200, 'the accept_terms handler moved');
  assertMatch(handler, /supplierTermsRecord\(secretVal, clientIp\(req\), req\.headers\.get\('user-agent'\) \|\| ''\)/);
  assert(!/body\.(accepted_terms|ip|user_agent|version|sha|at)\b/.test(handler), 'an acceptance field is read from the body');
});

Deno.test('the name typed at the agreement is the signatory and the contact, written only with a NEW acceptance; a short one is refused', () => {
  assertMatch(handler, /if \(fullName && !stands\) \{ names\.signatory_name = fullName; names\.contact_name = fullName; \}/);
  assertMatch(handler, /code: 'full_name_required'/);
  assertMatch(handler, /Please enter your full name: your first name and your family name\./);
});

Deno.test('an acceptance of the current version already on file is not written twice (one acceptance, one certificate)', () => {
  assertMatch(handler, /const stands = !!sup\.accepted_terms_at && await supplierAcceptanceStands\(secretVal, sup\.accepted_terms_version\);/);
  assertMatch(handler, /const rec = stands \? \{\} : await supplierTermsRecord/);
});

Deno.test('Submit treats an acceptance made at the agreement step, whose certificate has not landed, as pending, never as missing', () => {
  assertMatch(src, /const acceptedAt = accepting \? String\(upd\.accepted_terms_at\) : \(sup\.accepted_terms_at \? String\(sup\.accepted_terms_at\) : ''\);/);
  assertMatch(src, /const stillNeeded = \(v\.missing \|\| \[\]\)\.filter\(\(c\) => !\(certificatePending && c === 'reg_terms'\)/);
});

// REVIEW OF #1987, S5 (12 Nov 2026): an older page or a direct call recorded a first acceptance with no name, and a second call changed the
// signatory after the acceptance, so a re-issued certificate would print the new name.
Deno.test('S5: a first acceptance needs a full name; a re-acceptance by a supplier who accepted before never does', () => {
  assertEquals(acceptanceNeedsName({ accepted_terms_at: null, signatory_name: null }, null), true, 'a first acceptance with no name');
  assertEquals(acceptanceNeedsName({ accepted_terms_at: null, signatory_name: 'Ahmad' }, null), true, 'a first name on file is not a full name');
  assertEquals(acceptanceNeedsName({ accepted_terms_at: null, signatory_name: null }, 'ZZ DEMO Ahmad Zain'), false);
  assertEquals(acceptanceNeedsName({ accepted_terms_at: null, signatory_name: 'ZZ DEMO Ahmad Zain' }, null), false, 'his full name already on file');
  assertEquals(acceptanceNeedsName({ accepted_terms_at: '2026-10-01T00:00:00Z', signatory_name: null }, null), false, 'a new version to re-accept is never stopped');
});

Deno.test('S5: every door that records a supplier acceptance refuses a nameless first one; a standing acceptance keeps its signatory', () => {
  assertMatch(handler, /if \(!stands && acceptanceNeedsName\(sup, fullName\)\) return J\(\{ \.\.\.FULL_NAME_REQUIRED \}, 400\);/);
  assert(!/names\.signatory_name = fullName;(?![^\n]*!stands)/.test(handler.replace(/if \(fullName && !stands\) \{ names\.signatory_name = fullName;/, '')), 'the signatory is written without the !stands guard');
  const save = src.slice(src.indexOf("if (action === 'save_profile')"));
  assertMatch(save, /if \(acceptanceNeedsName\(\{ accepted_terms_at: sup\.accepted_terms_at, signatory_name: who\?\.signatory_name \?\? upd\.signatory_name \}, null\)\) return J\(\{ \.\.\.FULL_NAME_REQUIRED \}, 400\);/);
  const kyc = Deno.readTextFileSync(new URL('../kyc/index.ts', import.meta.url));
  assertMatch(kyc, /if \(acceptanceNeedsName\(lead as any, null\)\) return J\(\{ \.\.\.FULL_NAME_REQUIRED \}, 400\);/);
});

// deno test supabase/functions/supplier_api/the_agreement_is_accepted_at_its_own_step.test.ts
// FOUNDER RULING 1672 (12 Nov 2026): the supplier verifies his e-mail, his mobile, then "directly accepts the terms and conditions. We
// get the copy of that with the IP address", before any document. supplier_api accept_terms records the acceptance at that step with
// the one name typed in sign-up, the person accepting for the company. His own certificate that evening printed a first name as both
// "Full name" and "Authorised signatory".
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';
import { personName } from './lib/fields.ts';

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

Deno.test('the name typed at the agreement is the signatory (and the contact when none is on file); a short one is refused in plain words', () => {
  assertMatch(handler, /names\.signatory_name = fullName; if \(!String\(sup\.contact_name \?\? ''\)\.trim\(\)\) names\.contact_name = fullName;/);
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

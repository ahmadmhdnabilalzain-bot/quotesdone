// pickApiKey prefers the new keys, falls back to the legacy ones only when no new key is listed, and never
// returns a masked key. The fixtures are built at run time and are not keys of any project.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pickApiKey, projectKeys } from './supabase_keys.mjs';

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const fakeJwt = (role) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ iss: 'supabase', ref: 'zzfixture', role })}.${'x'.repeat(43)}`;
const LEGACY_ANON = { name: 'anon', type: 'legacy', api_key: fakeJwt('anon') };
const LEGACY_SERVICE = { name: 'service_role', type: 'legacy', api_key: fakeJwt('service_role') };
const PUB_DEFAULT = { name: 'default', type: 'publishable', api_key: 'sb_publishable_zzfixtureDEFAULT' };
const PUB_OTHER = { name: 'quotesdone2', type: 'publishable', api_key: 'sb_publishable_zzfixtureOTHER' };
const SEC_DEFAULT = { name: 'default', type: 'secret', api_key: 'sb_secret_zzfixtureDEFAULT' };

test('the new key is chosen over the legacy key, and the default one over any other', () => {
  const all = [LEGACY_ANON, LEGACY_SERVICE, PUB_OTHER, PUB_DEFAULT, SEC_DEFAULT];
  assert.equal(pickApiKey(all, 'publishable'), PUB_DEFAULT.api_key);
  assert.equal(pickApiKey(all, 'secret'), SEC_DEFAULT.api_key);
  assert.deepEqual(projectKeys(all), { ANON: PUB_DEFAULT.api_key, SERVICE: SEC_DEFAULT.api_key });
});

test('the legacy key is the fallback only when no new key of that power is listed', () => {
  assert.equal(pickApiKey([LEGACY_ANON, LEGACY_SERVICE], 'publishable'), LEGACY_ANON.api_key);
  assert.equal(pickApiKey([LEGACY_ANON, LEGACY_SERVICE], 'secret'), LEGACY_SERVICE.api_key);
  // a publishable key never stands in for the secret one, nor the reverse
  assert.equal(pickApiKey([PUB_DEFAULT], 'secret'), '');
  assert.equal(pickApiKey([SEC_DEFAULT], 'publishable'), '');
});

test('a masked key (listed without reveal) is never returned', () => {
  const masked = { name: 'default', type: 'secret', api_key: 'sb_secret_abcd••••' };
  assert.equal(pickApiKey([masked, LEGACY_SERVICE], 'secret'), LEGACY_SERVICE.api_key);
  assert.equal(pickApiKey([masked], 'secret'), '');
});

test('an answer that is not a list yields no key, and a wrong kind is refused', () => {
  assert.equal(pickApiKey({ message: 'Unauthorized' }, 'secret'), '');
  assert.equal(pickApiKey(null, 'publishable'), '');
  assert.throws(() => pickApiKey([], 'service_role'), /kind must be/);
});

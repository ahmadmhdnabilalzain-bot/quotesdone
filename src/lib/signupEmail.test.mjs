// node --test src/lib/signupEmail.test.mjs — the sign-up address rule both portals share.
import test from 'node:test';
import assert from 'node:assert/strict';
import { signupEmailProblem } from './signupEmail.ts';

test('a plain work address is accepted', () => {
  assert.equal(signupEmailProblem('ahmad@company.ae'), null);
  assert.equal(signupEmailProblem('  Ahmad@Company.COM '), null);
});
test('not an email at all', () => {
  assert.equal(signupEmailProblem('not-an-email'), 'signup_email_only');
  assert.equal(signupEmailProblem(''), 'signup_email_only');
  assert.equal(signupEmailProblem(null), 'signup_email_only');
});
test('reserved names that can never receive mail are refused', () => {
  for (const a of ['a@example.invalid', 'a@x.test', 'a@example.com', 'a@site.example', 'a@dev.localhost', 'a@ZZ.EXAMPLE.ORG']) {
    assert.equal(signupEmailProblem(a), 'signup_email_reserved', a);
  }
});

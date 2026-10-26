// fixtures_session.test.mjs — a fixture's JWT is refreshed before it expires. Seat: it_engineer.
// Replays run qd_run:0a717394 (19 Oct 2026, S22): fixtures signed in at 10:50, S22 called
// customer_api accept_terms after the 3600 s access token had expired and got HTTP 401
// UNAUTHORIZED_ASYMMETRIC_JWT. Without the refresh in fixtures.call this test fails.
// Run: node --test scripts/e2e/fixtures_session.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { trackSession, freshJwt, tokenIsStale, REFRESH_MARGIN_S } from './fixtures.mjs';

const T0 = 1_760_870_000;   // sign-in time, seconds

test('an expired fixture token is re-issued and the fixture moves with it', async () => {
  let signIns = 0;
  const fx = trackSession({ jwt: 'old', session: { access_token: 'old', expires_at: T0 + 3600 },
    newSession: async () => ({ access_token: `new${++signIns}`, expires_at: T0 + 7200 + signIns }) });
  assert.equal(await freshJwt('old', T0 + 3700), 'new1');          // the S22 moment: past expiry
  assert.equal(fx.jwt, 'new1');
  assert.equal(await freshJwt('old', T0 + 3700), 'old');   // the retired string is no longer owned, so no second sign-in
  assert.equal(await freshJwt('new1', T0 + 3700), 'new1');         // fresh token passes untouched
  assert.equal(signIns, 1);
});

test('a token near expiry is stale; one well inside its life is not', () => {
  assert.equal(tokenIsStale({ expires_at: T0 + 3600 }, T0), false);
  assert.equal(tokenIsStale({ expires_at: T0 + 3600 }, T0 + 3600 - REFRESH_MARGIN_S + 1), true);
  assert.equal(tokenIsStale({}, T0), true);
});

test('a token no fixture owns (anon, a raw user JWT) is passed through', async () => {
  assert.equal(await freshJwt('someone-else', T0 + 99999), 'someone-else');
  assert.equal(await freshJwt(null, T0), null);
});

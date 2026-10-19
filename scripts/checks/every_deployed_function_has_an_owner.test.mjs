// The owner check never reads a non-list answer as a result (19 Oct 2026: a 429 body reached owned.map).
import test from 'node:test';
import assert from 'node:assert/strict';
import { mustBeList } from './every_deployed_function_has_an_owner.mjs';

test('an error object from the management API stops the check instead of being measured', () => {
  assert.throws(() => mustBeList('public.function_owner', { message: 'ThrottlerException: Too Many Requests' }), /did not return a list/);
  assert.throws(() => mustBeList('x', 'HTTP 429'), /did not return a list/);
  assert.deepEqual(mustBeList('x', [{ function_slug: 'a' }]), [{ function_slug: 'a' }]);
});

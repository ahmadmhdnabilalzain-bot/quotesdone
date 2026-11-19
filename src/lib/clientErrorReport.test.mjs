// clientErrorReport.test.mjs — what a browser crash report may carry.
// node --test src/lib/clientErrorReport.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanPath, cleanReport, scrubText } from './clientErrorReport.ts';

test('the path loses its query string, fragment and host', () => {
  assert.equal(cleanPath('/ar/me?token=abc#x'), '/ar/me');
  assert.equal(cleanPath('https://quotesdone.com/en/portal?magic=1'), '/en/portal');
  assert.equal(cleanPath(''), '/');
});

test('an email address, a phone number and a token-shaped string are blanked from the message', () => {
  const m = scrubText('failed for a.b@example.com on 971501234567 key sk_live_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345', 300);
  assert.ok(!m.includes('@') && !m.includes('971501234567') && !m.includes('ABCDEFGH'));
});

test('a report keeps exactly message, digest, path and user agent, and caps their length', () => {
  const r = cleanReport({ message: 'ab '.repeat(300), digest: '12345', path: '/en?a=1', user_agent: 'UA/1\n2', cookie: 'sid=1', body: 'secret' });
  assert.deepEqual(Object.keys(r).sort(), ['digest', 'message', 'path', 'user_agent']);
  assert.equal(r.message.length, 300);
  assert.equal(r.path, '/en');
  assert.equal(r.user_agent, 'UA/1 2');
});

test('an empty or non-object report is refused', () => {
  assert.equal(cleanReport(null), null);
  assert.equal(cleanReport({ message: '' }), null);
  assert.equal(cleanReport('boom'), null);
});

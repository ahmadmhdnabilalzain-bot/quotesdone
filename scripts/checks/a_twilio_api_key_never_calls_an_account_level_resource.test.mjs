// A TWILIO API KEY NEVER CALLS AN ACCOUNT-LEVEL RESOURCE (it_engineer, 29 Sep 2026).
// Since the 29 Sep 13:01 UTC rotation the estate's key (twilio_api_key_sid) is a Standard key. Measured that day
// with it: GET /Accounts/{AC}.json 401 (70004), GET /Accounts/{AC}/Keys.json 401 (70004); Balance.json,
// Usage/Records, Messages, Content, Monitor Alerts and Messaging Senders 200. A Standard key cannot read the
// account resource or manage keys, so any call to those must present the auth token (as
// _shared/it_rotate_by_api.ts does for /Keys). This fails if a file builds such a URL and authenticates with the key.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../supabase/functions/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
function* files(dir) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) yield* files(p);
    else if (/\.ts$/.test(n) && !/\.test\.ts$/.test(n)) yield p;
  }
}
// The account resource itself (/Accounts/<x>.json), the key registry (/Keys), sub-accounts (/Accounts.json).
const ACCOUNT_LEVEL = /Accounts\/(?:\$\{[^}]+\}|' \+ \w+ \+ ')\.json|\/Keys[./'`]|\/Accounts\.json/;
const USES_API_KEY = /twilio_api_key_(?:sid|secret)|\bkSid\b|\bks\b.*\bkk\b/;

test('every Account-level Twilio call authenticates with the auth token, never the Standard API key', () => {
  const bad = [];
  for (const f of files(ROOT)) {
    const s = readFileSync(f, 'utf8');
    s.split('\n').forEach((line, i) => {
      if (!ACCOUNT_LEVEL.test(line) || /^\s*\/\//.test(line)) return;
      // the Authorization on the same call must be the account SID + auth token
      const call = s.split('\n').slice(i, i + 3).join('\n');
      if (!/basic\(ac, token\)|twilio_auth_token/.test(call) || USES_API_KEY.test(call)) bad.push(f.slice(ROOT.length) + ':' + (i + 1));
    });
  }
  assert.deepEqual(bad, []);
});

test('the pattern still catches the call it exists for', () => {
  const line = "await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}.json`, { headers: { Authorization: 'Basic ' + btoa(kSid + ':' + kSec) } })";
  assert.ok(ACCOUNT_LEVEL.test(line) && USES_API_KEY.test(line));
  assert.ok(!ACCOUNT_LEVEL.test('https://api.twilio.com/2010-04-01/Accounts/${sid}/Balance.json'));
});

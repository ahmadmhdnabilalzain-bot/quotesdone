// A HELD SUPPLIER IS NEVER TOLD "NOTHING IS NEEDED" (13 Oct 2026, it_engineer, founder ruling 1230).
// Measured on production: a supplier whose licence could not be read (Arabic-only, blank) was e-mailed and WhatsApped at
// Save "your account activates automatically ... Nothing is needed from you", then held as licence_unreadable with no
// further word. supplier_api save_profile must ask for a clearer licence BEFORE the "pending" and "certificate on its
// way" messages whenever the licence name, number or expiry is unread. Reads source only; runs in the checks job.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../supabase/functions/supplier_api/index.ts', import.meta.url), 'utf8');   // raw: comment stripping would eat the rest of any line holding 'https://'
test('an unread licence is asked for again before any "reviewing" or "nothing needed" message', () => {
  for (const f of ['licence_legal_name', 'trade_license_no', 'license_expiry']) assert.ok(src.includes(`!full?.${f} &&`), `the unread test must cover ${f}`);
  const ask = src.indexOf("(decision === 'pending' || !stillNeeded.length) && licUnreadEn");
  const pending = src.indexOf("decision === 'pending'\n", ask + 10), nothing = src.lastIndexOf('Nothing is needed from you');
  assert.ok(ask > 0, 'the clearer-licence branch is missing from save_profile');
  assert.ok(ask < pending && ask < nothing, 'the clearer-licence branch must come before the pending and certificate-on-its-way messages');
});

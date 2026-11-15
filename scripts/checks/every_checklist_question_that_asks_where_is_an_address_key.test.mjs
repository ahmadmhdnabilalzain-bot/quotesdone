// EVERY CHECKLIST QUESTION THAT ASKS WHERE IS AN ADDRESS KEY (13 Nov 2026, sales_engineer; founder ruling 1683; independent
// review of F2, item 2). Only `location` was reduced to the emirate; production's checklists also ask where under
// location_floor, property_location, emirate_location, location_area, emirate_building, property and access, so "Al Barsha 2,
// 3rd floor" reached every matched supplier whole (and the inquiry PDF's brief printed it). The keys a supplier door reduces
// are _shared/site_location.ts ADDRESS_KEYS, derived from production's category_specs by asksWhere on 13 Nov 2026 (396
// fields); a keyless place question is recorded per request (keylessPlaceKeys). This check reads the checklists again and
// fails when a NAMED key whose question asks where is not on the list.
//   node --test scripts/checks/every_checklist_question_that_asks_where_is_an_address_key.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const site = await import(pathToFileURL(path.join(ROOT, 'supabase/functions/_shared/site_location.ts')).href);

test('the classifier knows the questions the review named, and the floor and the size are not places', () => {
  for (const q of ['Which emirate/area, and what floor level for delivery?', 'Property type, emirate/area, and floor level?', 'Which emirate/area is the site in?',
    'Delivery emirate and address?', 'Plot number, community & emirate?', 'Any access constraints the supplier should know?', 'Emirate / area']) assert.ok(site.asksWhere({ question: q }), q);
  for (const q of ['Approximate area (sqm)?', 'Which areas (floor/wall, which rooms)?', 'Installation height / access?', 'Required capacity?']) assert.ok(!site.asksWhere({ question: q }), q);
  assert.equal(site.reducePlace('Al Barsha 2, 3rd floor', 'Dubai').value, 'Dubai, 3rd floor');
});

test('PRODUCTION: every named checklist key whose question asks where is an address key (read-only; skipped without a token)', async (t) => {
  if (!process.env.SUPABASE_ACCESS_TOKEN || process.env.QD_OFFLINE === '1') { t.skip('no management token (offline)'); return; }
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select f->>'key' as key, f->>'question' as question, f->>'question_plain_en' as question_plain_en
    from public.category_specs, jsonb_array_elements(case when jsonb_typeof(fields) = 'array' then fields else '[]'::jsonb end) f`, { readOnly: true });
  assert.ok(rows.length > 300, 'the checklists were not read');
  const asks = [...new Set(rows.filter((r) => r.key && site.asksWhere(r)).map((r) => r.key))].sort();
  assert.deepEqual(asks.filter((k) => !site.ADDRESS_KEYS.includes(k)), [], 'a checklist key asks where and is not in _shared/site_location.ts ADDRESS_KEYS');
});

// THE MARKETING SEAT MEASURES SEARCH, REGISTRATIONS AND COST PER SUPPLIER (marketing, 15 Nov 2026).
// Fails if a cause of "marketing_first_touch 0 rows, no Search Console, Web Analytics 404" comes back:
//   1. the registration stops calling fn_marketing_first_touch_record when the browser kept no tags;
//   2. the Search Console duty leaves the registry, or reads a key other than app_secrets;
//   3. the Web Analytics component renders without its switch, or loads a third-party host;
//   4. the daily KPI duty stops writing the seat's record or loses a KPI the CEO reads.
// Source checks only; the routines run on a local Postgres 16 with their probe.
//   node --test scripts/checks/the_marketing_seat_measures_search_registrations_and_cost_per_supplier.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (s) => s.split('\n').filter((l) => !/^\s*(--|\/\/)/.test(l)).join('\n');

test('a registration with no kept tags still reaches fn_marketing_first_touch_record', () => {
  const reg = code(read('supabase/functions/supplier_api/lib/registration.ts'));
  const body = reg.slice(reg.indexOf('export async function recordFirstTouch'), reg.indexOf('export async function emailProven'));
  assert.ok(body.includes('firstTouchPayload(raw)'), 'the payload is not built by firstTouchPayload');
  assert.doesNotMatch(body, /if \(!\w+ \|\| typeof \w+ !== 'object'\) return/, 'an early return on a missing touch is back');
  assert.match(code(read('supabase/functions/supplier_api/lib/first_touch_payload.ts')), /: \{\};/);
});

test('the Search Console duty is registered and reads its key only from app_secrets', () => {
  const reg = read('supabase/functions/marketing/duties/registry.ts');
  assert.match(reg, /import \{ searchConsole \} from '\.\/search_console\.ts'/);
  assert.match(code(reg), /\bsearchConsole,/);
  const sc = code(read('supabase/functions/marketing/duties/search_console.ts'));
  assert.match(sc, /ctx\.sec\('google_search_console_sa'\)/);
  assert.match(sc, /webmasters\.readonly/);
  assert.doesNotMatch(sc, /Deno\.env\.get\('GOOGLE/, 'the key must come from app_secrets, not the environment');
});

test('Web Analytics renders nothing without its switch and loads only a same-origin script', () => {
  const c = code(read('src/components/WebAnalytics.tsx'));
  assert.match(c, /process\.env\.NEXT_PUBLIC_WEB_ANALYTICS === 'on'/);
  assert.match(c, /if \(!WEB_ANALYTICS_ON\) return null;/);
  assert.match(c, /src="\/_vercel\/insights\/script\.js"/);
  assert.doesNotMatch(c, /https?:\/\//, 'no third-party host');
  assert.match(read('src/app/[locale]/layout.tsx'), /<WebAnalytics \/>/);
});

test('the daily KPI duty writes the seat record with every KPI the CEO reads', () => {
  const sql = code(read('scripts/sql/the_marketing_seat_measures_search_registrations_and_cost_per_supplier_every_day.sql'));
  for (const k of ["'registrations_by_source'", "'cost_per_registered_supplier'", "'posts'", "'articles'", "'search'", "'queries_in_top_10_last_7d'", "'indexed_urls'"]) {
    assert.ok(sql.includes(k), k + ' is missing from fn_marketing_measurement_kpis');
  }
  assert.match(sql, /insert into public\.marketing_duty_record \(duty, period, body\) values \('marketing\.measurement_kpis'/);
  assert.match(sql, /'marketing\.measurement_kpis', 'marketing', interval '1 day', 'fn_marketing_measurement_tick'/);
  assert.match(sql, /revoke execute on function public\.fn_marketing_measurement_reading\(\) from public, anon, authenticated;/);
});

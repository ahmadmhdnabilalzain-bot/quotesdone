// THE FOUNDER'S STANDING DEMO IS NEVER A DEMO LEFTOVER, AND A REAL LEFTOVER NAMES ITS ROWS.
//
// 22 Sep 2026, measured: duty:demo:customers (2) and duty:demo:leads (1) were open for hours, and every
// row they counted was qd-founderdemo-* (seeded 18 Sep by scripts/e2e/founder_demo_tour.mjs and kept on
// the founder's instruction 571). The harness exempted that tag; fn_it_duties' DEMO HYGIENE did not.
// This fails if the canonical fn_it_duties loses the exemption or the ids, or if the harness and the
// duty stop naming the same tag. The probe that proves it on production data is
// scripts/sql/the_founder_demo_is_never_a_demo_leftover_probe.sql.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const noComments = (s) => s.replace(/--.*$/gm, '');

// The file that wins is the LAST MANIFEST entry that defines the routine.
const canonical = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'))
  .filter((f) => { try { return /create or replace function public\.fn_it_duties\(p_r jsonb\)/i.test(read(f)); } catch { return false; } })
  .pop();

test('the canonical fn_it_duties skips the founder demo in both counts and lists the leftover ids', () => {
  assert.ok(canonical, 'no MANIFEST file defines fn_it_duties');
  const body = noComments(read(canonical));
  const hygiene = body.slice(body.indexOf("'customers' t"), body.indexOf("fn_it_duty_settle('demo'"));
  assert.ok(hygiene.length > 0, `${canonical}: DEMO HYGIENE section not found`);
  assert.match(hygiene, /coalesce\(c\.email, ''\) not like 'qd-founderdemo-%'/, `${canonical}: customers count lost the founder-demo exemption`);
  assert.match(hygiene, /coalesce\(l\.email, ''\) not like 'qd-founderdemo-%'/, `${canonical}: leads count lost the founder-demo exemption`);
  assert.match(hygiene, /'ids', to_jsonb\(x\.ids\)/, `${canonical}: the finding no longer names its rows`);
});

test('the harness and the duty name the same founder-demo tag', () => {
  assert.match(read('scripts/e2e/founder_demo_tour.mjs'), /export const TAG = 'founderdemo';/);
  assert.match(read('scripts/e2e/fixtures.mjs'), /const NEVER_SWEPT = new Set\(\[[^\]]*'founderdemo'/);
});

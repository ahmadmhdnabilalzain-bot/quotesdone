// NO SUPPLIER IS E-MAILED A SCORECARD; THE PORTAL STILL SHOWS IT (sales_engineer, 18 Nov 2026; founder ruling 1730). The monthly
// "Your QuotesDone scorecard for <month>" mail read zeros for every supplier; the founder stopped it. FAILS if: the file stops switching
// seat_duty 'sales_engineer.supplier_scorecard' off, or loses the way back on; a file applied AFTER it (MANIFEST, then pending, in apply
// order) switches the duty on again or schedules the tick on its own clock; the portal's scorecard action stops reading fn_supplier_scorecard.
//   node --test scripts/checks/no_supplier_is_e_mailed_a_scorecard.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending, applyState } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const FILE = 'scripts/sql/no_supplier_is_e_mailed_a_scorecard_the_portal_still_shows_it.sql';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

test('the file switches the scorecard e-mail off by its duty switch, and says how to turn it back on', () => {
  const src = code(R(FILE));
  assert.match(src, /update public\.seat_duty set enabled = false,[\s\S]+?where duty = 'sales_engineer\.supplier_scorecard'/);
  assert.match(R(FILE), /-- TO TURN THE E-MAIL BACK ON[\s\S]+?update public\.seat_duty set enabled = true,[\s\S]+?where duty = 'sales_engineer\.supplier_scorecard';/);
  assert.doesNotMatch(src, /drop\s+function|drop\s+table|delete\s+from/i, 'the switch-off drops something');
  assert.match(src, /'PROBE OK: the scorecard e-mail is switched off/);
  const st = applyState(FILE);
  assert.ok(st.applied !== (st.note !== null), 'exactly one of a MANIFEST line and a pending note');
});

test('nothing applied after it switches the duty on again or gives the tick its own clock', () => {
  const order = manifestWithPending();
  const at = order.indexOf(FILE);
  assert.ok(at >= 0, 'the file is neither applied nor pending');
  const on = /update\s+public\.seat_duty\s+set\s+enabled\s*=\s*true[^;]*'sales_engineer\.supplier_scorecard'|'sales_engineer\.supplier_scorecard'[^;]*on conflict[^;]*enabled\s*=\s*(true|excluded\.enabled)/i;
  const ownClock = /cron\.schedule\([^;]*fn_sales_engineer_supplier_scorecard_tick/i;
  for (const f of order.slice(at + 1)) {
    let t; try { t = code(R(f)); } catch { continue; }
    assert.doesNotMatch(t, on, `${f} switches the scorecard e-mail back on (founder ruling 1730)`);
    assert.doesNotMatch(t, ownClock, `${f} schedules the scorecard tick on its own clock`);
  }
});

test('the portal still shows the scorecard: it is computed on demand, not read from the e-mail duty', () => {
  const market = R('supabase/functions/supplier_portal/actions/market.ts');
  assert.match(market, /if \(action === 'scorecard'\)[\s\S]{0,200}admin\.rpc\('fn_supplier_scorecard', \{ p_lead: supId \}\)/);
});

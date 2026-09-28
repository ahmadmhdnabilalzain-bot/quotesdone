// supplier_performance keys on leads(id); supplier_score does not. Seat: sales_engineer. 28 Sep 2026.
// A score for a removed lead aborted the whole day's scoring 4 times running (FK violation). The newest
// definition of fn_sales_engineer_supplier_performance must join leads before it inserts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const DEF = /create\s+or\s+replace\s+function\s+public\.fn_sales_engineer_supplier_performance\s*\(/i;
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
const pending = readdirSync('scripts/sql/pending').filter((f) => f.endsWith('.txt')).map((f) => `scripts/sql/${f.replace(/\.txt$/, '.sql')}`);
const newest = [...manifest, ...pending].filter((f) => existsSync(f) && DEF.test(readFileSync(f, 'utf8'))).pop();

test('the supplier score reads only suppliers whose lead exists', () => {
  assert.ok(newest, 'no file defines fn_sales_engineer_supplier_performance');
  const body = readFileSync(newest, 'utf8').split(DEF)[1].split('$function$;')[0];
  assert.match(body, /join\s+public\.leads\s+\w+\s+on\s+\w+\.id\s*=\s*s\.lead_id/i, `${newest}: supplier_score is read without the leads join`);
});

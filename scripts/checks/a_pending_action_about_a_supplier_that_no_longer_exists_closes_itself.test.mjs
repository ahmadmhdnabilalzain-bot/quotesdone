// A PENDING ACTION ABOUT A SUPPLIER THAT NO LONGER EXISTS CLOSES ITSELF (10 Nov 2026, customer_support; item 10 of the
// supplier-journey audit's report, #1901).
//
// Two pending document_read_stuck actions named deleted suppliers (151660, 153580), and on 10 Nov every one of the 156
// pending actions naming a supplier did (doc_trades_held 149, vision_trades_confirm 5, document_read_stuck 2): nothing closed
// an action when its lead went. This fails if the rule stops closing only PENDING, non-handoff actions whose lead is gone, if
// the statement trigger on leads stops calling it, or if the heartbeat step (fn_supplier_doc_reading_escalate) stops running
// it. Bodies are read from the definition that wins the apply order, -- comments removed. Behaviour: the probe of the same
// name (rolled back on production: 156 of 156 closed, the control kept).
//   node --test scripts/checks/a_pending_action_about_a_supplier_that_no_longer_exists_closes_itself.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const SQL = 'scripts/sql/';
const FIX = 'a_pending_action_about_a_supplier_that_no_longer_exists_closes_itself.sql';
const manifest = readFileSync(SQL + 'MANIFEST.txt', 'utf8').split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
  .map((l) => l.replace(/^scripts\/sql\//, ''));
const pending = (f) => existsSync(SQL + 'pending/' + f.replace(/\.sql$/, '.txt'));
const defRe = (fn) => new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${fn}\\s*\\(`, 'i');
function winning(fn) {
  const defines = (f) => existsSync(SQL + f) && defRe(fn).test(readFileSync(SQL + f, 'utf8'));
  if (pending(FIX) && defines(FIX)) return FIX;
  const listed = manifest.filter(defines);
  assert.ok(listed.length, `no file defines ${fn}`);
  return listed[listed.length - 1];
}
function body(fn) {
  const src = readFileSync(SQL + winning(fn), 'utf8');
  const open = src.search(defRe(fn));
  const m = /\bas\s+(\$[a-z_]*\$)/i.exec(src.slice(open));
  assert.ok(m, `${fn} has no dollar-quoted body`);
  const start = open + m.index + m[0].length;
  return src.slice(start, src.indexOf(m[1], start)).replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
}

test('the rule closes only a pending, non-handoff action whose supplier lead does not exist, and deletes nothing', () => {
  const b = body('fn_agent_actions_close_for_gone_suppliers');
  assert.match(b, /a\.status = 'pending' and a\.kind <> 'handoff'/);
  assert.match(b, /coalesce\(nullif\(a\.detail ->> 'supplier_id', ''\), case when a\.target_table = 'leads' then a\.target_id end\)/);
  assert.match(b, /not exists \(select 1 from public\.leads l where l\.id = n\.sid::bigint\)/);
  assert.match(b, /set status = 'dismissed', decided_at = now\(\), decided_by = 'sales_engineer'/);
  assert.doesNotMatch(b, /delete from/i, 'a rule that closes must never delete the record');
});

test('a delete of leads closes its actions in the same statement', () => {
  const src = readFileSync(SQL + winning('fn_leads_gone_closes_its_pending_actions'), 'utf8');
  assert.match(src, /create trigger z90_leads_gone_closes_its_pending_actions after delete on public\.leads\s+referencing old table as gone for each statement/);
  assert.match(body('fn_leads_gone_closes_its_pending_actions'), /fn_agent_actions_close_for_gone_suppliers\(array\(select g\.id from gone g\)\)/);
  for (const sig of ['fn_agent_actions_close_for_gone_suppliers(bigint[])', 'fn_leads_gone_closes_its_pending_actions()'])
    assert.ok(src.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), `${sig} is not closed to the API roles`);
});

test('the heartbeat step runs the rule for anything the trigger did not see', () => {
  assert.match(body('fn_supplier_doc_reading_escalate'), /^\s*declare[\s\S]*?begin perform public\.fn_agent_actions_close_for_gone_suppliers\(null\);/);
});

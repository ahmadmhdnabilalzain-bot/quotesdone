// Instr 1013 item 3 (marketing): the recruitment plans for trades below ten suppliers may reorder the invitation
// queue and give it an English trade variant, and nothing else. Fails if the file starts touching a brake (the go
// switch, the daily cap, the sender), lets a variant carry Arabic or lose its link, or puts plans ahead of the
// sales engineer's recruit leads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../sql/marketing_plans_recruitment_for_every_trade_below_ten_suppliers.sql', import.meta.url), 'utf8');
const code = sql.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n');

test('no brake is written or redefined', () => {
  assert.doesNotMatch(code, /update\s+public\.app_secrets|insert\s+into\s+public\.app_secrets/i);
  assert.doesNotMatch(code, /function\s+public\.(enqueue_supplier_invites|fn_supplier_invite_eligible|fn_invite_ramp)\b/i);
  assert.doesNotMatch(code, /insert\s+into\s+public\.notifications/i);
});

test('a variant is English and keeps its link, by constraint', () => {
  assert.match(code, /invite_body like '%\{\{link\}\}%' and invite_body !~ '\[؀-ۿ\]'/);
});

test('recruit leads stay first, then plan rank; Arabic leads keep the Arabic copy', () => {
  assert.match(code, /order by r\.target_rank, r\.plan_rank,/);
  assert.match(code, /then 0\s+when pl\.rank is not null then 1 else 2 end as target_rank/);
  assert.match(code, /case when e\.lang = 'ar' then v_subj_ar else coalesce\(e\.plan_subject, v_subj\) end/);
});

test('every source row records its lookup', () => {
  assert.match(code, /http_status\s+integer not null/);
  assert.match(code, /checked_at\s+timestamptz not null/);
});

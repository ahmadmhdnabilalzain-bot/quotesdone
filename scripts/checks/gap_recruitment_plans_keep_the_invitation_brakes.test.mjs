// Instr 1013 item 3: marketing ranks the trades below ten suppliers and writes English variants; the sales
// engineer's queue (instr 625) reads that ranking. Fails if marketing's file starts writing the queue or a brake,
// if a variant can carry Arabic or lose its link, if the queue regains an Arabic path, or if planned leads jump
// ahead of the sales engineer's recruit leads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = f => readFileSync(new URL(`../sql/${f}.sql`, import.meta.url), 'utf8')
  .split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n');
const mkt = read('marketing_plans_recruitment_for_every_trade_below_ten_suppliers');
const queue = read('the_invitation_queue_reads_marketings_gap_ranking_and_is_always_english');

test('marketing writes no queue and no brake', () => {
  for (const code of [mkt, queue]) {
    assert.doesNotMatch(code, /update\s+public\.app_secrets|insert\s+into\s+public\.app_secrets/i);
    assert.doesNotMatch(code, /function\s+public\.(enqueue_supplier_invites|fn_supplier_invite_eligible|fn_invite_ramp)\b/i);
    assert.doesNotMatch(code, /insert\s+into\s+public\.notifications/i);
  }
  assert.doesNotMatch(mkt, /function\s+public\.fn_supplier_invite_candidates/i);
});

// 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); the constraint was turned round
// in the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer.sql.
test('a variant is English and carries no link, by constraint', () => {
  const noLink = read('the_supplier_invitation_carries_no_link_and_a_reply_with_trades_reaches_the_sales_engineer');
  assert.match(noLink, /check \(invite_body !~\* '\(https\?:\/\/\|www\\\.\|\\\{\\\{link\\\}\\\}\)' and invite_body !~ '\[؀-ۿ\]' and invite_subject !~ '\[؀-ۿ\]'\)/);
});

test('the queue has no Arabic path', () => {
  assert.doesNotMatch(queue, /invite_(subject|body)_ar|\/ar\/portal|'ar'/);
  assert.match(queue, /'en'::text as lang/);
});

test('recruit leads stay first, then marketing plan rank', () => {
  assert.match(queue, /order by r\.target_rank, r\.plan_rank,/);
  assert.match(queue, /then 0\s+when pl\.rank is not null then 1 else 2 end as target_rank/);
  assert.match(queue, /from public\.marketing_gap_recruitment_plan/);
});

test('every source row records its lookup', () => {
  assert.match(mkt, /http_status\s+integer not null/);
  assert.match(mkt, /checked_at\s+timestamptz not null/);
});

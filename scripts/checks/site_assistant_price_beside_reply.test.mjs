// customer_support, 12 Oct 2026 (sandbox run f4294be8, S13). The widget's price reasoning (two model calls,
// 7-13 s) ran BEFORE the reply's own reasoning, so "How much does it cost to reveal a supplier?" took 37-44 s and
// once died at 33 s with WORKER_RESOURCE_LIMIT. The reply is now composed while the price is reasoned. This check
// fails if the reply is again started only after the price lookup has been awaited.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../../supabase/functions/site_assistant/index.ts', import.meta.url), 'utf8');

test('the widget reply is started before the price reasoning is awaited', () => {
  const started = src.indexOf('const pFirst = reasoningOpen ? compose(');
  const awaited = src.indexOf('await pPrice;');
  assert.ok(started > 0, 'the reply is no longer started beside the price reasoning');
  assert.ok(awaited > started, 'the price reasoning is awaited before the reply starts');
  assert.ok(src.includes('const pPrice = (async'), 'priceGuidanceFor must run inside pPrice, not inline before the reply');
});

// 18 Oct 2026 (seat it_engineer). The IT digest (notifications 101206) told the founder "Only you can decide this" on
// a held review and an unregistered author model - both technical. The digest emails an item only when its finding
// matches an it_founder_decision_class row with to_founder; this asserts that table can never again send a technical
// class to him:
//   1. the schema mirror (= production) carries the CHECK that ties to_founder to money / destructive change / his fact;
//   2. the file that sets the rows leaves no review_independence or deliberation_independence class with to_founder;
//   3. the gateway never records a closed rehearsal window as a review hold, and the drill never judges author 'unknown'.
// With a token (local runs) it also reads production: no to_founder row outside the three categories.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const FILE = 'scripts/sql/a_technical_item_is_never_a_decision_for_the_founder.sql';
const CATS = /founder_category\s*=\s*ANY\s*\(ARRAY\['money'::text,\s*'destructive_production_change'::text,\s*'fact_only_he_holds'::text\]\)/i;

const PENDING = existsSync('scripts/sql/pending/a_technical_item_is_never_a_decision_for_the_founder.txt');

test('production refuses a founder decision class without one of his three categories', (t) => {
  if (PENDING) return t.skip('the file is pending apply; the mirror is asserted once it is applied');
  const mirror = readSchemaMirror();
  const i = mirror.indexOf('it_founder_decision_class_only_his_categories');
  assert.ok(i >= 0, 'the mirror has no it_founder_decision_class_only_his_categories constraint');
  assert.match(mirror.slice(i, i + 400), CATS, 'the constraint must allow to_founder only for money, destructive_production_change, fact_only_he_holds');
});

test('no review- or deliberation-independence class routes to the founder', () => {
  const src = readFileSync(FILE, 'utf8');
  assert.match(src, /set to_founder = false, founder_category = null,[\s\S]*?'duty:review_independence:%', 'duty:deliberation_independence:%'/,
    `${FILE}: both independence families must be set to_founder = false`);
});

test('a closed rehearsal window is never a review hold; a drill never judges an unknown author', () => {
  const gw = readFileSync('supabase/functions/ai_gateway/index.ts', 'utf8');
  assert.match(gw, /\^\(founder_hold\|exception\|rehearsal_window_closed\):/, 'ai_gateway must not record a rehearsal_window_closed refusal as a review_hold');
  const drill = readFileSync('scripts/e2e/expert_conversation_rehearsal.mjs', 'utf8');
  assert.doesNotMatch(drill, /\|\|\s*'unknown'/, 'the drill must not send counterpart_model unknown to the judge');
});

test('live: every to_founder row names one of his categories (skipped without a token)', async (t) => {
  const tokFile = 'C:/Users/Opera/.supabase/access-token';
  if (PENDING) return t.skip('the file is pending apply');
  if (!process.env.SUPABASE_ACCESS_TOKEN && !existsSync(tokFile)) return t.skip('no management token');
  const { mgmtRead, PROD_REF } = await import('../lib/qd_guard.mjs');
  const rows = await mgmtRead(PROD_REF, `select issue_key_like from public.it_founder_decision_class
    where to_founder and (founder_category is null or issue_key_like ~ '(independence|review|model|registry)')`);
  assert.deepEqual(rows, [], `technical classes still route to the founder: ${JSON.stringify(rows)}`);
});

// Every conversation is a case, and a reply works from the case summary (founder ruling 1635, 11 Nov 2026).
// Offline. Fails if the case SQL loses its closed writers or its append-only history, if the reply stops carrying the
// case block, or if WhatsApp stops reading the case. The behaviour is proved by _shared/support_case_memory.test.ts and,
// in SQL, by the _probe.sql file (run on a local Postgres stub, 11 Nov 2026). Assigned: it_engineer for customer_support.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(ROOT + p, 'utf8');
const NAME = 'scripts/sql/every_support_case_keeps_a_summary_and_the_reply_reads_it';

test('the case SQL: every writer pinned and closed, the history append-only, nothing deleted', () => {
  const s = read(NAME + '.sql');
  for (const sig of ['fn_support_case_summary_write(text, integer, jsonb, text, text, text, text, jsonb)', 'fn_support_open_cases(text, text, text, text)',
    'fn_support_case_route(bigint, text, text, text, text, text)', 'fn_support_case_summary_backup_enqueue(bigint)']) {
    assert.ok(s.includes('revoke execute on function public.' + sig + ' from public, anon, authenticated;'), sig);
  }
  assert.equal((s.match(/security definer set search_path to 'public', 'pg_temp'/g) ?? []).length, 4);
  assert.match(s, /before update or delete on public\.support_case_summary_version/);
  assert.match(s, /create policy support_case_summary_version_service_role_only/);
  assert.doesNotMatch(s, /\bdelete from\b|\btruncate\b/i);
  assert.match(s, /'case_summary_backup_enabled'\), ''\) <> 'true' then return false/, 'the Dropbox seam stays off until its renderer exists');
  assert.match(read(NAME + '_probe.sql'), /raise exception 'CHK<<PROBE OK/);
});

// CASES ON EVERY CHANNEL (customer_support, 11 Nov 2026; ruling 1635 is per person, not per channel). Each door's turn
// loads the case ONCE before its model call (_shared/case_context.ts loadCaseContext), gives the model what that returns,
// and records the exchange ONCE after the reply that was really given. The behaviour is _shared/case_context.test.ts;
// this fails if a door stops calling either, or calls the model with its own sys/history instead of the case's.
const DOORS = [
  { door: 'website widget', file: 'supabase/functions/site_assistant/index.ts', model: 'await answerFromBrief({',
    uses: [/sys: kase\.sys/, /input: \[\.\.\.kase\.past,/], after: /if \(reply\) recordCaseExchange\(tradeDeps, kase, \{ theirMessage: message, ourReply: reply/ },
  { door: 'customer portal chat', file: 'supabase/functions/sales_engineer/actions/portal.ts', model: 'await answerFromBrief({',
    uses: [/sys: kase\.sys/, /input: \[\.\.\.kase\.past,/], after: /if \(reply\) recordCaseExchange\(defaultDeps\(admin, 'sales_engineer'\), kase, \{ theirMessage: message, ourReply: reply/ },
  { door: 'supplier quotation chat', file: 'supabase/functions/supplier_api/actions/quote_review_chat.ts', model: 'await aiReply(',
    uses: [/aiReply\(defaultDeps\(admin, 'supplier_api'\), \{ \.\.\.kase\.reply,/], after: /if \(r\.reply\) recordCaseExchange\(defaultDeps\(admin, 'supplier_api'\), kase,/ },
  { door: 'e-mail reply', file: 'supabase/functions/email_triage/index.ts', model: 'await aiReply(',
    uses: [/aiReply\(deps, \{ \.\.\.kase\.reply,/, /context: \{ audience, language: lang,[^\n]*\.\.\.kase\.context \}/], after: /recordCaseExchange\(deps, kase, \{ theirMessage: q, ourReply: text, subject \}\)/ },
];
for (const d of DOORS) {
  test(`the ${d.door} reads the case before its model call and records it after the reply`, () => {
    const s = read(d.file);
    assert.match(s, /import \{ loadCaseContext, recordCaseExchange \} from '[./]+_shared\/case_context\.ts';/, `${d.file}: does not import the case helpers`);
    const load = s.indexOf('await loadCaseContext(');
    const call = s.indexOf(d.model, load);
    assert.ok(load > 0, `${d.file}: never loads the case`);
    assert.equal(s.indexOf('await loadCaseContext(', load + 1), -1, `${d.file}: loads the case more than once`);
    assert.ok(call > load, `${d.file}: the case is not loaded before the model call`);
    for (const u of d.uses) assert.match(s, u, `${d.file}: the model call does not read the case (${u})`);
    const rec = s.search(d.after);
    assert.ok(rec > call, `${d.file}: the exchange is not recorded after the reply`);
  });
}
test('email: the case hooks sit inside the answer, after the reply went, and never before the supplier mailbox reading of #1939', () => {
  const s = read('supabase/functions/email_triage/index.ts');
  assert.ok(s.indexOf("fn_inbox_send', { p_id: m.id") < s.indexOf('recordCaseExchange(deps, kase'), 'the summary is written only after the reply went');
  assert.ok(s.indexOf('readSupplierMailbox(admin, deps, m)') > s.indexOf('recordCaseExchange(deps, kase'), 'the case work lives in answer(), not in the mailbox reading');
});

test('the reply reads the case: aiReply carries the block in its cached prefix, WhatsApp reads and records the case', () => {
  const ai = read('supabase/functions/_shared/ai_reply.ts');
  assert.match(ai, /aiSystem\(\{ \.\.\.r, facts: undefined \}, replyLang\) \+ \(withCase \? '\\n\\n' \+ caseBlock\(r\.caseMemory!\) : ''\)/);
  assert.match(ai, /withCase \? caseTurns\(r\.conversation \?\? \[\]\)/);
  const say = read('supabase/functions/wa_inbound/say.ts');
  assert.match(say, /await waCaseMemory\(t, aud, lang\)/);
  assert.match(say, /if \(!signal && said\?\.text\) recordWaExchange\(caseMem, t, said\.text\)/);
});

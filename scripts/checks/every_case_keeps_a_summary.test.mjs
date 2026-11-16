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
  // the seam was off "until its renderer exists"; the renderer is the text file below (11 Nov 2026), and the seam's
  // canonical definition is now a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql
  assert.match(read(NAME + '_probe.sql'), /raise exception 'CHK<<PROBE OK/);
});

// THE CASE FILE IN DROPBOX (ruling 1635, customer_support, 11 Nov 2026). The request Dropbox receives is
// dropbox_backup/case_summary.test.ts; the queue rules are the _probe.sql. This fails if the enqueue goes back to a row per
// version (the daily listing check would read the older ones as changed), to a path nothing renders, or to a PDF.
const FILE = 'scripts/sql/a_case_summary_is_a_text_file_in_the_persons_dropbox_folder';
test('a case summary is one text file per case in the person\'s folder, re-queued on every version', () => {
  const s = read(FILE + '.sql');
  assert.match(s, /v_base \|\| 'cases\/' \|\| c\.case_ref \|\| '\.md', 'pending', 'CASE:' \|\| c\.case_ref\)/, 'not <folder>/cases/<case>.md, one row per case');
  assert.match(s, /on conflict \(dedupe_key\) do update\n\s+set status = 'pending', bucket = null, path = null, upload_state = null, error = null, attempts = 0,/,
    'a new version does not send the case back to be rendered');
  assert.match(s, /'case_summary_backup_enabled'\), ''\) = 'false' then return false/, 'the switch is a brake: on unless set to false');
  assert.match(s, /revoke execute on function public\.fn_support_case_summary_backup_enqueue\(bigint\) from public, anon, authenticated;/);
  assert.match(read(FILE + '_probe.sql'), /raise exception 'CHK<<PROBE OK %>>'/);
  const row = read('supabase/functions/dropbox_backup/row.ts');
  assert.match(row, /if \(row\.gen_kind === 'case_summary'\) return await caseSummaryFile\(admin, String\(row\.gen_ref\)\);/, 'dropbox_backup does not render the case file');
  assert.doesNotMatch(read('supabase/functions/_shared/case_dropbox.ts'), /pdf_native/, 'the case file is text, never a PDF waiting on a renderer');
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
    // the case may be read beside another read in one Promise.all (the supplier quotation chat reads his account too, supplier_known.ts)
    const load = s.search(/await (Promise\.all\(\[)?loadCaseContext\(/);
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
  // 16 Nov 2026 (audit WHO_KNOWS_WHAT item 2): the block is carried for one case with a summary OR several open cases with their
  // promises (hasCaseBlock); only one case's summary cuts the conversation to its last turns (withCase)
  assert.match(ai, /aiSystem\(\{ \.\.\.r, facts: undefined \}, replyLang\) \+ \(hasCaseBlock\(r\.caseMemory\) \? '\\n\\n' \+ caseBlock\(r\.caseMemory!\) : ''\)/);
  assert.match(ai, /const withCase = worksFromOneCase\(r\.caseMemory\);/);
  assert.match(ai, /withCase \? caseTurns\(r\.conversation \?\? \[\]\)/);
  const say = read('supabase/functions/wa_inbound/say.ts');
  // 12 Nov 2026 (final audit W3): the read starts with the turn and the reply waits only for it; the case step runs once the
  // reply is THE turn's reply (adopt), so an adopted speculative draft is recorded and a discarded one never is
  assert.match(say, /void startWaCase\(t\);/);
  assert.match(say, /await waCaseMemory\(t, aud\)/);
  // and (review of 12 Nov 2026) only once, at the turn's end, for a reply that was DELIVERED, with the words really sent
  assert.match(say, /if \(said\?\.text\) recordOnAdopt\.set\(said, \(sent: string\) => \{\n\s+recordWaExchange\(t, aud, lang, sent, conv\);/);
  assert.match(say, /if \(after\) \{ recordOnAdopt\.delete\(r\); t\.caseAfter = after; t\.deliveredReply = undefined; \}/);
  assert.match(read('supabase/functions/wa_inbound/index.ts'), /if \(t\.caseAfter && t\.deliveredReply\) t\.caseAfter\(t\.deliveredReply\.replace\(/);
});

// THE PROMISE LEDGER (customer_support, 11 Nov 2026). The behaviour is the _probe.sql (a dated promise flagged once to its
// seat, an undated one assumed, a restated one not doubled, a quotes promise kept by the notice that delivered the quotes,
// the owner alone marking the rest); this fails if the file loses one of the pieces that make that possible.
const LEDGER = 'scripts/sql/every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due';
test('the promise ledger: the one summary writer records every stated promise, and an hourly duty flags the owning seat', () => {
  const s = read(LEDGER + '.sql');
  assert.match(s, /perform public\.fn_support_case_promises_record\(c\.case_id, v_next, p_summary -> 'promised', p_written_by\);\n  perform public\.fn_support_case_summary_backup_enqueue/,
    'the summary writer does not record the promises it writes');
  assert.match(s, /unique \(case_id, promise_key\)/, 'a restated promise would become a second row');
  assert.match(s, /owner_seat text not null check \(owner_seat in \('customer_support', 'sales_engineer'\)\)/);
  assert.match(s, /'support\.promise_due', 'support_case_promise', r\.id::text/, 'the flag is not a handoff to the owning seat');
  assert.match(s, /from unnest\(array\['customer_support', 'sales_engineer'\]\) as s/, 'the handoff kind is not registered for both answering seats');
  assert.match(s, /pr\.flagged_at is null and pr\.is_demo = v_fx/, 'a promise is flagged more than once, or a fixture is flagged as real');
  assert.match(s, /n\.type = 'new_quote' and n\.status = 'sent'/, 'a quotes promise is not kept by the delivered quotes');
  assert.match(s, /insert into public\.ceo_brief_line \(subject_key, line, source\)/, 'the count is not in the CEO brief');
  assert.match(s, /values \('customer_support\.promise_watch', 'customer_support', interval '1 hour', 'fn_support_case_promise_watch'/);
  assert.match(s, /perform public\.fn_seat_duty_isolate\('customer_support\.promise_watch'\)/, 'the duty has no staggered job of its own');
  assert.match(s, /\('support_case_promise', true, 'customer'/, 'the ledger is not in the daily export (ruling 1634)');
  assert.doesNotMatch(s, /\bdelete from\b|\btruncate\b/i, 'nothing is deleted (ruling 1634)');
  assert.match(read(LEDGER + '_probe.sql'), /raise exception 'CHK<<PROBE OK %>>'/);
  const ts = read('supabase/functions/_shared/support_case_memory.ts');
  assert.match(ts, /const s = stampPromises\(checked, \{ previousText: o\.memory\.summaryText \}\);/, 'the summary step does not give promises their due time');
});

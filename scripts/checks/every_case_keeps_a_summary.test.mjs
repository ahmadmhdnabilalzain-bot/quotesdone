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

test('the reply reads the case: aiReply carries the block in its cached prefix, WhatsApp reads and records the case', () => {
  const ai = read('supabase/functions/_shared/ai_reply.ts');
  assert.match(ai, /aiSystem\(\{ \.\.\.r, facts: undefined \}, replyLang\) \+ \(withCase \? '\\n\\n' \+ caseBlock\(r\.caseMemory!\) : ''\)/);
  assert.match(ai, /withCase \? caseTurns\(r\.conversation \?\? \[\]\)/);
  const say = read('supabase/functions/wa_inbound/say.ts');
  assert.match(say, /await waCaseMemory\(t, aud, lang\)/);
  assert.match(say, /if \(!signal && said\?\.text\) recordWaExchange\(caseMem, t, said\.text\)/);
});

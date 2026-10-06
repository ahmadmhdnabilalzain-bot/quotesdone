// EVERY MODEL A FALLBACK CHAIN NAMES IS IN THE REGISTRY (6 Oct 2026, customer_support; final check, ledger 1119).
//
// Measured 6 Oct 2026: model_fallback_chain 'whatsapp_conversation' named google/gemini-3-flash (in no model_registry
// row) and anthropic/claude-sonnet-5, a month after the founder's matrix moved WhatsApp to luna with Gemini 3.8 Flash
// behind (founder_instruction 1108). Nothing compared the chain with the registry, so it drifted unseen.
//
// ONE aborted transaction per run, through scripts/lib/safe_replay.mjs: every pending SQL file that writes
// model_fallback_chain is replayed first (what the PR applies at merge), then a block that always raises with its
// verdict. A second run inserts a chain row naming an unregistered model and must FAIL - the guard is proved to bite.
// Needs a management token; without one the tests report skipped.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = join(REPO, 'scripts', 'sql');
const REF = 'htdblwldjkcgjvmqkbeh';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const pending = () => readdirSync(join(SQL, 'pending'))
  .map((n) => n.replace(/\.txt$/, '.sql'))
  .filter((n) => existsSync(join(SQL, n)) && /insert\s+into\s+public\.model_fallback_chain|update\s+public\.model_fallback_chain/i
    .test(readFileSync(join(SQL, n), 'utf8')))
  .sort();

// An active model rung must name a registered, active model. A deterministic rung names no model.
const VERDICT = `
do $chk$
declare v text;
begin
  select string_agg(c.purpose || ' rung ' || c.rung || ' ' || c.model, '; ' order by c.purpose, c.rung) into v
    from public.model_fallback_chain c
   where c.active and c.kind = 'model'
     and not exists (select 1 from public.model_registry r where r.model_id = c.model and r.active);
  if v is null then raise exception 'CHK<<PROBE OK every chain model is registered>>'; end if;
  raise exception 'CHK<<PROBE FAILED not in the registry (or inactive): %>>', v;
end $chk$;`;

async function run(query) {
  let text = '';
  try { await replaySql(query, { ref: REF, label: 'the fallback-chain replay' }); } catch (e) { if (e.throttled) throw e; text = String(e.body ?? e.message); }
  const m = text.match(/CHK<<(.*?)>>/s);
  assert.ok(m, `no verdict: ${text.slice(0, 500)}`);
  return m[1];
}
const replay = () => pending().map((n) => readFileSync(join(SQL, n), 'utf8')).join('\n;\n');

test('every model an active fallback chain names is a registered, active model', { skip: !hasToken }, async () => {
  const v = await run(replay() + '\n;\n' + VERDICT);
  console.log('replayed:', pending().join(', ') || 'none', '|', v);
  assert.match(v, /^PROBE OK /, v);
});

test('a chain row naming an unregistered model fails', { skip: !hasToken }, async () => {
  const v = await run(replay() + `\n;\ninsert into public.model_fallback_chain (purpose, rung, model, kind, rationale, authority)
    values ('zz_probe_chain', 1, 'zz/not-a-model', 'model', 'probe', 'probe');\n` + VERDICT);
  assert.match(v, /zz_probe_chain rung 1 zz\/not-a-model/, v);
});

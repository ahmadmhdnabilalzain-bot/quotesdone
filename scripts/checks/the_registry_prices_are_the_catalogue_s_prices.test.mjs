// THE REGISTRY PRICES ARE THE CATALOGUE'S PRICES (it_engineer, 23 Sep 2026; rewritten 5 Oct 2026, follow-up 28).
//
// UNTIL 5 OCT 2026 this check re-read https://openrouter.ai/api/v1/models and failed whenever a price or a context
// length the SQL files claimed differed from it. The provider moves prices without telling us, so it went red on
// every move (glm 28 Sep, glm again, deepseek 30 Sep, deepseek again 5 Oct) and a person wrote one more correcting file
// each time. A check that fails on somebody else's price list is a check about the provider, not about the estate.
//
// WHAT IS ASSERTED NOW (scripts/sql/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.sql):
//   1. THE SYNC IS FRESH: the it_engineer duty model_catalogue last succeeded less than 36 hours ago, and NOTHING is
//      pending - no catalogue change is held open. A held change is one the rule refused to apply by itself (a model of
//      the founder's matrix, or a jump over 20%); it stays red here until fn_model_catalogue_reason gives it a reason
//      and the next sync applies it. So a provider move turns this red only when it needs a decision, and a stalled
//      sync turns it red whatever the prices do.
//   2. THE RULE: fn_model_catalogue_decide, replayed on synthetic ZZ DEMO rows (pure, writes nothing), still applies a
//      drift of at most 20% on a non-matrix model, holds a bigger one, holds ANY change on a matrix model, holds a value
//      it cannot measure drift from, flags a model the catalogue lacks, and prices a ':online' variant as its base.
//   3. The matrix probe states no price (the catalogue moves prices; the registry is the one place they live).
//   4. The capabilities the routing relies on are the ones the catalogue advertises (network; unchanged).
//
// 1 and 2 need SUPABASE_ACCESS_TOKEN. The tokenless checks job reports them skipped; the parity job runs this with
// REGISTRY_SYNC_REQUIRE_LIVE=1, where a missing token fails. Before the file is applied (it is pending until merge) 2
// replays the pending file inside an aborted transaction, and 1 says it is not applied yet instead of failing.
//
//   node --test scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const REF = 'htdblwldjkcgjvmqkbeh';
const SYNC_SQL = 'scripts/sql/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.sql';
const PENDING_NOTE = 'scripts/sql/pending/the_it_engineer_syncs_the_model_registry_from_the_catalogue_every_day.txt';
const MATRIX_PROBE = 'scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql';
const CATALOGUE = 'https://openrouter.ai/api/v1/models';
const FRESH_HOURS = 36;

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  return existsSync(p) ? readFileSync(p, 'utf8').trim() : null;
}
const pending = () => existsSync(join(REPO, PENDING_NOTE));

// Returns the CHK<<...>> text of an error, or the JSON rows.
async function db(query) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }), signal: AbortSignal.timeout(120_000),
    });
    const text = await res.text();
    if ((res.status === 429 || res.status >= 500) && attempt < 6) { await new Promise((r) => setTimeout(r, 2000 * 2 ** attempt)); continue; }
    const m = text.match(/CHK<<(.*?)>>/s);
    if (m) return m[1].replace(/\\"/g, '"');
    assert.ok(res.ok, `management API HTTP ${res.status}: ${text.slice(0, 400)}`);
    return JSON.parse(text);
  }
}

test('a management token is present where the sync must be verified',
  { skip: process.env.REGISTRY_SYNC_REQUIRE_LIVE !== '1' && 'no REGISTRY_SYNC_REQUIRE_LIVE: the parity job verifies it' }, () => {
  assert.ok(token(), 'SUPABASE_ACCESS_TOKEN is missing: the model catalogue sync was NOT verified');
});

test('the model catalogue sync succeeded in the last 36 hours and holds nothing open', { skip: !token() && 'no management token' }, async () => {
  const [r] = await db(`select to_regclass('public.model_catalogue_change') is not null as built,
      (select max(started_at) from public.agent_runs where agent = 'it_engineer' and status = 'ok'
          and counts->>'job' = 'duty:model_catalogue') as last_ok,
      (select extract(epoch from now() - max(started_at)) / 3600 from public.agent_runs where agent = 'it_engineer'
          and status = 'ok' and counts->>'job' = 'duty:model_catalogue') as hours`);
  if (!r.built) {
    assert.ok(pending(), `public.model_catalogue_change does not exist and ${PENDING_NOTE} is gone: the sync file was never applied`);
    console.log(`NOT YET APPLIED (pending until merge): ${SYNC_SQL}. Freshness is asserted from the first run after it.`);
    return;
  }
  const open = await db(`select id, model_id, field, old_value, new_value, drift_pct, matrix, reason
      from public.model_catalogue_change where closed_at is null order by id`);
  assert.ok(r.last_ok && Number(r.hours) < FRESH_HOURS,
    `the model catalogue sync last succeeded ${r.last_ok ? `${Number(r.hours).toFixed(1)} h ago (${r.last_ok})` : 'never'}; `
    + `it must run at least every ${FRESH_HOURS} h (it_duty_schedule 'model_catalogue', resilience_ping itlater step `
    + `model_catalogue). Look at the step's result in the last ticks, and at duty_pause for 'resilience_ping.model_catalogue'.`);
  assert.deepEqual(open, [],
    'the catalogue changed a price or context length the sync will not apply by itself (a model of the founder\'s matrix, '
    + 'or a move over 20%). Each is an open finding duty:model_catalogue:change:<model>:<field>. Decide it: '
    + 'select public.fn_model_catalogue_reason(<id>, \'<why the new value is accepted>\', \'<seat>\'); the next sync '
    + `applies it. Open:\n  ${open.map((o) => `#${o.id} ${o.model_id} ${o.field} ${o.old_value} -> ${o.new_value}`
      + ` (${o.drift_pct ?? '?'}%, matrix ${o.matrix})${o.reason ? ' reasoned, waiting for the next sync' : ''}`).join('\n  ')}`);
});

// The synthetic case table. One row per branch of the rule; expected decisions listed per model and field.
const CASES = `select jsonb_agg(jsonb_build_object('m', model_id, 'f', field, 'd', decision) order by model_id, field) from
  public.fn_model_catalogue_decide(
    '[{"model_id":"zz-demo/ten-pct","in":1,"out":2,"ctx":1000},
      {"model_id":"zz-demo/twenty-pct","in":1,"out":2,"ctx":1000},
      {"model_id":"zz-demo/over-twenty","in":1,"out":2,"ctx":1000},
      {"model_id":"zz-demo/matrix","in":1,"out":2,"ctx":1000},
      {"model_id":"zz-demo/no-ctx","in":1,"out":2,"ctx":null},
      {"model_id":"zz-demo/gone","in":1,"out":2,"ctx":1000},
      {"model_id":"zz-demo/base:online","in":1,"out":2,"ctx":1000}]'::jsonb,
    array['zz-demo/matrix'],
    '[{"id":"zz-demo/ten-pct","context_length":1000,"pricing":{"prompt":"0.0000011","completion":"0.000002"}},
      {"id":"zz-demo/twenty-pct","context_length":1200,"pricing":{"prompt":"0.000001","completion":"0.000002"}},
      {"id":"zz-demo/over-twenty","context_length":1000,"pricing":{"prompt":"0.000001","completion":"0.00000243"}},
      {"id":"zz-demo/matrix","context_length":1001,"pricing":{"prompt":"0.000001","completion":"0.000002"}},
      {"id":"zz-demo/no-ctx","context_length":5000,"pricing":{"prompt":"0.000001","completion":"0.000002"}},
      {"id":"zz-demo/base","context_length":1000,"pricing":{"prompt":"0.000001","completion":"0.000002"}}]'::jsonb)`;
const WANT = [
  { m: 'zz-demo/gone', f: null, d: 'absent' },
  { m: 'zz-demo/matrix', f: 'ctx', d: 'held' },
  { m: 'zz-demo/no-ctx', f: 'ctx', d: 'held' },
  { m: 'zz-demo/over-twenty', f: 'out', d: 'held' },
  { m: 'zz-demo/ten-pct', f: 'in', d: 'auto' },
  { m: 'zz-demo/twenty-pct', f: 'ctx', d: 'auto' },
];

test('the sync rule: <=20% on a non-matrix model applies, anything else is held (synthetic ZZ DEMO rows)',
  { skip: !token() && 'no management token' }, async () => {
  const [{ built }] = await db(`select to_regprocedure('public.fn_model_catalogue_decide(jsonb,text[],jsonb)') is not null as built`);
  let got;
  if (built) {
    const [row] = await db(CASES);
    got = row.jsonb_agg;
  } else {
    assert.ok(pending(), `fn_model_catalogue_decide is not on production and ${PENDING_NOTE} is gone`);
    // Pending: replay the file in a transaction that always ends in an exception, so nothing commits.
    const sql = readFileSync(join(REPO, SYNC_SQL), 'utf8');
    assert.doesNotMatch(sql.replace(/--.*$/gm, ''), /^\s*(begin|commit|rollback)\s*;/im, 'the sync file carries a transaction line; the replay would commit');
    const v = await db(`begin;\n${sql}\n;\ndo $chk$ declare v jsonb; begin ${CASES} into v; raise exception 'CHK<<%>>', v; end $chk$;`);
    got = JSON.parse(v);
  }
  assert.deepEqual(got, WANT, 'fn_model_catalogue_decide no longer decides as the rule says');
});

test('the matrix probe states no price', () => {
  const probe = readFileSync(join(REPO, MATRIX_PROBE), 'utf8').replace(/--.*$/gm, '');
  assert.doesNotMatch(probe, /(in|out)_per_mtok_usd\s*(=|<|>|<=|>=)\s*[\d.]/i,
    `${MATRIX_PROBE} compares a price literal; prices are the catalogue's and the sync keeps the registry on them`);
});

const fetchCatalogue = async () => {
  try {
    const res = await fetch(CATALOGUE, { signal: AbortSignal.timeout(20000) });
    if (!res.ok) return { skip: `catalogue answered HTTP ${res.status}` };
    const body = await res.json();
    if (!Array.isArray(body?.data) || !body.data.length) return { skip: 'catalogue returned no data array' };
    return { models: new Map(body.data.map((m) => [m.id, m])) };
  } catch (e) {
    return { skip: `catalogue unreachable: ${String(e?.message ?? e).slice(0, 120)}` };
  }
};

// The models the seats' judgement classes run on. If any of them stops being vision-capable, or gemini-3.8-flash
// stops carrying audio, the capability branch in fn_ai_route silently substitutes something else. A FETCH FAILURE IS
// NOT A FINDING: it skips and says so.
test('the capabilities the registry file claims are the ones the catalogue advertises', async () => {
  const got = await fetchCatalogue();
  if (got.skip) {
    console.log(`SKIPPED (not a finding): ${got.skip}.`);
    return;
  }
  const expect = {
    'openai/gpt-5.6-sol': { image: true, audio: false },
    'anthropic/claude-opus-5.5': { image: true, audio: false },
    'anthropic/claude-sonnet-5': { image: true, audio: false },
    // The ONLY model any policy routes audio to; if it goes audio:false every voice note stops being transcribed.
    'google/gemini-3.8-flash': { image: true, audio: true },
    'openai/gpt-6-luna': { image: true, audio: false },
    // Every other seat's fallback (founder_instruction 1056).
    'deepseek/deepseek-v4.1-flash': { image: true, audio: false },
  };
  const wrong = [];
  for (const [id, want] of Object.entries(expect)) {
    const m = got.models.get(id);
    if (!m) { wrong.push(`${id}: not in the catalogue at all`); continue; }
    const mods = m.architecture?.input_modalities ?? [];
    if (mods.includes('image') !== want.image) wrong.push(`${id}: image=${mods.includes('image')}, file assumes ${want.image}`);
    if (mods.includes('audio') !== want.audio) wrong.push(`${id}: audio=${mods.includes('audio')}, file assumes ${want.audio}`);
  }
  assert.deepEqual(wrong, [],
    'a capability the registry records no longer matches the catalogue, so fn_ai_route\'s capability '
    + `branch will substitute a model nobody chose:\n  ${wrong.join('\n  ')}`);
});

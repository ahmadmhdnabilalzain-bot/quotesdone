// THE REGISTRY PRICES ARE THE CATALOGUE'S PRICES (it_engineer, 23 Sep 2026).
//
// Recurrence guard for scripts/sql/the_catalogue_names_every_model_the_seats_run_and_the_hold_covers
// _all_of_them.sql, which was written because model_registry had drifted from the provider: it was
// missing four models the seats were about to run, and carried context_len 200,000 for
// anthropic/claude-sonnet-5 and anthropic/claude-opus-4.8 against the catalogue's 1,000,000 — 5x low
// on the number any "will this prompt fit" decision reads, on the class that sends every quotation on
// one request.
//
// A price or a context length in that file is a CLAIM about a third party, and the third party can
// change it without telling us. So this check re-reads the catalogue and compares. It is the only
// check in this directory that touches the network, which shapes it:
//
//   * A FETCH FAILURE IS NOT A FINDING. No network, a 5xx, a timeout or a shape change skips the
//     comparison and says so. A check that goes red because openrouter.ai was briefly unreachable
//     teaches people to ignore it, and a check people ignore is worse than no check.
//   * A MISMATCH IS a finding, and fails. That is the whole point: it means the file's comments, the
//     rationale text quoting those prices, and the AED 1,170 budget arithmetic derived from them are
//     all stating a number that is no longer true.
//
// It reads the expected values out of the SQL file itself, so there is one place to correct when a
// price moves, and no second copy here to go stale on its own.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const OWNING_SQL =
  'scripts/sql/the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql';
const CATALOGUE = 'https://openrouter.ai/api/v1/models';

// The `update public.model_registry set context_len = <n>, in_per_mtok_usd = <a>,
//  out_per_mtok_usd = <b>, ... where model_id = '<id>';` statements, plus the three inserted rows.
const claimed = () => {
  const sql = readFileSync(join(REPO, OWNING_SQL), 'utf8');
  const out = new Map();

  for (const m of sql.matchAll(
    /update public\.model_registry set context_len = (\d+), in_per_mtok_usd = ([\d.]+),\s*\n?\s*out_per_mtok_usd = ([\d.]+),[\s\S]{0,400}?where model_id = '([^']+)';/g,
  )) {
    out.set(m[4], { ctx: Number(m[1]), in: Number(m[2]), out: Number(m[3]) });
  }

  // values ('<id>', '<provider>', '<tier>', <in>, <out>,\n <cr>, <cw>, <bool>, <bool>, <ctx>, ...
  for (const m of sql.matchAll(
    /\('([a-z0-9~./-]+)', '(?:anthropic|google|openai|qwen|z-ai)', '(?:small|medium|large|xlarge)', ([\d.]+), ([\d.]+),\s*\n\s*(?:[\d.]+|null), (?:[\d.]+|null), (?:true|false), true, (\d+),/g,
  )) {
    out.set(m[1], { ctx: Number(m[4]), in: Number(m[2]), out: Number(m[3]) });
  }

  assert.ok(out.size >= 10,
    `only ${out.size} models parsed out of ${OWNING_SQL} — the statements were reshaped and this `
    + 'check stopped reading them, which would make it pass by finding nothing');
  return out;
};

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

// USD per million tokens. OpenRouter prices per token as a decimal string.
const perMtok = (v) => (v == null ? null : Number((Number(v) * 1e6).toFixed(4)));

test('every price and context length the registry file claims is the one the catalogue serves', async () => {
  const want = claimed();
  const got = await fetchCatalogue();
  if (got.skip) {
    console.log(`SKIPPED (not a finding): ${got.skip}. ${want.size} claimed models were not compared.`);
    return;
  }

  const wrong = [];
  const absent = [];
  for (const [id, c] of want) {
    const m = got.models.get(id);
    if (!m) { absent.push(id); continue; }
    const live = { ctx: m.context_length, in: perMtok(m.pricing?.prompt), out: perMtok(m.pricing?.completion) };
    for (const k of ['in', 'out', 'ctx']) {
      if (live[k] !== c[k]) wrong.push(`${id} ${k}: file says ${c[k]}, catalogue serves ${live[k]}`);
    }
  }

  // A model the catalogue no longer lists is a finding of its own: the seats are routed to it.
  assert.deepEqual(absent, [],
    `${OWNING_SQL} registers model(s) the catalogue no longer lists: ${absent.join(', ')}. `
    + 'fn_ai_route will keep choosing them and every call will fail at the provider.');

  assert.deepEqual(wrong, [],
    'model_registry states a price or context length the provider does not. The file\'s comments, the '
    + 'model_policy rationale text that quotes these prices, and the AED 1,170/month budget '
    + `arithmetic derived from them are all now wrong:\n  ${wrong.join('\n  ')}`);
});

// The three models this PR added are the ones the seats' judgement classes run on. If any of them
// stops being vision-capable, or gemini-3.8-flash stops carrying audio, the capability branch in
// fn_ai_route silently substitutes something else.
test('the capabilities the registry file claims are the ones the catalogue advertises', async () => {
  const got = await fetchCatalogue();
  if (got.skip) {
    console.log(`SKIPPED (not a finding): ${got.skip}.`);
    return;
  }
  const expect = {
    // founder_instruction 841's two plan-A models. If either stops being vision-capable, every
    // extraction and drawing class silently gets substituted for something nobody chose; and their
    // audio:false is the measured fact that keeps speech_transcription on gemini.
    'qwen/qwen3.8-max-0902': { image: true, audio: false },
    'z-ai/glm-5.3-flash': { image: true, audio: false },
    'anthropic/claude-opus-5.5': { image: true, audio: false },
    'anthropic/claude-sonnet-5': { image: true, audio: false },
    'google/gemini-3.8-flash': { image: true, audio: true },
    // speech_transcription's pair. The SQL header says their audio support was READ, not assumed;
    // this is what keeps that true.
    'google/gemini-3.1-flash-lite': { image: true, audio: true },
    'google/gemini-3.5-flash': { image: true, audio: true },
    'openai/gpt-6-luna': { image: true, audio: false },
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

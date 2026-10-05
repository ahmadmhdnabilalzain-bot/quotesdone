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
//     rationale text quoting those prices, and the AED 1,600 budget arithmetic derived from them are
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
// Every file that registers a model and states its price. A later file that registers a model the
// first one did not (openai/gpt-5.6-sol, founder_instruction 854) must be read too, or its prices go
// unchecked while this check stays green.
const OWNING_SQLS = [
  'scripts/sql/the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql',
  'scripts/sql/gpt_sol_takes_every_qwen_class_and_one_gemini_takes_every_gemini_class.sql',
  // deepseek/deepseek-v4.1-flash, every other seat's fallback (founder_instruction 1056, 29 Sep 2026).
  'scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql',
  // A RETIRED MODEL IS NOT A CLAIM (founder_instruction 1068, 30 Sep 2026). The model the first file registered
  // for 841 was retired and deleted from model_registry; its three re-pricing files only ever priced it, so they
  // left this list, and this file's delete statement takes it out of the claim. A model no route can name can never
  // block CI again; every ACTIVE model is still compared strictly.
  'scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql',
  // 30 Sep 2026 ~10:10Z: the catalogue re-priced deepseek/deepseek-v4.1-flash to 0.0198 / 0.396; this file wins.
  'scripts/sql/deepseek_v4_1_flash_costs_what_the_catalogue_now_charges.sql',
  // 4 Oct 2026 ~20:20Z: re-priced again to 0.003 / 2.4; this file wins.
  'scripts/sql/deepseek_v4_1_flash_costs_what_the_catalogue_charges_on_4_october.sql',
  // 5 Oct 2026 ~06:10Z: back to 0.3 / 1.2; this file wins.
  'scripts/sql/deepseek_v4_1_flash_costs_what_the_catalogue_charges_on_5_october.sql',
  // 5 Oct 2026, matrix v2: deepseek/deepseek-v4.1-flash and qwen/qwen3.7-plus are switched off (active = false), so
  // they leave the claim; a retired model is skipped, every active one is still compared strictly.
  'scripts/sql/every_seat_runs_luna_with_gemini_behind_and_the_two_retired_models_leave_routing.sql',
];
const V2_SQL = 'scripts/sql/every_seat_runs_luna_with_gemini_behind_and_the_two_retired_models_leave_routing.sql';
const RETIRING_SQL = 'scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql';
const OWNING_SQL = OWNING_SQLS.join(' + ');
const CATALOGUE = 'https://openrouter.ai/api/v1/models';

// The `update public.model_registry set context_len = <n>, in_per_mtok_usd = <a>,
//  out_per_mtok_usd = <b>, ... where model_id = '<id>';` statements, plus the three inserted rows.
const claimed = () => {
  const out = new Map();

  // FILE BY FILE, IN OWNING_SQLS ORDER, AND WITHIN A FILE IN STATEMENT ORDER — the order the rows were
  // written in production. A later statement about a model supersedes an earlier one. Concatenating the
  // files and running the update pattern before the insert pattern (the first shape of this check) let
  // a 23 Sep INSERT overwrite the 24 Sep UPDATE that corrected it, so the check would have compared the
  // stale price for ever.
  const retired = new Map();   // model -> the file that retired it
  for (const f of OWNING_SQLS) {
    const sql = readFileSync(join(REPO, f), 'utf8');
    const found = [];

    // `update public.model_registry set context_len = <n>, in_per_mtok_usd = <a>,
    //  out_per_mtok_usd = <b>, ... where model_id = '<id>';`
    for (const m of sql.matchAll(
      /update public\.model_registry set context_len = (\d+), in_per_mtok_usd = ([\d.]+),\s*\n?\s*out_per_mtok_usd = ([\d.]+),[\s\S]{0,400}?where model_id = '([^']+)';/g,
    )) {
      found.push({ at: m.index, id: m[4], v: { ctx: Number(m[1]), in: Number(m[2]), out: Number(m[3]), from: f } });
    }

    // values ('<id>', '<provider>', '<tier>', <in>, <out>,\n <cr>, <cw>, <bool>, <bool>, <ctx>, ...
    for (const m of sql.matchAll(
      /\('([a-z0-9~./-]+)', '(?:anthropic|google|openai|qwen|z-ai|deepseek)', '(?:small|medium|large|xlarge)', ([\d.]+), ([\d.]+),\s*\n\s*(?:[\d.]+|null), (?:[\d.]+|null), (?:true|false), true, (\d+),/g,
    )) {
      found.push({ at: m.index, id: m[1], v: { ctx: Number(m[4]), in: Number(m[2]), out: Number(m[3]), from: f } });
    }

    // A retirement: `delete from public.model_registry where model_id = '<id>';`, or the row switched off
    // (`update public.model_registry set active = false ... where model_id = '<id>';`). No route can name it.
    for (const m of sql.matchAll(/delete from public\.model_registry where model_id = '([^']+)';/g)) {
      found.push({ at: m.index, id: m[1], v: null });
    }
    for (const m of sql.matchAll(/update public\.model_registry set active = false\b[^;]*?where model_id = '([^']+)';/g)) {
      found.push({ at: m.index, id: m[1], v: null });
    }

    for (const { id, v } of found.sort((a, b) => a.at - b.at)) {
      if (v) { out.set(id, v); retired.delete(id); } else { out.delete(id); retired.set(id, f); }
    }
  }

  // Every file must contribute what it registers. The size floor alone cannot see a later file's row
  // stop parsing: the first file clears 10 on its own, so a reshaped Sol row would vanish silently
  // and this check would stay green (measured in the review of PR #867).
  assert.ok(out.has('openai/gpt-5.6-sol'),
    'openai/gpt-5.6-sol was not parsed out of its registering file, so its price is not being checked');
  // The matrix v2 retirement must parse, or the two retired models' stale claims come back and block CI.
  for (const id of ['deepseek/deepseek-v4.1-flash', 'qwen/qwen3.7-plus']) {
    assert.ok(retired.get(id) === V2_SQL && !out.has(id),
      `${id} was not parsed as retired by ${V2_SQL}, so a model no route can name is still being compared`);
  }
  assert.ok(out.has('openai/gpt-6-luna'), 'openai/gpt-6-luna, every seat\'s main model, is not being checked');
  // The retirement must parse too, or the retired model's stale claim comes back and blocks CI again.
  assert.ok([...retired.values()].includes(RETIRING_SQL),
    `no retirement was parsed out of ${RETIRING_SQL}, so a retired model is being compared as if a route could name it`);
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
    + 'model_policy rationale text that quotes these prices, the model_rate row fn_llm_log prices every '
    + 'call from, and the AED 1,600/month budget arithmetic derived from them (gpt_sol_takes_every_qwen_'
    + 'class_and_one_gemini_takes_every_gemini_class.sql section 6) are all now wrong, and a price that '
    + 'reorders a tier moves every cheapest-in-tier route. Correct them in a NEW file '
    + 'appended to OWNING_SQLS (an `update public.model_registry set context_len = ..., in_per_mtok_usd = ..., '
    + 'out_per_mtok_usd = ...` statement is the pattern; a model no longer routed is retired instead):'
    + `\n  ${wrong.join('\n  ')}`);
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
    // openai/gpt-5.6-sol (founder_instruction 854, replacing qwen3.8-max). If it stops being vision-capable,
    // every extraction and drawing class silently gets substituted for something nobody chose; and its
    // audio:false is the measured fact that keeps speech_transcription on gemini.
    'openai/gpt-5.6-sol': { image: true, audio: false },
    'anthropic/claude-opus-5.5': { image: true, audio: false },
    'anthropic/claude-sonnet-5': { image: true, audio: false },
    // The ONLY model any policy routes audio to since founder_instruction 854 retired
    // gemini-3.1-flash-lite and gemini-3.5-flash. speech_transcription has no second model that
    // hears, so if this goes audio:false every voice note stops being transcribed.
    'google/gemini-3.8-flash': { image: true, audio: true },
    // Every seat's main model since matrix v2 (5 Oct 2026): image:true is what lets a vision or file call run on it;
    // audio:false is why speech_transcription and marketing_watch stay on Gemini with no fallback at all.
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

// fn_challenge can refuse a proposal and not say why.
//
// ── HOW IT SURFACED ─────────────────────────────────────────────────────────────────────────────
// The weekly executive meeting now puts its top three priorities to a second officer through
// fn_challenge (scripts/gen_exec_meeting_agenda_debate_priorities.mjs). Verifying that on staging
// produced a challenge with stance `recommend_against`, confidence 0.75 — and `reasoning` empty.
//
// ── THE DEFECT ──────────────────────────────────────────────────────────────────────────────────
// fn_challenge accumulates `v_weight` from two independent places and writes `v_reason` from only
// one of them:
//
//   challenge_heuristic  → v_weight += rank, AND v_reason := h.concern
//   institutional_memory → v_weight += 3 for each prior outcome of 'worse', v_reason UNCHANGED
//
// So a proposal that matches no heuristic but has two prior attempts on record that ended worse
// reaches v_weight 6, crosses the `>= 3` threshold into recommend_against, and is written to
// challenge_record with an empty reasoning. The `else` branch that supplies default prose only runs
// for `support`, which is precisely the stance that does not need explaining.
//
// Production has not hit it yet — 0 of 47 challenge_record rows have a blank reasoning, measured
// 9 Aug 2026 — because every recorded challenge so far matched a heuristic. The meeting calling
// fn_challenge three times a week is what makes it a matter of time.
//
// ── THE FIX ─────────────────────────────────────────────────────────────────────────────────────
// State the basis that actually drove the weight. The prior outcomes are already collected in
// `v_evidence` by the time the stance is decided, so the reason is written from the evidence that
// produced it rather than from a second query — and an unexplained refusal becomes an explained one.
//
// Read from the live definition and patched at one asserted anchor, so the rest of the routine
// stays byte-identical.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/challenge_reason_from_prior_outcomes.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_challenge' limit 1`);
if (!def) { console.error('fn_challenge not found'); process.exit(1); }
if (/prior attempt\(s\) on record/.test(def)) { console.error('REFUSING: fn_challenge already explains a prior-outcome refusal.'); process.exit(1); }

const ANCHOR = `  if v_alts='[]'::jsonb and v_stance<>'support' then`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the anchor did not match exactly once. Re-read fn_challenge first.');
  process.exit(1);
}

const BLOCK = `  -- A REFUSAL WITH NO REASON IS NOT A CHALLENGE. v_weight can cross the recommend_against
  -- threshold from institutional_memory alone, and only the heuristic loop above writes v_reason —
  -- so a proposal with two prior attempts that ended worse and no matching heuristic was recorded
  -- as recommend_against with an empty reasoning. Write the basis that actually drove the weight.
  if v_reason = '' and v_stance <> 'support' then
    v_reason := 'No principle in the priority hierarchy is touched by this, but '
      ||(select count(*) from jsonb_array_elements(v_evidence) e
          where e->>'type'='prior_outcome' and e->>'verdict'='worse')
      ||' prior attempt(s) on record ended worse: '
      ||coalesce((select string_agg(left(e->>'lesson',200), ' | ')
                    from jsonb_array_elements(v_evidence) e
                   where e->>'type'='prior_outcome' and e->>'verdict'='worse'),
                 'the outcome was recorded without a lesson')||'.';
  end if;

${ANCHOR}`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_challenge ${def.length} -> ${out.length} chars`);

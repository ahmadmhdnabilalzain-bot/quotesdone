// ROW #3 layer 3 — the lobby has a prose slot for an insight and puts nothing in it.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   exec-intel-narrative-insight  MISSING  2 lobby surface(s) render a prose key; the value behind
//                                          it right now is (null), causal: n/a, quantified: n/a
//
// The requirement is "the AI states an insight in prose with a cause, instead of a chart", and the
// check reads the ACTUAL value the lobby's prose key resolves to: fn_ws_exec()->command->health->note.
// The UI half has been done for a while — two lobby surfaces render it. The value is null.
//
// fn_health_index already has the slot and fills it for exactly one case:
//
//     'note', case when present < 3 then 'insufficient data — pre-traction; …' else null end
//
// So the company says something when it has almost no data and nothing at all when it has some.
// Production has seven of eight components measured and an index of 58.0, and the lobby prints a
// blank.
//
// ── THE CAUSE IS ARITHMETIC, NOT INFERENCE ──────────────────────────────────────────────────────
// `overall` is the MEAN of the present components. The components furthest below that mean are
// therefore exactly what hold the index where it is — that is division, not a guess, which is what
// makes "driven by" an honest connective here rather than a narrative flourish.
//
// The sentence names the two lowest with their own scores, against the average and the number of
// components it was taken over. On production today that reads:
//
//   Company health is 58.0 of 100 (watch), driven by RFQ completion at 0.0 and customer
//   acquisition at 0.0 — the two furthest below the 58.0-point average of 7 measured components.
//
// A cause and a magnitude, both of them numbers the routine already computed. The check requires
// both, and requires them in the SAME string, because a cause without a magnitude is not the
// requirement's example ("revenue will miss by 6% BECAUSE supplier response time rose 14%").
//
// The `present < 3` branch is left exactly as it was. It is the more honest sentence when there is
// nothing to be causal about, and replacing it would be trading a true statement for a longer one.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/health_note_names_its_cause.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_health_index' limit 1`);
if (!def) { console.error('fn_health_index not found'); process.exit(1); }
if (/driven by/.test(def)) { console.error('REFUSING: fn_health_index already writes a causal note.'); process.exit(1); }

const ANCHOR = `    'note', case when present < 3 then 'insufficient data — pre-traction; index will firm up with volume' else null end,`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the note anchor did not match exactly once. Re-read fn_health_index first.');
  process.exit(1);
}

const BLOCK = `    -- A PROSE INSIGHT WITH A CAUSE AND A MAGNITUDE, not a blank.
    -- \`overall\` is the mean of the present components, so the ones furthest below it are
    -- arithmetically what hold the index there. "driven by" is division, not narrative.
    'note', case
      when present < 3 then 'insufficient data — pre-traction; index will firm up with volume'
      else (select 'Company health is '||overall||' of 100 ('||band||'), driven by '
              ||string_agg(w.label||' at '||w.score, ' and ' order by w.score, w.label)
              ||' — the two furthest below the '||overall||'-point average of '||present
              ||' measured components.'
              from (select v.label, v.score from (values
                      ('customer acquisition', s_acq), ('supplier activity', s_supp),
                      ('RFQ completion', s_rfq), ('quote quality', s_qual),
                      ('response time', s_resp), ('dispute health', s_disp), ('uptime', s_up)
                    ) v(label, score)
                     where v.score is not null order by v.score, v.label limit 2) w)
      end,`;

const out = def.replace(ANCHOR, BLOCK);
if (out === def) { console.error('replacement produced no change'); process.exit(1); }

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${out};\n`);
console.log(`wrote ${OUT}`);
console.log(`  fn_health_index ${def.length} -> ${out.length} chars`);

// ROW #3 s28 — the company records 287 lessons and consults none of them at the moment it decides.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   s28-blocks-repeat-failures  MISSING  0 of 5 decision-path routine(s) consult
//                                        institutional_memory, outcome_record or org_memory before
//                                        deciding; the memory holds 287 item(s); the gate recorded
//                                        1,229 verdict(s)/30d
//
// The ledger is written and the gate runs 1,229 times a month. The two have never met. `fn_challenge`
// consults institutional_memory, but that is the adversary a founder proposal is put to — nothing on
// the path an ACTION takes reads it.
//
// ── WHERE IT GOES ───────────────────────────────────────────────────────────────────────────────
// fn_should_escalate. It already builds `reasons text[]` from six conditions — confidence below the
// floor, amount over the review threshold, money beyond the autonomous limit, fraud score, sensitive
// category, legal trigger — and escalates when the array is non-empty. A prior attempt that ended
// worse belongs in exactly that list, and escalation is the safe direction: it asks a person rather
// than acting.
//
// ── WHY THE MATCH IS THREE TOKENS AND NOT ONE ───────────────────────────────────────────────────
// This is a live decision path taking 1,229 verdicts a month, so the false-positive rate is the
// whole design question. The nine lessons with outcome 'worse' were read before this was written,
// and their distinctive words are not distinctive:
//
//   knowledge: test.failed on scheduled_run day_conductor   -> day_conductor, failed, knowledge, scheduled_run
//   knowledge_eng: Prioritized remediation roadmap for ...   -> module, prioritized, remediation, roadmap
//   hr: Self-review of HR onboarding status and readiness    -> onboarding, readiness, review, status
//   it: OS review [amber]: Technology OS                     -> review, technology
//
// Matching one token of six characters or more would escalate every action whose text contains
// "review", "status", "failed" or "knowledge" — which is most of them. So the bar is THREE distinct
// tokens from the SAME lesson. "OS review [amber]: Technology OS" carries only two and can therefore
// never fire, and that is the correct outcome: a two-word headline is too thin to claim a repeat
// from, and never firing is better than firing on the word "review".
//
// At most two reasons are appended, so an action that resembles several lessons escalates once with
// the two closest rather than carrying a wall of text into decision_log.reasons.
//
// ── WHAT THIS DOES NOT DO ───────────────────────────────────────────────────────────────────────
// It does not block anything. `escalate` routes the action to a person through the resolution
// already in this routine. The spec's requirement is that a failed strategy is CHECKED FOR before a
// decision, not that the machine overrules the founder.
//
// outcome_record is deliberately not read: all 51 of its rows sit at verdict 'pending' because the
// earliest measurement date is 11 Aug, so a clause reading it would be dead code that looks like a
// feature. It becomes the natural second source once outcomes start grading.
//
// Read from the live definition and patched at one asserted anchor.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from './staging/qd_guard.mjs';
import { REF as STAGE } from './staging/demo_factory.mjs';

const OUT = 'scripts/sql/escalate_on_prior_failure.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.proname='fn_should_escalate' limit 1`);
if (!def) { console.error('fn_should_escalate not found'); process.exit(1); }
if (/institutional_memory/.test(def)) { console.error('REFUSING: fn_should_escalate already consults institutional_memory.'); process.exit(1); }

const ANCHOR = `  -- RESOLVE THE PARTY.`;
if (def.split(ANCHOR).length - 1 !== 1) {
  console.error('REFUSING: the "RESOLVE THE PARTY" anchor did not match exactly once. Re-read the routine.');
  process.exit(1);
}

const BLOCK = `  -- A FAILED STRATEGY IS NOT REPEATED UNKNOWINGLY.
  -- institutional_memory is the company's ledger of what happened after it acted; 287 items, 9 of
  -- them graded 'worse'. Nothing on the path an action takes has ever read it. If this action reads
  -- like something already tried that ended worse, it goes to a person instead of through.
  --
  -- THREE distinct tokens from the SAME lesson, not one. The 'worse' headlines carry words like
  -- "review", "status", "failed" and "knowledge"; a single-token match would escalate most of the
  -- 1,229 actions the gate sees in a month. A headline too short to supply three tokens can never
  -- fire, which is the right answer for one — "OS review [amber]: Technology OS" is not evidence
  -- that anything in particular was tried.
  if c_txt <> '' then
    for trg in
      select m.headline from institutional_memory m
       where m.outcome = 'worse' and coalesce(m.headline,'') <> ''
         and (select count(distinct w) from regexp_split_to_table(lower(m.headline), '[^a-z0-9_]+') w
               where length(w) >= 6 and position(w in c_txt) > 0) >= 3
       order by m.created_at desc limit 2
    loop
      reasons := array_append(reasons,
        'a prior attempt on record ended worse: "'||left(trg, 120)||'"');
    end loop;
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
console.log(`  fn_should_escalate ${def.length} -> ${out.length} chars`);

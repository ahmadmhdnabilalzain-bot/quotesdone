// A STEP THE SCHEDULE DOES NOT NAME IS A STEP THAT NEVER RUNS (18 Sep 2026, it_engineer).
//
// Since the 15-minute tick takes its order from public.resilience_step rather than from a list in
// index.ts, the two are two files that have to agree. If a step is added to STEP_RUN and no row is
// seeded, fn_resilience_tick_plan never names it and it is silently dead — which is a worse version of
// the defect the schedule exists to fix, because a starved step at least raises a finding. If a row is
// seeded for a step the code does not have, the tick raises it as a failure every 15 minutes.
//
// This asserts both directions against PRODUCTION, so it fails on a schedule that was never applied as
// well as on a code change that forgot its row.
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const REF = 'htdblwldjkcgjvmqkbeh';
const token = supabaseAccessToken();

async function db(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (r.status === 429 && attempt < 5) {
    await new Promise((s) => setTimeout(s, 20_000 * (attempt + 1)));
    return db(query, attempt + 1);
  }
  const text = await r.text();
  if (!r.ok) throw new Error(`${r.status} ${text.slice(0, 400)}`);
  return JSON.parse(text);
}

// The STEP_RUN object literal is the one place the function's step names live. Anchored on the opening
// of the object and read to its closing brace, then the keys taken off the lines that declare a runner —
// a comment cannot contribute a name, because a name only counts with `{ run:` after it.
function stepsInSource() {
  const src = functionSource('resilience_ping');
  const open = src.indexOf('const STEP_RUN: Record<string, Omit<Step, \'name\'>> = {');
  if (open < 0) throw new Error('STEP_RUN not found in supabase/functions/resilience_ping/index.ts');
  const close = src.indexOf('\n};', open);
  if (close < 0) throw new Error('STEP_RUN has no closing brace');
  return [...src.slice(open, close).matchAll(/^\s{2}(\w+):\s*\{\s*run:/gm)].map((m) => m[1]);
}

const code = stepsInSource();
// The table not existing is a FINDING with a sentence, not a stack trace. A check that dies reads as
// infrastructure and gets waved through; a check that says "the schedule has not been applied" is the
// one line that tells you what to do, and it is the state this repository is in between the PR and the
// apply.
// Asked in two statements on purpose: Postgres parses a whole statement before running any of it, so a
// reference to a missing relation inside a CASE still fails at parse time. The existence question has to
// be its own query.
const present = await db("select to_regclass('public.resilience_step') is not null as present")
  .then((r) => r[0]?.present === true);
if (!present) {
  console.log('FAIL — public.resilience_step is not on production; apply '
    + 'scripts/sql/the_tick_runs_what_is_stalest_not_what_is_first_in_the_list.sql before merging');
  process.exit(1);
}
const rows = await db('select step, place from public.resilience_step order by step');
const scheduled = rows.map((r) => r.step);

const missing = code.filter((s) => !scheduled.includes(s));
const orphaned = scheduled.filter((s) => !code.includes(s));

console.log(`resilience_ping steps in code: ${code.length}; rows in public.resilience_step: ${scheduled.length}`);
if (missing.length) console.log(`  in the code, NOT scheduled (would never run): ${missing.join(', ')}`);
if (orphaned.length) console.log(`  scheduled, NOT in the code (fails every tick): ${orphaned.join(', ')}`);

// The three drains are the only steps allowed to sit outside the staleness plan, and every one of them
// must be there: outbox and archive deliver, and `it` must follow the detector.
const last = rows.filter((r) => r.place === 'last').map((r) => r.step).sort().join(',');
const expectedLast = 'archive,it,outbox';
if (last !== expectedLast) console.log(`  place='last' is "${last}", expected "${expectedLast}"`);

const findings = missing.length + orphaned.length + (last === expectedLast ? 0 : 1);
console.log(findings === 0 ? 'OK — the schedule and the function name the same steps' : `FAIL — ${findings} finding(s)`);
process.exit(findings === 0 ? 0 : 1);

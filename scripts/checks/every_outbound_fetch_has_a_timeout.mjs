// EVERY OUTBOUND CALL HAS A CLOCK ON IT — a RATCHET, not a gate (22 Sep 2026, it_engineer, CONN-04).
//
// WHAT IT COUNTS. `fetch(` sites in supabase/functions/** that carry no deadline: no `signal:` in the
// same call, not wrapped in timedFetch() or safeFetch(), not in a *.test.ts. A fetch with no deadline
// is bounded only by the platform killing the isolate, so the caller cannot tell "slow" from "never",
// and the work queued behind it — the row update that records what happened — never runs.
//
// WHY A BASELINE AND NOT ZERO. The audit measured 113 such sites across the deployed functions. Failing
// on all 113 at once would mean the check is red on day one and stays red, which is the same as no
// check; and fixing 113 call sites in one change is exactly the commit nobody can review. So the bar is
// the number in the baseline file: the count may FALL freely (the baseline is then out of date and the
// check says so, loudly, with the new number to paste in) and may never RISE. New code therefore cannot
// add an unbounded fetch, and the debt can only be paid down.
//
// HOW TO MOVE IT. Wrap the call in timedFetch (_shared/timed_fetch.ts) — or safeFetch, for a URL this
// process did not choose — run this check, and paste the number it prints into the baseline file.
//
// LIMIT, stated rather than hidden: this is a text scan, not a type-aware one. A call that builds its
// RequestInit in a variable declared elsewhere reads as unbounded here even when it is not, and a
// `signal:` on the same line satisfies it without being checked for what it is. It is a ratchet on a
// count, and the count is only as exact as that.
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');
const FN_DIR = join(ROOT, 'supabase', 'functions');
const BASELINE = join(ROOT, 'scripts', 'checks', 'outbound_fetch_timeout_baseline.json');

function walk(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.ts$/.test(e) && !/\.test\.ts$/.test(e)) out.push(p);
  }
  return out;
}

// A fetch call and everything up to the first `)` that closes a balanced argument list would need a
// parser. The measurement that matters is cheaper: take the call site and the 15 lines after it and
// ask whether a deadline appears before the next `fetch(`. 15 and not 7 because wa_inbound's directive
// classifier carries 13 lines of comment between its body and its `signal:`, and a check that calls a
// bounded call unbounded teaches people to ignore it.
export function unboundedFetches(src) {
  const lines = src.split('\n');
  const hits = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (!/(^|[^.\w])fetch\s*\(/.test(l)) continue;
    if (/timedFetch\s*\(|safeFetch\s*\(|\bfunction\s+fetch|export .*\bfetch\b\s*=/.test(l)) continue;
    if (/^\s*(\/\/|\*)/.test(l)) continue;
    const window = lines.slice(i, i + 16).join('\n');
    const upToNext = window.split(/(?<=\n)[^\n]*(?<![.\w])fetch\s*\(/)[0];
    if (/\bsignal\s*:/.test(upToNext)) continue;
    hits.push({ line: i + 1, text: l.trim().slice(0, 140) });
  }
  return hits;
}

const findings = [];
for (const f of walk(FN_DIR)) {
  for (const h of unboundedFetches(readFileSync(f, 'utf8'))) {
    findings.push({ file: relative(ROOT, f).replace(/\\/g, '/'), ...h });
  }
}

const baseline = JSON.parse(readFileSync(BASELINE, 'utf8'));
const count = findings.length;
// --list is a report, not a verdict: it prints the sites and exits 0 so it can be piped.
if (process.argv.includes('--list')) {
  for (const f of findings) console.log(`${f.file}:${f.line}  ${f.text}`);
  process.exit(0);
}

if (count > baseline.max_unbounded_fetches) {
  console.error(`FINDING: ${count} outbound fetch(es) with no deadline, over the baseline of ${baseline.max_unbounded_fetches}.`);
  console.error('New code may not add one. Wrap it in timedFetch() from supabase/functions/_shared/timed_fetch.ts.');
  console.error('Run with --list to see every site.');
  process.exit(1);
}
if (count < baseline.max_unbounded_fetches) {
  if (process.argv.includes('--ratchet')) {
    writeFileSync(BASELINE, JSON.stringify({ ...baseline, max_unbounded_fetches: count, measured_at: new Date().toISOString().slice(0, 10) }, null, 2) + '\n');
    console.log(`baseline lowered to ${count}`);
  } else {
    console.error(`FINDING: only ${count} unbounded fetch(es) remain but the baseline still says ${baseline.max_unbounded_fetches}.`);
    console.error(`A ratchet that is not tightened is not a ratchet. Run: node scripts/checks/every_outbound_fetch_has_a_timeout.mjs --ratchet`);
    process.exit(1);
  }
} else {
  console.log(`0 findings — ${count} unbounded fetch(es), exactly the baseline. ${baseline.note}`);
}

// A COMMITTED DELIVERABLE IS A CLAIM ABOUT PRODUCTION. NOTHING WAS CHECKING IT.
//
//   node --test scripts/checks/phase_d_deliverables_match_production.test.mjs
//
// THE DEFECT THIS EXISTS TO CATCH, measured 19 Aug 2026. scripts/checks/ held 76 files and not one
// of them contained the string `phase_d`. The only file in the directory that opened docs/phase-d
// at all was no_document_names_a_retired_door.test.mjs, and it filters `f.endsWith('.md')` — so no
// check in this repository had ever read a Phase D deliverable CSV. Nine of them are committed,
// each one a table of numbers about the live database, and the only thing standing between them and
// the reader was that somebody ran a builder once and remembered to commit the output.
//
// What that permitted, all of it measured rather than imagined:
//
//   · build_d0_crosswalk.mjs wrote its CSV to the REPOSITORY ROOT, not to docs/phase-d/. The
//     committed deliverable had therefore never been touched by its own builder.
//   · build_frontend_api_call_graph.mjs resolved 26 of 79 edges, wrote the short file, and THEN
//     exited 1 on an unrelated guard. The exit code was never read; the file was committed.
//   · four builders asserted a row count as a literal (`if (rows.length !== 257)`), which is right
//     until the registry moves and is a rubber stamp for as long as it does not.
//   · four columns were string constants presented as measurements — 'NOT_RUN' as a result,
//     'ENFORCED' as a status, 'RESOLVED_IN_CATALOGUE' as a resolution, and a production_version
//     reading "applied to htdblwldjkcgjvmqkbeh, read back identical" written by a builder that
//     performs no read-back.
//
// Every one of those is invisible to a reader of the CSV and invisible to CI. This check closes the
// loop the only way that means anything: it RE-RUNS each builder into a temp directory and diffs the
// result against the committed copy. A deliverable that no longer reproduces is a deliverable whose
// numbers have stopped being about production.
//
// WHAT IS ASSERTED WITHOUT A DATABASE, AND WHAT NEEDS ONE.
//
// The comparison itself is pure, and it carries a POSITIVE CONTROL that runs on every invocation:
// one row of a real committed deliverable is corrupted in memory and the differ is required to
// refuse it. A differ whose zero has never been seen to move is not a differ. The regeneration half
// needs the management token, and skips — loudly, by name — without it.
//
// The other seven required deliverables are hand-written prose. Prose cannot be regenerated, so what
// is asserted instead is the arithmetic inside it: a fraction a document states about a CSV must be
// the fraction that CSV holds, and the deliverable count a document claims must be the number of
// deliverables git is actually tracking.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BUILDERS, VOLATILE_LINE } from '../phase_d/lib/deliverable.mjs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const COMMITTED = 'docs/phase-d';

// ---------------------------------------------------------------------------------------------
// The comparison. Pure, line-oriented, and deliberately not a generic differ: it reports the FIRST
// difference with both sides printed, because "these files differ" is not something anyone can act
// on and "line 41 column enforcement_status: committed ENFORCED, rebuilt OUTSTANDING" is.
// ---------------------------------------------------------------------------------------------
const stripVolatile = (text) => text.split('\n').filter((l) => !VOLATILE_LINE.test(l));

export function diffDeliverable(committed, rebuilt) {
  const a = stripVolatile(committed);
  const b = stripVolatile(rebuilt);
  const findings = [];
  for (let i = 0; i < Math.max(a.length, b.length) && findings.length < 5; i++) {
    if (a[i] === b[i]) continue;
    if (a[i] === undefined) { findings.push(`line ${i + 1}: only in the REBUILT file: ${b[i]}`); continue; }
    if (b[i] === undefined) { findings.push(`line ${i + 1}: only in the COMMITTED file: ${a[i]}`); continue; }
    findings.push(`line ${i + 1}:\n      committed: ${a[i]}\n      rebuilt:   ${b[i]}`);
  }
  if (a.length !== b.length) {
    findings.push(`the committed file has ${a.length} line(s) and the rebuild produced ${b.length}`);
  }
  return findings;
}

// ---------------------------------------------------------------------------------------------
// POSITIVE CONTROL. Runs always, needs nothing, and is the reason the zero above may be believed.
// ---------------------------------------------------------------------------------------------
test('the deliverable comparison refuses a corrupted row, and ignores only the timestamp', () => {
  const sample = BUILDERS.map((b) => join(COMMITTED, b.file)).find((p) => existsSync(p));
  assert.ok(sample, `no committed deliverable found under ${COMMITTED}/ — this check would pass vacuously`);
  const real = readFileSync(sample, 'utf8');
  const lines = real.split('\n');
  assert.ok(lines.length > 3, `${sample} is too short to corrupt meaningfully`);

  // (a) identical content, different generated_at — must be reported as identical.
  const t1 = '# generated_at: 2026-08-19T00:00:00.000Z';
  const t2 = '# generated_at: 2026-08-20T11:22:33.444Z';
  assert.deepEqual(diffDeliverable([t1, ...lines].join('\n'), [t2, ...lines].join('\n')), [],
    'the comparison reported a difference between two files that differ only in their timestamp line; '
    + 'it would then fail on every run and be switched off within a week');

  // (b) ONE character of ONE data row changed — must be refused. Row 2 rather than row 1 so this
  //     is a data corruption and not a column-header change, which is a different failure.
  // The DATA row is the first non-comment line AFTER the column header. C5 gave every deliverable
  // two `#` provenance lines, which moved the header off row 1 and made an index computed from
  // "first non-# line" land on the header instead — this control caught its own arithmetic before
  // it could report a false green. The reported line NUMBER is deliberately not asserted either:
  // diffDeliverable drops the generated_at line before comparing, so its numbering is its own.
  // What is asserted is that the difference it reports is THIS row, by content.
  const headerIdx = lines.findIndex((l) => l.trim() !== '' && !l.startsWith('#'));
  assert.ok(headerIdx >= 0, `${sample} has no column header`);
  const idx = lines.findIndex((l, i) => i > headerIdx && l.trim() !== '' && !l.startsWith('#'));
  assert.ok(idx > headerIdx, `${sample} has no data row after its header`);
  const corrupted = [...lines];
  corrupted[idx] = corrupted[idx].replace(/[A-Za-z]/, (c) => (c === 'z' ? 'y' : 'z'));
  assert.notEqual(corrupted[idx], lines[idx], 'the corruption did not change the row — the control proves nothing');
  const found = diffDeliverable(real, corrupted.join('\n'));
  assert.ok(found.length > 0,
    `the comparison accepted a corrupted copy of ${sample} as identical. Every zero this check `
    + 'reports below would be meaningless.');
  const needle = corrupted[idx].slice(0, 40);
  assert.ok(found.some((f) => f.includes(needle)),
    `the comparison found a difference but not the corrupted row: ${found[0]}`);

  // (c) a truncated file — the exact shape build_frontend_api_call_graph.mjs shipped, 26 rows where
  //     79 belong, and nothing noticed.
  const truncated = diffDeliverable(real, lines.slice(0, Math.max(3, Math.floor(lines.length / 3))).join('\n'));
  assert.ok(truncated.length > 0, 'the comparison accepted a truncated file as identical');
});

// ---------------------------------------------------------------------------------------------
// REGENERATION. The builders themselves, into a temp directory, diffed against what is committed.
// ---------------------------------------------------------------------------------------------
const noToken = 'SKIPPED: no management token, so no builder can read production. Nothing is '
  + 'regenerated and nothing is asserted about whether the committed deliverables still reproduce.';

// TWO BUILDERS DRIVE PRODUCTION AND ARE NOT RUN BY DEFAULT.
//
// build_workflow_implementation_result.mjs drives all 30 frozen workflows and
// build_injected_defect_result.mjs injects all 75 catalogue defects. Both do it inside transactions
// that end in `raise exception` and both assert afterwards that they left nothing — but `npm test`
// is run casually and dozens of aborted drives against the one production project is not a
// reasonable default. They run under PHASE_D_DRIVE=1, and the skip below says by name what is
// therefore not being asserted rather than quietly reporting a smaller green.
const noDrive = process.env.PHASE_D_DRIVE === '1' ? false
  : 'SKIPPED: this builder drives production inside an aborted transaction. Set PHASE_D_DRIVE=1 to '
    + 'include it. Until then nothing is asserted about whether this deliverable still reproduces.';

for (const b of BUILDERS) {
  const names = [b.file];
  const why = !token ? noToken : (b.drives ? noDrive : false);
  test(`${b.file} still reproduces from production${b.drives ? ' (aborted-transaction drive)' : ''}`,
    { skip: why }, () => {
      const out = mkdtempSync(join(tmpdir(), 'phase-d-deliverable-'));
      try {
        const r = spawnSync(process.execPath, [b.script], {
          env: { ...process.env, PHASE_D_OUT_DIR: out, SUPABASE_ACCESS_TOKEN: token },
          encoding: 'utf8', timeout: 15 * 60 * 1000,
        });
        assert.equal(r.status, 0,
          `${b.script} exited ${r.status}. A builder that exits non-zero has not produced a `
          + `deliverable, whatever it left on disk.\n${r.stdout || ''}\n${r.stderr || ''}`);

        for (const name of names) {
          const rebuiltPath = join(out, name);
          const committedPath = join(COMMITTED, name);
          assert.ok(existsSync(rebuiltPath), `${b.script} exited 0 and wrote no ${name}`);
          assert.ok(existsSync(committedPath),
            `${committedPath} is not committed, so there is nothing for the rebuild to be checked against`);
          const findings = diffDeliverable(readFileSync(committedPath, 'utf8'), readFileSync(rebuiltPath, 'utf8'));
          assert.deepEqual(findings, [],
            `\n  ${committedPath} no longer matches what ${b.script} produces:\n  `
            + findings.join('\n  ')
            + `\n\n  Either production moved and the deliverable is stale — regenerate it with\n`
            + `    node ${b.script}\n`
            + `  — or the builder changed and the committed file is the correct one. The check does\n`
            + `  not decide which; it only refuses to let the two drift apart silently.\n`);
        }
      } finally {
        rmSync(out, { recursive: true, force: true });
      }
    });
}

// ---------------------------------------------------------------------------------------------
// THE HAND-WRITTEN SEVEN. Their numbers, against the machine-built files those numbers are about.
// ---------------------------------------------------------------------------------------------
function csvRows(path) {
  // Enough CSV for these files: quoted fields may hold commas and doubled quotes, never newlines,
  // and `#` provenance lines are not records.
  const out = [];
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue;
    const cells = []; let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (q) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
      else if (c === '"') q = true;
      else if (c === ',') { cells.push(cur); cur = ''; }
      else cur += c;
    }
    cells.push(cur);
    out.push(cells);
  }
  const head = out.shift();
  return out.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i] ?? ''])));
}

test('PHASE_D_FINANCIAL_PRIVACY_RESULT.md states the fractions PHASE_D_INJECTED_DEFECT_RESULT.csv holds', () => {
  const csv = join(COMMITTED, 'PHASE_D_INJECTED_DEFECT_RESULT.csv');
  const md = join(COMMITTED, 'PHASE_D_FINANCIAL_PRIVACY_RESULT.md');
  assert.ok(existsSync(csv) && existsSync(md), 'deliverable 9 or deliverable 12 is missing');
  const rows = csvRows(csv);
  assert.ok(rows.length > 0, `${csv} holds no rows — this check would pass vacuously`);

  const text = readFileSync(md, 'utf8');
  // "executed" is the CSV's own word for a defect that was actually injected: it produced a verdict
  // rather than a blocker. NOT_RUN is not an execution and must never be counted as one.
  for (const [category, label] of [['FINANCE', 'FINANCE defects executed and refused'],
                                   ['PRIVACY', 'PRIVACY defects executed']]) {
    const of = rows.filter((r) => r.category === category);
    assert.ok(of.length > 0, `${csv} holds no ${category} rows`);
    const executed = of.filter((r) => r.status !== 'NOT_RUN');
    const line = text.split('\n').find((l) => l.includes(label));
    assert.ok(line, `${md} no longer carries a "${label}" row, so its arithmetic cannot be checked`);
    const m = line.match(/\*\*\s*(\d+)\s*\/\s*(\d+)\s*\*\*/);
    assert.ok(m, `the "${label}" row in ${md} does not state a bold fraction: ${line.trim()}`);
    assert.deepEqual([Number(m[1]), Number(m[2])], [executed.length, of.length],
      `${md} says ${label} is ${m[1]} / ${m[2]}; ${csv} holds ${executed.length} executed of `
      + `${of.length} ${category} defects (${of.filter((r) => r.status !== 'NOT_RUN').map((r) => r.defect_id).join(', ') || 'none'}). `
      + 'The document and the file it summarises must not disagree.');
  }
});

test('PHASE_D_BUILDER_CLOSURE.md counts the deliverables git is actually tracking', () => {
  const required = 'QuotesDone_PHASE_D_DETERMINISTIC_BUSINESS_HANDLER_IMPLEMENTATION_PRODUCTION_DIRECT_v2026.08.17/PHASE_D_REQUIRED_DELIVERABLES.md';
  const md = join(COMMITTED, 'PHASE_D_BUILDER_CLOSURE.md');
  assert.ok(existsSync(md), `${md} is missing`);

  const ls = spawnSync('git', ['ls-files', COMMITTED], { encoding: 'utf8' });
  assert.equal(ls.status, 0, `git ls-files ${COMMITTED} failed: ${ls.stderr}`);
  const tracked = new Set(ls.stdout.split('\n').map((s) => s.trim()).filter(Boolean)
    .map((p) => p.split('/').pop()));
  assert.ok(tracked.size > 0, `git is tracking nothing under ${COMMITTED}/`);

  // The required list is the package's, not this repository's opinion of it. If the package is not
  // present the check says so rather than inventing a denominator — an absent input scoring as
  // satisfied is the exact failure mode this whole file exists to prevent.
  // THE LIST IS THE PACKAGE'S, NOT THIS REPOSITORY'S OPINION OF IT, and the package is untracked:
  // 79 files on disk, `git ls-files` returns 0, `git check-ignore` exits 1 so nothing is ignoring
  // it — it was simply never added. Two builder inputs live in it and this is one of them; the
  // other is registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv, which build_injected_defect_result.mjs
  // reads and which makes that builder throw ENOENT on a clean clone.
  //
  // This is a hard failure and not a skip on purpose. Falling back to a list typed into this file
  // would be an expectation checked against itself, and skipping would let an absent input score as
  // satisfied — which is the exact failure mode the rest of this file exists to catch.
  assert.ok(existsSync(required),
    `${required} is not on disk, so the required-deliverable list cannot be read.\n`
    + '  Stage the package inputs — by path, never `git add -A`:\n'
    + `    git add "${required}"\n`
    + '    git add "QuotesDone_PHASE_D_DETERMINISTIC_BUSINESS_HANDLER_IMPLEMENTATION_PRODUCTION_DIRECT_v2026.08.17/registries/PHASE_D_INJECTED_DEFECT_CATALOG.csv"');
  const names = [...readFileSync(required, 'utf8').matchAll(/\b(PHASE_D_[A-Z0-9_]+\.(?:csv|md))\b/g)]
    .map((m) => m[1]);
  const wanted = [...new Set(names)];
  assert.ok(wanted.length > 0, `no deliverable file names could be read out of ${required}`);

  const missing = wanted.filter((n) => !tracked.has(n));
  assert.deepEqual(missing, [], `required deliverable(s) not tracked by git: ${missing.join(', ')}`);

  // Every "N of 15" the closure states must be the number that is actually tracked.
  const claims = [...readFileSync(md, 'utf8').matchAll(/\*\*(\d+) of (\d+)\*\*/g)]
    .map((m) => ({ said: `${m[1]} of ${m[2]}`, n: Number(m[1]), d: Number(m[2]) }))
    .filter((c) => c.d === wanted.length);
  const wrong = claims.filter((c) => c.n !== wanted.length).map((c) => c.said);
  assert.deepEqual(wrong, [],
    `${md} claims ${wrong.join(', ')} while all ${wanted.length} required deliverables are tracked `
    + `under ${COMMITTED}/. A closure document understating its own completeness is read as a `
    + 'statement about the estate, not as a stale figure.');
});

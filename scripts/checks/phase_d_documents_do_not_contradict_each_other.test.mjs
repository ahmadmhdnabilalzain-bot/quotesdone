// THE COMMITTED TREE MAY HOLD ONE PHASE D VERDICT, AND EVERY NOT_RUN MUST NAME ITS BLOCKER.
//
// Two document findings from the 2026-08-20 independent acceptance, and both are the same shape: a
// claim in prose that nothing compares against anything.
//
// Finding 14. `PHASE_D_SECTION_8_PROBE_CLOSURE.md` ended with `PHASE_D_READY_FOR_FOUNDER_APPROVAL`
// while `PHASE_D_BUILDER_CLOSURE.md` said `PHASE_D_NOT_READY`. Both tracked, both committed, both
// read by whoever opened them first. The section 8 document was right about its own subject and had
// no business pronouncing on the phase; the verdict now lives in the required deliverable and
// nowhere else, and this test is what keeps it there.
//
// Finding 13. 38 of the 75 catalogued injected defects are NOT_RUN, and four categories — DISPATCH,
// LEGAL, QUOTE, TRACE — are 0 of 5. The acceptance offered two ways to close it: harnesses for the
// four zero categories, or a discharged blocker per row. The second is what the builder did, and
// every NOT_RUN row does carry a specific named blocker. But a blocker written in a CSV cell is a
// disposition in prose with no mechanism: nothing asserted that it was still there, still specific,
// or still true. This test asserts the first two. The third is a person's job, and the row that
// makes it possible is the one this test refuses to let go blank.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const tracked = execFileSync('git', ['ls-files', 'docs/'], { encoding: 'utf8' })
  .split('\n').map(s => s.trim()).filter(f => f.endsWith('.md'));

// The one document allowed to state the phase verdict.
const VERDICT_HOME = 'docs/phase-d/PHASE_D_BUILDER_CLOSURE.md';
const VERDICTS = /\bPHASE_D_(NOT_READY|READY_FOR_FOUNDER_APPROVAL|FINAL_ACCEPTANCE_(PASS|FAIL))\b/g;

test('the tracked tree states exactly one Phase D verdict, and it is not two different ones', () => {
  const stated = new Map();          // verdict -> [file:line]
  for (const f of tracked) {
    const lines = readFileSync(f, 'utf8').split('\n');
    lines.forEach((l, i) => {
      // A line that is quoting the history of a verdict is not stating one. The marker is narrow on
      // purpose: prose that says a file "used to end with" X is a record, not a claim.
      if (/used to end with|used to read|superseded by|recorded it as finding/.test(l)) return;
      for (const m of l.matchAll(VERDICTS)) {
        const v = m[0];
        if (!stated.has(v)) stated.set(v, []);
        stated.get(v).push(`${f}:${i + 1}`);
      }
    });
  }

  const kinds = [...stated.keys()].sort();
  assert.ok(kinds.length > 0,
    'no tracked document states a Phase D verdict at all — the required deliverable must state one');
  assert.equal(kinds.length, 1,
    'the committed tree states MORE THAN ONE Phase D verdict:\n' +
    kinds.map(k => `  ${k}\n${stated.get(k).map(s => `      ${s}`).join('\n')}`).join('\n') +
    '\n  One phase, one verdict, and it belongs in ' + VERDICT_HOME + '.');

  assert.ok(stated.get(kinds[0]).some(s => s.startsWith(VERDICT_HOME + ':')),
    `the verdict ${kinds[0]} is stated, but not in ${VERDICT_HOME}, which is the required ` +
    'deliverable and the document an acceptance reads.');
});

// ---------------------------------------------------------------------------------------------
function parseCsv(text) {
  const rows = []; let field = '', row = [], quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false; }
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ''; }
    else if (c !== '\r') field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows.filter(r => r.length > 1 && !String(r[0]).startsWith('#'));
}

test('every NOT_RUN injected defect names a specific blocker, and none is a placeholder', () => {
  const rows = parseCsv(readFileSync('docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv', 'utf8'));
  const h = rows[0];
  const [id, cat, status, blocker] =
    ['defect_id', 'category', 'status', 'blocker'].map(k => h.indexOf(k));
  assert.ok(Math.min(id, cat, status, blocker) >= 0, `a column is missing: ${h.join(', ')}`);

  const data = rows.slice(1);
  assert.equal(data.length, 75, `the catalogue is 75 defects; the result holds ${data.length}`);

  const tally = {}, thin = [];
  for (const r of data) {
    tally[r[status]] = (tally[r[status]] || 0) + 1;
    if (r[status] !== 'NOT_RUN') continue;
    const b = (r[blocker] || '').trim();
    // A blocker has to say something a reader could act on or disagree with. These three tests are
    // what separate "we measured why this cannot run" from "we did not run it".
    if (b.length < 40) thin.push(`${r[id]}: blocker is ${b.length} chars — "${b}"`);
    else if (/^(n\/a|none|tbd|todo|unknown|not run|blocked)\.?$/i.test(b)) thin.push(`${r[id]}: placeholder blocker "${b}"`);
    else if (!/[a-z]{3,}/.test(b)) thin.push(`${r[id]}: blocker is not prose — "${b}"`);
  }

  assert.deepEqual(thin, [],
    'a NOT_RUN row with no real blocker is an untested case wearing a reason:\n  ' + thin.join('\n  '));

  // Reported, not asserted at a number: the split is a disclosure and it is allowed to move. What
  // is asserted is that NOT_RUN never becomes the silent majority without somebody seeing it.
  assert.ok((tally.NOT_RUN || 0) <= 38,
    `NOT_RUN has grown to ${tally.NOT_RUN} of 75 (it was 38 at the 2026-08-20 acceptance). ` +
    'Untested coverage may be disclosed; it may not quietly increase.');
  assert.ok((tally.REFUSED_AS_REQUIRED || 0) >= 35,
    `REFUSED_AS_REQUIRED has fallen to ${tally.REFUSED_AS_REQUIRED} (it was 35). A defect the ` +
    'estate used to refuse and now does not is a regression, whatever the reason.');
});

test('the four zero-coverage categories are acknowledged by name, not left to be noticed', () => {
  const rows = parseCsv(readFileSync('docs/phase-d/PHASE_D_INJECTED_DEFECT_RESULT.csv', 'utf8'));
  const h = rows[0];
  const [cat, status] = ['category', 'status'].map(k => h.indexOf(k));
  const byCat = {};
  for (const r of rows.slice(1)) {
    byCat[r[cat]] = byCat[r[cat]] || { run: 0, total: 0 };
    byCat[r[cat]].total++;
    if (r[status] !== 'NOT_RUN') byCat[r[cat]].run++;
  }
  const zero = Object.entries(byCat).filter(([, v]) => v.run === 0).map(([k]) => k).sort();

  // The categories with no exercised case at all are the ones a reader most needs told. They are
  // allowed to exist — every row in them carries a blocker, asserted above — but the closure
  // document has to name them, so nobody has to parse a CSV to discover them.
  const closure = readFileSync('docs/phase-d/PHASE_D_BUILDER_CLOSURE.md', 'utf8');
  const unnamed = zero.filter(c => !closure.includes(c));
  assert.deepEqual(unnamed, [],
    `${unnamed.join(', ')} have zero exercised injected defects and are not named in ` +
    'PHASE_D_BUILDER_CLOSURE.md. A category with no coverage that nobody mentions reads exactly ' +
    'like a category that passed.');
});

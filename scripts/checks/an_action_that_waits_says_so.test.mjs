// AN ACTION THAT WAITS SAYS SO.
//
// Founder instruction, 18 Sep 2026: "Whenever someone presses something, if it's not instant, then
// during that second, for example, or two seconds, there should be a sort of an animation showing
// loading until that thing is done." The convention is docs/CONVENTIONS_LOADING.md; the primitives
// are src/components/ui/busy.tsx.
//
// WHAT THIS MEASURES, EXACTLY — the boundary said out loud, because a narrow check must never be
// read as a broad claim:
//
//   Subject:  async functions in src/components/** that are BOUND TO A CONTROL — named in an
//             onClick / onSubmit / onChange JSX attribute in the same file.
//   Assertion: if such a handler's body reaches the network, that same body must also carry a busy
//             affordance (a set*Busy-style setter, `.run('…'`, startTransition, useBusy,
//             useDelayedFlag) or a `busy-exempt:` comment naming a reason.
//
// It proves the action was WRITTEN with the convention in mind. It does NOT prove the affordance is
// correct, reaches the right element, or is translated — that is what review is for.
//
// WHY "bound to a control" and not "every async function": the first draft of this check asserted
// over every async body and produced 64 findings, of which the great majority were the thin
// `portal/*/api.ts` wrappers and small `const load = async () => call(…)` helpers whose CALLER owns
// the busy state. A check that cries 64 times about correct code is one people learn to ignore, and
// the founder's instruction was explicit that this must not be noisy. Narrowing to the handler a
// person actually presses is the subject the instruction is about.
//
// A file-level check would have been the other wrong answer: a large file with one busy flag
// somewhere would pass while a bare new action is added beside it — the exact regression this exists
// to catch.
//
// This is a SOURCE check, so per quotesdone-apply-discipline it would happily match its own prose:
// the busy-token list is assembled from split fragments so this header cannot satisfy it.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', 'src', 'components');

const NETWORK = [/\bcall\s*\(/, /\bapi\s*[(<]/, /\bpublicSite\s*[(<]/, /\bfetch\s*\(/,
  /\bSB\s*\(\s*\)\s*\./, /\.functions\.invoke\s*\(/];
// Split fragments, rejoined at load: this file's own comments must not satisfy its own assertion.
//
// The setter is matched by SHAPE, not by an enumerated name list. A list has to be edited every time
// somebody writes `setRwBusy` beside an existing `setBusy` — and the moment it goes stale the check
// reds a correct handler, which is how a guard gets softened instead of fixed. (It went stale
// exactly once, on the rebase that brought PR #729's `rewrite`/`setRwBusy` in.)
const SETTER = new RegExp('se' + 't\\w*(?:Busy|Saving|Sending|Loading|Uploading|Pending|Working|'
  + 'Reading|Checking|Analyzing|Canceling|Cancelling|Opening|Reviewing|Phase)\\b',
  // Case-insensitive because the codebase spells it both ways in the same component — `setVbusy`
  // sits four lines from `setBusy`. A guard that depends on somebody's capitalisation is a guard
  // that fails on style, not on substance.
  'i');
const BUSY = [SETTER, ...['us' + 'eBusy', 'us' + 'eDelayedFlag', 'sta' + 'rtTransition', 'bus' + 'y-exempt:']
  .map((s) => new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))];
const BUSY_RUN = /\.run\s*\(\s*['"`]/;         // useBusy().run('key', …)
// The third shape that IS a busy affordance, and the one most portal panels use: a reducer that
// flips its own `loading` — setSt((s) => ({ ...s, loading: true, err: '' })).
const BUSY_FLAG = /loading\s*:\s*true/;

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.tsx$/.test(e.name) && !/\.(test|spec)\.tsx$/.test(e.name)) out.push(p);
  }
  return out;
}

/** Names referenced from an onClick / onSubmit / onChange attribute anywhere in the file. */
function boundHandlers(src) {
  const names = new Set();
  const attr = /\bon(?:Click|Submit|Change|Drop|KeyDown)\s*=\s*\{([^}]{0,300})/g;
  let m;
  while ((m = attr.exec(src))) for (const id of m[1].match(/[A-Za-z_$][\w$]*/g) || []) names.add(id);
  return names;
}

/**
 * Named async functions and their bodies, by brace matching. Deliberately simple: it over-reports a
 * body's extent rather than under-reporting it, and an over-long body can only make the check more
 * forgiving, never falsely red.
 */
function namedAsyncBodies(src) {
  const out = [];
  // `async function name(`, `const name = async (`, `name: async (`, `const name = useCallback(async (`
  const sig = /(?:async\s+function\s+([A-Za-z_$][\w$]*)|(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=\n]{0,120})?=\s*(?:useCallback\s*\(\s*)?async\b)[^\n;{]{0,200}?\{/g;
  let m;
  while ((m = sig.exec(src))) {
    // A declaration at column 0 is a module-level helper (the shared `call`/`api` fetch wrapper),
    // not a handler — its CALLER owns the busy. Without this the wrapper is flagged in every file
    // that names it inside an onClick expression, which is how the first draft got to 64 findings.
    const col = m.index - (src.lastIndexOf('\n', m.index - 1) + 1);
    if (col === 0) { sig.lastIndex = m.index + m[0].length; continue; }
    let i = m.index + m[0].length - 1, depth = 0;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (!depth) break; }
    }
    // The body carries the preceding 6 lines so a `// busy-exempt:` note ABOVE the declaration
    // counts — that is where a reader expects to find the reason, not buried in the first statement.
    const head = src.lastIndexOf('\n', m.index) + 1;
    let from = head;
    for (let n = 0; n < 6 && from > 0; n++) from = src.lastIndexOf('\n', from - 2) + 1;
    out.push({ name: m[1] || m[2], at: src.slice(0, m.index).split('\n').length, body: src.slice(from, i + 1) });
    sig.lastIndex = m.index + m[0].length;
  }
  return out;
}

test('an action that waits says so', () => {
  const offenders = [];
  let checked = 0;
  for (const file of walk(ROOT)) {
    const src = fs.readFileSync(file, 'utf8');
    const bound = boundHandlers(src);
    if (!bound.size) continue;
    for (const { name, at, body } of namedAsyncBodies(src)) {
      if (!bound.has(name)) continue;                       // not something a person presses
      if (!NETWORK.some((r) => r.test(body))) continue;     // instant — rule: show nothing
      checked++;
      if (BUSY_RUN.test(body) || BUSY_FLAG.test(body) || BUSY.some((r) => r.test(body))) continue;
      offenders.push(`${path.relative(ROOT, file).replaceAll('\\', '/')}:${at} — ${name}()`);
    }
  }
  // A check that asserts over nothing is a green light over nothing. If the walk stops finding
  // bound network handlers, the walk broke, not the codebase.
  assert.ok(checked >= 40, `expected to inspect 40+ bound network handlers, inspected ${checked} — the walk is broken`);
  assert.deepEqual(offenders, [], [
    `Inspected ${checked} handlers bound to a control. These reach the network with no busy`,
    'affordance in their body — a press that waits and says nothing.',
    'Give each a busy state (docs/CONVENTIONS_LOADING.md, src/components/ui/busy.tsx), or mark it',
    '`// busy-exempt: <reason>` when it genuinely needs none.',
    ...offenders.map((o) => '  ' + o),
  ].join('\n'));
});

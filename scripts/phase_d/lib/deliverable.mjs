// WHERE A BUILT DELIVERABLE GOES, AND WHAT IT SAYS ABOUT ITSELF.
//
// Two problems, one file, because they are the same problem seen twice.
//
// 1. PROVENANCE. On 19 Aug 2026 all eight built Phase D CSVs opened directly on their column header
//    row. A reader holding PHASE_D_RULE_GATE_RESULT.csv could not tell which command produced it,
//    which project it was read from, when, or — the one that matters — what its 86 rows are 86 OF.
//    "86 rows" and "86 of 86 registered subjects" are different claims and the file made only the
//    first. A number with no denominator is the shape this estate has been bitten by repeatedly:
//    pct(got, 0) returns 100, and a deliverable that states a numerator alone invites exactly that
//    reading.
//
// 2. WHERE IT IS WRITTEN. The builders each hard-coded 'docs/phase-d/<name>.csv'. That is correct
//    for a build and useless for a CHECK: scripts/checks/phase_d_deliverables_match_production.test.mjs
//    has to regenerate each deliverable somewhere that is not the working tree and diff it against
//    the committed copy. A check that re-implements the build cannot detect a build that drifted —
//    it can only detect that two implementations disagree. So the check runs THESE builders, with
//    PHASE_D_OUT_DIR pointed at a temp directory, and diffs the result.
//
// THE TIMESTAMP IS ON ITS OWN LINE ON PURPOSE. Every other provenance field is stable across two
// runs over the same database, so the diff covers them. The timestamp is not, and a diff that fails
// because time passed is a diff nobody reads. `# generated_at:` is the one line the comparison
// strips, and it is the only one.
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const PROJECT = 'htdblwldjkcgjvmqkbeh';

/** The directory a built deliverable is written to. The check overrides it; a build does not. */
export const OUT_DIR = process.env.PHASE_D_OUT_DIR || 'docs/phase-d';

/** Full path for a deliverable file name, with the directory created. */
export function outPath(name) {
  const p = join(OUT_DIR, name);
  mkdirSync(dirname(p), { recursive: true });
  return p;
}

/**
 * The two `#` lines every built deliverable opens with, terminated so a CSV body can be appended.
 *
 * @param {object} p
 * @param {string} p.command      the exact command that regenerates this file
 * @param {number|string} p.numerator    what this file contains
 * @param {number|string} p.denominator  what it would contain if it were complete
 * @param {string} p.of           what the denominator counts, named in full
 * @param {string} p.attribution  how a row was decided — the model, not a restatement of the columns
 */
export function provenance({ command, numerator, denominator, of, attribution }) {
  for (const [k, v] of Object.entries({ command, of, attribution })) {
    if (!v || !String(v).trim()) throw new Error(`provenance: ${k} is required and was empty`);
  }
  if (numerator === undefined || denominator === undefined) {
    throw new Error('provenance: numerator and denominator are both required — a numerator alone is '
      + 'the defect this header exists to prevent');
  }
  // Newlines only. A comma is left alone: a spreadsheet will spread the `#` line across a few
  // columns, which is cosmetic, whereas stripping commas turned "(component, edge_function)" into
  // "(component  edge_function)" and made the one sentence that states the attribution model
  // unreadable. Neither `#` line is a record — every consumer of these files skips them.
  const clean = (s) => String(s).replace(/[\r\n]+/g, ' ').trim();
  return `# ${clean(command)} | project ${PROJECT} | ${numerator} of ${denominator} ${clean(of)}`
    + ` | attribution: ${clean(attribution)}\n`
    + `# generated_at: ${new Date().toISOString()}\n`;
}

/** The line the deliverable comparison strips before diffing. Exported so both sides agree. */
export const VOLATILE_LINE = /^# generated_at:/;

// THE BUILD ORDER, IN ONE PLACE, BECAUSE THREE THINGS HAVE TO AGREE ON IT: the npm script, the
// build_all runner, and the check that regenerates every one of them. It was previously written
// nowhere at all — the builders were run by hand, in whatever order the person remembered.
//
// `drives` marks a builder that opens a transaction on production and aborts it. Those two are the
// reason `npm run build:phase-d` is not something to run casually, and the reason the deliverable
// check names them separately when it reports what it regenerated.
export const BUILDERS = [
  { script: 'scripts/phase_d/build_d0_crosswalk.mjs', file: 'PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv', drives: false },
  { script: 'scripts/phase_d/build_handler_implementation_result.mjs', file: 'PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv', drives: false },
  { script: 'scripts/phase_d/build_workflow_implementation_result.mjs', file: 'PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv', drives: true },
  { script: 'scripts/phase_d/build_business_object_result.mjs', file: 'PHASE_D_BUSINESS_OBJECT_RESULT.csv', drives: false },
  { script: 'scripts/phase_d/build_rule_gate_result.mjs', file: 'PHASE_D_RULE_GATE_RESULT.csv', drives: false },
  { script: 'scripts/phase_d/build_handoff_event_result.mjs', file: 'PHASE_D_HANDOFF_EVENT_RESULT.csv', drives: false },
  { script: 'scripts/phase_d/build_frontend_api_call_graph.mjs', file: 'PHASE_D_FRONTEND_API_CALL_GRAPH.csv', drives: false },
  { script: 'scripts/phase_d/build_step_case_result.mjs', file: 'PHASE_D_STEP_CASE_RESULT.csv', drives: false },
  { script: 'scripts/phase_d/build_injected_defect_result.mjs', file: 'PHASE_D_INJECTED_DEFECT_RESULT.csv', drives: true },
  // DELIBERATELY NOT LISTED: scripts/phase_d/build_transaction_local_evidence.mjs.
  //
  // Everything in this array is a DERIVATION — a statement about the estate that must come out the
  // same on every rebuild, which is why the check that regenerates them compares byte for byte.
  // PHASE_D_TRANSACTION_LOCAL_EVIDENCE.csv is not a derivation. It is the record of ONE aborted
  // transaction, carrying that transaction's own fixture-run id and the digests it produced, and
  // re-running it does not reproduce that evidence — it produces different evidence about a
  // different run. Listing it here would force it to either drop the run identity that makes it
  // checkable, or fail its own reproduction test forever. It is regenerated deliberately, and the
  // run it describes is named in the file.
];

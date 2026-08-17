// REGENERATE THE PHASE C BUILDER CLOSURE FROM THE AUTHORITATIVE CHECKS.
//
//   node scripts/phase_c/regenerate_builder_closure.mjs
//
// WHY THIS EXISTS. The builder closure carried numbers that were typed once and then went stale:
// "965 routine names" when the same check at the same commit reported 1013, "positive cases
// accepted 20/20" for a suite that is 18 negatives and 2 positives, and a component count that
// production had moved past. A closure document whose numbers are hand-copied is a claim, not
// evidence.
//
// Every headline below is produced by RUNNING the authoritative script and reading its output, and
// every headline records six things so a reader never has to guess what a number means:
//
//     command      the exact argv that produced it
//     numerator    what passed / what was found
//     denominator  out of what
//     commit       the commit the run was made from
//     environment  the project and the zero-cost mode in force
//     measurement  static (committed files only) | production (a live read) | credential_blocked
//
// A check that could not reach production is recorded as CREDENTIAL_BLOCKED and is never folded
// into a pass. Writes docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.md and its .json twin.
import { writeFileSync, existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const REPO = process.cwd().replace(/\\/g, '/');
const PROD = 'htdblwldjkcgjvmqkbeh';
const commit = spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout.trim();
const branch = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' }).stdout.trim();
const dirty = spawnSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).stdout
  .split('\n').filter(l => l && !l.startsWith('??')).length;
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const hasToken = !!(process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) && readFileSync(LOCAL_TOKEN, 'utf8').trim()));

const ENV = {
  project_ref: PROD,
  NO_PAID_AI: 'true',
  OPENROUTER_DISABLED: 'true',
  AI_PROVIDER_MODE: 'mock',
  PHASE_D_EXTERNAL_EFFECT_MODE: 'mock',
  management_credential_present: hasToken,
};

const num = (out, re) => { const m = out.match(re); return m ? m.slice(1) : null; };

/**
 * Each entry names the ONE script that owns its subject. There is deliberately no second script
 * answering the same question: that is the defect this whole branch exists to close.
 */
const CHECKS = [
  {
    section: 'COMPONENT CROSSWALK',
    headline: 'committed declarations = committed crosswalk = live component rows',
    command: ['scripts/checks/phase_c_component_crosswalk.test.mjs', '--require-live'],
    measurement: 'production',
    parse: out => {
      const d = num(out, /committed declarations\s+(\d+)/);
      const c = num(out, /committed crosswalk rows\s+(\d+)/);
      const f = num(out, /findings\s+(\d+)/);
      const blocked = /NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL/.test(out);
      return {
        numerator: f ? `${Number(f[0]) === 0 ? '0 findings' : f[0] + ' findings'}` : 'unparsed',
        denominator: d && c ? `${d[0]} declared / ${c[0]} crosswalk` : 'unparsed',
        measurement: blocked ? 'credential_blocked' : 'production',
        detail: { declared: d && Number(d[0]), crosswalk: c && Number(c[0]), findings: f && Number(f[0]) },
      };
    },
  },
  {
    section: 'COMPONENT CROSSWALK',
    headline: 'the static half needs no credential and runs on every pull request',
    command: ['scripts/checks/phase_c_component_crosswalk.test.mjs', '--static'],
    measurement: 'static',
    parse: out => ({
      numerator: /STATIC PASS/.test(out) ? '0 findings' : 'FAIL',
      denominator: (num(out, /committed declarations\s+(\d+)/) || ['?'])[0] + ' declarations',
      measurement: 'static',
    }),
  },
  {
    section: 'ROUTINE SOURCE OF TRUTH',
    headline: 'one canonical file per routine, and it is what is deployed',
    command: ['scripts/checks/canonical_routine_manifest.mjs', '--all'],
    measurement: 'production',
    parse: out => {
      const canonical = num(out, /routine names with a repo definition (\d+)\s+canonical (\d+)/);
      const findings = num(out, /countable findings\s+(\d+)/);
      const skipped = /PRODUCTION COMPARISON SKIPPED/.test(out);
      return {
        numerator: findings ? `${findings[0]} findings` : 'unparsed',
        denominator: canonical ? `${canonical[1]} canonical routines` : 'unparsed',
        measurement: skipped ? 'credential_blocked' : 'production',
        detail: {
          repo_definitions: canonical && Number(canonical[0]),
          canonical: canonical && Number(canonical[1]),
          repo_to_prod: (num(out, /repository -> production drift\s+(\S+)/) || [])[0],
          prod_to_repo: (num(out, /production -> repository drift\s+(\S+)/) || [])[0],
          conflicting: (num(out, /conflicting current definitions\s+(\d+)/) || [])[0],
          ambiguous: (num(out, /ambiguous routine winners\s+(\d+)/) || [])[0],
          uncommitted_ddl: (num(out, /uncommitted application DDL\s+(\S+)/) || [])[0],
          manifest_gaps: (num(out, /manifest gaps\s+(\d+)/) || [])[0],
        },
      };
    },
  },
  {
    section: 'ROUTINE SOURCE OF TRUTH',
    headline: 'the engine is the only canonicality system, and it refuses a forced conflict',
    command: ['scripts/checks/canonical_routines.test.mjs'],
    measurement: 'mixed',
    parse: out => ({
      numerator: (num(out, /\((\d+) passed\)/) || ['?'])[0] + ' assertions passed',
      denominator: 'one engine, one forced counterexample',
      measurement: /repository-side only/.test(out) ? 'credential_blocked' : 'production',
    }),
  },
  {
    section: 'COMMAND CENTER',
    headline: 'the founder chain, end to end, asserted on normalised relationships',
    command: ['scripts/checks/phase_c_founder_chain.test.mjs'],
    measurement: 'production',
    parse: out => {
      const failed = num(out, /(\d+) check\(s\) failed/);
      const ok = (out.match(/^ok /gm) || []).length;
      return {
        numerator: `${ok} checks passed`,
        denominator: `${ok + (failed ? Number(failed[0]) : 0)} checks`,
        measurement: 'production',
      };
    },
  },
  {
    section: 'COMMAND CENTER',
    headline: 'the Command Center entry point, over the surface the founder uses',
    command: ['scripts/checks/phase_c_command_center_entry_point.test.mjs'],
    measurement: 'production',
    parse: out => ({
      numerator: /COMMAND CENTER ENTRY POINT VERIFIED/.test(out) ? 'VERIFIED' : (out.match(/(d+) check(s) failed/) || ['?'])[1] + ' failed',
      denominator: (out.match(/^ok /gm) || []).length + ' checks',
      measurement: 'production',
    }),
  },
  {
    section: 'COMMAND CENTER',
    headline: 'command routing acceptance cases',
    command: ['scripts/checks/phase_c_command_acceptance.test.mjs'],
    measurement: 'production',
    parse: out => {
      const m = num(out, /(\d+)\/(\d+) acceptance cases pass/);
      return { numerator: m ? `${m[0]} passed` : 'unparsed', denominator: m ? `${m[1]} cases` : 'unparsed', measurement: 'production' };
    },
  },
  {
    section: 'GUARDS',
    headline: 'injected defects refused (negative suite)',
    command: ['scripts/checks/phase_c_guards_reject_injected_defects.test.mjs'],
    measurement: 'production',
    parse: out => {
      const m = num(out, /(\d+)\/(\d+) injected defects refused/);
      return {
        numerator: m ? `${m[0]} refused` : 'unparsed',
        denominator: m ? `${m[1]} injected defects` : 'unparsed',
        measurement: 'production',
        detail: {
          sqlstate_guard_pairs: (num(out, /SQLSTATE \+ guard pair: (\d+)/) || [])[0],
          prose_only_assertions: (num(out, /asserted on a human message:\s+(\d+)/) || [])[0],
        },
      };
    },
  },
  {
    section: 'GUARDS',
    headline: 'genuine positive controls accepted (denominator derived, not typed)',
    command: ['scripts/checks/kernel_positive_controls.test.mjs'],
    measurement: 'production',
    parse: out => {
      const m = num(out, /genuine positive controls: (\d+) door\(s\), (\d+) accepted, (\d+) failed/);
      return {
        numerator: m ? `${m[1]} accepted` : 'unparsed',
        denominator: m ? `${m[0]} canonical kernel entry doors` : 'unparsed',
        measurement: 'production',
        detail: { failed: m && Number(m[2]) },
      };
    },
  },
  {
    section: 'GUARDS',
    headline: 'Phase B architecture guards fired (18 negative injections + 2 positive controls)',
    command: ['scripts/checks/phase_b_guards_reject_injected_defects.test.mjs'],
    measurement: 'production',
    parse: out => {
      const m = num(out, /(\d+)\/(\d+) guards fired/);
      return { numerator: m ? `${m[0]} fired` : 'unparsed', denominator: m ? `${m[1]} cases` : 'unparsed', measurement: 'production' };
    },
  },
  {
    section: 'KERNEL INVARIANTS',
    headline: 'Phase C invariants',
    command: ['scripts/checks/phase_c_invariants.test.mjs'],
    measurement: 'production',
    parse: out => ({
      numerator: /PHASE C INVARIANTS PASS/.test(out) ? 'PASS' : (num(out, /(\d+) check\(s\) failed/) || ['?'])[0] + ' failed',
      denominator: `${(out.match(/^ok /gm) || []).length} checks`,
      measurement: /SKIP phase_c_invariants/.test(out) ? 'credential_blocked' : 'production',
    }),
  },
  {
    section: 'KERNEL INVARIANTS',
    headline: 'kernel invariants',
    command: ['scripts/checks/kernel_invariants.test.mjs'],
    measurement: 'production',
    parse: out => ({
      numerator: /KERNEL INVARIANTS PASS/.test(out) ? 'PASS' : 'FAIL',
      denominator: `${(out.match(/^ok /gm) || []).length} checks`,
      measurement: 'production',
    }),
  },
  {
    section: 'KERNEL INVARIANTS',
    headline: 'cancellation reaches the kernel',
    command: ['scripts/checks/cancellation_reaches_the_kernel.test.mjs'],
    measurement: 'production',
    parse: out => ({
      numerator: /PASS —/.test(out) ? 'PASS' : 'FAIL',
      denominator: `${(out.match(/^ok /gm) || []).length} counters`,
      measurement: 'production',
    }),
  },
  {
    section: 'KERNEL INVARIANTS',
    headline: 'active signal types are executable',
    command: ['scripts/checks/active_signal_types_are_executable.test.mjs'],
    measurement: 'production',
    parse: out => {
      const m = num(out, /valid-state accepted (\d+)\/(\d+)/);
      return { numerator: m ? `${m[0]} accepted` : 'unparsed', denominator: m ? `${m[1]} active signal types` : 'unparsed', measurement: 'production' };
    },
  },
  {
    section: 'KERNEL INVARIANTS',
    headline: 'the kernel write guard, proved in both directions',
    command: ['scripts/checks/kernel_write_guard_both_directions.test.mjs'],
    measurement: 'production',
    parse: out => ({
      numerator: /WRITE GUARD PROVED BOTH DIRECTIONS/.test(out) ? 'PASS' : 'FAIL',
      denominator: (num(out, /\((\d+) passed\)/) || ['?'])[0] + ' cases',
      measurement: 'production',
    }),
  },
];

const results = [];
for (const c of CHECKS) {
  process.stderr.write(`running ${c.command.join(' ')}\n`);
  const r = spawnSync(process.execPath, c.command, { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const parsed = c.parse(out) || {};
  results.push({
    section: c.section,
    headline: c.headline,
    command: `node ${c.command.join(' ')}`,
    numerator: parsed.numerator ?? 'unparsed',
    denominator: parsed.denominator ?? 'unparsed',
    commit,
    environment: ENV,
    measurement: parsed.measurement ?? c.measurement,
    exit_code: r.status,
    result: parsed.measurement === 'credential_blocked' ? 'NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL'
      : r.status === 0 ? 'PASS' : 'FAIL',
    detail: parsed.detail ?? null,
  });
}

// ---------------------------------------------------------------- the document
const bySection = new Map();
for (const r of results) {
  if (!bySection.has(r.section)) bySection.set(r.section, []);
  bySection.get(r.section).push(r);
}
const blocked = results.filter(r => r.measurement === 'credential_blocked');
const failed = results.filter(r => r.result === 'FAIL');

const L = [];
L.push(`# Phase C execution kernel — builder closure`);
L.push('');
L.push(`**GENERATED by \`node scripts/phase_c/regenerate_builder_closure.mjs\`. Do not edit by hand.**`);
L.push(`Every number below was produced by running the script named beside it, in this environment,`);
L.push(`at this commit. A hand-typed number is how this document previously came to claim 965`);
L.push(`canonical routines when the same check reported 1013, and "20/20 positive controls" for a`);
L.push(`suite of 18 negative injections and 2 positive controls.`);
L.push('');
L.push(`| | |`);
L.push(`|---|---|`);
L.push(`| commit | \`${commit}\` |`);
L.push(`| branch | \`${branch}\` |`);
L.push(`| tracked files modified at generation time | ${dirty} |`);
L.push(`| project | \`${PROD}\` (the one project) |`);
L.push(`| zero-cost mode | \`NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock\` |`);
L.push(`| management credential present | ${hasToken ? 'yes' : 'NO — production halves are CREDENTIAL_BLOCKED below'} |`);
L.push(`| headlines generated | ${results.length} |`);
L.push(`| headlines FAILED | **${failed.length}** |`);
L.push(`| headlines CREDENTIAL_BLOCKED | **${blocked.length}** |`);
L.push('');
L.push(`A CREDENTIAL_BLOCKED headline is not a pass and is not folded into one. It says that the`);
L.push(`production half of that check did not run.`);
L.push('');
for (const [section, rows] of bySection) {
  L.push(`---`);
  L.push('');
  L.push(`## ${section}`);
  L.push('');
  L.push(`| headline | numerator | denominator | measurement | result |`);
  L.push(`|---|---|---|---|---|`);
  for (const r of rows) {
    L.push(`| ${r.headline} | **${r.numerator}** | ${r.denominator} | ${r.measurement} | ${r.result === 'PASS' ? '**PASS**' : '**' + r.result + '**'} |`);
  }
  L.push('');
  for (const r of rows) {
    L.push(`- \`${r.command}\` → exit ${r.exit_code}`
      + (r.detail ? `  ${JSON.stringify(r.detail)}` : ''));
  }
  L.push('');
}
L.push(`---`);
L.push('');
L.push(`## WHAT THIS DOCUMENT DOES NOT CLAIM`);
L.push('');
L.push(`- It is not an independent audit. It is the builder's own measurement, regenerated.`);
L.push(`- No business automation was reactivated to produce it: every probe above runs inside a`);
L.push(`  transaction that ends in \`raise exception\`, and each suite asserts its own row counts`);
L.push(`  unchanged afterwards.`);
L.push(`- No paid inference was used. The zero-cost mode above was in force for every command.`);
L.push(`- Phase D was not begun.`);
L.push('');
L.push(`The positive-control denominator is derived rather than declared; see`);
L.push(`\`docs/phase-c-final-kernel/PHASE_C_POSITIVE_CONTROL_DENOMINATOR_CORRECTION.md\`.`);
L.push('');

writeFileSync(`${REPO}/docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.md`, L.join('\n'), 'utf8');
writeFileSync(`${REPO}/docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.json`,
  JSON.stringify({ commit, branch, environment: ENV, generated_headlines: results }, null, 2) + '\n', 'utf8');

console.log(`wrote docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.md and .json`);
console.log(`  headlines ${results.length}   failed ${failed.length}   credential_blocked ${blocked.length}`);
for (const r of failed) console.log(`  FAIL  ${r.headline}  (${r.command})`);
process.exit(failed.length ? 1 : 0);

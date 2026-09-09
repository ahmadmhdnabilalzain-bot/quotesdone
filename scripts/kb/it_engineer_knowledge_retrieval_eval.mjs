// MEASURE public.it_engineer_knowledge AND fn_it_engineer_assist BY EXECUTION.
//
// THE EVALUATION QUESTIONS LIVE HERE AND NOWHERE ELSE. They are in executable code, not in a data
// file, and load_it_engineer_knowledge_pack.mjs admits only records/*.jsonl, so there is no manifest
// edit and no recursive-folder mistake that can put an exam answer into the corpus an agent
// retrieves. The estate has a documented defect where exactly that happened and 557 rows had to be
// quarantined; the separation here is structural rather than a convention.
//
// FIVE THINGS ARE MEASURED, and each fails loudly rather than printing a number nobody checks:
//   1  THE BANNED-SHAPE GUARD FIRES. Zero refusals at load time proves nothing on its own -- zero
//      cannot tell a dead guard from a clean corpus -- so the guard is run here against strings
//      that deliberately carry each of the six shapes, and every one must be rejected. The pattern
//      array is IMPORTED FROM THE LOADER, not copied: a copy would prove that a copy of the guard
//      bites, which is a different claim and is exactly the failure this corpus calls an instrument
//      measuring the wrong subject.
//   2  THE LIVE CORPUS CARRIES NONE OF THE SIX SHAPES. The same patterns are run over every live
//      row, authored and generated alike.
//   3  NONSENSE AND OUT-OF-SCOPE ARE REFUSED. Queries with no subject in either corpus must come
//      back answered:false.
//   4  BOTH GATES BITE, INDEPENDENTLY. Admission is cosine AND corroboration, so proving one fires
//      says nothing about the other. A question answered at the default settings must be refused
//      when the cosine floor alone is raised above its best hit, AND refused when corroboration
//      alone is raised with the cosine floor left where it was.
//   5  COVERAGE. Questions this seat would actually face -- including the three the founder named
//      by hand -- each with the record that should answer it, reported as an honest rate with every
//      failure printed rather than summarised away.
//
//   node scripts/kb/it_engineer_knowledge_retrieval_eval.mjs

import { sql, PROJECT_REF } from '../lib/db.mjs';
// The SAME array the loader enforces, from the side-effect-free module both import. Not a copy:
// a copy would prove that a copy of the guard bites, and would drift the first time one side was
// edited. Not imported from the loader itself either -- that file's top level connects to the
// database and runs a load, so borrowing a constant from it would run a load as a side effect.
import { BANNED_SHAPES, firstBanned } from './it_engineer_banned_shapes.mjs';

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }

async function embed(text) {
  const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: 'it_engineer_eval', action: 'embed', text }),
  });
  if (!res.ok) throw new Error(`ai_gateway HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  if (!j.embedding) throw new Error('ai_gateway returned no embedding');
  return typeof j.embedding === 'string' ? j.embedding : JSON.stringify(j.embedding);
}

const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
async function assist(text, { sim = 0.83, rank = 0.05, k = 5, overlap = 0.60 } = {}) {
  const v = await embed(text);
  const r = await sql(`select public.fn_it_engineer_assist(${q(text)}, ${q(v)}::vector(384),
                         ${sim}, ${rank}, ${k}, ${overlap}) as r`);
  return r[0].r;
}

let hardFail = 0;

// ---------------------------------------------------------------------------------------------
// 1. THE BANNED-SHAPE GUARD, PROVED TO FIRE -- USING THE LOADER'S OWN ARRAY
// ---------------------------------------------------------------------------------------------
console.log('--- 1. THE BANNED-SHAPE GUARD (patterns imported from the loader, not copied) ---');
console.log('shapes in the loader\'s array: ' + BANNED_SHAPES.length);
const MUST_REJECT = [
  ['CVE identifier',        'The relevant advisory is CVE-2026-31337 and it applies to this estate.'],
  ['GHSA identifier',       'Tracked upstream as GHSA-ab12-cd34-ef56 in the package registry.'],
  ['CVSS score',            'It carries a CVSS base score of 9.8, which makes it critical for us.'],
  ['version then verb',     'Our Postgres 15.4 is vulnerable to the row-security bypass described below.'],
  ['verb then version',     'The edge runtime is unpatched below 1.42.3 and must be upgraded before launch.'],
  ['patch-level assertion', 'The database is currently running 15.6 so the fix is already present here.'],
];
const MUST_PASS = [
  'When an advisory is published for a component this estate uses, determine whether it reaches us by reading the version the platform itself reports.',
  'The CVE process exists so a vulnerability has a stable name; this body holds no specific one because it cannot verify one.',
  'A file whose declared type and magic bytes disagree is quarantined and never opened in order to decide.',
  'Alert on ratios and rates of change rather than absolute counts, because a pre-launch system has small numbers.',
];
const shapesSeen = new Set();
for (const [label, s] of MUST_REJECT) {
  const hit = firstBanned(s);
  if (hit) shapesSeen.add(hit);
  console.log((hit ? 'REJECTED  ' : 'MISSED    ') + label.padEnd(23) + ' :: ' + (hit || '(nothing)'));
  if (!hit) hardFail++;
}
for (const s of MUST_PASS) {
  const hit = firstBanned(s);
  console.log((hit ? 'FALSE POS ' : 'PASSED    ') + (hit || '(nothing)').padEnd(23) + ' <- ' + s.slice(0, 62));
  if (hit) hardFail++;
}
// EVERY shape must have been exercised, not just "six strings were rejected". A shape no probe
// reaches is a shape nobody has shown to work, which is the whole point of section 1.
const unexercised = BANNED_SHAPES.map(([, w]) => w).filter((w) => !shapesSeen.has(w));
console.log('distinct shapes exercised: ' + shapesSeen.size + ' of ' + BANNED_SHAPES.length
  + (unexercised.length ? '  UNEXERCISED: ' + unexercised.join(' | ') : '  (all covered)'));
if (unexercised.length) hardFail++;

// ---------------------------------------------------------------------------------------------
// 2. THE LIVE CORPUS CARRIES NONE OF THE SIX SHAPES
// ---------------------------------------------------------------------------------------------
console.log('\n--- 2. THE LIVE CORPUS ---');
const live = await sql(`select record_id, epistemic_status, record_type, title, content, tags,
                               authority_effect, embedding_gte is not null as embedded
                          from public.it_engineer_knowledge order by record_id`);
const offenders = live.map((r) => [r.record_id, firstBanned(r.title + '\n' + r.content)]).filter(([, h]) => h);
console.log(`rows: ${live.length} | embedded: ${live.filter((r) => r.embedded).length} | offenders: ${offenders.length}`);
for (const [id, h] of offenders) console.log('  OFFENDER ' + id + ' contains ' + h);
if (offenders.length) hardFail++;

const carrying = live.filter((r) => r.authority_effect !== 'none').length;
console.log('rows carrying authority: ' + carrying + ' (the CHECK pins this at 0)');
if (carrying) hardFail++;

const byEpi = {}; for (const r of live) byEpi[r.epistemic_status] = (byEpi[r.epistemic_status] || 0) + 1;
console.log('epistemic labelling: ' + JSON.stringify(byEpi));
const byType = {}; for (const r of live) byType[r.record_type] = (byType[r.record_type] || 0) + 1;
console.log('record types:        ' + JSON.stringify(byType));

const grants = await sql(`select grantee, privilege_type from information_schema.role_table_grants
                           where table_schema='public' and table_name='it_engineer_knowledge'
                             and grantee in ('anon','authenticated')`);
console.log('grants to anon/authenticated: ' + grants.length + (grants.length ? ' :: ' + JSON.stringify(grants) : ' (none)'));
if (grants.length) hardFail++;

const fnGrants = await sql(`select count(*)::int n from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname='public' and p.proname='fn_it_engineer_assist'
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))`);
console.log('fn_it_engineer_assist executable by anon/authenticated: ' + fnGrants[0].n + ' (must be 0)');
if (fnGrants[0].n) hardFail++;

// ---------------------------------------------------------------------------------------------
// 3. NONSENSE AND OUT-OF-SCOPE MUST BE REFUSED
// ---------------------------------------------------------------------------------------------
console.log('\n--- 3. NONSENSE AND OUT OF SCOPE ---');
// Eight, spanning nonsense, another country's tax filing, a vehicle repair, a visa question, a
// recipe and a geography question. Deliberately NOT included: "which CVE number affects our
// database this month". That looks out of scope and is not -- this corpus exists partly to answer
// it, and it correctly returns the dated-threat-snapshot record whose whole content is the
// instruction never to quote an advisory as current without re-checking a live feed. It is scored
// in the coverage section instead, where it belongs. Calling a question nonsense because it is
// awkward, and then counting its refusal as a safety result, is the same self-flattery as a scorer
// reporting on its own fixtures.
const NONSENSE = [
  'zqxwv plkjh mnbvcx qwerty asdfgh',
  'purple elephant tessellation quantum knitting for beginners',
  'what is the best pizza restaurant in Naples and how do I book a table',
  'how do I replace the timing belt on a diesel van',
  'how do I bake sourdough bread at home',
  'what are the visa requirements for visiting Japan',
  'how do I file a United States federal tax return',
  'what is the capital city of Peru',
];
let nonsenseAdmitted = 0;
for (const t of NONSENSE) {
  const r = await assist(t);
  const f = r.floor || {};
  console.log((r.answered ? 'ADMITTED  ' : 'REFUSED   ') + (r.refusal || '').padEnd(42)
    + ' best_sim=' + (f.best_similarity ?? 'n/a') + ' lex ' + (f.best_lex_hits ?? '?') + '/' + (f.lexeme_overlap_needed ?? '?')
    + '  <- ' + t.slice(0, 46));
  if (r.answered) { nonsenseAdmitted++; console.log('    cited: ' + JSON.stringify(r.cited)); }
}
console.log(nonsenseAdmitted === 0 ? 'all ' + NONSENSE.length + ' refused'
  : 'FAILED: ' + nonsenseAdmitted + ' nonsense/out-of-scope quer(y|ies) admitted');
if (nonsenseAdmitted) hardFail++;

// ---------------------------------------------------------------------------------------------
// 4. BOTH GATES BITE, INDEPENDENTLY
// ---------------------------------------------------------------------------------------------
console.log('\n--- 4. BOTH GATES, PROVED SEPARATELY ---');
const PROBE = 'the comparison report is slow, where do I look';
const baseR = await assist(PROBE);
if (!baseR.answered) {
  console.log('CANNOT PROBE THE GATES: the base question is refused at the defaults -- ' + baseR.refusal);
  hardFail++;
} else {
  const bs = Number(baseR.floor.best_similarity);
  // Raise the COSINE FLOOR alone, above the best hit. Corroboration left at its default.
  const cosOnly = await assist(PROBE, { sim: Math.min(0.999, bs + 0.02) });
  console.log('cosine floor raised to ' + Math.min(0.999, bs + 0.02).toFixed(4)
    + ' (best hit was ' + bs.toFixed(4) + ') -> ' + (cosOnly.answered ? 'STILL ANSWERED (gate dead)' : 'refused: ' + cosOnly.refusal));
  if (cosOnly.answered) hardFail++;
  // Raise CORROBORATION alone -- BOTH of its routes. Cosine floor left exactly where it was.
  //
  // rank is 1.5 and that number is MEASURED, not chosen. The first version of this probe used 0.99
  // and the gate did not bite: the correct record's ts_rank came back at exactly 1.0000, so
  // lexical_rank >= 0.99 was still true and the all-terms route stayed open. ts_rank is not bounded
  // below 1 here. Closing only the overlap route while leaving the rank route open proves nothing,
  // because the two routes are OR-ed -- either one alone admits. So the probe has to close both.
  // Left at 0.99 this section would have reported a dead gate that is in fact alive, which is its
  // own instrument-measuring-the-wrong-subject failure.
  const corrOnly = await assist(PROBE, { overlap: 1.01, rank: 1.5 });
  console.log('corroboration raised to overlap 1.01 / rank 1.5 (both routes closed), cosine floor unchanged at 0.83 -> '
    + (corrOnly.answered ? 'STILL ANSWERED (gate dead)' : 'refused: ' + corrOnly.refusal));
  if (corrOnly.answered) hardFail++;
  console.log('the two gates fail independently, so each had to be shown to bite on its own');
}

// ---------------------------------------------------------------------------------------------
// 5. COVERAGE OVER QUESTIONS THIS SEAT WOULD ACTUALLY FACE
//
// The three the founder named by hand are marked FOUNDER. Every expected record is one this seat
// should reach; a question is a HIT when the expected record is cited, a NEAR MISS when something
// else was cited (recorded, not counted as a pass), and a REFUSAL when nothing cleared the gates.
// ---------------------------------------------------------------------------------------------
console.log('\n--- 5. COVERAGE ---');
const QUESTIONS = [
  // The founder's three, verbatim in substance.
  ['FOUNDER the comparison report is slow, where do I look', 'it_engineer_knowledge:QD-ITE-F-001'],
  ['FOUNDER a supplier uploaded a file, how do I know it is safe', 'it_engineer_knowledge:QD-ITE-S-001'],
  ['FOUNDER registration is failing for one customer but not others', 'it_engineer_knowledge:QD-ITE-F-002'],
  // Monitoring and detection.
  ['what should I monitor across the app and the website', 'it_engineer_knowledge:QD-ITE-M-007'],
  ['how do I build a detection that will still be true in six months', 'it_engineer_knowledge:QD-ITE-S-010'],
  ['what does an attack look like in our own signals', 'it_engineer_knowledge:QD-ITE-S-003'],
  ['the alert fired and nobody heard it', 'it_engineer_knowledge:QD-ITE-F-011'],
  ['a guard has never fired, does that mean the system is clean', 'it_engineer_knowledge:QD-ITE-L-002'],
  ['an alert fires constantly and everybody stopped listening', 'it_engineer_knowledge:QD-ITE-F-011'],
  // The scheduler, which is the least obvious part of the topology.
  ['nothing has run on a timer today, where do I start', 'it_engineer_knowledge:QD-ITE-F-003'],
  ['is pg_cron still running our scheduled jobs', 'it_engineer_knowledge:QD-ITE-A-003'],
  ['what drives the schedule now that cron is gone', 'it_engineer_knowledge:QD-ITE-A-004'],
  ['what does resilience_ping actually do on each tick', 'it_engineer_knowledge:QD-ITE-A-005'],
  // Registration and identity.
  ['which function actually creates a customer account', 'it_engineer_knowledge:QD-ITE-A-009'],
  ['a user sees different data on different requests', 'it_engineer_knowledge:QD-ITE-F-013'],
  ['can a customer sign up with only a mobile number', 'it_engineer_knowledge:QD-ITE-A-009'],
  // The comparison path.
  ['why does the comparison cache never hold anything', 'it_engineer_knowledge:QD-ITE-A-010'],
  ['where is the comparison report stored', 'it_engineer_knowledge:QD-ITE-A-010'],
  // Deploys and drift.
  ['a routine in production does not match the repository', 'it_engineer_knowledge:QD-ITE-F-006'],
  ['how does code actually reach production here', 'it_engineer_knowledge:QD-ITE-A-006'],
  ['what does deployed mean and how do I verify it', 'it_engineer_knowledge:QD-ITE-M-003'],
  ['should I roll this change back', 'it_engineer_knowledge:QD-ITE-M-008'],
  // Security operations.
  ['a file was judged hostile, what do I do with it now', 'it_engineer_knowledge:QD-ITE-S-002'],
  ['a secret appeared in a log, what is the procedure', 'it_engineer_knowledge:QD-ITE-S-008'],
  ['do our credentials rotate themselves', 'it_engineer_knowledge:QD-ITE-A-008'],
  ['is a published vulnerability relevant to this estate', 'it_engineer_knowledge:QD-ITE-S-004'],
  ['can customer text reach our agents and influence them', 'it_engineer_knowledge:QD-ITE-S-005'],
  ['could somebody poison the knowledge our agents read', 'it_engineer_knowledge:QD-ITE-S-006'],
  // Permissions and data.
  ['I revoked the permission and the role can still do it', 'it_engineer_knowledge:QD-ITE-F-007'],
  ['a foreign key started refusing every write after a cleanup', 'it_engineer_knowledge:QD-ITE-L-011'],
  // Diagnosis method.
  ['what should I establish before touching anything', 'it_engineer_knowledge:QD-ITE-M-001'],
  ['how do I verify a write without leaving one behind', 'it_engineer_knowledge:QD-ITE-M-002'],
  ['I cannot reproduce the problem the customer reported', 'it_engineer_knowledge:QD-ITE-M-010'],
  ['everything is slow at once, what does that mean', 'it_engineer_knowledge:QD-ITE-F-009'],
  ['the endpoint returns two hundred and nothing happened', 'it_engineer_knowledge:QD-ITE-F-004'],
  ['how do I read a log without drowning in it', 'it_engineer_knowledge:QD-ITE-M-009'],
  ['how severe is this when we have no customers yet', 'it_engineer_knowledge:QD-ITE-M-011'],
  ['provider spend suddenly went up, is that demand', 'it_engineer_knowledge:QD-ITE-F-012'],
  // Boundaries.
  ['should I email the founder about this incident', 'it_engineer_knowledge:QD-ITE-S-007'],
  // Answered from the OTHER corpus on purpose: this body holds no advisory identifier, and the
  // union reaches the it_security_deep record that is itself the staleness disclaimer. If this one
  // ever starts citing an it_engineer_knowledge record instead, something has put a specific
  // advisory into this body and the loader guard failed.
  ['which CVE number affects our database this month', 'ops_knowledge:itsec_stack-threat-snapshot-cves_01'],
  ['which supabase project do I deploy to', 'it_engineer_knowledge:QD-ITE-A-002'],
];

let hit = 0, nearMiss = 0, refusal = 0;
const failures = [];
for (const [text, expected] of QUESTIONS) {
  const clean = text.replace(/^FOUNDER /, '');
  const r = await assist(clean);
  const cited = r.cited || [];
  const f = r.floor || {};
  if (!r.answered) {
    refusal++;
    failures.push([text, 'REFUSED (' + r.refusal + ')', expected, 'best_sim=' + f.best_similarity + ' lex=' + f.best_lex_hits + '/' + f.lexeme_overlap_needed]);
    console.log('REFUSAL   ' + clean.slice(0, 58));
  } else if (cited.includes(expected)) {
    hit++;
    const pos = cited.indexOf(expected) + 1;
    console.log('HIT   @' + pos + '   ' + clean.slice(0, 58));
  } else {
    nearMiss++;
    failures.push([text, 'CITED SOMETHING ELSE', expected, cited.slice(0, 3).join(', ')]);
    console.log('NEAR MISS ' + clean.slice(0, 58));
  }
}

console.log('\nCOVERAGE  ' + hit + '/' + QUESTIONS.length + ' hit the expected record'
  + '  |  ' + nearMiss + ' cited something else  |  ' + refusal + ' refused');
if (failures.length) {
  console.log('\nEVERY FAILURE, IN FULL:');
  for (const [t, why, exp, got] of failures) {
    console.log('  ' + t);
    console.log('      ' + why + '  expected ' + exp);
    console.log('      got: ' + got);
  }
} else {
  console.log('no failures to report');
}

console.log('\n=== VERDICT ===');
console.log('hard failures (guard, corpus, grants, nonsense, gates): ' + hardFail);
console.log('coverage: ' + hit + '/' + QUESTIONS.length + ' (' + ((hit / QUESTIONS.length) * 100).toFixed(1) + '%)');
process.exit(hardFail === 0 ? 0 : 1);

// MEASURE public.accountant_knowledge AND fn_accountant_assist BY EXECUTION.
//
// THE EVALUATION QUESTIONS LIVE HERE AND NOWHERE ELSE. They are in executable code, not in a data
// file, and load_accountant_knowledge_pack.mjs admits only records/*.jsonl, so there is no manifest
// edit and no recursive-folder mistake that can put an exam answer into the corpus an agent
// retrieves. The estate has a documented defect where exactly that happened and 557 rows had to be
// quarantined; the separation here is structural rather than a convention.
//
// FIVE THINGS ARE MEASURED, and each one fails loudly rather than printing a number nobody checks:
//   1  THE NO-FIGURES TRIPWIRE FIRES. Zero refusals at load time proves nothing on its own -- zero
//      cannot tell a dead guard from a clean corpus -- so the guard is run here against a record
//      that deliberately contains a rate, and it must reject it.
//   2  THE CORPUS HOLDS NO FIGURES. The same patterns are run over every live row whose
//      epistemic_status claims it holds none.
//   3  NONSENSE IS REFUSED. Four queries with no subject in the corpus must come back answered:false.
//   4  BOTH GATES BITE, INDEPENDENTLY. Admission is cosine AND corroboration, so proving one fires
//      says nothing about the other. A question answered at the default settings must be refused
//      when the cosine floor alone is raised above its best hit, AND refused when corroboration
//      alone is raised with the cosine floor left where it was. This matters more than it looks:
//      the nearest nonsense probe reaches cosine 0.8353 against a 0.86 floor, a margin of 0.025,
//      and it is the corroboration gate rather than that margin that is doing the real work.
//   5  COVERAGE. 35 questions an accountant for this company would actually face, each with the
//      record that should answer it, reported as an honest rate rather than asserted.
//
//   node scripts/kb/accountant_knowledge_retrieval_eval.mjs

import { sql, PROJECT_REF } from '../lib/db.mjs';

const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
if (!secret) { console.error('no cred_fn_ai in app_secrets'); process.exit(2); }

async function embed(text) {
  const res = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ __secret: secret, fn: 'accountant_eval', action: 'embed', text }),
  });
  if (!res.ok) throw new Error(`ai_gateway HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const j = await res.json();
  if (!j.embedding) throw new Error('ai_gateway returned no embedding');
  return typeof j.embedding === 'string' ? j.embedding : JSON.stringify(j.embedding);
}

const q = (s) => "'" + String(s).replace(/'/g, "''") + "'";
async function assist(text, { sim = 0.86, rank = 0.05, k = 5, overlap = 0.60 } = {}) {
  const v = await embed(text);
  const r = await sql(`select public.fn_accountant_assist(${q(text)}, ${q(v)}::vector(384),
                         ${sim}, ${rank}, ${k}, ${overlap}) as r`);
  return r[0].r;
}

// ---------------------------------------------------------------------------------------------
// 1. THE NO-FIGURES TRIPWIRE, PROVED TO FIRE
// ---------------------------------------------------------------------------------------------
const FIGURE_PATTERNS = [
  [/\b\d+(?:\.\d+)?\s*(?:%|per\s*cent|percent)/i, 'a percentage'],
  [/\b(?:AED|aed|dirhams?)\s*[\d,]/i, 'an amount in AED'],
  [/[\d,]+\s*(?:AED|aed|dirhams?)\b/i, 'an amount in AED'],
  [/\b(?:within|after|before|every|for)\s+\d+\s+(?:days?|months?|years?|weeks?)\b/i, 'a deadline or retention period'],
  [/\b\d+\s+(?:days?|months?|years?)\s+(?:from|of|after|following)\b/i, 'a deadline in days/months/years'],
];
const firstFigure = (t) => (FIGURE_PATTERNS.find(([re]) => re.test(t)) || [null, null])[1];

const TRIPWIRE_MUST_REJECT = [
  'The standard rate of VAT is 5% on taxable supplies.',
  'Registration is mandatory once taxable supplies exceed AED 375,000.',
  'The return must be filed within 28 days of the end of the tax period.',
  'Records must be retained for 5 years from the end of the tax period.',
];
const TRIPWIRE_MUST_PASS = [
  'The rate is published by the Federal Tax Authority and must be read from its current publication.',
  'Account 1650 has a normal credit balance and reduces the cost account it sits against.',
];
let tripFail = 0;
console.log('--- 1. THE NO-FIGURES TRIPWIRE ---');
for (const t of TRIPWIRE_MUST_REJECT) {
  const hit = firstFigure(t);
  console.log((hit ? 'REJECTED  ' : 'MISSED    ') + (hit || '(nothing)') + '  <- ' + t.slice(0, 62));
  if (!hit) tripFail++;
}
for (const t of TRIPWIRE_MUST_PASS) {
  const hit = firstFigure(t);
  console.log((hit ? 'FALSE POS ' : 'PASSED    ') + (hit || '(nothing)') + '  <- ' + t.slice(0, 62));
  if (hit) tripFail++;
}
console.log(tripFail === 0
  ? 'tripwire: fires on all 4 figure-bearing strings, quiet on both clean ones'
  : 'TRIPWIRE FAILED on ' + tripFail + ' case(s)');

// ---------------------------------------------------------------------------------------------
// 2. THE LIVE CORPUS HOLDS NO FIGURES WHERE IT CLAIMS TO HOLD NONE
// ---------------------------------------------------------------------------------------------
console.log('\n--- 2. THE LIVE CORPUS ---');
const live = await sql(`select record_id, epistemic_status, title, content, tags, authority_effect
                          from public.accountant_knowledge order by record_id`);
const noFig = live.filter((r) => r.epistemic_status === 'obligation_shape_no_figures'
                              || r.epistemic_status === 'resolve_from_authority');
const offenders = noFig.map((r) => [r.record_id, firstFigure(r.content)]).filter(([, h]) => h);
console.log(`rows: ${live.length} | claiming to hold no figures: ${noFig.length} | offenders: ${offenders.length}`);
for (const [id, h] of offenders) console.log('  OFFENDER ' + id + ' contains ' + h);
const carrying = live.filter((r) => r.authority_effect !== 'none').length;
console.log('rows carrying authority: ' + carrying + ' (the CHECK pins this at 0)');

const byEpi = {}; for (const r of live) byEpi[r.epistemic_status] = (byEpi[r.epistemic_status] || 0) + 1;
console.log('epistemic labelling: ' + JSON.stringify(byEpi));

const grants = await sql(`select grantee, privilege_type from information_schema.role_table_grants
                           where table_schema='public' and table_name='accountant_knowledge'
                             and grantee in ('anon','authenticated')`);
console.log('grants to anon/authenticated: ' + grants.length + (grants.length ? ' :: ' + JSON.stringify(grants) : ' (none)'));

// ---------------------------------------------------------------------------------------------
// 3. NONSENSE AND OUT-OF-SCOPE MUST BE REFUSED
// ---------------------------------------------------------------------------------------------
console.log('\n--- 3. NONSENSE AND OUT OF SCOPE ---');
const NONSENSE = [
  'zqxwv plkjh mnbvcx qwerty asdfgh',
  'purple elephant tessellation quantum knitting for beginners',
  'how do I file a United States federal Form 1040 Schedule C',
  'what is the best pizza restaurant in Naples and how do I book a table',
];
let nonsenseAnswered = 0;
for (const text of NONSENSE) {
  const r = await assist(text);
  const best = (r.candidates || []).reduce((m, c) => Math.max(m, c.similarity ?? 0), 0);
  console.log((r.answered ? 'ANSWERED  ' : 'refused   ') + (r.refusal || '-').padEnd(40)
    + ' best cosine ' + best.toFixed(4) + '  <- ' + text.slice(0, 48));
  if (r.answered) nonsenseAnswered++;
}
console.log(nonsenseAnswered === 0
  ? 'nonsense: 0 of ' + NONSENSE.length + ' answered'
  : 'NONSENSE LEAK: ' + nonsenseAnswered + ' of ' + NONSENSE.length + ' answered');

// ---------------------------------------------------------------------------------------------
// 5. COVERAGE OVER REALISTIC ACCOUNTANT QUESTIONS
// ---------------------------------------------------------------------------------------------
// Each entry: the question, and the record_id that SHOULD answer it. A question that is answered
// by some other record still counts as answered but not as hit, and the two rates are reported
// separately -- collapsing them would let a corpus that answers everything with the wrong record
// score the same as one that answers correctly.
const QUESTIONS = [
  ['how do I record a refund to a customer',                                'QD-ACC-Q-007'],
  ['does the accountant approve refunds or does someone else',              'QD-ACC-Q-008'],
  ['who approves Meta ads spend',                                           'QD-ACC-Q-016'],
  ['what is the UAE VAT rate',                                              'QD-ACC-U-007'],
  ['are we registered for VAT',                                             'QD-ACC-POSITION-VAT'],
  ['do we have a TRN',                                                      'QD-ACC-U-008'],
  ['when must a business register for VAT in the UAE',                      'QD-ACC-U-006'],
  ['should I ask the founder about corporate tax registration',             'QD-ACC-POSITION-CORPORATE-TAX'],
  ['do we need an auditor appointed',                                       'QD-ACC-POSITION-AUDITOR'],
  ['how long must accounting records be retained',                          'QD-ACC-U-018'],
  ['what is the penalty for filing a tax return late',                      'QD-ACC-U-019'],
  ['what is the reverse charge mechanism',                                  'QD-ACC-U-013'],
  ['what is the difference between zero rated and exempt supplies',         'QD-ACC-U-012'],
  ['what is our trade licence number and who issued it',                    'QD-ACC-POSITION-LICENCE'],
  ['which account do payment processing fees go to',                        'QD-ACC-COA-6100'],
  ['what is account 1650 accumulated depreciation for',                     'QD-ACC-COA-1650'],
  ['how do I record depreciation on a fixed asset',                         'QD-ACC-M-013'],
  ['what is the difference between accrual and cash basis accounting',      'QD-ACC-M-007'],
  ['how do I reconcile the bank statement to the ledger',                   'QD-ACC-M-030'],
  ['what does a trial balance actually prove',                              'QD-ACC-M-006'],
  ['how should an annual software subscription be expensed',                'QD-ACC-Q-015'],
  ['when is the reveal fee recognised as revenue',                          'QD-ACC-Q-003'],
  ['is our marketplace revenue reported gross or net',                      'QD-ACC-Q-001'],
  ['how do I record supplier commission that has been earned',              'QD-ACC-Q-004'],
  ['what do I do with a receipt I cannot classify',                         'QD-ACC-Q-018'],
  ['a receipt arrived twice, how do I avoid double counting the expense',   'QD-ACC-M-035'],
  ['how do I correct a journal entry that was posted wrongly',              'QD-ACC-M-018'],
  ['what is deferred revenue and when do I use it',                         'QD-ACC-M-010'],
  ['how do I calculate runway and burn',                                    'QD-ACC-M-025'],
  ['what is a chargeback and how does it differ from a refund',             'QD-ACC-Q-009'],
  ['what are the steps in the month end close',                             'QD-ACC-M-016'],
  ['how do I record an expense paid in a foreign currency',                 'QD-ACC-Q-014'],
  ['is this cost capital expenditure or an expense',                        'QD-ACC-Q-013'],
  ['what does materiality mean when deciding what to chase',                'QD-ACC-M-026'],
  ['how do I write off a bad debt',                                         'QD-ACC-M-015'],
];

console.log('\n--- 5. COVERAGE OVER ' + QUESTIONS.length + ' REALISTIC QUESTIONS ---');
let answered = 0, hit = 0, hitTop1 = 0;
const misses = [], wrongRecord = [];
const results = [];
for (const [text, expect] of QUESTIONS) {
  const r = await assist(text);
  const cited = r.cited || [];
  const ids = cited.map((c) => c.split(':').slice(1).join(':'));
  const isHit = ids.includes(expect);
  const isTop1 = ids[0] === expect;
  if (r.answered) answered++;
  if (isHit) hit++;
  if (isTop1) hitTop1++;
  const best = (r.candidates || []).reduce((m, c) => Math.max(m, c.similarity ?? 0), 0);
  results.push({ text, expect, answered: r.answered, isHit, best, top: ids[0] || null, refusal: r.refusal });
  if (!r.answered) misses.push([text, expect, best, r.refusal]);
  else if (!isHit) wrongRecord.push([text, expect, ids.slice(0, 3)]);
  console.log((r.answered ? (isHit ? (isTop1 ? 'HIT@1 ' : 'HIT@k ') : 'OTHER ') : 'REFUSE')
    + ' cos ' + best.toFixed(4) + '  ' + (ids[0] || '-').padEnd(30) + '  ' + text.slice(0, 56));
}

console.log('\nANSWERED   ' + answered + '/' + QUESTIONS.length + '  (' + (100 * answered / QUESTIONS.length).toFixed(1) + '%)');
console.log('EXPECTED RECORD IN TOP ' + 5 + '  ' + hit + '/' + QUESTIONS.length + '  (' + (100 * hit / QUESTIONS.length).toFixed(1) + '%)');
console.log('EXPECTED RECORD RANKED FIRST  ' + hitTop1 + '/' + QUESTIONS.length + '  (' + (100 * hitTop1 / QUESTIONS.length).toFixed(1) + '%)');
if (misses.length) {
  console.log('\nREFUSED (a gap, not a failure -- the seat says so rather than guessing):');
  for (const [t, e, b, why] of misses) console.log('  ' + t + '\n     expected ' + e + ', best cosine ' + b.toFixed(4) + ', refusal ' + why);
}
if (wrongRecord.length) {
  console.log('\nANSWERED BY A DIFFERENT RECORD:');
  for (const [t, e, got] of wrongRecord) console.log('  ' + t + '\n     expected ' + e + ', got ' + got.join(', '));
}

// ---------------------------------------------------------------------------------------------
// 4. THE FLOOR BITES -- run last, because it needs a question the default floor answers
// ---------------------------------------------------------------------------------------------
console.log('\n--- 4. BOTH GATES BITE, INDEPENDENTLY ---');
let gatesBite = false;
const proven = results.find((r) => r.answered && r.best > 0);
if (!proven) {
  console.log('cannot prove the gates: no question was answered at the default settings');
} else {
  const above = Math.min(0.999, Number((proven.best + 0.02).toFixed(4)));
  console.log('question: ' + proven.text);
  console.log('  default (cosine 0.86, rank 0.05, overlap 0.60)  -> answered true, best hit ' + proven.best.toFixed(4));

  // GATE A -- the cosine floor, on its own. Corroboration left exactly where it was.
  const cosOnly = await assist(proven.text, { sim: above });
  console.log('  cosine raised to ' + above + ', corroboration unchanged -> answered ' + cosOnly.answered
    + ', refusal ' + (cosOnly.refusal || '-'));

  // GATE B -- corroboration, on its own. The cosine floor is left at its default, so a refusal
  // here can only have come from corroboration. Both routes are closed together: rank to 0.99
  // shuts the all-terms route and the tied lexical-only bar with it, and the overlap bar is set
  // from what the corpus ACTUALLY achieves rather than from a round number.
  //
  // BOTH BARS ARE COMPUTED FROM WHAT THE CORPUS ACTUALLY ACHIEVES, and two earlier versions of
  // this probe are the reason. Overlap 1.0 left the question answered -- not because the gate was
  // dead but because the correct record genuinely carries all three of its lexemes, so 1.0 was
  // satisfiable. Then rank 0.99 left it answered too: ts_rank reached 0.9978 on a record whose
  // TITLE carries the query terms at weight A, so 0.99 is not the ceiling it looks like. A bar the
  // corpus can clear proves nothing about a bar. Each is now set one step above the measured best.
  const base = await assist(proven.text);
  const nlex = base.floor.lexemes_in_question;
  const bestLex = base.floor.best_lex_hits ?? 0;
  const bestRank = Number(base.floor.best_lexical_rank ?? 0);
  const barOverlap = (bestLex + 1) / Math.max(nlex, 1);
  const barRank = Number((bestRank + 0.001).toFixed(4));
  const corrOnly = await assist(proven.text, { rank: barRank, overlap: barOverlap });
  console.log('  measured best: lexical rank ' + bestRank.toFixed(4) + ', lexeme overlap '
    + bestLex + '/' + nlex);
  console.log('  bars set just above both: rank ' + barRank + ', overlap ' + barOverlap.toFixed(3)
    + ' (needs ' + (bestLex + 1) + ' of ' + nlex + ')');
  console.log('  cosine unchanged, corroboration raised -> answered ' + corrOnly.answered
    + ', refusal ' + (corrOnly.refusal || '-'));

  gatesBite = !cosOnly.answered && !corrOnly.answered
    && corrOnly.refusal === 'not_corroborated_lexically';
  console.log(gatesBite
    ? 'both gates bite: raising either one alone refuses a question the pair together answers'
    : 'A GATE DID NOT BITE -- admission is not the conjunction it claims to be');
}

const ok = tripFail === 0 && offenders.length === 0 && carrying === 0 && grants.length === 0
        && nonsenseAnswered === 0 && gatesBite;
console.log('\nVERDICT: ' + (ok ? 'guards hold' : 'A GUARD FAILED -- see above'));
process.exit(ok ? 0 : 1);

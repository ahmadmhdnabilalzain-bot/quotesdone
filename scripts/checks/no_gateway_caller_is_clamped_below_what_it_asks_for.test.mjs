// NO GATEWAY CALLER IS CLAMPED BELOW WHAT IT ASKS FOR (it_engineer, 23 Sep 2026).
//
// Recurrence guard for scripts/sql/every_seat_gets_the_model_its_own_work_needs.sql §2 and §3.
//
// THE CAUSE. ai_gateway/index.ts:326 resolves the output ceiling as
//   Math.min(Number(body.max ?? route.max_tokens ?? 700), Number(route.max_tokens ?? 4000))
// so the ROUTE always wins. A caller that asks for more than its task class allows is silently
// truncated, and truncation is indistinguishable from a bad model: supplier_catalog_ingest asked
// for 3000 with response_format 'json', landed on general_drafting because it had no fn_task_class
// row, was clamped to 900, and recorded 'extraction_failed' about a catalogue nobody had read.
// email_triage cost two paid requests for nothing the same way (founder instruction 705), and
// drawing_redact's verify pass cost a whole session to a 400-token ceiling misdiagnosed as an
// unparseable model.
//
// THIS CHECK FAILS IF:
//   * a function calls ai_gateway and is not routed at all - a new caller is unrouted until someone
//     decides which class it belongs to, which is the decision that was skipped every time;
//   * a caller asks for more tokens than its class allows;
//   * a ceiling this PR set drifts below what its caller asks for.
//
// Repository only: no database, no token, no model. CEILINGS are the max_tokens each class allows.
// The rows this PR writes are READ OUT OF ITS OWN SQL FILE, so the two cannot disagree; the rest are
// measured from production on 23 Sep 2026 and named as such.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const OWNING_SQL = 'scripts/sql/every_seat_gets_the_model_its_own_work_needs.sql';

// fn LABELS, not directory names: wa_inbound sends three (its own, founder_directive,
// supplier_directive) and drawing_redact sends two.
//
// THE ROWS THAT ALREADY EXISTED on production, read from public.fn_task_class 23 Sep 2026. These are
// not what this PR changes, so a constant is honest here — and any drift in them shows up as an
// unrouted caller or a clamp below.
const CALLER_CLASS_PREEXISTING = {
  doc_extract: 'document_extraction',
  drawing_boq: 'document_extraction',
  drawing_redact: 'document_extraction',
  email_triage: 'intent_detection',
  extract_text: 'document_extraction',
  founder_directive: 'chief_of_staff_decision',
  inquiry_intake: 'agent_reasoning',
  license_extract: 'document_extraction',
  quote_compare: 'quote_comparison',
  quote_extract: 'document_extraction',
  resend_inbound: 'intent_detection',
  site_assistant: 'visitor_chat',
  supplier_directive: 'agent_reasoning',
  supplier_onboard: 'procurement_reasoning',
  transcribe: 'speech_transcription',
  wa_inbound: 'customer_communication',
};

// 29 Sep 2026 (founder_instruction 1056): the sales engineer's functions moved onto its own classes. READ OUT OF the
// file that moves them (its fn_task_class update), applied LAST, so a mapping deleted there fails here.
const MATRIX_SQL = 'scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql';
const callerClassMovedByMatrix = () => {
  const sql = read(MATRIX_SQL);
  const block = sql.slice(sql.indexOf('update public.fn_task_class t'), sql.indexOf(') as v(fn, cls)'));
  const out = {};
  for (const m of block.matchAll(/\('([a-z0-9_]+)',\s*'([a-z0-9_]+)'\)/g)) out[m[1]] = m[2];
  assert.ok(Object.keys(out).length >= 15, `only ${Object.keys(out).length} moves parsed out of ${MATRIX_SQL}`);
  return out;
};

// THE ROWS THIS PR ADDS OR MOVES, and they are READ OUT OF THE SQL FILE rather than copied here.
// This is the whole point of the check (corrected 23 Sep 2026 in review): the original defect was a
// MISSING fn_task_class row — supplier_catalog_ingest had none, fell to general_drafting, and was
// clamped 3000 -> 900. With the mapping hardcoded, deleting that row from the SQL again would leave
// this check passing, so it could not fail on its own original input. Now it reads the rows from the
// file that writes them, and a deletion there fails here.
const PR_ROWS_EXPECTED = ['ceo_agent', 'supplier_catalog_ingest', 'marketing_social_inbox', 'drawing_redact_verify'];

const callerClassFromOwningSql = () => {
  const sql = read(OWNING_SQL);
  const out = {};
  // insert into public.fn_task_class as ftc (...) values ('<fn>', '<class>', '<dept>', true, ...)
  for (const m of sql.matchAll(/\('([a-z0-9_]+)', '([a-z0-9_]+)', '([a-z_]+)', true,/g)) {
    out[m[1]] = m[2];
  }
  // the drawing_redact_verify move: update ... set task_class = '<class>' ... where fn = '<fn>'
  for (const m of sql.matchAll(
    /update public\.fn_task_class set\s*\n?\s*task_class = '([a-z0-9_]+)',[\s\S]{0,1200}?where fn = '([a-z0-9_]+)';/g,
  )) {
    out[m[2]] = m[1];
  }
  const missing = PR_ROWS_EXPECTED.filter((fn) => !(fn in out));
  assert.deepEqual(missing, [],
    `${OWNING_SQL} no longer routes ${missing.join(', ')}. That file exists because a gateway caller `
    + 'with no fn_task_class row falls to general_drafting — haiku at 900 tokens — AND sits outside '
    + 'every department ceiling, because fn_ai_route finds the budget by fn_task_class.dept_key. '
    + 'supplier_catalog_ingest was clamped 3000 -> 900 exactly this way and recorded '
    + '"extraction_failed" about a catalogue nobody had read.');
  return out;
};

// 27 Oct 2026 (#1640 review): the portal chat turn became a direct gateway call labelled 'sales_engineer'. Its row is
// READ OUT OF the file that writes it, like the owning file's, so deleting it there fails here.
const PORTAL_TURN_SQL = 'scripts/sql/the_portal_turn_has_its_task_class.sql';
const callerClassFromPortalTurnSql = () => {
  const sql = read(PORTAL_TURN_SQL);
  const out = {};
  const at = sql.indexOf('insert into public.fn_task_class');
  if (at >= 0) for (const m of sql.slice(at).matchAll(/\('([a-z0-9_]+)',\s*'([a-z0-9_]+)'/g)) out[m[1]] = m[2];
  return out;
};

const callerClass = () => ({ ...CALLER_CLASS_PREEXISTING, ...callerClassFromOwningSql(), ...callerClassMovedByMatrix(), ...callerClassFromPortalTurnSql() });

// Ceilings NOT written by the owning SQL file, measured from public.model_policy on 23 Sep 2026.
const CEILINGS_MEASURED = {
  agent_reasoning: 8000,
  chief_of_staff_decision: 4000,
  customer_communication: 800,
  document_extraction: 8000,
  intent_detection: 800,
  marketing_copy: 1200,
  procurement_reasoning: 4000,   // 1500 on 23 Sep; 4000 on production 29 Sep (opus_5_5_classes_leave_room_for_thinking.sql)
  quote_comparison: 10000,
  speech_transcription: 1024,
  visitor_chat: 900,
  // founder_instruction 1056 (29 Sep 2026): the classes the sales engineer's functions moved to. The matrix file
  // copies each seat route's ceiling from its base class at apply (b.max_tokens), so these are the base values read
  // from public.model_policy on 29 Sep 2026; drawing_and_boq_analysis is raised to 8000 by the file itself, the 8000
  // drawing_boq asks for. fn_ai_route also floors a seat's own row at the class's ceiling.
  sales_engineer__document_extraction: 8000,
  sales_engineer__json_extraction: 4000,
  sales_engineer__procurement_reasoning: 4000,
  inquiry_qualification_conversation: 4000,
  customer_portal_assistant: 4000,
  drawing_and_boq_analysis: 8000,
};

// The ceilings this PR sets, read out of the file that sets them so a later edit to one moves both.
const ceilingsFromOwningSql = () => {
  const sql = read(OWNING_SQL);
  const out = {};
  // insert ... values ('<class>', '<tier>', '<primary>', '<fallback>', <max>, true, ...)
  for (const m of sql.matchAll(/\(\s*'([a-z0-9_]+)'\s*,\s*'(?:small|medium|large|xlarge)'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*(\d+)\s*,\s*true/g)) {
    out[m[1]] = Number(m[2]);
  }
  // update ... max_tokens = <n> ... where task_class = '<class>'
  for (const m of sql.matchAll(/max_tokens\s*=\s*(\d+),[\s\S]{0,4000}?where task_class = '([a-z0-9_]+)'/g)) {
    out[m[2]] = Number(m[1]);
  }
  return out;
};

// What each caller asks ai_gateway for. Absent `max` means the caller takes the route's ceiling,
// which can never be a clamp - drawing_redact_verify deliberately sends none.
const SELF_CLASSED = new Map();
const requestedMax = () => {
  SELF_CLASSED.clear();
  const root = 'supabase/functions';
  const asks = {};
  const files = [];
  for (const d of readdirSync(join(REPO, root))) {
    if (d === 'ai_gateway' || d.startsWith('_')) continue;
    const p = join(REPO, root, d, 'index.ts');
    try { if (!statSync(p).isFile()) continue; } catch { continue; }
    // Every file of the function: a split moves the gateway call out of index.ts (resend_inbound: lib/runtime.ts).
    // The CEO's plan budgets (plan.ts PLAN_CALL) are asked under their own task class, not ceo_agent's row: they are
    // checked against those classes by the test below, so they are not attributed to the ceo_agent label here.
    const src = d === 'ceo_agent' ? functionSource(d).replace(PLAN_CALL_BLOCK, '') : functionSource(d);
    if (!/functions\/v1\/ai_gateway|makeLlmRich|makeLlm\(/.test(src)) continue;
    files.push(d);
    const lines = src.split('\n');
    lines.forEach((l, i) => {
      const mx = /\bmax:\s*(\d+)/.exec(l);
      if (!mx) return;
      const ctx = lines.slice(Math.max(0, i - 14), i + 14).join('\n');
      // A `max:` with no gateway call near it is not an ask (17 Nov 2026: it_engineer's runExamBatch option
      // `{ budgetMs, itemMs, max: 3 }`, items per post, was read as the it_engineer label asking for 3 tokens).
      if (!/makeLlm|ai_gateway|\bfn:|taskClass|task_class/.test(ctx)) return;
      const fn = /\bfn:\s*['"]([a-z0-9_]+)['"]/.exec(ctx)?.[1] ?? d;
      asks[fn] = Math.max(asks[fn] ?? 0, Number(mx[1]));
    });
    // Every fn label this file sends, whether or not it names a max.
    const labels = [...src.matchAll(/\bfn:\s*['"]([a-z0-9_]+)['"]/g)].map((m) => m[1]);
    for (const l of labels) asks[l] ??= 0;
    // A label sent with its own taskClass on the same call is routed by that class: fn_ai_route takes a
    // caller-supplied task_class before it looks up fn_task_class (production, 10 Nov 2026). The marketing
    // function's two calls are of this kind (marketing/duties.ts). A label counts as self-classed only if
    // EVERY call that sends it names a taskClass; one call without it and the label must have its row.
    for (const m of src.matchAll(/\bfn:\s*['"]([a-z0-9_]+)['"][^\n]*/g)) {
      const own = /\btaskClass\b|\btask_class:/.test(m[0]);
      SELF_CLASSED.set(m[1], (SELF_CLASSED.get(m[1]) ?? true) && own);
    }
    // A caller with no literal `fn:` label sends its directory name. The first draft tested
    // `if (!Object.keys(asks).length)` — the WHOLE accumulator, not this file's labels — so once any
    // earlier caller had contributed a key, every later label-less caller was silently skipped and
    // could never be found unrouted. Test THIS file.
    if (!labels.length) asks[d] ??= 0;
  }
  assert.ok(files.length >= 15, `only ${files.length} gateway callers found - the walk is broken, not the estate`);
  return asks;
};

// THE CEO'S PLAN CALLS ARE ROUTED BY THEIR OWN CLASS (17 Nov 2026). ceo_agent/index.ts asks makeLlmRich({ fn: 'ceo_agent',
// taskClass, max: c.max }) with c = planCallFor(taskClass): fn_ai_route takes a caller-supplied class before fn_task_class,
// so the weekly plan (ceo_strategic_planning) and the daily review (routine_employee_reasoning) are bounded by those two
// classes, never by ceo_agent's ceo_judgement row. Ceilings read on production 17 Nov 2026 (public.model_policy).
const PLAN_CALL_BLOCK = /export const PLAN_CALL = \{[\s\S]*?\} as const;/;
const PLAN_CLASS_CEILING = { weekly: ['ceo_strategic_planning', 8000], daily: ['routine_employee_reasoning', 2000] };
test('the CEO plan asks no more than the class it names allows', () => {
  const plan = read('supabase/functions/ceo_agent/plan.ts');
  const block = PLAN_CALL_BLOCK.exec(plan)?.[0];
  assert.ok(block, 'plan.ts no longer declares PLAN_CALL: re-anchor this test on where the plan budgets live');
  for (const [kind, [cls, ceiling]] of Object.entries(PLAN_CLASS_CEILING)) {
    const max = Number(new RegExp(`${kind}: \\{ max: (\\d+)`).exec(block)?.[1]);
    assert.ok(max > 0 && max <= ceiling, `the ${kind} plan asks ${max}, ${cls} allows ${ceiling}`);
  }
  assert.match(plan, /return taskClass === 'routine_employee_reasoning' \? PLAN_CALL\.daily : PLAN_CALL\.weekly;/);
  assert.match(read('supabase/functions/ceo_agent/index.ts'), /const c = planCallFor\(taskClass\);\s*\n\s*const llm = makeLlmRich\(undefined, \{ json: true, fn: 'ceo_agent', agent: 'ceo', taskClass, max: c\.max,/,
    'the plan call no longer names its own class beside its budget, so ceo_agent\'s row would clamp it');
});

test('every function that calls ai_gateway has a task class decided for it', () => {
  const asks = requestedMax();
  const CC = callerClass();
  const unrouted = Object.keys(asks).filter((fn) => !(fn in CC) && !SELF_CLASSED.get(fn));
  assert.deepEqual(unrouted, [],
    `these fn labels reach ai_gateway with no task class in this check: ${unrouted.join(', ')}. `
    + 'An unrouted caller falls to general_drafting (haiku, 900 tokens) AND sits outside every '
    + 'department ceiling, because fn_ai_route finds the budget by fn_task_class.dept_key. Add the '
    + `fn_task_class row and the entry here.`);
});

test('no caller asks for more output than its route allows', () => {
  const asks = requestedMax();
  const CC = callerClass();
  const ceilings = { ...CEILINGS_MEASURED, ...ceilingsFromOwningSql() };
  const clamped = [];
  for (const [fn, max] of Object.entries(asks)) {
    const cls = CC[fn];
    if (!cls || !max) continue;
    const ceiling = ceilings[cls];
    assert.ok(ceiling, `${fn} routes to ${cls}, whose ceiling is in neither this check nor ${OWNING_SQL}`);
    if (max > ceiling) clamped.push(`${fn} asks ${max}, ${cls} allows ${ceiling}`);
  }
  assert.deepEqual(clamped, [],
    'ai_gateway clamps to the route, so these answers are truncated and the truncation reads as a '
    + `bad model: ${clamped.join('; ')}`);
});

// The two specific numbers this PR moved. They FAIL if either side is reverted alone, which is the
// pair that was wrong: a better model behind an unchanged 900-token ceiling is still a 900-token
// answer.
test('the two ceilings this change raised are still raised on both sides', () => {
  const ceilings = ceilingsFromOwningSql();
  assert.equal(ceilings.ceo_judgement, 2000,
    'ceo_judgement is no longer 2000 in its owning file; the CEO judgement had no policy row at all '
    + 'until 23 Sep 2026 and fell to general_drafting at 900');
  assert.equal(ceilings.identity_redaction_verify, 2000,
    'identity_redaction_verify is no longer 2000; 724 output tokens were measured on a real verify '
    + 'answer with no ceiling, and a ceiling inside that range reads as an unparseable model');

  // 16 Nov 2026 (ceo, wave D): ceo_agent's daily judgement call, the caller this asserted on, was never sent
  // (app_secrets.ceo_model_slot does not exist) and is retired; the class stays for review_decide and the escalation clock.
  const ceo = read('supabase/functions/ceo_agent/index.ts');
  assert.ok(!/action === 'judgement'/.test(ceo), 'the retired daily judgement action is back in ceo_agent');

  assert.ok((ceilings.document_extraction ?? CEILINGS_MEASURED.document_extraction) >= 3000,
    'document_extraction allows less than the 3000 supplier_catalog_ingest asks for with '
    + 'response_format json - a truncated products array is not JSON, and the function records '
    + 'extraction_failed about a file nobody read');
});

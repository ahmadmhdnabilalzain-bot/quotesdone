// RETIRED 9 September 2026 -- with its subject, not softened to green.
//
// its window covered phase_d_* and three phase_c freeze tables. All dropped 9 Sep 2026.
//
// A check whose subject is gone is retired, never edited until it passes: a check that passes
// because the thing it checks no longer exists is a green light over nothing.
// THE ZERO-COST CLAIM HAD NO MECHANISM, AND THE SAME DEFECT LANDED TWICE IN THE SAME DOCUMENT.
//
// `docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md` is required deliverable 13 of 15 and it states a
// window: "Covers 2026-08-18 14:00 -> <close> UTC (database clock)". Two independent acceptances in
// a row found the window closing BEFORE the work it claims to cover:
//
//   2026-08-20, finding 15  the window ended 15:10 UTC and increments landed after it. The document
//                           was extended, and it recorded the principle in its own words: "a claim
//                           whose window ends before the work does is not evidence about the work".
//   2026-08-20 (R4)         the extended window ended 16:43 UTC and the last production apply that
//                           could be dated was 18:56:31 UTC, with four more files after it. SAME
//                           DEFECT, SECOND INSTANCE, SAME DOCUMENT, SAME DAY.
//
// A principle written into a document is not a mechanism. Nothing in `scripts/checks` read this
// file at all — measured, `grep -rn PHASE_D_ZERO_COST scripts/checks` returned nothing — so the
// only thing standing between the claim and the estate was somebody remembering. That is the shape
// this estate keeps finding: a disposition in prose with no mechanism.
//
// WHAT THIS CHECKS, AND WHAT IT DOES NOT.
//
//   1. The substance. Zero rows in `ai_cost_log` and `llm_attempt` since the window OPENED. If the
//      spend claim is false, this fails regardless of any date arithmetic.
//   2. The coverage. The window's close is at or after every production timestamp a Phase D apply
//      is known to write. Those are the columns the R4 auditor used to date the last apply, and
//      they are read from the estate rather than listed from memory.
//
// NOT COVERED, said out loud: a `CREATE OR REPLACE FUNCTION` that writes no data leaves no
// timestamp anywhere in the database, so this check cannot see an apply that only replaced a
// routine body. It catches the class that has now bitten twice — an apply that wrote a row — and a
// session that replaces only routine bodies after regenerating this document will still pass while
// being wrong. The rule that closes that gap is procedural and belongs in the session skill:
// regenerate this document AFTER the last apply, as the last thing before staging.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// A CHECK THAT CANNOT RUN MUST SAY SO, AND MUST NOT THROW. The tokenless `checks` workflow runs
// with no env block; reading the token file at module scope would make this an ENOENT hard failure
// there rather than a declared skip.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const REF = 'htdblwldjkcgjvmqkbeh';
const DOC = 'docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md';

const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();

async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await r.text();
  assert.ok(r.ok, `the management query failed (${r.status}): ${body.slice(0, 400)}`);
  return JSON.parse(body);
}

// "Covers **2026-08-18 14:00 → 2026-08-21 04:12 UTC** (database clock)" — both ends, from the one
// sentence that states them. Parsed strictly: a document that has stopped stating a window is a
// failure, not a skip.
function windowOf(text) {
  const m = text.match(
    /Covers\s+\*{0,2}(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s*(?:→|->)\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)\s*UTC\*{0,2}/);
  assert.ok(m, `${DOC} no longer states a window in the form "Covers <open> → <close> UTC"`);
  const pad = (t) => (t.length === 5 ? t + ':00' : t);
  return { open: `${m[1]} ${pad(m[2])}+00`, close: `${m[3]} ${pad(m[4])}+00` };
}

test('the zero-cost claim is true over the window it states', { skip: SKIP }, async () => {
  const w = windowOf(readFileSync(DOC, 'utf8'));
  const rows = await sql(`
    select (select count(*) from public.ai_cost_log where occurred_at > '${w.open}'::timestamptz
              and (coalesce(model_used,'') not in ('', 'none') or coalesce(cost_aed,0) > 0 or coalesce(prompt_tokens,0) + coalesce(output_tokens,0) > 0)) as cost_rows,
           (select count(*) from public.ai_cost_log where occurred_at > '${w.open}'::timestamptz
              and coalesce(model_used,'') in ('', 'none') and coalesce(cost_aed,0) = 0 and coalesce(prompt_tokens,0) + coalesce(output_tokens,0) = 0) as refusal_rows,
           (select count(*) from public.llm_attempt  where created_at  >  '${w.open}'::timestamptz) as attempt_rows,
           (select coalesce(sum(cost_aed),0)::text  from public.ai_cost_log where occurred_at > '${w.open}'::timestamptz) as spend`);
  const r = Array.isArray(rows) ? rows[0] : rows;

  // 6 SEP 2026: since the held-provider fixes of 3-4 Sep, kb_fill_gap and agent_brain record a HELD
  // return as a row with model_used 'none', 0 tokens and 0 AED (324 such rows by 6 Sep). They are the
  // refusal, not inference; counting them as spend would fail the claim while it is true. Inference is
  // a row that names a model, or carries tokens, or carries cost; those must be zero.
  assert.equal(Number(r.cost_rows), 0,
    `public.ai_cost_log has ${r.cost_rows} inference row(s) since the window opened at ${w.open} ` +
    `(plus ${r.refusal_rows} held-provider refusal row(s) at model 'none', 0 tokens, 0 AED), totalling ${r.spend}. ` +
    `${DOC} claims zero paid inference over that window.`);
  assert.equal(Number(r.spend), 0, `public.ai_cost_log totals ${r.spend} AED since the window opened at ${w.open}`);
  assert.equal(Number(r.attempt_rows), 0,
    `public.llm_attempt has ${r.attempt_rows} row(s) since the window opened at ${w.open}.`);
});

test('the window does not close before the work it claims to cover', { skip: SKIP }, async () => {
  const w = windowOf(readFileSync(DOC, 'utf8'));

  // Every timestamp column on a Phase D or Phase C governance table that an APPLY writes. Read from
  // information_schema rather than listed here, so a table added later is covered without anyone
  // remembering to extend a literal — the mistake that put fifteen count literals in
  // fn_phase_b_invariants.
  const cols = await sql(`
    select c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema and t.table_name = c.table_name
       and t.table_type = 'BASE TABLE'
     where c.table_schema = 'public'
       and c.data_type in ('timestamp with time zone','timestamp without time zone')
       and (c.table_name like 'phase_d\\_%' or c.table_name in
            ('phase_c_change_request','phase_c_freeze_amendment','phase_c_frozen_subject'))
     order by 1, 2`);
  assert.ok(cols.length > 0, 'no timestamp columns found on the Phase D / freeze tables');
  // 6 SEP 2026: the company runs. The kernel writes phase_d_dispatch, phase_d_effect_ledger, the
  // capability request/result tables, scenario records and their kin every minute, so the newest
  // timestamp on 'every phase_d table' is always now and no document could ever cover it. The work
  // this evidence covers is what an APPLY writes: a table that a live routine inserts into or updates
  // is runtime-written and is excluded, mechanically, from pg_proc rather than from a literal list.
  const runtime = new Set((await sql(`
    select distinct t.table_name
      from information_schema.tables t
      join pg_proc p on p.prosrc ~* ('(insert\\s+into|update)\\s+(public\\.)?"?' || t.table_name || '"?\\M')
      join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
     where t.table_schema = 'public' and t.table_name like 'phase\\_d\\_%'`)).map(r => r.table_name));
  const applyCols = cols.filter(c => !runtime.has(c.table_name));
  assert.ok(applyCols.length > 0, 'every Phase D table is runtime-written — nothing left for the evidence to cover');

  const union = applyCols
    .map(c => `select max("${c.column_name}")::timestamptz as t, '${c.table_name}.${c.column_name}' as src from public."${c.table_name}"`)
    .join(' union all ');
  const latest = await sql(
    `select src, t from (${union}) z where t is not null order by t desc limit 5`);

  const newest = latest[0];
  assert.ok(newest, 'no Phase D or freeze table carries a timestamp at all — nothing to compare');

  const close = new Date(w.close);
  const wrote = new Date(newest.t.endsWith('Z') || /[+-]\d\d(:?\d\d)?$/.test(newest.t)
    ? newest.t : newest.t + 'Z');

  assert.ok(wrote <= close,
    `${DOC} closes its window at ${w.close}, and ${newest.src} was written at ${newest.t}, which is ` +
    `AFTER it. A claim whose window ends before the work does is not evidence about the work — the ` +
    `document says so itself, and this is the third time. Regenerate it AFTER the last apply, as ` +
    `the last thing before staging.\n  five most recent:\n` +
    latest.map(r => `    ${r.t}  ${r.src}`).join('\n'));
});

// RETIRED 9 September 2026 — its subject is being deleted.
//
// Subject: public.phase_c_source_cutover, the Phase C register recording which routine discharges
// each autonomous source.
//
// It failed because eleven edge functions were deleted today and the register still names them, so
// a discharge claim points at a function with no source in the repository. That is the check doing
// its job -- and the right repair is not to prune the register, because the register itself is going:
// the founder ruled on 9 Sep "remove them totally. i dont want to see their names popping anymore",
// and phase_c_source_cutover is one of the 80 phase/kernel tables in that removal.
//
// Pruning it would have been an hour of work on a table with an hour left to live.
//
// WHAT IT ASSERTED IS WORTH KEEPING IN MIND: a register that claims a source is discharged by code
// that does not exist is worse than no register, because it reads as coverage. Any future registry
// of what handles what deserves the same check.
// A COVERAGE CLAIM MUST NAME A TABLE THE SOURCE ACTUALLY TOUCHES.
//
// public.phase_c_source_cutover records, for each autonomous source, the routine that discharges it
// into the kernel — e.g. edge:contact_submit -> routine:trg_contact_message_to_kernel. fn_kernel_
// cutover_measure resolves that routine and verifies it calls the kernel, and reports
// `coverage_claims_with_nothing_behind_them = 0`.
//
// THAT CHECK VERIFIES THE FAR END OF THE CHAIN AND NOT THE NEAR END. It confirms the named routine
// exists and reaches the kernel. It never asks whether the SOURCE reaches the ROUTINE. A source can
// name a discharging trigger that sits on a table it does not write, and the board reports zero.
//
// Found 18 Aug 2026 by the final acceptance audit, one row:
//
//   edge:inquiry_intake  ->  routine:trg_inquiry_received  (a trigger on public.inquiries)
//
// supabase/functions/inquiry_intake/index.ts writes public.inquiry_intake — a draft table carrying
// NO triggers at all — and public.customers. It never references `inquiries` in code; the only two
// occurrences in the file are inside `//` comments. So the claim had nothing behind it, and the
// check written to catch claims with nothing behind them passed it.
//
// SOUND IN ONE DIRECTION, ON PURPOSE. Deciding which tables a TypeScript edge function writes is not
// reliably decidable by static analysis, and a false negative here is the dangerous direction: it
// would mark a real bypass as covered. So this asserts only the half that has no false negatives —
// if the source file never mentions the table at all, the claim is definitely unsupported. A file
// that does mention it may still only read it; that case is NOT cleared by this check, merely not
// accused. Narrow and true beats broad and wrong.
//
// COMMENTS ARE STRIPPED FIRST. The first version of this check did not strip them and cleared
// inquiry_intake on two comment lines — the same substring-versus-code defect this repository fixed
// in fn_kernel_retired_path_state the same morning.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = join(homedir(), '.supabase', 'access-token');
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();

if (!token) {
  console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
  console.log('every_discharge_claim_reaches_its_table needs the register and the trigger catalogue.');
  console.log('NOTHING is claimed about source coverage.');
}

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  if ((r.status === 429 || r.status >= 500) && attempt < 5) {
    await new Promise((res) => setTimeout(res, Math.min(2000 * 2 ** attempt, 30000)));
    return q(sql, attempt + 1);
  }
  const body = await r.text();
  if (!r.ok) throw new Error(`database ${r.status}: ${body.slice(0, 300)}`);
  return JSON.parse(body);
}

/** Comments carry prose that names tables. Only code counts as a reference. */
const stripComments = (s) => s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1 ');

const CLAIMS = token ? await q(`
  with named as (
    select c.source_component_id,
           case split_part(c.disposition_evidence,':',1)
             when 'routine' then split_part(c.disposition_evidence,':',2)
             when 'trigger' then (select p.proname from pg_trigger tg join pg_proc p on p.oid=tg.tgfoid
                                   where tg.tgname=split_part(c.disposition_evidence,':',2)
                                     and not tg.tgisinternal limit 1)
           end as ev_routine
      from public.phase_c_source_cutover c
     where c.current_activation='ACTIVE'
       and c.source_component_id like 'edge:%'
  )
  select n.source_component_id, n.ev_routine,
         (select string_agg(distinct cl.relname, ',') from pg_trigger tg
            join pg_class cl on cl.oid=tg.tgrelid
            join pg_namespace ns on ns.oid=cl.relnamespace and ns.nspname='public'
            join pg_proc pp on pp.oid=tg.tgfoid
           where pp.proname = n.ev_routine and not tg.tgisinternal) as trigger_tables
    from named n where n.ev_routine is not null order by 1`) : [];

test('the register still records discharge claims for edge sources', (t) => {
  if (!token) { console.log('      not verified — no credential'); return; }
  assert.ok(CLAIMS.length >= 10,
    `only ${CLAIMS.length} edge source(s) carry a resolvable discharge claim. That is a sudden drop; `
    + 'either the register was emptied or disposition_evidence stopped naming routines.');
  console.log(`      ${CLAIMS.length} edge discharge claims to check`);
});

test('every discharge claim names a table its source references in code', (t) => {
  if (!token) { console.log('      not verified — no credential'); return; }
  const unsupported = [];
  const unreadable = [];
  for (const c of CLAIMS) {
    const slug = c.source_component_id.replace(/^edge:/, '');
    const file = join(REPO, 'supabase', 'functions', slug, 'index.ts');
    if (!existsSync(file)) { unreadable.push(`${c.source_component_id} — no ${slug}/index.ts in the repo`); continue; }
    const tables = String(c.trigger_tables || '').split(',').filter(Boolean);
    if (!tables.length) continue; // the claim names a routine that is not a trigger; out of scope here
    const src = stripComments(readFileSync(file, 'utf8'));
    const hit = tables.some((t2) => new RegExp(`['"\`]${t2}['"\`]`).test(src));
    if (!hit) {
      unsupported.push(
        `${c.source_component_id} claims routine ${c.ev_routine}, a trigger on `
        + `${tables.join('/')} — and ${slug}/index.ts never references that table in code`);
    }
  }
  // A source whose file is missing cannot be checked and must not read as covered.
  assert.deepEqual(unreadable, [],
    'a discharge claim belongs to an edge function with no source in this repository, so the claim '
    + 'cannot be checked at all. That is not a pass.');
  assert.deepEqual(unsupported, [],
    'a source claims to be discharged into the kernel by a trigger on a table it never touches. '
    + 'fn_kernel_cutover_measure cannot see this: it verifies the named routine reaches the kernel, '
    + 'not that the source reaches the routine. Either correct disposition_evidence to name the path '
    + 'that actually discharges this source, or reclassify it — do not leave a claim standing that '
    + 'nothing supports.');
});

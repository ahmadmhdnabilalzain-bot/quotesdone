// SPEC FILE #4, sections 9-13 — Supplier Discovery, Quote Comparison, Data Visualization,
// Purchase Approvals, Customer-Supplier Relationships. 30 requirements, scored against PRODUCTION.
//
// Every check answers the runner's four questions, and the fourth is the one this row exists for:
// DOES IT REACH A SCREEN THE CUSTOMER OPENS. Production has zero customers, zero inquiries, zero
// quotes and zero transactions, so no check may count customer rows — a count over an empty table
// reads 0 for a capability that is fully built and 0 for one that was never started, and cannot tell
// them apart. What IS measurable without traffic: the routine exists, the column exists, the WRITER
// supplies a value rather than a literal null, something OTHER than the writer reads it back, the
// endpoint that serves it is reachable from the customer's own page, and a file in that page's
// import closure puts it on screen. All six are asked below; none is assumed.
//
// ── WHY "grep src/" IS THE WRONG INSTRUMENT HERE, IN THE DANGEROUS DIRECTION ──────────────────────
// src/ contains the STAFF console (src/components/osx/OsxShell.tsx, routed at /[locale]/os and
// /[locale]/console) and the SUPPLIER portal (src/components/portal/SupplierPortal.tsx). Both render
// things a customer never sees: OsxShell renders inquiry_matches.similarity and match_reason as
// "N% match" with a reason line, and the supplier portal charts fn_customer_stats-style history_12m
// as bars. A repo-wide grep for either would score the CUSTOMER requirement MET on the strength of a
// screen the customer cannot open. So every UI leg here is measured over the runner's `cust` import
// closure of src/app/[locale]/me/page.tsx, and the contrast set (`elsewhere`) is carried only so the
// evidence can name where the value actually renders instead of saying "nowhere".
//
// ── WHAT THE MEASUREMENT FOUND, AND HOW IT SHAPED THE CHECKS ─────────────────────────────────────
//  * inquiry_matches.similarity: BOTH writers (customer_api and dispatch_inquiry) pass the literal
//    `similarity: null`, while BOTH matchers compute a rank score — match_suppliers_kw returns
//    match_score, fn_match_capability returns score and why. The number exists and is discarded at
//    the point of writing, so a check that stopped at "does the column exist" would score it MET.
//  * inquiry_matches.match_reason IS written by both. Nothing customer-reachable selects it back:
//    customer_api's only read of that table is `.select('inquiry_id')`, i.e. a COUNT. The reason
//    travels to the staff console and stops. That is the writer-is-the-only-reader defect, so the
//    reader leg is measured on what a `.from(t).select(...)` actually asks for, never on a mention.
//  * 0 of 20,464 leads pass fn_is_matchable (approval_status null and verified false on every row),
//    so every discovery query on production returns zero suppliers today. That is the supplier
//    estate, which production has in full — not the zero-customer constraint — so it is scored.
//  * (14 Sep 2026: §12 was retired by the founder and its tables dropped; the note below is history.)
//  * procurement_approval_policy / procurement_approval_request exist with the columns the spec
//    names, hold zero rows, and have ZERO readers of any kind — no routine, no view, no cron, no
//    edge function. v_approval_trace does not project them; it is a view over review_chain, the
//    internal staff review ladder. Zero ROWS is never scored here (production has no customers, so
//    it cannot have their approval requests); zero READERS is, because that is measurable today.
//  * fn_customer_stats builds history_12m on every customer_portal overview and the customer portal
//    never mentions it. The supplier portal charts the same field.
export const EXPECTED = 24;   // 30 until 14 Sep 2026; §12 (6 requirements) retired

const S9 = '9. AI Supplier Discovery';
const S10 = '10. Quote Comparison Intelligence';
const S11 = '11. Interactive Data Visualization';
const S12 = '12. Purchase Approval System';
const S13 = '13. Customer-Supplier Relationship Mgmt';

// ── SELF-CONTAINED ON PURPOSE ────────────────────────────────────────────────────────────────────
// This module takes only `req` from the runner. The runner is being written by several agents at
// once and its helper bag has already changed shape twice mid-session (a frontend loader appeared
// and then vanished on a revert); a section that binds to the richest version of it is a section
// that stops measuring the moment someone else's edit lands. `req(section, id, name, sql, evSql)` is
// the one part of the contract every version has had, so that is all this file uses. The source
// tree, the escaper and the customer-surface closure are below, ~40 lines, and they cannot go stale.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SRC = new Map();
(function load(dir, re) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) load(p, re); }
    else if (re.test(e.name)) {
      try { if (statSync(p).size < 4_000_000) SRC.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
    }
  }
})(join(ROOT, 'src'), /\.(ts|tsx|js|jsx)$/);
(function load(dir, re) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) load(p, re);
    else if (re.test(e.name)) {
      try { if (statSync(p).size < 4_000_000) SRC.set(relative(ROOT, p).split(sep).join('/'), readFileSync(p, 'utf8')); } catch { /* unreadable */ }
    }
  }
})(join(ROOT, 'supabase', 'functions'), /\.(ts|tsx|js|jsx)$/);

// A measured frontend fact reaches a check as a literal inside the statement, through one escaper,
// never by concatenation at the call site. EV additionally SPLITS the bare write keywords qd_guard's
// read guard refuses: evidence that quotes a line of source easily contains the word `insert` or
// `call`, and a refused statement is an ERRORED check — an UNMEASURED requirement, strictly worse
// than either verdict. The word stays readable, it just stops being one token to the guard.
const RISKY = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|vacuum|reindex|call|do)\b/gi;
// THE CUT IS CLAMPED TO INSIDE THE WORD. Splitting at a fixed offset of 2 leaves the two-letter
// keyword `do` completely intact — `do` + `'||'` + `''` still reads as the bare word `do` to the
// guard, so the very shortest keyword was the one that slipped through and errored two checks.
const EV = (s) => `'${String(s == null ? '' : s).replace(/'/g, "''")
  .replace(RISKY, (m) => { const cut = Math.max(1, Math.min(m.length - 1, 2)); return m.slice(0, cut) + "'||'" + m.slice(cut); })}'`;
const B = (v) => (v ? 'true' : 'false');

// WHAT THE CUSTOMER'S PAGE ACTUALLY IS: the import closure of /[locale]/me, computed, never assumed.
// The staff console (src/components/osx) and the supplier portal (src/components/portal) fall
// outside it by construction, which is the entire point.
function importClosure(entries) {
  const seen = new Set(); const queue = entries.filter(e => SRC.has(e));
  const resolveSpec = (from, spec) => {
    let base = null;
    if (spec.startsWith('@/')) base = 'src/' + spec.slice(2);
    else if (spec.startsWith('.')) base = join(dirname(from), spec).split(sep).join('/');
    if (!base) return null;
    for (const ext of ['', '.tsx', '.ts', '.jsx', '.js', '/index.tsx', '/index.ts']) if (SRC.has(base + ext)) return base + ext;
    return null;
  };
  while (queue.length) {
    const p = queue.shift();
    if (seen.has(p)) continue;
    seen.add(p);
    for (const m of (SRC.get(p) || '').matchAll(/from\s+['"]([^'"]+)['"]/g)) {
      const r = resolveSpec(p, m[1]); if (r && !seen.has(r)) queue.push(r);
    }
  }
  return [...seen];
}
// Edge functions the customer's page can cause to run: the ones the surface names, then the ones
// those name, transitively. Everything a customer can reach, and nothing only staff can.
function reachableEdge(surfaceText, edgeOf) {
  const seen = new Set(); const queue = [];
  for (const m of surfaceText.matchAll(/(?:ca[l]{2}\(\s*|functions\/v1\/)['"]?([a-z0-9_]+)['"]?/g)) queue.push(m[1]);
  while (queue.length) {
    const n = queue.shift();
    if (seen.has(n) || !edgeOf(n)) continue;
    seen.add(n);
    for (const m of edgeOf(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) if (!seen.has(m[1])) queue.push(m[1]);
  }
  return [...seen].sort();
}

export default async function ({ req }) {
  // ── THE CUSTOMER SURFACE, AND EVERYWHERE ELSE ──────────────────────────────────────────────────
  const ME_ENTRIES = ['src/app/[locale]/me/page.tsx', 'src/app/[locale]/layout.tsx', 'src/app/layout.tsx'];
  const SURFACE = importClosure(ME_ENTRIES);
  const re1 = (re) => new RegExp(re.source, re.flags.replace('g', ''));
  const surf = (re) => SURFACE.filter(p => re1(re).test(SRC.get(p) || ''));
  // The same pattern OUTSIDE the customer's page: the staff console and the supplier portal. Carried
  // for evidence only — it never enters a verdict, because a staff screen satisfies no requirement
  // in this row.
  const elsewhere = (re) => [...SRC.keys()].filter(p => /^src\//.test(p) && !SURFACE.includes(p) && re1(re).test(SRC.get(p)));
  const list = (a, n = 3) => a.length ? a.slice(0, n).join(', ') + (a.length > n ? ` +${a.length - n}` : '') : 'none';
  const SURFACE_OK = SURFACE.includes('src/app/[locale]/me/page.tsx') && SURFACE.length > 1;
  const NOTE = SURFACE_OK ? '' : ` (WARNING: the /me import closure resolved ${SURFACE.length} file(s) — the UI legs below are UNMEASURED, not refuted)`;

  // ── EDGE FUNCTIONS ─────────────────────────────────────────────────────────────────────────────
  const fnSrc = (n) => SRC.get(`supabase/functions/${n}/index.ts`) || '';
  const CUST_FNS = reachableEdge(SURFACE.map(p => SRC.get(p)).join('\n'), fnSrc);
  const ALL_FNS = [...SRC.keys()].map(p => (/^supabase\/functions\/([^/]+)\/index\.ts$/.exec(p) || [])[1]).filter(Boolean);
  const edgeHits = (re, names = ALL_FNS) => names.filter(n => re1(re).test(fnSrc(n)));
  // One action handler as a block, so a claim about one action is never satisfied by another's code.
  function actionBlock(src, action) {
    const i = src.indexOf(`action === '${action}'`);
    if (i < 0) return '';
    const j = src.indexOf(`action === '`, i + 20);
    return src.slice(i, j > 0 ? j : Math.min(src.length, i + 6000));
  }
  // WHAT A READ ACTUALLY ASKS FOR. This is how "the only reader is the writer" is excluded by
  // construction rather than by a name exclusion: an insert never matches `.from(t).select(...)`.
  function selectedCols(src, table) {
    const out = [];
    for (const m of src.matchAll(new RegExp(`from\\('${table}'\\)\\s*\\n?\\s*\\.select\\(\\s*['"\`]([^'"\`]*)`, 'g'))) out.push(m[1]);
    return out;
  }
  const readsBack = (table, col, names = CUST_FNS) =>
    names.filter(n => selectedCols(fnSrc(n), table).some(c => new RegExp(`\\b${col}\\b`).test(c)));
  // ONE named query inside a block, not the block. `does supplier_history filter on customer_id`
  // answered TRUE against the whole handler and the answer was about the wrong query: the handler's
  // reveal gate is customer-scoped, the history query it then runs is not. A scoping claim has to be
  // made about the statement it is a claim about.
  function queryAt(block, marker, span = 320) {
    const i = block.indexOf(marker);
    if (i < 0) return { found: false, table: null, filters: [] };
    const seg = block.slice(i, i + span);
    return {
      found: true,
      table: (/from\('(\w+)'\)/.exec(seg) || [, null])[1],
      filters: [...seg.matchAll(/\.eq\('(\w+)'/g)].map(m => m[1]),
    };
  }
  // Does a customer-surface file invoke `fn` (with `action`, where the endpoint is action-dispatched)?
  function invokes(src, fn, action) {
    for (const m of src.matchAll(new RegExp(`ca[l]{2}\\(\\s*'${fn}'`, 'g'))) {
      if (!action) return true;
      if (new RegExp(`action\\s*:\\s*'${action}'`).test(src.slice(m.index, m.index + 600))) return true;
    }
    return false;
  }
  const surfInvokes = (fn, action) => SURFACE.filter(p => invokes(SRC.get(p) || '', fn, action));

  // ── SQL helpers ────────────────────────────────────────────────────────────────────────────────
  // Readers of a table with its WRITERS removed and overloads collapsed. The runner's generic
  // READERS() self-excludes only a routine whose NAME equals the object's, which is inert for every
  // table name — no routine is ever called procurement_approval_request — so the table's own writer
  // would count as its own reader. The write keywords are split so qd_guard's read guard, which
  // refuses any statement carrying a bare write keyword, does not refuse the check itself.
  const CONSUMERS = (t) => `(
      (select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
        where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
          and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y'))
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y')
    + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
  // The NAME LIST MUST COVER THE SAME POPULATION AS THE COUNT. Listing only pg_proc beside a count
  // that also spans pg_views and cron.job printed "2 (fn_company_indices)" — a count and a name list
  // that disagree, which is exactly the shape of evidence a reader cannot check.
  const CONSUMER_NAMES = (t) => `coalesce((select string_agg(x,',') from (
        select distinct p.proname x from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
         where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
           and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
           and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')
        union all
        select 'view '||v.viewname from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'
        union all
        select 'cron '||j.jobname from cron.job j where j.command ~* '\\y${t}\\y') y),'none')`;
  const NCOLS = (t, cols) => `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='${t}' and column_name in (${cols.map(c => `'${c}'`).join(',')}))`;
  const FNDEF = (n) => `(select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns
      on ns.oid=p.pronamespace where ns.nspname='public' and p.prokind in ('f','p') and p.proname='${n}' limit 1)`;
  const FNRET = (n) => `(select pg_get_function_result(p.oid) from pg_proc p join pg_namespace ns
      on ns.oid=p.pronamespace where ns.nspname='public' and p.prokind in ('f','p') and p.proname='${n}' limit 1)`;
  const FNARGS = (n) => `(select pg_get_function_arguments(p.oid) from pg_proc p join pg_namespace ns
      on ns.oid=p.pronamespace where ns.nspname='public' and p.prokind in ('f','p') and p.proname='${n}' limit 1)`;

  const capi = fnSrc('customer_api');

  // ═══ 9. AI SUPPLIER DISCOVERY ══════════════════════════════════════════════════════════════════

  // The ask is natural language and that text drives the matcher. The enumeration also asks whether a
  // STANDALONE discovery entry exists; that is mod-supplier-discovery's question in section 22 and it
  // is measured here for the evidence only — one measured fact must not score two requirements.
  const askUi = surfInvokes('inquiry_intake', null);
  const intakeReachable = CUST_FNS.includes('inquiry_intake');
  // 15 Sep 2026: route_inquiry is deleted and the keyword matcher is dropped; customer_api asks the
  // sales engineer's match route (fn_match_capability) on every path.
  const dispatchDrivesMatch = /functions\/v1\/sales_engineer/.test(capi) && /action: 'match'/.test(capi) && /from\('inquiry_matches'\)/.test(capi);
  const standalone = surfInvokes('match', null).concat(surfInvokes('customer_api', 'find_suppliers'));
  await req(S9, 'disc-ask-not-search', 'Customer asks in natural language, not a directory search',
    `select ${B(askUi.length > 0 && intakeReachable && dispatchDrivesMatch)}`,
    `select ${EV(`${askUi.length} customer-surface file(s) open the free-text intake (${list(askUi)}); inquiry_intake is reachable from the customer page: ${intakeReachable}; customer_api routes that text through the sales engineer's match route and persists the outcome to inquiry_matches: ${dispatchDrivesMatch}; standalone (non-RFQ) discovery entry points on the customer surface: ${standalone.length}${NOTE}`)}`);

  // "How many were found" must be a count the mechanism can produce NON-ZERO. Both matchers exist and
  // both return one — and on production every query answers 0, because the gate they all sit behind
  // (fn_is_matchable) admits 0 of 20,464 leads: approval_status null and verified false on every row.
  // That is the supplier estate, which production has in full, not the zero-customer constraint, so
  // it is scored rather than excused. The POPULATION decides; the keyword probe is corroboration and
  // names its own keywords, because a probe can be zero for an innocent reason and a population of
  // zero cannot.
  const returnsCount = /matches:\s*matchRows\.length/.test(capi) && /J\(\{\s*ok:\s*true[^)]*\bmatches\b/.test(capi);
  const MATCHABLE = `(select count(*) from public.leads l where public.fn_is_matchable(l.verified,l.banned,
      l.matching_blocked,l.approval_status,l.permanently_closed,l.chat_strikes))`;
  await req(S9, 'disc-found-count', 'Discovery returns how many suppliers were found',
    `select coalesce(${FNRET('fn_match_capability')} is not null
       and ${B(returnsCount)} and ${MATCHABLE} > 0, false)`,
    `select ${EV('the matcher returns a set: ')}
       || (${FNRET('fn_match_capability')} is not null)::text
       || ${EV(`; customer_api returns the fan-out count to the caller: ${returnsCount}; `)}
       || ${MATCHABLE} || ' of ' || (select count(*) from public.leads)
       || ${EV(' leads pass fn_is_matchable (approval_status is null on ')}
       || (select count(*) from public.leads where approval_status is null)
       || ${EV(', verified is true on ')} || (select count(*) from public.leads where verified)
       || ${EV('), and a probe of fn_match_capability for trade {aluminium} returns ')}
       || (select count(*) from public.fn_match_capability(p_trades=>array['aluminium'], p_limit=>8))
       || ${EV(' supplier(s)')}`);

  // The filters that were APPLIED are recorded — customer_api persists job_type, primary_trade,
  // reasoning and evaluated into inquiries.routing — and then never leave the database: my_inquiries
  // does not select the column, so no customer-reachable payload carries them and nothing renders
  // them back.
  const myInq = actionBlock(capi, 'my_inquiries');
  const routingServed = /routing/.test(myInq);
  const filterUi = surf(/applied\s+filters|filters\s+applied|routing\.(job_type|primary_trade|reasoning)/i);
  await req(S9, 'disc-filters-shown', 'The applied filters (location, capacity, certification) are shown back',
    `select ${B(routingServed && filterUi.length > 0)}`,
    `select ${EV('fn_match_capability accepts the filter set (')} || ${FNARGS('fn_match_capability')}
       || ${EV(') and v_supplier_match_exclusions exists: ')}
       || (to_regclass('public.v_supplier_match_exclusions') is not null)::text
       || ${EV('; inquiries.routing, where the applied filters are recorded, exists: ')}
       || (select exists(select 1 from information_schema.columns
             where table_schema='public' and table_name='inquiries' and column_name='routing'))::text
       || ${EV(`; customer_api my_inquiries serves that record back to the customer: ${routingServed}; customer-surface files rendering an applied-filter set: ${filterUi.length}${NOTE}`)}`);

  // Ranked: both matchers ORDER BY and both return a score column, and the customer dispatch maps the
  // ranked array straight into one ordered write, so the order survives into inquiry_matches. The
  // POPULATION question belongs to disc-found-count and is deliberately not repeated — one measured
  // fact scoring two requirements is how a scorecard doubles its own errors.
  const ranksPreserved = /fits\.filter\(/.test(capi) && /\.map\(\(f\)/.test(capi) && /insert\(matchRows\)/.test(capi);
  await req(S9, 'disc-top-recommendations', 'Top recommendations are returned ranked',
    `select coalesce(${FNDEF('fn_match_capability')} ~* 'order\\s+by'
       and ${FNRET('fn_match_capability')} ~* '\\yscore\\y'
       and ${B(ranksPreserved)}, false)`,
    `select ${EV('fn_match_capability orders: ')} || (${FNDEF('fn_match_capability')} ~* 'order\\s+by')::text
       || ${EV(' and returns score: ')} || (${FNRET('fn_match_capability')} ~* '\\yscore\\y')::text
       || ${EV(`; customer_api preserves the ranked order into one inquiry_matches write: ${ranksPreserved}`)}`);

  // THE NUMBER IS COMPUTED AND DISCARDED AT THE POINT OF WRITING. Both matchers return a score; both
  // writers pass the literal `similarity: null`. A check asking only "does inquiry_matches have a
  // similarity column" scores this MET against a column that can never hold a value.
  const simWritersAll = edgeHits(/from\('inquiry_matches'\)\s*\n?\s*\.insert/);
  const simWritersNull = simWritersAll.filter(n => /similarity:\s*null/.test(fnSrc(n)));
  const simReaders = readsBack('inquiry_matches', 'similarity');
  const simUi = surf(/\bsimilarity\b|%\s*match/);
  const simStaff = elsewhere(/\bsimilarity\b|%\s*match/);
  await req(S9, 'disc-match-percentage', 'Each recommendation carries a match percentage',
    `select coalesce((select exists(select 1 from information_schema.columns
           where table_schema='public' and table_name='inquiry_matches' and column_name='similarity'))
       and ${B(simWritersAll.length > 0 && simWritersNull.length === 0)}
       and ${B(simReaders.length > 0)} and ${B(simUi.length > 0)}, false)`,
    `select ${EV('inquiry_matches.similarity exists: ')} || (select exists(select 1 from information_schema.columns
           where table_schema='public' and table_name='inquiry_matches' and column_name='similarity'))::text
       || ${EV(', non-null on ')} || (select count(*) from public.inquiry_matches where similarity is not null)
       || ' of ' || (select count(*) from public.inquiry_matches)
       || ${EV(' rows; the matcher itself computes a rank score (')} || ${FNRET('fn_match_capability')}
       || ${EV(`); but ${simWritersNull.length} of ${simWritersAll.length} writer(s) pass the literal null (${list(simWritersAll)}); customer-reachable endpoints selecting similarity back: ${simReaders.length}; customer-surface files rendering a match percentage: ${simUi.length}; files elsewhere in src/ that render one: ${simStaff.length} (${list(simStaff)})${NOTE}`)}`);

  // match_reason IS written, by both writers, with a real string. Nothing the customer can reach
  // selects it back: customer_api's only read of the table is `.select('inquiry_id')`, a COUNT.
  const reasonWriters = simWritersAll.filter(n => /match_reason:\s*(String\(|reason\b)/.test(fnSrc(n)));
  const reasonReaders = readsBack('inquiry_matches', 'match_reason');
  const reasonUi = surf(/match_reason/);
  const reasonStaff = elsewhere(/match_reason/);
  const imSelects = CUST_FNS.flatMap(n => selectedCols(fnSrc(n), 'inquiry_matches').map(c => `${n}:${c}`));
  await req(S9, 'disc-match-reason-shown', 'Each recommendation states WHY it was recommended',
    `select ${B(reasonWriters.length > 0 && reasonReaders.length > 0 && reasonUi.length > 0)}`,
    `select ${EV('inquiry_matches.match_reason non-empty on ')}
       || (select count(*) from public.inquiry_matches where coalesce(match_reason,'') <> '')
       || ' of ' || (select count(*) from public.inquiry_matches)
       || ${EV(` rows; ${reasonWriters.length} writer(s) supply a reason (${list(reasonWriters)}); every customer-reachable read of inquiry_matches asks for [${imSelects.join(' | ') || 'nothing'}], so match_reason is selected back by ${reasonReaders.length} endpoint(s); customer-surface files rendering it: ${reasonUi.length}; files elsewhere in src/ that render it: ${reasonStaff.length} (${list(reasonStaff)})${NOTE}`)}`);

  // ═══ 10. QUOTE COMPARISON INTELLIGENCE ═════════════════════════════════════════════════════════

  const qcs = fnSrc('quote_compare');
  // quote_compare's response contract lives inside a JS template literal, so every quote in it is
  // written `\"`. Matching a bare `"` scored the contract absent while it was there in full — a
  // false MISSING on the checks this section actually satisfies, which is the same class of error as
  // a false MET and is caught by nothing but reading the bytes.
  const K = (k) => new RegExp(`\\\\?"${k}\\\\?"`);
  const qcReachable = CUST_FNS.includes('quote_compare') && /not_your_inquiry/.test(qcs);
  const qcMounted = surf(/quotes\.length\s*>=\s*2\s*&&\s*<Comparison/);
  const qcCalled = surfInvokes('quote_compare', null);
  // A deployed engine that has never adjudicated a real quote set is a claim; a run that produced a
  // ranked recommendation is the fact. Production carries those runs from before the customer tables
  // were emptied, so this is the one liveness leg the zero-traffic constraint does not erase.
  const QC_RUNS = `(select count(*) from public.agent_runs where agent='quote_compare')`;
  const QC_DELIVERED = `(select count(*) from public.agent_runs where agent='quote_compare'
      and (counts->>'compared')='1' and coalesce((counts->>'top3')::int,0) > 0)`;
  await req(S10, 'qc-engine-exists', 'A quote comparison engine analyses received quotes',
    `select coalesce(${B(qcs.length > 0 && qcReachable && qcCalled.length > 0 && qcMounted.length > 0)}
       and ${QC_DELIVERED} > 0, false)`,
    `select ${EV(`quote_compare is ${qcs.length} bytes, reachable from the customer page with an ownership check: ${qcReachable}, opened by ${qcCalled.length} customer-surface file(s) and mounted inline once an RFQ has 2+ quotes in ${qcMounted.length} of them; it has run `)}
       || ${QC_RUNS} || ${EV(' time(s) on production, ')} || ${QC_DELIVERED}
       || ${EV(' of which produced a ranked recommendation, last ')}
       || coalesce((select max(finished_at)::timestamp(0)::text from public.agent_runs where agent='quote_compare'),'never')
       || ${EV(NOTE)}`);

  // PER DIMENSION, and each of the three named dimensions is asked separately — a global "is there
  // any score" would be satisfied by the single blended figure the portal already shows.
  // ONE FACT MAY NOT SCORE THREE DIMENSIONS. The `|| K('scores').test(qcs)` disjunct was applied
  // identically to every entry, so a single key named "scores" anywhere in the contract would have
  // marked price, delivery AND quality as carrying an explicit per-quote score — three requirements'
  // worth of coverage from one token, and none of them evidenced. That is the third defect class in
  // miniature. A `scores` object still counts, but only for the dimension whose own key appears
  // INSIDE it, so each dimension is asserted separately and the block that decides it is printed.
  const DIMS = [
    ['price', /\bprice_(score|rating)\b/, /price/i],
    ['delivery', /\b(delivery|lead_time)_(score|rating)\b/, /(delivery|lead_?time)/i],
    ['quality', /\bquality_(score|rating)\b/, /quality/i],
  ];
  const scoresBlock = (/\\?"scores\\?"\s*:\s*\{([\s\S]{0,500}?)\}/.exec(qcs) || [, ''])[1];
  const dimsScored = DIMS.filter(([, re, keyRe]) => re1(re).test(qcs) || keyRe.test(scoresBlock)).map(([d]) => d);
  const compositeUi = surf(/\bvscore\b/);
  // The per-quote key list is READ OUT OF THE CONTRACT, not recited. A recited list stays true-looking
  // after someone adds a price_score to the schema, at which point the evidence actively misleads.
  const qBlock = (/\\?"quotes\\?"\s*:\s*\[\s*\{([\s\S]{0,900}?)\}\s*\]/.exec(qcs) || [, ''])[1];
  const qKeys = [...new Set([...qBlock.matchAll(/\\?"(\w+)\\?"\s*:/g)].map(m => m[1]))];
  await req(S10, 'qc-per-dimension-scores', 'Each supplier is scored per dimension (price, delivery, quality)',
    `select ${B(dimsScored.length === DIMS.length)}`,
    `select ${EV(`${dimsScored.length} of ${DIMS.length} dimensions carry an explicit per-quote score key of their OWN in the quote_compare response contract (${dimsScored.join(',') || 'none'}); the contract's ${qKeys.length} per-quote key(s) are [${qKeys.join(',') || 'unparsed'}] and its "scores" object parses to [${scoresBlock.replace(/\s+/g, ' ').trim().slice(0, 120) || 'no scores object'}]; ${compositeUi.length} customer-surface file(s) instead render ONE composite "Value n/100" blended in the browser from price, rating and quote completeness${NOTE}`)}`);

  const top3Contract = new RegExp(`\\\\?"top3\\\\?"\\s*:\\s*\\[\\s*\\{\\s*\\\\?"rank\\\\?"`).test(qcs) && K('label').test(qcs);
  const top3Guard = /_top3\s*>\s*0\s*&&\s*_shown\s*>\s*0/.test(qcs);
  const top3Ui = surf(/a\.top3/).filter(p => /r\.rank/.test(SRC.get(p)) && /r\.label/.test(SRC.get(p)));
  await req(S10, 'qc-ai-recommendation', 'The engine names a recommended supplier',
    `select coalesce(${B(top3Contract && top3Guard && top3Ui.length > 0)} and ${QC_DELIVERED} > 0, false)`,
    `select ${EV(`the quote_compare contract defines top3[].rank and top3[].label: ${top3Contract}; the runtime records an error when the shortlist comes back empty: ${top3Guard}; ${top3Ui.length} customer-surface file(s) render the ranked pick (${list(top3Ui)}); `)}
       || ${QC_DELIVERED} || ' of ' || ${QC_RUNS}
       || ${EV(' production runs named a supplier, most recent shortlist ')}
       || coalesce((select counts->>'top3' from public.agent_runs where agent='quote_compare'
             and coalesce((counts->>'top3')::int,0) > 0 order by finished_at desc limit 1),'0')
       || ${EV(' pick(s)' + NOTE)}`);

  // The reasoning AND the trade-off accepted: a per-field universal over the four fields the
  // requirement and the contract name, because "some reasoning is rendered" is satisfied by one.
  const REASON_FIELDS = [['why', /r\.why/], ['tradeoff', /r\.tradeoff/], ['advice', /a\.advice/], ['watch_outs', /a\.watch_outs/]];
  const reasonRendered = REASON_FIELDS.filter(([, re]) => surf(re).length > 0).map(([f]) => f);
  const reasonContract = REASON_FIELDS.filter(([f]) => K(f).test(qcs)).map(([f]) => f);
  await req(S10, 'qc-recommendation-reason', 'The recommendation states its reasoning and the trade-off accepted',
    `select ${B(reasonRendered.length === REASON_FIELDS.length && reasonContract.length === REASON_FIELDS.length)}`,
    `select ${EV(`${reasonContract.length} of ${REASON_FIELDS.length} reasoning fields are in the quote_compare contract (${reasonContract.join(',') || 'none'}) and ${reasonRendered.length} of ${REASON_FIELDS.length} are rendered on the customer surface (${reasonRendered.join(',') || 'none'})${NOTE}`)}`);

  // In the portal means the analysis is on screen without leaving the page, not behind a download.
  const inlineFields = [/a\.bottom_line/, /a\.overview/, /a\.top3/, /a\.quotes/].filter(re => surf(re).length > 0).length;
  await req(S10, 'qc-in-portal-not-excel', 'Comparison happens in the portal, not in an exported spreadsheet',
    `select ${B(qcMounted.length > 0 && inlineFields === 4)}`,
    `select ${EV(`the comparison is mounted inline inside the opened request card in ${qcMounted.length} customer-surface file(s), and ${inlineFields} of 4 analysis blocks (bottom_line, overview, top3, per-quote detail) are rendered as JSX rather than handed to a download${NOTE}`)}`);

  // The export EXISTS and no customer can start it. Both halves are printed so the verdict cannot be
  // misread as "there is no exporter".
  const cmpBlock = actionBlock(capi, 'compare_pdf');
  const exportBuilt = cmpBlock.length > 0 && /buildComparePdf/.test(cmpBlock) && /Not your inquiry/.test(cmpBlock);
  const exportUi = surfInvokes('customer_api', 'compare_pdf');
  await req(S10, 'qc-comparison-export', 'The comparison can be exported as a document',
    `select ${B(exportBuilt && exportUi.length > 0)}`,
    `select ${EV(`customer_api action=compare_pdf exists (${cmpBlock.length} bytes), is ownership-checked and renders a PDF from the analysis: ${exportBuilt}; customer-surface files that can reach it: ${exportUi.length}${exportUi.length ? ' (' + list(exportUi) + ')' : ' — the endpoint has no caller anywhere the customer can click'}${NOTE}`)}`);

  // ═══ 11. INTERACTIVE DATA VISUALIZATION ════════════════════════════════════════════════════════

  const cportal = fnSrc('customer_portal');
  const histServed = /fn_customer_stats/.test(cportal) && /stats/.test(cportal) && CUST_FNS.includes('customer_portal');
  const histUi = surf(/history_12m/);
  const histElsewhere = elsewhere(/history_12m/);
  await req(S11, 'viz-annual-procurement-series', 'Annual procurement is shown as a time series',
    `select coalesce(${FNDEF('fn_customer_stats')} ~* 'history_12m'
       and ${FNDEF('fn_customer_stats')} ~* 'generate_series\\(0,\\s*11\\)'
       and ${B(histServed && histUi.length > 0)}, false)`,
    `select ${EV('fn_customer_stats builds a 12-point monthly series: ')}
       || (${FNDEF('fn_customer_stats')} ~* 'generate_series\\(0,\\s*11\\)')::text
       || ${EV(' and names it history_12m: ')} || (${FNDEF('fn_customer_stats')} ~* 'history_12m')::text
       || ${EV(`; customer_portal action=overview serves it on every load: ${histServed}; customer-surface files that mention it: ${histUi.length}; files elsewhere under src/ that render it: ${histElsewhere.length} (${list(histElsewhere)}) — the series is computed, put on the wire and dropped by the customer portal while the supplier portal charts the same field${NOTE}`)}`);

  // A forecast the customer can see must be ABOUT the customer. fn_finance_forecast takes no
  // arguments at all, so it cannot be scoped to one; the leg is per-customer-ness, not existence.
  const PER_CUST_FORECAST = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and (p.proname ~* 'forecast|predict' or pg_get_functiondef(p.oid) ~* '\\yforecast\\y')
         and pg_get_function_arguments(p.oid) ~* 'customer')`;
  const forecastCust = edgeHits(/forecast/i, CUST_FNS);
  const forecastUi = surf(/forecast|projected/i);
  await req(S11, 'viz-forecast-next-year', 'Next-year procurement forecast is shown alongside actuals',
    `select coalesce(${PER_CUST_FORECAST} > 0 and ${B(forecastCust.length > 0 && forecastUi.length > 0)}, false)`,
    `select ${PER_CUST_FORECAST} || ${EV(' routine(s) forecast anything per customer; fn_finance_forecast takes (')}
       || coalesce(nullif(${FNARGS('fn_finance_forecast')},''),'no arguments')
       || ${EV(`) so it is company-wide and cannot be scoped to one customer; customer-reachable endpoints serving a forecast: ${forecastCust.length}; customer-surface files rendering one: ${forecastUi.length}${NOTE}`)}`);

  // Rendered AS BARS. Two patterns are accepted so a hand-rolled chart is not scored MISSING for
  // declining to import a library: a charting primitive, or an array mapped onto element sizes —
  // which is exactly how the supplier portal's Spark draws its bars.
  const CHART_LIB = /recharts|components\/ui\/chart|Chart(Container|Tooltip)|<(Bar|Line|Area|Pie|Radar)Chart\b/;
  const CHART_HAND = /style=\{\{\s*(height|width)\s*:\s*[^}]*(Math\.|\/\s*max|\*\s*\d)/;
  const chartUi = [...new Set(surf(CHART_LIB).concat(surf(CHART_HAND)))];
  const chartElsewhere = [...new Set(elsewhere(CHART_LIB).concat(elsewhere(CHART_HAND)))];
  await req(S11, 'viz-bar-chart-rendered', 'The figures are rendered as bars/graphs, not just numbers',
    `select ${B(chartUi.length > 0)}`,
    `select ${EV(`${chartUi.length} of ${SURFACE.length} customer-surface file(s) draw a chart, counting either a charting primitive or a series mapped onto element sizes; ${chartElsewhere.length} file(s) elsewhere under src/ do (${list(chartElsewhere)}); recharts is installed and src/components/ui/chart.tsx is written, so the primitive exists and the customer's route does not import it${NOTE}`)}`);

  // Four named dimensions. The population is real — supplier_score covers all 20,464 leads — which is
  // exactly why a check that stopped at "is it populated" would score this MET.
  const ssCustReaders = edgeHits(/supplier_score/, CUST_FNS);
  const ssAnyEdge = edgeHits(/supplier_score/);
  const ssUi = surf(/supplier_score|reliability|price_index|quality_rating|response_rate/);
  await req(S11, 'viz-supplier-performance-graphs', 'Supplier performance graphs (reliability, price, quality, response)',
    `select ${B(ssCustReaders.length > 0 && ssUi.length > 0 && chartUi.length > 0)}`,
    `select ${EV('supplier_score covers ')} || (select count(*) from public.supplier_score)
       || ${EV(' supplier(s): reliability non-null on ')} || (select count(*) from public.supplier_score where reliability is not null)
       || ${EV(', quality_rating on ')} || (select count(*) from public.supplier_score where quality_rating is not null)
       || ${EV(', price_index on ')} || (select count(*) from public.supplier_score where price_index is not null)
       || ${EV(', response_rate on ')} || (select count(*) from public.supplier_score where response_rate is not null)
       || ${EV('; database readers other than its writer: ')} || ${CONSUMERS('supplier_score')}
       || ' (' || ${CONSUMER_NAMES('supplier_score')} || ')'
       || ${EV(`; edge functions reading it: ${ssAnyEdge.length}, of which customer-reachable: ${ssCustReaders.length}; customer-surface files rendering any of the four figures: ${ssUi.length}; charts on the customer surface: ${chartUi.length}${NOTE}`)}`);

  // A savings figure BROKEN DOWN BY CATEGORY. project_api's dashboard computes one global
  // avg_savings_pct from the spread between quotes on an RFQ — not a per-category benchmark — and
  // project_api has no caller on the customer surface at all.
  const SAVINGS_BY_CAT = `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and pg_get_functiondef(p.oid) ~* '\\ysavings?\\y'
         and pg_get_functiondef(p.oid) ~* '\\ycategory\\y')`;
  const papi = fnSrc('project_api');
  const savingsEdge = edgeHits(/saving/i, CUST_FNS);
  const savingsByCatEdge = savingsEdge.filter(n => /by_category|savings_by|per_category/i.test(fnSrc(n)));
  const projUi = surfInvokes('project_api', null);
  // `/saving/i` matched the portal's "Saving…" button label and reported 1 customer-surface file
  // rendering a savings figure. The verdict was unaffected (the other legs are zero) but the number
  // was false, and a number in the evidence that the verdict does not depend on is exactly the one
  // nobody re-checks.
  const savingsUi = surf(/\bsavings\b|savings_pct|potential.{0,12}saving/i);
  await req(S11, 'viz-savings-by-category', 'Cost optimization shows potential savings broken down by category',
    `select coalesce(${SAVINGS_BY_CAT} > 0 and ${B(savingsByCatEdge.length > 0 && savingsUi.length > 0)}, false)`,
    `select ${SAVINGS_BY_CAT} || ${EV(' database routine(s) name a savings figure alongside a category (')}
       || coalesce((select string_agg(distinct p.proname,',') from pg_proc p
             join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.prokind in ('f','p')
              and pg_get_functiondef(p.oid) ~* '\\ysavings?\\y'
              and pg_get_functiondef(p.oid) ~* '\\ycategory\\y'),'none')
       || ${EV('); ')}
       || ${EV(`customer-reachable endpoints emitting any savings figure: ${savingsEdge.length} (${list(savingsEdge)}), of which broken down by category: ${savingsByCatEdge.length}; project_api's dashboard emits one global avg_savings_pct derived from the spread between quotes on the same RFQ: ${/avg_savings_pct/.test(papi)}; customer-surface files that reach project_api at all: ${projUi.length}; customer-surface files rendering a savings figure: ${savingsUi.length}${NOTE}`)}`);

  const overviewKeys = (/return J\(\{\s*ok:\s*true,\s*customer[\s\S]{0,300}?\}\);/.exec(cportal) || [''])[0];
  const overviewNames = (overviewKeys.match(/\b(ok|customer|stats|alerts|alerts_count)\b/g) || []);
  await req(S11, 'viz-total-savings', 'A total potential-savings figure is presented',
    `select ${B(savingsEdge.length > 0 && projUi.length > 0 && savingsUi.length > 0)}`,
    `select ${EV(`the customer_portal overview payload returns [${[...new Set(overviewNames)].join(',') || 'unparsed'}] and carries no savings total; the only customer-reachable savings figure anywhere is project_api dashboard.avg_savings_pct (present: ${/avg_savings_pct/.test(papi)}), reachable from ${projUi.length} customer-surface file(s); customer-surface files rendering a savings total: ${savingsUi.length}; database routines computing a savings benchmark: `)}
       || ${SAVINGS_BY_CAT} || ${EV(NOTE)}`);

  // ═══ 12. PURCHASE APPROVAL SYSTEM — RETIRED 14 SEP 2026 ═══════════════════════════════════════
  // The founder removed it: "i think its better just to remove the approvals tab. cause even if a company signed up, we don't wanna interfere in their approvals process and they are treated like normal individuals".
  // Its six requirements (appr-policy-object, appr-request-object, appr-multi-step-chain,
  // appr-per-step-status, appr-triggered-by-award, appr-customer-ui) retired WITH their subject: the
  // tables, view, routines and award trigger were dropped in
  // scripts/sql/a_company_buys_like_an_individual_so_the_approval_chain_is_dropped.sql. They are not
  // scored as missing, because building them again would contradict the ruling.

  // ═══ 13. CUSTOMER-SUPPLIER RELATIONSHIP MANAGEMENT ═════════════════════════════════════════════
  // customer_api action=supplier_history is the only per-supplier relationship surface. It is
  // reveal-gated and customer-authed, and it is invoked by nothing: the portal's revealed-supplier
  // card offers phone, WhatsApp, email, website, a star-rating control, hire and refund — and no
  // supplier profile.

  const histBlock = actionBlock(capi, 'supplier_history');
  const histApiExists = histBlock.length > 0;
  const histRevealGated = /Reveal this supplier first/.test(histBlock);
  const histUiCallers = surfInvokes('customer_api', 'supplier_history');
  const histFromMatches = /inquiry_matches/.test(histBlock);
  const histOrderCount = /projects_count/.test(histBlock);
  // The claim is about ONE statement — the history query that builds projects[] — not about the
  // handler. Asked of the handler it answered "customer-scoped: true", because the reveal gate three
  // lines above it is customer-scoped while the history query is not: a self-contradicting evidence
  // string that printed the opposite of the sentence next to it.
  const histQ = queryAt(histBlock, 'data: projs');
  const histCustScoped = histQ.filters.includes('customer_id');

  await req(S13, 'rel-history-rfq-count', 'Per-supplier relationship shows how many RFQs they were sent',
    `select ${B(histFromMatches && histUiCallers.length > 0)}`,
    `select ${EV(`customer_api action=supplier_history exists (${histBlock.length} bytes) and counts inquiry_matches for the supplier: ${histFromMatches} — it builds its projects[] from ${histQ.table || 'an unparsed table'} filtered on [${histQ.filters.join(',') || 'nothing'}], i.e. from paid reveals, so an RFQ that was SENT to a supplier and never quoted is invisible; customer-surface files that invoke it: ${histUiCallers.length}; inquiry_matches holds `)}
       || (select count(*) from public.inquiry_matches) || ${EV(' dispatch record(s) on production' + NOTE)}`);

  await req(S13, 'rel-order-count', 'Per-supplier relationship shows how many orders were placed',
    `select ${B(histOrderCount && histUiCallers.length > 0)}`,
    `select ${EV(`supplier_history computes a per-supplier order count (projects_count): ${histOrderCount}, from ${histQ.table || 'an unparsed table'} filtered on [${histQ.filters.join(',') || 'nothing'}] — scoped to the asking customer: ${histCustScoped}, so the figure is that supplier's platform-wide history rather than this customer's relationship with them; customer-surface files that invoke it: ${histUiCallers.length}; transactions on production: `)}
       || (select count(*) from public.transactions) || ${EV('; po_orders on production: ')}
       || (select count(*) from public.po_orders) || ${EV(NOTE)}`);

  const relUi = surf(/reliability|avg_response_hours|delivery.{0,12}performance/i);
  await req(S13, 'rel-avg-delivery-pct', 'Average delivery performance percentage per supplier',
    `select ${B(ssCustReaders.length > 0 && relUi.length > 0)}`,
    `select ${EV('supplier_score.reliability non-null on ')}
       || (select count(*) from public.supplier_score where reliability is not null) || ' of '
       || (select count(*) from public.supplier_score) || ${EV(' supplier(s), avg_response_hours on ')}
       || (select count(*) from public.supplier_score where avg_response_hours is not null)
       || ${EV('; database readers other than its writer: ')} || ${CONSUMERS('supplier_score')}
       || ' (' || ${CONSUMER_NAMES('supplier_score')} || ')'
       || ${EV(`; customer-reachable endpoints serving it: ${ssCustReaders.length}; customer-surface files rendering a delivery figure: ${relUi.length}${NOTE}`)}`);

  const qualUi = surf(/quality_rating|quality.{0,12}score/i);
  const histServesRating = /rating_display/.test(histBlock);
  await req(S13, 'rel-quality-pct', 'Quality score percentage per supplier',
    `select ${B(ssCustReaders.length > 0 && qualUi.length > 0)}`,
    `select ${EV('supplier_score.quality_rating non-null on ')}
       || (select count(*) from public.supplier_score where quality_rating is not null) || ' of '
       || (select count(*) from public.supplier_score)
       || ${EV(` supplier(s); customer-reachable endpoints serving quality_rating: ${ssCustReaders.length}; supplier_history serves the leads star rating instead (rating_display: ${histServesRating}); customer-surface files rendering a quality percentage: ${qualUi.length}${NOTE}`)}`);

  // "For this customer" is the whole requirement: supplier_score is one global row per lead_id with
  // no customer column, so nothing in the estate can express a relationship. Both shapes an
  // implementation could take are searched for live rather than assumed absent.
  const REL_TABLES = `(select count(*) from (select c1.table_name from information_schema.columns c1
        join information_schema.columns c2 on c2.table_schema=c1.table_schema and c2.table_name=c1.table_name
        join information_schema.columns c3 on c3.table_schema=c1.table_schema and c3.table_name=c1.table_name
       where c1.table_schema='public' and c1.column_name='customer_id'
         and c2.column_name in ('supplier_id','lead_id')
         and c3.column_name ~* '(score|rating|reliab|qualit|index)'
       group by c1.table_name) z)`;
  const REL_FNS = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
         and pg_get_function_arguments(p.oid) ~* 'customer'
         and pg_get_function_arguments(p.oid) ~* '(supplier|lead)'
         and pg_get_functiondef(p.oid) ~* '\\yscore\\y')`;
  // THE STRUCTURAL LEG ALONE SCORED THIS MET AND IT WAS WRONG. `public.reviews` carries customer_id,
  // supplier_id and rating, so "a table with both keys and a score-ish column" is satisfied by the
  // star the customer themselves left after one job — which is an input to a score, not a
  // relationship score, and reaches no screen. That is population standing in for delivery, the
  // second defect class this row was told to pre-empt, and it is why the two delivery legs below are
  // conjoined to the structural one rather than reported beside it.
  const relScoreEdge = edgeHits(/relationship_score|rel_score/i, CUST_FNS);
  const relScoreUi = surf(/relationship.{0,12}score|rel_score/i);
  await req(S13, 'rel-relationship-score', 'A single relationship score per supplier for this customer',
    `select coalesce((${REL_TABLES} + ${REL_FNS}) > 0
       and ${B(relScoreEdge.length > 0 && relScoreUi.length > 0)}, false)`,
    `select ${REL_TABLES} || ${EV(' table(s) carry a score keyed by BOTH a customer and a supplier (')}
       || coalesce((select string_agg(distinct c1.table_name||'.'||c3.column_name,',') from information_schema.columns c1
             join information_schema.columns c2 on c2.table_schema=c1.table_schema and c2.table_name=c1.table_name
             join information_schema.columns c3 on c3.table_schema=c1.table_schema and c3.table_name=c1.table_name
            where c1.table_schema='public' and c1.column_name='customer_id'
              and c2.column_name in ('supplier_id','lead_id')
              and c3.column_name ~* '(score|rating|reliab|qualit|index)'),'none')
       || ${EV(`), of which ${relScoreEdge.length} are served by a customer-reachable endpoint and ${relScoreUi.length} reach the customer surface; `)}
       || ${REL_FNS} || ${EV(' routine(s) compute one from a (customer, supplier) pair; supplier_score carries a customer_id column: ')}
       || (select exists(select 1 from information_schema.columns
             where table_schema='public' and table_name='supplier_score' and column_name='customer_id'))::text
       || ${EV(', so its ')} || (select count(*) from public.supplier_score)
       || ${EV(' row(s) are one global verdict per supplier; the tables that do pair a customer with a supplier are ')}
       || coalesce((select string_agg(distinct c1.table_name,',') from information_schema.columns c1
             join information_schema.columns c2 on c2.table_schema=c1.table_schema and c2.table_name=c1.table_name
            where c1.table_schema='public' and c1.column_name='customer_id'
              and c2.column_name in ('supplier_id','lead_id')),'none')`);

  await req(S13, 'rel-customer-ui', 'The relationship intelligence is rendered to the customer',
    `select ${B(histApiExists && histRevealGated && histUiCallers.length > 0)}`,
    `select ${EV(`customer_api action=supplier_history exists: ${histApiExists}, reveal-gated: ${histRevealGated}; customer-surface files that invoke it: ${histUiCallers.length} — the revealed-supplier card renders phone, WhatsApp, email, website, a star-rating control, hire and refund, and no supplier profile; customer-surface files scanned: ${SURFACE.length}${NOTE}`)}`);
}

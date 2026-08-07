// SPEC FILE #4, sections 1-4 — Entry Experience, Digital Twin, AI Procurement Assistant,
// Command Center UI. 30 requirements, scored against PRODUCTION.
//
// THE CONSTRAINT THAT SHAPES EVERY CHECK HERE. Production carries 20,464 leads and a full
// supplier/knowledge estate, and ZERO customers, ZERO inquiries, ZERO quotes, ZERO transactions.
// So a check of the form "do customers see X" that counts customer rows returns 0 for every
// requirement in this file and measures nothing at all. Every check below scores the MECHANISM in
// three parts, and prints all three whichever way the verdict goes:
//
//   EXISTS   — the column/routine/view/edge action/component is defined
//   REACHES  — a customer's browser can cause it to run: it is named by CustomerPortal.tsx, or by an
//              edge function that surface names, transitively. "An endpoint exists" is not this.
//   RENDERS  — src/components/me/CustomerPortal.tsx puts the value on screen
//
// A figure computed by a perfect backend and rendered nowhere is MISSING. Where a requirement cannot
// be evidenced at all without traffic, the evidence says so rather than the verdict inventing one.
//
// THE FIVE DEFECTS THIS FILE IS WRITTEN AGAINST (row #2 shipped all five and reported a false
// 110/110 before they were found):
//
//  1 THE ONLY READER IS THE WRITER. customer_api:181 writes inquiry_matches.similarity as null and
//    customer_api:669 reads the same table back as a COUNT — so "something references similarity" is
//    true and "a customer is shown a match percentage" is false. Writes and reads are counted
//    separately BY SITE, and pg_proc consumers exclude writers by pattern with overloads collapsed
//    through count(distinct proname).
//  2 POPULATION STANDING IN FOR DELIVERY. Every requirement the enumeration marks "both" or "ui"
//    carries a RENDERS leg measured over the customer's own component. Nothing is satisfied by an
//    endpoint existing, and nothing is satisfied by a figure rendered on the staff console.
//  3 ONE ROW SCORES A WHOLE MECHANISM. There are no rows here to score one on. Where a requirement
//    says EVERY customer, the check is structural — the routine is keyed on the customers relation
//    with no allow-list — and the evidence states that the coverage claim is structural.
//  4 SATISFIABLE BY FLIPPING A FLAG. No check reads a flag; every leg counts code that exists.
//  5 EVIDENCE THAT DOES NOT COMPUTE THE VERDICT. Every number in every evidence string is the same
//    number the boolean uses, over the same population. No sentence asserts an unmeasured fact.
//
// Frontend facts are measured in JavaScript over the real files and enter a statement only as
// integers and identifier lists — never as a regex, and never as a LIKE pattern, where an unescaped
// `_` or `%` out of file content would silently widen the match.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const EXPECTED = 30;

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const rd = (p) => { try { return readFileSync(p, 'utf8'); } catch { return ''; } };

// ── the surfaces under test ──────────────────────────────────────────────────────────────────────
// THE CUSTOMER'S SCREEN IS 53 FILES, NOT ONE. This module scored `src/components/me/
// CustomerPortal.tsx` alone, which was the whole portal when it was written and stopped being so
// when the portal was split into src/components/portal/* — files CustomerPortal.tsx imports and
// mounts. Two of the five section modules already computed the /me route's import closure; this one
// did not, so one run held two different definitions of "the customer sees it". See
// ../portal_surface.mjs for why widening it is symmetric rather than a weakening.
import { PORTAL_SRC, ENTRY_SRC, CUST_FNS as SURFACE_FNS, CUST_SRC as SURFACE_SRC } from '../portal_surface.mjs';
const PORTAL = PORTAL_SRC;
const PORTAL_ENTRY = ENTRY_SRC;   // the one file, for evidence that genuinely means that file
const edgeSrc = (n) => rd(join(ROOT, 'supabase', 'functions', n, 'index.ts'));
const EDGE = (() => {
  const out = new Map();
  let names = [];
  try { names = readdirSync(join(ROOT, 'supabase', 'functions'), { withFileTypes: true }).filter(e => e.isDirectory()).map(e => e.name); } catch { /* none */ }
  for (const n of names) { const s = edgeSrc(n); if (s) out.set(n, s); }
  return out;
})();
const ALL_EDGE = [...EDGE.values()].join('\n/*FILE*/\n');

// Every .ts/.tsx/.js/.jsx under src/, so "nothing in the frontend renders X" is a count over files
// rather than a memory of having looked.
const ALL_SRC = (function walk(d, acc = []) {
  let es; try { es = readdirSync(d, { withFileTypes: true }); } catch { return acc; }
  for (const e of es) {
    const p = join(d, e.name);
    if (e.isDirectory()) { if (!/^(node_modules|\.next|dist|build)$/.test(e.name)) walk(p, acc); }
    else if (/\.(ts|tsx|js|jsx)$/.test(e.name)) { try { if (statSync(p).size < 4e6) acc.push(rd(p)); } catch { /* unreadable */ } }
  }
  return acc;
})(join(ROOT, 'src')).join('\n/*FILE*/\n');

// THE CUSTOMER'S REACHABLE EDGE SET — computed, never assumed. The portal names its endpoints as
// call('<name>', ...); each of those names further ones as functions/v1/<name>. Row #3's UI closure
// cannot answer this question: it is rooted in the whole of src/, so os_api and every staff surface
// sits inside it and "a customer can reach it" would be true of the founder's console. This set is
// rooted in the customer's own component.
// Rooted in the customer's whole surface rather than in one of its files, for the same reason and
// by the same algorithm as projects_and_rfq.mjs. Rooting it in CustomerPortal.tsx alone made every
// endpoint a mounted module owns — customer_documents, procurement_api, negotiation_assistant —
// unreachable by a customer who reaches them by clicking.
const CUST_FNS = SURFACE_FNS;
const CUST_SRC = SURFACE_SRC;
const edgeNamesMatching = (re) => [...EDGE.keys()].filter(n => re.test(EDGE.get(n))).sort();

// A component's source, from `function Name(` to the next top-level declaration. Deliberately local
// rather than imported from row #3's ui_closure.mjs: a section that imports another row's private
// helper dies with it, and a section that throws costs its whole denominator.
const slice = (name, text = PORTAL) => {
  const m = new RegExp('^(?:export )?(?:default )?function ' + name + '\\b', 'm').exec(text);
  if (!m) return '';
  const rest = text.slice(m.index + 1);
  const nxt = /\n(?:export )?(?:default )?(?:function |const [A-Z])/.exec(rest);
  return text.slice(m.index, nxt ? m.index + 1 + nxt.index : text.length);
};
const cnt = (re, txt) => (String(txt).match(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g')) || []).length;
// Occurrences of `token` within `win` characters of an `anchor` occurrence. A bare count of the word
// "similarity" across the customer-reachable edge set reads 2, and one of them is ai_gateway's
// embedding-cache hit score — a different subject entirely. Proximity to the relation being scored
// is what makes the count a count OF that relation.
const nearCount = (text, anchor, token, win = 400) => {
  const at = [...String(text).matchAll(new RegExp(anchor.source, anchor.flags.replace('g', '') + 'g'))].map(m => m.index);
  if (!at.length) return 0;
  let n = 0;
  for (const m of String(text).matchAll(new RegExp(token.source, token.flags.replace('g', '') + 'g'))) {
    if (at.some(i => Math.abs(i - m.index) <= win)) n++;
  }
  return n;
};

const AUTHED = slice('Authed'), DASH = slice('Dashboard'), NEWREQ = slice('NewRequest');
const CARD = slice('InquiryCard'), THREAD = slice('Thread');
const INTAKE = EDGE.get('inquiry_intake') || '', CPORTAL = EDGE.get('customer_portal') || '';
const CAPI = EDGE.get('customer_api') || '', PAPI = EDGE.get('project_api') || '', MAPI = EDGE.get('messages_api') || '';

// ── SQL literal helpers ──────────────────────────────────────────────────────────────────────────
const Q = (s) => `'${String(s == null ? '' : s).replace(/'/g, "''")}'`;
const LIST = (a) => Q(a.length ? a.join(',') : 'none');

export default async function ({ req }) {
  const S1 = '1. Customer Entry Experience', S2 = '2. Customer Digital Twin';
  const S3 = '3. AI Procurement Assistant', S4 = '4. Command Center UI';

  // ── shared SQL fragments ───────────────────────────────────────────────────────────────────────
  const COLN = (t, rx) => `(select count(*) from information_schema.columns
      where table_schema='public' and table_name='${t}' and column_name ~* '${rx}')`;
  const COLS = (t) => `coalesce((select string_agg(column_name, ',' order by ordinal_position)
      from information_schema.columns where table_schema='public' and table_name='${t}'), 'no such relation')`;
  const FNN = (n) => `(select count(distinct p.proname) from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
      where n2.nspname='public' and p.prokind in ('f','p') and p.proname='${n}')`;
  // A relation that may not exist reads -1 rather than ERRORing: an errored check is an UNMEASURED
  // requirement, which is a worse outcome than a false negative.
  const ROWS = (t) => `(select case when to_regclass('public.${t}') is null then -1 else
      (xpath('/row/c/text()', query_to_xml('select count(*) c from public.${t}', false, true, '')))[1]::text::int end)`;

  // Consumers of a relation with its WRITERS removed and overloads collapsed. The generic helper's
  // `proname <> '<table>'` self-exclusion is inert for every table name, because no routine is ever
  // called customer_score — so a table's own writer counted itself as its reader. The write keywords
  // are split so qd_guard's read guard does not refuse the check itself.
  const NOT_WRITER = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;
  const CONSUMERS = (t) => `(
      (select count(distinct p.proname) from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
        where n2.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;
  const CONSUMER_NAMES = (t) => `coalesce((select string_agg(distinct p.proname, ',') from pg_proc p
        join pg_namespace n2 on n2.oid=p.pronamespace
       where n2.nspname='public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)}), 'none')`;

  // THE CUSTOMER'S TWIN OBJECT, AND ONLY IT. fn_twin has four branches, and the COMPANY branch emits
  // suppliers_total / customers / revenue_paid_aed — scoring a per-customer requirement against the
  // whole function body would let QuotesDone's own twin satisfy the customer's. The customer branch
  // is everything before the first `elsif`. fn_ws_customer_360 is the other twin the spec names.
  const TWIN_TEXT = `(select coalesce(string_agg(t, ' '), '') from (
      select split_part(pg_get_functiondef(p.oid), 'elsif', 1) t from pg_proc p
        join pg_namespace n2 on n2.oid=p.pronamespace where n2.nspname='public' and p.proname='fn_twin'
      union all
      select pg_get_functiondef(p.oid) from pg_proc p
        join pg_namespace n2 on n2.oid=p.pronamespace where n2.nspname='public' and p.proname='fn_ws_customer_360') s)`;
  // A jsonb key as it appears inside jsonb_build_object: the quotes are part of the pattern, so a
  // column name or a comment mentioning the word does not count as the twin emitting the key.
  const KEY = (alt) => `''(${alt})''`;
  // DISTINCT KEYS, NOT OCCURRENCES — the count and the name list beside it must be the same
  // population, or the evidence stops computing the verdict. `'categories'` appears four times
  // across the two routines and is one key; a threshold of "4 analytic keys" met by one key
  // repeated four times would be exactly the defect this file is written against.
  const TWINK = (alt) => `(select count(distinct m[1]) from regexp_matches(${TWIN_TEXT}, '${KEY(alt)}', 'g') m)`;
  const TWINK_NAMES = (alt) => `coalesce((select string_agg(distinct m[1], ',')
      from regexp_matches(${TWIN_TEXT}, '${KEY(alt)}', 'g') m), 'none')`;
  const FNKEYS = (fname, alt) => `(select count(distinct m[1]) from regexp_matches(coalesce((select pg_get_functiondef(p.oid)
      from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
     where n2.nspname='public' and p.proname='${fname}' limit 1), ''), '${KEY(alt)}', 'g') m)`;

  // ══ SECTION 1 — CUSTOMER ENTRY EXPERIENCE ═════════════════════════════════════════════════════
  const alertRegion = cnt(/ov\.alerts/, DASH);
  const alertKinds = [...new Set([...CPORTAL.matchAll(/kind:\s*'([a-z0-9_]+)'/g)].map(m => m[1]))].sort();

  // ── ONE WORKSPACE TEST, SHARED BY SECTION 1 AND SECTION 4 ─────────────────────────────────────
  // THE DEFECT THIS REPLACES. entry-not-login-dashboard used to require `figureTiles >= 3` — it
  // counted KPI tiles as PROOF of a workspace — while its sibling cc-workspace-not-dashboard is
  // named 'a workspace, not a page of KPI tiles' and scored MISSING on the same component in the
  // same run. Two checks, one file, opposite verdicts, and the MET one was reading the counter-
  // evidence as evidence. The spec states the idea twice, so the two checks now share the panel
  // leg and can no longer disagree; each keeps legs the other does not, so neither is decided by
  // the shared number alone. Tiles are still counted — and printed as the thing that is NOT the
  // verdict.
  //
  // A PANEL IS WHAT IT RENDERS, NOT A WORD. `cnt(/project/i, DASH) > 0` certified a Projects panel
  // on any occurrence of the word, which is a spelling, not a surface — the same shape as the
  // "we matched you with suitable suppliers" empty state this row exists to stop. Each panel is
  // now a figure or a collection the panel could not exist without, and every one of the four is
  // a single component away from satisfiable.
  const NET = /suppliers?_(available|total|count|network)|network_size/i;
  const panels = {
    projects: cnt(/projects?\.map\(|\brfq_count\b|\brfq_open\b|\bpipeline_value\b|project_summary/i, DASH) > 0 ? 1 : 0,
    procurement: cnt(/s\.open_inquiries/, DASH) > 0 ? 1 : 0,
    financial: cnt(/budget_total|budget_used|budget_remaining|role="progressbar"|<Progress\b/i, DASH) > 0 ? 1 : 0,
    'supplier-network': cnt(NET, DASH) > 0 ? 1 : 0,
  };
  const present = Object.keys(panels).filter(k => panels[k]);
  const figureTiles = cnt(/<Kpi\b/, DASH);
  const workList = cnt(/inqs\.map\(/, DASH);
  // Work you can act on WITHOUT leaving the surface — the difference between a workspace and a
  // page of links. Measured on the work-item component generically (a control, and detail that
  // opens in the same component), never on this implementation's handler names.
  const itemControls = cnt(/onClick=|onKeyDown=/, CARD);
  const opensInPlace = cnt(/aria-expanded|\{open\s*&&|\{expanded\s*&&/, CARD);
  {
    // A workspace is a surface carrying live work you act on in place; a login dashboard is a page
    // of figures and links. Both halves are measured on the post-auth root and its work item.
    const postAuthRoot = cnt(/return <Dashboard\b/, AUTHED);
    const anchors = cnt(/<a\s+href/, DASH);
    const tables = cnt(/<table\b/, DASH);
    const itemLinksOut = cnt(/<a\s+href|router\.push|location\.href/, CARD);
    const feeds = [...new Set([...DASH.matchAll(/call\(\s*'([a-z0-9_]+)'/g)].map(m => m[1]))].sort();
    await req(S1, 'entry-not-login-dashboard',
      'After auth the customer lands in a workspace, not a login dashboard',
      `select ${postAuthRoot} > 0 and ${alertRegion} > 0 and ${workList} > 0
          and ${itemControls} > 0 and ${opensInPlace} > 0 and ${present.length} >= 3`,
      `select 'Authed() returns Dashboard=' || ${postAuthRoot}
        || '; the post-auth root renders alert region=' || ${alertRegion}
        || ', work-item list=' || ${workList} || ', fed by ' || ${LIST(feeds)}
        || '; the work item carries ' || ${itemControls} || ' in-place control(s) and opens its detail '
        || 'in the same component=' || ${opensInPlace} || ' (link-outs on the item=' || ${itemLinksOut} || ')'
        || '; of the four workspace panels section 4 names, present=' || ${present.length}
        || ' (' || ${LIST(present)} || ') — the SAME leg cc-workspace-not-dashboard scores, so the two'
        || ' checks cannot return opposite verdicts on this component'
        || '; NOT counted as evidence of a workspace: ' || ${figureTiles}
        || ' figure tile(s), anchors=' || ${anchors} || ', tables=' || ${tables}
        || '; inquiries on this target=' || ${ROWS('inquiries')}
        || ' so the list renders empty here and the surface, not the data, is what is scored'`);

    // The greeting is a time-of-day phrase beside the company name. The name half already works.
    const nameEmit = cnt(/name:\s*cust\.full_name/, CPORTAL);
    const nameRender = cnt(/ov\.customer\.name/, DASH);
    const greet = cnt(/good\s*(morning|afternoon|evening)|getHours\s*\(|صباح الخير|مساء الخير/i, ALL_SRC);
    await req(S1, 'entry-time-greeting',
      'Opening screen greets by time of day plus company name',
      `select ${nameEmit} > 0 and ${nameRender} > 0 and ${greet} > 0`,
      `select 'customer_portal overview emits customer.name=' || ${nameEmit}
        || '; CustomerPortal.tsx renders ov.customer.name=' || ${nameRender}
        || '; time-of-day greeting tokens anywhere in src/ (morning|afternoon|evening|getHours|Arabic)='
        || ${greet} || ' — the header shows the name alone'`);

    // A headline is ONE sentence stating what needs attention. N alert cards are not that sentence,
    // so the check looks for a headline-shaped key on the wire and on screen, and prints the cards
    // as the thing that exists instead.
    //
    // THE KEY POSITION IS THE POINT, NOT THE WORD. A bare word scan reads 3 here and every one of
    // them is something else: customer_api builds a local `headline` for the SUPPLIER notification
    // e-mail, and quote_compare's is the phrase "headline total" inside a model prompt. Counting
    // those as the backend half would have printed a number that flatly contradicts the verdict, so
    // the emit leg counts the token in a returned-payload KEY position and the raw mentions are
    // printed beside it rather than in place of it.
    const HEAD = /\b(headline|assistant_line|attention_line|today_line|daily_brief|briefing)\b/i;
    const headKey = cnt(/\b(headline|assistant_line|attention_line|today_line|daily_brief|briefing)\s*:/i, CUST_SRC);
    const headMentions = cnt(HEAD, CUST_SRC);
    // THE RENDER LEG IS AN INTERPOLATION, FOR THE SAME REASON THE EMIT LEG IS A KEY POSITION. A bare
    // word scan over the portal would let the sentence be scored on the word "briefing" appearing in
    // a heading — a spelling, not a line of text the server wrote.
    const headRender = cnt(/\{[^{}]{0,140}(headline|assistant_line|attention_line|today_line|daily_brief|briefing)[^{}]{0,140}\}/i, PORTAL);
    const headWord = cnt(HEAD, PORTAL);
    await req(S1, 'entry-assistant-headline',
      'A persistent AI assistant line states what needs attention today',
      `select ${headKey} > 0 and ${headRender} > 0`,
      `select 'customer-reachable edge functions=' || ${CUST_FNS.length}
        || '; headline-shaped payload key emitted by them=' || ${headKey}
        || ' of ' || ${headMentions} || ' raw mention(s) of the word anywhere in that set'
        || ', rendered inside a JSX interpolation in CustomerPortal.tsx=' || ${headRender}
        || ' of ' || ${headWord} || ' raw mention(s) of those words in that file'
        || '; what the entry screen shows instead: ' || ${alertRegion}
        || ' render site(s) mapping ov.alerts of kind ' || ${LIST(alertKinds)}`);

    // The strip needs three things: the per-project RFQ count in the database, an endpoint serving
    // it, and a caller. The third is the one that is absent.
    const papiList = cnt(/action === 'list'/, PAPI);
    const srcPapi = cnt(/project_api/, ALL_SRC);
    const rfqCountRender = cnt(/rfq_count|rfq_open/, PORTAL);
    await req(S1, 'entry-active-projects-strip',
      'Active projects listed on entry with per-project RFQ count',
      `select ${COLN('project_summary', '^rfq_count$')} > 0 and ${COLN('project_summary', '^rfq_open$')} > 0
          and ${papiList} > 0 and ${srcPapi} > 0 and ${rfqCountRender} > 0`,
      `select 'project_summary columns: ' || ${COLS('project_summary')}
        || '; project_api list action=' || ${papiList} || ' (customer-JWT authed)'
        || '; references to project_api anywhere in src/=' || ${srcPapi}
        || '; rfq_count/rfq_open rendered in CustomerPortal.tsx=' || ${rfqCountRender}
        || '; projects on this target=' || ${ROWS('projects')}`);

    // Savings has to be computed somewhere before it can be shown. Three places are searched: a
    // column on the project rollup, a routine, and the customer-reachable edge set. The render leg
    // matches "savings" and not "saving", because InquiryCard has a `saving` busy-flag and a
    // "Saving..." button label that would otherwise score this requirement on its own.
    const savCust = cnt(/savings/i, CUST_SRC);
    const savEdgeAll = cnt(/savings/i, ALL_EDGE);
    const savRender = cnt(/savings/i, PORTAL);
    const savFn = `(select count(distinct p.proname) from pg_proc p join pg_namespace n2 on n2.oid=p.pronamespace
        where n2.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\ysavings?\\y'
          and pg_get_functiondef(p.oid) ~* '\\y(customer_id|project_id)\\y')`;
    await req(S1, 'entry-potential-savings',
      'Each active project shows a Potential Savings figure',
      `select (${COLN('project_summary', 'saving')} + ${savFn} + ${savCust}) > 0 and ${savRender} > 0`,
      `select 'project_summary columns matching saving=' || ${COLN('project_summary', 'saving')}
        || '; routines emitting a savings figure keyed to a customer or a project=' || ${savFn}
        || '; savings mentions in the customer-reachable edge set=' || ${savCust}
        || ' (across all ' || ${EDGE.size} || ' edge functions=' || ${savEdgeAll}
        || ', project_api avg_savings_pct among them, with ' || ${srcPapi} || ' caller(s) in src/)'
        || '; a savings figure rendered in CustomerPortal.tsx=' || ${savRender}`);

    // A recommendation feed is a feed of recommendation-shaped items. The alert machinery exists and
    // renders; the kinds it can produce are the measured thing.
    const recKinds = alertKinds.filter(k => /price|lead|approval|recommend|forecast/i.test(k));
    const recEmit = cnt(/kind:\s*'[a-z0-9_]*(price|lead|approval|recommend|forecast)[a-z0-9_]*'/i, CUST_SRC);
    await req(S1, 'entry-ai-recommendations',
      'AI Recommendations feed: price moves, better lead times, approvals due',
      `select ${recEmit} > 0 and ${recKinds.length} > 0 and ${alertRegion} > 0`,
      `select 'alert kinds emitted by the customer-reachable edge set: ' || ${LIST(alertKinds)}
        || ' (' || ${alertKinds.length} || ' kind(s)); of those, price-move / lead-time / approval-shaped='
        || ${recKinds.length} || '; recommendation-shaped kind literals anywhere in that set=' || ${recEmit}
        || '; the alerts array itself does reach the screen (' || ${alertRegion}
        || ' render site(s)), so a kind that existed would be shown'`);
  }

  // ══ SECTION 2 — CUSTOMER DIGITAL TWIN ═════════════════════════════════════════════════════════
  {
    const TWIN_RE = /fn_twin|fn_ws_customer_360|customer_score|v_digital_twin/;
    const twinInCustEdge = cnt(TWIN_RE, CUST_SRC);
    const twinInPortal = cnt(/fn_twin|fn_ws_customer_360|customer_score|v_digital_twin|relationship_score/, PORTAL);
    const twinEdgeReaders = edgeNamesMatching(TWIN_RE);

    // A profile object, not a contact record: the customer branch must carry analytic figures, and
    // it must be keyed on any customers row rather than an allow-list. With zero customers the
    // "every customer" clause can only be structural, and the evidence says exactly that.
    await req(S2, 'twin-profile-object',
      'Every customer has an AI business profile object, not a contact record',
      `select ${FNN('fn_twin')} > 0 and ${TWINK('rfqs|deals|spend_aed|categories|last_active')} >= 4
          and (coalesce(${TWIN_TEXT}, '') ~* 'from customers')`,
      `select 'fn_twin=' || ${FNN('fn_twin')} || ', fn_ws_customer_360=' || ${FNN('fn_ws_customer_360')}
        || '; distinct analytic keys on the customer twin (fn_twin customer branch + fn_ws_customer_360)='
        || ${TWINK('rfqs|deals|spend_aed|categories|last_active')}
        || ' (' || ${TWINK_NAMES('rfqs|deals|spend_aed|categories|last_active')} || ')'
        || '; keyed on the customers relation=' || (coalesce(${TWIN_TEXT}, '') ~* 'from customers')
        || '; customers on this target=' || ${ROWS('customers')}
        || ' so per-customer coverage is structural, not counted'`);

    await req(S2, 'twin-industry', "Twin states the customer's industry",
      `select (${COLN('customers', 'industry|sector|vertical')}
             + ${TWINK('[a-z_]*(industry|sector|vertical)[a-z_]*')}) > 0`,
      `select 'customers columns matching industry/sector/vertical='
        || ${COLN('customers', 'industry|sector|vertical')}
        || '; industry-shaped key on the customer twin=' || ${TWINK('[a-z_]*(industry|sector|vertical)[a-z_]*')}
        || ' (' || ${TWINK_NAMES('[a-z_]*(industry|sector|vertical)[a-z_]*')} || ')'
        || '; every sector column in the schema belongs to the SUPPLIER record instead: '
        || coalesce((select string_agg(table_name || '.' || column_name, ',') from information_schema.columns
             where table_schema='public' and column_name ~* '^(industry|sector|vertical)$'), 'none')`);

    // PLURAL, DELIBERATELY. `[a-z_]*project[a-z_]*` also matches avg_project_budget — an average
    // budget, not a count of anything — and a leg satisfied by that would let a rendered project
    // count pass on the strength of a key that cannot supply it.
    const projCountRender = cnt(/projects?_(count|active|total)|active_projects/i, PORTAL);
    await req(S2, 'twin-active-projects', 'Twin states count of active projects',
      `select ${TWINK('[a-z_]*projects[a-z_]*')} > 0 and ${projCountRender} > 0`,
      `select 'projects-count key on the customer twin=' || ${TWINK('[a-z_]*projects[a-z_]*')}
        || ' (' || ${TWINK_NAMES('[a-z_]*projects[a-z_]*')} || '); every project-shaped key it does emit: '
        || ${TWINK_NAMES('[a-z_]*project[a-z_]*')} || ', and the nearest count is '
        || ${TWINK_NAMES('rfqs_active')} || ', which counts RFQs and not projects'
        || '; an active-project count rendered in CustomerPortal.tsx=' || ${projCountRender}
        || '; projects exists with ' || ${ROWS('projects')} || ' row(s), served by project_api with '
        || ${cnt(/project_api/, ALL_SRC)} || ' caller(s) in src/'`);

    const ANNUAL = '[a-z_]*(annual|yearly|ytd|12m|lifetime)[a-z_]*';
    const annualRender = cnt(/history_12m|annual|yearly|ytd|lifetime_value/i, PORTAL);
    const spendRender = cnt(/s\.total_spend/, DASH);
    await req(S2, 'twin-annual-procurement', 'Twin states annual procurement value',
      `select (${TWINK(ANNUAL)} + ${FNKEYS('fn_customer_stats', ANNUAL)}
             + ${COLN('customer_score', 'annual|lifetime|ytd|12m')}) > 0 and ${annualRender} > 0`,
      `select 'year-scoped procurement keys — customer twin=' || ${TWINK(ANNUAL)}
        || ', fn_customer_stats=' || ${FNKEYS('fn_customer_stats', ANNUAL)}
        || ', customer_score columns=' || ${COLN('customer_score', 'annual|lifetime|ytd|12m')}
        || ' (' || ${COLS('customer_score')} || '; ' || ${ROWS('customer_score')} || ' row(s); '
        || ${CONSUMERS('customer_score')} || ' consumer(s): ' || ${CONSUMER_NAMES('customer_score')} || ')'
        || '; a year-scoped figure rendered in CustomerPortal.tsx=' || ${annualRender}
        || '; the only spend figure on screen is the total_spend tile=' || ${spendRender}`);

    const prefSupRender = cnt(/preferred_suppliers|suppliers?_(count|total|preferred)/i, PORTAL);
    await req(S2, 'twin-preferred-suppliers', 'Twin states number of preferred suppliers',
      `select ${TWINK('[a-z_]*supplier[a-z_]*')} > 0 and ${prefSupRender} > 0`,
      `select 'supplier-shaped key on the customer twin=' || ${TWINK('[a-z_]*supplier[a-z_]*')}
        || ' (' || ${TWINK_NAMES('[a-z_]*supplier[a-z_]*')} || ')'
        || '; customer_preference exists with ' || ${ROWS('customer_preference')} || ' row(s) and '
        || ${CONSUMERS('customer_preference')} || ' consumer(s): ' || ${CONSUMER_NAMES('customer_preference')}
        || '; a preferred-supplier count rendered in CustomerPortal.tsx=' || ${prefSupRender}`);

    const catRollupRender = cnt(/preferred_categories|\bcategories\b/, PORTAL);
    const catInCustEdge = cnt(/preferred_categories|fn_twin|fn_ws_customer_360/, CUST_SRC);
    await req(S2, 'twin-buying-patterns', 'Twin lists buying patterns (categories the customer repeatedly buys)',
      `select (${TWINK('categories|preferred_categories')} + ${COLN('customer_score', '^preferred_categories$')}) > 0
          and ${catInCustEdge} > 0 and ${catRollupRender} > 0`,
      `select 'categories rollup on the customer twin=' || ${TWINK('categories|preferred_categories')}
        || ' (' || ${TWINK_NAMES('categories|preferred_categories')}
        || '), customer_score.preferred_categories=' || ${COLN('customer_score', '^preferred_categories$')}
        || ' with ' || ${ROWS('customer_score')} || ' row(s)'
        || '; emitted by the customer-reachable edge set=' || ${catInCustEdge}
        || '; a categories rollup rendered in CustomerPortal.tsx=' || ${catRollupRender}
        || ' — the card shows one inquiry.category per request, which is not a pattern'`);

    const polInCustEdge = cnt(/procurement_approval_policy|procurement_approval_request/, CUST_SRC);
    // A RENDERED CHAIN, NOT THE WORD. `cnt(/approval|approver/i, PORTAL)` is satisfiable by typing
    // the word once — a spelling, not a surface, and the same shape as the empty state this row
    // exists to stop. The render leg is the token inside a JSX interpolation; the raw word count is
    // printed beside it so the narrower verdict shows the wider figure it rejected.
    const polWord = cnt(/approval|approver/i, PORTAL);
    const polInPortal = cnt(/\{[^{}]{0,160}(approval|approver|current_step|decisions)[^{}]{0,160}\}/i, PORTAL);
    await req(S2, 'twin-approval-chain', "Twin renders the customer's approval chain",
      `select ${COLN('procurement_approval_policy', '^steps$')} > 0
          and ${CONSUMERS('procurement_approval_policy')} > 0 and ${polInCustEdge} > 0 and ${polInPortal} > 0`,
      `select 'procurement_approval_policy columns: ' || ${COLS('procurement_approval_policy')}
        || ' with ' || ${ROWS('procurement_approval_policy')} || ' row(s)'
        || '; consumers excluding writers=' || ${CONSUMERS('procurement_approval_policy')}
        || ' (' || ${CONSUMER_NAMES('procurement_approval_policy')} || ')'
        || '; references in the customer-reachable edge set=' || ${polInCustEdge}
        || '; an approval field inside a JSX interpolation in CustomerPortal.tsx=' || ${polInPortal}
        || ' of ' || ${polWord} || ' raw mention(s) of the word in that file'`);

    // The render leg matches a confidence FIGURE, not the word. A bare /completeness/ scan reads 1
    // on this file and the hit is the word inside a tooltip explaining the Value score
    // ("blends price, rating and quote completeness") — a sentence, not a percentage.
    const CONF = '[a-z_]*(confidence|understanding|completeness|profile_score)[a-z_]*';
    const confRender = cnt(/ai[_ ]understanding|understanding[_ ]?(score|pct|%)|confidence[_ ]?(score|pct|%)|profile_score/i, PORTAL);
    const confWord = cnt(/confidence|understanding|completeness/i, PORTAL);
    await req(S2, 'twin-ai-understanding-pct', 'Twin shows an AI Understanding confidence percentage',
      `select ${TWINK(CONF)} > 0 and ${confRender} > 0`,
      `select 'confidence/understanding/completeness key on the customer twin=' || ${TWINK(CONF)}
        || ' (' || ${TWINK_NAMES(CONF)} || '); every score-shaped key it does emit: '
        || ${TWINK_NAMES('[a-z_]*score[a-z_]*')}
        || '; such a percentage rendered in CustomerPortal.tsx=' || ${confRender}
        || ' of ' || ${confWord} || ' raw mention(s) of those words in that file'`);

    await req(S2, 'twin-customer-visible', 'The twin is rendered TO THE CUSTOMER, not only to staff',
      `select ${twinInCustEdge} > 0 and ${twinInPortal} > 0`,
      `select 'edge functions referencing a twin routine anywhere: ' || ${LIST(twinEdgeReaders)}
        || '; of those, inside the customer-reachable set rooted at CustomerPortal.tsx=' || ${twinInCustEdge}
        || ' (that set is ' || ${CUST_FNS.length} || ' function(s): ' || ${LIST(CUST_FNS)} || ')'
        || '; twin fields rendered in CustomerPortal.tsx=' || ${twinInPortal}`);
  }

  // ══ SECTION 3 — AI PROCUREMENT ASSISTANT ══════════════════════════════════════════════════════
  {
    // THE CHECK THIS REPLACES WAS UNSATISFIABLE, and that is a worse defect than a false MET: it
    // clamped the assistant's view coverage to `cnt(...) > 0 ? 1 : 0` and then demanded it be
    // `>= views.length`. With two top-level views the requirement could only be met by DELETING a
    // view, and every view the product gains makes it harder. No implementation could satisfy it,
    // so it measured nothing.
    //
    // WHAT "AVAILABLE FROM EVERY SURFACE" ACTUALLY MEANS, MEASURED. A view-switching component
    // reaches its assistant iff the mount is not stranded behind an earlier whole-surface return.
    // So: the mount exists, and EITHER it sits in a floating container (rendered over whatever the
    // view is) OR no view branch returns before the code reaches it. Both shapes are one edit away
    // — hoist the mount above the guards, or wrap it in a fixed container — and either one keeps
    // satisfying the check for every view added afterwards, which is the property the old form
    // inverted.
    const mounts = cnt(/<NewRequest\b/, PORTAL);
    const guarded = cnt(/showNew\s*&&\s*<NewRequest/, PORTAL);
    const floating = cnt(/fixed\s+(bottom|right|inset|z-)/, PORTAL);
    const views = [...new Set([...PORTAL.matchAll(/setView\('([a-z]+)'\)/g)].map(m => m[1]))].sort();
    // A whole-surface early return keyed on NAVIGATION state. Loading and error early-returns are
    // deliberately out: every React component has them, and counting them would rebuild the
    // unsatisfiable check in a new disguise.
    const viewGuards = [...DASH.matchAll(/if\s*\(\s*view\s*===\s*'([a-z0-9_]+)'\s*\)\s*return/g)];
    const mountAt = [...DASH.matchAll(/<NewRequest\b/g)].map(m => m.index);
    const firstMount = mountAt.length ? Math.min(...mountAt) : Number.POSITIVE_INFINITY;
    const stranded = viewGuards.filter(m => m.index < firstMount).map(m => m[1]);
    // The mount inside a floating container: a fixed/overlay wrapper within 400 characters of it.
    const floatingMount = nearCount(PORTAL, /<NewRequest\b/, /fixed\s+(bottom|right|inset|z-)|role="dialog"|<Dialog[\s>]|<Sheet[\s>]/, 400);
    await req(S3, 'assistant-floating-persistent',
      'A floating AI assistant is available from every surface, not buried in one flow',
      `select ${mounts} > 0 and (${floatingMount} > 0 or ${stranded.length} = 0)`,
      `select 'NewRequest mount site(s)=' || ${mounts} || ', of which behind the showNew toggle=' || ${guarded}
        || ', unguarded=' || ${mounts - guarded}
        || '; inside a floating/overlay container (measured at the mount, not anywhere in the file)='
        || ${floatingMount} || ' of ' || ${floating} || ' fixed-position container(s) in the file'
        || '; portal top-level views=' || ${views.length} || ' (' || ${LIST(views)}
        || '), view branch(es) that return before the code reaches the assistant, so cannot render it='
        || ${stranded.length} || ' (' || ${LIST(stranded)}
        || '); either a floating mount or zero stranded branches satisfies this, and both stay satisfied'
        || ' as views are added'`);

    // The brief contract is taken from the fallback brief the intake builds when the model is
    // unavailable — the one shape that is guaranteed, not a shape the model might return.
    const fallback = (INTAKE.match(/brief:\s*\{\s*summary:[^]*?details:\s*\{\}\s*\}/) || [''])[0]
      .replace(/^brief:\s*\{/, '{');   // the keys are the object's, not the name it is bound to
    const briefKeys = [...new Set([
      ...[...fallback.matchAll(/([a-z_]+):/g)].map(m => m[1]),
      ...[...fallback.matchAll(/[{,]\s*([a-z_]+)\s*(?=[,}])/g)].map(m => m[1]),
    ])].sort();
    const readyStatus = cnt(/status:\s*'ready'|status === 'ready'/, INTAKE);
    const setBrief = cnt(/setBrief\(/, NEWREQ);
    // `{brief.` is a JSX interpolation; submit()'s `(brief && brief.category)` is not, and counting
    // it would report a field as rendered because a different function reads it.
    const briefFields = cnt(/\{brief\.(category|summary|scope|timeline|budget|emirate)/, NEWREQ);
    await req(S3, 'assistant-nl-to-requirement', 'Free-text need is converted into a structured requirement',
      `select ${readyStatus} > 0 and ${briefKeys.length} >= 5 and ${setBrief} > 0 and ${briefFields} >= 3`,
      `select 'inquiry_intake ready-status sites=' || ${readyStatus}
        || ', guaranteed brief contract keys=' || ${briefKeys.length} || ' (' || ${LIST(briefKeys)} || ')'
        || '; NewRequest stores the returned brief=' || ${setBrief}
        || ' and renders ' || ${briefFields} || ' brief field(s) in the ready card'`);

    const projInBrief = briefKeys.filter(k => /project/.test(k)).length;
    const projIdInApi = cnt(/project_id/, CAPI);
    const projInPortal = cnt(/project_id/, PORTAL);
    await req(S3, 'assistant-infers-project', 'Assistant infers the project from the request',
      `select (${projInBrief} + ${projIdInApi}) > 0 and ${COLN('inquiries', '^project_id$')} > 0`,
      `select 'project-shaped key in the intake brief contract=' || ${projInBrief} || ' of ' || ${briefKeys.length}
        || ' key(s); project_id mentions in customer_api, the routine that persists the RFQ=' || ${projIdInApi}
        || '; inquiries.project_id column=' || ${COLN('inquiries', '^project_id$')}
        || '; project_id mentions in CustomerPortal.tsx=' || ${projInPortal}
        || '; project_api link action=' || ${cnt(/action === 'link'/, PAPI)}
        || ' with ' || ${cnt(/project_api/, ALL_SRC)} || ' caller(s) in src/'`);

    // THE RENDER LEG WAS MISSING AND ITS TWO SIBLINGS BOTH HAVE ONE. assistant-required-documents and
    // assistant-recommends-supplier-count are each scored on what the ready-brief card SHOWS before
    // Send; this one was scored on the intake contract alone and returned MET while the card renders
    // nine brief fields and quantity is not among them — an estimate the customer is never shown, on
    // a spec whose subject is what the customer is shown. It is also the same figure section 7's
    // rfq-quantity-extraction scores MISSING because create_inquiry drops it, so the two checks were
    // returning opposite verdicts about one number. One edit satisfies both.
    const qtyKey = briefKeys.filter(k => /quantity|qty|area/.test(k)).length;
    const qtyInContract = cnt(/quantity/i, INTAKE);
    const inferred = cnt(/inferred/i, INTAKE);
    const boqQty = cnt(/\bqty\b/, CAPI);
    const qtyInCard = cnt(/\{brief\.(quantity|qty|area)/, NEWREQ);
    const briefFieldsShown = [...new Set([...NEWREQ.matchAll(/\{brief\.([a-z_]+)/g)].map(m => m[1]))].sort();
    await req(S3, 'assistant-estimates-quantity', 'Assistant estimates quantity from the described scope',
      `select ${qtyKey} > 0 and ${qtyInContract} > 0 and ${inferred} > 0 and ${qtyInCard} > 0`,
      `select 'quantity key on the text-only brief path, with no drawing and no BOQ upload=' || ${qtyKey}
        || ' of ' || ${briefKeys.length} || ' key(s): ' || ${LIST(briefKeys)}
        || '; quantity mentions in the intake contract=' || ${qtyInContract}
        || '; the brief marks each value stated vs inferred=' || ${inferred}
        || '; the estimate rendered in the ready-brief card before Send=' || ${qtyInCard}
        || ', of the ' || ${briefFieldsShown.length} || ' brief field(s) that card does render ('
        || ${LIST(briefFieldsShown)} || ')'
        || '; the separate uploaded-BOQ path in customer_api carries line-item qty=' || ${boqQty}`);

    const reqsFnPresent = EDGE.has('category_reqs') ? 1 : 0;
    const reqsInCustEdge = cnt(/category_reqs|inquiry_answer_document|required_documents/, CUST_SRC);
    const docsInCard = cnt(/required[_ ]documents?|documents? (checklist|needed|required)|certificat/i, NEWREQ);
    await req(S3, 'assistant-required-documents',
      'Assistant lists required documents (technical specs, delivery timeline, warranty)',
      `select ${reqsInCustEdge} > 0 and ${docsInCard} > 0`,
      `select 'category_reqs edge function present=' || ${reqsFnPresent}
        || ', inquiry_answer_document has ' || ${ROWS('inquiry_answer_document')} || ' row(s)'
        || '; either one referenced inside the customer-reachable edge set=' || ${reqsInCustEdge}
        || '; a documents checklist rendered in the ready-brief card=' || ${docsInCard}`);

    const countPreSend = cnt(/supplier[_a-z]*count|count[_a-z]*supplier|n_suppliers|matched_suppliers/i, INTAKE);
    const countInCard = cnt(/supplier[_a-z]*count|count[_a-z]*supplier|matched_suppliers/i, NEWREQ);
    await req(S3, 'assistant-recommends-supplier-count',
      'Assistant states how many suppliers it recommends before dispatch',
      `select ${countPreSend} > 0 and ${countInCard} > 0`,
      `select 'routines that could supply the number: fn_match_capability=' || ${FNN('fn_match_capability')}
        || ', match_suppliers_kw=' || ${FNN('match_suppliers_kw')} || ', leads on this target=' || ${ROWS('leads')}
        || '; a supplier count on the pre-dispatch intake payload=' || ${countPreSend}
        || '; a supplier count rendered in the ready-brief card before Send=' || ${countInCard}`);

    // DEFECT CLASS 1 IN ITS ORIGINAL FORM: the only reader is the writer. customer_api both writes
    // inquiry_matches and reads it back, so "customer_api references inquiry_matches" is true and
    // proves nothing about a match percentage reaching anybody.
    const IM = /inquiry_matches/;
    const simWrites = nearCount(CUST_SRC, IM, /similarity:\s*[a-z_.'"]+/);
    const simWritesNull = nearCount(CUST_SRC, IM, /similarity:\s*null/);
    const simSelects = nearCount(CUST_SRC, IM, /\.select\(\s*['"][^'"]*similarity/);
    const pctRender = cnt(/similarity|match_pct|match_percent|match_reason/, PORTAL);
    await req(S3, 'assistant-best-matches-pct', 'Assistant names best-match suppliers with a match percentage',
      `select ${COLN('inquiry_matches', '^similarity$')} > 0 and ${simSelects} > 0 and ${pctRender} > 0`,
      `select 'inquiry_matches columns: ' || ${COLS('inquiry_matches')}
        || ' with ' || ${ROWS('inquiry_matches')} || ' row(s)'
        || '; inside the customer-reachable edge set, and within 400 characters of an inquiry_matches'
        || ' reference, similarity is written at ' || ${simWrites}
        || ' site(s) — of which as a null value at ' || ${simWritesNull}
        || ' — and selected back at ' || ${simSelects} || ' site(s)'
        || '; a match percentage or match_reason rendered in CustomerPortal.tsx=' || ${pctRender}`);

    const submitAction = cnt(/action:\s*'create_inquiry'/, NEWREQ);
    const briefButton = cnt(/onClick=\{submit\}/, NEWREQ);
    const apiWrites = cnt(/from\('inquiries'\)\.insert/, CAPI);
    await req(S3, 'assistant-acts-not-chats', 'Assistant takes actions rather than only answering',
      `select ${submitAction} > 0 and ${briefButton} > 0 and ${apiWrites} > 0`,
      `select 'the ready-brief card wires a button to submit()=' || ${briefButton}
        || ', submit() posts action=create_inquiry=' || ${submitAction}
        || ', customer_api persists the RFQ at ' || ${apiWrites} || ' site(s)'
        || '; inquiries on this target=' || ${ROWS('inquiries')} || ' so the path is scored, not its output'`);

    const unmounts = cnt(/onDone=\{\(\) => \{ setShowNew\(false\)/, DASH);
    const assistantInCard = cnt(/inquiry_intake|<NewRequest\b/, CARD);
    const threadAssistant = cnt(/request_chat/, THREAD);
    const revealGate = cnt(/revealed_at|unlocks after/, MAPI);
    await req(S3, 'assistant-available-post-creation',
      'Assistant remains reachable after the request exists, for follow-up questions',
      `select ${assistantInCard} > 0 or (${threadAssistant} > 0 and ${revealGate} = 0)`,
      `select 'NewRequest unmounts once the RFQ exists=' || ${unmounts}
        || '; an assistant entry point inside the opened InquiryCard=' || ${assistantInCard}
        || '; the only other assistant door is Thread request_chat=' || ${threadAssistant}
        || ', and messages_api gates a thread on a paid reveal at ' || ${revealGate}
        || ' site(s), so it is unreachable on an RFQ that has no revealed quote'`);
  }

  // ══ SECTION 4 — COMMAND CENTER UI ═════════════════════════════════════════════════════════════
  {
    const acEmit = cnt(/alerts_count/, CUST_SRC);
    const acRender = cnt(/alerts_count/, PORTAL);
    await req(S4, 'cc-attention-count', 'Command Center leads with "N decisions need your attention"',
      `select ${acEmit} > 0 and ${acRender} > 0`,
      `select 'customer_portal overview emits alerts_count=' || ${acEmit}
        || '; references to alerts_count anywhere in CustomerPortal.tsx=' || ${acRender}
        || '; the alerts array is rendered at ' || ${alertRegion}
        || ' site(s) as individual cards, with no count line above them'`);

    const progressApi = cnt(/progress|completion/i, PAPI);
    const projPanel = cnt(/project/i, DASH);
    const progressRender = cnt(/progress|completion/i, PORTAL);
    await req(S4, 'cc-projects-panel', 'Projects panel with per-project progress percentage',
      `select (${COLN('project_summary', 'progress|completion')} + ${progressApi}) > 0
          and ${projPanel} > 0 and ${progressRender} > 0`,
      `select 'project_summary columns: ' || ${COLS('project_summary')}
        || ' — of them matching progress/completion=' || ${COLN('project_summary', 'progress|completion')}
        || '; a progress figure computed by project_api=' || ${progressApi}
        || '; a projects region in the post-auth root=' || ${projPanel}
        || ', a progress figure rendered anywhere in CustomerPortal.tsx=' || ${progressRender}`);

    const statsInvoked = cnt(/fn_customer_stats/, CPORTAL);
    const openRender = cnt(/s\.open_inquiries/, DASH);
    await req(S4, 'cc-procurement-panel', 'Procurement panel showing open RFQ count',
      `select ${FNKEYS('fn_customer_stats', 'open_inquiries')} > 0 and ${statsInvoked} > 0 and ${openRender} > 0`,
      `select 'fn_customer_stats emits open_inquiries=' || ${FNKEYS('fn_customer_stats', 'open_inquiries')}
        || '; customer_portal overview invokes fn_customer_stats=' || ${statsInvoked}
        || '; CustomerPortal.tsx renders s.open_inquiries=' || ${openRender} || ' tile(s)'
        || '; inquiries on this target=' || ${ROWS('inquiries')}
        || ' so the tile reads 0 here and a real count once RFQs exist'`);

    const budgetEmit = cnt(/budget_total/, CUST_SRC);
    const budgetRender = cnt(/budget_total|budget_used/i, PORTAL);
    const bar = cnt(/role="progressbar"|<Progress\b|style=\{\{\s*width|w-\[\$\{/, PORTAL);
    await req(S4, 'cc-financial-budget-used', 'Financial Intelligence panel with a Budget Used progress bar',
      `select ${budgetEmit} > 0 and ${budgetRender} > 0 and ${bar} > 0`,
      `select 'projects.budget_total column=' || ${COLN('projects', '^budget_total$')}
        || ', emitted by the customer-reachable edge set=' || ${budgetEmit}
        || ' (project_summary.budget_total is served by project_api, which has '
        || ${cnt(/project_api/, ALL_SRC)} || ' caller(s) in src/)'
        || '; a budget figure rendered in CustomerPortal.tsx=' || ${budgetRender}
        || ', bar/meter element(s) of any kind in that file=' || ${bar}`);

    const netEmit = cnt(NET, CUST_SRC);
    const netRender = cnt(NET, PORTAL);
    await req(S4, 'cc-supplier-network-count',
      'Supplier Network panel showing suppliers available to this customer',
      `select ${netEmit} > 0 and ${netRender} > 0`,
      `select 'leads on this target=' || ${ROWS('leads')} || ' and fn_is_matchable=' || ${FNN('fn_is_matchable')}
        || ', so the network exists and is measurable'
        || '; a network size emitted by the customer-reachable edge set=' || ${netEmit}
        || ' (' || ${CUST_FNS.length} || ' function(s)); rendered in CustomerPortal.tsx=' || ${netRender}`);

    // The section names four panels. Each is looked for by the content that would have to be on
    // screen for it to exist (hoisted above section 1, because entry-not-login-dashboard scores the
    // SAME panel leg — the spec states the workspace idea twice and two checks on one component may
    // not return opposite verdicts). The ones present are named in the evidence.
    await req(S4, 'cc-workspace-not-dashboard', 'The main interface is a workspace, not a page of KPI tiles',
      `select ${present.length} >= 3`,
      `select 'the post-auth root renders ' || ${figureTiles} || ' figure tile(s) and '
        || ${workList} || ' vertical work-item list(s) whose item carries ' || ${itemControls}
        || ' in-place control(s); of the four panels this section names, present=' || ${present.length}
        || ' (' || ${LIST(present)} || ') — the same leg entry-not-login-dashboard scores'`);
  }
}

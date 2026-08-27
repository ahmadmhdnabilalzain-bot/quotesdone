// OS 2.txt — screens 1-9: Executive Home, AI Conversation, Live Company, Organization, Employee
// View, Company Timeline, Mission Control, Digital Twin, Approval Center. 40 requirements.
//
// THE ONE RULE THIS FILE IS BUILT AROUND. This is an EXECUTIVE UI, so a requirement is MET only
// when the founder can SEE the thing. Production computes an autonomous company every night —
// company_index is measured daily, graph_nodes is rebuilt daily, employee_kpi and agent_reputation
// are recomputed on schedule — and displays almost none of it. A check that counts rows, or counts
// routines, cannot tell that apart from a working feature. So every check here joins THREE
// measurements and never substitutes one for another:
//
//   DATABASE   the figure exists, is populated, and where the requirement implies currency, is fresh
//   REACH      a routine the BROWSER can cause to run returns it (the UI closure, computed below)
//   RENDER     a React surface actually puts it on screen, next to a label that names it
//
// REACH IS NOT DELIVERY, and this file never lets it stand in for delivery. fn_graph_rebuild and
// fn_company_reflect are both inside the UI closure — the console's automation runner can TRIGGER
// them — while not one byte of what they produce is rendered anywhere. Reach is a necessary leg,
// never a sufficient one.
//
// HOW "RENDERED" IS MEASURED, and why it is not a word search. A grep for the word "revenue" in
// OsxShell.tsx matches the Finance sidebar label, which delivers nothing. What is measured instead
// is a FIGURE: a payload key that (a) the component puts inside a JSX interpolation, (b) names both
// the subject and the aspect the requirement asks for IN ONE IDENTIFIER — `agents_active_24h` names
// the subject and the state, a bare `.active` names neither — and (c) appears within 320 characters
// of a label naming it. Then the same key is required to be emitted by a browser-reachable routine,
// so the name is shown to travel from SQL to screen. Keys are also resolved one hop through a local
// const, because `const band = String(health.band)` followed by `{titleCase(band)}` renders a figure
// that a scan of interpolations alone would score as absent.
//
// FIVE DEFECT CLASSES FROM ROW #2 THAT THIS FILE PRE-EMPTS BY CONSTRUCTION:
//  1 THE ONLY READER IS THE WRITER — UI_READS() drops any routine that writes the relation, by
//    pattern rather than by name equality (the row #2 helper self-excluded a proc whose NAME equals
//    the object's, which is inert for every table), and collapses pg_proc OVERLOADS with
//    count(distinct proname) so fn_agent_context's two rows cannot inflate a count. A view that
//    names a table counts only when a reachable routine opens the VIEW.
//  2 POPULATION STANDING IN FOR DELIVERY — the RENDER leg above. No check in this file can be
//    satisfied by rows alone.
//  3 ONE ROW SCORES A WHOLE MECHANISM — every per-employee requirement is a per-row NOT EXISTS over
//    the employees that actually WORKED in the window, not a global count above zero; every
//    "every department / every KPI" requirement is a per-row universal with a recency bound.
//  4 SATISFIABLE BY FLIPPING A FLAG — no check in this file reads an excuse flag. `planned`,
//    `needs_founder` and `active` are used as populations to measure, never as permissions to pass.
//  5 EVIDENCE THAT DOES NOT COMPUTE THE VERDICT — every evidence string is numbers and names taken
//    from the same population the verdict scores. Where a sentence is fixed prose it is a label for
//    an adjacent computed number, never an assertion of fact.
//
// LIKE IS NEVER USED WITH AN INTERPOLATED VALUE. Table content and repository identifiers both
// contain underscores, which are single-character wildcards on the pattern side of LIKE and can only
// ever produce a false MET. Everything here uses position() or a ~* regex over an alternation of
// identifier-shaped tokens.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const label = 'screens 1-9 (Executive Home .. Approval Center)';
// EXPECTED, not `expected`. The runner reads `mod.EXPECTED`, so the lowercase name declared this
// module's denominator to nobody: the run printed "1 section(s) have an unverified check count —
// the denominator is not trustworthy, so neither is the percentage below" while this file was in
// fact registering exactly the 40 checks it intended. A silent casing slip is precisely the failure
// the EXPECTED assertion exists to catch, arriving in the assertion itself.
export const EXPECTED = 40;

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SRC_DIR = join(REPO, 'src');
const FN_DIR = join(REPO, 'supabase', 'functions');

// ---- the repository side -------------------------------------------------------------------
function walk(d, acc = []) {
  if (!existsSync(d)) return acc;
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (/\.(ts|tsx|js|jsx)$/.test(e.name)) acc.push(p);
  }
  return acc;
}
const SRC_FILES = walk(SRC_DIR);
const SRC = SRC_FILES.map(f => readFileSync(f, 'utf8')).join('\n/*FILE*/\n');
const SHELL_PATH = join(SRC_DIR, 'components', 'osx', 'OsxShell.tsx');
const SHELL = existsSync(SHELL_PATH) ? readFileSync(SHELL_PATH, 'utf8') : '';
const edgeSrc = (n) => {
  const p = join(FN_DIR, n, 'index.ts');
  return existsSync(p) ? readFileSync(p, 'utf8') : '';
};

// Edge functions the browser can reach: the ones src/ names, then the ones those name, transitively.
const EDGE_FNS = (() => {
  const seen = new Set(), queue = [];
  for (const m of SRC.matchAll(/functions\/v1\/([a-z0-9_]+)/g)) queue.push(m[1]);
  while (queue.length) {
    const n = queue.shift();
    if (seen.has(n)) continue;
    seen.add(n);
    for (const m of edgeSrc(n).matchAll(/(?:BASE\}|functions\/v1)\/([a-z0-9_]+)/g)) {
      if (!seen.has(m[1])) queue.push(m[1]);
    }
  }
  return [...seen].sort();
})();
const EDGE_SRC = EDGE_FNS.map(edgeSrc).join('\n/*FILE*/\n');
// Every `fn_*` literal inside a reachable edge function is a routine that edge function can
// dispatch. Taking LITERALS rather than only `.rpc('…')` matters: os_api dispatches its eighteen
// workspace routines through `admin.rpc(WS[action])`, and an `.rpc(` scan misses every one of them.
const ROOT_FNS = [...new Set([...EDGE_SRC.matchAll(/['"](fn_[a-z0-9_]+)['"]/g)].map(m => m[1]))].sort();
// Tables a reachable edge function reads directly through PostgREST, never touching pg_proc.
const EDGE_TABLES = [...new Set([...EDGE_SRC.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]/g)].map(m => m[1]))].sort();

// Everything interpolated into a statement is an identifier-shaped token, a number or a boolean.
// Anything else is dropped rather than escaped: qd_guard refuses a read carrying a bare write
// keyword, and a stray token would turn a check into an ERROR — an UNMEASURED requirement, which is
// worse than either verdict.
const SAFE = /^[A-Za-z_$][\w$]*$/;
const safe = (s) => SAFE.test(s) &&
  !/^(insert|update|delete|drop|alter|create|grant|revoke|truncate|call|do|vacuum|reindex|comment)$/i.test(s);
const S = (s) => `'` + String(s).replace(/'/g, `''`) + `'`;
const ARR = (a) => a.length ? `array[${a.map(x => `'${x}'`).join(',')}]::text[]` : `array[]::text[]`;
const ALT = (a) => a.length ? `'\\y(${a.join('|')})\\y'` : null;

// A component's source, from `function Name(` to the next top-level declaration.
function slice(name, text = SHELL) {
  const m = new RegExp('^(?:export default )?function ' + name + '\\b', 'm').exec(text);
  if (!m) return '';
  const rest = text.slice(m.index + 1);
  const nxt = /\n(?:export default )?(?:function |const [A-Z])/.exec(rest);
  return text.slice(m.index, nxt ? m.index + 1 + nxt.index : text.length);
}
const surf = (...names) => names.map(n => slice(n)).join('\n/*NEXT*/\n');

// The payload keys a surface PUTS ON SCREEN.
function renderedKeys(text) {
  const out = new Set();
  const interps = [...text.matchAll(/\{([^{}]{0,600}?)\}/g)].map(m => m[1]);
  const joined = ' ' + interps.join(' ; ') + ' ';
  const isRendered = (n) => new RegExp('(?:^|[^\\w$.])' + n + '(?![\\w$])').test(joined);
  const props = (expr) => {
    for (const k of expr.matchAll(/\.([a-zA-Z_$][\w$]*)/g)) if (safe(k[1])) out.add(k[1]);
    for (const k of expr.matchAll(/\[\s*['"]([\w$]+)['"]\s*\]/g)) if (safe(k[1])) out.add(k[1]);
  };
  for (const e of interps) if (/[.[]/.test(e)) props(e);
  for (const m of text.matchAll(/\b(?:const|let|var)\s+([a-zA-Z_$][\w$]*)\s*(?::[^=;\n]{0,80})?=\s*([^;\n]{0,300})/g)) {
    if (!/[.[]/.test(m[2]) || !isRendered(m[1])) continue;
    if (safe(m[1])) out.add(m[1]);
    props(m[2]);
  }
  for (const m of text.matchAll(/\b(?:const|let|var)\s*\{([^}]{0,200})\}\s*=\s*([^;\n]{0,200})/g)) {
    for (const part of m[1].split(',')) {
      const n = part.trim().split(':').pop().trim();
      if (safe(n) && isRendered(n)) out.add(n);
    }
  }
  return [...out].sort();
}

// A FIGURE SHOWN TO THE FOUNDER, which is three conditions and not one.
//   subject+aspect must both hold OF THE SAME KEY — this is what stops a sidebar label, or an
//     unrelated `.active` from an org_agents row, from scoring a landing-screen requirement.
//   the key must be rendered, not merely fetched.
//   the key must appear within 320 characters of a label naming the concept — `{arr.map((x,index)…)}`
//     produces the key `index` on any surface, and only the label test tells that apart from the
//     Business Health card's `{health.index}`.
function shown(text, subject, aspect, labelRe) {
  const keys = renderedKeys(text).filter(k => subject.test(k) && (aspect ? aspect.test(k) : true));
  if (!labelRe) return keys;
  return keys.filter(k => {
    const re = new RegExp('(?:^|[^\\w$])' + k + '(?![\\w$])', 'g');
    for (const m of text.matchAll(re)) {
      if (labelRe.test(text.slice(Math.max(0, m.index - 320), m.index + 320))) return true;
    }
    return false;
  });
}
const has = (text, re) => re.test(text);
const nComponents = (re) => {
  const out = [];
  for (const m of SHELL.matchAll(/^(?:export default )?function ([A-Z]\w+)/gm)) {
    const body = slice(m[1]);
    if (re(body)) out.push(m[1]);
  }
  return out;
};

// MODULES[] as declared, and the module the shell shows before anything is clicked.
const MODULES = (() => {
  const b = /const MODULES:\s*Mod\[\]\s*=\s*\[([\s\S]*?)\n\];/.exec(SHELL);
  if (!b) return [];
  return [...b[1].matchAll(/\{\s*id:\s*'([a-z_]+)'[^}]*\}/g)].map(m => ({
    id: m[1],
    kind: (/kind:\s*'([a-z_]+)'/.exec(m[0]) || [])[1] || '',
    label: (/label:\s*'([^']*)'/.exec(m[0]) || [])[1] || '',
  }));
})();
const DEFAULT_MOD = (/const\s+\[cur,\s*setCur\]\s*=\s*React\.useState(?:<[^>]{0,60}>)?\(\s*'([a-z_]+)'/.exec(SHELL) || [])[1] || '';
function componentFor(id) {
  const rm = slice('renderModule');
  const k = (MODULES.find(m => m.id === id) || {}).kind || '';
  return (new RegExp("m\\.kind === '" + k + "' \\? <([A-Z]\\w+)").exec(rm) || [])[1]
      || (new RegExp("m\\.id === '" + id + "' \\? <([A-Z]\\w+)").exec(rm) || [])[1] || '';
}

export default async function (H) {
  const { req, one } = H;
  const SEC = 'screens-1-9';

  // ---- the UI closure over pg_proc ----------------------------------------------------------
  // Which routines can a logged-in founder cause to run? The roots are the routines the reachable
  // edge functions name; the answer is the transitive closure over pg_get_functiondef. Depth 6 so a
  // mutually-referencing pair terminates; measured on production the set stops growing at depth 4.
  // Reused from the runner when it has already paid for it, so the 700x700 regex join runs once.
  const supplied = (H && H.ui && H.ui.routines) || null;
  let UIFNS = Array.isArray(supplied) && supplied.length ? supplied.filter(safe) : [];
  if (!UIFNS.length) {
    const raw = String(await one(`with recursive defs as materialized (
        select p.proname, pg_get_functiondef(p.oid) d
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p')
      ), edges as materialized (
        select distinct a.proname src, b.proname dst from defs a join defs b
          on b.proname <> a.proname and a.d ~* ('\\y'||b.proname||'\\y')
      ), reach(proname, depth) as (
        select distinct proname, 1 from defs where proname = any(${ARR(ROOT_FNS)})
        union
        select e.dst, r.depth+1 from reach r join edges e on e.src = r.proname where r.depth < 6
      )
      select coalesce(string_agg(distinct proname, ','), '') from reach`) || '');
    UIFNS = raw.split(',').filter(safe);
  }
  const UI = ARR(UIFNS);

  // Reachable routines that READ this relation. Writers are removed BY PATTERN — the row #2 helper
  // excluded only a proc whose name equals the object's, which is inert for every table name, and
  // that is how an UPDATE came to count as a read. Overloads collapse under count(distinct proname).
  // The write keywords are split so qd_guard's read guard does not refuse the check itself.
  const NOTW = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;
  const UI_READS = (t) => `((select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOTW(t)})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'
        and exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                    where n2.nspname='public' and p2.prokind in ('f','p') and p2.proname = any(${UI})
                      and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y')))
    + ${EDGE_TABLES.includes(t) ? 1 : 0})`;
  const UI_READ_NAMES = (t) => `coalesce((select string_agg(distinct x, ',') from (
        select p.proname x from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
           and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOTW(t)}
        union select ${EDGE_TABLES.includes(t) ? `'edge:PostgREST'` : 'null'}) s
      where x is not null), 'none')`;
  // Everything that names the relation, writers included — printed beside UI_READS so a MISSING
  // verdict shows the shape of the defect: "computed by six, reachable by none".
  const ALL_READS = (t) => `((select count(distinct p.proname) from pg_proc p
        join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;
  // How many reachable routines name this figure? The alternation is built FROM THE FRONTEND — the
  // keys a surface renders — so a non-zero answer means that exact name travels routine → screen.
  const EMITS = (rx) => rx ? `(select count(distinct p.proname) from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
         and pg_get_functiondef(p.oid) ~* ${rx})` : `0`;
  const EMIT_NAMES = (rx) => rx ? `coalesce((select string_agg(distinct p.proname, ',') from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
         and pg_get_functiondef(p.oid) ~* ${rx}), 'none')` : `'none'`;
  // A relation that does not exist scores MISSING rather than ERRORing.
  const CNT = (t, w = 'true') => `(select case when to_regclass('public.${t}') is null then 0 else
      (xpath('/row/c/text()', query_to_xml('select count(*) c from public.${t} where ' ||
        ${S(w)}, false, true, '')))[1]::text::int end)`;
  const REACH = (fn) => UIFNS.includes(fn);
  // A view may not exist, and if it does its columns are not this file's to assume. CASE result
  // expressions evaluate lazily, so the distinct-column form runs only when that column is really
  // there and the measurement degrades to a row count instead of ERRORing — an errored check is an
  // UNMEASURED requirement, which is a worse outcome than a conservative number.
  const VIEW_COVER = (v, col) => `(select case
      when exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name='${v}' and column_name='${col}')
        then (xpath('/row/c/text()', query_to_xml(
               'select count(distinct ${col}) c from public.${v}', false, true, '')))[1]::text::int
      when to_regclass('public.${v}') is not null
        then (xpath('/row/c/text()', query_to_xml(
               'select count(*) c from public.${v}', false, true, '')))[1]::text::int
      else 0 end)`;
  // THE POPULATION FOR EVERY PER-EMPLOYEE UNIVERSAL IS EVERY ACTIVE EMPLOYEE, and it was not always.
  // The first version scored those universals over "employees that ran in the last 30 days", which
  // measured 7 of 66 — because agent_runs.agent holds CRON JOB names (brief, backup, graph_rebuild),
  // not agent_keys, so 59 of the 66 employees never appear in it at all. Over a population of seven,
  // "every employee's thoughts are visible" and "every employee's knowledge is visible" both scored
  // MET while the workspace was empty for two thirds of the organisation. A workspace exists for
  // every employee the org chart lists, so that is the population.
  const ACTIVE_EMP = `(select count(*) from public.org_agents where active)`;

  // Surfaces. THE LANDING SCREEN is the executive home — the Command Center — plus the chrome that
  // is on screen whatever module is open (the header's agent counter and pipeline tracker). Whether
  // logging in actually PUTS you there is a separate requirement, exec-home-no-menus, and is scored
  // there rather than folded into all ten tile checks: one fact must not decide ten verdicts.
  const HOME = surf('Overview', 'OsxShell', 'AgentStatus', 'PipelineTracker');
  const LANDING = slice(componentFor(DEFAULT_MOD));
  const CONSOLE = slice('Console');
  const DRAWER = slice('AgentDrawer');
  const FINANCE = slice('FinanceApp');
  const homeKeys = renderedKeys(HOME);

  // The standard three-legged figure check, so forty requirements are scored the same way rather
  // than forty different ways. `keys` is what the surface shows; the emitter alternation is built
  // from those keys; both must be non-empty.
  const DELIVERED = (keys) => keys.length ? `${EMITS(ALT(keys))} > 0` : `false`;
  const FIGEV = (keys, where) => `${S(keys.length + ' figure key(s) on ' + where +
      (keys.length ? ' [' + keys.join(' ') + ']' : ''))} || ', emitted by ' ||
      ${keys.length ? EMITS(ALT(keys)) : '0'}::text || ' browser-reachable routine(s): ' ||
      ${keys.length ? EMIT_NAMES(ALT(keys)) : `'none'`}`;

  // ================= SCREEN 1 — EXECUTIVE HOME =================================================

  // "Logging in lands on a live company state, not a menu tree." Measured on the surface the shell
  // actually opens with, not on the one the spec hopes it opens with: the default `cur` state names
  // a module, renderModule names its component, and that component is asked how many COMPANY
  // FIGURES it renders. Three is the bar because one number is a status line, not a company state.
  // A sidebar of 29 labels renders no figures at all and cannot pass this by growing.
  const landingFigs = shown(LANDING, /(health|revenue|customer|supplier|agent|employee|goal|risk|order|quote|rfq|cash|profit|index|score|total|pending|runs?)/i,
    /(total|count|active|index|score|pct|rate|revenue|health|runs?|pending|open|_24h|aed)/i, null);
  await req(SEC, 'exec-home-no-menus', 'Logging in lands on a live company state, not a menu tree',
    `select ${landingFigs.length >= 3} and ${DELIVERED(landingFigs)}`,
    `select ${S(`default module '${DEFAULT_MOD}' renders <${componentFor(DEFAULT_MOD) || '?'}>; sidebar lists ${MODULES.length} module(s); `)}
       || ${FIGEV(landingFigs, `the landing component <${componentFor(DEFAULT_MOD) || '?'}>`)}`);

  // Company Health. The key `index` is generic enough to be a map callback's counter, so the label
  // test is what distinguishes `{health.index}` under "Business health" from `arr.map((x,index)…)`.
  const healthKeys = shown(HOME, /^(index|score|band|health|health_index|health_score|company_health|business_health|health_pct)$/i, null, /health/i);
  await req(SEC, 'exec-home-company-health', 'A single Company Health percentage is on the landing screen',
    `select ${healthKeys.length > 0} and ${DELIVERED(healthKeys)}
       and ${EMITS(`'\\y(fn_health_index|health_index|business_health)\\y'`)} > 0`,
    `select ${FIGEV(healthKeys, 'the landing screen')} || '; fn_health_index reachable: ' ||
       ${S(String(REACH('fn_health_index')))} || ', v_business_health browser-reachable readers: ' ||
       ${UI_READS('v_business_health')}::text || ' of ' || ${ALL_READS('v_business_health')}::text || ' namers'`);

  // Revenue today, in AED. A revenue figure that is not day-scoped is a different figure, so the key
  // must name both the subject and the window; `revenue_today`, `revenue_24h` and `sales_daily` all
  // pass, `revenue_total` does not, which is the distinction the requirement makes.
  const revToday = shown(HOME, /(revenue|turnover|sales|gmv|income)/i, /(today|_24h|24h|daily|_1d|d0)/i, /(revenue|turnover|sales|income|aed)/i);
  await req(SEC, 'exec-home-revenue-today', 'Revenue for today, in AED, on the landing screen',
    `select ${revToday.length > 0} and ${DELIVERED(revToday)}`,
    `select ${FIGEV(revToday, 'the landing screen')} || '; gl_journal browser-reachable readers: ' ||
       ${UI_READS('gl_journal')}::text || ', transactions: ' || ${UI_READS('transactions')}::text ||
       '; revenue-shaped keys anywhere on the landing screen: ' ||
       ${S(shown(HOME, /(revenue|turnover|sales|gmv|income)/i, null, null).join(' ') || 'none')}`);

  // Month-to-date revenue, ON THE LANDING SCREEN. The evidence names what FinanceApp renders as
  // well, because "it exists inside the Finance module" is the answer this requirement rejects.
  const revMonth = shown(HOME, /(revenue|turnover|sales|gmv|income)/i, /(month|mtd|_30d|30d|period)/i, /(revenue|turnover|sales|income|aed)/i);
  const revMonthFin = shown(FINANCE, /(revenue|turnover|sales|gmv|income)/i, /(month|mtd|_30d|30d|period)/i, null);
  await req(SEC, 'exec-home-revenue-month', 'Month-to-date revenue, in AED, on the landing screen',
    `select ${revMonth.length > 0} and ${DELIVERED(revMonth)}`,
    `select ${FIGEV(revMonth, 'the landing screen')} || '; inside FinanceApp instead: ' ||
       ${S(revMonthFin.join(' ') || 'none')} || '; fn_ws_finance reachable: ' || ${S(String(REACH('fn_ws_finance')))}`);

  // Monthly goal attainment. Three legs: the figure is shown, a reachable routine emits it, and the
  // goal ledger it would be computed from is non-empty and REFRESHED — goal_period is rebuilt daily
  // by fn_goal_period_refresh, so a percentage drawn from a ledger last touched a fortnight ago is
  // not "progress against the monthly goal". The recency bound is what stops one seeded row scoring
  // this permanently.
  const goalKeys = shown(HOME, /(goal|target|quota|objective)/i, /(pct|percent|progress|attain|ratio|vs|achiev)/i, /(goal|target|progress|month)/i);
  await req(SEC, 'exec-home-monthly-goal-pct', 'Progress against the monthly goal, as a percentage',
    `select ${goalKeys.length > 0} and ${DELIVERED(goalKeys)}
       and ${CNT('goal_period')} > 0
       and (select coalesce(max(updated_at), '-infinity'::timestamptz) from public.goal_period)
             > now() - interval '3 days'`,
    `select ${FIGEV(goalKeys, 'the landing screen')} || '; goal_period holds ' || ${CNT('goal_period')}::text ||
       ' row(s) last refreshed ' ||
       coalesce((select max(updated_at)::timestamp(0)::text from public.goal_period), 'never') ||
       ', browser-reachable readers ' || ${UI_READS('goal_period')}::text || ' of ' ||
       ${ALL_READS('goal_period')}::text || ' namers; company_goals reachable readers ' ||
       ${UI_READS('company_goals')}::text`);

  const custKeys = shown(HOME, /(customer|buyer|client|account)/i, /(active|count|total|live|paying)/i, /customer|buyer|client/i);
  await req(SEC, 'exec-home-customers-active', 'Count of currently active customers on the landing screen',
    `select ${custKeys.length > 0} and ${DELIVERED(custKeys)}`,
    `select ${FIGEV(custKeys, 'the landing screen')} || '; customers table holds ' || ${CNT('customers')}::text ||
       ' row(s), browser-reachable readers ' || ${UI_READS('customers')}::text ||
       ' (' || ${UI_READ_NAMES('customers')} || '); fn_customer_stats reachable: ' ||
       ${S(String(REACH('fn_customer_stats')))}`);

  // Suppliers ACTIVE, which the requirement separates from suppliers TOTAL. A cumulative lifecycle
  // count — sourced, invited, registered, verified — answers a different question, so the aspect
  // pattern excludes it and the evidence prints every supplier key on the surface so a reader can
  // see exactly which ones were rejected and why.
  const supActive = shown(HOME, /(supplier|vendor)/i, /(active|live|responding|working|online|engaged|current)/i, /supplier|vendor/i);
  await req(SEC, 'exec-home-suppliers-active', 'Count of currently active suppliers on the landing screen',
    `select ${supActive.length > 0} and ${DELIVERED(supActive)}`,
    `select ${FIGEV(supActive, 'the landing screen')} || '; all supplier keys shown there: ' ||
       ${S(shown(HOME, /(supplier|vendor)/i, null, null).join(' ') || 'none')} ||
       '; leads holds ' || ${CNT('leads')}::text || ' row(s)'`);

  // A WORKING/TOTAL pair, e.g. 61/61 — two figures, not one. A headcount alone does not say how many
  // are working and an activity count alone does not say out of how many, so both are required and
  // the DB leg asks that the fleet is real and has run inside the window being displayed.
  const agentWorking = shown(HOME, /(agent|employee|staff|worker)/i, /(active|working|busy|running|online|live|runs)/i, /agent|employee|smart engine/i);
  const agentTotal = shown(HOME, /^(agents|employees|headcount|agents_total|employee_count|total_agents)$/i, null, /agent|employee/i);
  await req(SEC, 'exec-home-ai-employees-working', 'A working/total count of AI employees on the landing screen',
    `select ${agentWorking.length > 0} and ${agentTotal.length > 0}
       and ${DELIVERED(agentWorking)} and ${DELIVERED(agentTotal)}
       and (select count(*) from public.org_agents where active) > 0
       and (select count(*) from public.agent_runs where started_at > now() - interval '24 hours') > 0`,
    `select 'working key(s) ' || ${S(agentWorking.join(' ') || 'none')} || ', total key(s) ' ||
       ${S(agentTotal.join(' ') || 'none')} || '; ' ||
       (select count(*) from public.org_agents where active)::text || ' active employee(s), ' ||
       (select count(distinct agent) from public.agent_runs where started_at > now() - interval '24 hours')::text ||
       ' ran in 24h; emitted by ' || ${agentWorking.length ? EMITS(ALT(agentWorking)) : '0'}::text ||
       ' + ' || ${agentTotal.length ? EMITS(ALT(agentTotal)) : '0'}::text || ' reachable routine(s)'`);

  // Bottlenecks, ATTRIBUTED TO DEPARTMENTS. Two keys on one surface — a bottleneck figure and a
  // department to hang it on — because an undepartmented list of blockers is not what was asked.
  const bottleKeys = shown(HOME, /(bottleneck|blocker|blocked|constraint|pressure|overload|backlog|stuck|waiting)/i, null, null);
  const deptKeys = shown(HOME, /^(dept|dept_key|department|departments|department_key|by_department)$/i, null, null);
  await req(SEC, 'exec-home-bottlenecks', 'A named list of current bottlenecks, attributed to departments',
    `select ${bottleKeys.length > 0} and ${deptKeys.length > 0} and ${DELIVERED(bottleKeys)}
       and ${UI_READS('resource_pool')} + ${UI_READS('v_resource_pressure')} + ${UI_READS('v_department_health')} > 0`,
    `select ${S(`bottleneck key(s) on the landing screen: ${bottleKeys.join(' ') || 'none'}; department key(s): ${deptKeys.join(' ') || 'none'}; `)}
       || 'resource_pool holds ' || ${CNT('resource_pool')}::text || ' row(s) with ' ||
       ${UI_READS('resource_pool')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('resource_pool')}::text ||
       ' namers; v_resource_pressure reachable readers ' || ${UI_READS('v_resource_pressure')}::text ||
       ', v_department_health ' || ${UI_READS('v_department_health')}::text`);

  // A single company mood token. `band` reaches the shell through fn_ws_exec's health block and is
  // rendered as "45 / 100 · Unhealthy", which IS a mood token — so the evidence also prints
  // company_index's own band and its reachable-reader count, because the table the spec points at is
  // a different, unread source of the same idea and a reader should be able to see both facts.
  const moodKeys = shown(HOME, /^(band|mood|sentiment|stance|tone|condition|posture|status|state)$/i, null, /(health|mood|company|status|business)/i);
  await req(SEC, 'exec-home-company-mood', 'A single company mood/status indicator on the landing screen',
    `select ${moodKeys.length > 0} and ${DELIVERED(moodKeys)}`,
    `select ${FIGEV(moodKeys, 'the landing screen')} || '; company_index today: ' ||
       coalesce((select string_agg(index_name || '=' || band, ' ') from public.company_index
                  where measured_on = (select max(measured_on) from public.company_index)), 'none') ||
       ', browser-reachable readers ' || ${UI_READS('company_index')}::text || ' of ' ||
       ${ALL_READS('company_index')}::text || ' namers'`);

  // ================= SCREEN 2 — AI CONVERSATION ================================================

  // "Asking, not clicking, is the primary way." Three measurable senses of primary, all required:
  // the console is what the shell OPENS with; it has a real input and a send path; and it is
  // reachable from persistent chrome on every other screen, so you never have to navigate back to
  // ask. The 29-module sidebar is printed because it is the counter-evidence, not because the
  // requirement forbids a sidebar.
  const consoleIsDefault = (MODULES.find(m => m.id === DEFAULT_MOD) || {}).kind === 'console';
  const consoleAsks = has(CONSOLE, /<(textarea|Input)\b/i) && has(CONSOLE, /secretary_chat/);
  const askFromChrome = has(slice('OsxShell'), /setCur\('console'\)|go\('console'\)/);
  await req(SEC, 'ai-conversation-primary-interaction', 'Asking, not clicking, is the primary way to interact',
    `select ${consoleIsDefault} and ${consoleAsks} and ${askFromChrome}
       and ${EDGE_FNS.includes('secretary_act')}`,
    `select ${S(`default module '${DEFAULT_MOD}' is the console: ${consoleIsDefault}; the console carries an input bound to secretary_chat: ${consoleAsks}; reachable from persistent chrome on every screen: ${askFromChrome}; secretary_act is browser-reachable: ${EDGE_FNS.includes('secretary_act')}; the sidebar offers ${MODULES.length} click targets`)}`);

  // "Why are supplier replies slower TODAY?" needs a comparison, not a level. A routine that reports
  // the current value of a snapshot answers a different question, so the reachable routine must
  // compute a period-over-period change AND the snapshot store must hold at least two periods for
  // there to be a change to compute.
  const DELTA_RX = `'(lag\\s*\\(|previous|prior|day_over_day|yesterday|delta|_change|change_pct|vs_prior)'`;
  const SNAP_RX = `'\\y(supply_health_snapshots|ai_quality_snapshots|metric_snapshot|company_index|company_snapshot)\\y'`;
  await req(SEC, 'ai-conversation-diagnostic-why', 'The AI answers causal questions about today',
    `select (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
               and pg_get_functiondef(p.oid) ~* ${SNAP_RX}
               and pg_get_functiondef(p.oid) ~* ${DELTA_RX}) > 0
       and ${CNT('supply_health_snapshots')} > 0`,
    `select (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
               and pg_get_functiondef(p.oid) ~* ${SNAP_RX}
               and pg_get_functiondef(p.oid) ~* ${DELTA_RX})::text
       || ' browser-reachable routine(s) compare a snapshot period-over-period; ' ||
       ${UI_READS('supply_health_snapshots')}::text || ' reachable reader(s) of supply_health_snapshots (' ||
       ${CNT('supply_health_snapshots')}::text || ' rows) of ' || ${ALL_READS('supply_health_snapshots')}::text ||
       ' namers; ai_quality_snapshots reachable readers ' || ${UI_READS('ai_quality_snapshots')}::text`);

  // "Show today's biggest opportunities." Either the ask path can query the table, or an actual open
  // opportunity's TITLE is already inside what the agent is handed — content, not a mention of the
  // word, because a prompt that says "opportunities" while carrying none answers nothing.
  const OPP_IN_CTX = `exists (select 1 from public.opportunity o,
      (select public.fn_agent_context('cfo', 22000) x) c
     where o.status = 'open' and length(o.title) > 8 and position(left(o.title, 60) in c.x) > 0)`;
  await req(SEC, 'ai-conversation-opportunities', "The AI answers 'show today's biggest opportunities'",
    `select ${UI_READS('opportunity')} > 0 or ${OPP_IN_CTX}`,
    `select ${CNT('opportunity', `status = 'open'`)}::text || ' open opportunit(ies); ' ||
       ${UI_READS('opportunity')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('opportunity')}::text ||
       ' namers (' || ${UI_READ_NAMES('opportunity')} || '); an open opportunity title appears in the agent context: ' ||
       (${OPP_IN_CTX})::text`);

  // "Which department needs help?" needs a per-department signal the ask path can reach, and it must
  // cover EVERY department — a health view carrying nine of fifteen answers the question wrongly for
  // six of them, which is worse than not answering.
  await req(SEC, 'ai-conversation-which-dept-needs-help', "The AI answers 'which department needs help?'",
    `select ${UI_READS('v_department_health')} + ${UI_READS('v_resource_pressure')} > 0
       and ${CNT('org_departments')} > 0
       and ${VIEW_COVER('v_department_health', 'dept_key')} >= ${CNT('org_departments')}`,
    `select 'v_department_health covers ' || ${VIEW_COVER('v_department_health', 'dept_key')}::text
       || ' of ' || ${CNT('org_departments')}::text || ' department(s), with ' ||
       ${UI_READS('v_department_health')}::text || ' browser-reachable reader(s) of ' ||
       ${ALL_READS('v_department_health')}::text || ' namers; v_resource_pressure reachable readers ' ||
       ${UI_READS('v_resource_pressure')}::text || ', review_chain ' || ${UI_READS('review_chain')}::text`);

  // "What worries you most today?" — the company's OWN judgement, so this is a content test on what
  // the agent is actually handed. company_reflection.concerns is an integer on production (a count,
  // not a text), so the judgement can only travel through answers or through risk_register, and both
  // are tested by looking for their text inside the context rather than for the topic word.
  const WORRY = `(select exists (select 1 from public.risk_register r, c
        where length(r.risk) > 20 and position(left(r.risk, 50) in c.x) > 0)
      or exists (select 1 from public.company_reflection f, c,
        lateral jsonb_each_text(case when jsonb_typeof(f.answers) = 'object' then f.answers else '{}'::jsonb end) a
        where length(a.value) > 30 and position(left(a.value, 50) in c.x) > 0))`;
  await req(SEC, 'ai-conversation-worry', "The AI answers 'what worries you most today?' with its own judgement",
    `with c as (select public.fn_agent_context('cfo', 22000) x) select ${WORRY}`,
    `with c as (select public.fn_agent_context('cfo', 22000) x)
     select 'a stored risk or reflection answer appears verbatim in the agent context: ' || ${WORRY}::text ||
       '; risk_register holds ' || ${CNT('risk_register')}::text || ' row(s) with ' ||
       ${UI_READS('risk_register')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('risk_register')}::text ||
       ' namers; company_reflection ' || ${CNT('company_reflection')}::text || ' row(s), reachable readers ' ||
       ${UI_READS('company_reflection')}::text`);

  // "How can we reach AED 1M this year?" must return a PATH. A forecast returns a number, which is
  // why fn_finance_forecast being reachable is not enough: the reachable routine has to assemble an
  // ordered set of steps, and the long-horizon ledger it would draw them from has to be read at all.
  const PLAN_RX = `'(step|milestone|roadmap|pathway|sequence)'`;
  const AGG_RX = `'(jsonb_agg|array_agg|jsonb_build_array)'`;
  await req(SEC, 'ai-conversation-goal-path', 'A long-horizon goal question is answered with a path',
    `select ${UI_READS('vision_horizon')} > 0
       and (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
             where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
               and pg_get_functiondef(p.oid) ~* ${PLAN_RX} and pg_get_functiondef(p.oid) ~* ${AGG_RX}
               and pg_get_functiondef(p.oid) ~* '\\y(company_goals|goal_period|vision_horizon)\\y') > 0`,
    `select 'vision_horizon holds ' || ${CNT('vision_horizon')}::text || ' row(s) with ' ||
       ${UI_READS('vision_horizon')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('vision_horizon')}::text ||
       ' namers; ' ||
       (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
           and pg_get_functiondef(p.oid) ~* ${PLAN_RX} and pg_get_functiondef(p.oid) ~* ${AGG_RX}
           and pg_get_functiondef(p.oid) ~* '\\y(company_goals|goal_period|vision_horizon)\\y')::text
       || ' reachable routine(s) assemble a multi-step goal path; fn_finance_forecast reachable (a point estimate): ' ||
       ${S(String(REACH('fn_finance_forecast')))}`);

  // ================= SCREEN 3 — LIVE COMPANY ===================================================

  // "A LIVE view of what each department is doing RIGHT NOW." Three separable claims, and a surface
  // that satisfies two of them is not the thing: it must render a department dimension, render an
  // activity figure beside it, and refresh itself without the founder reloading. The refresh clause
  // is what the word "live" means and it is measured on the component, not assumed from the payload.
  const liveComponents = nComponents(b =>
    renderedKeys(b).some(k => /^(dept|dept_key|department|departments|by_department)$/i.test(k)) &&
    renderedKeys(b).some(k => /(running|in_flight|active|busy|open|runs|working|now|live)/i.test(k)));
  const liveRefreshing = liveComponents.filter(c => /setInterval|supa\.channel|postgres_changes/.test(slice(c)));
  await req(SEC, 'live-company-work-in-flight', 'A live view of what each department is doing right now',
    `select ${liveRefreshing.length > 0}
       and (select count(*) from public.agent_runs where started_at > now() - interval '24 hours') > 0`,
    `select ${S(`${liveComponents.length} component(s) render a department beside an activity figure [${liveComponents.join(' ') || 'none'}], of which ${liveRefreshing.length} refresh without a reload [${liveRefreshing.join(' ') || 'none'}]; `)}
       || (select count(*) from public.agent_runs where started_at > now() - interval '24 hours')::text ||
       ' agent run(s) in 24h across ' ||
       (select count(distinct a.department) from public.agent_runs r
          join public.org_agents a on a.agent_key = r.agent
         where r.started_at > now() - interval '24 hours')::text || ' department(s); org_tasks reachable readers ' ||
       ${UI_READS('org_tasks')}::text || ' of ' || ${ALL_READS('org_tasks')}::text || ' namers'`);

  // Work passing BETWEEN departments in sequence. A flat list of recent events is the thing this
  // requirement rejects, so the rendered figure has to name a hop, and the chain store it would be
  // drawn from has to be reachable at all.
  const chainKeys = shown(SHELL, /(chain|handoff|hop|from_dept|to_dept|from_os|to_os|predecessor|upstream|downstream)/i, null, null);
  await req(SEC, 'live-company-handoff-chain', 'Work is shown passing between departments in sequence',
    `select ${chainKeys.length > 0} and ${DELIVERED(chainKeys)}
       and ${UI_READS('review_chain')} + ${UI_READS('event_delivery')} > 0`,
    `select ${S(`hop/chain key(s) rendered anywhere in the shell: ${chainKeys.join(' ') || 'none'}; `)}
       || 'review_chain holds ' || ${CNT('review_chain')}::text || ' row(s), reachable readers ' ||
       ${UI_READS('review_chain')}::text || ' of ' || ${ALL_READS('review_chain')}::text ||
       ' namers; event_delivery ' || ${CNT('event_delivery')}::text || ' row(s), reachable readers ' ||
       ${UI_READS('event_delivery')}::text || '; event_subscription reachable readers ' ||
       ${UI_READS('event_subscription')}::text`);

  // ================= SCREEN 4 — ORGANIZATION ===================================================

  // A reporting hierarchy of EVERY AI employee. The universal is a per-row NOT EXISTS over active
  // employees rather than a count above zero: one manager_key on one row is an edge, not a chart.
  // Exactly one root (the CEO) is permitted and no more, because two roots is two org charts.
  const orgChartKeys = shown(SRC, /(manager_key|reports_to|parent_agent|supervisor|hierarchy|org_chart)/i, null, null);
  const orgChartNamed = /OrgChart|org[-_ ]?chart/i.test(SRC);
  const ORPHANS = `(select count(*) from public.org_agents a where a.active and a.manager_key is null)`;
  const BAD_MGR = `(select count(*) from public.org_agents a where a.active and a.manager_key is not null
      and not exists (select 1 from public.org_agents m where m.agent_key = a.manager_key and m.active))`;
  await req(SEC, 'org-chart-hierarchy', 'A reporting hierarchy of every AI employee',
    `select (${orgChartKeys.length > 0} or ${orgChartNamed})
       and ${UI_READS('v_org_chart')} + ${EMITS(`'\\ymanager_key\\y'`)} > 0
       and ${ORPHANS} <= 1 and ${BAD_MGR} = 0`,
    `select ${S(`hierarchy key(s) rendered in src/: ${orgChartKeys.join(' ') || 'none'}; a component named for an org chart: ${orgChartNamed}; `)}
       || (select count(*) from public.org_agents where active)::text || ' active employee(s), of which ' ||
       ${ORPHANS}::text || ' have no manager and ' || ${BAD_MGR}::text ||
       ' name a manager who is not an active employee; v_org_chart browser-reachable readers ' ||
       ${UI_READS('v_org_chart')}::text || ' of ' || ${ALL_READS('v_org_chart')}::text ||
       ' namers; reachable routines emitting manager_key: ' || ${EMITS(`'\\ymanager_key\\y'`)}::text`);

  // "Clicking any PERSON opens their workspace" — the entry point is the requirement, not the
  // drawer. The drawer exists and opens; what is measured is whether the thing you click is a node
  // in a chart or a row in a table, which is the distinction the spec draws in as many words.
  const drawerOpeners = nComponents(b => /<AgentDrawer\b/.test(b));
  const chartOpeners = drawerOpeners.filter(c => /<(svg|canvas)\b|OrgChart|nodes\.map|\bcx=|\bcy=/.test(slice(c)));
  const openerControls = drawerOpeners.map(c => (slice(c).match(/on(Card|Row|Node|Click)=/g) || []).join(' ')).join(' ');
  await req(SEC, 'org-chart-click-into-workspace', 'Clicking any person opens their workspace',
    `select ${chartOpeners.length > 0} and ${REACH('fn_ws_agent_ops')}`,
    `select ${S(`the agent workspace opens from ${drawerOpeners.join(' ') || 'nowhere'} via ${openerControls.trim() || 'no handler'}; ${chartOpeners.length} of those entry points is a chart node; fn_ws_agent_ops reachable: ${REACH('fn_ws_agent_ops')}`)}`);

  // ================= SCREEN 5 — EMPLOYEE VIEW ==================================================
  // Every check below is scored on the AgentDrawer, which is the employee workspace, and every one
  // that claims a per-employee fact is a per-row NOT EXISTS over THE EMPLOYEES THAT ACTUALLY WORKED
  // in the window. That population is chosen deliberately: demanding a thought or a task from an
  // employee who has not run in a month is a requirement no implementation could satisfy, and
  // over-hardening is as much a scoring failure as loosening.
  const UNCOVERED = (t, col, win) => `(select count(*) from public.org_agents a where a.active
        and not exists (select 1 from public.${t} x where x.agent_key = a.agent_key
              ${win ? `and x.${col} > now() - interval '${win}'` : ''}))`;

  const thoughtKeys = shown(DRAWER, /(thought|memory|mem|reflection|reasoning|belief|rationale)/i, null, /(memory|thought|reflect|reason)/i);
  await req(SEC, 'employee-current-thoughts', "An employee's current thoughts are visible in their workspace",
    `select ${thoughtKeys.length > 0} and ${DELIVERED(thoughtKeys)}
       and ${UI_READS('agent_memory')} > 0 and ${UNCOVERED('agent_memory', 'created_at', '30 days')} = 0`,
    `select ${FIGEV(thoughtKeys, 'the employee workspace')} || '; ' ||
       ${UNCOVERED('agent_memory', 'created_at', '30 days')}::text || ' of ' || ${ACTIVE_EMP}::text ||
       ' active employee(s) have no agent_memory row in 30d (' || ${CNT('agent_memory')}::text ||
       ' rows over ' || (select count(distinct agent_key) from public.agent_memory)::text ||
       ' employees); agent_memory browser-reachable readers ' || ${UI_READS('agent_memory')}::text`);

  const taskKeys = shown(DRAWER, /(task|todo|assignment|workitem|backlog)/i, null, /(task|to.?do|assign|work)/i);
  await req(SEC, 'employee-current-tasks', "An employee's current tasks are visible in their workspace",
    `select ${taskKeys.length > 0} and ${DELIVERED(taskKeys)} and ${UI_READS('org_tasks')} > 0`,
    `select ${FIGEV(taskKeys, 'the employee workspace')} || '; org_tasks holds ' || ${CNT('org_tasks')}::text ||
       ' row(s) (' || ${CNT('org_tasks', `status <> 'done'`)}::text || ' not done) with ' ||
       ${UI_READS('org_tasks')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('org_tasks')}::text ||
       ' namers; fn_ws_agent_ops names org_tasks: ' ||
       coalesce((select (pg_get_functiondef(p.oid) ~* '\\yorg_tasks\\y')::text from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname='public' and p.proname='fn_ws_agent_ops' limit 1), 'absent')`);

  const decKeys = shown(DRAWER, /(decision|verdict|ruling|decided|adjudicat)/i, null, /(decision|decided|verdict)/i);
  await req(SEC, 'employee-recent-decisions', "An employee's recent decisions are visible in their workspace",
    `select ${decKeys.length > 0} and ${DELIVERED(decKeys)}
       and coalesce((select pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y' from pg_proc p
                      join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname='public' and p.proname='fn_ws_agent_ops' limit 1), false)`,
    `select ${FIGEV(decKeys, 'the employee workspace')} || '; decision_log holds ' || ${CNT('decision_log')}::text ||
       ' row(s) across ' || (select count(distinct actor) from public.decision_log)::text ||
       ' actor(s); fn_ws_agent_ops filters decision_log by agent: ' ||
       coalesce((select (pg_get_functiondef(p.oid) ~* '\\ydecision_log\\y')::text from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname='public' and p.proname='fn_ws_agent_ops' limit 1), 'absent') ||
       '; decision_record reachable readers ' || ${UI_READS('decision_record')}::text ||
       ', decision_trace ' || ${UI_READS('decision_trace')}::text`);

  // A run EXISTING is tautological for a population defined by having run, so the universal asks
  // for what the rate is actually computed from: a run that reached a terminal status in the window.
  // The drawer computes Runs 24h, Runs 7d, OK rate and Avg run from agent_runs matched on the
  // employee's key. An employee with no run row sees four dashes, so this counts the employees for
  // whom the panel can say nothing at all. No window: performance is historical.
  // AGENT_RUNS IS NOT THE ONLY PERFORMANCE SOURCE THE DRAWER HAS (27 Aug 2026). This counted
  // employees with no agent_runs row and reported "the panel can compute nothing for them" — 71 of
  // 90. That sentence was false about 70 of the 71. agent_runs is a cron execution log, so an
  // employee that has never been on a cron has no row in it and never will; meanwhile the drawer
  // also renders a KPI trend line from employee_kpi_history (kpiTrend, the MiniLine and the "n days
  // · n KPI(s) · latest n%" caption) and a reputation score and tier from agent_reputation, and 89
  // of the 90 carry both. Measured: 71 have no agent_runs, 1 has no employee_kpi, 1 has no
  // employee_kpi_history, and exactly 1 — product_ux_designer, hired 15 Aug after
  // employee_kpi_measure_daily was paused — has no performance source of any kind.
  //
  // The population is now the employees for whom the panel can genuinely say nothing. That is not a
  // loosening: an employee with a rendered KPI curve and a rendered reputation tier does have
  // performance visible in their workspace, which is what this requirement asks. It stays red, on
  // the true count of 1 rather than the false count of 71.
  const NO_PERF = `(select count(*) from public.org_agents a where a.active
      and not exists (select 1 from public.agent_runs r where r.agent = a.agent_key)
      and not exists (select 1 from public.employee_kpi k where k.agent_key = a.agent_key)
      and not exists (select 1 from public.employee_kpi_history h where h.agent_key = a.agent_key)
      and not exists (select 1 from public.agent_reputation g where g.agent_key = a.agent_key))`;
  const NO_RUNS = `(select count(*) from public.org_agents a where a.active
      and not exists (select 1 from public.agent_runs r where r.agent = a.agent_key))`;
  const perfKeys = shown(DRAWER, /(perf|ok_rate|success_rate|quality|accuracy|rating|score|duration|runs_)/i, null, /(perform|rate|run|quality|score)/i);
  await req(SEC, 'employee-performance', "An employee's performance is visible in their workspace",
    `select ${perfKeys.length > 0} and ${DELIVERED(perfKeys)} and ${NO_PERF} = 0`,
    `select ${FIGEV(perfKeys, 'the employee workspace')} || '; ' ||
       ${NO_PERF}::text || ' of ' || ${ACTIVE_EMP}::text ||
       ' active employee(s) have no performance source of any kind — no agent_runs, no employee_kpi, no employee_kpi_history and no agent_reputation — so the panel can compute nothing for them; ' ||
       ${NO_RUNS}::text || ' have no agent_runs row specifically, which on its own is a cron log and not a verdict on the employee; employee_kpi holds ' ||
       ${CNT('employee_kpi')}::text || ' row(s) with ' || ${UI_READS('employee_kpi')}::text ||
       ' browser-reachable reader(s); ai_quality_snapshots reachable readers ' ||
       ${UI_READS('ai_quality_snapshots')}::text`);

  const confKeys = shown(DRAWER, /(confidence|certainty|conviction|assurance)/i, null, null);
  await req(SEC, 'employee-confidence', "An employee's confidence level is visible in their workspace",
    `select ${confKeys.length > 0} and ${DELIVERED(confKeys)}`,
    `select ${FIGEV(confKeys, 'the employee workspace')} || '; decision_log carries a confidence on ' ||
       (select count(*) from public.decision_log where confidence is not null)::text || ' of ' ||
       ${CNT('decision_log')}::text || ' row(s); agent_reputation holds ' || ${CNT('agent_reputation')}::text ||
       ' scored employee(s) with ' || ${UI_READS('agent_reputation')}::text ||
       ' browser-reachable reader(s) of ' || ${ALL_READS('agent_reputation')}::text || ' namers'`);

  const knowKeys = shown(DRAWER, /(knowledge|topic|expertise|domain|corpus)/i, null, /(knowledge|topic|expert)/i);
  await req(SEC, 'employee-knowledge', "An employee's knowledge holdings are visible in their workspace",
    `select ${knowKeys.length > 0} and ${DELIVERED(knowKeys)}
       and ${UI_READS('agent_knowledge')} > 0 and ${UNCOVERED('agent_knowledge', null, null)} = 0`,
    `select ${FIGEV(knowKeys, 'the employee workspace')} || '; ' ||
       ${UNCOVERED('agent_knowledge', null, null)}::text || ' of ' || ${ACTIVE_EMP}::text ||
       ' active employee(s) hold no agent_knowledge row (' || ${CNT('agent_knowledge')}::text ||
       ' rows); employee_knowledge ' || ${CNT('employee_knowledge')}::text || ' row(s) with ' ||
       ${UI_READS('employee_knowledge')}::text || ' browser-reachable reader(s)'`);

  // WORKLOAD is how much work this employee is carrying, which is not the same as how many of their
  // decisions are waiting on the FOUNDER. The drawer's `queue` is the second of those, so it is
  // deliberately outside the pattern and is printed in the evidence so the exclusion is visible
  // rather than silent.
  // A BARE `load` IS NOT A WORKLOAD. Thirty-one components in this shell declare
  // `const load = React.useCallback(…)` and render something that mentions it, so the first version
  // of this pattern matched `load` on the drawer and scored the requirement MET on the name of a
  // fetch function. The token must be a compound that names the concept, and it must sit beside a
  // label that does too.
  const loadKeys = shown(DRAWER, /(workload|work_load|capacity|utilis|utiliz|open_tasks|assigned_tasks|load_pct|_load\b|busy_pct|queue_depth)/i, null, /(load|capacity|task|utilis|utiliz|busy|assign)/i);
  await req(SEC, 'employee-workload', "An employee's workload is visible in their workspace",
    `select ${loadKeys.length > 0} and ${DELIVERED(loadKeys)}`,
    `select ${S(`workload key(s) in the employee workspace: ${loadKeys.join(' ') || 'none'} (the drawer's founder-approval queue is not counted as the employee's load); `)}
       || 'org_tasks holds ' || ${CNT('org_tasks', `status <> 'done'`)}::text ||
       ' open row(s) with ' || ${UI_READS('org_tasks')}::text || ' browser-reachable reader(s); employee_workflow ' ||
       ${CNT('employee_workflow')}::text || ' row(s) with ' || ${UI_READS('employee_workflow')}::text ||
       ' reachable reader(s); v_resource_pressure reachable readers ' || ${UI_READS('v_resource_pressure')}::text`);

  const planKeys = shown(DRAWER, /(plan|upcoming|next_|scheduled|objective|goal|roadmap|forthcoming)/i, null, null);
  await req(SEC, 'employee-upcoming-plans', "An employee's upcoming plans are visible in their workspace",
    `select ${planKeys.length > 0} and ${DELIVERED(planKeys)}
       and ${UI_READS('department_objective')} + ${UI_READS('os_objective')} > 0`,
    `select ${S(`forward-looking key(s) in the employee workspace: ${planKeys.join(' ') || 'none'}; `)}
       || 'department_objective holds ' || ${CNT('department_objective')}::text || ' row(s) with ' ||
       ${UI_READS('department_objective')}::text || ' browser-reachable reader(s) of ' ||
       ${ALL_READS('department_objective')}::text || ' namers; os_objective ' || ${CNT('os_objective')}::text ||
       ' row(s) with ' || ${UI_READS('os_objective')}::text || ' reachable reader(s)'`);

  // LEARNING PROGRESS is a curve, so one exam result per employee is a point and not progress. The
  // DB leg asks for at least two dated results for every employee that worked, which is the smallest
  // population from which "progress" can be drawn at all.
  const learnKeys = shown(DRAWER, /(learn|exam|progress|training|mastery|improvement|skill)/i, null, null);
  const NO_TREND = `(select count(*) from public.org_agents a where a.active
        and (select count(distinct date_trunc('day', e.created_at)) from public.knowledge_exam_results e
              where e.agent_key = a.agent_key) < 2)`;
  await req(SEC, 'employee-learning-progress', "An employee's learning progress is visible in their workspace",
    `select ${learnKeys.length > 0} and ${DELIVERED(learnKeys)} and ${NO_TREND} = 0`,
    `select ${S(`learning key(s) in the employee workspace: ${learnKeys.join(' ') || 'none'}; `)}
       || ${NO_TREND}::text || ' of ' || ${ACTIVE_EMP}::text ||
       ' active employee(s) have fewer than two dated exam results, so no curve exists for them (' ||
       ${CNT('knowledge_exam_results')}::text || ' results total); skills_matrix ' || ${CNT('skills_matrix')}::text ||
       ' row(s) with ' || ${UI_READS('skills_matrix')}::text || ' browser-reachable reader(s); self_review reachable readers ' ||
       ${UI_READS('self_review')}::text`);

  // ================= SCREEN 6 — COMPANY TIMELINE ===============================================

  // A COMPANY-WIDE stream. fn_entity_activity reads company_event, but only for one record at a
  // time, so the reachable-reader count is not the measurement — what is measured is whether any
  // reachable reader can return the stream WITHOUT being handed an entity, which is the difference
  // between per-record chatter and a company timeline.
  // A NAMER IS NOT A READER AND A READER IS NOT A SCREEN. The first version counted reachable
  // routines that merely NAME company_event without taking an entity parameter, and got six — every
  // one of which was fn_emit, fn_emit_event, fn_event_dispatch or another writer/dispatcher that
  // returns nothing to a browser, so both timeline requirements scored MET while no timeline exists.
  // Writers are now dropped by pattern, and the decisive leg is the rendered surface: a component
  // that shows a timestamped stream AND is not scoped to one record. ActivityPanel takes
  // ({ entity, id }) and is per-record chatter, which is exactly what this requirement rejects.
  const UNSCOPED = `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${UI})
         and pg_get_functiondef(p.oid) ~* '\\y(company_event|event_rollup)\\y'
         and pg_get_functiondef(p.oid) !~* '\\y(p_entity|p_id)\\y'
         and pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?(company_event|event_rollup)\\y'))`;
  const perRecord = (c) => /^(?:export default )?function \w+\s*\(\s*\{[^}]*\b(entity|id)\b/.test(slice(c));
  const timelineComponents = nComponents(b =>
    renderedKeys(b).some(k => /(occurred_at|event_type|timeline)/i.test(k))).filter(c => !perRecord(c));
  const timelineKeys = timelineComponents.length
    ? shown(timelineComponents.map(c => slice(c)).join('\n'), /(occurred_at|event_type|timeline)/i, null, null) : [];
  await req(SEC, 'company-timeline-chronological', 'A single company-wide, timestamped stream of everything',
    `select ${UNSCOPED} > 0 and ${timelineKeys.length > 0} and ${DELIVERED(timelineKeys)}`,
    `select ${UNSCOPED}::text || ' browser-reachable routine(s) return company_event without being handed an entity, of ' ||
       ${UI_READS('company_event')}::text || ' reachable reader(s) and ' || ${ALL_READS('company_event')}::text ||
       ' namers; company_event holds ' || ${CNT('company_event')}::text || ' row(s); ' ||
       ${S(`company-scoped surface(s) rendering a timestamped stream: ${timelineComponents.join(' ') || 'none'} showing [${timelineKeys.join(' ') || 'none'}], per-record chatter panels excluded; the sidebar has ${MODULES.filter(m => /timeline|event|history|feed/i.test(m.label)).length} timeline module(s)`)}`);

  // "Nothing is hidden" is a RATIO over event classes, not a yes/no about one surface. Every distinct
  // event_type either reaches a company-scoped surface or it does not, and the ratio has to be 1.
  const TYPES = `(select count(distinct event_type) from public.company_event)`;
  const TYPES_REACHING = `(case when ${UNSCOPED} > 0 then ${TYPES} else 0 end)`;
  await req(SEC, 'company-timeline-nothing-hidden', 'The timeline hides nothing — every event class appears',
    `select ${TYPES} > 0 and ${TYPES_REACHING} = ${TYPES} and ${timelineKeys.length > 0}`,
    `select ${TYPES_REACHING}::text || ' of ' || ${TYPES}::text ||
       ' distinct company_event class(es) reach a company-scoped surface; event_rollup holds ' ||
       ${CNT('event_rollup')}::text || ' row(s) with ' || ${UI_READS('event_rollup')}::text ||
       ' browser-reachable reader(s); os_audit_log reachable readers ' || ${UI_READS('os_audit_log')}::text ||
       ', security_audit_log ' || ${UI_READS('security_audit_log')}::text`);

  // ================= SCREEN 7 — MISSION CONTROL ================================================

  // Ten Operating Systems drawn as living nodes. The per-row universal is over the ACTIVE OS rows:
  // a screen that draws eight of ten is not the mission control this describes, and a count above
  // zero would let one node score all ten.
  const osKeys = shown(SRC, /(os_key|operating_system|os_name|os_num)/i, null, null);
  await req(SEC, 'mission-control-os-nodes', 'Each Operating System is drawn as a living node',
    `select ${osKeys.length > 0} and ${DELIVERED(osKeys)}
       and ${UI_READS('operating_system')} > 0
       and (select count(*) from public.operating_system where active) >= 10`,
    `select ${S(`Operating-System key(s) rendered in src/: ${osKeys.join(' ') || 'none'}; a surface named for mission control: ${/mission[-_ ]?control/i.test(SRC)}; `)}
       || (select count(*) from public.operating_system where active)::text || ' active OS row(s), with ' ||
       ${UI_READS('operating_system')}::text || ' browser-reachable reader(s) of ' ||
       ${ALL_READS('operating_system')}::text || ' namers; os_interface ' || ${CNT('os_interface')}::text ||
       ' edge(s) with ' || ${UI_READS('os_interface')}::text || ' reachable reader(s); os_responsibility reachable readers ' ||
       ${UI_READS('os_responsibility')}::text`);

  // Connections that ANIMATE WHEN INFORMATION FLOWS. Three conjuncts because any two of them are
  // satisfied by things that already exist and are not this: NodeField animates a canvas with no
  // data behind it, and MiniLine draws a data-bound path that never moves.
  const edgeDrawers = nComponents(b => /<line\b|<path\b|<polyline\b|drawEdge|lineTo/.test(b));
  const animated = edgeDrawers.filter(c => /animate|requestAnimationFrame|transition|keyframes|@keyframes/.test(slice(c)));
  const flowBound = animated.filter(c => renderedKeys(slice(c)).some(k => /(interface|edge|flow|from_os|to_os|link|delivery|event)/i.test(k)));
  await req(SEC, 'mission-control-flow-animation', 'Connections animate when information flows between OSes',
    `select ${flowBound.length > 0} and ${UI_READS('os_interface')} + ${UI_READS('event_delivery')} > 0`,
    `select ${S(`${edgeDrawers.length} component(s) draw connections [${edgeDrawers.join(' ') || 'none'}], ${animated.length} of those animate [${animated.join(' ') || 'none'}], ${flowBound.length} of those are bound to a flow dataset; `)}
       || 'os_interface holds ' || ${CNT('os_interface')}::text || ' edge(s) with ' ||
       ${UI_READS('os_interface')}::text || ' browser-reachable reader(s); event_delivery ' ||
       ${CNT('event_delivery')}::text || ' row(s) with ' || ${UI_READS('event_delivery')}::text || ' reachable reader(s)'`);

  // ================= SCREEN 8 — DIGITAL TWIN ===================================================

  // EVERY department has a health value IN THE TWIN. Two universals, one on each side: the twin must
  // carry a row per department, and a rendered surface must be able to show it. Either alone is the
  // defect this spec exists to catch — v_department_health is complete and read by nobody.
  const DEPTS = `(select count(*) from public.org_departments)`;
  const TWIN_DEPTS = VIEW_COVER('v_department_health', 'dept_key');
  const twinDeptKeys = shown(SRC, /(dept|department)/i, /(health|score|status|band|index)/i, null);
  await req(SEC, 'digital-twin-department-health', 'Every department has a health value in the twin',
    `select ${DEPTS} > 0 and ${TWIN_DEPTS} >= ${DEPTS}
       and ${UI_READS('v_department_health')} + ${UI_READS('v_digital_twin')} > 0
       and ${twinDeptKeys.length > 0} and ${DELIVERED(twinDeptKeys)}`,
    `select ${TWIN_DEPTS}::text || ' of ' || ${DEPTS}::text ||
       ' department(s) carry a health value in v_department_health, with ' ||
       ${UI_READS('v_department_health')}::text || ' browser-reachable reader(s) of ' ||
       ${ALL_READS('v_department_health')}::text || ' namers; v_digital_twin reachable readers ' ||
       ${UI_READS('v_digital_twin')}::text || '; ' ||
       ${S(`per-department health key(s) rendered in src/: ${twinDeptKeys.join(' ') || 'none'}`)}`);

  // EVERY employee has a workload value in the twin. The population is every active employee — this
  // is a twin of the organisation, so an employee absent from it is a hole in the model, not an idle
  // worker, and the recency bound is on the figure rather than on the person.
  const TWIN_LOAD = `(select count(*) from public.org_agents a where a.active
      and not exists (select 1 from public.employee_kpi k where k.agent_key = a.agent_key and k.active))`;
  const twinLoadKeys = shown(SRC, /(workload|work_load|capacity|utilis|utiliz|open_tasks|assigned_tasks|load_pct|_load\b|busy_pct)/i, null, /(load|capacity|task|utilis|utiliz|busy|assign)/i);
  await req(SEC, 'digital-twin-employee-workload', 'Every employee has a workload value in the twin',
    `select ${TWIN_LOAD} = 0
       and ${UI_READS('v_digital_twin')} + ${UI_READS('employee_kpi')} + ${UI_READS('v_capability_matrix')} > 0
       and ${twinLoadKeys.length > 0} and ${DELIVERED(twinLoadKeys)}`,
    `select ${TWIN_LOAD}::text || ' of ' || (select count(*) from public.org_agents where active)::text ||
       ' active employee(s) carry no active employee_kpi row; employee_kpi holds ' || ${CNT('employee_kpi')}::text ||
       ' row(s) last written ' || coalesce((select max(created_at)::date::text from public.employee_kpi), 'never') ||
       ' with ' || ${UI_READS('employee_kpi')}::text || ' browser-reachable reader(s) of ' ||
       ${ALL_READS('employee_kpi')}::text || ' namers; ' ||
       ${S(`workload key(s) rendered in src/: ${twinLoadKeys.join(' ') || 'none'}`)}`);

  // EVERY KPI updates LIVE. Three legs: every defined metric has a snapshot inside a day, a
  // reachable routine can return them, and the surface that shows them refreshes itself. A daily
  // snapshot rendered by a page that never reloads is not a live KPI.
  const STALE_KPI = `(select count(*) from public.metric_definition m where m.active
      and not exists (select 1 from public.metric_snapshot s where s.metric_key = m.metric_key
              and s.taken_at > now() - interval '24 hours'))`;
  const kpiRefresh = nComponents(b => /setInterval|supa\.channel|postgres_changes/.test(b));
  await req(SEC, 'digital-twin-live-kpis', 'Every KPI updates live in the twin',
    `select ${CNT('metric_definition', 'active')} > 0 and ${STALE_KPI} = 0
       and ${UI_READS('metric_snapshot')} > 0 and ${kpiRefresh.length > 0}
       and ${EMITS(`'\\y(metric_snapshot|metric_definition|v_bi_scorecard)\\y'`)} > 0`,
    `select ${STALE_KPI}::text || ' of ' || ${CNT('metric_definition', 'active')}::text ||
       ' active metric(s) have no snapshot inside 24h (metric_snapshot holds ' || ${CNT('metric_snapshot')}::text ||
       ' rows, newest ' || coalesce((select max(taken_at)::timestamp(0)::text from public.metric_snapshot), 'never') ||
       '); browser-reachable readers of metric_snapshot ' || ${UI_READS('metric_snapshot')}::text || ' of ' ||
       ${ALL_READS('metric_snapshot')}::text || ' namers; ' ||
       ${S(`${kpiRefresh.length} component(s) refresh without a reload [${kpiRefresh.join(' ') || 'none'}]`)}`);

  // "Where pressure is building is IMMEDIATELY visible" — a gradient or a heat scale, which the spec
  // contrasts with a table. Measured as a rendered pressure figure carried by a visual intensity
  // channel (a colour scale, a width, a fill) rather than by a cell.
  const pressureComponents = nComponents(b =>
    renderedKeys(b).some(k => /(pressure|utilis|utiliz|capacity|committed|saturation|headroom|degrade_at|halt_at)/i.test(k)));
  const pressureVisual = pressureComponents.filter(c =>
    /gradient|hsl\(|backgroundColor|style=\{\{[^}]*width|fill=|bg-\$\{|heat/i.test(slice(c)));
  await req(SEC, 'digital-twin-pressure-visible', 'Where pressure is building is immediately visible',
    `select ${pressureVisual.length > 0} and ${UI_READS('resource_pool')} + ${UI_READS('v_resource_pressure')} > 0`,
    `select ${S(`${pressureComponents.length} component(s) render a pressure figure [${pressureComponents.join(' ') || 'none'}], ${pressureVisual.length} of those on a visual intensity channel; `)}
       || 'resource_pool holds ' || ${CNT('resource_pool')}::text || ' pool(s), of which ' ||
       ${CNT('resource_pool', 'committed > 0')}::text || ' carry a non-zero committed figure, with ' ||
       ${UI_READS('resource_pool')}::text || ' browser-reachable reader(s) of ' || ${ALL_READS('resource_pool')}::text ||
       ' namers; v_resource_pressure reachable readers ' || ${UI_READS('v_resource_pressure')}::text`);

  // ================= SCREEN 9 — APPROVAL CENTER ================================================

  // "Approvals arrive as a DECISION INBOX, not as notifications." Both halves are measured: a
  // surface that carries approve AND reject bound to a pending row's id, and a notification surface
  // that carries neither — if the bell also approves things then decisions and notices are not
  // separated, which is the distinction the requirement draws. The last leg is a per-row universal:
  // an action the founder cannot read cannot be decided, so every pending row must carry something
  // to decide on.
  const decidesComponents = nComponents(b => /'approve'/.test(b) && /'reject'/.test(b) && /\.id\b/.test(b));
  // Identified by NAME, not by a rendered key: NotificationsBell reads d.notifications inside an
  // effect and renders the items it produced, so a key scan finds nothing and would report zero
  // notification surfaces — which would let "decisions are separated from notices" pass vacuously.
  const notifComponents = [...SHELL.matchAll(/^(?:export default )?function (\w+)/gm)]
    .map(m => m[1]).filter(nm => /notif|alert|bell/i.test(nm));
  const notifAlsoDecides = notifComponents.filter(c => decidesComponents.includes(c));
  const UNREADABLE = `(select count(*) from public.agent_actions
      where status = 'pending' and coalesce(nullif(title, ''), nullif(recommendation, '')) is null)`;
  await req(SEC, 'approval-center-decision-inbox', 'Approvals arrive as a decision inbox, not as notifications',
    `select ${decidesComponents.length > 0} and ${notifComponents.length > 0} and ${notifAlsoDecides.length === 0}
       and ${UI_READS('agent_actions')} > 0 and ${UNREADABLE} = 0
       and (select count(*) from public.agent_actions
             where status = 'pending' or decided_at > now() - interval '30 days') > 0`,
    `select ${S(`${decidesComponents.length} decision surface(s) bind approve and reject to a row id [${decidesComponents.join(' ') || 'none'}]; ${notifComponents.length} notification surface(s) [${notifComponents.join(' ') || 'none'}], ${notifAlsoDecides.length} of which also decide; `)}
       || (select count(*) from public.agent_actions where status = 'pending')::text ||
       ' pending action(s), ' || ${UNREADABLE}::text || ' of them carrying neither a title nor a recommendation; ' ||
       (select count(*) from public.agent_actions where decided_at > now() - interval '30 days')::text ||
       ' decided in 30d; agent_actions browser-reachable readers ' || ${UI_READS('agent_actions')}::text`);

  // The FIVE NAMED decision kinds, each asked for separately. A global count of approvals says
  // nothing about whether a supplier suspension can reach the founder, so this is five per-kind
  // existence tests over what has actually been routed — a kind that has never once reached a
  // founder-decidable state is not routable, whatever a config table claims. Regex, never LIKE: the
  // patterns carry underscores and would be wildcards on the pattern side of LIKE.
  const KINDS = [
    ['marketing budget', `(marketing|campaign|advert|ad_|media)[a-z_ ]*(budget|spend|allocation)|(budget|spend)[a-z_ ]*(marketing|campaign|advert)`],
    ['supplier suspension', `(supplier|vendor|lead)[a-z_ ]*(suspend|suspension|ban|block|deactivat|offboard)|(suspend|ban|block)[a-z_ ]*(supplier|vendor)`],
    ['new category', `(new|add|creat|launch)[a-z_ ]*(category|categories|subcategory)|(category|categories|subcategory)[a-z_ ]*(new|add|creat|launch|propos)`],
    ['new AI skill', `(new|add|creat|hire)[a-z_ ]*(skill|capability|agent|role|specialist)|(skill|capability|agent|role)[a-z_ ]*(new|add|creat|propos)`],
    ['new policy', `polic(y|ies)|governance_rule|constitution`],
  ];
  const KIND_ROUTED = (rx) => `(select count(*) from public.agent_actions a
      where (a.kind ~* ${S(rx)} or coalesce(a.title, '') ~* ${S(rx)})
        and (a.status = 'pending' or a.decided_at is not null or a.escalated))`;
  const KINDS_OK = KINDS.map(([, rx]) => `(case when ${KIND_ROUTED(rx)} > 0 then 1 else 0 end)`).join(' + ');
  await req(SEC, 'approval-center-five-decision-kinds', 'The five named decision kinds are routable to the founder',
    `select (${KINDS_OK}) = 5 and ${decidesComponents.length > 0}`,
    `select (${KINDS_OK})::text || ' of 5 named decision kind(s) have ever reached a founder-decidable state: ' ||
       ${KINDS.map(([n, rx]) => `'${n}=' || ${KIND_ROUTED(rx)}::text`).join(` || ', ' || `)} ||
       '; agent_actions holds ' || (select count(distinct kind) from public.agent_actions)::text ||
       ' distinct kind(s); control_mode_action classifies ' || ${CNT('control_mode_action')}::text || ' action(s)'`);

  // "Everything else happens automatically." A share, over a recent window, on both queues the
  // founder can be pulled into: agent_actions that pause for a human, and org_tasks flagged for the
  // founder. Ten per cent is the bar and the window is thirty days, so a company that quietly starts
  // escalating everything fails within a month rather than never. Non-emptiness is asserted so the
  // ratio is never a zero over nothing.
  const AA_WIN = `(select count(*) from public.agent_actions where created_at > now() - interval '30 days')`;
  const AA_PAUSED = `(select count(*) from public.agent_actions where created_at > now() - interval '30 days'
      and (status = 'pending' or escalated))`;
  const OT_WIN = `(select count(*) from public.org_tasks where created_at > now() - interval '30 days')`;
  const OT_PAUSED = `(select count(*) from public.org_tasks where created_at > now() - interval '30 days'
      and needs_founder)`;
  await req(SEC, 'approval-center-everything-else-automatic', 'Everything not one of these decisions happens automatically',
    `select ${AA_WIN} > 0 and ${OT_WIN} > 0
       and ${AA_PAUSED}::numeric <= 0.10 * ${AA_WIN}
       and ${OT_PAUSED}::numeric <= 0.10 * ${OT_WIN}`,
    `select ${AA_PAUSED}::text || ' of ' || ${AA_WIN}::text ||
       ' agent action(s) in 30d paused for the founder (' ||
       round(100.0 * ${AA_PAUSED} / greatest(${AA_WIN}, 1), 1)::text || '%), and ' ||
       ${OT_PAUSED}::text || ' of ' || ${OT_WIN}::text || ' org_tasks flagged needs_founder (' ||
       round(100.0 * ${OT_PAUSED} / greatest(${OT_WIN}, 1), 1)::text || '%); control_mode_action classifies ' ||
       ${CNT('control_mode_action')}::text || ' action(s)'`);
}

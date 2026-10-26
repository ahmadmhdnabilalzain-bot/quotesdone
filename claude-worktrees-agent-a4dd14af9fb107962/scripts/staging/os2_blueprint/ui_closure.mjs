// ui_closure.mjs — the two things spec file #3 needs that pg_proc alone cannot answer.
//
// This spec file scores an EXECUTIVE UI. Its defining defect is BUILT_BUT_UNREAD: graph_nodes is
// rebuilt nightly by an active cron and has zero readers anywhere; company_index is measured daily
// and has zero readers; challenge_record holds 47 recorded disagreements and is displayed nowhere.
// A scorer that only reads the database cannot tell any of that apart from a working feature, so
// every check in this row needs two measurements the database does not hold:
//
//   1. THE UI CLOSURE. Which database routines can the BROWSER actually reach? Computed, never
//      assumed: the frontend names its edge functions as `/functions/v1/<name>`; each of those edge
//      functions names further edge functions and names its RPCs as string literals; and from those
//      root routines the reachable set is the transitive closure over pg_get_functiondef. A routine
//      outside that closure may run on a cron all night and the founder still cannot see its output.
//
//   2. THE RENDERED KEY SET. Which payload keys does a given React surface actually PUT ON SCREEN?
//      A component that fetches `health.index` and never renders it delivers nothing, so the key set
//      is taken from JSX interpolations (plus one hop through a local const that is itself
//      rendered — `const band = String(health.band)` then `{titleCase(band)}` is a rendered figure).
//
// The two are then joined: a figure is DELIVERED when a routine inside the UI closure emits a key
// and a React surface renders that same key. That chain is what "the founder can see it" means, and
// it is the only form of evidence in this file that a nightly cron cannot fake.
//
// THE TRAP THIS FILE EXISTS TO AVOID: reachability is NOT delivery. fn_graph_rebuild and
// fn_company_reflect are both inside the closure — the console can TRIGGER them through the
// automation runner — while nothing renders one byte of what they produce. Reachability is therefore
// never sufficient on its own in any check; the rendered key set is what closes the loop.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SRC_DIR = join(REPO, 'src');
const FN_DIR = join(REPO, 'supabase', 'functions');

function walk(d, acc = []) {
  if (!existsSync(d)) return acc;
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (/\.(ts|tsx|js|jsx)$/.test(e.name)) acc.push(p);
  }
  return acc;
}

export const SRC_FILES = walk(SRC_DIR);
export const SRC = SRC_FILES.map(f => readFileSync(f, 'utf8')).join('\n/*FILE*/\n');
export const SHELL = existsSync(join(SRC_DIR, 'components', 'osx', 'OsxShell.tsx'))
  ? readFileSync(join(SRC_DIR, 'components', 'osx', 'OsxShell.tsx'), 'utf8') : '';

const edgeSrc = (n) => {
  const p = join(FN_DIR, n, 'index.ts');
  return existsSync(p) ? readFileSync(p, 'utf8') : '';
};

// Edge functions the browser can reach: the ones src/ names, then the ones those name, transitively.
function edgeClosure() {
  const seen = new Set(); const queue = [];
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
}

export const EDGE_FNS = edgeClosure();
export const EDGE_SRC = EDGE_FNS.map(edgeSrc).join('\n/*FILE*/\n');

// Every `fn_*` string literal inside a reachable edge function is a routine that edge function can
// dispatch. Taking the literals rather than only `.rpc('...')` is deliberate: os_api dispatches its
// eighteen workspace routines through `admin.rpc(WS[action])`, and a `.rpc(` scan misses all of them.
export const ROOT_FNS = [...new Set([...EDGE_SRC.matchAll(/['"](fn_[a-z0-9_]+)['"]/g)].map(m => m[1]))].sort();
// Tables a reachable edge function reads directly through PostgREST, bypassing pg_proc entirely.
export const EDGE_TABLES = [...new Set([...EDGE_SRC.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]/g)].map(m => m[1]))].sort();

// ---- SQL literal helpers ------------------------------------------------------------------------
// Everything interpolated into a statement is either a number, a boolean, or an identifier-shaped
// token from the repository. Anything else is rejected rather than escaped, because qd_guard refuses
// a read that carries a bare write keyword and a stray token could turn a check into an ERROR — an
// unmeasured requirement, which is a worse outcome than either verdict.
const SAFE = /^[A-Za-z_$][\w$]*$/;
export const safeToken = (s) => SAFE.test(s) && !/^(insert|update|delete|drop|alter|create|grant|revoke|truncate|call|do|vacuum|reindex|comment)$/i.test(s);
export const sqlStr = (s) => `'` + String(s).replace(/'/g, `''`).replace(/\\/g, '\\\\') + `'`;
export const sqlArr = (a) => a.length ? `array[${a.map(x => `'${x}'`).join(',')}]::text[]` : `array[]::text[]`;
export const rxAlt = (a) => a.length ? `'\\y(${a.join('|')})\\y'` : null;

// ---- the UI closure over pg_proc ----------------------------------------------------------------
// One 700x700 regex join, computed once per process and memoised. Depth 6 rather than unbounded so
// the recursion terminates on a mutually-referencing pair; measured on production the set stops
// growing at depth 4.
let CACHE = null;
export async function closure(one) {
  if (CACHE) return CACHE;
  const sql = `with recursive defs as materialized (
      -- dl is the body lower-cased ONCE per routine. The edge join below is O(n^2): 1,191 routines
      -- carrying 2.9 MB of bodies means 1,417,290 ordered pairs, so folding case inside the join
      -- would lower the same 2.4 kB body 1,190 times over.
      select p.proname, pg_get_functiondef(p.oid) d, lower(pg_get_functiondef(p.oid)) dl
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
    ), edges as materialized (
      -- A CHEAP CONTAINMENT TEST IN FRONT OF THE REGEX, AND NOTHING ELSE CHANGES.
      -- Measured on production: the regex-only form produced 1,229 edges in 79.50 s, and the client
      -- aborts at QD_REQ_TIMEOUT_MS (60 s by default) — so verify_os2_blueprint.mjs died with
      -- "transport failed after 7 attempts: TimeoutError" while the database was still working, and
      -- the message named the transport for what was our own timeout. With the pre-filter the SAME
      -- 1,229 edges come back in 6.07 s.
      --
      -- THIS DOES NOT WEAKEN THE CHECK. position() is strictly implied by the word-boundary regex —
      -- anything matching \\y…\\y is necessarily a substring — so the pre-filter can only drop pairs
      -- the regex would have rejected anyway. Proved rather than argued: the two edge sets were
      -- compared with EXCEPT on production, the difference was empty, and the counts were equal.
      select distinct a.proname src, b.proname dst from defs a join defs b
        on b.proname <> a.proname
       and position(lower(b.proname) in a.dl) > 0
       and a.d ~* ('\\y'||b.proname||'\\y')
    ), reach(proname, depth) as (
      select distinct proname, 1 from defs where proname = any(${sqlArr(ROOT_FNS)})
      union
      select e.dst, r.depth+1 from reach r join edges e on e.src = r.proname where r.depth < 6
    )
    select coalesce(string_agg(distinct proname, ','), '')
        || '|' || (select count(distinct proname) from defs)::text from reach`;
  const raw = String(await one(sql) || '');
  const [names, total] = raw.split('|');
  const fns = names.split(',').filter(n => safeToken(n));
  CACHE = { fns, total: Number(total || 0), UI: sqlArr(fns) };
  return CACHE;
}

// Reachable routines that READ this relation — writers removed by pattern, overloads collapsed by
// count(distinct proname). The write keywords are split so qd_guard's read guard, which refuses any
// statement carrying a bare write keyword, does not reject the check itself.
const NOT_WRITER = (t) => `pg_get_functiondef(p.oid) !~* ('(inse'||'rt\\s+into|upd'||'ate|del'||'ete\\s+from)\\s+(public\\.)?${t}\\y')`;

export function UI_READS(C, t) {
  const direct = EDGE_TABLES.includes(t) ? 1 : 0;
  return `((select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
          and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)})
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'
        and exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid=p2.pronamespace
                    where n2.nspname='public' and p2.prokind in ('f','p') and p2.proname = any(${C.UI})
                      and pg_get_functiondef(p2.oid) ~* ('\\y'||v.viewname||'\\y')))
    + ${direct})`;
}

export function UI_READ_NAMES(C, t) {
  const direct = EDGE_TABLES.includes(t) ? `'edge:PostgREST'` : `null`;
  return `coalesce((select string_agg(distinct x, ',') from (
        select p.proname x from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
           and pg_get_functiondef(p.oid) ~* '\\y${t}\\y' and ${NOT_WRITER(t)}
        union select ${direct}) s where x is not null), 'none')`;
}

// Every routine, view or cron job that names the relation, writers included. Printed beside
// UI_READS so a MISSING verdict shows the shape of the defect: "computed by 6, reachable by 0".
export function ALL_READS(t) {
  return `((select count(distinct p.proname) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
      where ns.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')
    + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\y${t}\\y'))`;
}

// How many reachable routines name this figure? The regex comes from the FRONTEND — the keys a
// surface renders — so a non-zero answer means the name travels from the routine to the screen.
export function UI_EMITS(C, rx) {
  if (!rx) return `0`;
  return `(select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
        and pg_get_functiondef(p.oid) ~* ${rx})`;
}
export function UI_EMIT_NAMES(C, rx) {
  if (!rx) return `'none'`;
  return `coalesce((select string_agg(distinct p.proname, ',') from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p') and p.proname = any(${C.UI})
         and pg_get_functiondef(p.oid) ~* ${rx}), 'none')`;
}

// A relation that may not exist scores MISSING rather than ERRORing. An errored check is an
// UNMEASURED requirement; a false negative is merely a wrong one.
export const REL_EXISTS = (t) => `(to_regclass('public.${t}') is not null)`;
export function COUNT_IF_EXISTS(t, where = 'true') {
  return `(select case when to_regclass('public.${t}') is null then 0 else
      (xpath('/row/c/text()', query_to_xml(
        'select count(*) c from public.${t} where ${where.replace(/'/g, "''")}', false, true, '')))[1]::text::int end)`;
}

// ---- the runner's entry point -------------------------------------------------------------------
// verify_os2_blueprint.mjs computes the closure ONCE and hands it to every section module, so the
// 700x700 regex join is paid once per run rather than once per section. `routines` is the set a
// logged-in founder can cause to execute; `views` is the set of views one of those routines opens.
// A section module may use this or compute its own — the numbers are identical, and a module that
// does not depend on this file survives the file being rewritten underneath it.
export async function uiClosure(qAll, _root) {
  const sql = `with recursive defs as materialized (
      -- dl is the body lower-cased ONCE per routine. The edge join below is O(n^2): 1,191 routines
      -- carrying 2.9 MB of bodies means 1,417,290 ordered pairs, so folding case inside the join
      -- would lower the same 2.4 kB body 1,190 times over.
      select p.proname, pg_get_functiondef(p.oid) d, lower(pg_get_functiondef(p.oid)) dl
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and p.prokind in ('f','p')
    ), edges as materialized (
      -- A CHEAP CONTAINMENT TEST IN FRONT OF THE REGEX, AND NOTHING ELSE CHANGES.
      -- Measured on production: the regex-only form produced 1,229 edges in 79.50 s, and the client
      -- aborts at QD_REQ_TIMEOUT_MS (60 s by default) — so verify_os2_blueprint.mjs died with
      -- "transport failed after 7 attempts: TimeoutError" while the database was still working, and
      -- the message named the transport for what was our own timeout. With the pre-filter the SAME
      -- 1,229 edges come back in 6.07 s.
      --
      -- THIS DOES NOT WEAKEN THE CHECK. position() is strictly implied by the word-boundary regex —
      -- anything matching \\y…\\y is necessarily a substring — so the pre-filter can only drop pairs
      -- the regex would have rejected anyway. Proved rather than argued: the two edge sets were
      -- compared with EXCEPT on production, the difference was empty, and the counts were equal.
      select distinct a.proname src, b.proname dst from defs a join defs b
        on b.proname <> a.proname
       and position(lower(b.proname) in a.dl) > 0
       and a.d ~* ('\\y'||b.proname||'\\y')
    ), reach(proname, depth) as (
      select distinct proname, 1 from defs where proname = any(${sqlArr(ROOT_FNS)})
      union
      select e.dst, r.depth+1 from reach r join edges e on e.src = r.proname where r.depth < 6
    )
    select coalesce((select string_agg(distinct proname, ',') from reach), '') as fns,
           coalesce((select string_agg(distinct v.viewname, ',') from pg_views v
                      where v.schemaname='public'
                        and exists (select 1 from reach r join defs d2 on d2.proname = r.proname
                                    where d2.d ~* ('\\y'||v.viewname||'\\y'))), '') as vws,
           (select count(distinct proname) from defs)::text as total`;
  const row = (await qAll(sql))[0] || {};
  const routines = String(row.fns || '').split(',').filter(safeToken);
  const views = String(row.vws || '').split(',').filter(safeToken);
  CACHE = { fns: routines, total: Number(row.total || 0), UI: sqlArr(routines) };
  return { edgeFns: EDGE_FNS, edgeTables: EDGE_TABLES, roots: ROOT_FNS,
           routines, views, total: Number(row.total || 0), UI: sqlArr(routines) };
}

// ---- the React side -----------------------------------------------------------------------------
// A component's source, from `function Name(` to the next top-level declaration.
export function slice(name, text = SHELL) {
  const m = new RegExp('^(?:export default )?function ' + name + '\\b', 'm').exec(text);
  if (!m) return '';
  const rest = text.slice(m.index + 1);
  const nxt = /\n(?:export default )?(?:function |const [A-Z])/.exec(rest);
  return text.slice(m.index, nxt ? m.index + 1 + nxt.index : text.length);
}
export const surface = (...names) => names.map(n => slice(n)).join('\n/*NEXT*/\n');

// The payload keys a surface PUTS ON SCREEN. Two sources, and the second one is not optional:
// `const band = String(health.band || 'unknown')` followed by `{titleCase(band)}` renders the band
// without ever writing `.band` inside a JSX interpolation, and a scan of interpolations alone would
// score a figure that is plainly visible as absent.
export function renderedKeys(text) {
  const out = new Set();
  const interps = [...text.matchAll(/\{([^{}]{0,600}?)\}/g)].map(m => m[1]);
  const joined = ' ' + interps.join(' ; ') + ' ';
  const isRendered = (n) => new RegExp('(?:^|[^\\w$.])' + n + '(?![\\w$])').test(joined);
  const props = (expr) => {
    for (const k of expr.matchAll(/\.([a-zA-Z_$][\w$]*)/g)) if (safeToken(k[1])) out.add(k[1]);
    for (const k of expr.matchAll(/\[\s*['"]([\w$]+)['"]\s*\]/g)) if (safeToken(k[1])) out.add(k[1]);
  };
  for (const e of interps) if (/[.[]/.test(e)) props(e);
  for (const m of text.matchAll(/\b(?:const|let|var)\s+([a-zA-Z_$][\w$]*)\s*(?::[^=;\n]{0,80})?=\s*([^;\n]{0,300})/g)) {
    if (!/[.[]/.test(m[2]) || !isRendered(m[1])) continue;
    if (safeToken(m[1])) out.add(m[1]);
    props(m[2]);
  }
  for (const m of text.matchAll(/\b(?:const|let|var)\s*\{([^}]{0,200})\}\s*=\s*([^;\n]{0,200})/g)) {
    for (const part of m[1].split(',')) {
      const n = part.trim().split(':').pop().trim();
      if (safeToken(n) && isRendered(n)) out.add(n);
    }
  }
  return [...out].sort();
}

// A FIGURE, not a word. Both patterns must hold of the SAME key, which is what stops a sidebar label
// or an unrelated `.active` from scoring a requirement: `agents_active_24h` names the subject and the
// state in one identifier, `active` on its own names neither.
export const figures = (keys, subject, aspect) =>
  keys.filter(k => subject.test(k) && (aspect ? aspect.test(k) : true));

// The module the shell shows before the founder clicks anything.
export function defaultModule() {
  const m = /useState(?:<[^>]{0,60}>)?\(\s*'([a-z_]+)'\s*\)\s*;?\s*(?:const\s+\[tabs|\/\/)/.exec(SHELL)
    || /const\s+\[cur,\s*setCur\]\s*=\s*React\.useState(?:<[^>]{0,60}>)?\(\s*'([a-z_]+)'/.exec(SHELL);
  return m ? m[1] : '';
}
// MODULES[] as declared, so the sidebar can be counted and a module id mapped to its component kind.
export function modules() {
  const block = /const MODULES:\s*Mod\[\]\s*=\s*\[([\s\S]*?)\n\];/.exec(SHELL);
  if (!block) return [];
  return [...block[1].matchAll(/\{\s*id:\s*'([a-z_]+)'[^}]*?\}/g)].map(m => ({
    id: m[1],
    kind: (/kind:\s*'([a-z_]+)'/.exec(m[0]) || [])[1] || '',
    ws: (/ws:\s*'([a-z.]+)'/.exec(m[0]) || [])[1] || '',
    label: (/label:\s*'([^']*)'/.exec(m[0]) || [])[1] || '',
  }));
}
// id -> the component renderModule() dispatches to, read from renderModule itself rather than
// assumed, so a renamed component does not silently make a surface look empty.
export function componentFor(id) {
  const rm = slice('renderModule');
  const byKind = new RegExp("m\\.kind === '" + id + "' \\? <([A-Z]\\w+)").exec(rm);
  const byId = new RegExp("m\\.id === '" + id + "' \\? <([A-Z]\\w+)").exec(rm);
  return (byKind || byId || [])[1] || '';
}

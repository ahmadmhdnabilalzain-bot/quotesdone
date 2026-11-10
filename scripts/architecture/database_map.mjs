// THE DATABASE MAP: every routine, table and cron job production runs, filed by business area (it_engineer, 10 Nov 2026).
//
// WHY. Measured 10 Nov 2026: production's `public` schema holds 2,077 routine names, 793 tables, 88 views and 97 cron
// jobs, defined across 2,685 SQL files, with nothing an outsider could use to find "where is the refund logic". The
// founder will hand this repository to an external auditor; this map is the page that auditor opens first.
//
// WHAT IT READS, all offline, all committed:
//   * supabase/schema/full_schema/        the mirror of what production runs (routines, tables, views, cron jobs);
//   * scripts/lib/canonical_routines.mjs  the gate's own rule for which file is canonical for each routine;
//   * scripts/sql/ in canonical order     the writer_seat, cron_registry and seat_duty rows the files insert, for the
//                                         seat that owns each cron job and its human name;
//   * scripts/architecture/database_areas.mjs   which area each name belongs to.
// It never connects to anything.
//
// WHAT IT WRITES: docs/architecture/database/README.md (the index) and one page per area. The pages are generated:
// do not edit them by hand, change the areas file or the SQL and run this again.
//
//   node scripts/architecture/database_map.mjs            write the pages
//   node scripts/architecture/database_map.mjs --check    exit 1 when a name is unmapped or a page is stale
//
// scripts/checks/the_database_map_is_complete_and_current.test.mjs runs the check in npm test, so the map cannot drift,
// and scripts/checks/export_from_either_source_is_identical.mjs --write (the mirror refresh after every apply) rewrites
// the pages in the same step, so the routine apply train does not leave the map one step behind.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonicalRoutines } from '../lib/canonical_routines.mjs';
import { SCHEMA_MIRROR, readSchemaMirror } from '../lib/schema_mirror.mjs';
import { AREAS, areaOf } from './database_areas.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const OUT_DIR = 'docs/architecture/database';
const LINK_UP = '../../../';   // from docs/architecture/database/ to the repository root

// ---------------------------------------------------------------- reading SQL row inserts offline
// The owning seat of a cron job is ROW DATA (public.writer_seat, public.seat_duty), and the mirror carries no rows.
// The files that insert those rows are committed, so they are replayed here as text: every
// `insert into public.<table> (<cols>) values (...), (...)` in canonical order, later rows replacing earlier ones on
// the table's key, and the simple `delete from public.<table> where <key> = '<x>'` forms removing them. Values that
// are not plain string literals (an expression, a sub-select) are kept as null rather than guessed.

/** Every tuple of every `insert into public.<table> (...) values ...` statement: { at: statement offset, row }. */
export function insertedRows(sql, table) {
  const rows = [];
  const head = new RegExp(`insert\\s+into\\s+(?:public\\.)?${table}\\s*\\(([^)]*)\\)\\s*values\\s*`, 'gi');
  let m;
  while ((m = head.exec(sql))) {
    const cols = m[1].split(',').map((c) => c.trim().toLowerCase());
    let i = head.lastIndex;
    for (;;) {
      while (/\s/.test(sql[i] || '')) i++;
      if (sql[i] !== '(') break;
      const { values, end } = tuple(sql, i);
      rows.push({ at: m.index, row: Object.fromEntries(cols.map((c, k) => [c, values[k] ?? null])) });
      i = end;
      while (/\s/.test(sql[i] || '') || sql.startsWith('--', i)) { if (sql.startsWith('--', i)) i = sql.indexOf('\n', i) < 0 ? sql.length : sql.indexOf('\n', i); else i++; }
      if (sql[i] !== ',') break;
      i++;
    }
    head.lastIndex = i;
  }
  return rows;
}

/** One parenthesised tuple from `start`: its items as strings (string literals joined by ||) or null. */
function tuple(sql, start) {
  const items = []; let depth = 0, i = start, cur = [], plain = true;
  const flush = () => { items.push(plain && cur.length ? cur.join('') : null); cur = []; plain = true; };
  for (; i < sql.length; i++) {
    const ch = sql[i];
    if (ch === "'") {                       // a string literal, '' escaping a quote
      let j = i + 1, s = '';
      for (; j < sql.length; j++) {
        if (sql[j] === "'" && sql[j + 1] === "'") { s += "'"; j++; } else if (sql[j] === "'") break; else s += sql[j];
      }
      if (depth === 1) cur.push(s);
      i = j; continue;
    }
    if (sql.startsWith('--', i)) { i = sql.indexOf('\n', i); if (i < 0) i = sql.length; continue; }
    if (ch === '(') { depth++; if (depth > 1) plain = false; continue; }
    if (ch === ')') { depth--; if (depth === 0) { flush(); return { values: items, end: i + 1 }; } continue; }
    if (depth === 1 && ch === ',') { flush(); continue; }
    if (depth === 1 && sql.startsWith('||', i)) { i++; continue; }
    if (depth === 1 && !/\s/.test(ch)) plain = false;   // an identifier, number or call: not a plain literal
  }
  return { values: items, end: i };
}

/** `delete from public.<table> where <col> = '<x>' [and <col> = '<y>']`: { at, row } with the key values it removes. */
export function deletedKeys(sql, table) {
  const out = [];
  const re = new RegExp(`delete\\s+from\\s+(?:public\\.)?${table}\\s+where\\s+([^;]*);`, 'gi');
  for (const m of sql.matchAll(re)) {
    const conds = [...m[1].matchAll(/([a-z_]+)\s*=\s*'([^']*)'/gi)].map((c) => [c[1].toLowerCase(), c[2]]);
    if (conds.length && conds.length === (m[1].match(/=/g) || []).length) out.push({ at: m.index, row: Object.fromEntries(conds) });
  }
  return out;
}

// ---------------------------------------------------------------- the model
export function buildMap() {
  const r = canonicalRoutines(REPO.replace(/\\/g, '/'));
  const mirror = readSchemaMirror();

  // Routines production runs, with their overload count and canonical file.
  const routines = new Map();
  for (const d of r.definitionsIn(SCHEMA_MIRROR)) {
    const e = routines.get(d.name) || { name: d.name, overloads: 0 };
    e.overloads++;
    routines.set(d.name, e);
  }
  for (const e of routines.values()) {
    const c = r.canonical.get(e.name);
    e.file = c ? c.file : null;
    e.area = areaOf(e.name);
  }

  const tables = [...mirror.matchAll(/^CREATE TABLE IF NOT EXISTS public\."?([a-z0-9_]+)"?/gm)].map((m) => m[1]);
  const views = [...mirror.matchAll(/^CREATE OR REPLACE VIEW public\."?([a-z0-9_]+)"?/gm)].map((m) => m[1]);

  // The SQL files in the order they were applied (the canonical sequence), for replaying row inserts.
  const ordered = r.FILES.map((f) => ({ f, key: r.sequenceOf(f).key })).filter((x) => x.key).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)).map((x) => x.f);
  const replay = (table, keyOf) => {
    const rows = new Map();
    for (const f of ordered) {
      const sql = r.read(f) || '';
      if (!new RegExp(`(?:public\\.)?${table}\\b`, 'i').test(sql)) continue;
      // inserts and deletes in the order they appear in the file
      const events = [...insertedRows(sql, table).map((e) => ({ ...e, put: true })), ...deletedKeys(sql, table)].sort((a, b) => a.at - b.at);
      for (const e of events) {
        const k = keyOf(e.row);
        if (!k) continue;
        if (e.put) rows.set(k, { ...e.row, file: f }); else rows.delete(k);
      }
    }
    return rows;
  };
  const writerSeat = replay('writer_seat', (x) => (x.kind === 'cron_job' && x.name ? x.name : null));
  const registry = replay('cron_registry', (x) => x.jobname || null);
  const duties = replay('seat_duty', (x) => x.duty || null);

  const crons = [...mirror.matchAll(/^select cron\.schedule\('([^']+)','([^']+)',\$CRON\$([\s\S]*?)\$CRON\$\);$/gm)].map((m) => {
    const [, jobname, schedule, command] = m;
    const calls = [...command.matchAll(/public\.([a-z0-9_]+)\s*\(/g)].map((c) => c[1]);
    const duty = (jobname.match(/^seat_duty:(.+)$/) || [])[1] || null;
    const ws = writerSeat.get(jobname);
    const sd = duty ? duties.get(duty) : null;
    const seat = ws?.owner_seat || sd?.owner_seat || null;
    const seatFrom = ws?.owner_seat ? `writer_seat, ${ws.file}` : sd?.owner_seat ? `seat_duty ${duty}, ${sd.file}` : null;
    const reg = registry.get(jobname);
    // A job is filed with the routine it runs; a seat duty's job with the routine its duty runs, else its duty's words.
    const target = duty ? (sd?.routine?.replace(/^public\./, '').replace(/\(.*$/, '') || duty.replace(/^[a-z_]+\./, '')) : calls.find((c) => routines.has(c)) || calls[0] || jobname;
    const area = (routines.get(target) && routines.get(target).area) || areaOf(target) || areaOf(jobname.replace(/[^a-z0-9_]/gi, '_'));
    // A seat duty's job always calls fn_seat_duty_run('<duty>'); what it RUNS is the duty's routine.
    const runs = duty && sd?.routine ? [`${sd.routine.replace(/^public\./, '').replace(/\(.*$/, '')} (duty ${duty})`] : calls;
    return { jobname, schedule, calls: runs, seat, seatFrom, human: reg?.human_name || sd?.what || null, category: reg?.category || null, area, target };
  });

  const functions = readdirSync(join(REPO, 'supabase/functions'))
    .filter((d) => existsSync(join(REPO, 'supabase/functions', d, 'index.ts'))).sort()
    .map((d) => ({ name: d, area: areaOf(d) }));

  return {
    routines: [...routines.values()].sort((a, b) => a.name.localeCompare(b.name)),
    tables: tables.sort().map((t) => ({ name: t, kind: 'table', area: areaOf(t) })),
    views: views.sort().map((t) => ({ name: t, kind: 'view', area: areaOf(t) })),
    crons: crons.sort((a, b) => a.jobname.localeCompare(b.jobname)),
    functions,
    canonicalOnly: [...r.canonical.keys()].filter((n) => !routines.has(n)).length,
  };
}

// ---------------------------------------------------------------- the pages
const md = (s) => String(s ?? '').replace(/\|/g, '\\|');
const fileLink = (f) => (f ? `[${f}](${LINK_UP}${f})` : '**no change file** (in the mirror only)');

export function renderPages(map) {
  const pages = new Map();
  const unmapped = [...map.routines, ...map.tables, ...map.views, ...map.functions].filter((x) => !x.area).map((x) => x.name);
  const cronUnmapped = map.crons.filter((c) => !c.area).map((c) => c.jobname);
  const count = (list, slug) => list.filter((x) => x.area === slug).length;

  const index = [
    '# The database, by business area',
    '',
    '**Generated** by `node scripts/architecture/database_map.mjs` from the schema mirror (`supabase/schema/full_schema/`),',
    'the canonical-file rule (`scripts/lib/canonical_routines.mjs`, the same code the gate runs) and the committed SQL.',
    'Do not edit these pages by hand: change `scripts/architecture/database_areas.mjs` or the SQL, then run the script.',
    '`scripts/checks/the_database_map_is_complete_and_current.test.mjs` fails when a name is in no area or a page is stale.',
    '',
    'Everything lives in one Postgres schema, `public`. An area is where a reader looks, not a runtime boundary: a',
    'routine in one area may read tables in another. Areas are assigned by the words of a name (rules and the short',
    'override list in the areas file), so a routine is found by its subject even though the schema has no folders.',
    '',
    '| area | routines | tables | views | cron jobs | edge functions |',
    '|---|---:|---:|---:|---:|---:|',
    ...AREAS.map((a) => `| [${a.title}](${a.slug}.md) | ${count(map.routines, a.slug)} | ${count(map.tables, a.slug)} | ${count(map.views, a.slug)} | ${count(map.crons, a.slug)} | ${count(map.functions, a.slug)} |`),
    `| **total** | **${map.routines.length}** | **${map.tables.length}** | **${map.views.length}** | **${map.crons.length}** | **${map.functions.length}** |`,
    '',
    '## How to read a routine row',
    '',
    '- **canonical file**: the one SQL file whose definition is the real one, by the rule in',
    '  `scripts/lib/canonical_routines.mjs` (the highest of: `supabase/migrations_history`, `supabase/migrations`,',
    '  `ai-organization/db-functions`, then `scripts/sql/` in `scripts/sql/MANIFEST.txt` order). To change a routine,',
    '  edit that file, not an earlier one: an earlier definition is superseded and applying it would revert production.',
    '- **overloads**: how many argument lists production carries under that name.',
    '',
    '## How to read a cron row',
    '',
    '- **owner seat** comes from the `writer_seat` row (kind `cron_job`) or, for a `seat_duty:<duty>` job, the duty\'s',
    '  `seat_duty.owner_seat`, as the committed SQL inserts them. "not recorded in the repository" means no committed file',
    '  inserts one; `scripts/checks/every_run_label_and_cron_job_names_its_seat.test.mjs` is the production check of the same',
    '  rule. **name / category** are the job\'s `cron_registry` row.',
    '- A cron job is filed with the routine it runs.',
    '',
    `Counts measured from the mirror at generation. ${map.canonicalOnly} further routine names have a canonical file but are not in`,
    'the mirror (dropped from production on purpose, recorded in `scripts/sql/DROPPED.txt`, or applied after the mirror was',
    'taken); they are not listed here.',
    '',
    'Matching itself is mostly not SQL: the supplier choice runs in `supabase/functions/customer_api/lib/matching.ts`, which',
    'is why the Matching area holds few routines.',
    '',
  ];
  if (unmapped.length || cronUnmapped.length) index.push('## UNMAPPED', '', ...[...unmapped, ...cronUnmapped].map((n) => `- \`${n}\``), '');
  pages.set('README.md', index.join('\n'));

  for (const a of AREAS) {
    const rs = map.routines.filter((x) => x.area === a.slug);
    const ts = [...map.tables, ...map.views].filter((x) => x.area === a.slug);
    const cs = map.crons.filter((x) => x.area === a.slug);
    const fs = map.functions.filter((x) => x.area === a.slug);
    const lines = [
      `# ${a.title}`,
      '',
      `${a.about}`,
      '',
      `Generated by \`node scripts/architecture/database_map.mjs\`; see [the index](README.md) for how to read it.`,
      `${rs.length} routines, ${ts.filter((t) => t.kind === 'table').length} tables, ${ts.filter((t) => t.kind === 'view').length} views, ${cs.length} cron jobs, ${fs.length} edge functions.`,
      '',
      '## Cron jobs',
      '',
      ...(cs.length ? ['| job | schedule | runs | owner seat | name / category |', '|---|---|---|---|---|',
        ...cs.map((c) => `| \`${md(c.jobname)}\` | \`${md(c.schedule)}\` | ${c.calls.length ? c.calls.map((x) => `\`${x}\``).join(', ') : '—'} | ${c.seat ? `${c.seat}` : 'not recorded in the repository'} | ${c.human ? `${md(c.human)}${c.category ? ` / ${md(c.category)}` : ''}` : '—'} |`)]
        : ['None.']),
      '',
      '## Edge functions',
      '',
      ...(fs.length ? fs.map((f) => `- [\`${f.name}\`](${LINK_UP}supabase/functions/${f.name}/index.ts)`) : ['None.']),
      '',
      '## Tables and views',
      '',
      ...(ts.length ? [ts.map((t) => `\`${t.name}\`${t.kind === 'view' ? ' (view)' : ''}`).join(' · ')] : ['None.']),
      '',
      '## Routines',
      '',
      '| routine | overloads | canonical file |',
      '|---|---:|---|',
      ...rs.map((x) => `| \`${x.name}\` | ${x.overloads} | ${fileLink(x.file)} |`),
      '',
    ];
    pages.set(`${a.slug}.md`, lines.join('\n'));
  }
  return { pages, unmapped: [...unmapped, ...cronUnmapped] };
}

// ---------------------------------------------------------------- write or check
/** Every reason the pages in `dir` are not what `rendered` says they should be; [] when they are. */
export function checkMap(dir = join(REPO, OUT_DIR), rendered = renderPages(buildMap())) {
  const { pages, unmapped } = rendered;
  const problems = [];
  for (const n of unmapped) problems.push(`UNMAPPED  ${n}: add a word to its area's rules or a line to OVERRIDES in scripts/architecture/database_areas.mjs`);
  const onDisk = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith('.md')) : [];
  for (const [name, text] of pages) {
    const p = join(dir, name);
    if (!existsSync(p)) problems.push(`MISSING   ${OUT_DIR}/${name}`);
    else if (readFileSync(p, 'utf8') !== text) problems.push(`STALE     ${OUT_DIR}/${name}`);
  }
  for (const f of onDisk) if (!pages.has(f)) problems.push(`EXTRA     ${OUT_DIR}/${f}: no area generates it`);
  return problems;
}

/** Write the pages, removing any page no area generates. Also called after the schema mirror is refreshed. */
export function writeMap() {
  const rendered = renderPages(buildMap());
  const dir = join(REPO, OUT_DIR);
  if (existsSync(dir)) for (const f of readdirSync(dir)) if (f.endsWith('.md') && !rendered.pages.has(f)) rmSync(join(dir, f));
  mkdirSync(dir, { recursive: true });
  for (const [name, text] of rendered.pages) writeFileSync(join(dir, name), text);
  return rendered;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.includes('--check')) {
    const problems = checkMap();
    for (const p of problems) console.log(p);
    if (problems.length) console.log('\nregenerate: node scripts/architecture/database_map.mjs');
    else console.log('the database map is complete and current');
    process.exitCode = problems.length ? 1 : 0;
  } else {
    const { pages, unmapped } = writeMap();
    console.log(`wrote ${pages.size} pages to ${OUT_DIR}${unmapped.length ? `; ${unmapped.length} UNMAPPED names are listed in its README` : ''}`);
    process.exitCode = unmapped.length ? 1 : 0;
  }
}

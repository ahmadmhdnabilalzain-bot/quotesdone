// THE DAILY EXPORT'S REGISTRY, READ FROM THE SQL FILES (it_engineer, 29 Sep 2026).
//
// public.table_export_registry holds one row per public table: exported (category = subject) or excluded (category =
// why). fn_table_export_list() reads it (scripts/sql/the_daily_export_reads_a_registry_every_pull_request_adds_rows_to.sql).
// Rows arrive by INSERT in the file that creates a table, so the static checks rebuild the registry by replaying every
// `insert into public.table_export_registry ... on conflict` in apply order (MANIFEST, then pending files), later rows
// replacing earlier ones exactly as the upsert does in the database. Comments are stripped first, so the example in a
// file's header is never read as a row.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifestWithPending } from './pending_sql.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
export const EXCLUSION_CATEGORIES = ['secret', 'cache', 'log', 'measurement', 'fixture', 'no_writer'];

// A `--` inside a quoted reason is text, not a comment: cut only at a `--` with an even number of quotes before it.
const stripComments = (sql) => sql.split('\n').map((l) => {
  for (let i = l.indexOf('--'); i >= 0; i = l.indexOf('--', i + 2)) if ((l.slice(0, i).split("'").length - 1) % 2 === 0) return l.slice(0, i);
  return l;
}).join('\n');
const ROW = /\(\s*'([a-z0-9_]+)'\s*,\s*(true|false)\s*,\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'\s*\)/g;

// Rows one SQL text registers, in order: [{table, exported, category, reason, added_by}].
export function registryRowsIn(sql) {
  const out = [];
  for (const m of stripComments(sql).matchAll(/insert\s+into\s+public\.table_export_registry\b([\s\S]*?)\bon\s+conflict\b/gi)) {
    for (const r of m[1].matchAll(ROW)) {
      out.push({ table: r[1], exported: r[2] === 'true', category: r[3].replace(/''/g, "'"), reason: r[4].replace(/''/g, "'"), added_by: r[5] });
    }
  }
  return out;
}

// The registry as it will stand once every applied and pending file has run: Map table -> row (with .file).
export function readRegistry(repo = REPO) {
  const reg = new Map();
  for (const f of manifestWithPending(repo)) {
    const p = join(repo, f);
    if (!existsSync(p)) continue;
    const sql = readFileSync(p, 'utf8');
    // A table renamed or dropped takes its row with it: `delete from public.table_export_registry where table_name =
    // '<t>'` (30 Sep 2026, the judgement queue's rename). ponytail: a file's deletes are replayed before its inserts,
    // which is right for delete-old-insert-new; a file that inserts and then deletes the same table would need order.
    for (const m of stripComments(sql).matchAll(/delete\s+from\s+public\.table_export_registry\s+where\s+table_name\s*=\s*'([a-z0-9_]+)'/gi)) reg.delete(m[1]);
    for (const row of registryRowsIn(sql)) reg.set(row.table, { ...row, file: f });
  }
  return reg;
}

export function exportedTables(repo = REPO) {
  return new Set([...readRegistry(repo)].filter(([, r]) => r.exported).map(([t]) => t));
}

// THE SCHEMA MIRROR IS ELEVEN FILES, READ AS ONE (29 Sep 2026, it_engineer).
//
// public.fn_schema_export() on production is committed to the repository as the mirror of what
// production runs. Until today it was one file, supabase/schema/full_schema.sql. MEASURED from git
// history: 2,666,424 bytes on 10 Sep, 4,341,250 on 24 Sep, 5,261,945 on 29 Sep (#1073, 778da78) —
// ~137 KB a day over 19 days and ~184 KB a day over the last five. At 5,261,945 it crossed the 5 MiB
// ceiling in the_repository_root_holds_only_the_product.test.mjs, and because CI tests every PR
// merged with main, that one red test blocked every open PR.
//
// A higher ceiling for this one file would have been green for about two weeks at that rate. So the
// export is split, and the check keeps its single 5 MiB limit with no exemption. The split is by
// object kind, and FUNCTIONS (4,327,806 bytes, 82% of the export) is split again by routine name:
//
//   part                                  starts at                        bytes, split of 778da78
//   01 banner, extensions … indexes       the top                                   635,806
//   02 views                              -- ===== VIEWS =====                      156,481
//   03 functions before fn_c              -- ===== FUNCTIONS =====                  711,488
//   04 functions fn_c                     first routine named >= 'fn_c'             694,761
//   05 functions fn_d … fn_h              first routine named >= 'fn_d'             300,535
//   06 functions fn_i … fn_l              first routine named >= 'fn_i'             552,576
//   07 functions fn_m … fn_o              first routine named >= 'fn_m'             562,944
//   08 functions fn_p … fn_r              first routine named >= 'fn_p'             346,149
//   09 functions fn_s                     first routine named >= 'fn_s'             636,297
//   10 functions fn_t onwards             first routine named >= 'fn_t'             523,056
//   11 triggers, RLS, policies, cron,     -- ===== TRIGGERS =====                   141,852
//      secret key NAMES
//
// The largest part is 711,488 bytes, 13.6% of the limit: even if ALL of the ~184 KB a day landed
// in one part it would take ~24 days to reach 5 MiB, and spread as it has been, months.
//
// Letter ranges, not equal-sized chunks, so adding one routine changes one file instead of moving
// every later routine into the next file. Every cut is at the START of a line, so the parts joined
// in order are the export byte for byte, banner included: readSchemaMirror() returns exactly the
// text the single file held, and every reader that used to read the file reads this instead.
// When a part nears 5 MiB, add a boundary to PARTS (a new file, same rule); nothing else changes.
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
/** The mirror's directory, relative to the repository root. */
export const SCHEMA_MIRROR = 'supabase/schema/full_schema';
const DIR = join(REPO, SCHEMA_MIRROR);
// The single file this replaced. The writer removes it so a stale copy can never be read again.
const RETIRED_SINGLE_FILE = join(REPO, 'supabase', 'schema', 'full_schema.sql');

// `section` starts a part at that export section header; `fn` at the first routine whose name sorts
// at or after it. The export lists routines by name, so a name boundary is one contiguous cut.
export const PARTS = [
  { file: '01_extensions_sequences_tables_constraints_indexes.sql' },
  { file: '02_views.sql', section: 'VIEWS' },
  { file: '03_functions_before_fn_c.sql', section: 'FUNCTIONS' },
  { file: '04_functions_fn_c.sql', fn: 'fn_c' },
  { file: '05_functions_fn_d_to_fn_h.sql', fn: 'fn_d' },
  { file: '06_functions_fn_i_to_fn_l.sql', fn: 'fn_i' },
  { file: '07_functions_fn_m_to_fn_o.sql', fn: 'fn_m' },
  { file: '08_functions_fn_p_to_fn_r.sql', fn: 'fn_p' },
  { file: '09_functions_fn_s.sql', fn: 'fn_s' },
  { file: '10_functions_fn_t_onwards.sql', fn: 'fn_t' },
  { file: '11_triggers_rls_policies_cron_secret_names.sql', section: 'TRIGGERS' },
];

const sectionAt = (text, name) => {
  const i = text.indexOf(`\n-- ===== ${name} =====\n`);
  if (i < 0) throw new Error(`schema mirror: the export has no "-- ===== ${name} =====" section; update PARTS in scripts/lib/schema_mirror.mjs`);
  return i + 1;
};

/** Split the whole mirror text (banner + export) into PARTS. Joined in order, the parts are `text`. */
export function splitSchemaMirror(text) {
  const fnEnd = sectionAt(text, 'TRIGGERS');
  const heads = [...text.matchAll(/^CREATE OR REPLACE FUNCTION public\.("?)([A-Za-z0-9_]+)\1\(/gm)];
  const starts = [0];
  for (const p of PARTS.slice(1)) {
    const prev = starts.at(-1);
    let at;
    if (p.section) at = sectionAt(text, p.section);
    else {
      const h = heads.find((m) => m.index >= prev && m.index < fnEnd && m[2] >= p.fn);
      at = h ? h.index : fnEnd;   // no routine in this range: the part is empty, the join still holds
    }
    if (at < prev) throw new Error(`schema mirror: ${p.file} would start before the part above it`);
    starts.push(at);
  }
  return PARTS.map((p, i) => ({ file: p.file, text: text.slice(starts[i], starts[i + 1] ?? text.length) }));
}

/** Write the mirror as its parts; remove any part no longer listed and the retired single file. */
export function writeSchemaMirror(text) {
  const parts = splitSchemaMirror(text);
  if (parts.map((p) => p.text).join('') !== text) throw new Error('schema mirror: the parts do not rejoin to the export');
  mkdirSync(DIR, { recursive: true });
  const keep = new Set(PARTS.map((p) => p.file));
  for (const f of readdirSync(DIR)) if (f.endsWith('.sql') && !keep.has(f)) rmSync(join(DIR, f));
  for (const p of parts) writeFileSync(join(DIR, p.file), p.text);
  if (existsSync(RETIRED_SINGLE_FILE)) rmSync(RETIRED_SINGLE_FILE);
  return parts.map((p) => ({ file: `${SCHEMA_MIRROR}/${p.file}`, bytes: Buffer.byteLength(p.text) }));
}

/** The whole mirror as one text, exactly as the single file held it. Throws if a part is missing
 *  or an unlisted part is present — a partial read would certify a routine that is not there. */
export function readSchemaMirror() {
  const want = PARTS.map((p) => p.file);
  const have = existsSync(DIR) ? readdirSync(DIR).filter((f) => f.endsWith('.sql')) : [];
  const missing = want.filter((f) => !have.includes(f));
  const extra = have.filter((f) => !want.includes(f));
  if (missing.length || extra.length) {
    throw new Error(`schema mirror ${SCHEMA_MIRROR} is not the ${want.length} listed parts: `
      + `missing [${missing.join(', ')}], unlisted [${extra.join(', ')}]. Regenerate with `
      + 'node scripts/checks/export_from_either_source_is_identical.mjs --write');
  }
  return want.map((f) => readFileSync(join(DIR, f), 'utf8')).join('');
}

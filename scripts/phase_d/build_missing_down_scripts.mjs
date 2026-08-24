// Writes a down script for every Phase D migration classified EXPLICIT_DOWN_REQUIRED that has none.
//
//   node scripts/phase_d/build_missing_down_scripts.mjs [--write]
//
// Without --write it lists what it would produce and writes nothing.
//
// WHAT THIS DOES AND DOES NOT CLAIM. It reverses the additive DDL it can name: a created table, a
// created index, trigger, view or type, an added column and an added constraint. Each generated
// file names every object it drops, never uses `cascade`, and refuses to run when the target is
// already gone. It CANNOT restore a routine that its source file dropped, and it says so in the
// header of any file where that applies, because a `drop function` is reversed by re-applying the
// file that defined it and this program does not know which file that was.
//
// A generated down script is a starting point a person reads before running, exactly as
// scripts/sql/down/README.md already requires of the hand-written ones. It is committed because
// "MISSING" in the rollback classification is worse: it reads as an absence of risk rather than an
// absence of a plan.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { FILES, classify, introducedBy } from './build_migration_rollback_classification.mjs';

const WRITE = process.argv.includes('--write');
const DIR = 'scripts/sql';

const stripBodies = (s) => s.replace(/\$([A-Za-z_][A-Za-z0-9_]*)?\$[\s\S]*?\$\1?\$/g, ' $BODY$ ');
const statements = (s) => stripBodies(s)
  .split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
  .split(';').map(x => x.replace(/\s+/g, ' ').trim()).filter(Boolean);

function reversals(sql) {
  const out = [];
  for (const raw of statements(sql)) {
    const s = raw.toLowerCase();
    let m;
    if ((m = s.match(/^create table (?:if not exists )?([a-z0-9_.]+)/)))
      out.push({ what: `table ${m[1]}`, down: `drop table if exists ${m[1]};` });
    else if ((m = s.match(/^create (?:unique )?index (?:concurrently )?(?:if not exists )?([a-z0-9_.]+) on ([a-z0-9_.]+)/)))
      out.push({ what: `index ${m[1]} on ${m[2]}`, down: `drop index if exists ${m[1].includes('.') ? m[1] : 'public.' + m[1]};` });
    else if ((m = s.match(/^create (?:or replace )?(?:constraint )?trigger ([a-z0-9_]+) .* on ([a-z0-9_.]+)/)))
      out.push({ what: `trigger ${m[1]} on ${m[2]}`, down: `drop trigger if exists ${m[1]} on ${m[2]};` });
    else if ((m = s.match(/^create (?:or replace )?view ([a-z0-9_.]+)/)))
      out.push({ what: `view ${m[1]}`, down: `drop view if exists ${m[1]};` });
    else if ((m = s.match(/^create type ([a-z0-9_.]+)/)))
      out.push({ what: `type ${m[1]}`, down: `drop type if exists ${m[1]};` });
    else if ((m = s.match(/^alter table (?:if exists )?(?:only )?([a-z0-9_.]+) (.*)$/))) {
      const table = m[1];
      for (const part of m[2].split(/,\s*(?=add )/)) {
        let a;
        if ((a = part.match(/^add column (?:if not exists )?([a-z0-9_]+)/)))
          out.push({ what: `column ${table}.${a[1]}`, down: `alter table ${table} drop column if exists ${a[1]};` });
        else if ((a = part.match(/^add constraint ([a-z0-9_]+)/)))
          out.push({ what: `constraint ${a[1]} on ${table}`, down: `alter table ${table} drop constraint if exists ${a[1]};` });
      }
    }
    else if ((m = s.match(/^drop function ([a-z0-9_.]+)/)))
      out.push({ what: `ROUTINE DROPPED BY THE SOURCE FILE: ${m[1]}`, down: null });
  }
  return out;
}

const missing = FILES.map(classify).filter(r => r.down_script === 'MISSING');
let written = 0;
for (const r of missing) {
  const stem = r.file.replace(/\.sql$/, '');
  const rev = reversals(readFileSync(`${DIR}/${r.file}`, 'utf8'));
  // A routine no other Phase D file defines was INTRODUCED here, and dropping it is the only
  // reversal there is — re-applying a predecessor cannot restore what had none.
  for (const fn of introducedBy(r.file)) {
    rev.push({ what: `routine ${fn.name}(${fn.args}) — introduced by this file`,
               down: `drop function if exists ${fn.name}(${fn.args});` });
  }
  const dropable = rev.filter(x => x.down);
  const unrestorable = rev.filter(x => !x.down);
  if (!dropable.length && !unrestorable.length) { console.log(`SKIP  ${r.file} — nothing this program can reverse`); continue; }

  // Objects are dropped in reverse creation order: a trigger before the table it sits on, a
  // constraint before the column it constrains.
  const body = dropable.slice().reverse();
  if (!dropable.length) {
    console.log(`SKIP  ${r.file} — the only reversal is a dropped routine, which this program cannot restore`);
    continue;
  }
  const firstTable = (dropable.find(x => x.what.startsWith('table ')) || {}).what;
  const guardOn = firstTable ? firstTable.slice(6)
    : (dropable.map(x => x.down.match(/on ([a-z0-9_.]+);/) || x.down.match(/alter table ([a-z0-9_.]+)/))
        .find(Boolean) || [])[1];

  const text = `-- =================================================================================================
-- PHASE D DOWN — reverses the additive DDL of
-- ${DIR}/${r.file}
--
-- NEVER RUN AUTOMATICALLY. Nothing in this repository invokes scripts/sql/down/: no npm script, no
-- check under scripts/checks/, no GitHub workflow, no apply_sql or --promote path. This file is a
-- hand-run rollback. A person opens it, reads the block below, accepts it, and runs it.
--
-- GENERATED 23 Aug 2026 by scripts/phase_d/build_missing_down_scripts.mjs, because the rollback
-- classification reported this file as EXPLICIT_DOWN_REQUIRED with no down script. It reverses the
-- named objects below and nothing else; read it before running it.
--
-- OBJECTS DROPPED, by name (never \`cascade\`):
${dropable.map(x => `--   ${x.what}`).join('\n') || '--   (none)'}
--
-- ROW COUNT AT RISK: dropping a column discards that column's values on every row of the table and
-- dropping a table discards all of its rows. Neither is measured here -- count them on
-- htdblwldjkcgjvmqkbeh immediately before running this file, and do not run it if the count
-- surprises you.
--
-- NOT TOUCHED: every \`create or replace function\` in the source file. A create-or-replace has no
-- down -- see scripts/sql/down/README.md; the predecessor body is restored by re-applying the file
-- that defined it, and every later file in that routine's chain, in order.
${unrestorable.length ? `--\n-- THIS PROGRAM CANNOT REVERSE:\n${unrestorable.map(x => `--   ${x.what} — restored only by re-applying the file that defined it`).join('\n')}` : ''}
--
-- NO TRANSACTION CONTROL. This file carries no BEGIN and no COMMIT of its own, deliberately: every
-- transport in this repository sends the whole file as ONE simple-query batch, and a multi-statement
-- batch with no explicit BEGIN is one implicit transaction in Postgres. So the file is still atomic,
-- AND it can be rehearsed inside \`begin; … rollback;\` without committing.
--
-- This generator emitted \`begin;\`/\`commit;\` until 24 Aug 2026, and 39 of the 67 self-committing
-- down scripts in scripts/sql/down/ came from here. A caller who wraps a self-committing file runs
-- ITS commit inside their block and their trailing rollback has nothing to undo: the independent
-- acceptance audit of 24 Aug 2026 deployed phase_d_d10, d18, d32 and k09 against production that
-- way while believing it was rehearsing. Rehearse with scripts/phase_c/rehearse_one.mjs, which
-- strips any wrapper it finds and refuses to report success unless the run raised.
-- =================================================================================================

${guardOn ? `do $pre$
begin
  if to_regclass('${guardOn}') is null then
    raise exception '${stem} down: ${guardOn} does not exist; there is nothing here to revert.';
  end if;
end $pre$;` : '-- Nothing to guard on: this file introduced routines and created no relation.'}

${body.map(x => x.down).join('\n')}
`;
  console.log(`${WRITE ? 'WRITE' : 'WOULD'} ${DIR}/down/${stem}_down.sql  (${dropable.length} object(s)${unrestorable.length ? `, ${unrestorable.length} unrestorable` : ''})`);
  if (WRITE) { writeFileSync(`${DIR}/down/${stem}_down.sql`, text); written++; }
}
console.log(`\n${missing.length} file(s) had no down script; ${WRITE ? written + ' written' : 'nothing written (pass --write)'}`);
if (WRITE) {
  const still = FILES.map(classify).filter(r => r.down_script === 'MISSING');
  console.log(`still missing after this run: ${still.length}`);
  for (const s of still) console.log(`  ${s.file}  (${s.additive_ddl})`);
}

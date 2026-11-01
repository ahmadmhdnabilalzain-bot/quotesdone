#!/usr/bin/env node
// A MERGED SQL FILE APPLIES ITSELF (it_engineer, 2 Nov 2026, founder ledger 1463: "Yes, automatic").
// Every line added to scripts/sql/MANIFEST.txt since <from-sha> is rehearsed whole, applied, read back and probed, in order. The
// first failure stops the rest and opens one ceo task, because the founder does not watch workflows and fn_it_detect resolves any
// it_watch_finding it did not emit itself. <from-sha> is the last successful run's commit, so a run GitHub dropped from the queue
// is covered by the next one.
//   node scripts/ci/apply_new_manifest_lines.mjs <from-sha> <after-sha>
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** The files a diff of MANIFEST.txt adds, in order. A removed line, a comment and a probe (never applied) are not an apply. */
export function addedFiles(diff) {
  return diff.split('\n').filter((l) => /^\+scripts\/sql\/\S+\.sql\s*$/.test(l) && !/_probe\.sql\s*$/.test(l)).map((l) => l.slice(1).trim());
}
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });

async function stop(what, after) {
  const { sql } = await import('../lib/db.mjs');
  const title = `A merged SQL file did not apply: ${what}`.replace(/'/g, "''");
  const why = `Workflow "A merged SQL file applies itself" stopped at commit ${after.replace(/[^0-9a-f]/g, '')}. Later files were not applied. Read the run, fix the file by PR.`;
  await sql(`select public.fn_ceo_task_open('${title}', '${why}')`);
  console.error('STOPPED at ' + what + '; later files were not applied.');
  process.exit(1);
}

async function main([from, after]) {
  let files;
  try {
    files = addedFiles(execFileSync('git', ['diff', from, after, '--', 'scripts/sql/MANIFEST.txt'], { encoding: 'utf8' }));
  } catch (e) {
    await stop('the MANIFEST diff itself', after);
  }
  console.log(files.length ? 'to apply:\n  ' + files.join('\n  ') : 'nothing new in MANIFEST');
  for (const file of files) {
    const probe = file.replace(/\.sql$/, '_probe.sql');
    const probeArgs = existsSync(probe) ? [probe] : [];
    try {
      run('node', ['scripts/ci/rehearse_sql.mjs', file, ...probeArgs]);
      run('node', ['scripts/apply_sql.mjs', file, '--apply', '--ddl']);
      if (probeArgs.length) run('node', ['scripts/ci/rehearse_sql.mjs', 'scripts/ci/noop.sql', probe]);
    } catch (e) {
      await stop(file, after);
    }
  }
}
if (import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));

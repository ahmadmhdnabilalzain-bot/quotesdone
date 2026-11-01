#!/usr/bin/env node
// A MERGED SQL FILE APPLIES ITSELF (it_engineer, 2 Nov 2026, founder ledger 1459: "Yes, automatic").
// Every line a push adds to scripts/sql/MANIFEST.txt is rehearsed whole, applied, read back and probed, in order. The first
// failure stops the rest and files one it_engineer finding, because the founder does not watch workflows.
//   node scripts/ci/apply_new_manifest_lines.mjs <before-sha> <after-sha>
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** The files a diff of MANIFEST.txt adds, in order. A removed or comment line is not an apply. */
export function addedFiles(diff) {
  return diff.split('\n').filter((l) => /^\+scripts\/sql\/\S+\.sql\s*$/.test(l)).map((l) => l.slice(1).trim());
}
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });

async function main([before, after]) {
  const diff = execFileSync('git', ['diff', before, after, '--', 'scripts/sql/MANIFEST.txt'], { encoding: 'utf8' });
  const files = addedFiles(diff);
  console.log(files.length ? 'to apply:\n  ' + files.join('\n  ') : 'nothing new in MANIFEST');
  for (const file of files) {
    const probe = file.replace(/\.sql$/, '_probe.sql');
    const probeArgs = existsSync(probe) ? [probe] : [];
    try {
      run('node', ['scripts/ci/rehearse_sql.mjs', file, ...probeArgs]);
      run('node', ['scripts/apply_sql.mjs', file, '--apply', '--ddl']);
      if (probeArgs.length) run('node', ['scripts/ci/rehearse_sql.mjs', 'scripts/ci/noop.sql', probe]);
    } catch (e) {
      const { sql } = await import('../lib/db.mjs');
      const title = `A merged SQL file did not apply: ${file}`.replace(/'/g, "''");
      await sql(`insert into public.it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
        values ('release:apply_new_manifest_lines', 'release', 'apply_sql', 'failed', 'high', '${title}',
                jsonb_build_object('sha', '${after.replace(/[^0-9a-f]/g, '')}'))
        on conflict (detector_key) do update set state = excluded.state, severity = excluded.severity, title = excluded.title,
          evidence = excluded.evidence, last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null`);
      console.error('STOPPED at ' + file + '; later files were not applied.');
      process.exit(1);
    }
  }
}
if (import.meta.url === pathToFileURL(process.argv[1]).href) await main(process.argv.slice(2));

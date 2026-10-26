// THE SAFE DEPENDENCY PATCH (IT engineer duty 23; founder, 14 Sep 2026: "add all for accountant and IT").
//
// Runs after scripts/it/report_dependency_audit.mjs in .github/workflows/it-weekly-readings.yml. That
// script is the scan and the report (duty 12, public.fn_it_dependency_ingest); this one is the patch:
//   1. `npm audit fix --package-lock-only --ignore-scripts --omit=dev` - never --force, so no major
//      version moves, and the same --omit=dev the audit reads;
//   2. kept only when the advisory count falls AND `npm ci` and `npm run typecheck` pass on the new lock;
//   3. pushed as a branch and opened as a pull request. NOTHING HERE MERGES IT: every pull request gets
//      an independent review. A PR opened with the workflow's own token does not start CI (GitHub's
//      rule), so the reviewer runs the checks.
// Whatever happens is recorded with public.fn_it_duty_ran('dependency_patch', ...). A patch that could
// not be made is a report, not a failed job; only a failure to record exits non-zero. No model call.
//
//   node scripts/it/open_dependency_patch_pr.mjs            try, open the PR, record
//   node scripts/it/open_dependency_patch_pr.mjs --dry-run  say what it would do; change and write nothing
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const run = (cmd, args) => spawnSync(cmd, args, {
  cwd: REPO, encoding: 'utf8', shell: process.platform === 'win32', maxBuffer: 64 * 1024 * 1024,
});

// npm audit --json (npm 7+) states its own total; the package list is the fallback.
export function advisoryCount(report) {
  const t = Number(report?.metadata?.vulnerabilities?.total);
  if (Number.isFinite(t)) return t;
  return Object.keys(report?.vulnerabilities ?? {}).length;
}

function audit() {
  const r = run('npm', ['audit', '--json', '--omit=dev']);
  try {
    const j = JSON.parse(r.stdout);
    if (j.error) return { error: 'npm audit: ' + String(j.error.summary || j.error.code).slice(0, 200) };
    return { count: advisoryCount(j), fixable: Object.values(j.vulnerabilities ?? {}).some((v) => v?.fixAvailable) };
  } catch { return { error: 'npm audit printed no JSON: ' + String(r.stderr || '').slice(0, 200) }; }
}

function attempt(dry) {
  const git = (...a) => run('git', a);
  const before = audit();
  if (before.error) return { error: before.error };
  if (!before.count) return { skipped: 'npm audit reports no advisory', before: 0 };
  if (!before.fixable) return { skipped: 'no advisory has a fix npm can apply', before: before.count };
  if (dry) return { skipped: 'dry run', before: before.count };
  const fix = run('npm', ['audit', 'fix', '--package-lock-only', '--ignore-scripts', '--omit=dev']);
  if (fix.status === null) return { error: 'npm audit fix did not run: ' + String(fix.error?.message || '').slice(0, 200) };
  if (git('diff', '--quiet', '--', 'package-lock.json').status === 0) return { skipped: 'npm audit fix changed nothing without --force', before: before.count };
  const revert = (why, after) => { git('checkout', '--', 'package-lock.json'); return { skipped: why, before: before.count, after }; };
  const after = audit();
  if (after.error) return revert('the patched lockfile could not be audited: ' + after.error, null);
  if (!(after.count < before.count)) return revert(`the fix did not lower the advisory count (${before.count} -> ${after.count})`, after.count);
  if (run('npm', ['ci', '--ignore-scripts']).status !== 0) return revert('npm ci failed on the patched lockfile', after.count);
  if (run('npm', ['run', 'typecheck']).status !== 0) return revert('the TypeScript build failed on the patched lockfile', after.count);
  const branch = `it-engineer/dependency-patch-${new Date().toISOString().slice(0, 10)}`;
  for (const a of [['checkout', '-b', branch], ['add', 'package-lock.json'],
                   ['commit', '-m', `it_engineer: npm audit fix, lockfile only (${before.count} -> ${after.count} advisories)`],
                   ['push', '-u', 'origin', branch]]) {
    const r = git(...a);
    if (r.status !== 0) return { error: `git ${a[0]} failed: ${String(r.stderr).slice(0, 200)}`, before: before.count, after: after.count };
  }
  const body = [
    'The IT engineer\'s weekly dependency readings (duty 23) found npm advisories with a fix npm applies without `--force`.',
    '', `- advisories before: ${before.count}`, `- advisories after: ${after.count}`,
    '- change: `package-lock.json` only (`npm audit fix --package-lock-only --ignore-scripts --omit=dev`)',
    '- checked before opening: `npm ci` and `npm run typecheck` pass on the patched lockfile',
    '', 'NEVER MERGED AUTOMATICALLY. Every pull request gets an independent review before it merges.',
    'A pull request opened with the workflow token does not start CI, so the reviewer runs the checks.',
    '', 'Seat: it_engineer',
  ].join('\n');
  const pr = run('gh', ['pr', 'create', '--base', 'main', '--head', branch,
    '--title', `it_engineer: dependency patch (${before.count} -> ${after.count} advisories)`, '--body', body]);
  if (pr.status !== 0) return { error: 'gh pr create failed: ' + String(pr.stderr).slice(0, 200), branch, before: before.count, after: after.count };
  const url = String(pr.stdout).trim().split('\n').pop();
  return { number: Number(url.match(/\/pull\/(\d+)/)?.[1]) || null, url, branch, before: before.count, after: after.count };
}

async function main() {
  const dry = process.argv.includes('--dry-run');
  const result = attempt(dry);
  console.log('dependency patch:', JSON.stringify(result));
  if (dry) return;
  const { sql, lit } = await import('../lib/db.mjs');
  await sql(`select public.fn_it_duty_ran('dependency_patch', ${lit(JSON.stringify(result))}::jsonb)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();

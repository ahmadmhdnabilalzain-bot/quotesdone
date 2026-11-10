// IT-C15 (it_engineer, ledger 1003 stage 2): the weekly audit of .github/workflows, handed to
// public.fn_it_workflow_audit_ingest, which opens a finding per file per rule and closes it when the file is fixed.
// Run by .github/workflows/it-weekly-readings.yml. Rules (SHA pins; least privilege; one runner policy):
//   runner          every runs-on is ubuntu-latest (the founder's ledger 1410, 28 Oct 2026, moved all 35 workflows
//                   there) or the older ${{ vars.RUNNER || 'ubicloud-standard-N' }} form; a bare Ubicloud label or
//                   any other runner is still reported
//   unpinned_action every `uses:` of a remote action names a 40-hex commit SHA
//   permissions     the workflow declares a top-level permissions block
//   write_all       no permissions: write-all
//   secret_in_log   no run line echoes/prints a ${{ secrets.* }} expression
//
//   node scripts/it/workflow_audit.mjs            # report to production
//   node scripts/it/workflow_audit.mjs --dry      # print only
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const RUNNER = /^(?:ubuntu-latest|\$\{\{ vars\.RUNNER \|\| 'ubicloud-standard-\d+' \}\})$/;

export function auditWorkflow(file, text) {
  const out = [];
  const add = (rule, message, lines) => out.push({ file, rule, message, lines });
  const lines = text.split(/\r?\n/);
  const at = (re) => lines.flatMap((l, i) => (re.test(l) ? [i + 1] : []));

  const badRunner = lines.flatMap((l, i) => {
    const m = l.match(/^\s*runs-on:\s*(.+?)\s*$/);
    return m && !RUNNER.test(m[1].replace(/^["']|["']$/g, '')) ? [i + 1] : [];
  });
  if (badRunner.length) add('runner', "runs-on is not ubuntu-latest (or ${{ vars.RUNNER || 'ubicloud-standard-N' }})", badRunner);

  const unpinned = lines.flatMap((l, i) => {
    const m = l.match(/^\s*(?:-\s*)?uses:\s*["']?([^\s"'#]+)/);
    if (!m || m[1].startsWith('./') || m[1].startsWith('docker://')) return [];
    return /@[0-9a-f]{40}$/.test(m[1]) ? [] : [i + 1];
  });
  if (unpinned.length) add('unpinned_action', `${unpinned.length} action(s) not pinned to a commit SHA`, unpinned);

  if (!lines.some((l) => /^permissions:/.test(l))) add('permissions', 'no top-level permissions block (the token gets the repository default)', []);
  const wa = at(/permissions:\s*write-all/);
  if (wa.length) add('write_all', 'permissions: write-all', wa);

  const leak = at(/\b(echo|printf|cat)\b.*\$\{\{\s*secrets\./);
  if (leak.length) add('secret_in_log', 'a secret expression is printed by a run step', leak);
  return out;
}

export function auditDir(dir = '.github/workflows') {
  const files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f));
  return { files: files.length, violations: files.flatMap((f) => auditWorkflow(f, readFileSync(join(dir, f), 'utf8'))) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const report = auditDir();
  if (process.argv.includes('--dry')) { console.log(JSON.stringify(report, null, 1)); process.exit(0); }
  const { sql, lit } = await import('../lib/db.mjs');
  const [r] = await sql(`select public.fn_it_workflow_audit_ingest(${lit(JSON.stringify(report))}::jsonb) r`);
  console.log(`workflow audit: ${report.files} files, ${report.violations.length} violations ->`, JSON.stringify(r.r));
}

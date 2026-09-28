// A PRODUCTION WRITE SHIPS ONLY REVIEWED CODE (28 Sep 2026, it_engineer).
//
// apply_sql.mjs --apply and deploy_functions.mjs --production could write a file from any branch,
// red or never pushed. This refuses unless every path is byte-identical to origin/main, OR the
// current branch's PR has every CI check finished and green. The escape is
// --skip-release-guard="<reason>": the reason is printed, so the apply's own log carries it.
// A CI run on a push to main is main by definition (the deploy workflow's checkout is shallow).
import { execFileSync } from 'node:child_process';

const OK = new Set(['SUCCESS', 'SKIPPED', 'NEUTRAL']);
// QD_GH_CMD: a node script standing in for gh (the test's mock). Unset, the real gh runs.
const gh = (args) => process.env.QD_GH_CMD
  ? execFileSync(process.execPath, [process.env.QD_GH_CMD, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  : execFileSync('gh', args, { encoding: 'utf8' });
const git = (args) => { try { execFileSync('git', args, { stdio: 'ignore' }); return true; } catch { return false; } };
// On main = the path exists on origin/main and the working copy does not differ from it.
const onMain = (p) => {
  const rel = p.replace(/\\/g, '/').replace(/^\.\//, '');
  return git(['cat-file', '-e', `origin/main:${rel}`]) && git(['diff', '--quiet', 'origin/main', '--', rel]);
};

// Returns null when the write may go ahead, otherwise the reason it may not.
export function releaseRefusal(paths, argv = process.argv) {
  const skip = argv.find((a) => a.startsWith('--skip-release-guard'));
  if (skip) {
    const reason = skip.split('=').slice(1).join('=').trim();
    if (!reason) return '--skip-release-guard needs a reason: --skip-release-guard="<why>"';
    console.error(`RELEASE GUARD SKIPPED: ${reason}`);
    return null;
  }
  if (process.env.GITHUB_ACTIONS === 'true' && process.env.GITHUB_REF === 'refs/heads/main') return null;
  const off = paths.filter((p) => !onMain(p));
  if (!off.length) return null;
  let checks;
  try { checks = JSON.parse(gh(['pr', 'view', '--json', 'number,statusCheckRollup'])).statusCheckRollup || []; }
  catch { return `${off.join(', ')} not on origin/main and no PR found for this branch`; }
  if (!checks.length) return `${off.join(', ')} not on origin/main and its PR has no CI checks yet`;
  // A Vercel status carries `state`, a check run `conclusion`; neither yet = still running.
  const bad = checks.filter((c) => !OK.has(String(c.conclusion || c.state || 'PENDING').toUpperCase()));
  if (bad.length) return `${off.join(', ')} not on origin/main and its PR has ${bad.length} check(s) not green: ${bad.map((c) => c.name || c.context).join(', ')}`;
  return null;
}

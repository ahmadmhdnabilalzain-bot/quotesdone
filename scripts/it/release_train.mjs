#!/usr/bin/env node
// THE RELEASE TRAIN (it_engineer, 29 Sep 2026). Founder: a release agent that runs ALL the time,
// not tied to a chat session. Code, not a model. Run by .github/workflows/release-train.yml every
// 10 minutes and on every check completion; one run releases at most ONE pull request.
//
// Each run:
//   1. DRIFT FIRST. canonical_routine_manifest.mjs against production; every canonical file whose
//      body is not deployed is applied (apply_sql.mjs --apply --ddl), then the check runs again.
//   2. PICK the oldest open PR into main that has every check green, is mergeable, carries
//      `review-approved` (the review agent's label: an independent review before every merge) or is
//      a Dependabot minor/patch bump, has no `hold` / `release-failed` label, and whose every
//      "Depends-on: #N" is merged.
//   3. MERGE it (squash), then on main: apply each pending SQL file the PR added (in the order its
//      notes give: a note that names another of the PR's files runs after it), run each probe the PR
//      added, delete the applied notes, append their MANIFEST lines, regenerate the schema mirror,
//      deploy the edge functions the PR changed, and push that bookkeeping as one commit.
//      A failed apply reverts nothing: it opens an it_engineer finding and labels the PR
//      `release-failed`, so the train never retries it blind.
//   4. CAMPAIGN HOURS: a file marked `apply-window: off-hours` is never applied inside them; a PR
//      carrying one waits for the next off-hours run (an apply locked sign-in once, 21 Sep 2026).
//
//   node scripts/it/release_train.mjs [--dry-run] [--pr=N]
//   --dry-run   evaluates and prints every decision; merges, applies, deploys and pushes nothing
//   --pr=N      consider only PR N (the dry-run test against a ZZ PR)
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, unlinkSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const REF = 'htdblwldjkcgjvmqkbeh';
const GREEN = new Set(['SUCCESS', 'SKIPPED', 'NEUTRAL']);

// ---------------------------------------------------------------- pure decisions (tested)

export function dependsOn(body = '') {
  const out = [];
  for (const line of body.matchAll(/^[ \t>*-]*Depends-on:(.*)$/gim))
    for (const n of line[1].matchAll(/#(\d+)/g)) out.push(Number(n[1]));
  return [...new Set(out)];
}

// Grouped bumps are titled "... the npm-minor-and-patch group ..."; single ones "from X.Y.Z to A.B.C".
// Below 1.0 a minor bump is breaking by semver, so 0.x must keep its minor too.
export function isDependabotMinorPatch(pr) {
  if (!/dependabot/i.test(pr.author?.login || '')) return false;
  if (/minor-and-patch/i.test(pr.title)) return true;
  const m = pr.title.match(/from v?(\d+)\.(\d+)\S* to v?(\d+)\.(\d+)/i);
  return !!m && m[1] === m[3] && (m[1] !== '0' || m[2] === m[4]);
}

// THE CHECKS A MERGE NEEDS, BY NAME (29 Sep 2026). "Every check present is green" merged #998 and #992
// minutes after the train updated their branches: the new head carried only Vercel's statuses, because
// GitHub Actions had not yet created its check runs, so nothing present was red. A check that has not
// started is not a pass. Each of these must be present and green (a skipped kernel gate on a PR without
// the label counts, as it is SKIPPED, not absent).
export const REQUIRED_CHECKS = [
  'classification, pricing and refund checks',
  'the database is running what this repository says',
  'typecheck the app',
  'typecheck the edge functions',
  'lint migrations for locking operations',
  'the kernel and handler gate, against production',
];
// ONE ENTRY PER CHECK: THE LATEST (29 Sep 2026). A head that ran a workflow twice (a push, then the
// `labeled` event) carries both runs in statusCheckRollup: #1095 showed the database check CANCELLED
// (superseded) and SUCCESS side by side, and the train refused it for ever. GitHub's own view (`gh pr
// checks`) keeps the latest; so does this. A check still running has no completedAt and counts as latest.
export function latestChecks(rollup = []) {
  const at = (c) => (c.completedAt && !c.completedAt.startsWith('0001') ? c.completedAt : '9999') + (c.startedAt || '');
  const byName = new Map();
  for (const c of rollup) {
    const k = c.name || c.context;
    if (!byName.has(k) || at(c) > at(byName.get(k))) byName.set(k, c);
  }
  return [...byName.values()];
}

export function checksGreen(rollup = [], required = REQUIRED_CHECKS) {
  const latest = latestChecks(rollup);
  const names = new Set(latest.map((c) => c.name || c.context));
  return latest.length > 0
    && required.every((n) => names.has(n))
    && latest.every((c) => GREEN.has(String(c.conclusion || c.state || 'PENDING').toUpperCase()));
}

// A check still running: no conclusion yet (a check run), or a status still PENDING (Vercel and friends).
export function checksRunning(rollup = []) {
  return latestChecks(rollup).some((c) => /^(PENDING|EXPECTED|QUEUED|IN_PROGRESS|WAITING)$/i.test(String(c.conclusion || c.state || 'PENDING')));
}

// THE ONE STALE PR TO REFRESH (29 Sep 2026). A reviewed PR's production checks compare its branch with the
// live database, so every merge to main turns the others red until they are updated. When nothing can be
// released, the oldest reviewed PR whose only blocker is its checks - finished, not green, and its branch
// behind main - is updated, and the tick ends; a later tick releases it once green. One PR at a time, never
// a sweep: sixty updates at once jammed Actions for hours on 28 Sep.
export function staleCandidate(prs, { depState = () => 'MERGED', isBehind = () => false } = {}) {
  // every other gate must already pass: judged as if its checks were green
  return prs.find((pr) => !checksGreen(pr.statusCheckRollup) && !checksRunning(pr.statusCheckRollup)
    && refusal({ ...pr, statusCheckRollup: REQUIRED_CHECKS.map((name) => ({ name, conclusion: 'SUCCESS' })) }, { depState }) === null
    && (missingChecks(pr.statusCheckRollup).length > 0
      || (onlyStaleFailures(pr.statusCheckRollup) && isBehind(pr)))) || null;
}

// The checks that read the LIVE database compare it with the branch, so a merge to main turns them red on
// every other PR: only these are refreshed by an update. A PR failing anything else (a unit check, a
// typecheck, the lint) is failing on its own code; updating it changes nothing, and picking it every tick
// starved the rest of the queue (29 Sep 2026: #1056, red on its own tests, was updated tick after tick).
export const STALE_PRONE = new Set(['the database is running what this repository says', 'the kernel and handler gate, against production']);
export function onlyStaleFailures(rollup = []) {
  const bad = latestChecks(rollup).filter((c) => !GREEN.has(String(c.conclusion || c.state || 'PENDING').toUpperCase()));
  return bad.length > 0 && bad.every((c) => STALE_PRONE.has(c.name || c.context));
}

// The required checks that never started on this head (a GITHUB_TOKEN push starts no workflow).
export function missingChecks(rollup = [], required = REQUIRED_CHECKS) {
  const names = new Set(latestChecks(rollup).map((c) => c.name || c.context));
  return required.filter((n) => !names.has(n));
}

// ponytail: one fixed Dubai window (UTC+4, no DST), weekdays and weekends alike; move it to a
// table if campaigns ever get their own calendar. RELEASE_CAMPAIGN_HOURS="08-20" overrides.
export function inCampaignHours(now = new Date(), window = process.env.RELEASE_CAMPAIGN_HOURS || '08-20') {
  const [from, to] = window.split('-').map(Number);
  const h = (now.getUTCHours() + 4) % 24;
  return from <= to ? h >= from && h < to : h >= from || h < to;
}

export const offHoursOnly = (sqlText = '') => /apply-window:\s*off-hours/i.test(sqlText);
export const isProbeNote = (note = '') => /^\s*A PROBE\b/.test(note);
// A *_probe.sql file is a probe whatever its note says (4 Oct 2026, #1149): its note was empty, the train APPLIED the
// probe before the definitions it tests, the probe failed and the merge was left unapplied.
export const isProbe = (x) => isProbeNote(x.note) || /_probe\.sql$/.test(x.sql || '');

// entries: [{ sql: 'scripts/sql/x.sql', note }].
// 1. A note may carry a line `apply-order: N`. When any note does, entries sort by N (none = last),
//    then by name.
// 2. Otherwise a note that names another entry's file runs after it - unless it says it runs BEFORE
//    that file ("applied BEFORE b.sql"), the reverse relation (#1070's marketing note). Name order
//    breaks ties; a cycle falls back to name order for what is left.
export const noteOrder = (note = '') => {
  const m = note.match(/^\s*apply-order:\s*(\d+)/im);
  return m ? Number(m[1]) : null;
};
const escRe = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const saysBefore = (note, file) => new RegExp(`\\bbefore\\s+\\W?(?:scripts/sql/)?${escRe(file)}`, 'i').test(note);

export function applyOrder(entries) {
  const byName = [...entries].sort((a, b) => a.sql.localeCompare(b.sql));
  if (byName.some((e) => noteOrder(e.note) !== null)) {
    const n = (e) => noteOrder(e.note) ?? Infinity;
    return byName.sort((a, b) => n(a) - n(b));
  }
  const base = (p) => p.split('/').pop();
  // e must wait for o
  const needs = (e, o) => (e.note.includes(base(o.sql)) && !saysBefore(e.note, base(o.sql)))
    || saysBefore(o.note, base(e.sql));
  const left = byName, out = [];
  while (left.length) {
    const i = left.findIndex((e) => !left.some((o) => o !== e && needs(e, o)));
    out.push(...left.splice(i < 0 ? 0 : i, 1));
  }
  return out;
}

// A REFUSED MERGE ENDS THE TICK, NOT THE TRAIN (30 Sep 2026). #1141's squash was refused by GitHub
// ("without workflows permission"); gh threw, the run crashed, and every later tick picked #1141 again,
// blocking the queue. A failed merge now opens a finding and labels the PR release-failed, so refusal()
// skips it on the next tick.
export function mergeOrFlag(pr, { merge, finding, label }) {
  try { merge(); return true; } catch (e) {
    finding(pr, 'merge', `${e.stderr || ''}${e.stdout || ''}${e.message || e}`);
    label(pr);
    return false;
  }
}

// Returns null when the PR may be released now, otherwise why not.
export function refusal(pr, { depState = () => 'MERGED', campaign = false, offHoursFiles = [] } = {}) {
  const labels = (pr.labels || []).map((l) => l.name);
  if (pr.isDraft) return 'draft';
  if (pr.baseRefName && pr.baseRefName !== 'main') return `base is ${pr.baseRefName}, not main`;
  if (labels.includes('hold')) return 'labelled hold';
  if (labels.includes('release-failed')) return 'labelled release-failed';
  // #1141, 30 Sep 2026: the train's GitHub App token has no `workflows` permission, so GitHub refuses a
  // squash that touches .github/workflows/. Skip it up front; a person merges it.
  if ((pr.files || []).some((f) => f.path?.startsWith('.github/workflows/'))) return 'needs a human merge: workflow files';
  if (!labels.includes('review-approved') && !isDependabotMinorPatch(pr)) return 'no review-approved label';
  if (pr.mergeable !== 'MERGEABLE') return `mergeable is ${pr.mergeable}`;
  if (!checksGreen(pr.statusCheckRollup)) return 'checks not all green';
  const open = dependsOn(pr.body).filter((n) => depState(n) !== 'MERGED');
  if (open.length) return `depends on unmerged ${open.map((n) => '#' + n).join(', ')}`;
  if (campaign && offHoursFiles.length) return `campaign hours; off-hours file(s) ${offHoursFiles.join(', ')}`;
  return null;
}

// Files named in the REPOSITORY -> PRODUCTION section of canonical_routine_manifest.mjs.
// A RETRY FOR A LOCK, AND ONLY FOR A LOCK (29 Sep 2026: #1105's apply died on a transient 40P01 and the
// release stopped). Retried only when the error is a deadlock (40P01) or a lock not available (55P03), the
// file is ONE transaction (apply_sql sends the whole file in one request, so without an explicit
// BEGIN/COMMIT a failure rolls back everything), a read-back shows every routine the file defines still
// has its pre-apply body, and the file's apply window is still open. At most 3 attempts, 5/15/45 s with
// jitter. Any other error stops the release as before; the deploy still waits for a successful apply.
export const RETRYABLE = /\b(40P01|55P03)\b/;
export function isOneTransaction(sqlText = '') {
  const code = sqlText.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  if (/^\s*(begin|commit|start\s+transaction|rollback)\s*;/im.test(code)) return false;
  // Statements that cannot run inside a transaction block, or commit on their own: a failure around them
  // is not a clean rollback, so no retry (coordinator, 29 Sep 2026).
  return !/\bconcurrently\b|\bvacuum\b|\balter\s+system\b|\balter\s+type\b[\s\S]*?\badd\s+value\b|\bcreate\s+database\b|\bdrop\s+database\b|\breindex\b[\s\S]*?\bconcurrently\b/i.test(code);
}
export function routinesIn(sqlText = '') {
  // public. is optional, as apply_sql.mjs treats it
  return [...new Set([...sqlText.matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?(\w+)\s*\(/gi)].map((m) => m[1].toLowerCase()))];
}
export const BACKOFF_MS = [5000, 15000, 45000];
export async function applyWithRetry({ apply, sqlText, snapshot, windowOpen = () => true, sleep, log = () => {}, jitter = () => 0.8 + Math.random() * 0.4 }) {
  let attempts = 0, last = null;
  const before = snapshot();
  while (attempts < 3) {
    attempts++;
    last = apply();
    if (!last.code) return { ok: true, attempts, last };
    if (!RETRYABLE.test(last.out)) { log(`apply failed with a non-lock error: no retry`); break; }
    // apply_sql prints 'applied <file> to <ref>' only once the database accepted the file: a failure after
    // that (a read-back DIFFERS, a PROBE FAILED) is not a rolled-back apply, whatever else the output says.
    if (/^applied \S+ to \S+/m.test(last.out)) { log('the database accepted the file before the error: no retry'); break; }
    if (!isOneTransaction(sqlText)) { log('lock error, but the file is not one transaction: no retry'); break; }
    if (snapshot() !== before) { log('lock error, but the routines no longer match their pre-apply bodies: no retry'); break; }
    if (attempts >= 3) { log('lock error on the third attempt: giving up'); break; }
    if (!windowOpen()) { log('lock error, and the apply window has closed: the next tick retries'); break; }
    const wait = Math.round(BACKOFF_MS[attempts - 1] * jitter());
    log(`lock error (${(last.out.match(RETRYABLE) || [])[1]}): rolled back, retry ${attempts + 1} of 3 in ${wait} ms`);
    await sleep(wait);
  }
  return { ok: false, attempts, last };
}

export function driftFiles(report = '') {
  const at = report.indexOf('REPOSITORY -> PRODUCTION drift');
  if (at < 0) return [];
  const section = report.slice(at).split(/\n(?=[A-Z][A-Z ]{6,})/)[0];
  return [...new Set([...section.matchAll(/\[([^\]\s]+\.sql)\]/g)].map((m) => m[1]))];
}

// ---------------------------------------------------------------- side effects

const run = (cmd, args, opts = {}) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 64 << 20, ...opts });
  return { code: r.status ?? 1, out: `${r.stdout || ''}${r.stderr || ''}` };
};
const gh = (args) => execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 64 << 20 });
const git = (args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
const node = (args) => run(process.execPath, args);
const log = (s) => console.log(s);

function sqlLit(s) { return `$qd$${String(s).replace(/\$qd\$/g, '')}$qd$`; }

// The live bodies of the named routines, as one digest; the read-back that proves a failed apply rolled back.
function liveRoutineDigest(names) {
  if (!names.length) return 'no routines';
  const dir = mkdtempSync(join(tmpdir(), 'release-train-'));
  const f = join(dir, 'digest.sql');
  writeFileSync(f, `select coalesce(md5(string_agg(pg_get_functiondef(p.oid), '|' order by p.proname, p.oid::regprocedure::text)), 'none') as d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any (array[${names.map(sqlLit).join(',')}]::text[]);`);
  const r = node(['scripts/qsql.mjs', f, `--ref=${REF}`]);
  // qsql prints a one-column, one-row result bare (its `--` lines are retry notes); anything else is unparsed
  // and never equal to the snapshot, so it never licenses a retry.
  const line = r.out.split(/\r?\n/).map((l) => l.trim()).find((l) => /^([0-9a-f]{32}|none)$/.test(l));
  return r.code ? `unreadable:${Date.now()}` : (line ?? `unparsed:${Date.now()}`);
}

function openFinding(pr, file, output) {
  const dir = mkdtempSync(join(tmpdir(), 'release-train-'));
  const f = join(dir, 'finding.sql');
  writeFileSync(f, `select public.fn_it_engineer_finding_upsert(
    ${sqlLit(`release_train:#${pr.number}:${file}`)},
    ${sqlLit(`Release train: ${file} failed after #${pr.number} merged`)},
    ${sqlLit(file)}, 'internal', 0,
    jsonb_build_object('pr', ${pr.number}, 'output', ${sqlLit(output.slice(-3000))}),
    '{}'::text[], array['nothing was reverted; the PR is labelled release-failed']::text[], 'it_engineer');`);
  const r = node(['scripts/qsql.mjs', f, `--ref=${REF}`]);
  log(r.code === 0 ? `finding opened for ${file}` : `COULD NOT OPEN FINDING: ${r.out}`);
}

// DRIFT IS REPORTED, NEVER REPAIRED (29 Sep 2026, ruling of the release coordinator). A repair applied
// the canonical file of a main that was already stale while an operator was between merge and apply,
// reverting fn_ceo_root_cause_applies and resurrecting superseded bodies. Drift now opens an
// it_engineer finding and the train releases nothing on that tick; a person repairs it in MANIFEST order.
function drift(DRY) {
  const files = driftFiles(node(['scripts/checks/canonical_routine_manifest.mjs', '--all']).out);
  log(`drift: ${files.length} canonical file(s) not deployed${files.length ? ': ' + files.join(', ') : ''}`);
  if (files.length && !DRY) openFinding({ number: 0 }, 'drift', `canonical files not deployed on main: ${files.join(', ')}`);
  return files;
}

export function prSql(pr, oid) {
  const at = (p) => { try { return git(['show', `${oid}:${p}`]); } catch { return ''; } };
  const notes = (pr.files || []).map((f) => f.path).filter((p) => /^scripts\/sql\/pending\/[^/]+\.txt$/.test(p));
  return notes.map((n) => {
    const sql = n.replace('/pending/', '/').replace(/\.txt$/, '.sql');
    return { noteFile: n, sql, note: at(n), text: at(sql) };
  }).filter((e) => e.note || e.text);
}

export async function main(argv = process.argv.slice(2)) {
  const DRY = argv.includes('--dry-run') || process.env.RELEASE_TRAIN_DRY_RUN === 'true';
  const only = Number((argv.find((a) => a.startsWith('--pr=')) || '').slice(5)) || null;
  const campaign = inCampaignHours();
  log(`release train ${DRY ? '(DRY RUN) ' : ''}- campaign hours: ${campaign}`);

  if (drift(DRY).length) { log('drift on main: releasing nothing this tick'); return 1; }

  const fields = 'number,title,author,labels,createdAt,body,mergeable,statusCheckRollup,files,isDraft,baseRefName,headRefOid,headRefName';
  let prs = JSON.parse(gh(['pr', 'list', '--state', 'open', '--base', 'main', '--limit', '200', '--json', fields]));
  if (only) prs = prs.filter((p) => p.number === only);
  prs.sort((a, b) => a.createdAt.localeCompare(b.createdAt));

  const states = new Map();
  const depState = (n) => {
    if (!states.has(n)) { try { states.set(n, JSON.parse(gh(['pr', 'view', String(n), '--json', 'state'])).state); } catch { states.set(n, 'UNKNOWN'); } }
    return states.get(n);
  };

  let chosen = null, entries = [];
  for (const pr of prs) {
    let why = refusal(pr, { depState }), e = [];
    if (!why && !chosen) {   // only a PR that could go is fetched and read for its SQL
      run('git', ['fetch', '-q', 'origin', `pull/${pr.number}/head`]);
      e = prSql(pr, pr.headRefOid);
      why = refusal(pr, { depState, campaign, offHoursFiles: e.filter((x) => offHoursOnly(x.text)).map((x) => x.sql) });
    }
    log(`#${pr.number} ${why ? 'skip: ' + why : 'ELIGIBLE'}  - ${pr.title.slice(0, 90)}`);
    if (!why && !chosen) { chosen = pr; entries = e; }
  }
  if (!chosen) {
    const isBehind = (pr) => {
      run('git', ['fetch', '-q', 'origin', 'main', `pull/${pr.number}/head`]);
      return run('git', ['merge-base', '--is-ancestor', 'origin/main', pr.headRefOid]).code !== 0;
    };
    const stale = staleCandidate(prs, { depState, isBehind });
    if (!stale) { log('nothing to release'); return 0; }
    const behind = isBehind(stale);
    log(`nothing to release; #${stale.number} ${behind ? 'is behind main' : 'has required checks that never ran'}: ${DRY ? 'DRY RUN would ' : ''}${behind ? 'update its branch and ' : ''}start its CI`);
    if (!DRY) {
      if (behind) {
        const r = run('gh', ['pr', 'update-branch', String(stale.number)]);
        log(r.out.trim());
      } else {
        // A push made with GITHUB_TOKEN (this train's update-branch) leaves the PR's workflow runs in
        // 'action_required', waiting for approval (29 Sep 2026: twelve PRs sat with only Vercel's statuses).
        // Approve the waiting runs on this head; they then run as pull_request runs and attach to the PR.
        let runs = [];
        try { runs = JSON.parse(run('gh', ['run', 'list', '--branch', stale.headRefName, '--limit', '20',
          '--json', 'databaseId,conclusion,headSha']).out || '[]'); } catch { log('could not list runs'); }
        for (const w of runs.filter((x) => x.conclusion === 'action_required' && x.headSha === stale.headRefOid)) {
          const d = run('gh', ['api', '-X', 'POST', `repos/{owner}/{repo}/actions/runs/${w.databaseId}/approve`]);
          log(`approved run ${w.databaseId} on #${stale.number} -> exit ${d.code}`);
        }
      }
    }
    return 0;
  }

  const applies = applyOrder(entries.filter((x) => !isProbe(x) && x.text));
  const probes = entries.filter((x) => isProbe(x) && x.text);
  log(`release #${chosen.number}: apply [${applies.map((x) => x.sql).join(', ')}] probe [${probes.map((x) => x.sql).join(', ')}]`);
  if (DRY) { log(`DRY RUN would merge #${chosen.number} (squash), apply, probe, append MANIFEST, regenerate the mirror, deploy changed functions`); return 0; }

  git(['fetch', '-q', 'origin', 'main']);
  const base = git(['rev-parse', 'origin/main']);
  const merged = mergeOrFlag(chosen, {
    merge: () => gh(['pr', 'merge', String(chosen.number), '--squash', '--match-head-commit', chosen.headRefOid]),
    finding: openFinding,
    label: (p) => run('gh', ['pr', 'edit', String(p.number), '--add-label', 'release-failed']),
  });
  if (!merged) { log(`merge of #${chosen.number} refused: labelled release-failed; the next tick moves on`); return 1; }
  git(['fetch', '-q', 'origin', 'main']);
  // Apply only onto the merge just made: main's tip must BE that merge commit, or another release is
  // in flight and this tick stops before writing anything to production.
  const mergeOid = JSON.parse(gh(['pr', 'view', String(chosen.number), '--json', 'mergeCommit'])).mergeCommit?.oid;
  const tip = git(['rev-parse', 'origin/main']);
  if (!mergeOid || tip !== mergeOid) {
    log(`main's tip ${tip.slice(0, 7)} is not #${chosen.number}'s merge ${String(mergeOid).slice(0, 7)}: nothing applied`);
    openFinding(chosen, 'merge-tip', `main moved past the merge before its SQL was applied (tip ${tip}, merge ${mergeOid})`);
    run('gh', ['pr', 'edit', String(chosen.number), '--add-label', 'release-failed']);
    return 1;
  }
  git(['reset', '-q', '--hard', mergeOid]);
  log(`merged #${chosen.number}; main ${base.slice(0, 7)} -> ${git(['rev-parse', '--short', 'HEAD'])}`);

  let failed = null;
  const manifest = 'scripts/sql/MANIFEST.txt';
  for (const x of applies) {
    const names = routinesIn(x.text);
    const res = await applyWithRetry({
      apply: () => node(['scripts/apply_sql.mjs', x.sql, '--apply', '--ddl']),
      sqlText: x.text,
      snapshot: () => liveRoutineDigest(names),
      windowOpen: () => !(inCampaignHours() && offHoursOnly(x.text)),
      sleep: (ms) => new Promise((ok) => setTimeout(ok, ms)),
      log,
    });
    const r = res.last;
    log(`apply ${x.sql} -> exit ${r.code}${res.attempts > 1 ? ` after ${res.attempts} attempts` : ''}`);
    if (!res.ok) { log(r.out.slice(-3000)); failed = { file: x.sql, out: r.out }; break; }
    if (existsSync(x.noteFile)) unlinkSync(x.noteFile);
    const m = readFileSync(manifest, 'utf8');
    writeFileSync(manifest, m + (m.endsWith('\n') ? '' : '\n') + x.sql + '\n');
  }
  if (!failed) for (const p of probes) {
    const r = node(['scripts/qsql.mjs', p.sql, `--ref=${REF}`]);
    const ok = /PROBE OK/.test(r.out) && !/PROBE FAILED/.test(r.out);
    log(`probe ${p.sql} -> ${ok ? 'PROBE OK' : 'FAILED'}`);
    if (!ok) { log(r.out.slice(-3000)); failed = { file: p.sql, out: r.out }; break; }
  }
  if (failed) {
    openFinding(chosen, failed.file, failed.out);
    run('gh', ['pr', 'edit', String(chosen.number), '--add-label', 'release-failed']);
  }
  if (applies.length) log(`schema mirror -> exit ${node(['scripts/checks/export_from_either_source_is_identical.mjs', '--write']).code}`);
  // NO DEPLOY AFTER A FAILED APPLY (29 Sep 2026). #1050's SQL failed (42501) and the train deployed its new
  // think.ts anyway, so every importer called a routine signature the database did not have. Code that
  // depends on SQL ships only when that SQL is live; a failed release leaves the functions as they were.
  if (failed) log('an apply or probe failed: changed functions are NOT deployed');
  else {
    const dep = node(['scripts/deploy_functions.mjs', `--ref=${REF}`, '--production', '--changed', `--base=${base}`]);
    log(`deploy changed functions -> exit ${dep.code}\n${dep.out.slice(-2000)}`);
    if (dep.code) { failed = { file: 'supabase/functions', out: dep.out }; openFinding(chosen, 'deploy_functions', dep.out); run('gh', ['pr', 'edit', String(chosen.number), '--add-label', 'release-failed']); }
  }

  run('git', ['add', '--', manifest, 'scripts/sql/pending', 'supabase/schema']);
  if (run('git', ['diff', '--cached', '--quiet']).code) {
    git(['-c', 'user.name=it_engineer release train', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
      'commit', '-q', '-m', `it_engineer: release train - #${chosen.number} applied, MANIFEST and mirror recorded`]);
    if (run('git', ['push', '-q', 'origin', 'HEAD:main']).code) {   // main moved: replay the bookkeeping on top once
      git(['pull', '-q', '--rebase', 'origin', 'main']);
      git(['push', '-q', 'origin', 'HEAD:main']);
    }
    log('bookkeeping pushed to main');
  }
  // A merge made with GITHUB_TOKEN starts no push workflow, so main's own CI never ran on a train merge
  // (29 Sep 2026: #961, #993, #1060, #998, #992). The train dispatches it; workflow_dispatch works with the token.
  for (const wf of ['checks.yml', 'project-parity.yml']) {
    const r = run('gh', ['workflow', 'run', wf, '--ref', 'main']);
    log(`dispatched ${wf} on main -> exit ${r.code}`);
  }
  return failed ? 1 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) process.exit(await main());

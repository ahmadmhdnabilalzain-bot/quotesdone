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

export function checksGreen(rollup = []) {
  return rollup.length > 0
    && rollup.every((c) => GREEN.has(String(c.conclusion || c.state || 'PENDING').toUpperCase()));
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

// entries: [{ sql: 'scripts/sql/x.sql', note }]. A note that names another entry's file runs after
// it; otherwise name order. A cycle falls back to name order for what is left.
export function applyOrder(entries) {
  const left = [...entries].sort((a, b) => a.sql.localeCompare(b.sql));
  const base = (p) => p.split('/').pop();
  const out = [];
  while (left.length) {
    const i = left.findIndex((e) => !left.some((o) => o !== e && e.note.includes(base(o.sql))));
    out.push(...left.splice(i < 0 ? 0 : i, 1));
  }
  return out;
}

// Returns null when the PR may be released now, otherwise why not.
export function refusal(pr, { depState = () => 'MERGED', campaign = false, offHoursFiles = [] } = {}) {
  const labels = (pr.labels || []).map((l) => l.name);
  if (pr.isDraft) return 'draft';
  if (pr.baseRefName && pr.baseRefName !== 'main') return `base is ${pr.baseRefName}, not main`;
  if (labels.includes('hold')) return 'labelled hold';
  if (labels.includes('release-failed')) return 'labelled release-failed';
  if (!labels.includes('review-approved') && !isDependabotMinorPatch(pr)) return 'no review-approved label';
  if (pr.mergeable !== 'MERGEABLE') return `mergeable is ${pr.mergeable}`;
  if (!checksGreen(pr.statusCheckRollup)) return 'checks not all green';
  const open = dependsOn(pr.body).filter((n) => depState(n) !== 'MERGED');
  if (open.length) return `depends on unmerged ${open.map((n) => '#' + n).join(', ')}`;
  if (campaign && offHoursFiles.length) return `campaign hours; off-hours file(s) ${offHoursFiles.join(', ')}`;
  return null;
}

// Files named in the REPOSITORY -> PRODUCTION section of canonical_routine_manifest.mjs.
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

function drift(DRY, campaign) {
  const check = () => node(['scripts/checks/canonical_routine_manifest.mjs', '--all']);
  const first = check();
  const files = driftFiles(first.out);
  log(`drift: ${files.length} canonical file(s) not deployed${files.length ? ': ' + files.join(', ') : ''}`);
  let applied = 0;
  for (const f of files) {
    if (!existsSync(f)) { log(`  ${f}: not on disk, skipped`); continue; }
    if (campaign && offHoursOnly(readFileSync(f, 'utf8'))) { log(`  ${f}: off-hours file, campaign hours, skipped`); continue; }
    if (DRY) { log(`  DRY RUN would apply ${f}`); continue; }
    const r = node(['scripts/apply_sql.mjs', f, '--apply', '--ddl']);
    log(`  apply ${f} -> exit ${r.code}`); if (r.code) log(r.out.slice(-2000)); else applied++;
  }
  if (applied) log(`drift re-check: ${driftFiles(check().out).length} file(s) still not deployed`);
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

  drift(DRY, campaign);

  const fields = 'number,title,author,labels,createdAt,body,mergeable,statusCheckRollup,files,isDraft,baseRefName,headRefOid';
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
  if (!chosen) { log('nothing to release'); return 0; }

  const applies = applyOrder(entries.filter((x) => !isProbeNote(x.note) && x.text));
  const probes = entries.filter((x) => isProbeNote(x.note) && x.text);
  log(`release #${chosen.number}: apply [${applies.map((x) => x.sql).join(', ')}] probe [${probes.map((x) => x.sql).join(', ')}]`);
  if (DRY) { log(`DRY RUN would merge #${chosen.number} (squash), apply, probe, append MANIFEST, regenerate the mirror, deploy changed functions`); return 0; }

  git(['fetch', '-q', 'origin', 'main']);
  const base = git(['rev-parse', 'origin/main']);
  gh(['pr', 'merge', String(chosen.number), '--squash', '--match-head-commit', chosen.headRefOid]);
  git(['fetch', '-q', 'origin', 'main']);
  git(['reset', '-q', '--hard', 'origin/main']);
  log(`merged #${chosen.number}; main ${base.slice(0, 7)} -> ${git(['rev-parse', '--short', 'HEAD'])}`);

  let failed = null;
  const manifest = 'scripts/sql/MANIFEST.txt';
  for (const x of applies) {
    const r = node(['scripts/apply_sql.mjs', x.sql, '--apply', '--ddl']);
    log(`apply ${x.sql} -> exit ${r.code}`);
    if (r.code) { log(r.out.slice(-3000)); failed = { file: x.sql, out: r.out }; break; }
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
  const dep = node(['scripts/deploy_functions.mjs', `--ref=${REF}`, '--production', '--changed', `--base=${base}`]);
  log(`deploy changed functions -> exit ${dep.code}\n${dep.out.slice(-2000)}`);
  if (dep.code && !failed) { failed = { file: 'supabase/functions', out: dep.out }; openFinding(chosen, 'deploy_functions', dep.out); run('gh', ['pr', 'edit', String(chosen.number), '--add-label', 'release-failed']); }

  run('git', ['add', '--', manifest, 'scripts/sql/pending', 'supabase/schema']);
  if (run('git', ['diff', '--cached', '--quiet']).code) {
    git(['-c', 'user.name=it_engineer release train', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
      'commit', '-q', '-m', `it_engineer: release train - #${chosen.number} applied, MANIFEST and mirror recorded`]);
    git(['push', '-q', 'origin', 'HEAD:main']);
    log('bookkeeping pushed to main');
  }
  return failed ? 1 : 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) process.exit(await main());

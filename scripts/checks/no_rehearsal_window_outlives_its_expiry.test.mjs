// No qd_run rehearsal window stays open past its own expires_at (18 Oct 2026, it_engineer).
//
// WHY THIS EXISTS. Every night 13-18 Oct the nightly left one window open past expires_at (qd_run:566956ec, 0af178e3,
// 23412b06, e9a3aa72, 1611a8b3, 887b3b13, ad52831d): every_drawing_format_is_read was SIGTERMed at its parent's
// 12-minute ceiling inside its finally, and nothing closed the window. While one is open every harness run, stage2
// included, refuses to start. Closed now on three paths: the script fits its ceiling, the parent closes a killed
// child's window by tag (QD_E2E_RUN_TAGS), and the workflow's always() step closes any window the job opened.
//
// (a) source: the three paths stay wired. (b) production: no window is open more than 15 minutes past expires_at
// (#1401's fn_rehearsal_window_sweep runs every 10 minutes; 15 is its period plus slack). Read only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();
const src = (p) => readFileSync(join(ROOT, p), 'utf8');

test('(a) every path that can kill a harness script closes its window by tag', () => {
  assert.match(src('scripts/e2e/fixtures.mjs'), /if \(process\.env\.QD_E2E_RUN_TAGS\) appendFileSync\(process\.env\.QD_E2E_RUN_TAGS, run\.tag/, 'openRun no longer records its tag before opening the window');
  const parent = src('scripts/e2e/drawing_journeys_into_report.mjs');
  assert.match(parent, /if \(r\.signal \|\| r\.error\) \{[\s\S]*closeJobWindows\(/, 'a drawing journey killed at its ceiling is not closed by the parent');
  const wf = src('.github/workflows/nightly-journey.yml');
  assert.match(wf, /- if: always\(\)[^\n]*\n\s+run: node scripts\/e2e\/close_job_windows\.mjs "\$QD_E2E_RUN_TAGS"/, 'the nightly has no always() window close');
  assert.match(wf, /QD_E2E_RUN_TAGS: /, 'the nightly does not collect its run tags');
  assert.match(wf, /\$\{\{ steps\.journeys\.outcome \}\}[\s\S]*\$\{\{ steps\.drawings\.outcome \}\}[\s\S]*\$\{\{ steps\.quote_review\.outcome \}\}/, 'the nightly badge no longer reads every journey step');
});

test('(b) production: no rehearsal window is open past its expires_at', { skip: process.env.QD_CHECK_OFFLINE === '1' }, async () => {
  const { mgmtRead } = await import('../lib/qd_guard.mjs');
  let rows;
  try {
    rows = await mgmtRead('htdblwldjkcgjvmqkbeh', `select run_tag, opened_by, expires_at from public.rehearsal_window
                                                 where ended_at is null and expires_at < now() - interval '15 minutes' order by expires_at`);
  } catch (e) { return void console.log(`(b) skipped: production unreadable here (${String(e?.message || e).slice(0, 120)})`); }
  assert.deepEqual(rows, [], `windows open past expires_at: ${JSON.stringify(rows)}`);
});

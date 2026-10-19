// scripts/e2e/close_job_windows.mjs — tear down and close every rehearsal window THIS job opened that is still open.
// Assigned: it_engineer.
//
// WHY (18 Oct 2026, run 39079803518). Every night 13-18 Oct one qd_run window stayed open past its expires_at:
// a drawing journey was killed at its parent's ceiling before closeRun's finally ran, and an open window makes
// every harness run (stage2 included) refuse to start. fixtures.openRun writes each tag to $QD_E2E_RUN_TAGS before
// it opens the window; this script reads that file and, for each tag whose window is still open, runs the
// harness's own teardown by that exact tag and closes the window. Tags it did not open are never touched.
//
//   node scripts/e2e/close_job_windows.mjs <tags file>
import { existsSync, readFileSync } from 'node:fs';
import { read } from './fixtures.mjs';
import { newRun, teardown, closeRehearsalWindow, q } from '../lib/demo_factory.mjs';

export async function closeJobWindows(file) {
  if (!file || !existsSync(file)) return [];
  const tags = [...new Set(readFileSync(file, 'utf8').split(/\s+/).filter((t) => /^[a-z0-9]{4,16}$/.test(t)))];
  if (!tags.length) return [];
  const open = (await read(`select substring(run_tag from 5) tag from public.rehearsal_window
                             where ended_at is null and run_tag in (${tags.map((t) => q('qd_run:' + t)).join(',')})`)).map((r) => r.tag);
  const out = [];
  for (const tag of open) {
    let summary;
    try { summary = (await teardown(newRun({ tag, quiet: true }))).summary; } catch (e) { summary = 'teardown failed: ' + String(e?.message || e).slice(0, 200); }
    await closeRehearsalWindow(tag);   // closed even when teardown failed: the nightly sweep removes fixtures of a closed run
    out.push({ tag, summary });
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('close_job_windows.mjs')) {
  process.env.QD_FIXTURES = '1';
  const closed = await closeJobWindows(process.argv[2]);
  for (const c of closed) console.log(`::warning::closed rehearsal window qd_run:${c.tag} its own process left open (${c.summary})`);
  console.log(`${closed.length} window(s) this job left open were closed`);
  process.exit(0);
}

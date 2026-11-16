// scripts/archive/e2e/wait_for_no_open_window.mjs — wait until no rehearsal window is open, so a run that refuses to
// start beside another harness run (stage2.mjs, "no other harness run is open") waits for its quiet moment instead.
// Assigned: it_engineer. A window past its expires_at is a run that is over and does not count (the same rule as stage2).
//
//   node scripts/archive/e2e/wait_for_no_open_window.mjs <max minutes, default 120>
// Exit 0 when none is open; exit 1 when the limit passes first (the caller must not start). Reads only.
import { read } from '../../e2e/fixtures.mjs';

const MAX_MIN = Number(process.argv[2] || 120);
if (!Number.isFinite(MAX_MIN) || MAX_MIN <= 0) { console.error('REFUSED: max minutes must be a positive number'); process.exit(2); }

export async function openWindows() {
  return read(`select run_tag, opened_by, expires_at from public.rehearsal_window where ended_at is null and expires_at > now() order by expires_at`);
}

if (process.argv[1]?.endsWith('wait_for_no_open_window.mjs')) {
  process.env.QD_FIXTURES = '1';
  const until = Date.now() + MAX_MIN * 60_000;
  for (;;) {
    const w = await openWindows();
    console.log(`${new Date().toISOString()} open rehearsal windows: ${w.length}${w.length ? ` (latest expiry ${w[w.length - 1].expires_at})` : ''}`);
    if (!w.length) { console.log('quiet: none open'); process.exit(0); }
    if (Date.now() + 60_000 > until) { console.error(`NOT QUIET after ${MAX_MIN} minutes: ${w.length} open`); process.exit(1); }
    await new Promise((r) => setTimeout(r, 60_000));
  }
}

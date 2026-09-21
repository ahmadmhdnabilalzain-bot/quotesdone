// scripts/e2e/launch_path.mjs — the hourly launch-path probes, run by hand (21 Sep 2026, it_engineer).
//
//   node scripts/e2e/launch_path.mjs          # prints one line per probe; exit 1 if any failed twice
//
// The SAME probes the heartbeat runs every hour (resilience_ping step `launchpath`): this imports
// supabase/functions/_shared/launch_path.ts directly (Node 24 strips the types), so there is one list of
// probes and two callers, never a second harness that drifts. What each probe asserts, and why none of
// them can reach a person or write a row, is in that file's header.
//
// It only READS: it never raises or closes the finding. The heartbeat owns duty:launch_path:down, and a
// laptop run settling it would close a finding on a reading taken from somewhere the campaign is not.
import { probeLaunchPath } from '../../supabase/functions/_shared/launch_path.ts';

// The public anon key, as the site ships it (src/lib/supaEnv.ts): the probes are what a signed-out
// visitor's browser sends.
const src = (await import('node:fs')).readFileSync(new URL('../../src/lib/supaEnv.ts', import.meta.url), 'utf8');
const anon = process.env.QD_ANON_KEY || (src.match(/'(eyJ[\w-]+\.[\w-]+\.[\w-]+)'/) || [])[1];
if (!anon) { console.error('no anon key: set QD_ANON_KEY'); process.exit(2); }

const r = await probeLaunchPath(anon);
for (const x of r.results) {
  console.log(`${x.ok ? 'PASS' : 'FAIL'} ${x.id.padEnd(34)} HTTP ${String(x.status).padEnd(3)} ${String(x.ms).padStart(5)} ms${x.retried ? ' (retried)' : ''}${x.why ? ' — ' + x.why : ''}`);
}
console.log(`${r.ok ? 'LAUNCH PATH OK' : 'LAUNCH PATH BROKEN'}: ${r.results.length - r.failed.length}/${r.results.length} in ${r.ms} ms`);
process.exitCode = r.ok ? 0 : 1;

// A CALL THAT ENTERS FROM OUTSIDE THE REGION, OR THAT SUCH A FUNCTION MAKES, NAMES THE DATABASE'S REGION.
//
// Seat: it_engineer, 10 Nov 2026 (channels audit before the paid test round, founder ruling 1608).
// Supabase runs an edge function in the region nearest its CALLER; the database is in ap-southeast-1. A browser call is pinned by
// fnUrl (every_browser_call_to_a_function_is_region_pinned.test.mjs) and the WhatsApp reply's gateway and embedder calls by
// inDbRegion (_shared/db_region.test.ts, #1888). What was left runs wherever a provider or a scheduler enters, measured on
// production (agent_runs fn:<slug> counts.region, 8-10 Nov 2026):
//   resilience_ping (Vercel cron)            us-east-1 192 of 192, avg 75.8 s a tick
//     -> send_whatsapp                       us-east-1 p50 9.4 s   against ap-southeast-1 0.66 s
//     -> send_outbox                         us-east-1 p50 4.4 s   against ap-southeast-1 0.35 s
//   wa_inbound / resend_inbound -> license_extract   us-east-1 p50 13.6 s against ap-southeast-1 6.3 s
// Each line below is a call site on one of those paths; it must carry the region parameter. Comments are stripped first, so an
// explanation in the file cannot satisfy it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const code = (p) => readFileSync(root + p, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1');
/** Every line of `file` that names '/functions/v1/<slug>' must also pin the region (inDbRegion( or the literal parameter). */
function pinned(file, slug) {
  const lines = code(file).split('\n').filter((l) => l.includes('/functions/v1/' + slug));
  assert.ok(lines.length > 0, file + ' no longer calls ' + slug + ' by its literal path (no_function_calls_an_undeployed_function reads it)');
  for (const l of lines) assert.match(l, /inDbRegion\(|forceFunctionRegion=ap-southeast-1/, file + ' calls ' + slug + ' without the region: ' + l.trim());
}

test('the Vercel cron calls resilience_ping in the database region (it drains the outbox and the WhatsApp queue)', () => {
  pinned('src/app/api/resilience-ping/route.ts', 'resilience_ping');
});

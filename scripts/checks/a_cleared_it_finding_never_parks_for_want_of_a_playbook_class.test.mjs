// A CLEARED IT FINDING NEVER PARKS FOR WANT OF A PLAYBOOK CLASS (it_engineer, 24 Sep 2026).
//
// scripts/sql/a_whatsapp_delivery_finding_closes_its_own_loop.sql. Measured 24 Sep 2026: it.finding
// handoff #58198 (duty:whatsapp_delivery:no_final_status:whatsapp) was answered by customer_support and
// its finding closed on 22 Sep 21:31Z, yet fn_it_loop_reverify parked it at awaiting_learning for two
// days, because no it_playbook row's issue_prefix covered the whatsapp_delivery duty -- the originator's
// auto-close had nothing to record the learning from. That raised
// duty:handoff_sla:it.finding:customer_support:unclosed.
//
// This fails when the cause returns: a pending it.finding handoff parked at awaiting_learning whose
// issue_key no it_playbook prefix covers at all. (A class that exists but still lacks its typical_cause
// is a different wait -- the gate doing its job -- and is reported by the handoff_sla duty, not here.)
//
//   node --test scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { sql } from '../lib/db.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const FILE = 'scripts/sql/a_whatsapp_delivery_finding_closes_its_own_loop.sql';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('the whatsapp_delivery duty has a playbook class with a measured cause', () => {
  const src = readFileSync(join(REPO, FILE), 'utf8');
  assert.match(src, /\('whatsapp_delivery', 'duty:whatsapp_delivery:'/, 'no it_playbook row covers duty:whatsapp_delivery:');
  assert.match(src, /select public\.fn_it_loop_reverify\(\);/, 'the file does not re-run the originator\'s reverify, so #58198 waits for the next tick');
});

test('no cleared it.finding handoff is parked because no playbook class covers its key', { skip: SKIP }, async () => {
  const rows = await sql(`
    select a.id, a.detail->>'issue_key' issue_key
      from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
       and a.detail ? 'awaiting_learning'
       and not exists (select 1 from public.it_playbook b
                        where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix)
     order by a.id`);
  assert.deepEqual(rows, [], 'parked with no playbook class to learn from -- add an it_playbook row for the duty: '
    + JSON.stringify(rows));
});

// THE ORGANISATION STILL REPORTS THE WAY THE FOUNDER APPROVED.
//
// 16 Aug 2026. fn_phase_a_organization_violations() returned 0 rows and fn_phase_c_invariants()
// returned 58 checks all true while 26 of the 90 standing roles reported to the wrong manager or
// carried the wrong class, and all 86 category overlays were missing the broad-domain escalation
// their registry entry assigns them. Neither instrument was wrong about what it measured. Both
// measure PROPERTIES of the reporting graph — every role has a manager, the manager is active,
// there is no cycle, no self-management, no duplicate identity — and neither had the founder's map
// as a subject to compare against. A graph can satisfy every structural property and still be the
// wrong graph.
//
// This runs the check that does have a subject. public.phase_c_reporting_authority holds the
// founder-approved map (package v2026.08.16, 90 standing roles) and
// public.fn_phase_c_reporting_map_drift() compares the live organisation against it field by field:
// primary manager, department, H/O/S/R class, department head, the walked path to the founder,
// duplicate identity, self-management, an identity that cannot act, the nine overlay governance
// facts, and the two chain-of-command rules — normal autonomous work must not route through the
// founder or the Chief of Staff, and refund_decision is the only routine founder approval.
//
// The check asserts its own subject first: an empty authority table reports
// `authority_not_recorded` rather than agreeing with nothing. Verified by execution — deleting one
// row, and then all 90, each produced a drift row rather than a green result.
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';

let token;
try {
  token = (process.env.SUPABASE_ACCESS_TOKEN
    || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
} catch { /* fall through to the skip below */ }

if (!token) {
  console.log('SKIPPED: no SUPABASE_ACCESS_TOKEN and no local access token, so production cannot be '
    + 'read. This check measures the live organisation; it has nothing to assert without it.');
  process.exit(0);
}

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  // The management API rate-limits hard after a heavy session. A 429 here is throttling, not a
  // finding, and reporting it as drift would be the worst kind of false red.
  if ((r.status === 429 || r.status >= 500) && attempt < 5) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return q(sql, attempt + 1);
  }
  if (!r.ok) {
    console.error('could not read production:', r.status, (await r.text()).slice(0, 300));
    process.exit(1);
  }
  return r.json();
}

const drift = await q('select subject, role_id, approved, live from public.fn_phase_c_reporting_map_drift() '
  + 'order by subject, role_id');

if (drift.length) {
  console.error(`FAIL: the live organisation disagrees with the founder-approved reporting map in `
    + `${drift.length} place(s).\n`);
  for (const d of drift) {
    console.error(`  ${d.subject}  ${d.role_id}\n      approved: ${d.approved}\n      live:     ${d.live}`);
  }
  console.error('\nThe authority is public.phase_c_reporting_authority, recorded from '
    + 'QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP_v2026.08.16. If a change to the '
    + 'organisation is intended, it is a Phase A change request with the founder\'s approval, and '
    + 'the authority moves first — not the other way round.');
  process.exit(1);
}

console.log('OK: 90 standing roles and 86 category overlays match the founder-approved reporting map; '
  + 'no normal autonomous step routes through the founder or the Chief of Staff; refund_decision is '
  + 'the only routine founder approval.');

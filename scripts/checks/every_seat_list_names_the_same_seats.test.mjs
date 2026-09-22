// EVERY LIST OF SEATS NAMES THE SAME SEATS (ceo, 22 Sep 2026, with the sixth seat: marketing).
//
// Founder instruction 721 added the marketing seat. Measured before it: the seats are written out by hand
// in the owner check (function_owner_owner_ck), the TypeScript Seat type, three checks and five routines,
// and nothing compared them, so a seat added in one list and forgotten in another would pass until the
// forgotten list refused something at run time. The founder, 21 Sep 2026: "i dont want things to pop up
// again for the same reasons".
//
// FAILS when:
//   * the seats admitted by the newest function_owner_owner_ck in scripts/sql (MANIFEST order, then the files
//     pending apply), the Seat type in supabase/functions/_shared/payment_handoffs.ts, and the seat lists of
//     every_report_and_handoff_comes_back, the_ceo_plans_every_day, every_seat_carries_the_company_knowledge
//     and the G9 roster are not all the same set;
//   * (production) the active org_role seats are not that set, or an active seat other than the ceo has no
//     edge to the ceo and does not name the founder as its escalation.
//
//   node --test scripts/checks/every_seat_list_names_the_same_seats.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const sorted = (xs) => [...new Set(xs)].sort();
const quoted = (s) => [...s.matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);

export function ownerCheckSeats() {
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
  const listed = new Set(manifest);
  const pending = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql')).map((f) => 'scripts/sql/' + f)
    .filter((f) => !listed.has(f)).sort();
  let last = null;
  for (const f of [...manifest, ...pending]) {
    if (!existsSync(join(REPO, f))) continue;
    for (const m of read(f).matchAll(/add constraint function_owner_owner_ck\s+check\s*\(owner = any \(array\[([^\]]*)\]\)\)/gi)) last = m[1];
  }
  assert.ok(last, 'no file adds function_owner_owner_ck');
  return sorted(quoted(last).filter((s) => s !== 'website'));   // 'website' owns public pages; it is not a seat
}

export function listsInCode() {
  const ts = read('supabase/functions/_shared/payment_handoffs.ts').match(/export type Seat = ([^;]+);/);
  const arr = (file) => {
    const m = read(file).match(/const SEATS = \[([^\]]*)\]/);
    assert.ok(m, `${file} has no SEATS list`);
    return sorted(quoted(m[1]));
  };
  const knowledge = sorted([...read('scripts/checks/every_seat_carries_the_company_knowledge.test.mjs').matchAll(/\{ seat: '([a-z_]+)'/g)].map((m) => m[1]));
  const roster = read('scripts/checks/support_acceptance_group_org_and_channels.mjs').match(/S\('the_roster_is_exactly_the_\w+_authorised_seats', '([a-z_,]+)'/);
  return {
    'payment_handoffs.ts Seat': sorted(quoted(ts[1])),
    'every_report_and_handoff_comes_back SEATS': arr('scripts/checks/every_report_and_handoff_comes_back.test.mjs'),
    'the_ceo_plans_every_day SEATS': arr('scripts/checks/the_ceo_plans_every_day.test.mjs'),
    'every_seat_carries_the_company_knowledge SEATS': knowledge,
    'support_acceptance G9 roster': sorted(roster[1].split(',')),
  };
}

test('every seat list in the repository names the seats the owner check admits', () => {
  const want = ownerCheckSeats();
  assert.ok(want.includes('marketing') && want.includes('ceo'), `owner check reads ${want}`);
  for (const [where, got] of Object.entries(listsInCode())) assert.deepEqual(got, want, `${where} disagrees with function_owner_owner_ck`);
});

test('the comparison fails a list that is one seat short (positive control)', () => {
  const want = ownerCheckSeats();
  assert.notDeepEqual(want.filter((s) => s !== 'marketing'), want);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: the active seats are those seats, and each reports to the ceo or names the founder', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select r.role_id, r.escalation_targets,
                                 exists (select 1 from public.org_reporting_edge e where e.child_role_id = r.role_id and e.parent_role_id = 'ceo') edged
                            from public.org_role r where r.status = 'active' order by r.role_id`);
  assert.deepEqual(rows.map((r) => r.role_id), ownerCheckSeats(), 'org_role (active) is not the repository\'s seat list: is the seat file applied?');
  const loose = rows.filter((r) => r.role_id !== 'ceo' && !r.edged && !(r.escalation_targets || []).includes('founder')).map((r) => r.role_id);
  assert.deepEqual(loose, [], 'these seats report to nobody');
});

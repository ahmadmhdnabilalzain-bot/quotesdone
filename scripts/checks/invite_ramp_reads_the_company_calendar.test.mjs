// THE COMPANY WROTE DOWN WHEN NOT TO SEND. SOMETHING HAS TO READ IT.
//
// 13 Aug 2026. public.company_calendar holds 55 hand-researched, sourced, verified rows about the
// market this company sells into — UAE public holidays, trade shows, compliance deadlines,
// seasonality — each with an `action` instruction and an owning department. Nothing read it: not a
// routine, not a view, not an edge function, not a file in src/.
//
// Row 1 is Mawlid, 25 Aug 2026, and its action says "Do not launch campaigns or invite pushes
// 22-27 Aug." On the same day this check was written the invite daily cap went from 10 to 20, and
// nothing would have stopped enqueue_supplier_invites pushing twenty cold invitations a day into a
// national shutdown the company had already written down.
//
// This check fails if the ramp stops consulting the calendar, if the pause stops being
// self-clearing, or if the calendar runs dry — a guard with nothing left to guard against is the
// same defect as no guard, it just takes longer to notice.
//
//   node --test scripts/checks/
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// This POSTed its own fetch with NO backoff at all, and reported a throttle as
// `query failed on htdblwldjkcgjvmqkbeh: 429` — which reads as "the invite ramp stopped consulting
// the calendar". MEASURED 22 Sep 2026: that is how this check went red on origin/main while the
// ramp was correct. scripts/lib/db.mjs is the estate's one retry policy for this endpoint and
// names an exhausted throttle as infrastructure. The assertions below are unchanged; read_only is
// set because both statements are reads.
const q = (project, query) => sql(query, { ref: project, readOnly: true });

const defOf = async (project) => {
  const rows = await q(project, "select pg_get_functiondef(p.oid) as def from pg_proc p "
    + "join pg_namespace n on n.oid = p.pronamespace "
    + "where n.nspname = 'public' and p.proname = 'enqueue_supplier_invites'");
  assert.equal(rows.length, 1, 'enqueue_supplier_invites is missing or overloaded');
  return String(rows[0].def);
};

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`the invite ramp consults company_calendar on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token, so the live routine cannot be read'); return; }
    const def = await defOf(project);

    assert.match(def, /company_calendar/,
      'enqueue_supplier_invites does not read company_calendar — the company researches its own '
      + 'shutdown calendar and the ramp sends through it');

    // Before anything is planned or written. A frozen day must not leave an invite_schedule row
    // claiming it planned sends it never made.
    const calAt = def.indexOf('company_calendar');
    const schedAt = def.indexOf('insert into invite_schedule');
    assert.ok(calAt > 0 && schedAt > 0 && calAt < schedAt,
      'the calendar check must run BEFORE the invite_schedule upsert, or a frozen day records a plan it never executed');

    // Self-clearing. The bounce auto-pause deliberately flips invite_enabled to false and needs a
    // human to restore it; a public holiday must resume on its own the next morning.
    const guard = def.slice(calAt, schedAt);
    // 6 SEP 2026: the founder's outreach switch (supplier_outreach_golive) and the ramp's own gate
    // (invite_enabled) are READ inside this range now, before anything is planned. Reading a gate is
    // not the outage this guards against; WRITING invite_enabled from the calendar pause is.
    assert.doesNotMatch(guard, /update\s+(public\.)?app_secrets[^;]*invite_enabled/i,
      'the calendar pause must not touch app_secrets.invite_enabled — a holiday that needs a human '
      + 'to switch invites back on is an outage, not a pause');

    // The row's own words reach a human. The automatic pause is deliberately narrower than the
    // written guidance ("22-27 Aug" for a one-day holiday), so the prose has to travel with it.
    assert.match(guard, /\baction\b/,
      "the pause does not carry the calendar row's `action` text, so the wider written guidance "
      + 'never reaches anyone');
  });
}

test('the calendar still has something to guard against', async (t) => {
  if (!mgmtToken) { t.skip('no management token'); return; }
  const [row] = await q('htdblwldjkcgjvmqkbeh',
    "select count(*)::int as upcoming, min(starts_on)::text as next_on, "
    + "(array_agg(event_name order by starts_on))[1] as next_event "
    + "from public.company_calendar "
    + "where kind = 'public_holiday' and coalesce(ends_on, starts_on) >= current_date");
  assert.ok(row.upcoming > 0,
    'company_calendar holds no future public_holiday row. Either the calendar has gone stale — it '
    + 'is hand-maintained and every row carries a verified_at — or the kind was renamed and the '
    + 'ramp guard now matches nothing. A guard with nothing to match is not a guard.');
  console.log(`company_calendar: ${row.upcoming} future public holiday(s); next is ${row.next_event} on ${row.next_on}`);
});

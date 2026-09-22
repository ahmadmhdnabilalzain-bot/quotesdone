// EVERY PROVIDER CAP AND EVERY RENEWAL DATE IS RECORDED, AND NO TEMPLATE WAITS UNREAD.
//
// 21 Sep 2026: four provider caps had sat since 14 Sep at the NULL their file inserted ("not recorded"),
// the quotesdone.ae expiry was NULL because aeDA publishes none and nobody read the invoice, and the
// WhatsApp templates submitted on 18 Sep were in no register - so each was re-found as "open" days later.
// scripts/sql/the_open_account_facts_of_21_september_are_recorded.sql recorded them. This fails, against
// production, if the same cause comes back:
//   1. a cap_/floor_ row of public.it_threshold is NULL - allowed only for the caps the founder holds
//      (HELD_BY_FOUNDER below, instruction 639), and only while their row says where he sets them and the
//      IT register keeps them from ever reaching him;
//   2. a domain or licence in public.it_expiry has no date and is not marked never-expiring;
//   3. an item inside its first warning has no renewal.due handoff for that date;
//   4. a wa_template_registry row has been 'pending' for more than 14 days without being read again.
//
//   node --test scripts/checks/every_provider_cap_and_renewal_date_is_recorded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// The management API throttles after a busy session; a 429 is not a finding. This file hand-rolled
// that backoff — five attempts, LINEAR, no jitter — and it was not enough on 22 Sep 2026. The
// deterministic schedule is the reason: several checks run against one rate limiter in one job and
// a fixed ladder makes them collide on the same window over and over (the hazard scripts/lib/db.mjs
// was given jitter for). db.mjs is the estate's one policy for this endpoint: 7 attempts, jittered
// exponential to a 60 s cap, and an exhausted throttle throws as infrastructure rather than as a
// failed query. Strictly more retries and strictly clearer text; the assertions below are untouched.
const q = (query) => sql(query);

// HELD BY THE FOUNDER. Founder instruction 639, 22 Sep 2026: "Do not ask about Vercel caps or subscriptions;
// that is on him and he adds when reached. Twilio balance: only raise it if it is actually a blocker."
// These two stay NULL on purpose: the number is his, he is never asked for it, and an empty cap is not a
// blocker (a balance that stops sends fails the sends, and that arrives as its own fault). The check stays red
// for any OTHER unrecorded cap, and for these two if their row stops saying so, loses where he sets it, or if
// the IT register would ever mail him about it.
//
// WHY THIS CHANGED (22 Sep 2026): the exemption used to be "basis starts 'set by the <seat> on'". That was the
// wording #784 wrote for a NULL too, which read like a recorded cap;
// scripts/sql/a_cap_nobody_has_recorded_says_not_recorded.sql made a NULL say 'not recorded: <where> (noted by
// the <seat> on <date>)' (two other checks require that), and this check went red on the two caps 639 settled.
const HELD_BY_FOUNDER = {
  cap_vercel_charges_month: 'instruction 639: Vercel caps and subscriptions are his, added when reached; never asked',
  floor_twilio_balance: 'instruction 639: the Twilio balance is raised only when it is actually a blocker',
};

test('no provider cap or floor is left at its unrecorded default', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select key, basis from public.it_threshold
                         where key ~ '^(cap|floor)_' and key <> 'cap_warn_ratio' and value is null order by key`);
  const unrecorded = rows.filter((r) => !HELD_BY_FOUNDER[r.key]).map((r) => r.key);
  assert.deepEqual(unrecorded, [], 'caps nobody recorded (set each with public.fn_it_cap_set)');
  // a held cap still says, truthfully, that it is empty and where he would set it
  const unsaid = rows.filter((r) => HELD_BY_FOUNDER[r.key] && !/^not recorded: .*(vercel\.com|console\.twilio\.com)/.test(r.basis || ''))
    .map((r) => r.key);
  assert.deepEqual(unsaid, [], 'a cap held by the founder no longer says it is not recorded and where he sets it');
});

test('an unrecorded cap never reaches the founder', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select issue_key_like, to_founder from public.it_founder_decision_class
                         where 'duty:usage_vercel:cap_unknown:vercel_charges_month' like issue_key_like
                            or 'duty:usage_twilio:cap_unknown:twilio_balance' like issue_key_like`);
  assert.ok(rows.length >= 1, 'no it_founder_decision_class row covers the cap_unknown findings (instruction 639)');
  assert.deepEqual(rows.filter((r) => r.to_founder).map((r) => r.issue_key_like), [],
    'the IT register would mail the founder about a cap instruction 639 says he is never asked about');
});

test('every domain and licence has an expiry date', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select item from public.it_expiry
                         where kind in ('domain', 'licence') and expires_on is null and never_expires is not true order by item`);
  assert.deepEqual(rows.map((r) => r.item), [], 'renewal items with no date (read the invoice when RDAP has none)');
});

test('every item inside its first warning has a renewal.due handoff for that date', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select e.item from public.it_expiry e
                         where e.kind <> 'tls' and e.expires_on is not null
                           and e.expires_on - current_date <= (select max(w) from unnest(e.warn_days) w)
                           and not exists (select 1 from public.agent_actions a
                                            where a.kind = 'handoff' and a.detail->>'type' = 'renewal.due'
                                              and a.detail->>'item' = e.item and a.detail->>'expires_on' = e.expires_on::text)
                         order by e.item`);
  assert.deepEqual(rows.map((r) => r.item), [], 'renewals due with no warning to the accountant (fn_it_renewal_watch)');
});

test('no WhatsApp template waits more than 14 days without being read again', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select template_name from public.wa_template_registry
                         where status = 'pending' and checked_at < now() - interval '14 days' order by 1`);
  assert.deepEqual(rows.map((r) => r.template_name), [], 'pending templates to re-read at Twilio and Meta');
});

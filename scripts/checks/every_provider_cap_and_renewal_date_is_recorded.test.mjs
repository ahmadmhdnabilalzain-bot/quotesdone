// EVERY PROVIDER CAP AND EVERY RENEWAL DATE IS RECORDED, AND NO TEMPLATE WAITS UNREAD.
//
// 21 Sep 2026: four provider caps had sat since 14 Sep at the NULL their file inserted ("not recorded"),
// the quotesdone.ae expiry was NULL because aeDA publishes none and nobody read the invoice, and the
// WhatsApp templates submitted on 18 Sep were in no register - so each was re-found as "open" days later.
// scripts/sql/the_open_account_facts_of_21_september_are_recorded.sql recorded them. This fails, against
// production, if the same cause comes back:
//   1. a cap_/floor_ row of public.it_threshold is NULL with the basis its file inserted - a NULL is
//      allowed only once somebody recorded, through fn_it_cap_set, what was measured and where it is set;
//   2. a domain or licence in public.it_expiry has no date and is not marked never-expiring;
//   3. an item inside its first warning has no renewal.due handoff for that date;
//   4. a wa_template_registry row has been 'pending' for more than 14 days without being read again.
//
//   node --test scripts/checks/every_provider_cap_and_renewal_date_is_recorded.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const q = async (query, attempt = 0) => {
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const text = await r.text();
  // The management API throttles after a busy session; a 429 is not a finding.
  if (r.status === 429 && attempt < 5) {
    await new Promise((res) => setTimeout(res, 3000 * (attempt + 1)));
    return q(query, attempt + 1);
  }
  assert.ok(r.ok, `query failed: ${r.status} ${text}`);
  return JSON.parse(text);
};

test('no provider cap or floor is left at its unrecorded default', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const rows = await q(`select key from public.it_threshold
                         where key ~ '^(cap|floor)_' and value is null and basis !~ '^set by the (accountant|ceo|founder) on '
                         order by key`);
  assert.deepEqual(rows.map((r) => r.key), [], 'caps nobody recorded (set each with public.fn_it_cap_set)');
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

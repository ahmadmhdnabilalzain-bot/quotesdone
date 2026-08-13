// A PHONE MAY CONFIRM AN IDENTITY, IT MAY NEVER SELECT ONE.
//
// 13 Aug 2026. The founder registered as a customer with djzaino@outlook.com, signed in on his
// mobile, and /me -> Account showed him management@quotesdone.com. login_otp held three separate
// phone-keyed identity resolutions and all three could hand back another person's account:
//
//   1. resolveEmailByPhone consulted app_secrets.admin_mfa_phone FIRST and UNCONDITIONALLY, before
//      it looked at `kind` at all. admin_mfa_phone is his mobile and admin_emails[0] is
//      management@quotesdone.com, so every CUSTOMER sign-in by SMS from that number was handed the
//      admin's account. phone_verifications at 19:44:14 records the resolver returning exactly
//      that, and auth.users.last_sign_in_at for the address is 19:44:27.
//   2. The customer and supplier branches were `ilike '%'||last9` + limit(1) with no ORDER BY.
//      Two customers shared +971509319355; Postgres returned whichever row it liked.
//   3. The verify branch preferred the newest phone_verifications row for the number - whoever had
//      last asked for a code on that handset - over the account tables themselves.
//
// customers.phone stays deliberately non-unique: in the UAE one number is shared by families,
// colleagues and a whole company through one office landline. The consequence is this check.
//
// It asserts by EXECUTION against the deployed function, not by reading source:
//   A. an unknown number is refused 404 for BOTH kinds, and for kind='admin' a number that is not
//      in admin_mfa_phone is refused too - i.e. the admin short-circuit no longer leaks into the
//      customer path;
//   B. a number carried by two accounts is refused 409 BEFORE any Twilio call, rather than
//      resolving to one of them. Exercised on staging with two ZZ DEMO / @example.invalid fixture
//      rows that are removed again in the same run.
//
// Neither branch sends an SMS: both refusals happen before the Twilio request, which is the point -
// a code we could not attribute to one account must not be issued.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh', staging: 'pglpqrhvozwepymcuunn' };
// A number in no account and in no admin_mfa_phone. 5-series is a real UAE mobile prefix, so it
// exercises toE164 rather than being rejected as malformed before the resolver is reached.
const UNKNOWN = '+971500000042';
const SHARED = '+971500000043';

const q = async (project, query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  // Read the body ONCE. `assert.ok(r.ok, ...await r.text())` evaluates the message eagerly and
  // then r.json() below throws "Body is unusable", which hides every real failure behind it.
  const text = await r.text();
  assert.ok(r.ok, `query failed on ${project}: ${r.status} ${text}`);
  return JSON.parse(text);
};

const send = async (project, user_kind, identifier) => {
  const r = await fetch(`https://${project}.supabase.co/functions/v1/login_otp`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'send', user_kind, identifier }),
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};

for (const [label, project] of Object.entries(PROJECTS)) {
  test(`an unknown number resolves to nobody for every kind on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }

    for (const kind of ['customer', 'supplier', 'admin']) {
      const { status, body } = await send(project, kind, UNKNOWN);
      // 503 means Twilio is unconfigured on this project; the resolver still ran first, but the
      // assertion below would be measuring the wrong thing, so say so rather than pass quietly.
      assert.notEqual(status, 503, `Twilio is not configured on ${label}, so this check cannot tell a refusal from an outage`);
      assert.equal(status, 404, `${kind}: expected 404 no_account for a number in no account, got ${status} ${JSON.stringify(body)}`);
      assert.equal(body.no_account, true, `${kind}: expected no_account:true, got ${JSON.stringify(body)}`);
    }
  });
}

// A PHONE CANNOT MINT AN IDENTITY EITHER, AND THE REFUSAL MUST HAPPEN BEFORE THE SPEND.
//
// allow_signup used to let an unknown number through to Twilio. The flow could not complete: `send`
// writes the phone_verifications row with email:'' for an unknown number, and `verify` then has no
// account to resolve, so it answered "No account is registered with this number... sign up first" -
// to somebody who had just tapped sign up, AFTER we had paid to text them. Measured end to end on
// production before the fix: send returned 200 known:false and left a row with an empty email.
//
// Not fixable by having verify create the account: email is the identity (customers_email_lower_uidx),
// so an account minted from a handset alone would have no address to send a quote to and nothing
// the ~20 server-side lookups could key on.
for (const [label, project] of Object.entries(PROJECTS)) {
  test(`a mobile number cannot create an account on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const { status, body } = await fetch(`https://${project}.supabase.co/functions/v1/login_otp`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'send', user_kind: 'customer', identifier: UNKNOWN, allow_signup: true }),
    }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));

    assert.equal(status, 404, `expected 404, got ${status} ${JSON.stringify(body)}`);
    assert.equal(body.signup_by_email, true, 'the refusal must name email as the way to sign up');
    // The point of the guard is that it happens BEFORE Twilio. A 200 here would mean we paid to
    // send a code that verify is going to refuse.
    assert.notEqual(status, 200, 'an SMS was sent for a sign-up that cannot complete');
  });
}

// THE AMBIGUITY GUARD, EXERCISED FOR REAL. Two accounts, one number, one HTTP call. Staging only:
// this inserts and removes rows, and it must never be run against live customer data.
test('two accounts on one number are refused, not guessed (staging)', async (t) => {
  if (!mgmtToken) { t.skip('no management token'); return; }
  const project = PROJECTS.staging;
  const cleanup = () => q(project, `delete from public.customers where email in ('zz-demo-shared-a@example.invalid','zz-demo-shared-b@example.invalid')`);

  await cleanup();
  try {
    await q(project, `insert into public.customers (full_name, email, phone) values
      ('ZZ DEMO - shared handset A','zz-demo-shared-a@example.invalid','${SHARED}'),
      ('ZZ DEMO - shared handset B','zz-demo-shared-b@example.invalid','${SHARED}')`);

    const rows = await q(project, `select count(*) n from public.customers where phone = '${SHARED}'`);
    assert.equal(Number(rows[0].n), 2, 'the fixture did not create two accounts on one number, so the guard below would not be under test');

    const { status, body } = await send(project, 'customer', SHARED);
    assert.notEqual(status, 503, 'Twilio is not configured on staging, so this check cannot tell a refusal from an outage');
    assert.equal(status, 409, `expected 409 for a number on two accounts, got ${status} ${JSON.stringify(body)}`);
    assert.equal(body.ambiguous, true, `expected ambiguous:true, got ${JSON.stringify(body)}`);
    assert.match(String(body.error || ''), /sign in with your email/i, 'the refusal must tell the caller what to do instead');
  } finally {
    await cleanup();
  }
});

// The schema half of the same rule: email is unique, phone is deliberately not, and the reason is
// recorded on the column so the next session does not "fix" the missing phone index.
for (const [label, project] of Object.entries(PROJECTS)) {
  test(`email is unique and phone is deliberately not on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }
    const idx = await q(project, `select indexname from pg_indexes where schemaname='public'
      and indexname in ('customers_email_lower_uidx','leads_claimed_by_lower_uidx')`);
    const names = idx.map((r) => r.indexname).sort();
    assert.deepEqual(names, ['customers_email_lower_uidx', 'leads_claimed_by_lower_uidx'],
      'the identity indexes are missing; a phone-keyed lookup can return another person again');

    const phoneUnique = await q(project, `select count(*) n from pg_indexes
      where schemaname='public' and tablename='customers' and indexdef ilike '%unique%' and indexdef ilike '%phone%'`);
    assert.equal(Number(phoneUnique[0].n), 0,
      'a unique index on customers.phone would lock out UAE families, colleagues and shared office landlines - phone repeating is the decision, not an oversight');

    const cmt = await q(project, `select col_description('public.customers'::regclass,
      (select attnum from pg_attribute where attrelid='public.customers'::regclass and attname='phone')) c`);
    assert.match(String(cmt[0].c || ''), /never SELECT one/i,
      'the reason phone is not unique must stay written on the column');
  });
}

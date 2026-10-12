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
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// ONE PROJECT since 15 Aug 2026. This used to loop over { production, staging }; staging was
// deleted, and left in place every assertion below would have run twice — once for real, once
// against a ref that 404s. The `send` helper reads a non-200 as a refusal, so half of these tests
// would have gone on PASSING on a project that does not exist.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };
// A number in no account and in no admin_mfa_phone. 5-series is a real UAE mobile prefix, so it
// exercises toE164 rather than being rejected as malformed before the resolver is reached.
// Both sit in 90-99, which scripts/e2e/fixtures.mjs demoMobile() never issues (15 Sep 2026). They
// were 42 and 43, inside the range the e2e harness hands out; on 14 Sep a run's supplier held 42 and
// production correctly answered this "unknown" number as a known supplier - and texted it.
const UNKNOWN = '+971500000098';
const SHARED = '+971500000097';

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

// THIS FILE IS A REHEARSAL, AND SAYS SO. It calls the live, public login_otp six times a run and five are
// refused by design. Measured 22 Sep 2026 03:53 UTC: those refusals, from check sessions run without a window,
// were 56 of the 67 login_otp calls fn_it_detect saw outside any rehearsal in 24 hours, and it raised a HIGH
// refusal_rate:login_otp finding ("turned away 84% ... a surface a customer opens") against the suite's own
// traffic. The e2e harness opens a public.rehearsal_window for exactly this (scripts/e2e/fixtures.mjs openRun);
// this file now does the same for its duration and ALWAYS closes it, so real refusals outside it still count.
// The run_tag is not 'qd_run:<tag>', so the harness's stale-run sweep never mistakes it for a fixture run.
// Prevented from recurring by the rehearsal/control pair in it_engineer_loop_is_closed.test.mjs.
// A WINDOW THIS FILE OPENED NEVER OUTLIVES IT (13 Oct 2026). Windows opened at 21:03 and 21:16 on 12 Oct
// stayed open and blocked sandbox run 4. after() closes on pass and fail alike; it also runs on SIGTERM/SIGINT
// (a cancelled CI job never reaches `after`), and every open first sweeps this file's own stale windows,
// matched by its run_tag only, never anyone else's.
const RUN_TAG = 'check:a_phone_cannot_select_an_account';
let windowId = null;
const closeWindows = () => q(PROJECTS.production,
  `update public.rehearsal_window set ended_at = now() where run_tag = '${RUN_TAG}' and ended_at is null`);
for (const sig of ['SIGTERM', 'SIGINT']) process.once(sig, () => { (mgmtToken ? closeWindows() : Promise.resolve()).catch(() => {}).finally(() => process.exit(1)); });
before(async () => {
  if (!mgmtToken) return;
  await closeWindows();
  const [w] = await q(PROJECTS.production, `insert into public.rehearsal_window (run_tag, opened_by, note)
    values ('${RUN_TAG}', 'scripts/checks/a_phone_cannot_select_an_account.test.mjs',
            'ZZ DEMO: live login_otp refusals by design') returning id`);
  windowId = w.id;
});
after(async () => {
  if (!mgmtToken) return;
  await closeWindows(); // node:test runs after() when a test fails too
});
test('the live login_otp calls run inside a rehearsal window of their own', { skip: mgmtToken ? false : 'no management token' }, () => {
  assert.ok(windowId != null, 'no rehearsal window was opened, so every refusal below reads as a customer turned away');
});

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
    // "Unknown" must be measured, not assumed: if any account carries the number, a 200 below would
    // be production answering correctly, and the check would be blaming it for its own fixture.
    // Ids, the column that matched and the demo marker, so a transient harness row is told from a customer.
    const tail = UNKNOWN.slice(-9);
    const holders = await q(project, `select 'customers.phone' col, id::text, is_demo, created_at from public.customers where phone like '%${tail}'
      union all select 'customers.whatsapp_phone', id::text, is_demo, created_at from public.customers where whatsapp_phone like '%${tail}'
      union all select 'leads.phone', id::text, is_demo, created_at from public.leads where phone like '%${tail}'
      union all select 'leads.whatsapp_phone', id::text, is_demo, created_at from public.leads where whatsapp_phone like '%${tail}'`);
    assert.deepEqual(holders, [], `${UNKNOWN} is held by an account, so it is not an unknown number: ${JSON.stringify(holders)}`);

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

// A QA IDENTITY, NEVER A PERSON, AND NO SESSION OUTLIVES THE RUN (6 Oct 2026). The customer_api test
// below needs a signed-in identity that is not a customer. It used to sign in as admin_emails[0] --
// the founder's own address -- through login_otp on every run and never sign out. Measured 6 Oct:
// 358 of the 359 auth.sessions on that address had never been refreshed, each created within seconds
// of this file's fixture login_otp calls in agent_runs. A first fix cached a refresh token for that
// account in public.app_secrets; that put a live credential for the founder in a table and turned the
// schema drift check red. Both are gone:
//   - the identity is QA_IDENTITY below, a ZZ DEMO address on example.invalid that can never deliver
//     mail to anybody. login_otp's verify (user_kind admin) creates its auth user on first use and
//     writes no customers or leads row for it. assertQaIdentity refuses anything else, and refuses
//     any address listed in app_secrets.admin_emails, so the founder's account cannot be selected
//     even by editing the constant.
//   - the session lives only in this process. Nothing is written to app_secrets or any table, and
//     the finally signs the session out (scope=global, so a leftover from a killed run dies too).
const QA_IDENTITY = 'zz-demo-qa-check-admin@example.invalid';
function assertQaIdentity(email, adminList) {
  const e = String(email || '').trim().toLowerCase();
  assert.ok(/^zz-demo-[a-z0-9.-]+@example\.invalid$/.test(e) || /^qa\.[a-z0-9.-]+@quotesdone\.com$/.test(e),
    `refusing to sign in as ${e}: this check may only use a ZZ DEMO @example.invalid or qa.*@quotesdone.com identity`);
  const admins = String(adminList || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  assert.ok(!admins.includes(e), `refusing to sign in as ${e}: it is listed in admin_emails, which is a real person`);
  return e;
}
const anonKey = async (project) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + mgmtToken } });
  const k = (await r.json().catch(() => [])).find?.((x) => x.name === 'anon')?.api_key;
  assert.ok(k, `could not read the anon key: ${r.status}`);
  return k;
};
async function qaSession(project, email) {
  const anon = await anonKey(project);
  // A one-time code generated for this run; it is hashed into the row and never printed.
  const code = String(100000 + (crypto.getRandomValues(new Uint32Array(1))[0] % 900000));
  await q(project, `insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
    values ('${email}', encode(hmac('${code}', (select value from app_secrets where key='otp_hmac_key'), 'sha256'), 'hex'),
            'login', 'admin', now() + interval '5 minutes')`);
  const mint = await fetch(`https://${project}.supabase.co/functions/v1/login_otp`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'verify', user_kind: 'admin', identifier: email, code }),
  }).then((r) => r.json());
  assert.ok(mint.access_token, `could not mint a QA session: ${JSON.stringify({ ...mint, access_token: undefined, refresh_token: undefined }).slice(0, 160)}`);
  assert.equal(String(mint.email || '').toLowerCase(), email, 'login_otp signed in a different identity than the QA one asked for');
  return { anon, access_token: mint.access_token };
}
async function signOut(project, s) {
  const r = await fetch(`https://${project}.supabase.co/auth/v1/logout?scope=global`, {
    method: 'POST', headers: { apikey: s.anon, Authorization: 'Bearer ' + s.access_token },
  });
  assert.ok(r.status === 204 || r.ok, `could not sign the QA session out: ${r.status}`);
}

// READING WHO YOU ARE MUST NOT CREATE WHO YOU ARE.
//
// customer_api opened with `if (!cust) insert({ email })`, so ANY authenticated identity that
// touched it became a customer. Measured: the duplicate management@quotesdone.com row was retired
// at 20:30 on 13 Aug and a NEW one appeared at 21:01:05 with a different id, full_name null and
// phone null - the shape of that insert, and the only line in the estate that writes it. Deleting
// the row was futile while the endpoint kept re-creating it.
//
// It was redundant on the legitimate path too: login_otp's email branch already inserts the row
// when a buyer verifies their code, and a customer JWT can only come from mintSession there.
// This asserts the count does not move when an authenticated non-customer reads the endpoint.
for (const [label, project] of Object.entries(PROJECTS)) {
  test(`customer_api does not manufacture an account on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token'); return; }

    const admins = await q(project, `select value from app_secrets where key='admin_emails'`);
    const qaEmail = assertQaIdentity(QA_IDENTITY, admins[0]?.value);

    const before = await q(project, `select count(*)::int n from public.customers`);
    const hasRow = await q(project, `select count(*)::int n from public.customers where lower(btrim(email)) = '${qaEmail}'`);
    // If the QA address holds a customer account this check cannot tell creation from a
    // pre-existing row, so say so rather than pass on a technicality.
    assert.equal(Number(hasRow[0].n), 0,
      `${qaEmail} holds a customers row, so this check cannot prove the endpoint stopped creating them. Retire that row first.`);

    const mint = await qaSession(project, qaEmail);
    try {
      const me = await fetch(`https://${project}.supabase.co/functions/v1/customer_api`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + mint.access_token },
        body: JSON.stringify({ action: 'me' }),
      });
      assert.equal(me.status, 403, `an identity with no customer account must be refused, got ${me.status}`);

      const after = await q(project, `select count(*)::int n from public.customers`);
      assert.equal(Number(after[0].n), Number(before[0].n),
      'reading customer_api created a customers row - the endpoint is manufacturing accounts again');
    } finally { await signOut(project, mint); }
  });
}

// THE AMBIGUITY GUARD, EXERCISED FOR REAL. Two accounts, one number, one HTTP call.
//
// REHOMED 15 AUG 2026, AND IT IS THE ONE CHECK IN THIS FILE THAT CANNOT BE MADE ROLLBACK-SAFE.
// Said plainly rather than dressed up: the guard lives in the login_otp edge function, which
// connects on its own session, so it cannot see rows inside an uncommitted transaction. The
// aborted-transaction probe used everywhere else in this repo is not available here. The choice was
// to delete a guard that pins a real 13 Aug defect, or to run it against the one project with the
// fixtures visible for the duration of a single HTTP call. It runs — under three conditions:
//
//   1. it refuses outright if the fixture number is carried by ANY existing row, so it can never
//      touch a real customer or read someone else's account as its own fixture;
//   2. the rows use the estate's demo convention — `ZZ DEMO — …` and @example.invalid — so anything
//      that ever leaks is identifiable on sight rather than looking like a customer;
//   3. the removal is ASSERTED, not assumed. `finally` deletes them and the test then counts back
//      to zero, so a leak fails this check instead of hiding inside it.
// SINCE #1362 A PHONE MATCHES ONLY A ROW WHOSE PHONE AND EMAIL ARE BOTH VERIFIED (13 Oct 2026). The fixtures
// below set both flags where a row must count, and leave them false where it must not. SHARED is a reserved
// fixture number, so a number that resolves to one account answers 200 fixture_number (the step just before
// Twilio) and is never texted; 404 means nobody resolved, 409 means two did.
const SHARED_EMAILS = ['zz-demo-shared-a@example.invalid', 'zz-demo-shared-b@example.invalid'];
const sharedFixture = async (t, rows, expect) => {
  if (!mgmtToken) { t.skip('no management token'); return; }
  const project = PROJECTS.production;
  const cleanup = () => q(project, `delete from public.customers where email in ('${SHARED_EMAILS.join("','")}')`);

  await cleanup();
  // NAMED, NOT COUNTED (22 Sep 2026). A run reported this number "carried by a real customers row" twice and
  // a read-only look minutes later found no such row -- most likely another run's fixtures mid-flight. A count
  // cannot tell those apart; the ids, the column that matched, the demo marker and the creation time can.
  // No phone or address is printed: the id and the marker are enough to look the row up.
  const squatters = await q(project, `select id, is_demo, fn_is_demo_email(email) demo_email, created_at,
      case when phone = '${SHARED}' then 'customers.phone' else 'customers.whatsapp_phone' end col
      from public.customers where phone = '${SHARED}' or whatsapp_phone = '${SHARED}' order by created_at`);
  assert.deepEqual(squatters, [],
    `${SHARED} is carried by ${squatters.length} customers row(s): ${JSON.stringify(squatters)}. If each is_demo `
    + 'row was created seconds ago it is a concurrent run of this check, not a customer; otherwise this check would '
    + 'be inserting fixtures alongside live data and asserting against a mix of the two. Pick another fixture number.');
  try {
    const values = rows.map((verified, i) => `('ZZ DEMO - shared handset ${'AB'[i]}','${SHARED_EMAILS[i]}','${SHARED}',${verified},${verified})`);
    await q(project, `insert into public.customers (full_name, email, phone, phone_verified, email_verified) values ${values.join(',')}`);
    const seeded = await q(project, `select count(*)::int n from public.customers where phone = '${SHARED}'`);
    assert.equal(Number(seeded[0].n), rows.length, 'the fixture rows were not all created, so the case below would not be under test');

    const { status, body } = await send(project, 'customer', SHARED);
    assert.notEqual(status, 503, 'SMS sign-in is not configured, so this check cannot tell a refusal from an outage');
    expect(status, body);
  } finally {
    await cleanup();
    // ASSERTED, NOT ASSUMED. A delete that matched nothing returns 200 exactly like one that
    // matched two rows, and this is the only place in the estate that puts a fixture next to live
    // customer data. If it ever leaks, this line is what says so.
    const left = await q(project, `select count(*)::int n from public.customers
       where email in ('${SHARED_EMAILS.join("','")}') or phone = '${SHARED}'`);
    assert.equal(Number(left[0].n), 0,
      'the shared-number fixtures were not removed — there is demo data on the live project right now');
  }
};

test('two verified accounts on one number are refused, not guessed', (t) => sharedFixture(t, [true, true], (status, body) => {
  assert.equal(status, 409, `expected 409 for a number on two accounts, got ${status} ${JSON.stringify(body)}`);
  assert.equal(body.ambiguous, true, `expected ambiguous:true, got ${JSON.stringify(body)}`);
  assert.match(String(body.error || ''), /sign in with your email/i, 'the refusal must tell the caller what to do instead');
}));

test('one verified and one unverified account on a number resolve to the verified one', (t) => sharedFixture(t, [true, false], (status, body) => {
  assert.equal(status, 200, `the unverified row must not make the number ambiguous; got ${status} ${JSON.stringify(body)}`);
  assert.equal(body.code, 'fixture_number', `expected the resolved number to reach the pre-Twilio fixture step, got ${JSON.stringify(body)}`);
}));

test('a fully verified account on a number reaches the code step (live positive control)', (t) => sharedFixture(t, [true], (status, body) => {
  assert.equal(status, 200, `a verified owner must resolve; got ${status} ${JSON.stringify(body)}`);
  assert.equal(body.code, 'fixture_number', `expected the pre-Twilio fixture step, got ${JSON.stringify(body)}`);
}));

test('an unverified account on a number resolves to nobody', (t) => sharedFixture(t, [false], (status, body) => {
  assert.equal(status, 404, `an unverified phone must not select an account; got ${status} ${JSON.stringify(body)}`);
  assert.equal(body.code, 'no_account_for_number', JSON.stringify(body));
}));

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

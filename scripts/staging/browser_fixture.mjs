// browser_fixture.mjs — stand up (and tear down) real staging data for a BROWSER-driven run.
//
// §3.6: "Nothing has yet run against the deployed Vercel preview URL. The frontend was verified by
// reading its built bundle, not by driving it. There is no browser test harness in the repo."
//
// This is the data half of closing that. Every other fixture in scripts/staging/ drives the API
// directly and tears down inside withRun()'s finally - which is right for them and useless here,
// because a browser session needs the rows to still exist while a human or an agent clicks around.
// So this splits the two halves explicitly and makes the teardown a named command rather than an
// implicit one, because data that outlives its run is exactly what §2.2 is a list of.
//
//   node scripts/staging/browser_fixture.mjs setup            -> prints the email, OTP and run tag
//   node scripts/staging/browser_fixture.mjs teardown <tag>    -> removes every row and object
//
// The OTP is seeded the same way journey_test does it: login_otp stores an HMAC and never the code,
// and staging cannot send email (email_enabled is forced off so staging can never mail a real
// person), so the test writes a verification row for a code it chose, hashed exactly as login_otp
// hashes it. Everything except the delivery hop is genuinely exercised.
import { createHmac } from 'node:crypto';
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF, newRun, makeCustomer, makeInquiry, makeQuote, makeSupplier, teardown, q } from './demo_factory.mjs';

const [, , cmd, arg] = process.argv;

if (cmd === 'teardown') {
  if (!arg) { console.error('teardown needs the run tag'); process.exit(2); }
  const removed = await teardown({ tag: arg });
  console.log(`run ${arg} torn down:`, removed || '(nothing)');
  process.exit(0);
}

if (cmd !== 'setup') { console.error('usage: browser_fixture.mjs setup | teardown <tag>'); process.exit(2); }

const run = newRun();
const OTP = '424242';

const cust = await makeCustomer(run);
const sup1 = await makeSupplier(run, { trade: 'aluminium', variant: 0, variants: 2 });
const sup2 = await makeSupplier(run, { trade: 'aluminium', variant: 1, variants: 2 });
const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'quoted' });
await makeQuote(run, { inquiry: inq, supplier: sup1, amount: 118500, notes: 'Supply and install 40 aluminium windows, 6 week lead time.' });
await makeQuote(run, { inquiry: inq, supplier: sup2, amount: 132000, notes: 'Premium thermal break system, 8 week lead time.' });

// Mark the customer verified and seed a login OTP so the browser can complete a real sign-in.
const otpKey = (await mgmtRead(REF, "select value from public.app_secrets where key='otp_hmac_key'"))[0]?.value;
if (!otpKey) { console.error('no otp_hmac_key in app_secrets - cannot seed a login code'); process.exit(1); }
const hash = createHmac('sha256', otpKey).update(OTP).digest('hex');
await mgmtWrite(REF, `
  insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
  values (${q(cust.email)}, ${q(hash)}, 'login', 'customer', now() + interval '60 minutes')`, 'seed login otp');
await mgmtWrite(REF, `update public.customers set email_verified=true where id=${q(cust.customerId)}::uuid`, 'verify email');

console.log(JSON.stringify({
  tag: run.tag, email: cust.email, otp: OTP,
  customerId: cust.customerId, inquiryId: inq.id,
  teardown: `node scripts/staging/browser_fixture.mjs teardown ${run.tag}`,
}, null, 2));

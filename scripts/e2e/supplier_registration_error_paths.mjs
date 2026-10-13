// scripts/e2e/supplier_registration_error_paths.mjs — every way the invited registration can go wrong (24 Sep 2026, sales_engineer, ledger 993).
//   node scripts/e2e/supplier_registration_error_paths.mjs
// ZZ DEMO leads and @example.invalid accounts only; the one fixture mobile is refused before Twilio. Torn down at the end.
import { openRun, closeRun, read, write, call, BASE } from './fixtures.mjs';
import { mkAuthUser, verifyEmailByOtp } from '../lib/demo_factory.mjs';
const out = []; const step = (n, ok, d) => { out.push({ n, ok, d }); console.log(`${ok ? 'PASS' : 'FAIL'} ${n} — ${d}`); };
const run = await openRun();
try {
  const A = `qd-${run.tag}-supA@example.invalid`, B = `qd-${run.tag}-supB@example.invalid`, company = `ZZ DEMO Errors ${run.tag}`;
  const lead = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags)
    values ('${company}', '${A}', 'Dubai', 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}']) returning id, claim_token::text t`))[0];
  run.ids.leads.add(String(lead.id));
  // invalid / malformed / unknown token
  let r = await call('claim_lookup', null, { t: '00000000-0000-0000-0000-000000000000' }); step('unknown token -> not_found', r.status === 404 && r.json?.error === 'not_found', `${r.status} ${r.text.slice(0, 120)}`);
  r = await call('claim_lookup', null, { t: 'not-a-token' }); step('malformed token -> invalid_link', r.status === 400 && r.json?.error === 'invalid_link', `${r.status} ${r.text.slice(0, 120)}`);
  r = await call('claim_lookup', null, { t: lead.t }); step('valid token -> company, claimable', r.json?.ok && r.json?.claimable === true, r.text.slice(0, 140));
  // wrong email OTP
  r = await call('login_otp', null, { action: 'verify', identifier: A, code: '000001', user_kind: 'supplier' }); step('wrong e-mail code refused', r.status === 400 && r.json?.code === 'wrong_code', `${r.status} ${r.text.slice(0, 100)}`);
  // A signs up and claims
  const ua = await mkAuthUser(run, A); await verifyEmailByOtp(A, 'supplier');
  r = await call('supplier_api', ua.jwt || ua.access_token || ua.token, { action: 'claim', t: lead.t }); step('A claims the invited listing', r.json?.ok === true, `${r.status} ${r.text.slice(0, 120)}`);
  // reuse the link: B tries the same token
  const ub = await mkAuthUser(run, B); await verifyEmailByOtp(B, 'supplier');
  const tb = ub.jwt || ub.access_token || ub.token;
  r = await call('claim_lookup', null, { t: lead.t }); step('reused link reports already claimed', r.json?.ok && r.json?.claimable === false, r.text.slice(0, 140));
  r = await call('supplier_api', tb, { action: 'claim', t: lead.t }); step('second account cannot claim the reused link', r.status === 409, `${r.status} ${r.text.slice(0, 120)}`);
  // duplicate company: B registers a new company with the same name
  r = await call('supplier_api', tb, { action: 'create_company', company_name: company, emirate: 'Dubai', lang: 'en' });
  if (r.json?.id) { run.ids.leads.add(String(r.json.id)); await write(`update public.leads set tags = ARRAY['qd_demo','qd_run:${run.tag}'] where id = ${Number(r.json.id)}`, 'tag the duplicate so teardown reaches it'); }
  step('a second account cannot register an already-claimed company name', r.status === 409 && r.json?.code === 'company_already_registered', `${r.status} ${r.text.slice(0, 160)}`);
  r = await call('supplier_api', tb, { action: 'create_company', company_name: company + ' 2', emirate: 'Dubai', lang: 'en' });
  step('one account cannot own a second company', r.status === 409, `${r.status} ${r.text.slice(0, 100)}`);
  // missing documents: A's listing has no licence -> verification is not approved
  const v = (await write(`select public.fn_sales_engineer_verifies_supplier(${lead.id}, 'e2e_error_paths') j`))[0].j;
  step('missing licence/documents -> action_required, not approved', v?.decision === 'action_required', JSON.stringify(v).slice(0, 200));
  // wrong SMS code: a fixture number is refused before Twilio (no real SMS)
  r = await call('kyc', tb, { action: 'verify_sms', phone: '+971500000077', code: '123456' }); step('SMS verify on a fixture number never reaches Twilio', r.json?.captured === true, r.text.slice(0, 120));
} finally {
  const c = await closeRun(run); console.log('teardown:', JSON.stringify(c.leftovers));
}
console.log(`${out.filter((o) => o.ok).length}/${out.length} passed`);
process.exit(out.every((o) => o.ok) ? 0 : 1);

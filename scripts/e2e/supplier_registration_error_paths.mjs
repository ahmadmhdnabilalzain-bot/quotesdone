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
  // B's duplicate was refused, so B still owns nothing: its first own company is allowed (and tagged so teardown
  // reaches it - 13 Oct 2026 this row escaped teardown untagged), and only a SECOND one is refused.
  r = await call('supplier_api', tb, { action: 'create_company', company_name: company + ' 2', emirate: 'Dubai', lang: 'en' });
  if (r.json?.id) { run.ids.leads.add(String(r.json.id)); await write(`update public.leads set tags = ARRAY['qd_demo','qd_run:${run.tag}'] where id = ${Number(r.json.id)}`, 'tag B company for teardown'); }
  step('an account with no company may register its own', r.json?.ok === true, `${r.status} ${r.text.slice(0, 100)}`);
  r = await call('supplier_api', tb, { action: 'create_company', company_name: company + ' 3', emirate: 'Dubai', lang: 'en' });
  if (r.json?.id) { run.ids.leads.add(String(r.json.id)); await write(`update public.leads set tags = ARRAY['qd_demo','qd_run:${run.tag}'] where id = ${Number(r.json.id)}`, 'tag stray for teardown'); }
  step('one account cannot own a second company', r.status === 409 && r.json?.code === 'company_exists', `${r.status} ${r.text.slice(0, 100)}`);
  // missing documents: A's listing has no licence -> verification is not approved
  const v = (await write(`select public.fn_sales_engineer_verifies_supplier(${lead.id}, 'e2e_error_paths') j`))[0].j;
  step('missing licence/documents -> action_required, not approved', v?.decision === 'action_required', JSON.stringify(v).slice(0, 200));
  // wrong SMS code: a fixture number is refused before Twilio (no real SMS)
  r = await call('kyc', tb, { action: 'verify_sms', phone: '+971500000077', code: '123456' }); step('SMS verify on a fixture number never reaches Twilio', r.json?.captured === true, r.text.slice(0, 120));

  // ── ruling 1230 (13 Oct 2026, it_engineer): the OTP, duplicate identities, bad files, the 30-minute purge ──
  const ta = ua.jwt || ua.access_token || ua.token;
  const key = (await read(`select value from public.app_secrets where key='otp_hmac_key'`))[0].value;
  const { createHmac } = await import('node:crypto');
  const seed = (email, code, mins) => write(`insert into public.email_verifications (email, token_hash, purpose, user_kind, expires_at)
    values ('${email}', '${createHmac('sha256', key).update(code).digest('hex')}', 'login', 'supplier', now() + interval '${mins} minutes')`, 'seed otp');
  const C = `qd-${run.tag}-supc@example.invalid`;
  // an expired code
  await seed(C, '515151', -1);
  r = await call('login_otp', null, { action: 'verify', identifier: C, code: '515151', user_kind: 'supplier' });
  step('an expired e-mail code is refused as expired', r.status === 400 && /expired|wrong_code/.test(r.json?.code || ''), `${r.status} ${r.text.slice(0, 100)}`);
  // a resend: the code is generated and recorded, the fenced send answers, and the earlier code is retired
  await seed(C, '626262', 10);
  const before = Number((await read(`select count(*)::int n from public.email_verifications where email='${C}'`))[0].n);
  r = await call('login_otp', null, { action: 'send', identifier: C, user_kind: 'supplier', allow_signup: true });
  const after = (await read(`select count(*)::int n, count(*) filter (where used_at is null and expires_at > now())::int live from public.email_verifications where email='${C}'`))[0];
  step('a resend generates and records a new code; the send is attempted (fixture fenced at the Resend door)', r.status === 200 && after.n > before, `${r.status} ${r.text.slice(0, 100)}; rows ${before} -> ${after.n}, live ${after.live}`);
  r = await call('login_otp', null, { action: 'verify', identifier: C, code: '626262', user_kind: 'supplier' });
  step('the code before the resend no longer verifies', r.status === 400, `${r.status} ${r.text.slice(0, 100)}`);
  await write(`delete from public.email_verifications where email='${C}'`, 'otp rows of the resend probe');
  // a duplicate phone: allowed by design (shared UAE numbers), so a phone sign-in on it must ask for the e-mail
  await write(`update public.leads set phone='+971500000088', owner_phone_verified=true, owner_email_verified=true where lower(claimed_by) in (lower('${A}'),lower('${B}')) and 'qd_run:${run.tag}'=any(tags)`, 'two fixture companies share one mobile');
  r = await call('login_otp', null, { action: 'send', identifier: '+971500000088', user_kind: 'supplier' });
  step('a mobile shared by two suppliers never selects an account (409 ambiguous_phone, no SMS)', r.status === 409 && r.json?.code === 'ambiguous_phone', `${r.status} ${r.text.slice(0, 100)}`);
  // a duplicate e-mail: a second sign-up with A's address creates no second login
  const { keys } = await import('../lib/demo_factory.mjs'); const { ANON } = await keys();
  await fetch(`${BASE}/auth/v1/signup`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: A, password: 'Dup-' + run.tag + 'A1!' }) }).catch(() => null);
  const dup = (await read(`select count(*)::int n from auth.users where lower(email)=lower('${A}')`))[0];
  step('a second sign-up with a registered e-mail creates no second login', dup.n === 1, `auth users for A: ${dup.n}`);
  // files: wrong type and too large are refused, never stored
  const exe = Buffer.concat([Buffer.from('MZ'), Buffer.alloc(2048, 7)]).toString('base64');
  r = await call('supplier_portal', ta, { action: 'save_documents', items: [{ kind: 'license', original_b64: exe, filename: 'licence.exe', mime: 'application/x-msdownload', expiry: '' }] });
  const lic1 = (await read(`select license_doc_path from public.leads where id=${lead.id}`))[0];
  step('a wrong file type is refused with a reason and not stored', !lic1.license_doc_path && (r.json?.failed?.length > 0 || r.status >= 400), `${r.status} ${r.text.slice(0, 160)}`);
  const big = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.alloc(26 * 1024 * 1024, 32)]).toString('base64');
  r = await call('supplier_portal', ta, { action: 'save_documents', items: [{ kind: 'license', original_b64: big, filename: 'licence.pdf', mime: 'application/pdf', expiry: '' }] });
  const lic2 = (await read(`select license_doc_path from public.leads where id=${lead.id}`))[0];
  step('a 26 MB file is refused with a reason and not stored', !lic2.license_doc_path && (r.json?.failed?.length > 0 || r.status >= 400), `${r.status} ${r.text.slice(0, 160)}`);
  // ruling 1181: an unfinished sign-up older than 30 minutes is purged; one inside its 30 minutes is not
  const D = `qd-${run.tag}-supd@example.invalid`, E = `qd-${run.tag}-supe@example.invalid`;
  const ld = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags, claimed, claimed_by, owner_email_verified, portal_updated_at, created_at)
    values ('ZZ DEMO Unfinished ${run.tag}', '${D}', 'Dubai', 'directory', 'sent', now() - interval '2 hours', 'en', ARRAY['qd_demo','qd_run:${run.tag}'], true, '${D}', true, now() - interval '45 minutes', now() - interval '2 hours') returning id`))[0];
  const le = (await write(`insert into public.leads (company_name, email, emirate, source, invite_status, invited_at, locale, tags, claimed, claimed_by, owner_email_verified, portal_updated_at)
    values ('ZZ DEMO Fresh ${run.tag}', '${E}', 'Dubai', 'directory', 'sent', now(), 'en', ARRAY['qd_demo','qd_run:${run.tag}'], true, '${E}', true, now()) returning id`))[0];
  run.ids.leads.add(String(ld.id)); run.ids.leads.add(String(le.id));
  await mkAuthUser(run, D); await mkAuthUser(run, E);
  await write(`update auth.users set created_at = now() - interval '45 minutes' where lower(email)=lower('${D}')`, 'age the unfinished sign-up');
  const pe = (await write(`select public.fn_unfinished_signup_purge(true, 5, '${E}') j`))[0].j;
  const pd = (await write(`select public.fn_unfinished_signup_purge(true, 5, '${D}') j`))[0].j;
  const st = (await read(`select (select claimed from public.leads where id=${ld.id}) d_claimed, (select claimed from public.leads where id=${le.id}) e_claimed,
    (select count(*)::int from auth.users where lower(email)=lower('${D}')) d_login, (select count(*)::int from auth.users where lower(email)=lower('${E}')) e_login`))[0];
  step('an unfinished sign-up past 30 minutes is purged: login deleted, invited lead back in the pool', st.d_claimed === false && st.d_login === 0, `${JSON.stringify(st)} purge ${JSON.stringify(pd).slice(0, 160)}`);
  step('a sign-up inside its 30 minutes is untouched', st.e_claimed === true && st.e_login === 1, `${JSON.stringify(pe).slice(0, 120)}`);
} finally {
  const c = await closeRun(run); console.log('teardown:', JSON.stringify(c.leftovers));
}
console.log(`${out.filter((o) => o.ok).length}/${out.length} passed`);
process.exit(out.every((o) => o.ok) ? 0 : 1);

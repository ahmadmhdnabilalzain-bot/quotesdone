// A RECORDED ACCEPTANCE ALWAYS GETS ITS CERTIFICATE, AND NOBODY WORKS WITHOUT ONE (it_engineer, 13 Nov 2026). Offline.
//
// 13 Nov 2026: a customer's acceptance write was cancelled by a lock and kyc answered ok anyway (fixed in kyc with
// _shared/recorded_write.ts), a customer certificate that did not land was never asked for again (suppliers had a minute
// sweep, customers none), and nothing counted people working with no acceptance on record. This fails if the customer
// re-sign or the hourly count loses its schedule, its bound, its revoke or its key on the acceptance, if the file starts
// taking a strong lock on a hot table, or if compliance_archive or kyc stops reading back the write a person depends on.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { catalogueFrom, stallsLiveUsers } from '../lib/replay_guard.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'a_recorded_acceptance_always_gets_its_certificate_and_nobody_works_without_one';
const SQL = read(`scripts/sql/${NAME}.sql`);

test('the customer re-sign: every minute, after 5 minutes, at most 3 times, keyed on THIS acceptance, then a person', () => {
  assert.match(SQL, /cron\.schedule\('customer_support_terms_resign', '\* \* \* \* \*'/);
  assert.match(SQL, /c\.tos_accepted_at < now\(\) - interval '5 minutes'/);
  assert.match(SQL, /c\.signed_terms_at < c\.tos_accepted_at/, 'a certificate older than the acceptance is not its certificate');
  assert.match(SQL, /if v_prior >= 3 then/);
  assert.match(SQL, /\(a\.detail ->> 'tos_accepted_at'\)::timestamptz = r\.tos_accepted_at/);
  assert.match(SQL, /'needs_review'/);
  assert.match(SQL, /'kind', 'customer', 'id', r\.id/);
  assert.match(SQL, /p_customer_id is null or c\.id = p_customer_id/, 'the probe reaches only its own fixture');
});

test('the hourly count names the four states, real apart from demo, and raises a finding only for a real one', () => {
  for (const s of ['customer_active_without_acceptance', 'supplier_active_without_acceptance', 'customer_acceptance_without_certificate', 'supplier_acceptance_without_certificate']) {
    assert.ok(SQL.includes(`'${s}'`), s);
  }
  assert.match(SQL, /if v_real > 0 then\s+perform public\.fn_it_engineer_finding_upsert\(/);
  assert.match(SQL, /cron\.schedule\('it_engineer_acceptance_gap', '23 \* \* \* \*'/);
});

test('both routines are revoked and pinned; the file takes no strong lock on a hot table; it is pending with its probe', () => {
  assert.match(SQL, /revoke execute on function public\.fn_customer_support_resigns_unsigned_terms\(uuid\) from public, anon, authenticated;/);
  assert.match(SQL, /revoke execute on function public\.fn_it_engineer_finds_people_working_without_an_acceptance\(\) from public, anon, authenticated;/);
  assert.equal((SQL.match(/set search_path to 'public', 'pg_temp'/g) ?? []).length, 2);
  // every relation the file touches, as production's pg_class has them: none is locked beyond ROW EXCLUSIVE
  const prod = catalogueFrom({ relations: ['public.customers', 'public.leads', 'public.inquiries', 'public.agent_actions', 'public.app_secrets',
    'public.it_engineer_finding', 'public.cron_registry', 'public.writer_seat', 'cron.job'].join(',') });
  assert.deepEqual(stallsLiveUsers(SQL, prod), []);
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  const pending = (() => { try { return read(`scripts/sql/pending/${NAME}.txt`).trim(); } catch { return ''; } })();
  assert.ok(manifest.includes(`scripts/sql/${NAME}.sql`) !== Boolean(pending), 'exactly one of: a MANIFEST line, or a pending note');
  assert.match(read(`scripts/sql/${NAME}_probe.sql`), /PROBE OK: re-signed once, audited once, not again within 5 minutes/);
});

test('the writes a person depends on are read back: compliance_archive retries its certificate write and tells the IT seat', () => {
  const ca = read('supabase/functions/compliance_archive/index.ts');
  assert.match(ca, /const w = await writeRecorded\(casWrite\);/);
  assert.match(ca, /if \(casErr\) await certificateNotRecorded\(kind, rec\.id, w\.attempts, casErr\.message\);/);
  assert.match(ca, /p_issue_key: `certificate_not_recorded:\$\{kind\}`/);
  const kyc = read('supabase/functions/kyc/index.ts');
  assert.equal((kyc.match(/if \(!w\.ok\) return termsNotRecorded\(kind, email, w\);/g) ?? []).length, 2);
});

test('the probe can pass on production and catches the five mutants review measured (13 Nov 2026, local Postgres 16)', () => {
  // code only: the probe's header describes both defects in words (apply-discipline §7)
  const probe = read(`scripts/sql/${NAME}_probe.sql`).split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
  assert.doesNotMatch(probe, /insert into public\.customers \([^)]*\bis_demo\b/, 'customers.is_demo is a generated column on production');
  assert.doesNotMatch(probe, /' \|\| r\d\b(?!::text)/, "text || jsonb resolves to jsonb and raises 'invalid input syntax for type json'");
  for (const m of ['M1', 'M2', 'M3', 'M4', 'M5']) assert.match(probe, new RegExp(`PROBE FAILED \\(${m}\\)`), `${m} has no fixture`);
  // the real-counted fixture can reach nobody: no e-mail, no phone
  assert.match(probe, /\(v_real, +'Probe fixture without contact ' \|\| left\(v_real::text, 8\), null, false,/);
});

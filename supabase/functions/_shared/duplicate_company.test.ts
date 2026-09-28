// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/duplicate_company.test.ts
//
// What a write refused by the duplicate-company indexes answers, and what a document write does when its
// licence number belongs to another claimed company. The error objects are the shape PostgREST returns
// ({ code, message, details, hint }); the database is a stub. No network, no filesystem, no real row.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  CLAIM_FAILED, COMPANY_ALREADY_REGISTERED, DUPLICATE_LICENCE_INDEX, DUPLICATE_NAME_INDEX, isDuplicateCompany, isLicenceClash,
  type LeadWriter, type PgError, registrationRefusal, updateLeadSettingAsideClashingLicence,
} from './duplicate_company.ts';
import { SANCTIONED_REGISTRATION_REFUSAL } from './sanctioned.ts';

const violation = (index: string) => ({
  code: '23505',
  message: `duplicate key value violates unique constraint "${index}"`,
  details: 'Key (...)=(...) already exists.',
  hint: null,
});

Deno.test('a 23505 on the name index or the licence index is a duplicate company; only the licence index is a licence clash', () => {
  assert(isDuplicateCompany(violation(DUPLICATE_NAME_INDEX)));
  assert(isDuplicateCompany(violation(DUPLICATE_LICENCE_INDEX)));
  assert(isDuplicateCompany({ code: '23505', message: 'duplicate key', details: `constraint "${DUPLICATE_LICENCE_INDEX}"` }));
  assert(isLicenceClash(violation(DUPLICATE_LICENCE_INDEX)));
  assertEquals(isLicenceClash(violation(DUPLICATE_NAME_INDEX)), false);
});

Deno.test('any other unique violation, error code or nothing is not a duplicate company', () => {
  for (const other of ['leads_claimed_by_lower_uidx', 'uq_leads_email_lower', 'leads_claim_token_key', 'leads_place_id_uidx']) {
    assertEquals(isDuplicateCompany(violation(other)), false, other);
    assertEquals(isLicenceClash(violation(other)), false, other);
  }
  assertEquals(isDuplicateCompany({ code: '23514', message: `SANCTIONED_PARTY_BLOCKED ${DUPLICATE_NAME_INDEX}` }), false);
  assertEquals(isDuplicateCompany(null), false);
  assertEquals(isDuplicateCompany(undefined), false);
  assertEquals(isDuplicateCompany({}), false);
});

Deno.test('claim: duplicate -> 409 company_already_registered; sanctions -> the create_company 403; anything else -> stable code, no Postgres text', () => {
  assertEquals(registrationRefusal(violation(DUPLICATE_NAME_INDEX)), { body: { ...COMPANY_ALREADY_REGISTERED }, status: 409 });
  assertEquals(registrationRefusal(violation(DUPLICATE_LICENCE_INDEX)).status, 409);
  const sanctioned = registrationRefusal({ code: '23514', message: 'SANCTIONED_PARTY_BLOCKED: this identity belongs to a confirmed ban' });
  assertEquals(sanctioned, { body: { ...SANCTIONED_REGISTRATION_REFUSAL }, status: 403 });
  const raw = 'Please use a permanent email address; temporary inboxes are not allowed.';
  for (const err of [{ code: '23514', message: raw }, { code: '23505', message: 'duplicate key value violates unique constraint "leads_claimed_by_lower_uidx"' }, { code: 'PGRST301', message: 'JWT expired' }]) {
    const r = registrationRefusal(err);
    assertEquals(r, { body: { ...CLAIM_FAILED }, status: 500 });
    assertEquals(JSON.stringify(r.body).includes(String(err.message)), false, 'raw Postgres text reached the browser');
  }
});

// A stub of the few client calls the writer makes. `refuse` decides each update's answer.
function stub(refuse: (values: Record<string, unknown>) => PgError) {
  const updates: Record<string, unknown>[] = [];
  const inserts: { table: string; values: Record<string, unknown> }[] = [];
  const admin: LeadWriter = {
    from: (table: string) => ({
      update: (values: Record<string, unknown>) => ({
        eq: (_c: string, _v: unknown) => { updates.push({ ...values }); return Promise.resolve({ error: refuse(values) }); },
      }),
      insert: (values: Record<string, unknown>) => { inserts.push({ table, values }); return Promise.resolve({ error: null }); },
    }),
  };
  return { admin, updates, inserts };
}
const doc = { license_doc_path: 'licences/77/licence.pdf', license_expiry: '2027-03-31', trade_license_no: 'CN-1234567', doc_extracted_at: '2026-09-24T12:00:00Z' };

Deno.test('document write: a clashing licence number is set aside, the document and expiry are still written, and a human is asked', async () => {
  const { admin, updates, inserts } = stub((v) => ('trade_license_no' in v ? violation(DUPLICATE_LICENCE_INDEX) : null));
  const r = await updateLeadSettingAsideClashingLicence(admin, 77, doc, 'test');
  assertEquals(r, { error: null, licenceSetAside: 'CN-1234567' });
  assertEquals(updates.length, 2);
  assertEquals(updates[1], { license_doc_path: 'licences/77/licence.pdf', license_expiry: '2027-03-31', doc_extracted_at: '2026-09-24T12:00:00Z' });
  assertEquals(inserts.length, 1);
  assertEquals(inserts[0].table, 'agent_actions');
  assertEquals(inserts[0].values.status, 'needs_review');
  assertEquals(inserts[0].values.agent, 'sales_engineer');
  assertEquals((inserts[0].values.detail as Record<string, unknown>).licence_number_read, 'CN-1234567');
});

Deno.test('document write: no clash writes once and asks nobody; any other error is returned untouched and not retried', async () => {
  const ok = stub(() => null);
  assertEquals(await updateLeadSettingAsideClashingLicence(ok.admin, 77, doc, 'test'), { error: null, licenceSetAside: null });
  assertEquals([ok.updates.length, ok.inserts.length], [1, 0]);

  for (const err of [violation(DUPLICATE_NAME_INDEX), { code: '23514', message: 'SANCTIONED_PARTY_BLOCKED' }, { code: '08006', message: 'connection failure' }]) {
    const bad = stub(() => err);
    const r = await updateLeadSettingAsideClashingLicence(bad.admin, 77, doc, 'test');
    assertEquals(r, { error: err, licenceSetAside: null });
    assertEquals([bad.updates.length, bad.inserts.length], [1, 0]);
  }
});

Deno.test('document write: if the retry without the licence also fails, that error is returned and nobody is asked', async () => {
  const second = { code: '08006', message: 'connection failure' };
  const s = stub((v) => ('trade_license_no' in v ? violation(DUPLICATE_LICENCE_INDEX) : second));
  assertEquals(await updateLeadSettingAsideClashingLicence(s.admin, 77, doc, 'test'), { error: second, licenceSetAside: null });
  assertEquals(s.inserts.length, 0);
});

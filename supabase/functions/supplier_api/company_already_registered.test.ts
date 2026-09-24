// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_api/company_already_registered.test.ts
//
// A unique violation on either duplicate-company index answers with the EXISTING #944 refusal, and no
// other error does. The error objects are the shape PostgREST returns ({ code, message, details, hint });
// pure function, no network, no filesystem, no real row.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { COMPANY_ALREADY_REGISTERED, DUPLICATE_COMPANY_INDEXES, isDuplicateCompany } from './company_already_registered.ts';

const violation = (index: string) => ({
  code: '23505',
  message: `duplicate key value violates unique constraint "${index}"`,
  details: 'Key (fn_company_registration_name_key(company_name))=(zz demo steel) already exists.',
  hint: null,
});

Deno.test('a 23505 on the name index or the licence index is a duplicate company', () => {
  assert(isDuplicateCompany(violation('leads_claimed_company_name_uidx')));
  assert(isDuplicateCompany(violation('leads_claimed_trade_licence_uidx')));
  // PostgREST has been seen to put the constraint in details only; either field is read.
  assert(isDuplicateCompany({ code: '23505', message: 'duplicate key', details: 'constraint "leads_claimed_trade_licence_uidx"' }));
});

Deno.test('any other unique violation, error code or nothing keeps its own answer', () => {
  for (const other of ['leads_claimed_by_lower_uidx', 'uq_leads_email_lower', 'leads_claim_token_key', 'leads_place_id_uidx']) {
    assertEquals(isDuplicateCompany(violation(other)), false, other);
  }
  assertEquals(isDuplicateCompany({ code: '23514', message: 'SANCTIONED_PARTY_BLOCKED leads_claimed_company_name_uidx' }), false);
  assertEquals(isDuplicateCompany(null), false);
  assertEquals(isDuplicateCompany(undefined), false);
  assertEquals(isDuplicateCompany({}), false);
});

Deno.test('the answer is the existing company_already_registered refusal', () => {
  assertEquals(COMPANY_ALREADY_REGISTERED.code, 'company_already_registered');
  assertEquals(DUPLICATE_COMPANY_INDEXES.length, 2);
  // The sentence matching serverCopy.ts word for word, and the index names matching the SQL, are
  // asserted by scripts/checks/a_claimed_company_cannot_be_registered_twice.test.mjs: this suite runs
  // with no filesystem access (scripts/checks/run.mjs).
});

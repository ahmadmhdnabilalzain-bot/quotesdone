// AN ACCEPTANCE IS RECORDED OR THE PERSON IS TOLD IT WAS NOT (it_engineer, 13 Nov 2026).
//
// MEASURED (test journey f0219e92, a ZZ DEMO customer, 13 Nov 2026): at 08:47 a rehearsal on production held a table lock
// (scripts/lib/replay_guard.mjs) and kyc accept_terms's write of customers.tos_accepted_at was cancelled by the 8 s statement
// timeout. kyc never read the write's error: it answered ok, the page went on to the dashboard ("accepted the terms and
// pressed Finish & continue -> his dashboard opened"), and compliance_archive then refused the certificate because no
// acceptance was on record (08:48:16, 409 no_acceptance_on_record). A person used the platform with no recorded acceptance of
// the terms, which is a legal gap, and nothing told him, retried, or told a seat. The supplier branch had the same shape.
//
// Now the write goes through _shared/recorded_write.ts (read back, a blip retried: the same values each time, so a retry
// cannot record a second acceptance), and when it is not recorded the person reads TERMS_NOT_RECORDED and presses again,
// and the it_engineer seat gets a finding (kyc/index.ts termsNotRecorded).
// The sentence, the budget and recordAcceptance itself live in _shared/recorded_write.ts since 13 Nov 2026, because supplier_api's
// accept_terms (the supplier portal's own acceptance) records the same way; they are re-exported here for kyc and its tests.
export { ACCEPTANCE_BUDGET_MS, isBlip, recordAcceptance, TERMS_NOT_RECORDED, type Recorded, type WriteResult } from '../_shared/recorded_write.ts';

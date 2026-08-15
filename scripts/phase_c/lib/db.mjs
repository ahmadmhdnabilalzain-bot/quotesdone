// Read/write SQL client for Phase C scripts.  One project: htdblwldjkcgjvmqkbeh.
//
// Identical contract to scripts/phase_b/lib/db.mjs, re-exported here so a Phase C
// script never has to reach across into Phase B's tree.  The 429 backoff matters:
// a bare throttle reads exactly like a broken query and has been misdiagnosed as a
// defect before.
export { sql, lit, valuesOf, PROJECT_REF } from '../../phase_b/lib/db.mjs';

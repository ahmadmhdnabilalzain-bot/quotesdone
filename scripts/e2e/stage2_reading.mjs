// scripts/e2e/stage2_reading.mjs — when S21 may read a supplier's row: its documents have finished being read.
// Assigned: it_engineer. 27 Oct 2026, stage-2 rerun of run 0a717394 (ledger 1121/1261).
//
// S21: a document reading on a supplier's row is READ only when it ended without an error; 'reading' (and 'retry',
// the sweep's second attempt) is still in progress. The row is SETTLED when no document is in progress and the gate no
// longer holds it for 'documents_being_read'. Guard: scripts/e2e/stage2_reading.test.mjs.
export const docIsRead = (x) => !!x?.status && !/reading|retry|queued|error|unread|failed|refused/i.test(x.status);
export const readingSettled = (row) => !!row && row.licence_gate_reason !== 'documents_being_read'
  && !(row.source_docs?.docs || []).some((x) => /reading|retry|queued/i.test(String(x?.status || '')))
  && (row.approval_status !== 'pending' || !!row.licence_gate_reason || (row.source_docs?.docs || []).length > 0);

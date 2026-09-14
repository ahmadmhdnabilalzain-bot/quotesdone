// What a SQL file SAYS, as opposed to what its comments mention. Used by scripts/apply_sql.mjs.
//
// Review of #661, 15 Sep 2026: apply_sql sends a file that must run outside a transaction (CREATE INDEX
// CONCURRENTLY) without its `set application_name = 'qd-apply ...'` signature, and the test was a bare
// /\bconcurrently\b/ over the whole file. Measured the same day: the three files that word matched while
// also defining routines (fn_dr_restore_clear_one_bounded_delete_per_pass.sql,
// ops_knowledge_semantic_retrieval.sql, the_detector_that_finds_it_and_the_alert_that_sends_it_are_now_one_thing.sql)
// say it only in comments, so their routine changes went out unsigned - which IT duty 24 reports as an
// unauthorised change. The three files with a real CONCURRENTLY statement define no routine.
// So the test reads statements only: comments and dollar-quoted bodies are removed first.

// Removes dollar-quoted bodies ($$...$$, $fn$...$fn$), then -- line comments and /* */ block comments.
export function sqlStatements(sql) {
  return String(sql)
    .replace(/\$([A-Za-z_]*)\$[\s\S]*?\$\1\$/g, '$$$$')
    .replace(/--[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '');
}

// A statement Postgres refuses inside a transaction block, so the file must be sent on its own.
export const runsOutsideTransaction = (sql) => /\bconcurrently\b/i.test(sqlStatements(sql));

// The file defines or alters a routine, so routine_change_log records it and the signature matters.
export const definesRoutine = (sql) =>
  /\b(create\s+(or\s+replace\s+)?(function|procedure)|alter\s+(function|procedure))\b/i.test(sqlStatements(sql));

// Both at once cannot be signed: the signature is a SET in the same request, and a CONCURRENTLY
// statement must be the request's only statement. Each management-API call is its own session, so a
// separate SET does not carry over. Such a file is refused before anything is written.
export function refuseUnsignable(sql, file = 'this file') {
  if (runsOutsideTransaction(sql) && definesRoutine(sql)) {
    return `${file} both runs a CONCURRENTLY statement and defines a routine. A CONCURRENTLY statement must be sent alone, `
      + 'so the routine change would reach routine_change_log unsigned and IT duty 24 would report it as unauthorised. '
      + 'Move the CONCURRENTLY statement into its own file, listed in MANIFEST right after this one.';
  }
  return null;
}

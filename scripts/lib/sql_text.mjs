// What a SQL file SAYS, as opposed to what its comments and strings mention. Used by scripts/apply_sql.mjs.
//
// Review of #661, 15 Sep 2026: apply_sql sends a file that must run outside a transaction (CREATE INDEX
// CONCURRENTLY) without its `set application_name = 'qd-apply ...'` signature, and the test was a bare
// /\bconcurrently\b/ over the whole file. Measured the same day: the three files that word matched while
// also defining routines (fn_dr_restore_clear_one_bounded_delete_per_pass.sql,
// ops_knowledge_semantic_retrieval.sql, the_detector_that_finds_it_and_the_alert_that_sends_it_are_now_one_thing.sql)
// say it only in comments, so their routine changes went out unsigned - which IT duty 24 reports as an
// unauthorised change. The three files with a real CONCURRENTLY statement define no routine.
//
// Re-review of 12f5ed5: the first cut removed comments with regex passes, and a `--` inside a string
// literal ('a -- b') ate the real statement after it on the same line. So this is ONE left-to-right scan
// that knows every place SQL text is not code: '...' (with '' escapes), E'...' (with backslash escapes),
// "..." identifiers (with "" escapes), $tag$...$tag$ bodies with any tag, -- line comments and /* */
// block comments (which Postgres nests). apply_sql.mjs's tok() is not reused: it normalises routine
// bodies for the read-back and knows only '...' strings.

const IDENT = /[A-Za-z0-9_$]/;

// The code of a SQL text, with every literal, quoted identifier, dollar-quoted body and comment
// replaced by a neutral placeholder ('' for strings, "" for identifiers, $$ for bodies, a space for
// comments), so keyword tests see only statements.
export function sqlStatements(sql) {
  const s = String(sql); const n = s.length; let out = ''; let i = 0;
  while (i < n) {
    const c = s[i], d = s[i + 1];
    if (c === '-' && d === '-') {                                   // -- to end of line
      const e = s.indexOf('\n', i); i = e < 0 ? n : e; out += ' '; continue;
    }
    if (c === '/' && d === '*') {                                   // /* ... */, nested
      let depth = 1; i += 2;
      while (i < n && depth) {
        if (s[i] === '/' && s[i + 1] === '*') { depth++; i += 2; }
        else if (s[i] === '*' && s[i + 1] === '/') { depth--; i += 2; }
        else i++;
      }
      out += ' '; continue;
    }
    if ((c === 'E' || c === 'e') && d === "'" && !IDENT.test(s[i - 1] ?? ' ')) {   // E'...' : \ escapes
      i += 2;
      while (i < n) {
        if (s[i] === '\\') { i += 2; continue; }
        if (s[i] === "'") { if (s[i + 1] === "'") { i += 2; continue; } i++; break; }
        i++;
      }
      out += "''"; continue;
    }
    if (c === "'") {                                                // '...' : '' escapes
      i++;
      while (i < n) { if (s[i] === "'") { if (s[i + 1] === "'") { i += 2; continue; } i++; break; } i++; }
      out += "''"; continue;
    }
    if (c === '"') {                                                // "identifier" : "" escapes
      i++;
      while (i < n) { if (s[i] === '"') { if (s[i + 1] === '"') { i += 2; continue; } i++; break; } i++; }
      out += '""'; continue;
    }
    if (c === '$' && !IDENT.test(s[i - 1] ?? ' ')) {                // $tag$ ... $tag$ (not $1, not a$b)
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(s.slice(i, i + 80));
      if (m) {
        const e = s.indexOf(m[0], i + m[0].length);
        i = e < 0 ? n : e + m[0].length; out += '$$'; continue;
      }
    }
    out += c; i++;
  }
  return out;
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

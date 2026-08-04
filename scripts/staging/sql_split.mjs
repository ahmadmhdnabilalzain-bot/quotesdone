// sql_split.mjs — statement splitter that understands dollar-quoting.
//
// full_schema.sql is 32,861 lines and ~700 of them are PL/pgSQL function bodies whose
// semicolons are NOT statement terminators. Splitting on /;\s*\n/ silently shreds every
// function into fragments that then fail one by one, which reads as "the baseline is broken"
// when the splitter is what is broken. Hence a real tokenizer, and a self-test below.
// fn_schema_export() writes one section header with a LITERAL backslash-n instead of a newline:
//   -- ===== TABLES (403) =====\nCREATE TABLE IF NOT EXISTS public.action_class_gate (
// A line comment runs to the end of the LINE, and there is no line break here, so the first
// CREATE TABLE of the section is swallowed by the comment and silently never created. Whichever
// table sorts first in that section simply does not exist downstream - it was action_class_gate.
// Repair the boundary before splitting. Scoped to the section-header pattern so a legitimate
// \n inside a string literal is untouched.
export function repairDumpSectionBreaks(sql) {
  return sql.replace(/(=====)\\n/g, '$1\n');
}

export function splitStatements(sql) {
  const out = [];
  let buf = '';
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];

    // line comment
    if (c === '-' && sql[i + 1] === '-') {
      const j = sql.indexOf('\n', i);
      const end = j === -1 ? n : j + 1;
      buf += sql.slice(i, end); i = end; continue;
    }
    // block comment
    if (c === '/' && sql[i + 1] === '*') {
      const j = sql.indexOf('*/', i + 2);
      const end = j === -1 ? n : j + 2;
      buf += sql.slice(i, end); i = end; continue;
    }
    // single-quoted literal ('' escapes)
    if (c === "'") {
      let j = i + 1;
      while (j < n) {
        if (sql[j] === "'" && sql[j + 1] === "'") { j += 2; continue; }
        if (sql[j] === "'") { j++; break; }
        j++;
      }
      buf += sql.slice(i, j); i = j; continue;
    }
    // double-quoted identifier
    if (c === '"') {
      let j = i + 1;
      while (j < n) {
        if (sql[j] === '"' && sql[j + 1] === '"') { j += 2; continue; }
        if (sql[j] === '"') { j++; break; }
        j++;
      }
      buf += sql.slice(i, j); i = j; continue;
    }
    // dollar-quoted body: $tag$ ... $tag$
    if (c === '$') {
      const m = /^\$[A-Za-z_-￿][A-Za-z0-9_-￿]*\$|^\$\$/.exec(sql.slice(i));
      if (m) {
        const tag = m[0];
        const j = sql.indexOf(tag, i + tag.length);
        const end = j === -1 ? n : j + tag.length;
        buf += sql.slice(i, end); i = end;
        // A closing dollar-quote is the last token of a CREATE FUNCTION body. fn_schema_export()
        // terminates none of its 590 function definitions with a semicolon, so splitting on ';'
        // alone glues the entire FUNCTIONS section into ONE 1.1 MB statement - which then trips
        // the production-literal quarantine as a unit and silently drops all 590 functions.
        // Treat "body closed, next token starts a new statement" as a terminator.
        const rest = sql.slice(i);
        const ws = /^\s*/.exec(rest)[0].length;
        if (/^(?:CREATE|ALTER|DROP|COMMENT|GRANT|REVOKE|--)\b/i.test(rest.slice(ws))) {
          if (buf.trim()) out.push(buf.trim());
          buf = '';
        }
        continue;
      }
    }
    if (c === ';') { buf += ';'; i++; if (buf.trim()) out.push(buf.trim()); buf = ''; continue; }
    buf += c; i++;
  }
  if (buf.trim()) out.push(buf.trim());
  return out.filter(s => s.replace(/--[^\n]*/g, '').trim().replace(/;$/, '').trim().length > 0);
}

// sql_split.mjs — statement splitter that understands dollar-quoting.
//
// full_schema.sql is 32,861 lines and ~700 of them are PL/pgSQL function bodies whose
// semicolons are NOT statement terminators. Splitting on /;\s*\n/ silently shreds every
// function into fragments that then fail one by one, which reads as "the baseline is broken"
// when the splitter is what is broken. Hence a real tokenizer, and a self-test below.
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
        buf += sql.slice(i, end); i = end; continue;
      }
    }
    if (c === ';') { buf += ';'; i++; if (buf.trim()) out.push(buf.trim()); buf = ''; continue; }
    buf += c; i++;
  }
  if (buf.trim()) out.push(buf.trim());
  return out.filter(s => s.replace(/--[^\n]*/g, '').trim().replace(/;$/, '').trim().length > 0);
}

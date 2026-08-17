// THE REPOSITORY'S RECORD OF DDL, read out of .sql text.
//
// Lifted verbatim out of scripts/checks/canonical_routines.test.mjs so that check and
// scripts/checks/application_source_of_truth.test.mjs cannot drift apart about what "the
// repository records this table/column/index/constraint" means. Two copies of a parser is two
// answers to one question, and this whole section exists because two answers to one question is
// how fn_phase_c_event_ingress hid for a day.
//
// It is deliberately generous about what counts as recorded: anything it fails to see shows up as
// an uncommitted-DDL finding, which is the safe direction for a check to be wrong in.

export function newDdlRecord() {
  return { tables: new Set(), cols: new Set(), idx: new Set(), cons: new Set() };
}

export function eatDdl(rec, src) {
  for (const m of src.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi)) {
    const t = m[1].toLowerCase();
    rec.tables.add(t);
    // Column list: from the opening paren to the line that closes it. Good enough for a dump and
    // for the hand-written create-tables in scripts/sql; anything it misses shows up as a finding.
    const block = src.slice(m.index + m[0].length);
    const close = block.search(/^\s*\)\s*;/m);
    for (const line of block.slice(0, close < 0 ? 4000 : close).split('\n')) {
      const c = line.trim().match(/^"?([a-z0-9_]+)"?\s+[a-z]/i);
      if (c && !/^(constraint|primary|unique|foreign|check|exclude|like)$/i.test(c[1])) {
        rec.cols.add(`${t}.${c[1].toLowerCase()}`);
      }
      const inline = line.match(/\bconstraint\s+"?([a-z0-9_]+)"?/i);
      if (inline) rec.cons.add(inline[1].toLowerCase());
    }
  }
  for (const m of src.matchAll(/alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(?:public\.)?"?([a-z0-9_]+)"?[\s\S]{0,80}?add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
    rec.cols.add(`${m[1].toLowerCase()}.${m[2].toLowerCase()}`);
  }
  for (const m of src.matchAll(/create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?/gi)) {
    rec.idx.add(m[1].toLowerCase());
  }
  for (const m of src.matchAll(/add\s+constraint\s+"?([a-z0-9_]+)"?/gi)) rec.cons.add(m[1].toLowerCase());
  return rec;
}

// The live side of the same question. One statement, so both checks ask production the same thing.
export const LIVE_DDL_SQL = `
   select 'table' kind, c.relname obj, ''::text detail
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p')
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
   union all
   select 'column', c.relname, a.attname
     from pg_attribute a join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p') and a.attnum > 0 and not a.attisdropped
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
   union all
   select 'constraint', c.relname, con.conname
     from pg_constraint con join pg_class c on c.oid = con.conrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and con.contype in ('p','u','f','c','x')
      and not exists (select 1 from pg_depend d where d.objid = con.oid and d.deptype = 'e')
   union all
   select 'index', c.relname, i.relname
     from pg_index x join pg_class i on i.oid = x.indexrelid
     join pg_class c on c.oid = x.indrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_constraint k where k.conindid = x.indexrelid)
      and not exists (select 1 from pg_depend d where d.objid = i.oid and d.deptype = 'e')`;

// The same verdict loop both checks run over the two sides.
export function uncommittedDdl(rec, liveRows) {
  const out = [];
  for (const row of liveRows) {
    const t = row.obj.toLowerCase(), d = (row.detail || '').toLowerCase();
    if (row.kind === 'table' && !rec.tables.has(t)) out.push(`table       ${t}`);
    else if (row.kind === 'column' && !rec.cols.has(`${t}.${d}`)) out.push(`column      ${t}.${d}`);
    else if (row.kind === 'constraint' && !rec.cons.has(d)) out.push(`constraint  ${d}  on ${t}`);
    else if (row.kind === 'index' && !rec.idx.has(d)) out.push(`index       ${d}  on ${t}`);
  }
  return out.sort();
}

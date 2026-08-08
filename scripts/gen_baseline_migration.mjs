// Generate the BASELINE migration: create the tables that exist on production but that no
// migration in supabase/migrations/ ever creates.
//
//   node scripts/gen_baseline_migration.mjs
//
// ── WHY THIS FILE HAS TO EXIST ──────────────────────────────────────────────────────────────────
// The Supabase Preview check builds a fresh branch and replays every migration in filename order.
// It had never passed. Once the 20260724 ordering was fixed it got further and then died on
// `relation "public.decision_policy" does not exist` — a different defect and a much older one.
//
// Thirty-five public tables, including leads, inquiries, documents and reviews, are ALTERed,
// INSERTed into and INDEXed by migrations, and created by none of them. They exist on production
// and staging because somebody made them directly in the database and never wrote the file. The
// written history therefore starts partway through: it can describe the database but it cannot
// rebuild it, which is why no fresh environment has ever been buildable from this repo.
//
// This generator reads the REAL shape of each table out of production's catalog and writes it as
// the first migration in the folder. It is generated, never hand-typed, for the same reason
// promote_rows_to_production.mjs reads values back rather than retyping them: a hand-copied column
// type or default is a silent divergence between the rebuilt database and the real one.
//
// ── EVERYTHING IT EMITS IS IDEMPOTENT, AND THAT IS WHAT MAKES IT SAFE ───────────────────────────
// `create table if not exists`, `create index if not exists`, and constraints added only when a
// constraint of that name is absent. Production and staging already have all of it, so applying
// this file there changes nothing at all — measured, not asserted, by the caller running
// check_migration_order.mjs afterwards. On an empty database it is the missing foundation.
//
// ── AND IT IS ORDERED SO IT CAN ACTUALLY RUN ───────────────────────────────────────────────────
// Tables first with no foreign keys attached, then every foreign key afterwards. Emitting FKs
// inline would reintroduce exactly the ordering bug this whole exercise is about: a table
// referencing another that has not been created yet.
import { writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { mgmtRead, PROD_REF } from './staging/qd_guard.mjs';

const OUT = 'supabase/migrations/00000000000000_baseline_tables_created_out_of_band.sql';

// Excluding its own output is what makes this re-runnable. Analysing a tree that already contains
// the baseline reports nothing missing, and the generator would then overwrite a good file with an
// empty one — a regenerate that silently undoes itself.
const analysis = JSON.parse(execFileSync('node',
  ['scripts/check_migration_order.mjs', '--json', `--exclude=${OUT.split('/').pop()}`],
  { encoding: 'utf8' }));
const wanted = analysis.missingPublic.map((m) => m.table);
console.log(`${wanted.length} table(s) reported missing by check_migration_order`);

const q = (sql) => mgmtRead(PROD_REF, sql);
const lit = wanted.map((t) => `'${t}'`).join(',');

// Only tables that REALLY exist on production. `_cand` is a CTE name the DDL scanner reads as a
// table; asking the catalog rather than trusting the scanner drops it without a special case.
const real = (await q(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relname in (${lit}) order by 1`)).map((r) => r.relname);
const notReal = wanted.filter((t) => !real.includes(t));
console.log(`${real.length} exist on production${notReal.length ? `; not real tables, skipped: ${notReal.join(', ')}` : ''}`);

const rlit = real.map((t) => `'${t}'`).join(',');

// ── COLUMNS, with the exact stored type, default, nullability and identity ──────────────────────
const cols = await q(`
  select c.relname tbl, a.attname col, format_type(a.atttypid, a.atttypmod) typ,
         a.attnotnull notnull, pg_get_expr(d.adbin, d.adrelid) def,
         a.attidentity ident, a.attgenerated gen, a.attnum
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where n.nspname='public' and c.relname in (${rlit}) and a.attnum > 0 and not a.attisdropped
  order by c.relname, a.attnum`);

// ── CONSTRAINTS. Non-FK go inline; FK are emitted after every table exists ──────────────────────
const cons = await q(`
  select c.relname tbl, con.conname name, con.contype typ, pg_get_constraintdef(con.oid) def
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname in (${rlit})
  order by c.relname, con.contype, con.conname`);

// ── INDEXES, minus the ones a constraint already creates ───────────────────────────────────────
const idx = await q(`
  select c.relname tbl, i.relname name, pg_get_indexdef(x.indexrelid) def
  from pg_index x
  join pg_class i on i.oid = x.indexrelid
  join pg_class c on c.oid = x.indrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relname in (${rlit})
    and not exists (select 1 from pg_constraint con where con.conindid = x.indexrelid)
  order by c.relname, i.relname`);

const rls = await q(`select c.relname tbl, c.relrowsecurity rls
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in (${rlit})`);

// Types the tables use that Postgres does not ship: enums must be created, extensions installed.
const enums = await q(`
  select distinct t.typname, n2.nspname sch,
         (select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder)
          from pg_enum e where e.enumtypid = t.oid) labels
  from pg_attribute a
  join pg_class c on c.oid=a.attrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_type t on t.oid = a.atttypid
  join pg_namespace n2 on n2.oid = t.typnamespace
  where n.nspname='public' and c.relname in (${rlit}) and a.attnum>0 and not a.attisdropped
    and t.typtype='e'`);

const exts = await q(`
  select distinct e.extname
  from pg_attribute a
  join pg_class c on c.oid=a.attrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_type t on t.oid=a.atttypid
  join pg_depend dep on dep.objid = t.oid and dep.refclassid = 'pg_extension'::regclass
  join pg_extension e on e.oid = dep.refobjid
  where n.nspname='public' and c.relname in (${rlit}) and a.attnum>0 and not a.attisdropped`);

const by = (rows, key) => rows.reduce((m, r) => ((m[r[key]] ||= []).push(r), m), {});
const C = by(cols, 'tbl'), K = by(cons, 'tbl'), I = by(idx, 'tbl');
const rlsOn = new Set(rls.filter((r) => r.rls === true || r.rls === 't').map((r) => r.tbl));

const colDDL = (c) => {
  let s = `  ${c.col} ${c.typ}`;
  if (c.ident === 'a') s += ' generated always as identity';
  else if (c.ident === 'd') s += ' generated by default as identity';
  else if (c.gen === 's' && c.def) s += ` generated always as (${c.def}) stored`;
  else if (c.def !== null && c.def !== undefined) s += ` default ${c.def}`;
  if (c.notnull === true || c.notnull === 't') s += ' not null';
  return s;
};

const out = [];
out.push(`-- ==============================================================================================`);
out.push(`-- BASELINE — the tables this repository's migration history never created.`);
out.push(`--`);
out.push(`-- Generated by scripts/gen_baseline_migration.mjs from production's catalog. Do not hand-edit:`);
out.push(`-- re-run the generator instead, so the file cannot drift from the database it describes.`);
out.push(`--`);
out.push(`-- ${real.length} table(s) are ALTERed, INSERTed into and INDEXed by later migrations and created by`);
out.push(`-- none of them. They exist on production and staging because they were made directly in the`);
out.push(`-- database, so the written history could describe this platform but never rebuild it. That is`);
out.push(`-- why the Supabase Preview check — which replays onto an EMPTY database — had never passed.`);
out.push(`--`);
out.push(`-- Every statement is idempotent. On production and staging this file is a no-op in full; on an`);
out.push(`-- empty database it is the foundation everything after it assumes.`);
out.push(`--`);
out.push(`-- Foreign keys come after every table, never inline, because an inline reference to a table`);
out.push(`-- created later is the exact defect this baseline exists to end.`);
out.push(`-- ==============================================================================================`);
out.push('');

if (exts.length) {
  out.push('-- Extensions the column types depend on.');
  for (const e of exts) out.push(`create extension if not exists ${e.extname};`);
  out.push('');
}

// ── SEQUENCES BEFORE TABLES, BECAUSE A serial COLUMN DOES NOT CREATE ITS OWN ───────────────────
// The first generated draft emitted `id bigint default nextval('agent_knowledge_id_seq'::regclass)`
// and nothing that creates that sequence — so the baseline would have failed on an empty database
// at the very first table, which is precisely the class of bug it exists to remove. Identity
// columns (`generated always as identity`) DO create their own and must not be listed here, so the
// sequences are taken from the nextval() defaults themselves rather than from pg_depend, which
// cannot tell the two apart without more care than the distinction deserves.
const seqs = [...new Set(cols
  .map((c) => (c.def || '').match(/nextval\('(?:public\.)?"?([a-z0-9_]+)"?'/i))
  .filter(Boolean).map((m) => m[1]))].sort();
if (seqs.length) {
  out.push('-- Sequences backing serial-style defaults. Identity columns are not here: they make their own.');
  for (const s of seqs) out.push(`create sequence if not exists public.${s};`);
  out.push('');
}
if (enums.length) {
  out.push('-- Enum types used by these columns.');
  for (const e of enums) {
    out.push(`do $$ begin`);
    out.push(`  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace`);
    out.push(`                 where t.typname='${e.typname}' and n.nspname='${e.sch}') then`);
    out.push(`    create type ${e.sch}.${e.typname} as enum (${e.labels});`);
    out.push(`  end if;`);
    out.push(`end $$;`);
  }
  out.push('');
}

const fks = [];
for (const t of real) {
  const inline = (K[t] || []).filter((k) => k.typ !== 'f');
  for (const k of (K[t] || []).filter((k) => k.typ === 'f')) fks.push({ tbl: t, ...k });

  out.push(`-- ── public.${t} ${'─'.repeat(Math.max(0, 78 - t.length))}`);
  out.push(`create table if not exists public.${t} (`);
  const body = (C[t] || []).map(colDDL);
  for (const k of inline) body.push(`  constraint ${k.name} ${k.def}`);
  out.push(body.join(',\n'));
  out.push(`);`);
  if (rlsOn.has(t)) out.push(`alter table public.${t} enable row level security;`);
  for (const x of (I[t] || [])) {
    // pg_get_indexdef has no IF NOT EXISTS; inject it so a re-run is a no-op.
    out.push(x.def.replace(/^CREATE (UNIQUE )?INDEX /i, (m, u) => `create ${u ? 'unique ' : ''}index if not exists `) + ';');
  }
  out.push('');
}

if (fks.length) {
  out.push(`-- ── FOREIGN KEYS, once every table above exists ─────────────────────────────────────────────`);
  for (const f of fks) {
    out.push(`do $$ begin`);
    out.push(`  if not exists (select 1 from pg_constraint where conname='${f.name}'`);
    out.push(`                 and conrelid='public.${f.tbl}'::regclass) then`);
    out.push(`    alter table public.${f.tbl} add constraint ${f.name} ${f.def};`);
    out.push(`  end if;`);
    out.push(`end $$;`);
  }
  out.push('');
}

writeFileSync(OUT, out.join('\n'));
console.log(`\nwrote ${OUT}`);
console.log(`  ${real.length} table(s), ${cols.length} column(s), ${cons.length} constraint(s) `
  + `(${fks.length} foreign key(s)), ${idx.length} index(es), ${enums.length} enum(s), ${exts.length} extension(s)`);
console.log(`  RLS enabled on ${rlsOn.size} of ${real.length}`);

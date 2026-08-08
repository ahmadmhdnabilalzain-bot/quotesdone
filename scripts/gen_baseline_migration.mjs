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

const OUT = 'supabase/migrations/20200101000000_baseline_tables_created_out_of_band.sql';
// ── THE FOREIGN KEYS GO LAST, IN THEIR OWN MIGRATION, AND THIS WAS LEARNED THE HARD WAY ─────────
// The first version put every foreign key at the end of the baseline. It failed on a real fresh
// database at statement 134: company_goals references org_departments, and org_departments is
// created by 20260724020640_org_foundation — which runs AFTER the baseline. Keeping the FKs inside
// the baseline only avoids the ordering trap WITHIN the file while walking straight into it across
// the file boundary.
//
// So they move to a migration that sorts after every existing one. By then every table in the tree
// exists, whoever created it, and a foreign key cannot reference something that is not there yet.
const OUT_FK = 'supabase/migrations/20991231235959_baseline_foreign_keys.sql';

// Excluding its own output is what makes this re-runnable. Analysing a tree that already contains
// the baseline reports nothing missing, and the generator would then overwrite a good file with an
// empty one — a regenerate that silently undoes itself.
const q = (sql) => mgmtRead(PROD_REF, sql);

// ── --all: THE WHOLE SCHEMA, BECAUSE "ONLY WHAT IS MISSING" WAS THE WRONG QUESTION ─────────────
// A baseline of just the uncreated TABLES got a clean replay 103 migrations deep and then died on
// `column i.pipeline_stage does not exist` — a view referencing a column that no migration adds.
// Tables were never the unit of the problem. This database was built by hand alongside its
// migrations, so the gaps are tables AND columns AND whatever comes next, and chasing them one
// replay at a time converges only by luck.
//
// So the baseline creates EVERY public table with EVERY current column, and the entire class of
// "does not exist" disappears in one move rather than one round per object. The 736 historical
// migrations still run on top; measured across all of them, only fourteen statements are not
// idempotent (6 create table, 5 add column, 3 create index), and those are fixed at the source.
let real;
if (process.argv.includes('--all')) {
  real = (await q(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' order by 1`)).map((r) => r.relname);
  console.log(`--all: ${real.length} public table(s) on production`);
} else {
  const analysis = JSON.parse(execFileSync('node',
    ['scripts/check_migration_order.mjs', '--json',
      `--exclude=${OUT.split('/').pop()},${OUT_FK.split('/').pop()}`],
    { encoding: 'utf8' }));
  const wanted = analysis.missingPublic.map((m) => m.table);
  console.log(`${wanted.length} table(s) reported missing by check_migration_order`);
  const lit = wanted.map((t) => `'${t}'`).join(',');
  // Only tables that REALLY exist on production. `_cand` is a CTE name the DDL scanner reads as a
  // table; asking the catalog rather than trusting the scanner drops it without a special case.
  real = (await q(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relname in (${lit}) order by 1`)).map((r) => r.relname);
  const notReal = wanted.filter((t) => !real.includes(t));
  console.log(`${real.length} exist on production${notReal.length ? `; not real tables, skipped: ${notReal.join(', ')}` : ''}`);
}

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

// ── EVERY EXTENSION PRODUCTION HAS, NOT JUST THE ONES A COLUMN TYPE NEEDS ──────────────────────
// The first version asked which extensions the COLUMN TYPES depend on and emitted exactly one:
// vector. A fresh database then died on `select cron.unschedule(jobid) from cron.job` — pg_cron
// provides no column type, so nothing pointed at it, and a migration that schedules a job cannot
// run without it. The same is true of pg_net for outbound calls and pg_trgm for a search index.
//
// An extension is part of the database's shape whether or not a column happens to be typed by it,
// so the list now comes from pg_extension itself. plpgsql is always present and supabase_vault is
// managed by the platform; the rest are installed, in the schema production keeps them in, because
// code that calls extensions.crypt() breaks if pgcrypto lands somewhere else.
const exts = await q(`select e.extname, n.nspname sch
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname not in ('plpgsql', 'supabase_vault')
  order by e.extname`);

// ── ANYTHING THAT CALLS A USER FUNCTION HAS TO WAIT FOR THAT FUNCTION ──────────────────────────
// The full-schema baseline died at statement 1032 on public.quotes:
//
//     ERROR: function margin_rate(numeric) does not exist
//
// A column default calling a function that a later migration creates. The baseline runs first by
// design, so every user function it depends on is by definition not there yet — and the fix is the
// one already used for foreign keys: emit the column without the default, and set the default in
// the trailing migration once the whole history has run and the functions exist.
//
// The same is true of CHECK constraints and index expressions, so all three are tested against the
// same list rather than fixing only the one that happened to fail first.
const userFns = new Set((await q(`select distinct p.proname from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname='public'`)).map((r) => r.proname));
const usesUserFn = (text) => {
  if (!text) return false;
  for (const m of String(text).matchAll(/\b([a-z_][a-z0-9_]*)\s*\(/gi)) {
    if (userFns.has(m[1].toLowerCase())) return true;
  }
  return false;
};

const by = (rows, key) => rows.reduce((m, r) => ((m[r[key]] ||= []).push(r), m), {});
const C = by(cols, 'tbl'), K = by(cons, 'tbl'), I = by(idx, 'tbl');
const rlsOn = new Set(rls.filter((r) => r.rls === true || r.rls === 't').map((r) => r.tbl));

// ── GENERATED COLUMNS CANNOT WAIT, SO THEIR FUNCTIONS MUST COME FIRST ──────────────────────────
// public.quotes has three:
//
//     margin_rate    numeric generated always as (margin_rate(quote_amount)) stored,
//     app_fee        numeric generated always as (round(quote_amount * margin_rate(quote_amount), 2)) stored,
//     customer_price numeric generated always as (...) stored,
//
// margin_rate is a column AND a user function, which is also why the first detector missed it: it
// only inspected DEFAULTS, and a generated expression takes a different branch.
//
// A default or a CHECK can be deferred to the trailing migration. A generated column cannot — the
// expression is part of the column definition, so the function has to exist when the table is
// created. Those few functions are therefore emitted BEFORE the tables, with
// `set check_function_bodies = off` so a body referencing a table that does not exist yet is not
// validated at creation time. That is exactly what pg_dump does, and for exactly this reason.
//
// Only the functions the column expressions actually need are emitted. Emitting all 590 would drag
// in the ones whose parameters are TABLE types (fn_supplier_capability_score(l leads)), and those
// genuinely cannot be created before their table — the later migrations create them in due course.
const exprFnNames = new Set();
for (const c of cols) {
  const expr = (c.gen === 's' && c.def) ? c.def : null;
  if (!expr) continue;
  for (const m of String(expr).matchAll(/\b([a-z_][a-z0-9_]*)\s*\(/gi)) {
    if (userFns.has(m[1].toLowerCase())) exprFnNames.add(m[1].toLowerCase());
  }
}
const exprFns = exprFnNames.size ? await q(`
  select p.proname, pg_get_functiondef(p.oid) def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname in (${[...exprFnNames].map((x) => `'${x}'`).join(',')})
    -- Skip any whose parameters are table types; those cannot exist before their table.
    and not exists (
      select 1 from unnest(p.proargtypes) at(oid)
      join pg_class rc on rc.reltype = at.oid
      join pg_namespace rn on rn.oid = rc.relnamespace
      where rn.nspname = 'public' and rc.relkind = 'r')
  order by p.proname`) : [];

// Defaults that call a user function are collected here and applied by the trailing migration.
const deferredDefaults = [];
const colDDL = (c) => {
  let s = `  ${c.col} ${c.typ}`;
  if (c.ident === 'a') s += ' generated always as identity';
  else if (c.ident === 'd') s += ' generated by default as identity';
  else if (c.gen === 's' && c.def) s += ` generated always as (${c.def}) stored`;
  else if (c.def !== null && c.def !== undefined) {
    if (usesUserFn(c.def)) deferredDefaults.push({ tbl: c.tbl, col: c.col, def: c.def });
    else s += ` default ${c.def}`;
  }
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
  out.push('-- Extensions, in the schema production keeps them in. pg_cron is what a migration that');
  out.push('-- schedules a job needs, and no column type points at it — hence the whole list, not a subset.');
  const schemas = [...new Set(exts.map((e) => e.sch))].filter((s) => s !== 'public' && s !== 'pg_catalog');
  for (const s of schemas) out.push(`create schema if not exists ${s};`);
  for (const e of exts) {
    // pg_catalog cannot be named as a target schema; those extensions install there by default.
    const where = e.sch === 'pg_catalog' ? '' : ` with schema ${e.sch}`;
    out.push(`create extension if not exists "${e.extname}"${where};`);
  }
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

if (exprFns.length) {
  out.push('-- Functions that GENERATED columns call. A generated expression is part of the column');
  out.push('-- definition, so unlike a default it cannot be deferred — the function must already exist.');
  out.push('-- check_function_bodies is off so a body referencing a not-yet-created table still loads,');
  out.push('-- which is the same thing pg_dump does and for the same reason.');
  out.push('set check_function_bodies = off;');
  for (const f of exprFns) out.push(f.def.trimEnd() + (f.def.trimEnd().endsWith(';') ? '' : ';'));
  out.push('reset check_function_bodies;');
  out.push('');
}

const fks = [];
const deferredCons = [];
const deferredIdx = [];
for (const t of real) {
  // A CHECK calling a user function waits for the same reason a default does.
  const inline = (K[t] || []).filter((k) => k.typ !== 'f' && !usesUserFn(k.def));
  for (const k of (K[t] || []).filter((k) => k.typ !== 'f' && usesUserFn(k.def))) deferredCons.push({ tbl: t, ...k });
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
    const ddl = x.def.replace(/^CREATE (UNIQUE )?INDEX /i, (m, u) => `create ${u ? 'unique ' : ''}index if not exists `) + ';';
    if (usesUserFn(x.def)) deferredIdx.push({ tbl: t, ddl });
    else out.push(ddl);
  }
  out.push('');
}

writeFileSync(OUT, out.join('\n'));

// ── THE FOREIGN KEYS, AS THE LAST MIGRATION IN THE TREE ────────────────────────────────────────
const fkOut = [];
fkOut.push(`-- ==============================================================================================`);
fkOut.push(`-- BASELINE, PART 2 — the foreign keys of the tables the history never created.`);
fkOut.push(`--`);
fkOut.push(`-- Generated by scripts/gen_baseline_migration.mjs. Do not hand-edit; re-run the generator.`);
fkOut.push(`--`);
fkOut.push(`-- These are separated from the baseline itself and dated to run LAST, and the reason is a`);
fkOut.push(`-- failure rather than a preference. With the FKs at the end of the baseline, a real fresh`);
fkOut.push(`-- database died at statement 134: public.company_goals references org_departments, which is`);
fkOut.push(`-- created by 20260724020640_org_foundation — a migration that runs AFTER the baseline. A`);
fkOut.push(`-- foreign key can only be added once BOTH tables exist, and for these tables that moment is`);
fkOut.push(`-- not the start of the history but the end of it.`);
fkOut.push(`--`);
fkOut.push(`-- Each is guarded on the constraint's absence, so production and staging — which have every`);
fkOut.push(`-- one of them already — are untouched.`);
fkOut.push(`-- ==============================================================================================`);
fkOut.push('');
for (const f of fks) {
  fkOut.push(`do $$ begin`);
  fkOut.push(`  if not exists (select 1 from pg_constraint where conname='${f.name}'`);
  fkOut.push(`                 and conrelid='public.${f.tbl}'::regclass) then`);
  fkOut.push(`    alter table public.${f.tbl} add constraint ${f.name} ${f.def};`);
  fkOut.push(`  end if;`);
  fkOut.push(`end $$;`);
}

// Defaults, CHECKs and indexes that call a user function. They are here rather than in the baseline
// because the baseline runs before any migration has created those functions.
if (deferredDefaults.length) {
  fkOut.push('');
  fkOut.push(`-- ── COLUMN DEFAULTS THAT CALL A USER FUNCTION ───────────────────────────────────────────────`);
  for (const d of deferredDefaults) {
    fkOut.push(`alter table public.${d.tbl} alter column ${d.col} set default ${d.def};`);
  }
}
if (deferredCons.length) {
  fkOut.push('');
  fkOut.push(`-- ── CHECK CONSTRAINTS THAT CALL A USER FUNCTION ─────────────────────────────────────────────`);
  for (const k of deferredCons) {
    fkOut.push(`do $$ begin`);
    fkOut.push(`  if not exists (select 1 from pg_constraint where conname='${k.name}'`);
    fkOut.push(`                 and conrelid='public.${k.tbl}'::regclass) then`);
    fkOut.push(`    alter table public.${k.tbl} add constraint ${k.name} ${k.def};`);
    fkOut.push(`  end if;`);
    fkOut.push(`end $$;`);
  }
}
if (deferredIdx.length) {
  fkOut.push('');
  fkOut.push(`-- ── INDEXES WHOSE EXPRESSION CALLS A USER FUNCTION ──────────────────────────────────────────`);
  for (const x of deferredIdx) fkOut.push(x.ddl);
}
fkOut.push('');
writeFileSync(OUT_FK, fkOut.join('\n'));

console.log(`\nwrote ${OUT}`);
console.log(`wrote ${OUT_FK}  (${fks.length} FK, ${deferredDefaults.length} deferred default(s), ${deferredCons.length} deferred check(s), ${deferredIdx.length} deferred index(es); runs last)`);
console.log(`  ${real.length} table(s), ${cols.length} column(s), ${cons.length} constraint(s) `
  + `(${fks.length} foreign key(s)), ${idx.length} index(es), ${enums.length} enum(s), ${exts.length} extension(s)`);
console.log(`  RLS enabled on ${rlsOn.size} of ${real.length}`);

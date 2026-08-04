// sync_staging_grants.mjs — restore the table privileges that dropping schema public destroys.
//
// WHY THIS EXISTS
// rebuild_staging drops and recreates schema public. That also destroys the schema's DEFAULT
// PRIVILEGES, so every table created afterwards is owned by postgres and granted to nobody else.
// Schema-level USAGE is not table-level SELECT, and the difference is invisible until something
// reads a row: PostgREST answered
//
//   403 {"code":"42501","message":"permission denied for table customers"}
//
// and supabase-js in the Edge Functions discards that error, so customer_api returned
// {"customer": null} and then crashed dereferencing it. The whole customer journey failed on a
// missing GRANT, three layers away from where it looked like a null-handling bug.
//
// Production is the source of truth for WHO gets what: postgres and service_role hold full
// privileges, while anon and authenticated hold SELECT on a small, deliberate handful. This
// copies that shape rather than granting broadly to make the error go away.
//
//   node scripts/staging/sync_staging_grants.mjs [--apply]
import { mgmtRead, mgmtWrite, PROD_REF, assertNotProduction } from './qd_guard.mjs';

const REF = assertNotProduction(process.env.QD_STAGING_REF || 'pglpqrhvozwepymcuunn', 'grant sync');
const APPLY = process.argv.includes('--apply');

const GRANT_Q = `select grantee, table_name, string_agg(distinct privilege_type, ',' order by privilege_type) as privs
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon','authenticated')
  group by grantee, table_name order by grantee, table_name`;

const narrow = await mgmtRead(PROD_REF, GRANT_Q);
console.log(`production grants ${narrow.length} explicit anon/authenticated table grant(s)`);
for (const g of narrow) console.log(`   ${g.grantee.padEnd(14)} ${g.table_name.padEnd(34)} ${g.privs}`);

// postgres and service_role hold everything on every relation in production, and future objects
// must inherit it - otherwise the next migration reintroduces exactly this outage.
const broad = [
  'grant usage on schema public to postgres, anon, authenticated, service_role',
  'grant all privileges on all tables in schema public to postgres, service_role',
  'grant all privileges on all sequences in schema public to postgres, service_role',
  'grant all privileges on all functions in schema public to postgres, service_role',
  'alter default privileges in schema public grant all on tables to postgres, service_role',
  'alter default privileges in schema public grant all on sequences to postgres, service_role',
  'alter default privileges in schema public grant all on functions to postgres, service_role',
];

if (!APPLY) {
  console.log('\nwould run:');
  for (const s of broad) console.log('   ' + s);
  console.log(`   + ${narrow.length} targeted grant(s) for anon/authenticated`);
  console.log('\nDRY RUN - nothing applied. Re-run with --apply.');
  process.exit(0);
}

let ok = 0, bad = 0;
for (const s of broad) {
  try { await mgmtWrite(REF, s, 'grant'); ok++; console.log('ok   ' + s); }
  catch (e) { bad++; console.log('FAIL ' + s + '\n     ' + String(e.message).slice(0, 160)); }
}
for (const g of narrow) {
  const sql = `grant ${g.privs} on public.${g.table_name} to ${g.grantee}`;
  try { await mgmtWrite(REF, sql, 'grant'); ok++; }
  catch (e) { bad++; console.log('FAIL ' + sql + '\n     ' + String(e.message).slice(0, 160)); }
}

const after = await mgmtRead(REF,
  `select grantee, count(distinct table_name) as tables from information_schema.role_table_grants
   where table_schema='public' group by grantee order by 2 desc`);
console.log(`\napplied ${ok}, failed ${bad}`);
console.log('staging grants now:');
for (const x of after) console.log(`   ${String(x.tables).padStart(4)} tables  ${x.grantee}`);
process.exitCode = bad ? 1 : 0;

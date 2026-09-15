// A REVERSED SUPPLIER CHARGE IS NEVER OWED (15 Sep 2026, agent: accountant).
//
// Every routine that reminds, demands, accrues or counts a supplier due as receivable asks ONE
// predicate, public.fn_supplier_due_is_owed(status, paid_at), instead of spelling its own closed list.
// Each used to spell one and none listed 'reversed' (scripts/sql/a_reversed_supplier_charge_is_never_owed.sql).
// This fails if a dues routine's canonical definition (the last scripts/sql file in MANIFEST.txt that
// defines it) stops asking the predicate, or if the predicate drops 'reversed' or 'void'.
// Production reads skip without a management token (CI's checks job has none).
//
//   node --test scripts/checks/a_reversed_supplier_charge_is_never_owed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
const q = async (query) => {
  const r = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, read_only: true }),
  });
  const text = await r.text();
  assert.ok(r.ok, `query failed: ${r.status} ${text}`);
  return JSON.parse(text);
};

const PREDICATE = 'fn_supplier_due_is_owed';
export const DUES_ROUTINES = [
  'fn_accountant_collections_tick', 'fn_supplier_dues_accrue_interest', 'fn_ban_overdue_dues',
  'fn_accountant_record_court_step', 'fn_accountant_dues_aging', 'fn_accountant_month_close_figures',
  'fn_accountant_recovery_position', 'fn_finance_forecast', 'fn_ws_finance', 'fn_ws_supplier_360', 'fn_ops_dashboard',
];
// fn_accountant_recovery_position reads v_accountant_recovery_ledger, whose `owed` column IS the predicate;
// it asks by filtering on that column. Every other routine names the predicate itself.
const VIA_LEDGER = 'fn_accountant_recovery_position';
const asks = (name, body) => (name === VIA_LEDGER ? /filter \(where owed\)/.test(body) : body.includes(PREDICATE));
const manifest = () => read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((s) => s.trim()).filter((s) => s && !s.startsWith('#'));

// The body of the LAST definition of public.<name> across the files, in MANIFEST order.
function canonicalBody(name) {
  const head = new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\(`, 'gi');
  let found = null;
  for (const f of manifest()) {
    if (!existsSync(join(root, f))) continue;
    const s = read(f);
    for (const m of s.matchAll(head)) {
      const tag = s.slice(m.index).match(/\bas\s+(\$[a-z_]*\$)/i);
      if (!tag) continue;
      const start = m.index + tag.index + tag[0].length;
      const end = s.indexOf(tag[1], start);
      found = { file: f, body: s.slice(start, end) };
    }
  }
  return found;
}

test('the predicate names reversed and void as not owed', () => {
  const s = read('scripts/sql/a_reversed_supplier_charge_is_never_owed.sql');
  const def = s.match(/function public\.fn_supplier_due_is_owed\(p_status text, p_paid_at timestamptz\)[\s\S]*?\$fn\$([\s\S]*?)\$fn\$/);
  assert.ok(def, 'the predicate definition is missing');
  assert.match(def[1], /p_paid_at is null/);
  for (const st of ['paid', 'settled', 'waived', 'cancelled', 'reversed', 'void']) assert.match(def[1], new RegExp(`'${st}'`), `the predicate drops '${st}'`);
  assert.match(s, /revoke execute on function public\.fn_supplier_due_is_owed\(text, timestamptz\) from public, anon, authenticated/);
});

test('every dues routine, as canonically defined, asks the predicate', () => {
  const missing = [];
  for (const name of DUES_ROUTINES) {
    const c = canonicalBody(name);
    if (!c) { missing.push(`${name}: no scripts/sql definition`); continue; }
    if (!asks(name, c.body)) missing.push(`${name} (${c.file}) does not ask ${PREDICATE}`);
  }
  assert.deepEqual(missing, []);
  // The ledger's stage names a closed charge by its status, and `owed` is the predicate.
  const s = read('scripts/sql/a_reversed_supplier_charge_is_never_owed.sql');
  assert.match(s, /when not public\.fn_supplier_due_is_owed\(d\.status, d\.paid_at\) then d\.status/);
  assert.match(s, /public\.fn_supplier_due_is_owed\(d\.status, d\.paid_at\) as owed/);
});

test('production: every dues routine and both views ask the predicate, and it answers correctly', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const [row] = await q(`select
      (select json_agg(p.proname order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname = any (array[${DUES_ROUTINES.map((n) => `'${n}'`).join(',')}])
         and case when p.proname = '${VIA_LEDGER}' then p.prosrc not like '%filter (where owed)%'
                  else p.prosrc not like '%${PREDICATE}%' end) as not_asking,
      (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname = any (array[${DUES_ROUTINES.map((n) => `'${n}'`).join(',')}]))::int as found,
      pg_get_viewdef('public.finance_kpis'::regclass) like '%${PREDICATE}%' as kpis,
      pg_get_viewdef('public.v_accountant_recovery_ledger'::regclass) like '%${PREDICATE}%' as ledger,
      public.${PREDICATE}('reversed', null) as reversed, public.${PREDICATE}('void', null) as void,
      public.${PREDICATE}('pending', null) as pending, public.${PREDICATE}('legal', null) as legal`);
  assert.equal(row.found, DUES_ROUTINES.length);
  assert.equal(row.not_asking, null, `not asking the predicate: ${JSON.stringify(row.not_asking)}`);
  assert.equal(row.kpis, true);
  assert.equal(row.ledger, true);
  assert.deepEqual([row.reversed, row.void, row.pending, row.legal], [false, false, true, true]);
});

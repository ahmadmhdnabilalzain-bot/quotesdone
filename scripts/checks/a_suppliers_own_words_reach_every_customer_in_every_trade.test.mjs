// A SUPPLIER'S OWN WORDS REACH EVERY CUSTOMER WHO ASKS FOR THE SAME WORK, IN EVERY TRADE (10 Nov 2026, sales_engineer;
// founder ledger 1573, 1579, 1586). The shape of the change, read offline:
//   * the probe's matrix is the fixture's (one matrix: general_matching.test.ts proves text -> codes over it, the probe
//     proves codes -> suppliers on production);
//   * the SQL keeps matching on CODES: a curated, reviewed alias queue; adjacency one level only; a supplier reached
//     through a named service's trade or an adjacent trade must hold a named service; the similarity weight is in the
//     ranking and nowhere in the gate; every new table and routine is closed to the public roles;
//   * the file is committed and pending (no MANIFEST line until it is applied), and its probe is noted as a probe;
//   * the Services tab offers the documents' services UNTICKED (founder 862), the save files his phrases, and the request
//     carries the keys its conversation state chose (inquiry_create, the intake count).
//   node --test scripts/checks/a_suppliers_own_words_reach_every_customer_in_every_trade.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const sql = R(FILE);
const body = (fn) => {
  const at = sql.indexOf(`create or replace function public.${fn}(`);
  assert.ok(at >= 0, `${fn} is not defined in ${FILE}`);
  const tag = sql.slice(at).match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  return code(sql.slice(at).split(tag)[1]);
};

test('the probe asks production the fixture\'s matrix, row for row', () => {
  const fx = JSON.parse(R('supabase/functions/_shared/general_matching.fixtures.json'));
  const lit = R(PROBE).match(/\$mx\$([\s\S]*?)\$mx\$/);
  assert.ok(lit, 'the probe carries no $mx$ matrix literal');
  const mx = JSON.parse(lit[1]);
  const want = fx.rows.map((r) => ({ f: r.family, st: r.supplier.trade, sk: r.supplier.keys, ct: r.customer.trade, ck: r.customer.keys, control: r.control }));
  assert.deepEqual(mx.rows, want, 'the probe\'s rows are not the fixture\'s (regenerate the literal from the fixture)');
  assert.deepEqual(mx.conf.map((c) => c.name), fx.confusables.map((c) => c.name));
  assert.ok(mx.rows.length >= 40 && new Set(fx.rows.map((r) => r.group)).size === 12, 'the matrix no longer spans the 12 groups');
  assert.match(R(PROBE), /raise exception 'CHK<<%>>'/, 'the probe does not end in its rolled-back verdict');
  // its suppliers are the factory-built ZZ DEMO ones at @example.invalid; it creates none (an approved supplier needs the six)
  assert.match(R(PROBE), /company_name ~\* '\^\\s\*zz\\s\*demo' and l\.email like '%@example\.invalid'/, 'the probe\'s suppliers are not ZZ DEMO at @example.invalid');
  assert.doesNotMatch(code(R(PROBE)), /insert into public\.leads/, 'the probe creates a supplier');
});

test('matching stays on codes: the reach is one level, the trade-level pass is the request\'s own trades, similarity only ranks', () => {
  const m = body('fn_match_capability');
  assert.doesNotMatch(m, /with\s+recursive/i, 'a recursive walk appeared over the adjacency or implication map');
  assert.match(m, /reach as \([\s\S]*taxonomy_trade_adjacent j on j\.active[\s\S]*where \(select k from n\) > 0/, 'the adjacency is not limited to a request that names a service');
  assert.match(m, /and sc\.trades && \(select codes from reach\)/, 'the candidate gate does not read the reach');
  assert.match(m, /or \(c\.never_asked and c\.direct\)/, 'a supplier reached only through the reach passes at trade level');
  const gate = m.slice(m.indexOf('scored as ('), m.indexOf('ranked as ('));
  const where = gate.slice(gate.lastIndexOf('from svc c'));
  assert.doesNotMatch(where, /sim/, 'the similarity signal decides who is matched');
  assert.match(m.slice(m.indexOf('ranked as (')), /\+ w\.w_sim\s+\* s\.sim/, 'the similarity signal is not in the ranking');
  // the gates the matcher already had
  for (const g of [/sc\.confirmed_at is not null/, /public\.fn_is_matchable\(/, /public\.fn_supplier_available\(av\.state, av\.busy_until\)/,
                   /not exists \(\s*select 1 from unnest\(\(select codes from req_auth\)\) a/]) assert.match(m, g, `a gate is gone: ${g}`);
  assert.doesNotMatch(m, /\bilike\b|similarity\s*\(|%>/, 'a word or trigram comparison appeared in the matcher');
});

test('the alias queue is reviewed rows: only an approval writes an alias, and never one that names another service', () => {
  const d = body('fn_service_alias_decide');
  assert.match(d, /if p_decision = 'approved' then[\s\S]*fn_service_alias_owners\(p\.phrase_norm\)[\s\S]*alias_names_another_service[\s\S]*update public\.taxonomy_trade_service/, 'an approval does not check the other owners before it writes');
  assert.match(d, /decider_required/, 'a decision without a decider is accepted');
  const p = body('fn_service_alias_propose');
  assert.doesNotMatch(p, /update public\.taxonomy_trade_service/, 'proposing writes an alias');
  assert.match(sql, /source in \('supplier_confirmed', 'profile', 'curated'\)/);
});

test('every new table has RLS, a deliberate policy and no public grant; every new routine is pinned and revoked', () => {
  for (const t of ['service_alias_proposal', 'taxonomy_trade_adjacent']) {
    assert.match(sql, new RegExp(`alter table public\\.${t} enable row level security`), `${t}: RLS`);
    assert.match(sql, new RegExp(`create policy ${t}_service_role_only on public\\.${t}\\s+as permissive for all to public using \\(false\\) with check \\(false\\)`), `${t}: policy`);
    assert.match(sql, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t}: revoke`);
  }
  for (const [fn, sig] of [['fn_service_alias_norm', 'text'], ['fn_service_alias_owners', 'text'], ['fn_service_alias_propose', 'bigint, jsonb, text'], ['fn_service_alias_decide', 'bigint, text, text, text']]) {
    const at = sql.indexOf(`create or replace function public.${fn}(`);
    const head = sql.slice(at, sql.indexOf(' as $fn$', at));
    assert.match(head, /set search_path to 'public', 'pg_temp'/, `${fn}: search_path not pinned`);
    assert.ok(sql.includes(`revoke execute on function public.${fn}(${sig}) from public, anon, authenticated;`), `${fn}: no revoke for (${sig})`);
  }
  assert.match(sql.slice(0, 600), /Seat: sales_engineer/, 'the file does not name its seat');
});

test('committed and pending, not listed as applied; the probe is noted as a probe', () => {
  const manifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(!manifest.includes(FILE), 'the file is in MANIFEST.txt but this branch applies nothing (pending note instead)');
  const note = `scripts/sql/pending/${NAME}.txt`;
  assert.ok(existsSync(join(ROOT, note)) && R(note).trim().length > 40, 'no pending note says why and when it is applied');
  assert.match(R(`scripts/sql/pending/${NAME}_probe.txt`), /A PROBE/);
});

test('the supplier and the request sides use it: offered unticked, phrases filed, the chosen keys carried', () => {
  const tab = R('src/components/portal/supplier/ServicesTab.tsx');
  assert.match(tab, /data-testid="proposed-services"/, 'the Services tab does not show the services the documents state');
  assert.match(tab, /setPropTicked\(\(cur\) => reloadSet\(cur, \(d\.proposed_services \|\| \[\]\)\.filter\(\(p\) => p\.stated\)/, 'a proposal is ticked for him on load (founder 862: it starts unticked)');
  assert.match(tab, /phrases,\n/, 'the save does not send his phrases');
  const svc = R('supabase/functions/_shared/supplier_services.ts');
  assert.match(svc, /recordOwnPhrases\(admin, supplierId, stated, phrasesOf\(body\.phrases\)\)/);
  assert.match(svc, /rpc\('fn_service_alias_propose'/);
  const create = R('supabase/functions/customer_api/actions/inquiry_create.ts');
  assert.equal((create.match(/\.\.\.serviceKeyCols\(/g) || []).length, 3, 'not every inquiry insert (single, turnkey, split child) carries the chosen keys');
  const intake = R('supabase/functions/inquiry_intake/handle.ts');
  assert.ok(intake.indexOf('stateServiceKeys(await stateP') > 0 && intake.indexOf('stateServiceKeys(await stateP') < intake.indexOf('serviceKeysOf(allText'), 'the intake count reads the prose before the chosen keys');
  const op = R('supabase/functions/sales_engineer/actions/operator.ts');
  assert.match(op, /action === 'alias_decide'[\s\S]*rpc\('fn_service_alias_decide'/, 'the sales engineer has no door to decide an alias');
  const docs = R('supabase/functions/_shared/supplier_doc_trades.ts');
  assert.match(docs, /proposed_services: proposedServices, licence_check/, 'the documents\' services and the licence check are not stored');
  assert.match(docs, /kind: 'licence_scope_check'/, 'a service the licence does not cover is not put to the sales engineer');
});

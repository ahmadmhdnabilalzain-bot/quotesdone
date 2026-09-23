// A SERVICE INQUIRY REACHES ONLY SUPPLIERS WHO TICKED WHAT IT NAMES
// (23 Sep 2026, sales_engineer; founder_instruction 857).
//
// Rewritten from a_confirmed_trade_is_still_reachable_when_the_inquiry_names_a_service.test.mjs, whose
// name and assertions encoded the policy the founder overruled: that a supplier silent at service level
// in a trade he declares is trade level there. The founder, instruction 857: "if he didnt tick it in the
// customer portal in his profile then yea it means he didnt confirm that he does it basically". So the
// old first assertion — naming a trade's services never reaches fewer suppliers than naming the trade —
// is now FALSE BY DESIGN, and the old "silent where asked must survive" is now "must be excluded".
//
// THE FOUR RULED PROPERTIES, each read against the LIVE fn_match_capability:
//   1. a supplier that ticked a named service is reached;
//   2. a supplier that declares the trade but ticked NONE of the named services in it is NOT reached;
//   3. a supplier never asked — the services named are all in trades he does not declare, and he is
//      admitted through another trade the inquiry names — IS reached;
//   4. an inquiry naming no service (or only words the taxonomy does not know) reaches every supplier
//      of the trade.
//
// PROPERTY 3 IS FIXTURE-INDEPENDENT. It pairs a declared trade with a trade NO confirmed supplier
// declares, so the named trades are disjoint from every candidate's own by construction whatever the
// ZZ DEMO rehearsal set is doing (it was watched going 4 -> 7 -> 1 -> 0 -> 4 -> 1 in one day).
//
// PROPERTY 2 IS MADE, NOT WAITED FOR. The case the ruling changes — a supplier who declares a trade and
// ticked NOTHING in it — was absent from production on 23 Sep, and the first version of this guard only
// read real rows, so it went green on the overruled body. The shape is now made for the run — a ZZ DEMO
// supplier from demo_factory, given its no-tick capability inside one always-rolled-back transaction —
// and the REAL fn_match_capability is asked (the 857.2 probe below).
// Measured 23 Sep 2026: the live #859 body REACHES that supplier (red); this PR's body, installed as a
// pg_temp copy inside the same rolled-back transaction, does NOT (green); leads count unchanged.
// The data-reading 857.2 test is kept for the partial-tick case real rows do carry.
//
// MEASURED NOTHING IS NOT A DEFECT. With no confirmed capability row there is nothing to measure, and
// a fixture retiring must not turn this red: each test prints a NOT_VERIFIED_ line and skips, the same
// road the missing credential takes.
//
//   node --test scripts/checks/a_service_inquiry_reaches_only_suppliers_who_ticked_what_it_names.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const nothing = (t, marker, why) => { console.log(marker); return t.skip(why); };
const lit = (a) => (a.length ? `array[${a.map((s) => `'${String(s).replace(/'/g, "''")}'`).join(',')}]::text[]` : `'{}'::text[]`);

// Everything the four tests read: the confirmed rows with their EFFECTIVE keys (what they ticked, plus
// the curated implications, minus removals — exactly what the gate compares), and a matcher helper.
async function world() {
  const { sql } = await import('../lib/db.mjs');
  const caps = await sql(`
    select sc.supplier_id::text as id, coalesce(sc.trades, '{}'::text[]) as trades,
           public.fn_services_effective(sc.services, sc.trades, sc.services_removed) as eff
      from public.supplier_capabilities sc where sc.confirmed_at is not null order by 1`);
  const declared = [...new Set(caps.flatMap((c) => c.trades))].sort();
  const servicesOf = async (tr) => (await sql(
    `select trade_code || '.' || code as k from public.taxonomy_trade_service
      where active and trade_code = '${tr.replace(/'/g, "''")}' order by 1`)).map((r) => r.k);
  // p_limit far above any real candidate set, so a truncated list can never look like an exclusion.
  const match = async (trades, services) => new Set((await sql(
    `select supplier_id::text as id from public.fn_match_capability(${lit(trades)}, p_limit := 500` +
    (services ? `, p_services := ${lit(services)}` : '') + `)`)).map((r) => r.id));
  // WHO THE TRADE REACHES, WITHOUT ASKING THE SERVICE GATE. Every test below needs "the suppliers of
  // this trade" as a reference, and the first version read it from fn_match_capability with no service
  // named — which is itself gated by the no-service arm. Measured 23 Sep 2026: with that arm deleted the
  // reference emptied too, property 4 compared 0 with 0 and stayed green. So the reference is the
  // candidate gates the function applies BEFORE the service gate, for a call that names no value and no
  // emirate (every call here): confirmed, trade intersection, declared negative scope, matchable, a role
  // that executes, every mandatory authority held. Written as the function writes them, so a supplier
  // outside it is outside it for a reason that has nothing to do with services.
  const tradeLevel = async (trades) => new Set((await sql(`
    select sc.supplier_id::text as id
      from public.supplier_capabilities sc
      join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and sc.trades && ${lit(trades)}
       and not (sc.excluded_trades && ${lit(trades)})
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                  l.approval_status, l.permanently_closed, l.chat_strikes)
       and exists (select 1 from public.taxonomy_role r where r.code = any(sc.roles) and r.executes)
       and not exists (select 1 from public.taxonomy_trade tt, unnest(tt.authority_required) a
                        where tt.code = any(${lit(trades)}) and not (sc.authority_approvals ? a))`)).map((r) => r.id));
  return { sql, caps, declared, servicesOf, match, tradeLevel };
}

test('857.4: an inquiry naming no service reaches every supplier of the trade', { skip: SKIP }, async (t) => {
  const w = await world();
  if (!w.declared.length) return nothing(t, 'NOT_VERIFIED_NO_CONFIRMED_CAPABILITY_ROW', 'production holds no confirmed capability row');
  const bad = []; let asked = 0;
  for (const tr of w.declared) {
    const base = await w.tradeLevel([tr]);
    asked += base.size;
    for (const [label, svc] of [['omitted', null], ['{}', []], ["{'Doors'} (no taxonomy key)", ['Doors']]]) {
      const got = await w.match([tr], svc);
      const lost = [...base].filter((id) => !got.has(id));
      // The other direction keeps the reference honest: a supplier the function reaches that the
      // reference does not means the reference has drifted from the function's own candidate gates.
      const extra = [...got].filter((id) => !base.has(id));
      console.log(`  ${tr.padEnd(14)} trade level ${base.size}, p_services ${label}: ${got.size}`);
      if (lost.length) bad.push(`${tr}, p_services ${label}: lost ${lost.join(',')}`);
      if (extra.length) bad.push(`${tr}, p_services ${label}: reached ${extra.join(',')}, whom the trade-level reference does not hold — the reference has drifted`);
    }
  }
  // Every declared supplier failing some other gate (role, matchable, authority) empties both sides and
  // would pass having compared nothing. Say so instead, as 857.3 does.
  if (!asked) return nothing(t, 'NOT_VERIFIED_NO_SUPPLIER_REACHED_AT_TRADE_LEVEL', 'no confirmed supplier passes the gates before the service gate');
  assert.deepEqual(bad, [], 'an inquiry that names no real service must reach every supplier the trade reaches');
});

test('857.1: a supplier that ticked a named service is reached', { skip: SKIP }, async (t) => {
  const w = await world();
  if (!w.caps.length) return nothing(t, 'NOT_VERIFIED_NO_CONFIRMED_CAPABILITY_ROW', 'production holds no confirmed capability row');
  const bad = []; let asked = 0;
  for (const c of w.caps) {
    for (const k of c.eff) {
      const tr = k.split('.')[0];
      if (!c.trades.includes(tr)) continue;            // an implication outside his trades: not his to be asked
      if (!(await w.tradeLevel([tr])).has(c.id)) continue; // another gate (role, authority) already excludes him
      asked++;
      if (!(await w.match([tr], [k])).has(c.id)) bad.push(`${c.id} ticked ${k} and was not reached by an inquiry naming it`);
    }
  }
  console.log(`  ${asked} (supplier, ticked service) pair(s) asked`);
  if (!asked) return nothing(t, 'NOT_VERIFIED_NO_TICKED_SERVICE_IN_A_DECLARED_TRADE', 'no confirmed supplier has a ticked service in a trade he declares');
  assert.deepEqual(bad, [], 'a supplier that ticked the very service named must receive the inquiry');
});

// 857.2, THE CASE THE RULING CHANGED, MADE RATHER THAN WAITED FOR. A supplier who declares a trade and
// ticked NOTHING in it is the only shape that tells the ruled gate from the overruled one, and production
// may not hold one (on 23 Sep it held none, so the data-reading test below went green on the overruled
// body). So the shape is made for the run and the REAL public.fn_match_capability is asked.
//
// THE SUPPLIER COMES FROM THE FACTORY, NOT FROM THIS FILE. fn_is_matchable requires verified AND
// approval_status 'approved', and trg_leads_e0_mandatory_six_gate refuses either without the founder's
// six AS EVIDENCE (a verified +9715 mobile, a verified e-mail, a licence and a company profile that
// storage actually holds, signed terms). Evidence of that kind cannot be produced inside one SQL
// transaction, and writing the approval here while switching the gate off would be softening it. So the
// supplier is built exactly as a_supplier_who_ignores_holds_is_warned_then_held does it: demo_factory
// makeSupplier (ZZ DEMO, fixture mobile, example.com, withAuth:false) uploads the real documents, signs
// the agreement and lets the sales engineer approve; withRun tears it all down afterwards, even on a throw.
// It is built with NO capability row, so nothing about its services exists outside the probe.
//
// THE PROBE ITSELF COMMITS NOTHING. One DO block, no exception handler, ending in an unconditional
// `raise exception`: it writes the one capability row (a confirmed trade with nothing ticked), asks the
// function, ticks one service, asks again, and rolls it all back. `set local session_replication_role =
// replica` stops every trigger on the tables it touches for that transaction only, so nothing is queued.
// It writes no leads row and so consumes no leads_id_seq value; the factory's lead does consume one,
// which teardown does not give back (sequences are never rolled back) — an id gap there is not a leak.
//
// CONTROLS, so a pass cannot be vacuous: the supplier must be matchable and reached with NO service
// named (otherwise some other gate excluded him and the assertion proves nothing), and reached again
// once he has ticked one of the named services.
const PROBE_857_2 = String.raw`
do $probe$
declare
  v_lead bigint := __LEAD__; v_tr text := '__TRADE__'; v_keys text[]; v_role text; v_auth jsonb; r jsonb;
begin
  set local session_replication_role = replica;
  select array_agg(s.trade_code || '.' || s.code order by s.code) into v_keys
    from public.taxonomy_trade_service s where s.active and s.trade_code = v_tr;
  select code into v_role from public.taxonomy_role where executes order by code limit 1;
  if coalesce(cardinality(v_keys), 0) = 0 or v_role is null then
    raise exception 'PROBE<<{"skipped":"the taxonomy holds no active service for the probe trade, or no role that executes"}>>';
  end if;
  select coalesce(jsonb_object_agg(a, true), '{}'::jsonb) into v_auth
    from public.taxonomy_trade t, unnest(t.authority_required) a where t.code = v_tr;
  insert into public.supplier_capabilities (supplier_id, trades, roles, services, services_removed,
                                            authority_approvals, excluded_trades, confirmed_at)
  values (v_lead, array[v_tr], array[v_role], '{}'::text[], '{}'::text[], v_auth, '{}'::text[], now());
  r := jsonb_build_object('trade', v_tr, 'services_named', cardinality(v_keys),
    'matchable', (select public.fn_is_matchable(verified, banned, matching_blocked, approval_status, permanently_closed, chat_strikes) from public.leads where id = v_lead),
    'reached_no_service_named', exists (select 1 from public.fn_match_capability(array[v_tr], p_limit := 500) m where m.supplier_id = v_lead),
    'reached_having_ticked_nothing', exists (select 1 from public.fn_match_capability(array[v_tr], p_limit := 500, p_services := v_keys) m where m.supplier_id = v_lead));
  update public.supplier_capabilities set services = array[v_keys[1]] where supplier_id = v_lead;
  r := r || jsonb_build_object(
    'reached_having_ticked_one', exists (select 1 from public.fn_match_capability(array[v_tr], p_limit := 500, p_services := v_keys) m where m.supplier_id = v_lead));
  raise exception 'PROBE<<%>>', r::text;
end $probe$;`;
const PROBE_TRADE = 'aluminium';

test('857.2 (probe): a supplier who ticked NOTHING in the trade named is not reached', { skip: SKIP }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const { withRun, makeSupplier } = await import('../lib/demo_factory.mjs');
  let out = null, lead = null, leftBehind = null;
  // The factory refuses to write fixture rows to production unless QD_FIXTURES=1 (qd_guard). Set for
  // this test only and restored after, as a_supplier_who_ignores_holds_is_warned_then_held does.
  const hadFixtures = process.env.QD_FIXTURES;
  process.env.QD_FIXTURES = '1';
  // withRun tears the supplier (row, documents, signed terms) down even if the probe or an assert throws.
  try { await withRun(async (run) => {
    const sup = await makeSupplier(run, { trade: PROBE_TRADE, withAuth: false, capability: false, company_name: `ZZ DEMO probe 857.2 ${run.tag}` });
    lead = Number(sup.leadId);
    try { await sql(PROBE_857_2.replace('__LEAD__', String(lead)).replace('__TRADE__', PROBE_TRADE)); } catch (e) {
      const m = String(e.message || e).match(/PROBE<<([\s\S]*)>>/); if (!m) throw e;
      out = JSON.parse(m[1].replace(/\\"/g, '"'));
    }
    // Keyed to the probe's OWN identity, not to a table total: production gains leads and capability
    // rows on its own, and a real sign-up landing in the probe's window must not read as a leak.
    leftBehind = (await sql(`select count(*)::int as n from public.supplier_capabilities where supplier_id = ${lead}`))[0].n;
  }, { quiet: true }); } finally {
    if (hadFixtures === undefined) delete process.env.QD_FIXTURES; else process.env.QD_FIXTURES = hadFixtures;
  }
  assert.ok(out, 'the probe did not report: it must end in its own raise, so it can never commit');
  if (out.skipped) return nothing(t, 'NOT_VERIFIED_PROBE_' + out.skipped.replace(/\W+/g, '_').toUpperCase(), out.skipped);
  console.log(`  probe on ZZ DEMO lead ${lead}: ${JSON.stringify(out)}`);
  assert.equal(leftBehind, 0, 'the probe left its capability row behind: it must roll back');
  assert.equal(out.matchable, true, 'the probe supplier is not matchable, so the assertion below would prove nothing');
  assert.equal(out.reached_no_service_named, true, 'the probe supplier is not reached even at trade level, so another gate excluded him');
  assert.equal(out.reached_having_ticked_one, true, 'once he ticks a named service he must be reached');
  assert.equal(out.reached_having_ticked_nothing, false,
    'founder_instruction 857: he declares the trade and ticked none of the named services, so he did not confirm he does them');
});

test('857.2: a supplier that declares the trade but ticked none of the named services is NOT reached', { skip: SKIP }, async (t) => {
  const w = await world();
  if (!w.caps.length) return nothing(t, 'NOT_VERIFIED_NO_CONFIRMED_CAPABILITY_ROW', 'production holds no confirmed capability row');
  const bad = []; let asked = 0, tickedNothing = 0;
  for (const c of w.caps) {
    for (const tr of c.trades) {
      if (!(await w.tradeLevel([tr])).has(c.id)) continue;
      // Every active service of the trade that he did NOT tick. Asking for all of them at once is the
      // widest inquiry that still names nothing he confirmed.
      const unticked = (await w.servicesOf(tr)).filter((k) => !c.eff.includes(k));
      if (!unticked.length) continue;                   // he ticked every service of this trade
      const none = !c.eff.some((k) => k.split('.')[0] === tr);
      asked++; if (none) tickedNothing++;
      const reached = (await w.match([tr], unticked)).has(c.id);
      console.log(`  ${c.id} in ${tr}: ${none ? 'ticked NOTHING in it' : 'ticked some of it'}, asked ${unticked.length} unticked -> ${reached ? 'REACHED' : 'not reached'}`);
      if (reached) bad.push(`${c.id} declares ${tr}, ticked ${none ? 'nothing in it' : 'none of the named'}, and was reached by an inquiry naming ${unticked.length} service(s) he did not tick`);
    }
  }
  if (!asked) return nothing(t, 'NOT_VERIFIED_NO_SUPPLIER_WITH_AN_UNTICKED_SERVICE', 'every confirmed supplier ticked every service of every trade he declares');
  // The shape the ruling changed. Absent from the data it cannot be read, and saying so is the honest
  // outcome; the partial-tick case above is still asserted.
  if (!tickedNothing) console.log('NOT_VERIFIED_NO_SUPPLIER_TICKED_NOTHING_IN_A_DECLARED_TRADE');
  assert.deepEqual(bad, [], 'founder_instruction 857: a supplier who did not tick it did not confirm he does it');
});

test('857.3: a supplier never asked about any trade he declares IS reached', { skip: SKIP }, async (t) => {
  const w = await world();
  if (!w.declared.length) return nothing(t, 'NOT_VERIFIED_NO_CONFIRMED_CAPABILITY_ROW', 'production holds no confirmed capability row');
  // A trade NO confirmed supplier declares: the named trades are then disjoint from every candidate's own.
  const [o] = await w.sql(`
    select t.code as tr from public.taxonomy_trade t
     where t.active
       and exists (select 1 from public.taxonomy_trade_service s where s.active and s.trade_code = t.code)
       and not exists (select 1 from public.supplier_capabilities sc, unnest(coalesce(sc.trades, '{}'::text[])) x
                        where sc.confirmed_at is not null and x = t.code)
     order by t.code limit 1`);
  if (!o) return nothing(t, 'NOT_VERIFIED_NO_UNDECLARED_TRADE', 'every trade with services is declared by some confirmed supplier');
  const named = await w.servicesOf(o.tr);
  const bad = []; let asked = 0;
  for (const tr of w.declared) {
    const base = await w.tradeLevel([tr, o.tr]);
    const got = await w.match([tr, o.tr], named);
    asked += base.size;
    const lost = [...base].filter((id) => !got.has(id));
    console.log(`  p_trades {${tr}, ${o.tr}}, naming only ${o.tr}'s ${named.length} services: trade level ${base.size}, reached ${got.size}` +
                (lost.length ? `  LOST ${lost.join(',')} (never asked)` : ''));
    if (lost.length) bad.push(`{${tr}, ${o.tr}}: ${lost.join(',')} were asked nothing about any trade they declare, yet were dropped`);
  }
  if (!asked) return nothing(t, 'NOT_VERIFIED_NO_SUPPLIER_REACHED_AT_TRADE_LEVEL', 'no confirmed supplier is reached at trade level');
  assert.deepEqual(bad, [], 'a supplier that was asked nothing failed to tick nothing, and must receive the inquiry');
});

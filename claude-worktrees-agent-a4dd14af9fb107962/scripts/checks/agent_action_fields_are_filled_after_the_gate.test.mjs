// A BEFORE TRIGGER THAT READS WHAT A LATER BEFORE TRIGGER WRITES.
//
// 13 Aug 2026. Spec §36 wants seven fields on every rendered recommendation. Three were always
// present (confidence and evidence from fn_governance_stamp, plus risk). Four were not:
// alternatives null on 1,254 of 1,362 recommendations in 30 days, and assumptions, cost and
// expected_impact null on 1,325 each.
//
// A trigger for exactly this already existed and had never fired on an insert. It opened with
// `if NEW.decision_log_id is null then return NEW; end if;` — and decision_log_id is assigned by
// zzz_action_gate, named `zzz_` on purpose because BEFORE triggers fire in NAME order.
// `trg_agent_actions_alternatives` sorts BEFORE `zzz_action_gate`, so it always ran first, always
// saw NULL, and always returned. Guarded by a condition that could not be true when it was tested.
//
// The fix is ordering, so ordering is what this check pins. It is deliberately NOT a check that
// counts recent rows: with no new recommendations in the window such a check passes while testing
// nothing, which is the failure mode that let a 16,608-record phantom and a "0 missing" empty run
// through earlier the same day.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const mgmtToken = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

const q = async (project, query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + mgmtToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  assert.ok(r.ok, `query failed on ${project}: ${r.status}`);
  return r.json();
};

// 9 SEP 2026 — THE GATE THIS TEST NAMED WAS DROPPED, THE ORDERING PROPERTY WAS NOT.
//
// `trg_action_gate` (trigger `zzz_action_gate`) was dropped from production on 7 Sep 2026 under the
// founder's ruling that anything outside the two-agent structure is deleted; scripts/sql/DROPPED.txt
// line 155 records it. MEASURED on production 9 Sep: 0 rows in pg_proc for any %action_gate% name,
// and the BEFORE row triggers left on agent_actions are a00_agent_action_resolve_addressee,
// trg_dedupe_it_incident, trg_governance_stamp and zzz_zz_agent_action_fill_fields.
//
// That did NOT re-open the defect. The filler was rewritten on 3 Sep
// (scripts/sql/fn_agent_actions_fill_alternatives_without_a_decision_log.sql) to derive alternatives
// from the row's own dispositions instead of returning early on a null decision_log_id, so it fills
// with no gate present. MEASURED: both agent_actions rows written since (id 10081, 10082, newest
// 7 Sep 16:15Z) carry decision_log_id NULL and all four of alternatives, assumptions, cost and
// expected_impact populated. So this is not a live defect and the check is not retired.
//
// WHAT IS ASSERTED NOW IS STRICTLY STRONGER, not weaker. The old assertion was "the filler sorts
// after ONE named trigger". The replacement is "the filler sorts after EVERY other BEFORE row
// trigger on agent_actions" — which implies the old one for any future gate, under any name, and
// also catches a new sibling that assigns something the filler reads. The population of BEFORE
// triggers is asserted so an empty answer cannot read as a pass.
//
// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`the field filler fires last among the BEFORE triggers on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token, so trigger order cannot be read'); return; }
    const rows = await q(project,
      "select t.tgname, p.proname from pg_trigger t join pg_class c on c.oid = t.tgrelid "
      + "join pg_proc p on p.oid = t.tgfoid "
      + "where c.relname = 'agent_actions' and not t.tgisinternal "
      + "and (t.tgtype & 2) = 2 and (t.tgtype & 1) = 1 "   // BEFORE, ROW
      + "order by t.tgname");
    assert.ok(rows.length > 1,
      `only ${rows.length} BEFORE row trigger(s) were found on agent_actions on ${label}. The `
      + 'ordering question is meaningless on a set that small — the query is wrong, or the table has '
      + 'lost its triggers, and either way a pass here would assert nothing.');
    const filler = rows.find((r) => r.proname === 'fn_agent_actions_fill_alternatives');
    assert.ok(filler, `no BEFORE trigger runs fn_agent_actions_fill_alternatives on ${label}`);
    const later = rows.filter((r) => r.tgname > filler.tgname).map((r) => r.tgname);
    assert.deepEqual(later, [],
      `the field filler "${filler.tgname}" sorts BEFORE ${later.join(', ')} on ${label}. BEFORE `
      + 'triggers fire in name order, and the filler reads columns its siblings assign — so anything '
      + 'sorting after it is written too late to be seen, and the filler quietly fills nothing, '
      + 'exactly as it did for months when zzz_action_gate sorted after it.');
    console.log(`${label}: ${rows.map((r) => r.tgname).join(' -> ')}`);
  });
}

test('the filler fills all four missing fields, and overwrites none of them', async (t) => {
  if (!mgmtToken) { t.skip('no management token'); return; }
  const [{ prosrc }] = await q('htdblwldjkcgjvmqkbeh',
    "select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
    + "where n.nspname = 'public' and p.proname = 'fn_agent_actions_fill_alternatives'");
  for (const col of ['alternatives', 'assumptions', 'expected_impact', 'cost']) {
    assert.match(prosrc, new RegExp(`NEW\\.${col} is null`),
      `the filler does not guard on NEW.${col} is null — either it never sets that field, or it `
      + 'overwrites what a caller supplied. Both are wrong: a routine that did the reasoning must win.');
    assert.match(prosrc, new RegExp(`NEW\\.${col} :=`),
      `the filler never assigns NEW.${col}, so §36 will still find it null on every row`);
  }
  // The derived alternatives must come from the ledger the gate wrote, not from a literal.
  //
  // 18 AUG 2026 — THIS ASSERTED AN ALIAS, NOT A BEHAVIOUR. It was `assert.match(prosrc,
  // /d\.alternatives/)`, which required the body to hold a plpgsql RECORD named `d`. That record
  // was removed on purpose: an unassigned RECORD raises 55000 on the first field reference, and
  // `d` was only assigned inside an if-branch, so every row that skipped the lookup crashed. The
  // replacement declares v_alts / v_decision as typed scalars, which are null when the lookup is
  // skipped, and null is answerable. The behaviour this test exists to protect never changed —
  // only the identifier did — and the final acceptance audit counted this as one of the eight
  // repository-suite failures.
  //
  // Now asserted on what the sentence actually says: the body READS the ledger, and the value it
  // assigns comes from that read rather than from a literal built in the trigger.
  assert.match(prosrc, /from\s+public\.decision_log\b/,
    'the filler never reads public.decision_log, so whatever it puts in alternatives cannot be the '
    + 'two options the gate genuinely weighed');
  const assign = prosrc.match(/NEW\.alternatives\s*:=\s*([^;]+);/);
  assert.ok(assign, 'the filler never assigns NEW.alternatives');
  assert.doesNotMatch(assign[1], /jsonb_build_array\s*\(|'\s*\[/,
    'alternatives is assigned a literal built inside the trigger. It must be read from the '
    + `decision_log row the gate just wrote. Found: ${assign[1].trim().slice(0, 120)}`);
});

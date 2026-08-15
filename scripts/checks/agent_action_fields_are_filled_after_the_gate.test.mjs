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

// staging was a second target until its Supabase project was deleted on 15 Aug 2026; the same
// assertions now run against production alone.
for (const [label, project] of [['production', 'htdblwldjkcgjvmqkbeh']]) {
  test(`the field filler fires after the gate on ${label}`, async (t) => {
    if (!mgmtToken) { t.skip('no management token, so trigger order cannot be read'); return; }
    const rows = await q(project,
      "select t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid "
      + "join pg_proc p on p.oid = t.tgfoid "
      + "where c.relname = 'agent_actions' and not t.tgisinternal "
      + "and (t.tgtype & 2) = 2 "                      // BEFORE
      + "and p.proname in ('trg_action_gate','fn_agent_actions_fill_alternatives') "
      + "order by t.tgname");
    const names = rows.map((r) => r.tgname);
    const gate = names.find((n) => n === 'zzz_action_gate');
    const filler = names.find((n) => n !== 'zzz_action_gate');
    assert.ok(gate, `zzz_action_gate is not a BEFORE trigger on agent_actions on ${label}`);
    assert.ok(filler, `no BEFORE trigger runs fn_agent_actions_fill_alternatives on ${label}`);
    assert.ok(filler > gate,
      `the field filler "${filler}" sorts BEFORE the gate "${gate}" on ${label}. BEFORE triggers fire `
      + 'in name order, and the filler reads NEW.decision_log_id which the gate assigns — so it will '
      + 'see NULL on every insert and fill nothing, exactly as it did for months.');
    console.log(`${label}: ${gate} then ${filler}`);
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
  assert.match(prosrc, /d\.alternatives/,
    'alternatives must be read from the decision_log row the gate just wrote — the two options it '
    + 'genuinely weighed — not invented in the trigger');
});

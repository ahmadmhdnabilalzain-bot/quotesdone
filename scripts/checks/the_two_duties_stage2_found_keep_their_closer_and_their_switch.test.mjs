// Stage-2 run f0b2de8f (2 Nov 2026, S18) found two live duties that did not keep a rule the platform relies on. The rolled-back probes next
// to each SQL file prove them on production at apply time; these offline checks pin the text, with a known-bad control each.
//   node --test scripts/checks/the_two_duties_stage2_found_keep_their_closer_and_their_switch.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = (n) => readFileSync(new URL(`../sql/${n}.sql`, import.meta.url), 'utf8').replace(/^\s*--.*$/gm, '');
const duties = readFileSync(new URL('../e2e/stage2_duties.mjs', import.meta.url), 'utf8');
const stage2 = readFileSync(new URL('../e2e/stage2.mjs', import.meta.url), 'utf8');

// customer_support.knowledge_request_deadline: a knowledge.request handoff is closed only by its originator, who names itself.
const namesItselfAroundTheClose = (t) => /set_config\('qd\.handoff_closer', 'customer_support', true\);[\s\S]*fn_seat_handoff_complete[\s\S]*set_config\('qd\.handoff_closer', '', true\)/.test(t);
test('the knowledge-request tick names customer_support while it closes handoffs, then clears the name', () => {
  assert.ok(namesItselfAroundTheClose(sql('the_knowledge_request_duty_names_itself_when_it_closes_a_handoff')));
  assert.ok(!namesItselfAroundTheClose(sql('customer_support_closes_every_knowledge_request_by_a_deadline')), 'known-bad: the old body closed without naming itself');
});

// sales_engineer.supplier_onboarding: the fixture switch goes down into the invite nudges.
const passesTheSwitch = (t) => /fn_sales_engineer_nudges_invited_suppliers\(p_include_fixtures => v_fx\)/.test(t);
test('the supplier-onboarding duty passes its fixture switch to the invite nudges', () => {
  assert.ok(passesTheSwitch(sql('the_supplier_onboarding_duty_passes_its_fixture_switch_to_the_invite_nudges')));
  assert.ok(!passesTheSwitch(sql('an_unopened_supplier_invitation_is_nudged_on_day_3_7_and_14_under_the_same_switch_cap_and_brakes')), 'known-bad: the old body called it with its defaults (real mail)');
});

test('S18 runs every duty on the live rows (error only) and in fixture mode (no real row), both rolled back', () => {
  assert.match(duties, /export async function probeDuty\(d, tag, fixtures = false\)/);
  assert.match(duties, /set_config\('qd\.duty_fixtures', \$\{q\(fixtures \? 'on' : ''\)\}, true\)/);
  assert.match(stage2, /probeDuty\(d, tag, false\)/);
  assert.match(stage2, /probeDuty\(d, tag, true\)/);
  assert.match(duties, /raise exception 'CHK<</, 'a probe still always raises, so it can never commit');
});

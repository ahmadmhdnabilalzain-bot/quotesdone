// Supplier invitations and their reminders go only to role addresses (info@, sales@ ...), never a person's
// mailbox (founder, 19 Oct 2026, legal finding 3; Assigned: ceo). The rule is public.fn_is_role_address(text) in
// scripts/sql/supplier_invitations_go_only_to_role_addresses_never_a_persons_mailbox.sql. This replays its regex
// on literals and proves the three selecting routines in that file call it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../sql/supplier_invitations_go_only_to_role_addresses_never_a_persons_mailbox.sql', import.meta.url), 'utf8');
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const re = new RegExp(code.match(/~\s*'(\^\(info\|[^']+)'/)[1]);
const isRole = (e) => typeof e === 'string' && e.indexOf('@') > 0 && re.test(e.trim().toLowerCase().split('@')[0]);

test('role addresses are accepted, personal-name addresses rejected', () => {
  for (const e of ['info@acme.ae', 'Sales@Acme.ae', 'enquiries@acme.ae', 'info.dubai@acme.ae', 'sales1@acme.ae', 'tenders_ae@acme.ae', 'bd@acme.ae'])
    assert.ok(isRole(e), e);
  for (const e of ['ahmed@acme.ae', 'j.smith@acme.ae', 'ahmed.k@acme.ae', 'infoahmed@acme.ae', 'john.sales@acme.ae', 'careers@acme.ae', 'info', ''])
    assert.ok(!isRole(e), e);
});

test('the invitation row rule, set rule and reminder selection all call fn_is_role_address', () => {
  for (const f of ['fn_supplier_invite_eligible(', 'fn_supplier_invite_eligible_ids(', 'fn_supplier_invite_nudges_due(']) {
    const a = code.indexOf('create or replace function public.' + f);
    assert.ok(a >= 0, f + ' is defined');
    const body = code.slice(a, code.indexOf('$fn$;', a));
    assert.match(body, /public\.fn_is_role_address\(/, f + ' calls the rule');
  }
  assert.match(sql, /'PROBE OK'/);
});

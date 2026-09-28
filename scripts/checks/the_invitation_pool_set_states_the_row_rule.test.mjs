// fn_supplier_invite_eligible_ids() is the set form of fn_supplier_invite_eligible(leads), written so the
// daily supplier list and the 10:00 send fit PostgREST's 8 s statement timeout (28 Sep 2026: the list
// timed out every evening and was never produced). Two statements of one rule can drift, so this reads the
// live mirror and fails when a table the row rule consults is missing from the set rule, or when the set
// callers go back to the per-row call. The apply probe proved lead-for-lead equality on 17,401 leads.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const MIRROR = new URL('../../supabase/schema/full_schema.sql', import.meta.url);
const body = (sql, name) => {
  const i = sql.search(new RegExp(`FUNCTION public\\.${name}\\(`));
  if (i < 0) return null;
  const s = sql.indexOf('$', sql.indexOf(' AS ', i));
  const tag = sql.slice(s, sql.indexOf('$', s + 1) + 1);
  const a = s + tag.length;
  return sql.slice(a, sql.indexOf(tag, a));
};

test('the set rule consults every table the row rule does', { skip: !existsSync(MIRROR) }, () => {
  const sql = readFileSync(MIRROR, 'utf8');
  const row = body(sql, 'fn_supplier_invite_eligible');
  const set = body(sql, 'fn_supplier_invite_eligible_ids');
  if (!set) return;   // not applied yet: the pending note covers it
  const sendable = body(sql, 'fn_email_sendable') ?? '';
  const tables = (t) => new Set([...t.matchAll(/\b(?:public\.)?(sanctions_ban|supplier_screening_hit|notifications|email_domain_mx|email_platform_domain|email_suppressions|email_block_pattern)\b/g)].map((m) => m[1]));
  const want = new Set([...tables(row), ...(row.includes('fn_email_sendable') ? tables(sendable) : [])]);
  const have = tables(set);
  for (const t of want) assert.ok(have.has(t), `the row rule reads ${t}; the set rule does not`);
});

test('the list and the candidates read the set, not the per-row call', { skip: !existsSync(MIRROR) }, () => {
  const sql = readFileSync(MIRROR, 'utf8');
  if (!body(sql, 'fn_supplier_invite_eligible_ids')) return;
  for (const f of ['fn_supplier_campaign_next_list', 'fn_supplier_invite_candidates']) {
    assert.doesNotMatch(body(sql, f), /fn_supplier_invite_eligible\(l\)/, f);
  }
});

// A customer hears the reveal and its invoice in the inquiry's language (19 Oct 2026, sales_engineer).
//
// Ruling: a customer is written in the inquiry's language, else their registered one; suppliers are
// English (1008). invoice_ready used the registered locale only. Fails if either writer stops using
// fn_customer_notice_locale, or (with a management token) if the choice itself is wrong:
// EN inquiry -> en, AR inquiry -> ar (even for an EN-registered customer), nothing known -> en,
// no inquiry -> the customer's registered locale.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { replaySql } from '../lib/safe_replay.mjs';

const FILE = 'scripts/sql/a_customer_hears_the_reveal_and_its_invoice_in_the_inquiry_language.sql';
const sql = readFileSync(new URL(`../../${FILE}`, import.meta.url), 'utf8');

test('both customer writers choose the language through fn_customer_notice_locale', () => {
  assert.match(sql, /when p_role = 'customer' then public\.fn_customer_notice_locale\(p_inquiry, p_customer\)/);
  assert.match(sql, /v_ar := public\.fn_customer_notice_locale\(\(new\.detail->>'inquiry_id'\)::uuid, c\.id\) = 'ar'/);
  assert.match(sql, /coalesce\(public\.fn_inquiry_locale\(p_inquiry\),\s*public\.fn_registered_locale\('customer', p_customer, null, null\),\s*'en'\)/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, aborted: EN inquiry -> en, AR inquiry -> ar, nothing -> en, no inquiry -> registered', { skip: hasToken ? false : 'no Supabase management token in this environment', timeout: 300000 }, async () => {
  const rows = await replaySql(sql + `
;select
  public.fn_customer_notice_locale((select id from public.inquiries where lang='en' limit 1),
                                   (select id from public.customers where locale like 'ar%' limit 1)) as en_inquiry,
  public.fn_customer_notice_locale((select id from public.inquiries where lang='ar' limit 1),
                                   (select id from public.customers where locale = 'en' limit 1)) as ar_inquiry,
  public.fn_customer_notice_locale(null, null) as nothing,
  public.fn_customer_notice_locale(null, (select id from public.customers where locale like 'ar%' limit 1)) as registered_ar`,
  { label: 'customer notice locale', rows: true, retry: false });
  assert.deepEqual(rows[0], { en_inquiry: 'en', ar_inquiry: 'ar', nothing: 'en', registered_ar: 'ar' });
});

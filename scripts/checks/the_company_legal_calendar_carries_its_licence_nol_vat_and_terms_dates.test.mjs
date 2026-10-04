// THE COMPANY LEGAL CALENDAR CARRIES ITS LICENCE, NOL, VAT AND TERMS DATES (T6, seat: accountant).
//
// Fails if:
//   1. the SQL file stops naming the two expiries with their dates and a 90/60/30 stage;
//   2. against production: the VAT watch stops reporting at 80% and 100% of AED 375,000 (or reports below 50%);
//   3. against production, once the file is applied (its pending note gone): either expiry lacks the 90-day
//      stage, or a calendar row is missing.
//
//   node --test scripts/checks/the_company_legal_calendar_carries_its_licence_nol_vat_and_terms_dates.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const NAME = 'the_company_legal_calendar_carries_its_licence_nol_vat_and_terms_dates';
const FILE = new URL(`../sql/${NAME}.sql`, import.meta.url);
const PENDING = new URL(`../sql/pending/${NAME}.txt`, import.meta.url);
const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

test('the file names both expiries, their dates and the 90/60/30 stage', () => {
  const s = readFileSync(FILE, 'utf8');
  for (const needle of ["'trade_licence_det_1633275'", "'tdra_nol_26_100000665'", "date '2027-06-24'",
    "date '2027-09-14'", 'array[90, 60, 30]', 'Terms versions in force', 'AED 375,000']) {
    assert.ok(s.includes(needle), `missing ${needle}`);
  }
  assert.ok(!/^\s*(begin|commit)\s*;/im.test(s), 'the file must not carry its own transaction');
});

test('the VAT watch reports at 80% and 100% of AED 375,000', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  const [r] = await sql(`select (select num_value from public.gl_settings where key = 'vat_registration_threshold_aed') thr,
    public.fn_vat_threshold_fraction_reached(300000) f80, public.fn_vat_threshold_fraction_reached(375000) f100,
    public.fn_vat_threshold_fraction_reached(150000) flow`);
  assert.equal(Number(r.thr), 375000);
  assert.equal(Number(r.f80), 0.8);
  assert.equal(Number(r.f100), 1);
  assert.equal(r.flow, null);
});

test('once applied, both expiries remind at 90/60/30 and the four calendar rows exist', async (t) => {
  if (!token) { t.skip('no management token'); return; }
  if (existsSync(PENDING)) { t.skip('pending: applied at merge'); return; }
  const [r] = await sql(`select
    (select count(*) from public.it_expiry where item in ('trade_licence_det_1633275','tdra_nol_26_100000665')
       and warn_days = array[90,60,30])::int exp,
    (select count(*) from public.company_calendar where kind = 'compliance' and event_name in (
       'Trade licence DET 1633275 expires', 'TDRA NOL NOL-26-100000665 expires',
       'VAT registration threshold watch (AED 375,000, rolling 12 months)', 'Terms versions in force'))::int cal`);
  assert.equal(r.exp, 2);
  assert.equal(r.cal, 4);
});

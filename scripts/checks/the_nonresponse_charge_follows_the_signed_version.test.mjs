// THE NON-RESPONSE CHARGE FOLLOWS THE VERSION THE SUPPLIER SIGNED, AND THE PRICING TABLE STATES THE CURRENT ONE
// (19 Oct 2026, accountant; founder ledger 990 and 1086; Supplier Agreement v15 clauses 31 and 33).
//
// MEASURED BEFORE THE FIX: pricing_config row 1 held AED 250 and 0.09, the v12/v13 figures, as the price list every
// reader takes as current (marketing's fact register flagged 250 against the FAQ's 500), and
// fn_accountant_nonresponse_charge read its legacy AED 250 from that row, so correcting the row would have
// retro-charged every v12 signer AED 500.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the legacy branch reads the fee from pricing_config again instead of its literal 250, or the file stops
//     setting pricing_config to the current 500 / 0.12; the file carries both (or neither of) a pending note and a
//     MANIFEST line;
//   * production, ONE aborted transaction (the file replayed first while it is pending; nothing commits), ZZ DEMO
//     suppliers at @example.invalid only: v12 -> AED 250 / 9%, v13 -> AED 500 / 9%, v15 -> AED 500 / 12%,
//     v15 accepted only AFTER the reveal -> AED 250 / 9% (never retroactive); pricing_config reads 500 / 0.12.
//
//   node --test scripts/checks/the_nonresponse_charge_follows_the_signed_version.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_nonresponse_charge_follows_the_signed_version.sql';
const NAME = FILE.split('/').pop();
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', NAME.replace(/\.sql$/, '.txt')));
const code = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('static: the legacy fee is the literal the supplier signed; the pricing table is set to the current terms', () => {
  const sql = code(read(FILE));
  assert.match(sql, /else\s+v_fee := 250;/, 'the legacy branch does not charge the literal AED 250 of v6-v12');
  assert.doesNotMatch(sql, /v_fee := c\.supplier_nonresponse_admin_fee_aed/, 'the legacy fee is read from the pricing table again');
  assert.match(sql, /'supplier_nonresponse_admin_fee_from_v13_aed'\), 500\);/, 'the v13+ fee falls back to the pricing table, not 500');
  assert.match(sql, /update public\.pricing_config set supplier_nonresponse_admin_fee_aed = 500, supplier_nonresponse_interest_apr = 0\.12/, 'the pricing table is not set to the current v15 terms');
  assert.match(sql, /v_apr\s+:= least\(coalesce\(c\.supplier_nonresponse_interest_apr, 0\.09\), coalesce\(v_cap, 0\.09\), 0\.09\);/, 'the no-agreed-rate branch lost its 9% literal');
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).some((l) => l.trim().endsWith(NAME));
  assert.ok(inManifest !== pending(), 'the file must carry exactly one of a pending note and a MANIFEST line');
});

export const PROBE = `
do $$
declare s12 bigint; s13 bigint; s15 bigint; s15late bigint; t uuid; out jsonb := '{}'; r jsonb; k text; sid bigint;
begin
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO fee probe v12 (QuotesDone fixture, not a real company)', 'zz-demo-fee-v12@example.invalid', 'v12', now() - interval '30 days') returning id into s12;
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO fee probe v13 (QuotesDone fixture, not a real company)', 'zz-demo-fee-v13@example.invalid', 'v13', now() - interval '30 days') returning id into s13;
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO fee probe v15 (QuotesDone fixture, not a real company)', 'zz-demo-fee-v15@example.invalid', 'v15', now() - interval '30 days') returning id into s15;
  insert into public.leads (company_name, email, accepted_terms_version, accepted_terms_at) values
    ('ZZ DEMO fee probe v15 late (QuotesDone fixture, not a real company)', 'zz-demo-fee-v15late@example.invalid', 'v15', now() - interval '5 days') returning id into s15late;
  for k, sid in select * from (values ('v12', s12), ('v13', s13), ('v15', s15), ('v15_after_reveal', s15late)) x loop
    insert into public.transactions (supplier_id, revealed_at, total_charged, reveal_fee, refund_amount_aed, refund_status, refund_confirmed_at)
      values (sid, now() - interval '20 days', 300, 300, 300, 'refunded', now() - interval '10 days') returning id into t;
    r := public.fn_accountant_nonresponse_charge(t, null);
    out := out || jsonb_build_object(k, jsonb_build_object('ok', r->'ok', 'fee', r->'admin_fee_aed', 'apr', r->'interest_apr', 'v', r->'signed_version'));
  end loop;
  out := out || jsonb_build_object('config', (select jsonb_build_object('fee', supplier_nonresponse_admin_fee_aed, 'apr', supplier_nonresponse_interest_apr) from public.pricing_config order by id limit 1));
  raise exception 'CHK<<%>>', out::text;
end $$;`;

export async function runProbe(replay) {
  const { replaySql: sql } = await import('../lib/safe_replay.mjs');   // the one door: cannot commit
  try { await sql((replay ? read(FILE) + '\n' : '') + PROBE, { retry: false }); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw new Error('the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  throw new Error('the probe committed instead of rolling back');
}

export function verdict(o) {
  const bad = [];
  for (const [k, fee, apr] of [['v12', 250, 0.09], ['v13', 500, 0.09], ['v15', 500, 0.12], ['v15_after_reveal', 250, 0.09]]) {
    const c = o[k];
    if (!c || c.ok !== true) { bad.push(`${k}: ${JSON.stringify(c)}`); continue; }
    if (Number(c.fee) !== fee) bad.push(`${k}: admin fee AED ${c.fee} instead of ${fee}`);
    if (Number(c.apr) !== apr) bad.push(`${k}: interest ${Number(c.apr) * 100}% instead of ${apr * 100}%`);
  }
  if (Number(o.config?.fee) !== 500 || Number(o.config?.apr) !== 0.12) bad.push(`pricing_config states ${JSON.stringify(o.config)}, not the current AED 500 / 12%`);
  return bad;
}

const hasToken = !process.env.PROBE_IMPORTED && (!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token')));
test('production, aborted: v12 250/9%, v13 500/9%, v15 500/12%, late v15 250/9%, pricing table 500/12%', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const o = await runProbe(pending());
  assert.deepEqual(verdict(o), [], JSON.stringify(o));
});

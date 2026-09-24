// THE SALES ENGINEER REVIEWS THE WEEK AND OWNS ITS DUTIES (24 Sep 2026; founder_instruction 983, seat audit gaps 3-6).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   * offline: the reveal ladder or the licence duty is owned by another seat again, or a new duty has no clock;
//   * production, in ONE aborted transaction (the pending file replayed first; ZZ DEMO and example.invalid only, every
//     row rolls back): a ZZ DEMO request with no match is not counted, not remembered as a no_exact_match case, a held
//     quote's reason is not counted, the week is not remembered, or an enterprise account's totals miss its member.
//
//   node --test scripts/checks/the_sales_engineer_reviews_the_week_and_owns_its_duties.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/the_sales_engineer_reviews_the_week_owns_licences_the_ladder_and_enterprise_accounts.sql';
const src = readFileSync(join(REPO, FILE), 'utf8');
const pending = existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));

test('the ladder and document validity are the sales engineer\'s, and each new duty has a clock', () => {
  assert.match(src, /update public\.resilience_step set owner_seat = 'sales_engineer' where step = 'ladder'/);
  assert.match(src, /delete from public\.seat_duty where duty = 'it_engineer\.licence_expiry_watch'/);
  for (const d of ['weekly_quality_review', 'enterprise_pipeline'])
    assert.match(src, new RegExp(`\\('sales_engineer\\.${d}', 'sales_engineer'`), d + ' has no seat_duty row');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('production, aborted: the week is reviewed, remembered, and an enterprise account consolidates', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const block = String.raw`
do $$ declare o jsonb := '{}'; v jsonb; cid uuid; inq uuid; q uuid; acc bigint; begin
  insert into public.customers (full_name, email) values ('ZZ DEMO weekly review', 'zz-weekly-review@example.invalid') returning id into cid;
  insert into public.inquiries (customer_id, category, summary_masked, created_at)
    values (cid, 'zz_demo_trade', 'ZZ DEMO request nobody can quote', now() - interval '2 days') returning id into inq;
  select id into q from public.quotes limit 1;
  if q is not null then
    insert into public.quote_spec_hold (quote_id, inquiry_id, state, missing, original_snapshot, opened_at)
      values (q, inq, 'open', '[{"scope":"line","line_no":1,"attr":"zz_demo_thickness"}]', '{}', now() - interval '2 days');
  end if;
  v := public.fn_sales_engineer_weekly_quality_review(true);
  o := o || jsonb_build_object('review', v, 'had_quote', q is not null,
    'case_no_match', (select count(*) from public.seat_case_memory where source_table = 'inquiries.no_exact_match' and source_id = inq::text),
    'case_week', (select count(*) from public.seat_case_memory where source_table = 'sales_engineer.weekly_quality_review' and source_id = v->>'week'),
    'ladder_owner', (select owner_seat from public.resilience_step where step = 'ladder'),
    'it_licence_duty', (select count(*) from public.seat_duty where duty = 'it_engineer.licence_expiry_watch'));
  insert into public.enterprise_account (name) values ('ZZ DEMO Enterprise') returning id into acc;
  insert into public.enterprise_account_member (account_id, customer_id) values (acc, cid);
  o := o || jsonb_build_object('pipeline', public.fn_sales_engineer_enterprise_pipeline());
  o := o || jsonb_build_object(  -- a separate statement: the update above must be in its snapshot
    'totals', (select totals from public.enterprise_account where id = acc));
  raise exception 'CHK<<%>>', o;
end $$;`;
  let o;
  try { await sql((pending ? src + '\n' : '') + block, { retry: false }); assert.fail('the probe committed'); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o.review.requests >= 1 && o.review.no_exact_match >= 1, JSON.stringify(o.review));
  assert.equal(o.case_no_match, 1, 'the unmatched request is not in seat_case_memory');
  assert.equal(o.case_week, 1, 'the week is not in seat_case_memory');
  if (o.had_quote) assert.ok(o.review.hold_reasons.zz_demo_thickness >= 1, 'the hold reason is not counted');
  assert.equal(o.ladder_owner, 'sales_engineer');
  assert.equal(o.it_licence_duty, 0);
  assert.equal(o.totals?.members, 1, JSON.stringify(o));
  assert.equal(o.totals.requests, 1);
  assert.ok(o.pipeline.plan_due.length >= 1, 'an account with no plan is not listed as due');
});

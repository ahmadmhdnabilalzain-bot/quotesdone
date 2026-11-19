// A REQUEST THAT HAS ENDED TAKES NO QUOTATION CHANGE (sales_engineer, 19 Nov 2026; founder rulings 1683, 1686; second review of the
// price-positioning fix). fn_supplier_stats compares a supplier only on ended requests; on an expired or lost one submit_quote still
// took a re-sent price (it refused only CONCLUDED: completed, closed, cancelled) and withdraw_quote read no request status, so he
// could move his side and read the other suppliers' price out of the answer. FAILS if either action stops refusing an ended request
// before it writes, or if trigger a06 in the SQL file stops naming exactly the statuses of _shared/request_closed.ts.
//   deno test --no-lock --node-modules-dir=none -A supabase/functions/supplier_api/a_request_that_has_ended_takes_no_quotation_change.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { CLOSED_REQUEST_STATUSES, isClosedRequest } from '../_shared/request_closed.ts';
import { CONCLUDED, REQUEST_ENDED_SUBMIT, REQUEST_ENDED_WITHDRAW } from './lib/fields.ts';

const SQL = '../../../scripts/sql/no_rival_price_can_be_worked_out_and_the_customer_sees_the_quoted_price.sql';

Deno.test('expired and lost are ended requests, and CONCLUDED alone was not enough', () => {
  for (const s of ['expired', 'lost', 'completed', 'closed', 'cancelled']) assert(isClosedRequest(s), s);
  for (const s of ['open', 'sent', 'quoted', 'revealed', '', null]) assert(!isClosedRequest(s), String(s));
  assert(!CONCLUDED.includes('expired') && !CONCLUDED.includes('lost'), 'CONCLUDED now covers them: this test can say so');
  assertEquals([REQUEST_ENDED_SUBMIT.code, REQUEST_ENDED_WITHDRAW.code], ['request_ended', 'request_ended']);
  assert(!/\d/.test(REQUEST_ENDED_SUBMIT.error + REQUEST_ENDED_WITHDRAW.error), 'a refusal must carry no figure');
});

Deno.test('submit_quote and withdraw_quote refuse an ended request before they write', async () => {
  const src = await Deno.readTextFile(new URL('./actions/quotes.ts', import.meta.url));
  const w = src.slice(src.indexOf("if (action === 'withdraw_quote')"), src.indexOf("if (action === 'submit_quote')"));
  const refuseW = w.indexOf('if (wInq && isClosedRequest(wInq.status)) return J(REQUEST_ENDED_WITHDRAW, 409);');
  assert(refuseW > 0, 'withdraw_quote does not refuse an ended request');
  assert(refuseW < w.indexOf(".update({ status: 'withdrawn' })"), 'withdraw_quote writes before it checks the request');
  const s = src.slice(src.indexOf("if (action === 'submit_quote')"));
  const refuseS = s.indexOf('if (inqStat && isClosedRequest(inqStat.status)) return J(REQUEST_ENDED_SUBMIT, 409);');
  assert(refuseS > 0, 'submit_quote does not refuse an ended request');
  assert(refuseS < s.indexOf('writeQuoteRow(det'), 'submit_quote writes before it checks the request');
});

Deno.test('trigger a06 freezes the same five statuses as request_closed.ts, before insert or update', async () => {
  const sql = await Deno.readTextFile(new URL(SQL, import.meta.url));
  const fn = sql.slice(sql.indexOf('create or replace function public.trg_an_ended_request_takes_no_quotation_change()'));
  const body = fn.slice(0, fn.indexOf('end $fn$;'));
  const lists = [...body.matchAll(/i\.status in \(([^)]*)\)/g)].map((m) => m[1].split(',').map((x) => x.trim().replace(/'/g, '')).sort());
  assertEquals(lists.length, 2);
  for (const l of lists) assertEquals(l, [...CLOSED_REQUEST_STATUSES].sort());
  assert(/create or replace trigger a06_an_ended_request_takes_no_quotation_change\s+before insert or update on public\.quotes/.test(sql));
  assert(sql.includes("revoke execute on function public.trg_an_ended_request_takes_no_quotation_change() from public, anon, authenticated;"));
  assert(/set search_path to 'public', 'pg_temp'/.test(fn.slice(0, 400)), 'the trigger function has no pinned search_path');
  for (const c of ['quote_amount', 'price_ex_vat', 'amount_as_stated', 'gross_amount', 'discount_amount', 'vat_amount', 'option_no']) {
    assert(body.includes(`NEW.${c}`) && body.includes(`OLD.${c}`), `${c} is not guarded`);
  }
});

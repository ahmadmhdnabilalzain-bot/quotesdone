// PROBE — fn_support_request_ratings_due, against PRODUCTION, writing nothing.
//
// public.transactions holds 0 rows, so this routine can only be proved on synthetic reveals. They
// are created inside a transaction that is aborted by `raise exception 'CHK<<...>>'`, so production
// gains no row and no email is ever queued for delivery.
//
// POSITIVE CONTROL FIRST, and this one is not decoration. Every assertion below except one is a
// ZERO ("this reveal was NOT asked"), and an absent fixture produces exactly the same zero as a
// working guard. So the probe reports the fixture rows it actually created, the refund_status the
// database actually stamped on them, and the ONE case that must be non-zero. If the 21-day case
// comes back 0, every other zero in the output means nothing.
//
//   node scripts/probe_rating_request_three_weeks_after_reveal.mjs
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';
const token = supabaseAccessToken();

async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return sql(query, attempt + 1);
  }
  return { ok: r.ok, text: t };
}

const PROBE = `do $CHK$
declare
  v_cust uuid := gen_random_uuid();
  v_inq  uuid;
  s20 bigint; s21 bigint; sRated bigint; sRef bigint;
  q20 uuid; q21 uuid; qRated uuid; qRef uuid;
  tRated uuid;
  r1 jsonb; r2 jsonb; fx jsonb; out jsonb;
begin
  insert into public.customers (id, full_name, email, phone)
  values (v_cust, 'ZZ DEMO Rating Probe', 'zz.demo.rating@example.invalid', '+971500000000');

  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier 20d','zz.s20@example.invalid') returning id into s20;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier 21d','zz.s21@example.invalid') returning id into s21;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier Rated','zz.sr@example.invalid') returning id into sRated;
  insert into public.leads (company_name, email) values ('ZZ DEMO Supplier Refunded','zz.sf@example.invalid') returning id into sRef;

  insert into public.inquiries (customer_id, summary, status)
  values (v_cust, 'ZZ DEMO rating probe job', 'open') returning id into v_inq;

  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (v_inq, s20, 1000) returning id into q20;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (v_inq, s21, 1000) returning id into q21;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (v_inq, sRated, 1000) returning id into qRated;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount) values (v_inq, sRef, 1000) returning id into qRef;

  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at)
  values (q20, v_inq, s20, v_cust, 1000, now() - interval '20 days');
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at)
  values (q21, v_inq, s21, v_cust, 1000, now() - interval '21 days');
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at)
  values (qRated, v_inq, sRated, v_cust, 1000, now() - interval '40 days') returning id into tRated;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, revealed_at, refund_status)
  values (qRef, v_inq, sRef, v_cust, 1000, now() - interval '40 days', 'refunded');

  insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
  values (sRated, v_cust, v_inq, tRated, 4, 'ZZ DEMO already rated');

  select jsonb_build_object(
    'customers', (select count(*) from public.customers where id = v_cust),
    'leads',     (select count(*) from public.leads where id in (s20,s21,sRated,sRef)),
    'quotes',    (select count(*) from public.quotes where id in (q20,q21,qRated,qRef)),
    'transactions_total', (select count(*) from public.transactions),
    'tx_at_20d', (select count(*) from public.transactions where quote_id = q20),
    'tx_at_21d', (select count(*) from public.transactions where quote_id = q21),
    'tx_rated',  (select count(*) from public.transactions where quote_id = qRated),
    'tx_refunded',(select count(*) from public.transactions where quote_id = qRef and refund_status = 'refunded'),
    'reviews',   (select count(*) from public.reviews where transaction_id = tRated),
    'refund_status_stamped', (select jsonb_object_agg(coalesce(refund_status,'NULL'), n) from (select refund_status, count(*) n from public.transactions group by 1) z),
    'age_days_of_the_21d_row', (select round(extract(epoch from (now() - revealed_at))/86400.0, 3) from public.transactions where quote_id = q21),
    'notifications_before', (select count(*) from public.notifications where type = 'rating_request')
  ) into fx;

  select public.fn_support_request_ratings_due(500) into r1;
  select public.fn_support_request_ratings_due(500) into r2;

  select jsonb_build_object(
    'fixtures', fx, 'run1', r1, 'run2', r2,
    'case1_20d_NOT_asked',   (select count(*) from public.notifications where type='rating_request' and quote_id = q20),
    'case2_21d_IS_asked',    (select count(*) from public.notifications where type='rating_request' and quote_id = q21 and coalesce(channel,'email')='email'),
    'case3_twice_is_one',    (select count(*) from public.notifications where type='rating_request' and quote_id = q21),
    'case4_rated_NOT_asked', (select count(*) from public.notifications where type='rating_request' and quote_id = qRated),
    'case5_refund_NOT_asked',(select count(*) from public.notifications where type='rating_request' and quote_id = qRef),
    'the_email', (select jsonb_build_object('to',to_email,'role',to_role,'kind',kind,'status',status,'channel',channel,'subject',subject,'body',body)
                    from public.notifications where type='rating_request' and quote_id = q21 limit 1)
  ) into out;

  raise exception 'CHK<<%>>', out::text;
end $CHK$;`;

const r = await sql(PROBE);
// The abort comes back as the management API's own JSON error envelope, so the payload is escaped
// once. Unwrap that first — regexing the raw text yields a string full of \" that JSON.parse rejects.
let body = r.text;
try { body = JSON.parse(r.text)?.message ?? r.text; } catch { /* already plain */ }
const m = /CHK<<([\s\S]*?)>>/.exec(body);
if (!m) { console.error('probe did not reach its assertion:\n' + r.text); process.exit(1); }
const o = JSON.parse(m[1]);
console.log(JSON.stringify(o, null, 2));

let fails = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail === undefined ? '' : '  — ' + detail}`); if (!ok) fails++; };

console.log('\n-- POSITIVE CONTROL --');
check('4 synthetic reveals exist', Number(o.fixtures.transactions_total) >= 4, `${o.fixtures.transactions_total} transactions`);
check('the rated fixture carries a review', Number(o.fixtures.reviews) === 1);
check('the refunded fixture is refunded', Number(o.fixtures.tx_refunded) === 1);
check('no rating request existed before the run', Number(o.fixtures.notifications_before) === 0);
check('THE ASK ACTUALLY FIRES (without this every zero below is meaningless)', Number(o.case2_21d_IS_asked) === 1);

console.log('\n-- THE FIVE CASES --');
check('20 days: NOT asked', Number(o.case1_20d_NOT_asked) === 0);
check('21 days: asked', Number(o.case2_21d_IS_asked) === 1);
check('asked twice: still ONE row', Number(o.case3_twice_is_one) === 1, `run1 asked=${o.run1.asked}, run2 asked=${o.run2.asked}`);
check('already rated: NOT asked', Number(o.case4_rated_NOT_asked) === 0);
check('refunded: NOT asked', Number(o.case5_refund_NOT_asked) === 0);
check('the mail is Support\'s and the customer\'s', o.the_email?.to_role === undefined ? o.the_email?.role === 'customer' : true, `kind=${o.the_email?.kind} role=${o.the_email?.role}`);

console.log(fails ? `\n${fails} FAILED` : '\nALL PASS — and the transaction was aborted, so production holds none of it');
// Not process.exit(0): Node 24 on Windows trips a libuv assertion tearing down the fetch handles.
// Falling off the end exits 0 on its own.
if (fails) process.exit(1);

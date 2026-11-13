#!/usr/bin/env node
// A PAID REVEAL, REHEARSED ON PRODUCTION AND ROLLED BACK, CAPTURED AS A TRACE (sales_engineer, 13 Nov 2026; W2 of the
// company-workflow fix round, founder_instruction 1685/1688).
//
// WHY. a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs judges a TRACE: by default the 21 Sep 2026 capture of the
// one paid reveal production keeps. That capture can never change, so a gap judged on its rows (the request's outcome, the
// other suppliers' notices, the response watch) stays red whatever a branch builds, until the code is applied and a new
// reveal is paid. This script produces the same trace from the code ON THIS BRANCH: it sends the pending SQL files named
// below, then ONE ZZ DEMO reveal (a request with three quotations, the first paid, exactly the row the accountant's code
// writes), then the check's own traceSql() for that transaction, all through scripts/lib/safe_replay.mjs (one request, always
// rolled back, production proven unchanged). The rows come back and are written, with every demo address replaced, to
// scripts/fixtures/zz_demo_paid_reveal_rehearsal_<date>.json, which the check judges with REVEAL_REHEARSAL=<that file>.
//   node scripts/it/rehearse_a_paid_reveal_trace.mjs [more pending .sql files to apply first ...]
// Every party is a ZZ DEMO fixture on @example.invalid; nothing is committed, nothing is sent (pg_net sends only committed rows).
import { readFileSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OWN = ['scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql'];
const files = [...process.argv.slice(2), ...OWN];
// THE CHECK'S OWN traceSql, byte for byte: importing the check would register and run its node:test tests in this process,
// so the function's text is lifted out of it and compiled here. One SELECT, the same one live mode sends.
const CHECK = readFileSync(join(ROOT, 'scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs'), 'utf8');
const src = CHECK.slice(CHECK.indexOf('export function traceSql(tx) {'), CHECK.indexOf('\nasync function liveTrace'));
const traceSql = new Function('UUID', src.replace('export function traceSql', 'return function traceSql'))(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);

const id = { c: randomUUID(), i: randomUUID(), q1: randomUUID(), q2: randomUUID(), q3: randomUUID(), t: randomUUID() };
const setup = `
do $rehearsal$
declare s1 bigint; s2 bigint; s3 bigint;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values ('${id.c}', 'ZZ DEMO Rehearsal Customer', 'zz-demo-rehearsal-cust@example.invalid', '+971500000188', true, true, 'demo://terms', 'en', now() - interval '30 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Rehearsal Chosen', 'zz-demo-rehearsal-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Rehearsal Second', 'zz-demo-rehearsal-s2@example.invalid') returning id into s2;
  insert into public.leads (company_name, email) values ('ZZ DEMO Rehearsal Third', 'zz-demo-rehearsal-s3@example.invalid') returning id into s3;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  values ('${id.i}', '${id.c}', 'plumbing', 'Dubai', 'ZZ DEMO paid reveal rehearsal', 'quoted', 'en', now() - interval '10 days', 'single');
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  select q, 1, 'ZZ DEMO heater and labour', 'ZZ DEMO Brand', 'ZZ-1', '80 litre electric', 1, 'lot', 4000, 500
    from unnest(array['${id.q1}', '${id.q2}', '${id.q3}']) q;
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, price_ex_vat, vat_treatment, status, created_at, warranty, lead_time, payment_terms, exclusions, validity)
  select q::uuid, '${id.i}', s, 4500, 4500, 'exclusive', 'submitted', now() - interval '5 days', '1 year', '1 week', '50% advance', 'civil works', '30 days'
    from (values ('${id.q1}', s1), ('${id.q2}', s2), ('${id.q3}', s3)) x(q, s);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in ('${id.q1}', '${id.q2}', '${id.q3}');
  update public.quotes set status = 'submitted' where inquiry_id = '${id.i}';
  -- the sale, as reveal_sale.ts recordRevealSale writes it: the row first, then the quote and the request read revealed
  insert into public.transactions (id, quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, app_fee, processing_fee,
                                   total_charged, customer_price, paid_by, payment_ref, fee_status, revealed_at)
  values ('${id.t}', '${id.q1}', '${id.i}', s1, '${id.c}', 4500, 135, 135, 0, 135, 4500, 'customer', 'pi_zz_demo_rehearsal', 'paid', now());
  update public.quotes set status = 'revealed' where id = '${id.q1}';
  update public.inquiries set status = 'revealed' where id = '${id.i}' and status not in ('revealed', 'completed', 'closed');
end $rehearsal$;
`;
const text = files.map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n;\n') + '\n;\n' + setup + '\n' + traceSql(id.t) + ';\n';
const rows = await replaySql(text, { label: 'paid reveal rehearsal', rows: true });
const trace = rows?.[0]?.trace;
if (!trace?.transaction) { console.error('no trace came back:', JSON.stringify(rows).slice(0, 500)); process.exit(1); }
// the same redaction as the 21 Sep capture: no fixture address leaves the database, even a demo one
const redacted = JSON.parse(JSON.stringify(trace).replace(/[a-z0-9._%+-]+@example\.invalid/gi, '<zz-demo-address>'));
const day = new Date().toISOString().slice(0, 10);
const out = `scripts/fixtures/zz_demo_paid_reveal_rehearsal_${day}.json`;
writeFileSync(join(ROOT, out), JSON.stringify({
  captured_from: `a rolled-back rehearsal on production htdblwldjkcgjvmqkbeh, ${day}, of: ${files.join(', ')}`,
  rehearsed_sql: files, ...redacted,
}, null, 1) + '\n');
console.log(`wrote ${out}: handoffs ${trace.handoffs.length}, notifications ${trace.notifications.length}, inquiry ${trace.inquiry.status}/${trace.inquiry.outcome}, watch ${trace.response_watch}`);

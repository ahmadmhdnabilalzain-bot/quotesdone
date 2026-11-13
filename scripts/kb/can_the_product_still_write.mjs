// CAN THE PRODUCT STILL WRITE?
//
// The 7 September deletion removed 461 routines. plpgsql resolves a called routine at RUN time, so
// every trigger that called one kept existing and its table silently became unwritable -- discovered
// only when an insert was attempted. A regex over trigger bodies finds most of them and mis-reads
// table names as function calls, so this does not infer: it ATTEMPTS a real insert on each table the
// product must write to, inside a transaction that always aborts.
//
// Nothing survives. Every probe ends in a raise, so the row is rolled back and the error -- or its
// absence -- is the measurement.
//
//   node scripts/kb/can_the_product_still_write.mjs

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();

// The minimum a row needs to exist. Deliberately small: this asks "can this table be written to at
// all", not "is this a realistic row".
const PROBES = [
  ['leads', `insert into public.leads (company_name, email) values ('ZZ DEMO WRITE PROBE', 'zz-probe@example.invalid')`],
  ['customers', `insert into public.customers (full_name, email) values ('ZZ DEMO Probe', 'zz-probe-c@example.invalid')`],
  ['inquiries', `insert into public.inquiries (category, emirate, raw_input, status)
                 values ('steel', 'Dubai', 'probe', 'open')`],
  ['quotes', `insert into public.quotes (inquiry_id, supplier_id, quote_amount, status)
              select i.id, l.id, 1000, 'submitted' from public.inquiries i, public.leads l limit 1`],
  ['transactions', `insert into public.transactions (quote_amount, reveal_fee) values (1000, 30)`],
  ['notifications', `insert into public.notifications (type, to_email, channel, subject, body, status)
                     values ('probe','zz@example.invalid','email','probe','probe','queued')`],
  ['documents', `insert into public.documents (bucket, path) values ('probe','probe/zz.pdf')`],
  ['support_case', `insert into public.support_case (case_ref, party_kind, subject)
                    values ('case:probe:zz', 'customer', 'probe')`],
  ['support_ceo_report', `insert into public.support_ceo_report (idempotency_key, source_agent, severity,
      subject, verified_evidence, attempted_actions, requested_outcome, owner_role_id, next_review_at)
      values ('probe:zz','customer_support','routine','probe', '{"a":1}'::jsonb, '[]'::jsonb, 'x','customer_support', now())`],
  ['wa_conversation', `insert into public.wa_conversation (phone_e164, party_kind, message_count)
                       values ('971500000000','unknown',0)`],
];

// Through the replay guard (13 Nov 2026): every probe here writes a row into a live table and rolls back, which is a lock on
// that table for as long as the request runs. It runs on the local database by default; on production only with
// QD_REPLAY_ON_PRODUCTION=1, cut at 5 s (scripts/lib/safe_replay.mjs).
const { replaySql } = await import('../lib/safe_replay.mjs');
const run = async (sqlText) => {
  try { await replaySql(sqlText, { label: 'a write probe' }); return 'returned without raising'; } catch (e) { return String(e?.body ?? e?.message ?? e); }
};

console.log('CAN THE PRODUCT WRITE?  (every probe rolls back)\n');
const broken = [];
for (const [table, stmt] of PROBES) {
  const body = await run(`do $p$ begin ${stmt}; raise exception 'PROBE_OK'; end $p$;`);
  if (body.includes('PROBE_OK')) { console.log('  writable   ' + table); continue; }
  const m = body.match(/ERROR:\s*[0-9A-Z]+:\s*([^\\"]{0,150})/);
  const why = m ? m[1].trim() : body.slice(0, 130);
  // A NOT NULL or FK complaint means the table is writable and my probe row was too thin. That is
  // not a defect in the product, and reporting it as one would be a false alarm.
  const thin = /null value in column|violates foreign key|violates check constraint/i.test(why);
  console.log('  ' + (thin ? 'writable*  ' : 'BROKEN     ') + table + '  :: ' + why);
  if (!thin) broken.push([table, why]);
}
console.log('\n* the probe row was too thin for that table; the write path itself works');
console.log(broken.length ? '\nBROKEN TABLES: ' + broken.length : '\nEvery probed table accepts a write.');
process.exit(broken.length ? 1 : 0);

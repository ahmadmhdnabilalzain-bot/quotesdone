// verify_match_similarity.mjs — the match percentage survives the write.
//
// Both writer sites (dispatch_inquiry, customer_api matchAndNotify) used to pass the literal null
// into inquiry_matches.similarity, so the score fn_match_capability computes was discarded at the
// moment of persisting and every row in every environment held null. Three customer requirements
// (disc-match-percentage, assistant-best-matches-pct, rfqcc-best-match-pct) had nothing to read.
//
// This drives ONE real dispatch through the DEPLOYED dispatch_inquiry and then asserts, against the
// rows it wrote, that the stored number is the matcher's own score and not an invention: for every
// contacted supplier, similarity must equal round(fn_match_capability score / 100, 3), where the
// score is re-read from the deployed function in a SEPARATE statement.
//
// Cost: one rfq_routing model call, same as verify_matching.mjs --live. Staging only.
//
//     node scripts/staging/verify_match_similarity.mjs
import { mgmtRead } from '../lib/qd_guard.mjs';
import {
  REF, withRun, makeBulkCorpus, makeCustomer, makeInquiry, makeRequirement,
  internalCred, call, q,
} from '../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(52)} ${detail}`);
};

await withRun(async (run) => {
  await makeBulkCorpus(run, { perTrade: 2 });
  const cust = await makeCustomer(run, { mode: 'sql' });  // the SQL path still returns a usable jwt
  const inq = await makeInquiry(run, { customer: cust, trade: 'flooring', emirate: 'Dubai' });
  await makeRequirement(run, { inquiry: inq, trade: 'flooring', value_band: 300000 });

  const d = await call('dispatch_inquiry', null, { __secret: await internalCred(), inquiry_id: inq.id });
  const rows = await mgmtRead(REF,
    `select supplier_id, similarity, match_reason from public.inquiry_matches
      where inquiry_id=${q(inq.id)} order by supplier_id`);
  step('dispatch wrote match rows', d.status === 200 && rows.length > 0,
    `HTTP ${d.status} outcome=${d.json?.outcome ?? '-'} rows=${rows.length}`);

  // The constraint says 0..1; a raw 87 would render as "8700% match" on the customer's quote card.
  const outOfRange = rows.filter((r) => r.similarity != null && (Number(r.similarity) < 0 || Number(r.similarity) > 1));
  step('every stored similarity is a 0..1 fraction', outOfRange.length === 0,
    `${rows.filter((r) => r.similarity != null).length} of ${rows.length} row(s) scored, ` +
    `${outOfRange.length} outside [0,1]; values ${rows.map((r) => r.similarity ?? 'null').join(', ')}`);

  // THE NUMBER IS THE MATCHER'S, NOT A DECORATION. Re-read the score from the deployed function and
  // require the stored value to be that score over 100. A separate statement on purpose: reading a
  // function's effect inside the statement that calls it returns the pre-call snapshot.
  // The arguments are read from inquiry_requirement rather than retyped, because that is exactly
  // what route_inquiry's capabilityRetrieve passes; a retyped product list would be scoring a
  // different question and could agree or disagree for reasons that have nothing to do with the fix.
  const scored = await mgmtRead(REF,
    `select c.supplier_id, round(c.score/100.0, 3) expected
       from public.inquiry_requirement r
       cross join lateral public.fn_match_capability(
         r.trades_required, coalesce(r.role_required,'executes'), coalesce(r.products_norm,'{}'),
         coalesce(r.brands_specified,'{}'), r.project_type, r.value_band, r.emirate, 12) c
      where r.inquiry_id = ${q(inq.id)}`);
  const expected = new Map(scored.map((r) => [Number(r.supplier_id), r.expected == null ? null : Number(r.expected)]));
  const mismatched = rows.filter((r) => {
    const e = expected.get(Number(r.supplier_id));
    return e == null || r.similarity == null || Math.abs(Number(r.similarity) - e) > 0.0005;
  });
  step('stored similarity equals fn_match_capability score / 100',
    rows.length > 0 && mismatched.length === 0,
    mismatched.length
      ? mismatched.map((r) => `${r.supplier_id}: stored ${r.similarity} vs expected ${expected.get(Number(r.supplier_id)) ?? 'not in pool'}`).join('; ')
      : rows.map((r) => `${r.supplier_id}=${r.similarity}`).join(', '));

  step('match_reason is still written alongside it',
    rows.length > 0 && rows.every((r) => String(r.match_reason || '').trim().length > 0),
    rows.map((r) => String(r.match_reason || '(empty)').slice(0, 40)).join(' | '));

  // AND IT REACHES THE CUSTOMER. A stored number whose only reader is the writer is the same defect
  // in a new column, so the last leg is the customer-authed endpoint: my_inquiries must serve the
  // best match as a percentage on the inquiry the customer owns.
  const mine = await call('customer_api', cust.jwt, { action: 'my_inquiries' });
  const served = (mine.json?.inquiries || []).find((i) => String(i.id) === String(inq.id));
  const best = served?.best_match_pct;
  const expectedBest = Math.max(...rows.map((r) => Math.round(Number(r.similarity) * 100)));
  step('customer_api my_inquiries serves best_match_pct',
    mine.status === 200 && best === expectedBest,
    `HTTP ${mine.status} best_match_pct=${best ?? 'absent'} expected=${expectedBest} ` +
    `matched_suppliers=${served?.matched_suppliers ?? '-'}`);
}, { quiet: false });

const pass = checks.filter((c) => c.ok).length;
console.log(`\nMATCH SIMILARITY ${pass}/${checks.length} on ${REF}`);
process.exitCode = pass === checks.length ? 0 : 1;

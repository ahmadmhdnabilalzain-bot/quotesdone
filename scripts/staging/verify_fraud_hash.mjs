// verify_fraud_hash.mjs — the copied_quote fraud rule, which could never fire.
//
// fn_fraud_scan carries a `copied_quote` rule: group `quotes` by committed_hash having more than
// one distinct supplier, i.e. the same quotation filed by two different suppliers. Measured 5 Aug
// 2026, `quotes.committed_hash` had NO WRITER in either project — its only writer was
// quote_review_api, deleted in d79b28e (22 Jul 2026) as proven-dead, and nothing replaced it. The
// rule has been reading a column nothing populates ever since, so a control the founder believes
// exists has never been capable of producing a single flag.
//
// A trigger now writes it from the words the supplier wrote — deliberately NOT quote_amount, since
// identical amounts on one RFQ are already caught by the identical_bids rule directly above it.
//
//     node scripts/staging/verify_fraud_hash.mjs      zero model calls
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF, withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, q } from './demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(56)} ${detail}`);
};

// Long enough to clear the trigger's 40-character floor, which exists so that boilerplate one-liners
// like "supply and install as specified" cannot collide across honest suppliers.
const COPIED = 'Supply, delivery and installation of thermally broken aluminium windows including all '
  + 'necessary fixings, sealants, ironmongery and making good. Price includes site measurement, '
  + 'shop drawings and a two-year workmanship warranty.';
const ORIGINAL = 'Fabrication and fitting of uPVC casement units with trickle vents, to the schedule '
  + 'provided, including removal of existing frames and disposal off site.';

await withRun(async (run) => {
  const cust = await makeCustomer(run);
  const [supA, supB, supC] = await Promise.all([
    makeSupplier(run, { trade: 'aluminium', variant: 0, variants: 3 }),
    makeSupplier(run, { trade: 'aluminium', variant: 1, variants: 3 }),
    makeSupplier(run, { trade: 'aluminium', variant: 2, variants: 3 }),
  ]);
  const inq = await makeInquiry(run, { customer: cust, trade: 'aluminium', status: 'quoted' });

  // Two suppliers file the SAME prose at DIFFERENT amounts — so identical_bids cannot be what fires.
  const qa = await makeQuote(run, { inquiry: inq, supplier: supA, amount: 118000, notes: COPIED });
  const qb = await makeQuote(run, { inquiry: inq, supplier: supB, amount: 141500, notes: COPIED });
  const qc = await makeQuote(run, { inquiry: inq, supplier: supC, amount: 129000, notes: ORIGINAL });

  const rows = await mgmtRead(REF, `
    select id::text, supplier_id, committed_hash, quote_amount
      from public.quotes where inquiry_id = ${q(inq.id)}::uuid order by quote_amount`);
  const byAmt = Object.fromEntries(rows.map((r) => [String(r.quote_amount).replace(/\.0+$/, ''), r]));
  const a = byAmt['118000'], b = byAmt['141500'], c = byAmt['129000'];

  step('the trigger populates committed_hash at all',
    !!a?.committed_hash && !!b?.committed_hash && !!c?.committed_hash,
    `${rows.filter((r) => r.committed_hash).length} of ${rows.length} quote(s) hashed — the column had NO writer before today`);

  step('identical prose from two suppliers produces the SAME hash',
    !!a?.committed_hash && a.committed_hash === b?.committed_hash,
    `${String(a?.committed_hash).slice(0, 16)}… == ${String(b?.committed_hash).slice(0, 16)}…`);

  step('different prose produces a different hash',
    !!c?.committed_hash && c.committed_hash !== a?.committed_hash,
    `${String(c?.committed_hash).slice(0, 16)}… differs`);

  step('the amounts differ, so identical_bids is NOT what would fire',
    Number(a?.quote_amount) !== Number(b?.quote_amount),
    `${a?.quote_amount} vs ${b?.quote_amount} — copied_quote is an independent signal`);

  // Run the real scanner and look for the flag it could never previously raise.
  await mgmtWrite(REF, 'select public.fn_fraud_scan()', 'run fraud scan');
  const flag = (await mgmtRead(REF, `
    select f.kind, f.severity, f.subject_id,
           jsonb_array_length(coalesce(f.detail->'suppliers','[]'::jsonb)) as n_suppliers
      from public.fraud_flags f
     where f.kind = 'copied_quote' and f.subject_id = ${q(a?.committed_hash || 'none')}`))[0];

  step('fn_fraud_scan raises copied_quote for the pair',
    !!flag && Number(flag.n_suppliers) === 2 && flag.severity === 'high',
    flag ? `kind=${flag.kind} severity=${flag.severity} suppliers=${flag.n_suppliers}`
         : 'no copied_quote flag — the rule still cannot fire');

  // Clean the flag: fraud_flags is keyed on the hash, not on any demo row, so teardown cannot
  // derive it. This is the same class as the agent_actions leak found in session 9.
  await mgmtWrite(REF, `delete from public.fraud_flags where kind='copied_quote' and subject_id=${q(a?.committed_hash || 'none')}`, 'clear demo flag');
  await mgmtWrite(REF, `delete from public.fraud_flags where subject_type='inquiry' and subject_id=${q(inq.id)}`, 'clear demo inquiry flags');
  void qa; void qb; void qc;
});

const bad = checks.filter((c) => !c.ok).length;
console.log(`\nFRAUD HASH ${checks.length - bad}/${checks.length} on ${REF} (zero spend)`);
process.exit(bad ? 1 : 0);

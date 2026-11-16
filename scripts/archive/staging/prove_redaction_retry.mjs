// prove_redaction_retry.mjs — does a REFUSED drawing page get a second, targeted attempt?
//
// WHAT THIS EXISTS TO ANSWER. drawing_redact runs an adversarial verifier over every rendered page
// and refuses anything it can still read an identity on. The verifier returns a precise, located
// list — "Company name/logo visible in bottom right corner", "REVISIONS block" — and until 13 Aug
// 2026 that list was written to drawing_redaction_runs.verify_detail and used for nothing: the
// loop did `skipped++; continue`. A blanket right-22%/bottom-12% fallback was tried instead and
// removed, because it was aimed at a guess rather than at the answer the verifier had already
// given.
//
// The retry is aimed at that answer. This proves the control flow around it, on staging, against
// the committed fixture whose title block carries KNOWN fake identifiers (see fixtures/README.md):
// AL NAHDA CONSULTANTS, MR OMAR BIN FAISAL, VILLA 42, plot 345-8871, +971 4 555 1234,
// info@alnahda-consult.ae, AN-2026-114.
//
// WHAT IT DOES AND DOES NOT PROVE. It proves that a refused page is retried, that the ledger
// records which attempt decided it, and that the gate still fails CLOSED — a page that is still
// dirty after the retry is not published. It does NOT prove a yield number on a real consultant's
// drawing set; that needs the real 6-sheet set, which is not in this working tree (see the ten
// pack artefacts with no source file). Do not quote a yield from this script.
//
//   node scripts/archive/staging/prove_redaction_retry.mjs
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../../lib/qd_guard.mjs';
import { REF } from '../../lib/demo_factory.mjs';

if (REF === PROD_REF) { console.error('refusing to run against production'); process.exit(2); }

// drawing_redact is internal-only and its legitimate caller is customer_api's analyze_drawing, so
// that is the credential presented here — the same one the real path carries.
const secret = (await mgmtRead(REF, "select value from public.app_secrets where key='cred_fn_customer_api'"))[0]?.value;
if (!secret) { console.error('cred_fn_customer_api missing from staging app_secrets'); process.exit(2); }

const png = readFileSync('scripts/archive/staging/fixtures/drawing_windows.png').toString('base64');
const job = 'retryprobe-' + Math.random().toString(36).slice(2, 10);

let failures = 0;
const check = (name, ok, detail) => { if (!ok) failures++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`); };

const t0 = Date.now();
const r = await fetch(`https://${REF}.supabase.co/functions/v1/drawing_redact`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ __secret: secret, job_id: job, images: [{ mime: 'image/png', data: png }] }),
});
const j = await r.json().catch(() => ({}));
console.log(`drawing_redact HTTP ${r.status} in ${((Date.now() - t0) / 1000).toFixed(1)}s: ${JSON.stringify(j).slice(0, 500)}`);

check('drawing_redact answered 200', r.status === 200, `HTTP ${r.status}`);
check('it reported a run', j && j.ok === true && !!j.job_id);
check('it accounted for the page it was given', j && j.pages_in === 1, `pages_in=${j?.pages_in}`);
check('published + skipped equals pages in', j && (j.pages_out + j.skipped) === j.pages_in,
  `out=${j?.pages_out} skipped=${j?.skipped} in=${j?.pages_in}`);
// THE GATE, WHICH THE RETRY MUST NOT HAVE OPENED. A page is publishable only if the verifier
// returned clean; verify_failed and pages_out can never both count the same page.
check('nothing was published that the verifier refused', j && j.pages_out === j.pages_verified,
  `pages_out=${j?.pages_out} pages_verified=${j?.pages_verified}`);

// Keyed on the id the FUNCTION returned, not the job_id posted to it: recordRun stores its own
// uuid and leaves caller_ref null, so matching on what we sent finds nothing and reports a missing
// ledger row for a run that was recorded correctly.
const rows = await mgmtRead(REF,
  `select pages_in, pages_out, pages_verified, verify_failed, status, verify_detail::text as detail
     from public.drawing_redaction_runs where id = '${String(j.job_id).replace(/'/g, "''")}' limit 1`);
const row = rows[0];
check('the ledger recorded the run', !!row, JSON.stringify(row || null));
if (row) {
  check('the ledger agrees with the response', Number(row.pages_out) === Number(j.pages_out),
    `ledger=${row.pages_out} response=${j.pages_out}`);
  // Whether a retry happened at all depends on what the verifier said about this fixture, which is
  // a model judgement and not something to assert. What IS asserted: if a second attempt ran, the
  // ledger says so, because "the retry never helps" must be a query and not an opinion.
  const detail = String(row.detail || '');
  const sawAttempt = /"attempts":\s*2/.test(detail);
  console.log(`INFO  verify_detail: ${detail.slice(0, 400) || '(null — the page passed first time)'}`);
  console.log(`INFO  a second attempt ${sawAttempt ? 'RAN and is recorded' : 'was not needed on this page'}`);
  check('a refused page is recorded with its attempt count', Number(row.verify_failed) === 0 || sawAttempt,
    `verify_failed=${row.verify_failed}, attempts recorded=${sawAttempt}`);
}

// ── CASE 2: A PAGE THE FIRST PASS IS LIKELY TO GET WRONG ─────────────────────────────────────
// The drawing fixture passes on attempt 1, which proves the happy path and exercises nothing of
// the retry. quotation_supplier.png is a supplier LETTERHEAD — company name, two phone numbers, an
// email and a TRN, laid out nothing like a drawing title block — fed to a detector whose prompt is
// written for drawings. It is a deliberately adversarial input, and whichever way it lands it
// answers something: refused-then-recovered exercises the targeted retry, refused-twice exercises
// fail-closed, and both must leave an attempt count in the ledger.
console.log('\n── case 2: a supplier letterhead through a drawing redactor ──');
const letterhead = readFileSync('scripts/archive/staging/fixtures/quotation_supplier.png').toString('base64');
const t1 = Date.now();
const r2 = await fetch(`https://${REF}.supabase.co/functions/v1/drawing_redact`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ __secret: secret, images: [{ mime: 'image/png', data: letterhead }] }),
});
const j2 = await r2.json().catch(() => ({}));
console.log(`drawing_redact HTTP ${r2.status} in ${((Date.now() - t1) / 1000).toFixed(1)}s: ${JSON.stringify(j2).slice(0, 600)}`);
check('case 2 answered 200', r2.status === 200, `HTTP ${r2.status}`);
check('case 2 accounted for every page', j2 && (j2.pages_out + j2.skipped) === j2.pages_in,
  `out=${j2?.pages_out} skipped=${j2?.skipped} in=${j2?.pages_in}`);
check('case 2 published nothing the verifier refused', j2 && j2.pages_out === j2.pages_verified,
  `pages_out=${j2?.pages_out} pages_verified=${j2?.pages_verified}`);
const d2 = JSON.stringify(j2?.verify_detail || []);
const retried = /"attempts":\s*2/.test(d2);
console.log(`INFO  case 2 verify_detail: ${d2.slice(0, 500)}`);
console.log(`INFO  a second attempt ${retried ? 'RAN' : 'did not run'} on this page`);
check('every refusal or recovery carries its attempt count',
  (Number(j2?.verify_failed) === 0 && !/"recovered"/.test(d2)) || retried,
  `verify_failed=${j2?.verify_failed}, detail=${d2.slice(0, 200)}`);

// ── case 3: an ADVERSARIAL page, built to defeat the first pass ────────────────────────────────
//
// WHY IT EXISTS. Cases 1 and 2 both pass the verifier on the first attempt, so neither has ever
// reached the retry — the thing this file is named after. Reported as "unexercised" for days,
// which is true and useless: it does not say whether the retry works or whether the first pass is
// simply good.
//
// drawing_watermarked.png is aimed at the gap in that reasoning. Redaction of a drawing is aimed
// at TITLE BLOCKS and CORNERS — the note at the retry site says so outright, and the two refusals
// it has ever seen were a corner logo and a REVISIONS block. This fixture carries the identity
// TWICE: once in a title block bottom-right where a first pass expects it, and once as a 46pt
// watermark rotated -28 degrees straight across the middle of the sheet, over the drawing itself,
// where nothing is aimed.
//
// WHAT HAPPENED, 13 Aug 2026 on staging: it passed on the FIRST attempt, verify_detail [], and the
// published JPG was pulled out of storage and LOOKED AT rather than trusted. Both watermark lines
// and the whole title block are blacked out; nothing identifying survives. So the retry is still
// unexercised, and the reason is now measured rather than assumed: the first pass keeps winning,
// including against a page built specifically to beat it.
//
// DO NOT TREAT A PASS HERE AS PROOF THE RETRY WORKS. It proves the opposite is not needed on this
// input. The retry branch stays unexecuted until a page genuinely refuses.
console.log('\n── case 3: an adversarial page — identity in a diagonal watermark, away from the title block ──');
const watermarked = readFileSync('scripts/archive/staging/fixtures/drawing_watermarked.png').toString('base64');
const t2 = Date.now();
const r3 = await fetch(`https://${REF}.supabase.co/functions/v1/drawing_redact`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ __secret: secret, images: [{ mime: 'image/png', data: watermarked }] }),
});
const j3 = await r3.json().catch(() => ({}));
console.log(`drawing_redact HTTP ${r3.status} in ${((Date.now() - t2) / 1000).toFixed(1)}s: ${JSON.stringify(j3).slice(0, 600)}`);
check('case 3 answered 200', r3.status === 200, `HTTP ${r3.status}`);
check('case 3 accounted for every page', j3 && (j3.pages_out + j3.skipped) === j3.pages_in,
  `out=${j3?.pages_out} skipped=${j3?.skipped} in=${j3?.pages_in}`);
// THE GATE IS THE ASSERTION, not the yield. A page the verifier refused must never be published,
// whether it refused once or twice.
check('case 3 published nothing the verifier refused', j3 && j3.pages_out === j3.pages_verified,
  `pages_out=${j3?.pages_out} pages_verified=${j3?.pages_verified}`);
const d3 = JSON.stringify(j3?.verify_detail || []);
const retried3 = /"attempts":\s*2/.test(d3);
console.log(`INFO  case 3 verify_detail: ${d3.slice(0, 500)}`);
console.log(`INFO  a second attempt ${retried3 ? 'RAN — the retry path is exercised' : 'did not run; the first pass cleared this page too'}`);
check('case 3 records an attempt count whenever it refused or recovered',
  (Number(j3?.verify_failed) === 0 && !/"recovered"/.test(d3)) || retried3,
  `verify_failed=${j3?.verify_failed}, detail=${d3.slice(0, 200)}`);

console.log(failures ? `\nFAILURES: ${failures}` : '\nALL CHECKS PASSED');
// SAY IT OUT LOUD RATHER THAN LEAVING IT TO BE INFERRED FROM A GREEN RUN. Three fixtures, none
// refused, so the retry branch has still never executed. A green run of this file means the gate
// held and the ledger is honest — it does NOT mean the retry works.
const anyRetry = [d2, d3].some((d) => /"attempts":\s*2/.test(d));
console.log(anyRetry
  ? 'RETRY PATH: exercised in this run.'
  : 'RETRY PATH: STILL UNEXERCISED — all fixtures passed on the first attempt. Do not quote a yield, '
    + 'and do not read a green run above as evidence that the retry works.');
process.exit(failures ? 1 : 0);

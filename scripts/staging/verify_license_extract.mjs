// verify_license_extract.mjs — the licence reader, and the ceiling the brief called "the next suspect".
//
// license_extract passes `max: 1500` to ai_gateway. doc_extract passed `max: 2000` the same way and
// was measured at 1,996 / 2,170 / 2,051 output tokens for one page, returning extraction_null on the
// runs that crossed it. This function maps to the same task_class (document_extraction, 8000) and
// the same model, so the same shape of defect is expected here.
//
// It hides better here than it did in doc_extract. `parseJson` returns {} when the model's output
// cannot be parsed, and every field is then read off that empty object and scrubbed to '' - so a
// truncated licence comes back as HTTP 200 `{ok:true, mode:'license', doc:{legal_name:'', ...,
// confidence:'low'}}`. That is exactly the quote_extract failure of session 8: a fully-formed,
// entirely empty result behind an ok:true. So every assertion below is on CONTENT.
//
// Three variants, from scripts/staging/fixtures/licence_pdf.mjs: a valid DED-style licence, an
// expired one, and a page that genuinely cannot be read. The third is the one that matters most -
// a reader that invents a licence number for an unreadable scan is worse than one that fails.
//
//     node scripts/staging/verify_license_extract.mjs        3 model calls, ~0.2 AED
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF, call, q } from '../lib/demo_factory.mjs';
import {
  VALID_LICENCE, EXPIRED_LICENCE, DENSE_LICENCE,
  validLicencePdf, denseLicencePdf, expiredLicencePdf, illegibleLicencePdf,
} from './fixtures/licence_pdf.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(48)} ${detail}`);
};

const cred = (await mgmtRead(REF,
  "select value from public.app_secrets where key='cred_fn_supplier_api'"))[0]?.value;
step('a credential scopes license_extract', !!cred,
  cred ? 'cred_fn_supplier_api (context fn.supplier_api)' : 'no credential scopes license_extract');
if (!cred) { report(); process.exit(); }

const CEILING = Number((await mgmtRead(REF,
  "select max_tokens from public.model_policy where task_class='document_extraction'"))[0]?.max_tokens ?? 0);

const read = async (pdf, filename) => call('license_extract', null, {
  __secret: cred, mode: 'license', file_b64: pdf.toString('base64'),
  mime: 'application/pdf', filename,
}, 180000);

const lastCost = async () => (await mgmtRead(REF, `
  select model_used, prompt_tokens, output_tokens, cost_aed, ok
    from public.ai_cost_log where fn='license_extract' order by occurred_at desc limit 1`))[0];

// ---- 1. a valid licence ------------------------------------------------------------------------
const r1 = await read(validLicencePdf(), 'trade_licence_1145872.pdf');
const d = r1.json?.doc || {};
step('a valid trade licence is read, not merely accepted',
  r1.status === 200 && r1.json?.ok === true
    && d.legal_name && d.license_number && d.license_authority,
  `HTTP ${r1.status} name="${d.legal_name || ''}" no="${d.license_number || ''}" ` +
  `confidence=${d.confidence || '-'}`);

step('the licence number and legal name match the document',
  d.license_number === VALID_LICENCE.license_number
    && String(d.legal_name || '').toLowerCase().includes('al meydan'),
  `expected ${VALID_LICENCE.license_number} / "Al Meydan…", got ` +
  `${d.license_number || 'none'} / "${d.legal_name || 'none'}"`);

step('authority, emirate and TRN are read',
  String(d.license_authority || '').toLowerCase().includes('economy')
    && d.emirate === 'Dubai' && d.trn === VALID_LICENCE.trn,
  `authority="${d.license_authority || ''}" emirate=${d.emirate || '-'} trn=${d.trn || '-'}`);

// The dates are what the licence gate and the exception sweep act on, so a wrong date either
// suspends a valid supplier or lets a lapsed one keep trading.
step('the expiry date is read and normalised to YYYY-MM-DD',
  d.expiry_date === VALID_LICENCE.expiry_date && d.issue_date === VALID_LICENCE.issue_date,
  `issue ${d.issue_date || 'none'} (expected ${VALID_LICENCE.issue_date}), ` +
  `expiry ${d.expiry_date || 'none'} (expected ${VALID_LICENCE.expiry_date}) — printed DD/MM/YYYY`);

step('the licensed activities come through',
  Array.isArray(d.activities) && d.activities.length >= 2,
  `${(d.activities || []).length} activity(ies): ${(d.activities || []).slice(0, 2).join(' | ')}`);

const c1 = await lastCost();
const out1 = Number(c1?.output_tokens ?? 0);
// The caller-side max:1500 has been removed, so the live ceiling is the task class's. Both figures
// are printed because the old one is the number that mattered: this function ran against 1500 until
// session 9, and the margin below is what says whether it was ever safe.
const OLD_CAP = 1500;
step(`a plain licence sits well inside the ${CEILING}-token ceiling`,
  out1 > 0 && out1 < CEILING * 0.8,
  c1 ? `${c1.model_used} ${c1.prompt_tokens}+${out1} tokens = ` +
       `${Math.round(100 * out1 / (CEILING || 1))}% of ${CEILING} ` +
       `(would have been ${Math.round(100 * out1 / OLD_CAP)}% of the removed ${OLD_CAP} cap)`
     : 'no ai_cost_log row for license_extract');

// ---- 1b. a realistic dense licence ---------------------------------------------------------------
// A DED licence routinely lists a dozen or more activities. The simple fixture used 57% of the
// caller's ceiling; this is the one that decides whether 1500 is safe or merely untested.
const rD = await read(denseLicencePdf(), 'trade_licence_1207734_dense.pdf');
const dd = rD.json?.doc || {};
const cD = await lastCost();
const outD = Number(cD?.output_tokens ?? 0);
step('a 15-activity licence is read completely',
  rD.status === 200 && dd.license_number === DENSE_LICENCE.license_number
    && Array.isArray(dd.activities) && dd.activities.length >= 12
    && dd.expiry_date === DENSE_LICENCE.expiry_date,
  `no=${dd.license_number || 'none'} activities=${(dd.activities || []).length}/15 ` +
  `expiry=${dd.expiry_date || 'none'} confidence=${dd.confidence || '-'}`);

step('a realistic licence has room the old cap did not give it',
  outD > 0 && outD < CEILING * 0.8,
  `${cD?.model_used} ${cD?.prompt_tokens}+${outD} tokens = ` +
  `${Math.round(100 * outD / (CEILING || 1))}% of ${CEILING}, but ` +
  `${Math.round(100 * outD / OLD_CAP)}% of the removed ${OLD_CAP} cap` +
  (outD >= OLD_CAP * 0.7 ? ' — a two-page licence would have crossed it' : ''));

// ---- 2. an expired licence ---------------------------------------------------------------------
const r2 = await read(expiredLicencePdf(), 'trade_licence_0938441_expired.pdf');
const e = r2.json?.doc || {};
const expiredInPast = !!e.expiry_date && new Date(e.expiry_date) < new Date();
step('an expired licence reads its past expiry date rather than the issue date',
  r2.status === 200 && e.expiry_date === EXPIRED_LICENCE.expiry_date && expiredInPast,
  `expiry ${e.expiry_date || 'none'} (expected ${EXPIRED_LICENCE.expiry_date}), ` +
  `in the past=${expiredInPast}, issue ${e.issue_date || 'none'}`);

// ---- 3. an unreadable page ---------------------------------------------------------------------
// The important negative. SYS_LICENSE says "If a value is not visible use an empty string and lower
// the confidence", and never guess.
const r3 = await read(illegibleLicencePdf(), 'scan_unreadable.pdf');
const u = r3.json?.doc || {};
step('an unreadable page yields no invented licence',
  r3.status === 200 && !u.license_number && !u.legal_name && u.confidence === 'low',
  `confidence=${u.confidence || '-'} name="${u.legal_name || ''}" no="${u.license_number || ''}" ` +
  `expiry="${u.expiry_date || ''}"`);

// A low-confidence empty result and a TRUNCATED result are indistinguishable from the response
// alone - which is the whole hazard. ai_gateway records both, so ask it instead of guessing.
const truncated = await mgmtRead(REF, `
  select count(*)::int n from public.ai_cost_log
   where fn='license_extract' and occurred_at > now() - interval '10 minutes'
     and coalesce(model_selected_because,'') ilike '%TRUNCATED%'`);
step('none of the four reads hit the ceiling',
  Number(truncated[0].n) === 0,
  `${truncated[0].n} of 4 calls logged TRUNCATED: — ai_gateway records the ceiling and task class ` +
  'when a model stops at max_tokens, so an empty doc can be told apart from an unreadable one');

function report() {
  const pass = checks.filter((c) => c.ok).length;
  console.log(`\nLICENCE EXTRACT ${pass}/${checks.length} on ${REF}`);
  process.exitCode = pass === checks.length ? 0 : 1;
}
report();

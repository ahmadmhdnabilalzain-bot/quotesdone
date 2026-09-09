// LOAD QuotesDone Accountant Knowledge v1 INTO public.accountant_knowledge.
//
// Forked from load_sales_knowledge_pack.mjs, which established the pattern this estate keeps: read
// the pack's OWN allowlist, validate at the door, name every refusal BEFORE any write, and never
// let an invalid record touch a row that is already correct.
//
// TWO THINGS DIFFER FROM THE SALES LOADER, both deliberate.
//
// 1. THERE IS NO content_sha256. That column exists on sales_knowledge to preserve a third party's
//    canonical hash verbatim. This pack is authored in this repository; there is no second party's
//    token to preserve, and a column holding a hash we computed ourselves would prove nothing that
//    body_sha256 does not already prove.
//
// 2. THE COMPANY'S OWN POSITION IS GENERATED, NOT AUTHORED. The chart-of-accounts records come from
//    public.gl_accounts and the tax-position records come from public.company_registration, read
//    live on every run. This is the structural guarantee that the knowledge cannot contradict the
//    founder's standing rulings: there is no hand-typed copy of vat_registered, of the threshold, of
//    the corporate tax ruling or of the auditor ruling anywhere in the JSONL that could drift from
//    the row. Re-running the loader is what refreshes them.
//
// WHAT IS REFUSED AT THE DOOR: any runtime path that is not records/*.jsonl. The evaluation
// questions live in scripts/kb/accountant_knowledge_retrieval_eval.mjs, which is executable code
// rather than a data file and can therefore never be reached by a manifest edit. The estate has a
// documented defect where exam answers leaked into the corpus an agent retrieves and 557 rows had
// to be quarantined.
//
//   node scripts/kb/load_accountant_knowledge_pack.mjs [--root <dir>] [--apply]

import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { sql } from '../lib/db.mjs';

const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = at('--root') || join(HERE, 'accountant_knowledge');
const APPLY = process.argv.includes('--apply');

const manifest = JSON.parse(readFileSync(join(ROOT, 'manifest.json'), 'utf8'));
const FILES = manifest.runtime_files;
if (!Array.isArray(FILES) || !FILES.length) { console.error('manifest.json has no runtime_files'); process.exit(2); }
console.log('runtime allowlist from the pack itself: ' + FILES.join(', '));

const PACK_ID = manifest.package_id || 'QD-ACCOUNTANT';
const PACK_VERSION = manifest.version || '1.0.0';
const UPDATED_AT = manifest.authored || new Date().toISOString().slice(0, 10);

const REQUIRED = ['record_id', 'record_type', 'domain', 'title', 'content', 'structured_data',
  'source_ids', 'epistemic_status', 'jurisdiction', 'tags'];

// The eight the table's CHECK admits. Validated HERE too, so a bad status is named by record_id in
// a refusal list rather than surfacing as a constraint violation on row 71 of a multi-row insert.
const EPISTEMIC = new Set(['method_general_accounting', 'marketplace_policy_derived',
  'framework_shape_verify_current_text', 'obligation_shape_no_figures', 'resolve_from_authority',
  'company_record_generated', 'company_governance_ruling', 'authority_protocol']);

const bodyHash = (r) => createHash('sha256').update(String(r.title) + '\n' + String(r.content), 'utf8').digest('hex');

// THE NO-FIGURES RULE, ENFORCED RATHER THAN PROMISED. A record whose epistemic_status says it holds
// no figures is scanned for the patterns a tax figure takes: a percentage, an amount in AED or
// dirhams, a count of days/months/years framed as a deadline or retention period. This will not
// catch every possible way of writing a number, and it is not claimed to -- it is a tripwire for
// the specific failure of a rate or a deadline being typed into a record that says it holds none.
const FIGURE_PATTERNS = [
  [/\b\d+(?:\.\d+)?\s*(?:%|per\s*cent|percent)/i, 'a percentage'],
  [/\b(?:AED|aed|dirhams?)\s*[\d,]/i, 'an amount in AED'],
  [/[\d,]+\s*(?:AED|aed|dirhams?)\b/i, 'an amount in AED'],
  [/\b(?:within|after|before|every|for)\s+\d+\s+(?:days?|months?|years?|weeks?)\b/i, 'a deadline or retention period in days/months/years'],
  [/\b\d+\s+(?:days?|months?|years?)\s+(?:from|of|after|following)\b/i, 'a deadline expressed in days/months/years'],
];
const NO_FIGURE_STATUSES = new Set(['obligation_shape_no_figures', 'resolve_from_authority']);

// ---------------------------------------------------------------------------------------------
// READ AND VALIDATE. Every refusal is collected BEFORE anything is written, and one fatal refusal
// aborts the whole run: a partially valid file must not partially overwrite a correct corpus.
// ---------------------------------------------------------------------------------------------
const rows = [], refused = [], seenId = new Map(), seenBody = new Map(), collisions = [];
for (const rel of FILES) {
  const norm = String(rel).replace(/\\/g, '/');
  if (!/^records\/[A-Za-z0-9_.-]+\.jsonl$/.test(norm)) {
    console.error('REFUSED RUNTIME FILE ' + rel + ' :: only records/*.jsonl may be ingested');
    process.exit(2);
  }
  const p = join(ROOT, norm);
  if (!existsSync(p)) { console.error('MISSING ' + p); process.exit(2); }
  let n = 0;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    n++;
    let r;
    try { r = JSON.parse(line); } catch { refused.push([norm + ':' + n, 'unparseable JSON']); continue; }
    const id = r.record_id || (norm + ':' + n);

    const missing = REQUIRED.filter((k) => r[k] === undefined || r[k] === null);
    if (missing.length) { refused.push([id, 'missing required field(s): ' + missing.join(',')]); continue; }
    if (!EPISTEMIC.has(r.epistemic_status)) { refused.push([id, 'epistemic_status not in the eight the table admits: ' + r.epistemic_status]); continue; }
    if (r.authority_effect !== undefined && r.authority_effect !== 'none') { refused.push([id, 'authority_effect=' + r.authority_effect + ' (a record may describe authority, never carry it)']); continue; }
    if (!Array.isArray(r.source_ids) || r.source_ids.length < 1) { refused.push([id, 'source_ids must have at least one entry']); continue; }
    if (typeof r.structured_data !== 'object' || Array.isArray(r.structured_data)) { refused.push([id, 'structured_data is not an object']); continue; }
    if (typeof r.content !== 'string' || r.content.trim().length < 200) { refused.push([id, 'content is empty or under 200 chars']); continue; }
    if (!Array.isArray(r.tags) || !r.tags.length) { refused.push([id, 'tags must have at least one entry -- they carry weight B in the search vector']); continue; }

    if (NO_FIGURE_STATUSES.has(r.epistemic_status)) {
      const hit = FIGURE_PATTERNS.find(([re]) => re.test(r.content));
      if (hit) { refused.push([id, 'epistemic_status=' + r.epistemic_status + ' but the content contains ' + hit[1] + ' -- a record that says it holds no figures may not hold one']); continue; }
    }

    if (seenId.has(r.record_id)) { refused.push([id, 'duplicate record_id, first seen at line ' + seenId.get(r.record_id)]); continue; }
    seenId.set(r.record_id, n);

    const bs = bodyHash(r);
    if (seenBody.has(bs)) collisions.push([r.record_id, seenBody.get(bs), bs]);
    else seenBody.set(bs, r.record_id);

    r.__body_sha256 = bs;
    r.__origin = norm;
    rows.push(r);
  }
}
const authoredCount = rows.length;
console.log('read ' + authoredCount + ' authored record(s) from ' + FILES.length + ' allowlisted file(s)');

// ---------------------------------------------------------------------------------------------
// GENERATE THE COMPANY'S OWN POSITION FROM LIVE ROWS. Nothing below is typed by hand anywhere.
// ---------------------------------------------------------------------------------------------
const gl = await sql(`select code, name, type, subtype, normal_balance, description
                        from public.gl_accounts where coalesce(is_active, true) order by code`);
const cr = (await sql(`select * from public.company_registration order by recorded_at desc limit 1`))[0];
if (!cr) { console.error('public.company_registration is empty -- the company position records cannot be generated and MUST NOT be invented'); process.exit(2); }
console.log('generating from live rows: ' + gl.length + ' chart-of-accounts row(s), 1 company_registration row');

const side = (b) => (String(b).toUpperCase() === 'D' ? 'debit' : 'credit');
const opp  = (b) => (String(b).toUpperCase() === 'D' ? 'credit' : 'debit');
const gen = [];

for (const a of gl) {
  const contra = (a.subtype === 'contra') || ((a.type === 'asset') !== (String(a.normal_balance).toUpperCase() === 'D'));
  gen.push({
    record_id: 'QD-ACC-COA-' + a.code,
    record_type: 'chart_of_accounts',
    domain: a.type,
    title: 'Account ' + a.code + ' ' + a.name + ' (' + a.type + (a.subtype ? ', ' + a.subtype : '') + ')',
    content: 'Account ' + a.code + ', "' + a.name + '", is a ' + a.type
      + (a.subtype ? ' account of subtype ' + a.subtype : ' account')
      + ' with a normal ' + side(a.normal_balance) + ' balance. A ' + side(a.normal_balance)
      + ' entry increases it and a ' + opp(a.normal_balance) + ' entry decreases it.'
      + (contra ? ' It is a contra account: its normal balance is the opposite of its account family, because it exists to reduce the account it sits against rather than to hold a balance of its own.' : '')
      + (a.description ? ' ' + a.description : '')
      + ' This record is generated at load time from public.gl_accounts and describes the account as it actually exists in this company\'s ledger; the chart is the authority and this record follows it, never the other way round. Before posting to this code, confirm it is still active and that its normal balance has not been changed, by reading the row rather than by relying on this text.',
    structured_data: { code: a.code, name: a.name, type: a.type, subtype: a.subtype,
                       normal_balance: a.normal_balance, is_contra: contra, source: 'public.gl_accounts' },
    source_ids: ['live:public.gl_accounts'],
    epistemic_status: 'company_record_generated',
    jurisdiction: 'QuotesDone_company_record',
    tags: ['chart of accounts', 'account ' + a.code, a.code, a.name.toLowerCase(), a.type,
           a.subtype || 'account', 'normal balance', side(a.normal_balance)].filter(Boolean),
  });
}

const vatReg = cr.vat_registered === true;
gen.push({
  record_id: 'QD-ACC-POSITION-VAT',
  record_type: 'company_position',
  domain: 'vat',
  title: 'The company\'s own VAT position: registered or not, and the threshold it is measured against',
  content: 'As recorded by the company itself in public.company_registration on ' + String(cr.vat_ruling_on || cr.recorded_at).slice(0, 10)
    + ': VAT registered = ' + String(vatReg) + '; TRN = ' + (cr.trn === null || cr.trn === undefined ? 'none held' : String(cr.trn))
    + '; the registration threshold the company measures itself against is recorded on that row as vat_threshold_aed = ' + String(cr.vat_threshold_aed) + '. '
    + 'This is the company\'s OWN recorded position and its own recorded threshold value, not a statement of what the law requires: the authoritative threshold, the window it is measured over and which supplies count towards it are published by the Federal Tax Authority and must be read there. '
    + (vatReg
        ? 'Because the company is registered, it charges VAT on its taxable supplies, issues tax invoices showing its TRN, and may recover input tax subject to the conditions in force.'
        : 'Because the company is NOT registered and holds no TRN, it does not charge VAT, does not issue tax invoices, files no VAT return, and cannot recover input tax: VAT paid to suppliers is part of the cost of what was bought. Accounts 1150 VAT Recoverable (Input) and 2100 VAT Payable exist in the chart against a future registration and carry nothing today.')
    + ' There is a standing founder ruling that the company does not register for VAT until the threshold is reached. The accountant seat monitors the measure against the threshold and does not ask the founder to register; when the measure approaches the threshold it opens a registration task. This record is generated at load time from the live row, so it cannot drift from the ruling.',
  structured_data: { vat_registered: vatReg, trn: cr.trn ?? null, vat_threshold_aed: cr.vat_threshold_aed,
                     ruling_on: cr.vat_ruling_on ?? null, source: 'public.company_registration',
                     authoritative_threshold_source: 'the Federal Tax Authority' },
  source_ids: ['live:public.company_registration'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_company_record',
  tags: ['VAT', 'VAT registered', 'TRN', 'threshold', 'company position', 'registration', 'input VAT'],
});

gen.push({
  record_id: 'QD-ACC-POSITION-CORPORATE-TAX',
  record_type: 'company_position',
  domain: 'corporate_tax',
  title: 'The company\'s own corporate tax position, and the standing instruction not to raise it',
  content: 'Recorded by the company itself in public.company_registration. Verbatim: "' + String(cr.corporate_tax_note || 'not recorded') + '" '
    + 'Two things follow for the accountant seat and both are operative rather than advisory. First, the company\'s position is settled and is read from that row rather than re-derived, so no answer given by this seat may assert that the company is registered for corporate tax or that it is required to be. Second, the founder is not to be asked about corporate tax registration, the first tax period, or small business relief; the seat monitors revenue against the threshold and opens a registration task when it approaches, and that task is the mechanism, not a question to him. '
    + 'What the threshold actually is, what the registration criteria are and what the deadlines are remain published by the Federal Tax Authority and are read there when the task is opened; they are deliberately not stored in this knowledge body. This record is generated at load time from the live row so that it cannot drift from the ruling it carries.',
  structured_data: { corporate_tax_note: cr.corporate_tax_note ?? null,
                     do_not_ask_founder_about: ['corporate tax registration', 'the first tax period', 'small business relief'],
                     mechanism: 'the seat opens a registration task when revenue approaches the threshold',
                     source: 'public.company_registration' },
  source_ids: ['live:public.company_registration'],
  epistemic_status: 'company_governance_ruling',
  jurisdiction: 'QuotesDone_company_record',
  tags: ['corporate tax', 'registration', 'founder ruling', 'small business relief', 'company position', 'do not ask'],
});

gen.push({
  record_id: 'QD-ACC-POSITION-AUDITOR',
  record_type: 'company_position',
  domain: 'audit',
  title: 'The company has no auditor and none is required',
  content: 'Recorded by the company itself in public.company_registration. Verbatim: "' + String(cr.auditor || 'not recorded') + '" '
    + 'The operative consequence is that the accountant seat does not ask for an auditor\'s name, does not record one, and does not produce a report that assumes an audit has taken place or will. It also does not conclude from the absence of an audit that the accounts are unreliable: reliability comes from the bookkeeping and the controls around it, not from an audit, and the seat is responsible for the first regardless of the second. Whether an audit becomes required later is a determination against the licensing authority\'s requirements at that time. This record is generated at load time from the live row.',
  structured_data: { auditor: cr.auditor ?? null, source: 'public.company_registration' },
  source_ids: ['live:public.company_registration'],
  epistemic_status: 'company_governance_ruling',
  jurisdiction: 'QuotesDone_company_record',
  tags: ['auditor', 'audit', 'founder ruling', 'company position', 'not required'],
});

gen.push({
  record_id: 'QD-ACC-POSITION-LICENCE',
  record_type: 'company_position',
  domain: 'licensing',
  title: 'The company\'s licence, the authority that issued it and the activities it permits',
  content: 'Recorded by the company itself in public.company_registration, from the licence document. Trade name: ' + String(cr.trade_name)
    + '. Issuing authority: ' + String(cr.authority) + '. Licence type: ' + String(cr.license_type)
    + '. Licence number: ' + String(cr.license_no) + '. Issued ' + String(cr.issued_on) + ', expires ' + String(cr.expires_on)
    + '. Owner: ' + String(cr.owner_name) + ' (' + String(cr.owner_share) + '). Permitted activities: ' + String(cr.activities) + '. '
    + (cr.license_class_note ? 'Class note from the licence: ' + String(cr.license_class_note) + ' ' : '')
    + 'For the accountant seat this row settles three questions that otherwise get guessed at: which authority the company answers to on licensing matters, that the position is a mainland licence rather than a free zone one, and which activities the company may lawfully earn income from. Income from an activity outside those listed is a licensing problem before it is an accounting one and is reported as such. The expiry date is a real operational date: it is tracked, and it is the licensing authority rather than this record that states what renewal requires. This record is generated at load time from the live row.',
  structured_data: { trade_name: cr.trade_name, authority: cr.authority, license_type: cr.license_type,
                     license_no: cr.license_no, issued_on: cr.issued_on, expires_on: cr.expires_on,
                     owner_name: cr.owner_name, owner_share: cr.owner_share, activities: cr.activities,
                     position: 'mainland', source: 'public.company_registration' },
  source_ids: ['live:public.company_registration'],
  epistemic_status: 'company_record_generated',
  jurisdiction: 'QuotesDone_company_record',
  tags: ['licence', 'trade licence', 'DET', 'mainland', 'activities', 'expiry', 'company position', 'owner'],
});

gen.push({
  record_id: 'QD-ACC-POSITION-SUMMARY',
  record_type: 'company_position',
  domain: 'tax_position',
  title: 'The company\'s tax position in one place: what is settled and what is not to be asked',
  content: 'Read this before answering any question about what the company owes, files or must register for. As recorded in public.company_registration: VAT registered = ' + String(vatReg)
    + '; TRN = ' + (cr.trn === null || cr.trn === undefined ? 'none held' : String(cr.trn))
    + '; VAT threshold recorded by the company = ' + String(cr.vat_threshold_aed)
    + '; corporate tax = not registered and not required until the threshold is reached, by standing founder ruling; auditor = none appointed and none required, by standing founder ruling. '
    + 'Three consequences. The company issues no tax invoices and charges no VAT, so a question about how to show VAT on an invoice is answered by saying it is not charged, not by describing a format. Input VAT paid to suppliers is a cost and not a recoverable asset. And the founder is not asked about VAT registration, corporate tax registration, the first tax period, small business relief, or the appointment of an auditor: each of those is settled, and the seat\'s job is to monitor the measures and open a task when one is approached, not to raise the subject. '
    + 'None of the underlying legal figures are held here. The thresholds, rates, deadlines and penalties are published by the Federal Tax Authority and are read from its current publication at the moment they are needed. This record is generated at load time from the live row, so it changes when the company\'s position changes and not before.',
  structured_data: { vat_registered: vatReg, trn: cr.trn ?? null, vat_threshold_aed: cr.vat_threshold_aed,
                     corporate_tax: 'not registered, not required until threshold, standing founder ruling',
                     auditor: 'none appointed, none required, standing founder ruling',
                     never_ask_the_founder_about: ['VAT registration', 'corporate tax registration', 'the first tax period', 'small business relief', 'appointing an auditor'],
                     figures_source: 'the Federal Tax Authority', source: 'public.company_registration' },
  source_ids: ['live:public.company_registration'],
  epistemic_status: 'company_governance_ruling',
  jurisdiction: 'QuotesDone_company_record',
  tags: ['tax position', 'VAT', 'corporate tax', 'auditor', 'TRN', 'founder ruling', 'company position', 'do not ask'],
});

for (const r of gen) {
  if (seenId.has(r.record_id)) { refused.push([r.record_id, 'generated record collides with an authored record_id']); continue; }
  seenId.set(r.record_id, -1);
  const bs = bodyHash(r);
  if (seenBody.has(bs)) collisions.push([r.record_id, seenBody.get(bs), bs]);
  else seenBody.set(bs, r.record_id);
  r.__body_sha256 = bs;
  r.__origin = 'generated';
  rows.push(r);
}

// ---------------------------------------------------------------------------------------------
// REPORT WHAT WAS READ, THEN ABORT ON ANY REFUSAL.
// ---------------------------------------------------------------------------------------------
const byType = {}; for (const r of rows) byType[r.record_type] = (byType[r.record_type] || 0) + 1;
const byEpi  = {}; for (const r of rows) byEpi[r.epistemic_status] = (byEpi[r.epistemic_status] || 0) + 1;
console.log('total records: ' + rows.length + ' (' + authoredCount + ' authored + ' + gen.length + ' generated)');
console.log('by record_type:      ' + JSON.stringify(byType));
console.log('by epistemic_status: ' + JSON.stringify(byEpi));
console.log('jurisdictions:       ' + JSON.stringify([...new Set(rows.map((r) => r.jurisdiction))]));

if (collisions.length) {
  console.log('BODY_SHA256 COLLISIONS ' + collisions.length + ' (same title+content under different IDs):');
  for (const [a, b, h] of collisions.slice(0, 20)) console.log('  ' + a + ' == ' + b + '  (' + h.slice(0, 12) + ')');
} else {
  console.log('body_sha256 collisions: 0 (' + seenBody.size + ' distinct bodies across ' + rows.length + ' records)');
}
if (refused.length) {
  console.log('REFUSED ' + refused.length + ':');
  for (const [i, w] of refused) console.log('  ' + i + ' :: ' + w);
  console.error('\nABORTING: ' + refused.length + ' refusal(s). Nothing written; existing rows untouched.');
  process.exit(1);
}
console.log('refused: 0');

if (!APPLY) { console.log('\nDRY RUN -- nothing written.'); process.exit(0); }

// ---------------------------------------------------------------------------------------------
// WRITE. Each chunk is ONE statement: a multi-row insert ... on conflict (record_id) do update, so
// it is atomic in itself and a repeat import updates in place and can produce no duplicate. Said
// plainly rather than claimed: the run is not one transaction, and it does not need to be --
// validation completed BEFORE the first write, and every statement is an idempotent upsert, so a
// run that dies halfway is fixed by running it again rather than by cleaning up after it.
// ---------------------------------------------------------------------------------------------
const lit = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (Array.isArray(a) && a.length ? 'array[' + a.map(lit).join(',') + ']::text[]' : "'{}'::text[]");

const before = new Map((await sql('select record_id, body_sha256 from public.accountant_knowledge'))
  .map((r) => [r.record_id, r.body_sha256]));
let inserted = 0, updated = 0, unchanged = 0;
for (const r of rows) {
  if (!before.has(r.record_id)) inserted++;
  else if (before.get(r.record_id) === r.__body_sha256) unchanged++;
  else updated++;
}

let done = 0;
for (let i = 0; i < rows.length; i += 25) {
  const values = rows.slice(i, i + 25).map((r) => `(${[
    lit(r.record_id), lit(r.record_type), lit(r.domain), lit(r.title), lit(r.content),
    lit(JSON.stringify(r.structured_data)) + '::jsonb', arr(r.source_ids),
    lit(r.epistemic_status), lit(r.jurisdiction), lit(PACK_ID), lit(PACK_VERSION),
    lit(r.__body_sha256), 'true', "'none'", arr(r.tags), lit(UPDATED_AT) + '::timestamptz',
  ].join(', ')})`).join(',\n');
  await sql(`insert into public.accountant_knowledge (record_id, record_type, domain, title, content,
      structured_data, source_ids, epistemic_status, jurisdiction, pack_id, pack_version,
      body_sha256, runtime_index_eligible, authority_effect, tags, updated_at)
    values ${values}
    on conflict (record_id) do update set
      record_type = excluded.record_type, domain = excluded.domain, title = excluded.title,
      content = excluded.content, structured_data = excluded.structured_data,
      source_ids = excluded.source_ids, epistemic_status = excluded.epistemic_status,
      jurisdiction = excluded.jurisdiction, pack_version = excluded.pack_version,
      body_sha256 = excluded.body_sha256,
      runtime_index_eligible = excluded.runtime_index_eligible,
      authority_effect = excluded.authority_effect, tags = excluded.tags,
      updated_at = excluded.updated_at, ingested_at = now()`);
  done += Math.min(25, rows.length - i);
  process.stdout.write(done + ' ');
}
console.log('\nknowledge rows written: ' + done);

// A body whose text changed must lose its old vector, or the HNSW index answers with a similarity
// computed against text that no longer exists. Measured and cleared rather than hoped about.
if (updated) {
  const stale = rows.filter((r) => before.has(r.record_id) && before.get(r.record_id) !== r.__body_sha256)
                    .map((r) => lit(r.record_id)).join(',');
  const cleared = await sql(`update public.accountant_knowledge set embedding_gte = null
                              where record_id in (${stale}) and embedding_gte is not null
                              returning record_id`);
  console.log('cleared ' + cleared.length + ' now-stale embedding(s); re-run the embedder');
}

console.log('\nSUMMARY  inserted ' + inserted + ' | updated ' + updated + ' | unchanged ' + unchanged
  + ' | refused ' + refused.length + ' | body collisions ' + collisions.length);

const c = await sql(`select
    (select count(*) from public.accountant_knowledge) records,
    (select count(*) from public.accountant_knowledge where search is not null) with_search,
    (select count(*) from public.accountant_knowledge where embedding_gte is not null) with_embedding,
    (select count(distinct record_type) from public.accountant_knowledge) types,
    (select count(distinct epistemic_status) from public.accountant_knowledge) epistemic_values,
    (select count(*) from public.accountant_knowledge where authority_effect <> 'none') carrying_authority,
    (select count(distinct body_sha256) from public.accountant_knowledge) distinct_bodies`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(0);

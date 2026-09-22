// A SEEDED APPROVED SUPPLIER CARRIES THE FOUNDER'S MANDATORY SIX — Assigned: it_engineer.
//
// WHY THIS EXISTS. trg_leads_e0_mandatory_six_gate went live with #698 (15 Sep 2026) and refuses any
// leads row set approval_status='approved' or verified=true unless all six are present AS EVIDENCE:
//
//   reg_name     the company name
//   reg_mobile   owner_phone_verified AND a +9715 UAE mobile in phone / phone_e164
//   reg_email    owner_email_verified — NOT leads.email, which is why a row can supply an address and
//                still be missing this one
//   reg_licence  storage.objects actually HOLDS license_doc_path in bucket supplier-docs
//   reg_profile  the same for company_profile_doc_path — a path naming nothing is not a document
//   reg_terms    signed_terms_path non-empty
//
// FIVE FIXTURES had hand-rolled a seed that wrote the approval without the evidence, and every one of
// them was refused the moment it ran: the routing check and the own-words probe (fixed in #733), and
// accountant_duties_fixtures.sql, hvac_dress_rehearsal.mjs and rehearse_supplier_loops.mjs (the last now
// retired with its subject; fixed with this file, 18 Sep 2026). Every one was found by reading, not by
// running — nobody had run three of them in over a week — which is the point. This
// check finds the sixth one on the day it is written instead of on the day someone next runs it.
//
// THE RULE. A seed that approves or verifies a supplier must do ONE of three things:
//   1. go through scripts/staging/demo_factory.mjs — the one shared way this estate builds a demo
//      supplier: it uploads the real PDFs, signs the agreement and lets the sales engineer decide; or
//   2. call public.fn_sales_engineer_verifies_supplier, the production approval path; or
//   3. supply the evidence itself, in the same file, for each of the six.
// Never by softening the gate. The gate is the founder's rule.
//
// WHAT IT DELIBERATELY DOES NOT DO:
//   * IT DOES NOT READ COMMENTS. Every line and block comment is stripped before anything is matched,
//     because this repository has twice had a check fail against a file that was already correct, on
//     the prose explaining the very rule it was checking (quotesdone-apply-discipline §7). The comment
//     block you are reading names approval_status='approved' and verified=true several times over.
//   * IT DOES NOT TOUCH THE PRODUCTION ROUTINES. scripts/sql/*.sql defines the routines that
//     legitimately approve a supplier — fn_sales_engineer_verifies_supplier writes
//     approval_status='approved' because that IS the approval. Only the seeding surfaces are in scope:
//     scripts/checks, scripts/staging, scripts/rehearsal, scripts/e2e, and the probe and fixture files
//     inside scripts/sql, which are seeds like any other.
//
//   node --test scripts/checks/a_seeded_approved_supplier_carries_the_mandatory_six.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SCRIPTS = join(REPO, 'scripts');

/** Every file under scripts/ that could carry a seed, as repo-relative POSIX paths. */
export function seedingSurfaces(root = SCRIPTS) {
  const out = [];
  (function walk(dir) {
    for (const e of readdirSync(dir)) {
      if (e === 'node_modules' || e.startsWith('.')) continue;
      const p = join(dir, e);
      if (statSync(p).isDirectory()) { walk(p); continue; }
      if (!/\.(sql|mjs|js|ts)$/.test(e) || /\.RETIRED\./.test(e)) continue;
      const rel = relative(REPO, p).split(sep).join('/');
      // scripts/sql holds the production routines; its probes and fixtures are seeds like any other.
      if (rel.startsWith('scripts/sql/') && !/(probe|fixture)/i.test(e)) continue;
      out.push(rel);
    }
  })(root);
  return out.sort();
}

/**
 * Comments removed, everything else kept at its original length so line numbers still hold.
 * Block comments and line comments only — a `--` or `//` inside a string literal is left alone,
 * which is why the scan tracks quotes as it goes.
 */
export function stripComments(src, sql) {
  const out = src.split('');
  const blank = (a, b) => { for (let k = a; k < b && k < out.length; k++) if (out[k] !== '\n') out[k] = ' '; };
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "'" || (!sql && (c === '"' || c === '`'))) {           // a string literal
      const quote = c;
      for (i++; i < src.length; i++) {
        if (!sql && src[i] === '\\') { i++; continue; }
        if (src[i] === quote) { if (sql && src[i + 1] === quote) { i++; continue; } break; }
      }
      continue;
    }
    if (src.startsWith('$$', i) || (sql && /^\$[a-z_]*\$/i.test(src.slice(i, i + 12)))) {
      const tag = src.slice(i).match(/^\$[a-z_]*\$/i)?.[0];          // a dollar-quoted body
      if (tag) { const end = src.indexOf(tag, i + tag.length); i = end < 0 ? src.length : end + tag.length - 1; continue; }
    }
    if (src.startsWith('/*', i)) { const e = src.indexOf('*/', i + 2); blank(i, e < 0 ? src.length : e + 2); i = e < 0 ? src.length : e + 1; continue; }
    if (src.startsWith(sql ? '--' : '//', i)) { const e = src.indexOf('\n', i); blank(i, e < 0 ? src.length : e); i = e < 0 ? src.length : e - 1; continue; }
  }
  return out.join('');
}

/** Split `a, b, (c, d), 'e,f'` on its TOP-LEVEL commas. */
function splitTop(s) {
  const parts = []; let depth = 0, start = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "'") { for (i++; i < s.length; i++) { if (s[i] === "'") { if (s[i + 1] === "'") { i++; continue; } break; } } continue; }
    if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth--;
    else if (c === ',' && depth === 0) { parts.push(s.slice(start, i)); start = i + 1; }
  }
  parts.push(s.slice(start));
  return parts.map((p) => p.trim());
}

/** The text from `from` to the matching close of the parenthesis that opens at or after it. */
function balanced(src, from) {
  const open = src.indexOf('(', from);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === "'") { for (i++; i < src.length; i++) { if (src[i] === "'") { if (src[i + 1] === "'") { i++; continue; } break; } } continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return { inner: src.slice(open + 1, i), end: i }; }
  }
  return null;
}

const APPROVED = /'approved'/i;
// `verified` the column, never owner_phone_verified / owner_email_verified / phone_verified.
const VERIFIED_TRUE = /(?<![\w.])verified\s*=\s*true\b/i;
const line = (src, idx) => src.slice(0, idx).split('\n').length;

/**
 * Where `src` approves or verifies a leads row. Returns [{ line, how }].
 * INSERT is read positionally — the column's index in the list decides which value is read — so an
 * insert naming approval_status while setting 'pending' is correctly left alone.
 */
export function approvingWrites(src) {
  const hits = [];
  // The alias is optional and it is NOT optional to allow for it: `update public.leads l set verified=true`
  // is the same defect as `update public.leads set verified=true`, and the first spelling walked straight
  // past the detector until the database review of 18 Sep 2026 named it.
  for (const m of src.matchAll(/update\s+(?:public\.)?leads\s+(?:as\s+)?(?:(?!set\b)[a-z_][a-z0-9_]*\s+)?set\b/gi)) {
    const stmt = src.slice(m.index, m.index + 4000).split(';')[0];
    if (APPROVED.test(stmt) && /approval_status\s*=/i.test(stmt)) hits.push({ line: line(src, m.index), how: "update ... approval_status='approved'" });
    else if (VERIFIED_TRUE.test(stmt)) hits.push({ line: line(src, m.index), how: 'update ... verified=true' });
  }
  for (const m of src.matchAll(/insert\s+into\s+(?:public\.)?leads\s*(?=\()/gi)) {
    const cols = balanced(src, m.index);
    if (!cols) continue;
    const names = splitTop(cols.inner).map((c) => c.toLowerCase());
    const vAt = names.indexOf('verified'), aAt = names.indexOf('approval_status');
    if (vAt < 0 && aAt < 0) continue;
    const vkw = src.slice(cols.end, cols.end + 200).search(/\bvalues\b/i);
    if (vkw < 0) {
      // insert ... select: the value belonging to a column cannot be read positionally through a join
      // and a where clause, so the whole statement is read instead. BOTH columns are judged — until the
      // database review of 18 Sep 2026 this branch looked only at approval_status, so an
      // `insert into public.leads (..., verified) select ..., true from ...` was invisible to it.
      const stmt = src.slice(cols.end, cols.end + 4000).split(';')[0];
      if (aAt >= 0 && APPROVED.test(stmt)) hits.push({ line: line(src, m.index), how: "insert ... select 'approved'" });
      else if (vAt >= 0 && /(?<![\w.])true\b/i.test(stmt)) hits.push({ line: line(src, m.index), how: 'insert ... select verified true' });
      continue;
    }
    const vals = balanced(src, cols.end + vkw);
    if (!vals) continue;
    const got = splitTop(vals.inner);
    if (aAt >= 0 && APPROVED.test(got[aAt] || '')) hits.push({ line: line(src, m.index), how: "insert ... approval_status 'approved'" });
    else if (vAt >= 0 && /^true$/i.test((got[vAt] || '').trim())) hits.push({ line: line(src, m.index), how: 'insert ... verified true' });
  }
  return hits;
}

/** The three ways a seed is allowed to reach an approved supplier. */
export function howItIsAllowed(src) {
  if (/demo_factory|makeSupplier|makeBulkCorpus|makeLicenceGatedSupplier/.test(src)) return 'the shared demo factory';
  if (/fn_sales_engineer_verifies_supplier/.test(src)) return 'fn_sales_engineer_verifies_supplier';
  const six = ['owner_phone_verified', 'owner_email_verified', 'license_doc_path', 'company_profile_doc_path', 'signed_terms_path'];
  const missing = six.filter((c) => !new RegExp(`\\b${c}\\b`).test(src));
  // reg_licence and reg_profile count a document only when storage HOLDS it, so naming the paths is
  // not enough: the file has to put the objects there (or upload them) as well.
  if (!/storage\.objects|uploadObject/.test(src)) missing.push('the licence and profile objects in storage');
  return missing.length ? { missing } : 'the evidence, supplied in this file';
}

test('every seeded approved supplier goes through the factory, the sales engineer, or the evidence', () => {
  const findings = [];
  for (const rel of seedingSurfaces()) {
    if (rel === 'scripts/lib/demo_factory.mjs') continue;                     // it IS the factory
    if (rel === 'scripts/checks/a_seeded_approved_supplier_carries_the_mandatory_six.test.mjs') continue;
    const raw = readFileSync(join(REPO, rel), 'utf8');
    const src = stripComments(raw, /\.sql$/.test(rel));
    const writes = approvingWrites(src);
    if (!writes.length) continue;
    const allowed = howItIsAllowed(src);
    if (typeof allowed === 'string') continue;
    findings.push(`${rel}:${writes[0].line} — ${writes.map((w) => w.how).join('; ')}; missing ${allowed.missing.join(', ')}`);
  }
  assert.deepEqual(findings, [],
    'A fixture approves or verifies a supplier without the founder\'s mandatory six. trg_leads_e0_mandatory_six_gate '
    + 'will refuse it the moment it runs. Build the supplier with scripts/staging/demo_factory.mjs, or approve it '
    + 'through fn_sales_engineer_verifies_supplier, or supply the evidence in the same file (a verified +9715 mobile, '
    + 'owner_email_verified, a licence and a company profile that storage.objects actually HOLDS, and signed terms). '
    + 'Never soften the gate.\n  ' + findings.join('\n  '));
});

// A CHECK THAT CANNOT FAIL IS WORSE THAN NO CHECK. These are the exact shapes the five real fixtures
// carried, and the exact shapes that must NOT be reported.
test('the detector fires on the shape that was actually refused, and on nothing else', () => {
  const bad = `insert into public.leads (company_name, email, verified, approval_status)
               values ('ZZ DEMO x', 'x@example.invalid', true, 'approved');`;
  assert.equal(approvingWrites(bad).length, 1, 'the shape that #733 found is not detected');
  assert.equal(howItIsAllowed(bad).missing.length, 6, 'a bare seed must be missing all six pieces of evidence');

  // THE TWO SHAPES THE DETECTOR USED TO WALK PAST (database review, 18 Sep 2026). Both were false
  // NEGATIVES — the worst kind, because the check stays green while the defect ships — and neither was
  // covered by this suite, so the detector could have regressed on either without a single test going
  // red. They are covered now.
  assert.equal(approvingWrites(                                    // an alias between `leads` and `set`
    `update public.leads l set verified = true where l.id = 1;`).length, 1, 'an aliased UPDATE evades the detector');
  assert.equal(approvingWrites(
    `update public.leads as l set approval_status = 'approved' where l.id = 1;`).length, 1, 'an "as" alias evades the detector');
  assert.equal(approvingWrites(                                    // insert ... select, verified only
    `insert into public.leads (company_name, verified) select 'ZZ DEMO q', true from public.taxonomy_trade;`).length, 1,
  'an insert...select setting verified evades the detector');
  assert.equal(approvingWrites(
    `insert into public.leads (company_name, approval_status) select 'ZZ DEMO q', 'approved' from public.taxonomy_trade;`).length, 1,
  'an insert...select setting approval_status evades the detector');
  // …and neither widening may start reporting the innocent shapes beside them.
  assert.deepEqual(approvingWrites(`update public.leads_archive set verified = true where id = 1;`), []);
  assert.deepEqual(approvingWrites(
    `insert into public.leads (company_name, verified) select 'ZZ DEMO q', false from public.taxonomy_trade;`), []);

  // Positional: approval_status is named but the value is 'pending' — not an approval.
  assert.deepEqual(approvingWrites(
    `insert into public.leads (company_name, approval_status, verified) values ('ZZ DEMO y', 'pending', false);`), []);
  // owner_phone_verified = true is not `verified = true`.
  assert.deepEqual(approvingWrites(
    `update public.leads set owner_phone_verified = true, owner_email_verified = true where id = 1;`), []);
  // A comment describing the rule is not a violation of it (quotesdone-apply-discipline §7).
  assert.deepEqual(approvingWrites(stripComments(
    `-- never write approval_status='approved' or verified=true on public.leads by hand\nselect 1;`, true)), []);
  assert.deepEqual(approvingWrites(stripComments(
    "// insert into public.leads (verified, approval_status) values (true, 'approved')\nconst x = 1;", false)), []);
  // …but the same words inside a string literal ARE code the database will run.
  assert.match(stripComments(
    `await sql(\`insert into public.leads (company_name, verified, approval_status) values ('a', true, 'approved')\`);`, false),
  /approval_status/);

  // The three exits.
  assert.equal(typeof howItIsAllowed('await makeSupplier(run, { trade: "hvac" })'), 'string');
  assert.equal(typeof howItIsAllowed('select public.fn_sales_engineer_verifies_supplier(id, \'x\')'), 'string');
  assert.equal(typeof howItIsAllowed(`insert into storage.objects (bucket_id, name) values ('supplier-docs', 'a');
    insert into public.leads (company_name, phone, owner_phone_verified, owner_email_verified,
      license_doc_path, company_profile_doc_path, signed_terms_path, verified, approval_status)
    values ('ZZ DEMO z', '+971500000099', true, true, 'a', 'b', 'c', true, 'approved');`), 'string');
});

test('the production approval routines are out of scope, and the seeding surfaces are in it', () => {
  const files = seedingSurfaces();
  assert.ok(!files.includes('scripts/sql/the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql'),
    'the gate\'s own file must never be judged by this check');
  // A retired rehearsal is out of scope by design — scripts/staging/rehearse_supplier_loops.RETIRED.mjs
  // is kept for the day its subject comes back, and a file nothing runs cannot seed anything.
  assert.ok(!files.some((f) => /\.RETIRED\./.test(f)), 'a retired file is not a live seeding surface');
  for (const f of ['scripts/checks/accountant_duties_fixtures.sql', 'scripts/rehearsal/hvac_dress_rehearsal.mjs',
    'scripts/sql/a_supplier_describes_its_services_in_its_own_words_probe.sql',
    'scripts/checks/a_ready_request_reaches_the_suppliers_registered_for_its_trade.test.mjs']) {
    assert.ok(files.includes(f), `${f} is a seeding surface and must be in scope`);
  }
});

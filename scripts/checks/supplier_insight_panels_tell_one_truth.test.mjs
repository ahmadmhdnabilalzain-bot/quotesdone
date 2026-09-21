// THE SUPPLIER INSIGHT PANELS TELL ONE TRUTH — recurrence guard for the supplier-portal audit of
// 21 Sep 2026 (ZZ DEMO Interiors, findings 18, 19, 24 and 48). The routines were fixed in
// scripts/sql/the_supplier_portal_tells_one_truth_in_every_panel.sql; this guards the components that
// render them, so a later edit cannot put the old words back on screen.
//
//   18  The EGR is the establishment card issued with the trade licence. It was shown as
//       "EGR (Emirates Green Building) certificate" — a green-building certificate it is not.
//   19  Certifications listed "VAT certificate" and "Bank details (IBAN)" with "Upload in Documents",
//       while the Documents tab has no slot for either (IBAN removed estate-wide).
//   24  Company health labelled the served emirates "COUNTRIES", and printed a risk grade with no
//       measurement behind it.
//   48  "✓" baked into heading/label text; status belongs in a badge, not in the words.
//
// Source-only (no token, runs in CI). Comments are stripped before matching, so the comments that
// explain these removals cannot trip the check; each detector is also proved to fire on a bad sample.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SRC = 'src';
const DIR = 'src/components/portal/supplier';
const PANELS = ['SupplierTwin', 'MarketIntelligence', 'SupplierKnowledgeGraph', 'SupplierAdvisor',
  'SupplierCertifications', 'SupplierDocumentImpact', 'Insights', 'SupplierInsightsSummary',
  'SupplierInsightBoard', 'SupplierQuoteBuilder', 'SupplierTier', 'SupplierOpportunities'];

// Block comments, JSX comments and // line comments (not the // inside a URL such as https://).
const strip = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"])\/\/.*$/gm, '$1');
const read = (p) => strip(readFileSync(p, 'utf8'));
const walk = (dir, out = []) => {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) { if (n !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx|js|jsx|mjs|json)$/.test(n)) out.push(p);
  }
  return out;
};

const DETECT = {
  greenBuilding: /Emirates Green/,
  retiredCertKey: /['"](vat|bank_iban)['"]/,
  retiredCertText: /VAT certificate|Bank details|IBAN/,
  riskFallback: /['"]LOW['"]|risk_level\s*(\|\||\?\?)\s*['"]/,
  countriesLabel: /['"](COUNTRIES|Countries)['"]|t\(\s*lang\s*,\s*['"]countries['"]\s*\)/,
  tickHeading: /(['"`]|>)\s*✓/,
};

test('each detector fires on the defect it guards (a check that cannot fail proves nothing)', () => {
  assert.match("doc_egr:'EGR (Emirates Green Building) certificate'", DETECT.greenBuilding);
  assert.match("{ key: 'bank_iban' }", DETECT.retiredCertKey);
  assert.match("label: 'VAT certificate'", DETECT.retiredCertText);
  assert.match("value={twin.risk_level || 'LOW'}", DETECT.riskFallback);
  assert.match("countries: 'Countries'", DETECT.countriesLabel);
  assert.match("<h3>✓ Trade licence</h3>", DETECT.tickHeading);
  assert.match("'✓ ' + t(lang, 'verified')", DETECT.tickHeading);
  assert.equal(strip('// Emirates Green\nconst a = 1;').match(DETECT.greenBuilding), null);
});

test('18: no page in src calls the EGR an "Emirates Green" certificate', () => {
  const hits = walk(SRC).filter((p) => DETECT.greenBuilding.test(read(p)));
  assert.deepEqual(hits, [], 'EGR is the establishment card — "Establishment card (EGR)" / "بطاقة المنشأة (EGR)"');
});

test('19: Certifications cannot render a VAT or bank-details (IBAN) row', () => {
  const src = read(join(DIR, 'SupplierCertifications.tsx'));
  // The one place the two keys may be named is the set that drops them for an older server.
  const rest = src.replace(/const RETIRED_SUBJECTS = new Set\(\[[^\]]*\]\);/, '');
  assert.match(src, /RETIRED_SUBJECTS\.has\(c\.key\)/, 'the list must drop retired subjects before rendering');
  assert.doesNotMatch(rest, DETECT.retiredCertKey);
  assert.doesNotMatch(rest, DETECT.retiredCertText);
  assert.match(src, /label_ar/, 'Arabic labels come from label_ar');
});

test('24: Company health has no invented risk grade and no Countries label', () => {
  const src = read(join(DIR, 'SupplierTwin.tsx'));
  assert.doesNotMatch(src, DETECT.riskFallback, 'a NULL risk_level must read "not rated yet", never a default grade');
  assert.doesNotMatch(src, DETECT.countriesLabel, 'the served emirates are labelled Emirates / الإمارات');
  assert.match(src, /twin\.emirates \?\? twin\.countries/, 'reads emirates, falling back to the legacy key');
  assert.match(src, /emirateLabel\(/, 'emirate names are localised');
});

test('48: no heading or label string in the insight panels starts with a baked-in ✓', () => {
  const hits = PANELS.map((n) => join(DIR, n + '.tsx')).filter((p) => DETECT.tickHeading.test(read(p)));
  assert.deepEqual(hits, [], 'status belongs in a badge, not in the heading text');
});

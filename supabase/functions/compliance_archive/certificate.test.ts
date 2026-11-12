// Run: deno test -A supabase/functions/compliance_archive/certificate.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert';
import { certFields, certLang, certificate, COMPANY_NOT_YET_READ, identityRows, isRegisterRow, noAcceptanceRunStatus, supplierCompany, supplierEvidence } from './certificate.ts';

// 12 Oct 2026: the live register listed 3 ZZ DEMO customers (founderdemo A/B, harness d749b836).
Deno.test('the customer register lists accepted real customers only, never a fixture', () => {
  const real = { full_name: 'Real Buyer', email: 'buyer@realco.ae', tos_accepted_at: '2026-10-01', is_demo: false };
  assert(isRegisterRow(real));
  assert(!isRegisterRow({ ...real, tos_accepted_at: null }), 'no acceptance, not a customer (1181)');
  assert(!isRegisterRow({ ...real, is_demo: true }));
  assert(!isRegisterRow({ ...real, email: 'qd-d749b836-cust0@example.invalid' }));
  assert(!isRegisterRow({ ...real, full_name: 'ZZ DEMO Customer d749b836' }));
  assert(isRegisterRow({ ...real, full_name: 'Zzdemolition Contracting LLC' }), 'a real name that merely starts with zzdemo-letters stays');
});

Deno.test('a demo fixture without an acceptance is skipped; a real party without one is still an error', () => {
  assertEquals(noAcceptanceRunStatus('qd-abb53328-cust0@example.invalid'), 'skipped');
  assertEquals(noAcceptanceRunStatus('buyer@realco.ae'), 'error');
  assertEquals(noAcceptanceRunStatus('someone@example.invalid.ae'), 'error');
  assertEquals(noAcceptanceRunStatus(null), 'error');
  // 3 Nov 2026: the registration walks' Resend sink is a fixture; nothing else at resend.dev is.
  assertEquals(noAcceptanceRunStatus('delivered+qd-0a717394-sup0@resend.dev'), 'skipped');
  assertEquals(noAcceptanceRunStatus('delivered@resend.dev'), 'error');
  assertEquals(noAcceptanceRunStatus('delivered+qd-x@resend.dev.ae'), 'error');
  assertEquals(noAcceptanceRunStatus('sales@realco.ae'), 'error');
});

// 24 Sep 2026: lead 126512 stored accepted_terms_sha256 0d99185f... while the certificate printed the
// SHA-256 of the live supplier_terms_html secret (fd487a4f...). The certificate certifies the ROW.
Deno.test('a supplier certificate prints the version, hash and user agent the acceptance row recorded', () => {
  const row = { accepted_terms_version: 'v12', accepted_terms_sha256: 'aa'.repeat(32), accepted_terms_user_agent: 'Mozilla/5.0 ZZ' };
  const ev = supplierEvidence(row, 'Supplier Agreement — Version 99', 'ff'.repeat(32));
  assertEquals(ev, { terms_label: 'Supplier Agreement — Version 12', hash: 'aa'.repeat(32), ua: 'Mozilla/5.0 ZZ' });
  const c = certificate({ ...fields, terms_label: ev.terms_label, ua: ev.ua }, 'supplier', ev.hash, 'https://quotesdone.com/supplier-agreement', 'en');
  assertStringIncludes(c.body_html, 'Browser (user agent)</td><td>Mozilla/5.0 ZZ');
  assertStringIncludes(c.body_html, 'Supplier Agreement — Version 12');
  assertStringIncludes(c.body_html, 'aa'.repeat(32));
  assert(!c.body_html.includes('ff'.repeat(32)) && !c.body_html.includes('Version 99'), 'live values never override the row');
});

Deno.test('an older acceptance without stored evidence falls back to the live label and hash; no UA reads Not recorded', () => {
  assertEquals(supplierEvidence({}, 'Supplier Agreement — Version 13', 'bb'), { terms_label: 'Supplier Agreement — Version 13', hash: 'bb', ua: '' });
  const c = certificate({ ...fields, ua: '' }, 'supplier', 'bb', 'https://quotesdone.com/supplier-agreement', 'en');
  assertStringIncludes(c.body_html, 'Browser (user agent)</td><td>Not recorded');
});
import { renderPdf } from '../pdf_native/render.ts';

const rec = { contact_name: 'ZZ DEMO Contact', signatory_name: 'ZZ DEMO Signatory', company_name: 'ZZ DEMO Co', locale: 'ar' };
const fields = { ...certFields(rec, 'supplier'), company: 'ZZ DEMO Co', phone: '+971500000012', email: 'qd-x@example.invalid',
  terms_label: 'Supplier Agreement — Version 12', accepted_utc: '2026-09-21 17:39:59 UTC', accepted_iso: '2026-09-21T17:39:59Z', ip: '' };
const HASH = '94151f940a4567944ff04f362e8c8c3ae6ad87d96cbb7ef280f505420aa11bb2';

Deno.test('a supplier certificate names the signatory the supplier entered, not the contact', () => {
  assertEquals(identityRows(fields, 'supplier'), [['Full name', 'ZZ DEMO Contact'], ['Company', 'ZZ DEMO Co'], ['Authorised signatory', 'ZZ DEMO Signatory']]);
});

Deno.test('no signatory entered: the contact is named; a customer has no signatory row', () => {
  const f = { ...certFields({ contact_name: 'ZZ DEMO Contact' }, 'supplier'), company: 'C' };
  assertEquals(identityRows(f, 'supplier')[2], ['Authorised signatory', 'ZZ DEMO Contact']);
  assertEquals(identityRows({ ...certFields({ full_name: 'ZZ DEMO Buyer' }, 'customer'), company: '' }, 'customer'), [['Full name', 'ZZ DEMO Buyer']]);
});

Deno.test('an Arabic-registered account gets an Arabic certificate; everyone else English', () => {
  assertEquals(certLang(rec), 'ar'); assertEquals(certLang({ locale: 'en' }), 'en'); assertEquals(certLang({}), 'en');
  const ar = certificate(fields, 'supplier', HASH, 'https://quotesdone.com/supplier-agreement', 'ar');
  assertEquals(ar.lang, 'ar');
  assertStringIncludes(ar.title, 'شهادة قبول');
  assertStringIncludes(ar.body_html, 'المفوّض بالتوقيع</td><td>ZZ DEMO Signatory');
  assertStringIncludes(ar.body_html, 'اتفاقية المورّد — الإصدار 12');
  assertStringIncludes(ar.body_html, 'https://quotesdone.com/ar/supplier-agreement');
  assertStringIncludes(ar.body_html, HASH);
  const en = certificate(fields, 'supplier', HASH, 'https://quotesdone.com/supplier-agreement', 'en');
  assert(!/[؀-ۿ]/.test(en.body_html), 'the English certificate carries no Arabic');
});

Deno.test('the Arabic certificate renders through pdf_native with nothing dropped', async () => {
  const c = certificate(fields, 'supplier', HASH, 'https://quotesdone.com/supplier-agreement', 'ar');
  // The brand fonts are committed copies of storage brand/qd_*.ttf (IBM Plex Sans Arabic, Sora — both SIL
  // OFL 1.1). CI runs deno tests with no network (scripts/checks/run.mjs), and a fetch that fell back to
  // Helvetica made this check fail on PR #796 for the wrong reason. A missing fixture now fails the read
  // loudly instead of silently rendering without the font this check exists to prove.
  const BRAND = new URL('../pdf_native/fixtures/brand/', import.meta.url);
  const fetchBytes = async (p: string) => /.ttf$/.test(p) ? await Deno.readFile(new URL(p, BRAND)) : null;
  const r = await renderPdf({ title: c.title, lang: c.lang, body_html: c.body_html }, { fetchBytes });
  assert(r.ok, JSON.stringify((r as { body?: unknown }).body));
  if (r.ok) {
    assertEquals(r.meta.glyphs_dropped, 0);
  }
});

// FOUNDER RULING 1672 (12 Nov 2026). His own certificate that evening printed "Triple six real estate" as he had typed it, no licence
// number, and a first name as both "Full name" and "Authorised signatory". The company is the licence's; the licence number is printed.
Deno.test('ruling 1672: the certificate names the company as its trade licence was read, with the licence number', () => {
  const row = { company_name: 'ZZ DEMO typed name', licence_legal_name: 'ZZ DEMO Licensed Real Estate L.L.C.', trade_license_no: 'ZZ-1672-001',
    contact_name: 'ZZ DEMO Firstname', signatory_name: 'ZZ DEMO Firstname Lastname' };
  assertEquals(supplierCompany(row), { company: 'ZZ DEMO Licensed Real Estate L.L.C.', licence_no: 'ZZ-1672-001' });
  const f = { ...fields, ...certFields(row, 'supplier'), ...supplierCompany(row) };
  const rows = identityRows(f, 'supplier', 'en');
  assertEquals(rows.slice(0, 4), [['Full name', 'ZZ DEMO Firstname'], ['Company', 'ZZ DEMO Licensed Real Estate L.L.C.'], ['Trade licence no.', 'ZZ-1672-001'], ['Authorised signatory', 'ZZ DEMO Firstname Lastname']]);
  assertStringIncludes(certificate(f, 'supplier', 'aa'.repeat(32), 'https://quotesdone.com/supplier-agreement', 'en').body_html, '<td>Trade licence no.</td><td>ZZ-1672-001</td>');
});

Deno.test('ruling 1672: before the licence is read the company is said in words, never an empty cell, and no licence row is drawn', () => {
  const row = { company_name: '', licence_legal_name: null, trade_license_no: null };
  assertEquals(supplierCompany(row), { company: COMPANY_NOT_YET_READ, licence_no: '' });
  const rows = identityRows({ ...fields, ...supplierCompany(row) }, 'supplier', 'en');
  assert(rows.some(([k, v]) => k === 'Company' && v === 'Not yet read from the trade licence'));
  assert(!rows.some(([k]) => k === 'Trade licence no.'));
  // an invited listing whose licence is not read yet keeps its registered name
  assertEquals(supplierCompany({ company_name: 'ZZ DEMO Listed Co LLC' }).company, 'ZZ DEMO Listed Co LLC');
});

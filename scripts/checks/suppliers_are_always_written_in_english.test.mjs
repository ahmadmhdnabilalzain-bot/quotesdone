// SUPPLIERS ARE ALWAYS WRITTEN IN ENGLISH; A CUSTOMER IN THE LANGUAGE OF THEIR INQUIRY
// (28 Sep 2026, sales_engineer with customer_support).
//
// Founder, 28 Sep 2026, after he received an Arabic supplier email sample: every message to a SUPPLIER is
// English, never Arabic, on every channel (email, WhatsApp, SMS, PDF), invitations, nudges, inquiries and
// notices included; every message to a CUSTOMER is in the language they chose when they created the inquiry.
//
// Measured before the fix: 5 supplier-bound notifications carried lang 'ar' (the Arabic invitation, chosen
// from leads.locale or an Arabic company name), and eight routines plus supplier_api chose a supplier's
// language from leads.locale. This check fails if any of that can come back:
//   SQL (the CANONICAL body of every routine - the last definition in scripts/sql/MANIFEST.txt order, then
//   the files still pending in scripts/sql/pending/, the order they will be applied in):
//     - fn_registered_locale must answer 'en' for a supplier and read no leads.locale;
//     - a04 (fn_notifications_speak_the_recipients_language) must force lang 'en' on a supplier row and
//       replace a supplier row that carries Arabic;
//     - no routine may choose a language from a lead's locale or from Arabic script in a company name,
//       except the ones listed in READS_LEADS_LOCALE_NOT_FOR_A_MESSAGE with the reason;
//     - notifications must carry the z05_notifications_supplier_is_english guard trigger (never a CHECK: a
//       CHECK refuses a status update on the five historical rows) and inquiries the lang column.
//   The senders: send_outbox's frame and send_whatsapp's template language refuse Arabic for a supplier;
//   supplier_api and its review flow take SUPPLIER_LOCALE, never leads.locale or the request's language;
//   customer_api create_inquiry stores the page language on every inquiries insert.
//   The detectors are also run on the code that was live before the fix, and must flag it.
//   node --test scripts/checks/suppliers_are_always_written_in_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { definitions } from '../lib/canonical_sql.mjs';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';
import { readSource } from '../lib/portal_sources.mjs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');   // comments may quote the old shape

// The canonical body of every routine: MANIFEST order, then the pending files (they apply after).
const order = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim())
  .filter((p) => /^scripts\/sql\/[^/]+\.sql$/.test(p));
for (const p of pendingNotes().keys()) if (!order.includes(p)) order.push(p);
const canon = new Map();
for (const p of order) {
  if (!existsSync(new URL(p, ROOT))) continue;
  for (const d of definitions(read(p))) canon.set(d.name, { file: p, body: d.stmt });
}
const body = (name) => { const d = canon.get(name); assert.ok(d, `no canonical definition of ${name}`); return code(d.body); };

// ── the detectors ────────────────────────────────────────────────────────────────────────────────────────
// A language decided from a lead's locale: the routine reads leads and a `locale` of a row alias that is not
// a customer (c./c2./cust.), or takes an Arabic company name as a language.
// A customer row alias (c, c2, cust, v_cust, ...) or the trigger's own row is not a lead.
// A customer's locale is not a finding. Besides the usual names (c, c2, *cust*), any alias the routine binds to
// public.customers, and any record it selects a customers alias's locale INTO, is a customer (16 Nov 2026:
// fn_supplier_ack_record and fn_reason_apply_customer_support__dispute_intake read `customers cu` into v_c and write the
// supplier's row in 'en'; the detector read cu.locale and v_c.locale as a lead's).
const NOT_AN_ALIAS = new Set(['on', 'where', 'join', 'left', 'inner', 'set', 'using', 'group', 'order', 'limit', 'for', 'and', 'or']);
const customerNames = (b) => {
  const a = new Set([...b.matchAll(/\bcustomers\s+(?:as\s+)?([a-z_][a-z0-9_]*)/gi)].map((m) => m[1].toLowerCase()).filter((x) => !NOT_AN_ALIAS.has(x)));
  for (const m of b.matchAll(/select\s[^;]*?\b([a-z_][a-z0-9_]*)\.locale\b[^;]*?\binto\s+([a-z_][a-z0-9_]*)/gi)) if (a.has(m[1].toLowerCase())) a.add(m[2].toLowerCase());
  return a;
};
const leadLocale = (b) => {
  const cust = customerNames(b);
  const rest = b.replace(/\b(c|c2|new|old|[a-z_]*cust[a-z0-9_]*)\.locale\b/gi, '')
    .replace(/\b([a-z_][a-z0-9_]*)\.locale\b/gi, (m, a) => (cust.has(a.toLowerCase()) ? '' : m));
  return /\bleads\b/i.test(b) && /\b[a-z_][a-z0-9_]*\.locale\b/i.test(rest);
};
const arabicNameAsLanguage = (b) => /company_name[^;]{0,80}~\s*'\[؀-ۿ\]'[\s\S]{0,300}'ar'/.test(b);
const registeredLocaleIsEnglishForSuppliers = (b) => /when\s+p_role\s*=\s*'supplier'\s+then\s+'en'/i.test(b) && !/\bleads\b/i.test(b);
const a04ForcesEnglish = (b) => /if\s+new\.to_role\s*=\s*'supplier'\s+then\s+new\.lang\s*:=\s*'en'/i.test(b.replace(/\s+/g, ' '))
  && /v_sup_ar/.test(b);

// Routines that read leads.locale for something other than a message to the supplier. Each needs a reason.
const READS_LEADS_LOCALE_NOT_FOR_A_MESSAGE = {
  // (none today - a new entry must say why the locale it reads never picks a supplier message's language)
};

test('the detectors flag the code that was live before 28 Sep 2026', () => {
  const oldResolver = "select case when x is null then null when lower(x) like 'ar%' then 'ar' else 'en' end from (select case "
    + "when p_role = 'supplier' then coalesce((select l.locale from public.leads l where l.id = p_lead)) end as x) s";
  assert.equal(registeredLocaleIsEnglishForSuppliers(oldResolver), false);
  const oldInvite = "from leads l join keyed k on k.id = l.id ... case when (lower(coalesce(l.locale, '')) like 'ar%' or "
    + "coalesce(l.company_name, '') ~ '[؀-ۿ]') and coalesce(v_body_ar, '') like '%{{link}}%' and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang";
  assert.equal(leadLocale(oldInvite), true);
  assert.equal(arabicNameAsLanguage(oldInvite), true);
  assert.equal(leadLocale("for r in select l.id, l.locale from public.leads l loop v_ar := r.locale = 'ar';"), true);
  assert.equal(leadLocale("v_ar boolean := lower(coalesce(p.locale, '')) like 'ar%'; select 1 from leads"), true);
  // a customer's locale is not a finding
  assert.equal(leadLocale("select c.locale from public.customers c join public.leads l on true"), false);
  assert.equal(leadLocale("select cu.locale into v_c from public.customers cu left join public.leads l on true; x := v_c.locale;"), false);
  // ...but a lead's locale beside a customer's still is
  assert.equal(leadLocale("select cu.locale, l.locale into v_c from public.customers cu join public.leads l on true"), true);
});

test('fn_registered_locale answers English for every supplier', () => {
  assert.ok(registeredLocaleIsEnglishForSuppliers(body('fn_registered_locale')),
    `${canon.get('fn_registered_locale').file}: fn_registered_locale can answer Arabic for a supplier again`);
});

test('a04 writes every supplier row in English, and a customer row in its inquiry\'s language', () => {
  const b = body('fn_notifications_speak_the_recipients_language');
  assert.ok(a04ForcesEnglish(b), `${canon.get('fn_notifications_speak_the_recipients_language').file}: a supplier row can keep lang 'ar' or an Arabic body`);
  assert.match(b, /fn_inquiry_locale\(new\.inquiry_id\)/, 'a customer row about an inquiry no longer takes the inquiry\'s language');
});

test('no routine chooses a supplier\'s language from leads.locale or an Arabic company name', () => {
  const bad = [];
  for (const [name, d] of canon) {
    const b = code(d.body);
    if (arabicNameAsLanguage(b)) bad.push(`${name} (${d.file}): an Arabic company name chooses the language`);
    if (leadLocale(b) && !READS_LEADS_LOCALE_NOT_FOR_A_MESSAGE[name]) bad.push(`${name} (${d.file}): reads a lead's locale`);
  }
  assert.deepEqual(bad, [], 'a supplier could be written in Arabic again:\n  ' + bad.join('\n  '));
});

test('the schema carries the rule: the supplier guard trigger and the inquiry language', () => {
  const all = order.filter((p) => existsSync(new URL(p, ROOT))).map(read).join('\n');
  // A trigger, not a CHECK (release review of #1065, 29 Sep 2026): a NOT VALID CHECK still runs on every
  // UPDATE, so the delivery/bounce webhooks' status update on the five historical Arabic seed rows failed.
  // The guard fires on insert and on an update of lang/subject/body/to_role only, never on status.
  assert.doesNotMatch(code(all), /add constraint notifications_supplier_is_english/i,
    'a CHECK on notifications would refuse a status update on the historical Arabic supplier rows');
  assert.match(code(all), /create trigger z05_notifications_supplier_is_english\s+before insert or update of lang, subject, body, to_role on public\.notifications/i);
  const g = body('fn_notifications_supplier_is_english');
  assert.match(g, /old\.lang is not distinct from new\.lang/i, 'the guard must let an update that leaves the language alone through');
  assert.match(g, /coalesce\(new\.to_role, ''\) = 'supplier' and coalesce\(new\.lang, 'en'\) <> 'en'/i);
  assert.match(code(all), /alter table public\.inquiries add column if not exists lang text/i);
  assert.match(code(all), /create trigger a00_inquiries_lang_default before insert on public\.inquiries/i);
});

test('the senders never frame or template a supplier message in Arabic', () => {
  const outbox = code(read('supabase/functions/send_outbox/index.ts').replace(/\/\/.*$/gm, ''));
  assert.match(outbox, /const arMail = !internal && !supplierSide && n\.lang === 'ar'/, 'send_outbox: a supplier mail can get the Arabic frame');
  const wa = functionSource('send_whatsapp').replace(/\/\/.*$/gm, '');
  assert.match(wa, /const wlang = n\.lang === 'ar' && n\.to_role !== 'supplier' \? 'ar' : 'en'/, 'send_whatsapp: a supplier can get the Arabic template');
  assert.match(read('supabase/functions/_shared/registered_locale.ts'), /export const SUPPLIER_LOCALE: Locale = 'en';/);
});

test('supplier_api and its review flow write to a supplier in English only', () => {
  for (const f of ['supabase/functions/supplier_api/index.ts', 'supabase/functions/supplier_api/quote_review_actions.ts']) {
    // supplier_api/index.ts names the whole function (index.ts plus its modules since 9 Nov 2026).
    const s = (f === 'supabase/functions/supplier_api/index.ts' ? functionSource('supplier_api') : read(f)).replace(/\/\/.*$/gm, '');
    for (const re of [/sup\.locale/, /full\?\.locale/, /body\.lang === 'ar'/, /String\(sup\.locale/]) {
      assert.doesNotMatch(s, re, `${f}: a supplier message or document takes its language from ${re.source} again`);
    }
  }
});

test('create_inquiry stores the language the customer chose on every inquiry it creates', () => {
  const s = functionSource('customer_api');
  const inserts = s.match(/from\('inquiries'\)\.insert\(\{[^}]{0,120}/g) || [];
  assert.ok(inserts.length >= 4, `expected the four create_inquiry inserts, found ${inserts.length}`);
  for (const i of inserts) assert.match(i, /lang: inquiryLang/, 'an inquiry is created without the customer\'s chosen language: ' + i.slice(0, 80));
  assert.match(s, /const inquiryLang = documentLocale\(body\.lang, cust\.locale\);/);
  // 15 Nov 2026 (8170e5077): site_photos follows lang in the payload, so lang is no longer its last key
  assert.match(readSource('src/components/me/NewRequest.tsx'), /action: 'create_inquiry'[^\n]*requirement_edits: edits, lang(?: \}|, )/, 'the composer no longer sends the page language');
});

// language_follows_registration.mjs — THE REGISTERED LANGUAGE FOLLOWS EVERY TOUCHPOINT UNTIL THE REVEAL.
// node scripts/checks/language_follows_registration.mjs          (reads production; needs a Supabase token)
//
// Founder, 14 Sep 2026 (founder_instruction #193): "are you making sure things are aligned in terms of
// the language. so if someone registered while the language was arabic then arabic follows through the
// whole workflow till the reveal. and if english then all english."
// SUPERSEDED FOR SUPPLIERS on 28 Sep 2026: every message to a supplier is English, whatever leads.locale
// says, so fn_registered_locale answers 'en' for a supplier and the walk's "Arabic supplier" now expects
// English (scripts/checks/suppliers_are_always_written_in_english.test.mjs holds that rule). A customer
// is written in the language they chose when they created the inquiry (inquiries.lang).
//
// Three parts, and the check fails if any one of them does:
//   1. THE WALK (production, one aborted transaction). An Arabic-registered and an English-registered
//      ZZ DEMO customer, and an Arabic and an English ZZ DEMO supplier, are created and taken through the
//      messages each stage sends: new job to the suppliers, quote-ready to the customers, a hold notice to
//      each supplier, a project-chat message, the reveal receipt and the invoice-ready notice, and a
//      sales-engineer billing answer that is written in English only. Every row they receive must carry
//      the recipient's registered language in notifications.lang and read wholly in it
//      (public.fn_language_mismatch - the one definition). Every address is @example.invalid, every row
//      is captured by zzzz_notifications_demo_capture, and the transaction is rolled back by raise: the
//      walk is incapable of reaching a person, and nothing survives it.
//   2. THE INTAKE QUESTIONS. Every one of the 396 plain-language questions the sales engineer asks in
//      Arabic must be Arabic without English prose in it.
//   3. THE DOCUMENTS AND THE PAGES. The quotation and comparison PDFs are proved by
//      supabase/functions/_shared/quote_documents.test.ts (Arabic documents carry no English word outside
//      brands, standards and codes); it is run here. The edge functions and portals are then read to
//      prove each touchpoint takes its language from the registered row and not from the request body,
//      the URL, the browser or the text the person typed.
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { manifestLines, manifestWithPending } from '../lib/pending_sql.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const REF = 'htdblwldjkcgjvmqkbeh';
const tokenPath = join(homedir(), '.supabase', 'access-token');
const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(tokenPath) ? readFileSync(tokenPath, 'utf8') : '')).trim();
const fails = [];
const ok = (cond, msg) => { if (!cond) fails.push(msg); return cond; };
const src = (p) => readFileSync(join(ROOT, p), 'utf8');

async function sql(query) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }) });
  const text = await r.text();
  return { ok: r.ok, status: r.status, text };
}

// ── 1. THE WALK ────────────────────────────────────────────────────────────────────────────────
const WALK = String.raw`
do $walk$
declare
  tag text := substr(md5(random()::text), 1, 8);
  c_ar uuid := gen_random_uuid(); c_en uuid := gen_random_uuid();
  e_car text; e_cen text; e_sar text; e_sen text;
  l_ar bigint; l_en bigint; h bigint; rows jsonb; errs jsonb := '[]'::jsonb;
  names text[] := array['ZZ DEMO Arabic Supplier', 'ZZ DEMO English Supplier', 'ZZ DEMO Arabic Customer', 'ZZ DEMO English Customer'];
begin
  e_car := 'zz-demo-lang-car-' || tag || '@example.invalid'; e_cen := 'zz-demo-lang-cen-' || tag || '@example.invalid';
  e_sar := 'zz-demo-lang-sar-' || tag || '@example.invalid'; e_sen := 'zz-demo-lang-sen-' || tag || '@example.invalid';
  insert into public.customers (id, email, full_name, locale) values
    (c_ar, e_car, 'ZZ DEMO Arabic Customer', 'ar'), (c_en, e_cen, 'ZZ DEMO English Customer', 'en');
  insert into public.leads (company_name, email, claimed_by, locale)
    values ('ZZ DEMO Arabic Supplier', e_sar, e_sar, 'ar') returning id into l_ar;
  insert into public.leads (company_name, email, claimed_by, locale)
    values ('ZZ DEMO English Supplier', e_sen, e_sen, 'en') returning id into l_en;

  -- the job reaches the suppliers (customer_api matchAndNotify writes English only)
  insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body) values
    ('new_inquiry', e_sar, 'supplier', l_ar, 'email', 'New job request on QuotesDone', 'A customer is requesting quotes for: kitchen fit-out. Log in to your QuotesDone supplier portal to quote.'),
    ('new_inquiry', e_sen, 'supplier', l_en, 'email', 'New job request on QuotesDone', 'A customer is requesting quotes for: kitchen fit-out. Log in to your QuotesDone supplier portal to quote.');
  -- a quote is on hold (fn_supplier_notice, both languages supplied)
  perform public.fn_supplier_notice(l_ar, 'quote_spec_hold', 'Your quote is on hold', 'Hello {company}, your quote is on hold until the missing specification is added.',
                                    'عرضك معلّق', 'مرحبًا {company}، عرضك معلّق حتى تُضاف المواصفات الناقصة.');
  perform public.fn_supplier_notice(l_en, 'quote_spec_hold', 'Your quote is on hold', 'Hello {company}, your quote is on hold until the missing specification is added.',
                                    'عرضك معلّق', 'مرحبًا {company}، عرضك معلّق حتى تُضاف المواصفات الناقصة.');
  -- the quote is ready to compare (supplier_api notifyNewQuote writes English only)
  insert into public.notifications (type, to_email, to_role, channel, subject, body) values
    ('new_quote', e_car, 'customer', 'email', 'You have a new quote on QuotesDone', 'A supplier submitted a quote for your request. Log in to view the full quotation and compare.'),
    ('new_quote', e_cen, 'customer', 'email', 'You have a new quote on QuotesDone', 'A supplier submitted a quote for your request. Log in to view the full quotation and compare.');
  -- a project-chat message both ways (messages_api writes English only)
  insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body) values
    ('new_message', e_car, 'customer', null, 'email', 'New message from a supplier', 'You have a new message on your open project chat. Log in to reply.'),
    ('new_message', e_sen, 'supplier', l_en, 'email', 'New message from a customer on QuotesDone', 'You have a new message on an open project chat. Log in to your supplier portal to reply.');
  -- the reveal receipt and a billing answer, written by the sales engineer and delivered by customer_support
  begin
    h := public.fn_sales_engineer_writes('reveal_receipt', 'customer', e_car, null, c_ar, null, null,
          'Your supplier is revealed', 'Your payment went through and the supplier''s contact details are in your portal.',
          'تم الكشف عن المورّد', 'تمّت عملية الدفع وبيانات التواصل مع المورّد في بوابتك.', '{}', 'lang-walk-rr-ar-' || tag);
    perform public.fn_customer_support_acts_on_handoff(h);
    h := public.fn_sales_engineer_writes('reveal_receipt', 'customer', e_cen, null, c_en, null, null,
          'Your supplier is revealed', 'Your payment went through and the supplier''s contact details are in your portal.',
          'تم الكشف عن المورّد', 'تمّت عملية الدفع وبيانات التواصل مع المورّد في بوابتك.', '{}', 'lang-walk-rr-en-' || tag);
    perform public.fn_customer_support_acts_on_handoff(h);
    h := public.fn_sales_engineer_writes('billing_answer', 'customer', e_car, null, c_ar, null, null,
          'Your question about a charge', 'Here is what our records show: one reveal fee.', null, null, '{}', 'lang-walk-ba-ar-' || tag);
    perform public.fn_customer_support_acts_on_handoff(h);
  exception when others then errs := errs || to_jsonb('sales engineer / customer_support path: ' || sqlerrm);
  end;
  -- the invoice-ready notice, through the REAL door: the stored Stripe PDF lands on a sale (doc_path), the
  -- accountant files it (fn_accountant_files_reveal_invoice) and hands it to the sales engineer, who tells
  -- the customer. (27 Oct 2026, accountant) This used to hand-write the handoff row; that imitation carried
  -- no sender, so the 1013 note refused it while the real door worked - the walk measured its own fixture.
  begin
    insert into public.transactions (customer_id, doc_path, doc_name)
    values (c_ar, 'invoices/zz-demo-lang-walk/' || tag || '-ar.pdf', 'ZZ DEMO lang walk invoice.pdf'),
           (c_en, 'invoices/zz-demo-lang-walk/' || tag || '-en.pdf', 'ZZ DEMO lang walk invoice.pdf');
  exception when others then errs := errs || to_jsonb('invoice-ready path: ' || sqlerrm);
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'type', n.type, 'role', n.to_role, 'channel', n.channel, 'lang', n.lang, 'status', n.status,
           'want', coalesce(public.fn_registered_locale(n.to_role, null, n.lead_id, n.to_email), '?'),
           'bad', public.fn_language_mismatch(coalesce(public.fn_registered_locale(n.to_role, null, n.lead_id, n.to_email), 'en'),
                                              coalesce(n.subject, '') || ' ' || coalesce(n.body, ''), names),
           'to', split_part(n.to_email, '-', 4)) order by n.id), '[]'::jsonb)
    into rows
    from public.notifications n where n.to_email in (e_car, e_cen, e_sar, e_sen);

  raise exception 'CHK<<%>>', jsonb_build_object('rows', rows, 'errors', errs,
    'intake_total', (select count(*) from public.category_specs cs, jsonb_array_elements(cs.fields) f),
    'intake_bad', (select coalesce(jsonb_agg(left(f->>'question_plain_ar', 80)), '[]'::jsonb) from public.category_specs cs, jsonb_array_elements(cs.fields) f
                    -- Product names an Arabic speaker writes in Latin script (one meeting-room question
                    -- names both). Named one by one: a name is not an English sentence.
                    where public.fn_language_mismatch('ar', f->>'question_plain_ar', array['Teams', 'Zoom']) is not null));
end $walk$;`;

// 22 Sep 2026 (review of PR #857). This used to be one all-or-nothing gate: with no management token
// the whole file failed, so run.mjs could only run it where a token exists — and CI's checks job has
// none, which meant "registered but never enforced". The file has three parts and only the first two
// need production. Part 3 reads SOURCE, and part 3 is what had been wrong on main since 14 Sep while
// nothing ran it. So the parts are now separable: with no token the walk and the intake questions are
// NOT VERIFIED and say so by name, and the source assertions still run and still fail the check.
// This is not a softening — nothing that used to be asserted has stopped being asserted; a part that
// could not run before is now the part that CI enforces.
const NOT_VERIFIED = [];
if (!TOKEN) {
  NOT_VERIFIED.push('the production walk (4 demo recipients, one rolled-back transaction)');
  NOT_VERIFIED.push('the 396 Arabic intake questions');
  console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL — no SUPABASE_ACCESS_TOKEN and no ~/.supabase/access-token.');
  console.log('  Parts 1 and 2 read production and are NOT asserted in this run. Part 3 (the documents,');
  console.log('  the edge functions and the portals) runs below and still fails this check.');
} else {
  // THE WALK AS IT WILL BE (accountant, 27 Oct 2026). A committed-but-unapplied file that changes a routine on the
  // walk's path is replayed first, in the same rolled-back request (safe_replay), so a PR is measured against what it
  // will apply - not only against what production runs today.
  const applied = new Set(manifestLines());
  const onPath = /seat_handoff_kind|fn_accountant_files_reveal_invoice|fn_sales_engineer_tells_customer_invoice_ready|fn_sales_engineer_writes|fn_customer_support_acts_on_handoff|fn_supplier_notice|fn_registered_locale|fn_language_mismatch|fn_handoff_summary/;
  const pendingOnPath = manifestWithPending().filter((f) => !applied.has(f) && !/_probe\.sql$/.test(f) && onPath.test(src(f)));
  let msg;
  if (pendingOnPath.length) {
    console.log(`walk: replayed after ${pendingOnPath.length} pending file(s) on its path: ${pendingOnPath.join(', ')}`);
    try { await replaySql([...pendingOnPath.map(src), WALK].join('\n;\n'), { label: 'language walk after pending files' }); msg = 'the walk returned without raising'; }
    catch (e) {
      msg = String(e?.body ?? e?.message ?? e);
      const brace = msg.indexOf('{');
      if (brace >= 0) { try { msg = String(JSON.parse(msg.slice(brace)).message ?? msg); } catch (_e) { /* raw */ } }
    }
  } else {
    const r = await sql(WALK);
    msg = r.text; try { const j = JSON.parse(r.text); msg = String(j.message || j.error || r.text); } catch (_e) { /* raw */ }
    if (!/CHK<</.test(msg)) msg = `HTTP ${r.status}: ${msg}`;
  }
  const m = msg.match(/CHK<<(.*)>>/s);
  if (!m) fails.push('the walk did not report: ' + msg.slice(0, 400));
  else {
    const out = JSON.parse(m[1]);
    for (const e of out.errors) fails.push(e);
    const rows = out.rows;
    console.log(`walk: ${rows.length} message(s) to 2 customers and 2 suppliers`);
    for (const x of rows) {
      const where = `${x.type} → ${x.role} ${x.to} (${x.channel})`;
      ok(x.want === 'ar' || x.want === 'en', `${where}: recipient has no registered language`);
      ok(x.lang === x.want, `${where}: notifications.lang is ${x.lang}, registered language is ${x.want}`);
      ok(x.bad === null, `${where}: not wholly in ${x.want} — ${x.bad}`);
      ok(x.status !== 'queued', `${where}: left queued (a demo row must be captured, status ${x.status})`);
      console.log(`  ${x.bad === null && x.lang === x.want ? 'ok ' : 'BAD'} ${where} lang=${x.lang}`);
    }
    const has = (type, to) => rows.some((x) => x.type === type && x.to === to);
    for (const [type, to] of [['new_inquiry', 'sar'], ['new_inquiry', 'sen'], ['quote_spec_hold', 'sar'], ['quote_spec_hold', 'sen'],
                              ['new_quote', 'car'], ['new_quote', 'cen'], ['new_message', 'car'], ['new_message', 'sen'],
                              ['reveal_receipt', 'car'], ['reveal_receipt', 'cen'], ['billing_answer', 'car'],
                              ['invoice_ready', 'car'], ['invoice_ready', 'cen']]) ok(has(type, to), `the walk never produced ${type} for ${to}`);
    ok(out.intake_total >= 396, `intake: expected at least 396 questions, found ${out.intake_total}`);
    ok(out.intake_bad.length === 0, `intake: ${out.intake_bad.length} Arabic question(s) carry English: ${out.intake_bad.slice(0, 3).join(' | ')}`);
    console.log(`intake: ${out.intake_total} Arabic questions, ${out.intake_bad.length} with English in them`);
  }
}

// ── 3a. THE DOCUMENTS ──────────────────────────────────────────────────────────────────────────
const deno = spawnSync('deno', ['test', '--no-lock', '--node-modules-dir=auto', 'supabase/functions/_shared/quote_documents.test.ts'], { cwd: ROOT, encoding: 'utf8', shell: process.platform === 'win32' });
ok(deno.status === 0, 'quotation / comparison PDFs: quote_documents.test.ts failed — ' + String(deno.stdout + deno.stderr).split('\n').filter((l) => /FAILED|error/i.test(l)).slice(0, 4).join(' / '));
console.log(`documents: quote_documents.test.ts ${deno.status === 0 ? 'passed' : 'FAILED'}`);

// ── 3b. EACH TOUCHPOINT READS THE REGISTERED ROW ─────────────────────────────────────────────────
const F = 'supabase/functions/';
const capi = src(F + 'customer_api/index.ts');
// 21 Sep 2026 (customer-portal journey audit, finding 4): the "النسخة العربية" button served English,
// because a document read customers.locale alone and ignored the button that was pressed. The fix went
// further than the quotation — EVERY customer document (quotation, comparison, CSV, brief) now routes
// through documentLocale(body.lang, cust.locale): the registered language is the default, and only an
// explicit 'en'/'ar' overrides it. 22 SEP 2026 (DL-12): these two lines still described the state
// before that fix — they demanded three bare asLocale(cust.locale) calls and exactly one
// documentLocale — so this check had been RED on main since, naming correct code as the defect.
// What must hold now: every document action takes documentLocale, and none reads the locale alone.
ok((capi.match(/documentLocale\(body\.lang, cust\.locale\)/g) || []).length >= 4,
   'customer_api: each customer document (quote, comparison, CSV, brief) must take documentLocale(body.lang, cust.locale)');
ok(!/lang = asLocale\(cust\.locale\)/.test(capi),
   'customer_api: a document reads customers.locale alone again, so the language button it was asked for is ignored');
ok(!/String\(body\.lang/.test(capi), 'customer_api: a document still reads its language from the request body');
ok(/registeredLocale\(admin, \{ role: 'customer'/.test(src(F + 'quote_compare/index.ts')), 'quote_compare: an unspecified language must come from the registered customer');
ok(!/test\(String\(inq\.summary/.test(src(F + 'quote_compare/index.ts')), 'quote_compare: still guesses the language from the request text');
ok(/const ar = asLocale\(\(cust as any\)\?\.locale\) === 'ar'/.test(src(F + 'inquiry_intake/index.ts')), 'inquiry_intake: the sales engineer must answer in the registered language');
ok(!/String\(b\.lang/.test(src(F + 'customer_portal/index.ts')), 'customer_portal: alerts still take their language from the request body');
ok(!/tmpl\[key\]\.en/.test(src(F + 'send_whatsapp/index.ts')) && /n\.lang === 'ar'/.test(src(F + 'send_whatsapp/index.ts')), 'send_whatsapp: the template language must be the row\'s registered language');
ok(/n\.lang === 'ar'/.test(src(F + 'send_outbox/index.ts')), 'send_outbox: the email frame must follow notifications.lang');
for (const fn of ['login_otp', 'kyc', 'mobile_otp']) ok(/Locale: /.test(src(F + fn + '/index.ts')), `${fn}: the SMS / voice code must carry Locale`);
const rinv = src(F + 'reveal_invoice/index.ts');
// 21 Sep 2026: the invoice and receipt are both QuotesDone documents in either language; the registered one is the default.
ok(/registeredLocale\(admin, \{ role: 'customer'/.test(rinv) && !/lang: 'en'/.test(rinv), 'reveal_invoice: an unspecified language must come from the registered customer');
ok(/form\.set\('locale'/.test(src(F + 'stripe_checkout/index.ts')), 'stripe_checkout: the hosted page must be pinned to the registered language');
ok(/locale: lang === 'ar' \? 'ar' : 'en'/.test(src('src/components/me/RevealPayment.tsx')), 'RevealPayment: the Payment Element must take the portal language');
// Every customers insert is a registration and must record the language.
for (const fn of ['login_otp', 'kyc', 'mobile_otp', 'inquiry_intake']) {
  const lines = src(F + fn + '/index.ts').split('\n');
  lines.forEach((l, i) => {
    const call = l + (lines[i + 1] || '');   // inquiry_intake splits .from('customers') and .insert({..}) over two lines
    if (/from\('customers'\)\s*\.insert\(/.test(call.replace(/\s+/g, ' ')) && /from\('customers'\)/.test(l)) ok(/locale/.test(call), `${fn}: a customer is registered without a language: ${l.trim().slice(0, 90)}`);
  });
}
// 28 Oct 2026 (#1712, ledger 1401 audit S7): create_company's insert moved to supplier_api/create_company.ts, which takes
// the language from the door (SUPPLIER_LOCALE, the constant English). Both halves are asserted, so neither can drop it.
ok(/source: 'self_registered',\s*locale: deps\.locale,/.test(src(F + 'supplier_api/create_company.ts'))
  && /createCompany\(admin, email, body, \{[^}]*\blocale: SUPPLIER_LOCALE \}\)/.test(src(F + 'supplier_api/index.ts')), 'supplier_api create_company: a supplier is registered without a language');
const cp = src('src/components/me/CustomerPortal.tsx');
ok(!/getItem\('qd-lang'\)\) return/.test(cp), 'CustomerPortal: this device\'s stored language still overrides the registered one');
ok(/action: 'set_locale', locale: l/.test(cp), 'CustomerPortal: switching language while signed in must save customers.locale');
ok(/action: 'verify', user_kind: 'customer'[^}]*lang/.test(cp), 'CustomerPortal: sign-up must send the page language it registers');
const sp = src('src/components/portal/SupplierPortal.tsx');
// 21 Sep 2026: this assertion had been red on main since 3bb1bf5 (14 Sep), which deliberately replaced
// the reloading switchLang with adoptLocale (src/lib/documentLocale.ts) — the same path the customer
// portal uses. The behaviour stayed; the check still named the removed function. It now asserts the
// behaviour: the settings answer's locale is adopted, and switching while signed in saves leads.locale.
// 12 Oct 2026 (founder ruling 1008): suppliers are always English, so the supplier portal no longer
// adopts leads.locale or saves a language. scripts/checks/the_supplier_portal_is_always_english.test.mjs
// owns that rule; here we only assert the old behaviour has not come back.
ok(/const lang: string = 'en';/.test(sp) && !/adoptLocale|setLang/.test(sp), 'SupplierPortal: the supplier portal must render English only (ruling 1008)');

// THE FRAME AND THE TEMPLATE MUST AGREE ON THE FOOTER (22 Sep 2026, reviews of PR #857).
// DL-06 corrected the supplier footer in templates.email_supplier and in send_outbox/arabic_frame.ts,
// which translates the English footer words at send time. Those two are one sentence split across a
// stored template and a deployed function, and either half alone prints a wrong footer: the frame
// without the apply leaves an English licence line inside an Arabic mail, and the apply without the
// frame leaves the corrected English words untranslated. A bridge that recognised BOTH wordings was
// carried for one commit and then removed rather than left as dead code with nothing to remove it —
// so this asserts the pair in both directions, and fails while the two disagree.
{
  const frame = src(F + 'send_outbox/arabic_frame.ts');
  const bridged = /Dubai DET E-Trader Licence/.test(frame);
  if (TOKEN) {
    const r = await sql(`select count(*)::int n from public.templates where content like '%Dubai DET E-Trader Licence%'`);
    let live = null; try { live = JSON.parse(r.text)?.[0]?.n ?? null; } catch (_e) { /* reported below */ }
    ok(live !== null, 'arabic_frame bridge: could not read templates (HTTP ' + r.status + ')');
    if (live === 0) {
      ok(!bridged, 'arabic_frame.ts still carries the pre-DL-06 footer mapping, and no template holds that wording any more: delete the bridge');
      console.log('supplier footer: the template and arabic_frame.ts agree on DET Trader Licence No. 1633275 · TDRA NOL-26-100000665');
    } else {
      ok(bridged, `templates.email_supplier still carries the pre-DL-06 footer on ${live} row(s) while arabic_frame.ts translates only the corrected wording — an Arabic supplier mail would print an English licence line. APPLY: node scripts/apply_sql.mjs scripts/sql/the_licence_we_name_is_the_licence_we_hold.sql --apply  (and apply it BEFORE deploying send_outbox)`);
    }
  } else {
    NOT_VERIFIED.push('whether the arabic_frame.ts deploy-order bridge is still needed (reads templates)');
  }
}

if (fails.length) {
  console.error(`\nlanguage_follows_registration: ${fails.length} failure(s)`);
  for (const f of fails) console.error('  - ' + f);
  process.exit(1);
}
// NAMED, NEVER SILENT: a pass that could not measure everything says what it did not measure.
if (NOT_VERIFIED.length) {
  console.log(`\nlanguage_follows_registration: the source side passes; ${NOT_VERIFIED.length} part(s) NOT VERIFIED here:`);
  for (const n of NOT_VERIFIED) console.log('  - ' + n);
  console.log('  Run this file where a management token exists to assert them.');
} else {
  console.log('\nlanguage_follows_registration: every touchpoint speaks the registered language');
}

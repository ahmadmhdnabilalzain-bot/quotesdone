// scripts/e2e/stage2_coverage.mjs — the FEATURE INVENTORY the stage-2 sandbox run is scored against.
// Assigned: it_engineer (tooling), for sales_engineer and customer_support journeys. Ledger 1119.
//
// Founder, 6 Oct 2026: "not a single feature we have should be missed. everything needs to be tested."
// So the inventory is READ FROM THE CODE AND THE DATABASE on every run, never typed from memory:
//   route     every page.tsx / route.ts under src/app, once per locale for [locale] pages
//   tab       every customer portal nav id (PortalShell NAV_GROUPS) and supplier portal tab id
//   action    every edge function action (`action === 'x'`), or the function itself if it has none
//   notice    every notification type written by the functions, plus every type seen in 365 days
//   duty      every cron_registry job in a category that touches a customer, supplier, inquiry,
//             quote or payment
// Each item is then classed by the rules below as TESTED (a scenario step asserts its real effect),
// JUSTIFIED (a written reason it cannot run in the sandbox) or UNCOVERED. UNCOVERED is reported as
// such — a gap is a finding, never rounded into a percentage that reads as done.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

const walk = (dir, out = []) => {
  if (!existsSync(dir)) return out;
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
};
const uniq = (a) => [...new Set(a)].sort();

// Duty categories that reach a customer, supplier, inquiry, quote or payment (cron_registry.category,
// compared lower-case). Governance, knowledge, backup, security and the like run on the company itself.
export const CUSTOMER_FACING_DUTY = ['operations', 'marketplace', 'supplier growth', 'finance', 'messaging',
  'demand', 'supply', 'marketing', 'growth', 'trust_and_safety'];

export async function buildInventory(repo, read) {
  const items = [];
  const add = (kind, id, src) => items.push({ kind, id, src });

  // routes
  const app = join(repo, 'src', 'app');
  for (const f of walk(app).filter((f) => /[\\/](page|route)\.tsx?$/.test(f))) {
    const rel = f.slice(app.length).replace(/\\/g, '/').replace(/\/(page|route)\.tsx?$/, '') || '/';
    if (rel.startsWith('/[locale]')) for (const l of ['en', 'ar']) add('route', `${l === 'ar' ? '/ar' : ''}${rel.replace('/[locale]', '') || '/'}`, f);
    else add('route', rel, f);
  }
  // portal tabs
  const shell = readFileSync(join(repo, 'src/components/me/PortalShell.tsx'), 'utf8');
  for (const m of shell.matchAll(/\{ id: '([a-z_]+)',\s+icon:/g)) add('tab', `customer:${m[1]}`, 'PortalShell.tsx');
  const sp = walk(join(repo, 'src/components/portal')).filter((f) => /\.tsx$/.test(f)).map((f) => readFileSync(f, 'utf8')).join('\n');
  for (const id of uniq([...sp.matchAll(/(?:(?:tab|view|section) === |set(?:Tab|View|Section)\()'([a-z_]+)'/g)].map((m) => m[1]))) add('tab', `supplier:${id}`, 'src/components/portal');
  // edge function actions
  const fns = join(repo, 'supabase', 'functions');
  for (const fn of readdirSync(fns).filter((n) => !n.startsWith('_') && existsSync(join(fns, n, 'index.ts')))) {
    const src = readFileSync(join(fns, fn, 'index.ts'), 'utf8');
    const acts = uniq([...src.matchAll(/\b(?:action|act|op) === '([a-z_]+)'/g)].map((m) => m[1]));
    if (acts.length) acts.forEach((a) => add('action', `${fn}.${a}`, fn)); else add('action', fn, fn);
  }
  // notification types
  const fnSrc = walk(fns).filter((f) => f.endsWith('.ts')).map((f) => readFileSync(f, 'utf8')).join('\n');
  // Only a `type: 'x'` written near a notifications insert or a notify call is a notice type; the same
  // shape also names JSON-schema types and product attributes (smoke_detector, json_object), which are not.
  const codeTypes = [...fnSrc.matchAll(/\btype:\s*'([a-z_]+)'/g)]
    .filter((m) => /notifications|notify|outbox/.test(fnSrc.slice(Math.max(0, m.index - 300), m.index))).map((m) => m[1]);
  const dbTypes = (await read(`select distinct type from public.notifications where created_at > now() - interval '365 days' and type is not null`)).map((r) => r.type);
  for (const t of uniq([...codeTypes, ...dbTypes])) add('notice', t, 'notifications');
  // seat duties
  const duties = await read(`select jobname, lower(category) category, purpose from public.cron_registry order by jobname`);
  for (const d of duties.filter((d) => CUSTOMER_FACING_DUTY.includes(d.category))) add('duty', d.jobname, d.category);
  return items;
}

// ---- classification -------------------------------------------------------------------------
// TESTED: [kind, regex on id, scenario key]. A rule only lands here when that scenario's step asserts
// a row, a status, a stored object or a rendered body — never a bare HTTP 200.
export const TESTED = [
  ['route', /.*/, 'S16'],                                   // every page, EN and AR: 200, rendered, no console error
  ['tab', /.*/, 'S16'],                                     // every portal tab opened and settled, both portals
  ['action', /^kyc\.|^login_otp|^mobile_otp/, 'S03'],
  ['action', /^supplier_api\.(claim|create_company|save_profile|accept_terms|services_|capability_|me$|settings|save_settings|set_availability)/, 'S01'],
  ['action', /^supplier_api\.process_docs|^license_extract|^doc_extract/, 'S02'],
  ['action', /^inquiry_intake|^customer_api\.(create_inquiry|missing_specs|add_missing_specs|edit_inquiry|complete_inquiry|trades|me$|my_inquiries|set_locale|preferences|save_preferences|activity)/, 'S04'],
  ['action', /^customer_api\.(analyze_drawing|analyze_document|analyze_boq|cad_read_status|brief_pdf)|^drawing_|^cad_convert|^extract_text|^pdf_native/, 'S05'],
  ['action', /^rfq_flag|^procurement_api|^sales_engineer/, 'S06'],
  ['action', /^supplier_api\.(inbox|inquiry_pdf|inquiry_documents|submit_quote|extract_quote|quote_pdf|spec_|projects|search)|^quote_extract/, 'S07'],
  ['action', /^customer_api\.(compare_pdf|compare_csv|quote_pdf|spec_offer_reply|rfq_note|concierge|discover|supplier_history)|^quote_compare/, 'S09'],
  ['action', /^stripe_checkout|^stripe_confirm|^stripe_webhook|^customer_api\.reveal|^reveal_invoice|^customer_documents/, 'S10'],
  ['action', /^customer_api\.(request_refund|cancel_inquiry)|^refund_flow|^refunds_api|^accountant/, 'S11'],
  ['action', /^supplier_ack|^supplier_api\.(ack_contact|receipts|receipt_pdf|dispute_charge)/, 'S12'],
  ['action', /^site_assistant|^messages_api|^customer_portal|^supplier_portal/, 'S13'],
  ['action', /^unsubscribe|^contact_submit|^complaint_status|^claim_lookup|^public_site|^customer_api\.rate_supplier|^supplier_api\.support_rating/, 'S14'],
  ['action', /^send_outbox|^send_whatsapp|^send_sms|^customer_followup/, 'S15'],
  ['action', /^marketing(\.|$)|^marketing_outreach/, 'S17'],
  ['notice', /^(new_quote|quote_accepted|reveal_receipt|invoice_ready|new_message|clarification_requested|spec_offer_offer|rfq_addendum|registration_received|quote_coaching|duty_activation_first_request|inbound_reply)$/, 'S15'],
  ['notice', /^(login_otp|magiclink)$/, 'S03'],
  ['notice', /^(new_inquiry|rfq_no_supplier)$/, 'S06'],
  ['notice', /^(quote_received|job_awarded_other|spec_offer_accepted|clarification_answered|supplier_ack|supplier_registered|doc_received|supplier_doc_applied)$/, 'S15'],
  ['notice', /^(support_reply|contact_message)$/, 'S14'],
  ['notice', /^marketing_/, 'S17'],
  ['action', /^project_api\./, 'S04'],
];

// JUSTIFIED: [kind, regex, reason]. Each reason names what WOULD be touched and why the sandbox may not.
export const JUSTIFIED = [
  ['action', /^marketing_social_connect|^marketing_social_inbox|^oauth_connect|^marketing_channels/, 'Connects or reads a real Meta/Google account. The founder forbids posting to Meta; S17 renders the social plan to the Desktop folder instead.'],
  ['action', /^wa_template_setup|^wa_templates_watch|^wa_status/, 'Registers templates with Meta or reads Meta delivery receipts for real numbers. A fixture number never reaches Meta (code fixture_number); the rendered body is asserted in S15.'],
  ['action', /^wa_inbound|^sms_inbound|^resend_inbound|^inbound_email|^resend_webhook|^email_triage/, 'Needs a provider-signed webhook from Meta, Twilio or Resend. A forged signature is refused by design; the parser is covered by the static checks named in docs/e2e.md.'],
  ['action', /^supplier_api\.pay_registration/, 'Charges a supplier registration fee. Suppliers register free under the current offer, so a demo run does not take this payment path.'],
  ['notice', /^(expense_logged|wa_templates_ready)$/, 'Internal notice to the accountant or the founder (company spend, Meta template approval); no customer or supplier receives it.'],
  ['action', /^voice_otp|^voice_otp_capture|^transcribe|^supplier_api\.transcribe_service_note/, 'Places a real phone call or needs recorded audio from one.'],
  ['action', /^stripe_setup|^stripe_setup_page|^supplier_pay/, 'Creates live Stripe Connect / subscription objects on the company account; stage 2 stays on Stripe TEST checkout only.'],
  ['action', /^backup|^dropbox_backup|^compliance_archive|^conversation_archive/, 'Writes company-wide archives to Dropbox and storage; running it for demo traffic would archive real rows too.'],
  ['action', /^ai_gateway|^embed_ml|^resilience_ping|^site_error_ingest|^role_guard|^sanctions_screen|^it_engineer|^ceo_agent|^email_cron|^customer_intelligence|^supplier_onboard|^supplier_catalog_ingest/, 'Infrastructure or a seat runtime with no customer-facing action of its own; every route through it is measured in ai_cost_log by the scenarios that call it (model route asserted per step).'],
  ['notice', /^(founder_alert|founder_brief|board_report|it_engineer_handover|accountant_spend_report|accountant_weekly_report|delivery_feedback_canary)$/, 'Goes to the founder or a seat, not to a customer or supplier; a demo run must never page the founder (rehearsal window).'],
  ['notice', /^supplier_(campaign|invite)/, 'Supplier campaign to the real leads pool; the composer is covered by the_supplier_campaign_honours_unsubscribe and S14 asserts the unsubscribe effect.'],
  ['duty', /.*/, 'Scheduled duties act on every row in production. Firing one from the harness would act on real customers and suppliers too. Their demo-row effects are proved by the aborted-transaction duty probes in scripts/checks (stage 1 §6).'],
];

export function classify(items) {
  return items.map((it) => {
    const t = TESTED.find(([k, re]) => k === it.kind && re.test(it.id));
    if (t) return { ...it, status: 'tested', scenario: t[2] };
    const j = JUSTIFIED.find(([k, re]) => k === it.kind && re.test(it.id));
    if (j) return { ...it, status: 'justified', reason: j[2] };
    return { ...it, status: 'uncovered' };
  });
}

export function summarise(classified) {
  const by = (k) => classified.filter((c) => c.status === k).length;
  const kinds = uniq(classified.map((c) => c.kind));
  return {
    total: classified.length, tested: by('tested'), justified: by('justified'), uncovered: by('uncovered'),
    pct_tested_or_justified: classified.length ? Math.round(1000 * (by('tested') + by('justified')) / classified.length) / 10 : 0,
    by_kind: Object.fromEntries(kinds.map((k) => {
      const c = classified.filter((x) => x.kind === k);
      return [k, { total: c.length, tested: c.filter((x) => x.status === 'tested').length,
        justified: c.filter((x) => x.status === 'justified').length, uncovered: c.filter((x) => x.status === 'uncovered').length }];
    })),
  };
}

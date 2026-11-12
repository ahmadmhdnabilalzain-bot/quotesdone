// THE BUSINESS AREAS OF THE DATABASE, AND THE RULE THAT PUTS EACH ROUTINE AND TABLE IN ONE (it_engineer, 10 Nov 2026).
//
// The founder, 10 Sep 2026 and again 10 Nov: the code must read as though a real software engineer built it, because
// he will hand it to an external auditor. Measured 10 Nov 2026: production runs 2,077 routine names (2,082 with
// overloads) and 793 tables, all in one schema, `public`, with no grouping an outsider can see. This file is the
// grouping. scripts/architecture/database_map.mjs applies it and writes docs/architecture/database/, one page per area.
//
// HOW A NAME IS PLACED, first match wins:
//   1. OVERRIDES: a name placed by hand, because its words point somewhere it does not belong;
//   2. an area's PREFIX: a name that starts with a seat's or a subsystem's own prefix belongs to it whatever else it
//      says (`accountant_book_stripe_fees` is the accountant's bookkeeping, not a payment flow);
//   3. the area RULES, in the order of AREAS below. Each rule is a regular expression tested against the name with
//      its `fn_`, `trg_` or `_` prefix removed. Earlier areas are the narrower ones (payments before customers, so
//      `customer_refund` is a payment), and the seat areas come last (so `ceo_refund_*` is a payment too, while a
//      `ceo_*` routine about nothing else is the CEO seat's own machinery).
// A name no rule places is UNMAPPED, and scripts/checks/the_database_map_is_complete_and_current.test.mjs fails on it.
// There is deliberately no catch-all: a catch-all area would hold whatever nobody looked at, which is the state this
// replaces. A new routine is placed by naming it well (most are, by the words already here) or by an OVERRIDE line.
//
// What a rule here decides is WHERE A READER LOOKS, not who owns the routine at run time. Ownership at run time is
// recorded in the database (function_owner, writer_seat, seat_duty) and the map prints it where the repository
// records it (cron jobs). Moving a routine between areas changes a page, never behaviour.

/** Strip the conventional prefixes (routine, trigger, view), so a rule tests the words. */
export const words = (name) => name.replace(/^(fn_|trg_|tg_|v_|_+)/, '');

export const AREAS = [
  {
    slug: 'quotes-reveal-payments',
    title: 'Quotes, reveal and payments',
    about: 'A supplier\'s quotation, the comparison, the customer paying to reveal a supplier, refunds, Stripe, purchase orders.',
    prefix: /^(refunds?|reveal|quotes?|stripe|po|price|pricing)(_|$)/,
    rules: [/quote|quotation|reveal|refund|stripe|payment|checkout|payout|(^|_)po(_|$)|purchase_order|comparison|compare|margin|(^|_)pric(e|ing)|(^|_)fee(_|$)|charge|dispute/],
  },
  {
    slug: 'matching',
    title: 'Matching',
    about: 'Deciding which suppliers see an inquiry: trades, categories of work, the RFQ, the shortlist, demand.',
    prefix: /^(match|matching|rfq|trade|demand|service_alias|services)(_|$)/,
    rules: [/(^|_)match|(^|_)rfq|shortlist|recommend|(^|_)trades?(_|$)|supply_gap|demand|service_alias|(^|_)services?(_|$)|service_implication/],
  },
  {
    slug: 'messaging',
    title: 'Messaging, outbox and WhatsApp',
    about: 'Everything that tells a person something: the outbox, email, WhatsApp, SMS, notifications, consent, unsubscribe.',
    prefix: /^(wa|whatsapp|twilio|outbox|notifications?|notify|mail|email|sms|otp|conversation|m365|delivery|inbound|unsubscribe|suppression)(_|$)/,
    rules: [/whatsapp|(^|_)wa(_|$)|twilio|outbox|email|mail|inbox|notif|notify|(^|_)sms|unsubscribe|suppression|deliverab|delivery|conversation|message|(^|_)otp|glockapps|consent|opt_?in|opt_out|(^|_)channel|phone|bounce|template|plain_language|(^|_)chat_|dead_letter|machine_sender|mobile/],
  },
  {
    slug: 'suppliers-registration',
    title: 'Suppliers and registration',
    about: 'The supplier pool: leads, invitations, sign-up, licences, sanctions screening, documents, the catalogue, ratings.',
    prefix: /^(suppliers?|invite|leads?|signup|sales|sanctions|screening|licence|registered|reg|crm|opportunity|expiring|business_entity)(_|$)/,
    rules: [/supplier|(^|_)leads?(_|$)|invite|invitation|signup|sign_up|registration|register|licen[cs]e|sanction|screening|onboard|catalog|vendor|disposable|agreement|yello|scrape|sourcing|acquisition|founding_rank/],
  },
  {
    slug: 'customers-inquiries',
    title: 'Customers and inquiries',
    about: 'The customer side: accounts, the inquiry and its intake, specifications, drawings, complaints, support cases.',
    prefix: /^(customers?|inquiry|inquiries|complaint|cs|support|spec|boq|cad|doc|document)(_|$)/,
    rules: [/customer|inquir|intake|(^|_)spec(_|s_|$)|boq|drawing|(^|_)cad(_|$)|(^|_)project|complaint|(^|_)cs(_|$)|support|csat|review_request|banned|stalled|concierge|site_visit|ticket|document|attachment|artifact|contact|feedback|field_definition|(^|_)scope_|procurement|(^|_)reviews$|questions|assistant_logs|docver|job_no/],
  },
  {
    slug: 'accounting',
    title: 'Accounting',
    about: 'The accountant seat: the ledger, bank lines, expenses, receipts, invoices, VAT, budgets, month close, cash, AI and ad spend.',
    prefix: /^(accountant|gl|expense|vat|bank|finance|ap|ar|budget|fraud|transaction)(_|$)/,
    rules: [/ledger|(^|_)gl(_|$)|bank|expense|(^|_)vat(_|$)|budget|month_close|cash|revenue|finance|spend|collections|(^|_)tax(_|$)|aging|(^|_)usd|cost|subscription|money|fraud|transaction|invoice|receipt|bookkeep|openrouter|dues/],
  },
  {
    slug: 'marketing',
    title: 'Marketing',
    about: 'The marketing seat: campaigns, content, the blog, social, ads, SEO, competitors, the public pages.',
    prefix: /^(marketing|campaign|blog|social|ads?|seo|competitor|content|pages|ambition|public_site)(_|$)/,
    rules: [/campaign|content|blog|social|(^|_)ads?(_|$)|seo(_|$)|competitor|brand|(^|_)pages?(_|$)|published|promotional|funnel|audience|article|ambition|(^|_)targets?(_|$)|market_intel|competitive|meta_insights|outreach|public_worked_case/],
  },
  {
    slug: 'knowledge',
    title: 'Knowledge',
    about: 'What the machine knows: the knowledge base, embeddings, lessons, FAQs, taxonomy, categories, Arabic text, case memory.',
    prefix: /^(kb|kn|knowledge|lesson|faq|taxonomy|arabic|ml|case|category|norm|text|legal)(_|$)/,
    rules: [/(^|_)kb(_|$)|knowledge|lesson|faq|embed|vector|taxonomy|glossary|arabic|normali[sz]e|recall|corpus|categor|case_memory|(^|_)ml(_|$)|learn|exam|playbook|(^|_)mep|regulation|(^|_)legal|(^|_)memory|graph_|canon_eval|compliance_sources|materials|(^|_)mdm_|quality_standard/],
  },
  {
    slug: 'it-ops-monitoring',
    title: 'IT, operations and monitoring',
    about: 'The IT seat and the platform: backups, privacy (PDPL), security, resilience, the scheduler, schema, demo data, rehearsals, incidents.',
    prefix: /^(it|backup|dropbox|dbx|pdpl|security|resilience|os|demo|rehearsal|table|cron|mask|scrub|auth|internal|workflow|qd|rl|e2e)(_|$)|^(a0\d|z55|zzz)_/,
    rules: [/(^|_)it(_|$)|backup|dropbox|(^|_)dbx|pdpl|security|resilien|(^|_)cron|schema|(^|_)tables?(_|$)|demo|rehearsal|e2e|smoke|alarm|health|kernel|(^|_)routine|version|(^|_)mask|scrub|audit|incident|finding|runner|heartbeat|workflow|vercel|rate_limit|login|(^|_)undo|retention|purge|unfinished|watch|game_day|identity|anonym|uptime|degraded|holiday|working_day|secret|credential|alert|(^|_)entity_|mfa|control_mode|ui_label|file_scan|file_is|deploy|continuity|critical_capability|integration_matrix|operating_system|owning_os|query_platform|phase1|red_episode|removed_trigger|qa_results|vt_results|edge_expectation|blocked_domains|jsonb|trim_at_word|remediation|(^|_)twin$|quarantine|(^|_)tests?(_|$)|test_matrix/],
  },
  {
    slug: 'seats-agents-duties',
    title: 'Seats, agents and duties',
    about: 'The six seats and how they work: the CEO\'s decisions, tasks, handoffs, duties, reasoning and judgement, the model gateway, the workspace readers.',
    prefix: /^(ceo|seat|org|agent|agents|founder|ws|reason|dept|department|ea|llm|ai|model|handoff|judgement|task|action|duty|employee|autonomy|goal|kpi|governance|high_stakes|reask|role|outcome|ops|decision|declog|prompt|step|scenario|p2c1)(_|$)/,
    rules: [/seat|ceo|(^|_)org(_|$)|agent|department|founder|(^|_)ws(_|$)|reason|judgement|handoff|decision|declog|(^|_)tasks?(_|$)|action|dut(y|ies)|employee|autonomy|(^|_)ea(_|$)|goal|kpi|governance|llm|(^|_)ai(_|$)|(^|_)model|prompt|deliberation|authority|delegat|approval|improvement|experiment|challenge|(^|_)roles?(_|$)|originator|executor|execution|(^|_)hold|held|reask|policy|step_run|strategy|reputation|seniority|scenario|outcome|gateway|priority|training|report|(^|_)rules?(_|$)|(^|_)event|emit|review|(^|_)board_|(^|_)decide$|escalat|tool_call|paid_route|web_search|what_if|(^|_)eval_|gate_state|allocation|evolution|function_owner|(^|_)idea$|metric|resource_pool|simulations|skills_matrix|vision|route_party|marketplace_analytics|workstream|scorecard|(^|_)resource|(^|_)company(_|$)/],
  },
];

// A name placed by hand, with the reason its words mislead. Keep this short; most names are placed by the rules.
export const OVERRIDES = {
  // the break-even ledger's fixed inputs (founder's spend to date, the target date): its words name no area
  break_even_basis: 'accounting',
  // the matching engine's supplier-side reads: their `supplier_` prefix would file them with registration
  fn_supplier_product_match: 'matching',
  fn_supplier_portfolio_match_reads_ticks: 'matching',
  fn_supplier_portfolio_gaps: 'matching',
  fn_supplier_trade: 'matching',
  fn_supplier_target_by_trade_emirate: 'matching',
  fn_is_matchable: 'matching',
  // words that say nothing about the subject
  fn_language_mismatch: 'messaging',            // a reply written in a language other than the conversation's
  fn_notice_without_a_route_sweep: 'messaging', // a notice with no route to its person says why ("notice" is not one of the area's words)
  fn_reconcile_doc_blocks: 'customers-inquiries',
  fn_company_name_norm: 'suppliers-registration', // normalises a supplier company's trading name
  trg_terms_pins_sync: 'suppliers-registration', // the agreement terms a supplier signs
  inv_items: 'customers-inquiries',
  opportunity: 'suppliers-registration',
  supply_recruitment_brief: 'suppliers-registration',
  // edge functions (supabase/functions/<name>) whose name does not say their subject; each from its own header
  claim_lookup: 'suppliers-registration',       // "is this your company?" for the supplier claim flow
  compliance_archive: 'customers-inquiries',    // signed terms certificates and the customer register
  extract_text: 'knowledge',                    // reads an attachment's text through ai_gateway
  kyc: 'customers-inquiries',                   // account completion: mobile, email, date of birth, signed terms
  oauth_connect: 'it-ops-monitoring',           // the founder grants provider consents
  pdf_native: 'customers-inquiries',            // renders the platform's PDF documents
  public_site: 'marketing',                     // the no-sign-in endpoints behind the public website
  resend_inbound: 'messaging',                  // inbound email
  resend_webhook: 'messaging',                  // delivery events: bounces and complaints
  site_assistant: 'marketing',                  // the public website's assistant
  site_error_ingest: 'it-ops-monitoring',       // the website's runtime errors
  transcribe: 'knowledge',                      // speech to text
  supplier_pay: 'quotes-reveal-payments',       // a supplier settles what it owes, by Stripe
};

/** The area slug for a routine or table name, or null when nothing places it. */
export function areaOf(name) {
  if (Object.hasOwn(OVERRIDES, name)) return OVERRIDES[name];
  const w = words(name);
  for (const a of AREAS) if (a.prefix.test(w)) return a.slug;
  for (const a of AREAS) if (a.rules.some((re) => re.test(w))) return a.slug;
  return null;
}

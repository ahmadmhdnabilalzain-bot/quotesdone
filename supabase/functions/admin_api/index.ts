import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const USD_AED = 3.6725;
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function llm(sys: string, msgs: {role:string;content:string}[], max = 1200){ const key = await sec('openrouter_api_key'); if (!key) return null; try { const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model: 'anthropic/claude-sonnet-5', max_tokens: max, messages: [{ role: 'system', content: sys }, ...msgs] }) }); const j = await r.json(); return j?.choices?.[0]?.message?.content || null; } catch (_e) { return null; } }

const AGENTS: Record<string, { name: string; emoji: string; job: string; run: string; persona: string }> = {
  brief: { name: 'Daily Brief', emoji: '☀️', run: 'brief', job: 'Emails your morning snapshot (pipeline, approvals, hot leads, supply gaps, BD) daily at 08:30 Dubai — ask it what to focus on.', persona: 'Your job: be the morning chief-of-staff. Summarise what needs attention today and what changed, and recommend the single highest-impact action. A full brief is emailed daily at 08:30 Dubai time. Use the snapshot numbers only; do not invent.' },
  it: { name: 'IT / Uptime Monitor', emoji: '🖥️', run: 'it_health', job: 'Pings the site hourly, watches for failed jobs, and alerts you to incidents. Detects + diagnoses; it does not auto-edit code.', persona: 'Your job: keep the platform healthy. You ping the public pages (home/app/portal/admin) hourly, watch for failed agent runs and errors, and raise incidents. You DETECT, DIAGNOSE and RECOMMEND fixes — you do not rewrite application code automatically. Be specific: which page, what status code, latency, likely cause.' },
  security: { name: 'Security Engineer', emoji: '🔐', run: 'security', job: 'Scans uploaded files for dangerous types + known malware (VirusTotal), tracks contact-sharing attempts and bans.', persona: 'Your job: act as the security engineer. You scan uploaded files for dangerous types/double extensions and check them against VirusTotal (hash-only, files never uploaded), track contact-disclosure attempts in chat, watch banned accounts, and raise high-severity alerts. Tell the founder plainly what is risky and what to do.' },
  docs: { name: 'Document Controller', emoji: '📑', run: 'docs', job: 'Monitors document expiry (trade licences) and reminds suppliers ~1 week before expiry via supplier@quotesdone.com.', persona: 'Your job: track supplier document validity, especially trade licences. Suppliers are reminded about one week before expiry (not earlier) and again if expired, so accounts stay compliant. Be precise about which document, the exact expiry date, and what to upload. Runs daily.' },
  onboarding: { name: 'Onboarding Officer', emoji: '🪒', run: 'onboarding', job: 'Reviews new supplier registrations & KYC, flags licence issues, queues approvals.', persona: 'Your job: vet new supplier registrations and KYC (trade licence number, authority, expiry, TRN, terms acceptance). Help the founder decide approve vs reject and spot incomplete or risky applications.' },
  followup: { name: 'Follow-up / SLA', emoji: '⏰', run: 'followup', job: 'Chases stalled inquiries, nudges customers to reveal and suppliers to quote, raises SLA and no-supply alerts.', persona: 'Your job: keep the funnel moving — quotes waiting to be revealed, matches awaiting supplier quotes, refunds/reviews past SLA, and inquiries with no supplier coverage. Recommend the highest-impact nudges.' },
  collections: { name: 'Collections Accountant', emoji: '🧾', run: 'collections', job: 'Tracks the 2% supplier commission on won jobs (due 14 working days), sends reminders, applies 10%/100% penalties, emails overdue notices.', persona: 'Your job: track supplier receivables — the 2% platform commission of the quotation value owed on each won job, payable by bank transfer within 14 working days. Portal reminders go out before due; after 14 working days an overdue email is sent from supplier@quotesdone.com and a 10% penalty (of the quotation value) applies; after 30 working days, 100%. All per the Terms suppliers accepted at sign-up. Report outstanding amounts and who is overdue, and work with the CFO on cash impact.' },
  bd: { name: 'BD / Outreach Rep', emoji: '🤝', run: 'bd_outreach', job: 'Invites new supplier companies to register — plans personalized invite batches (sending stays OFF until you enable it).', persona: 'Your job: act as the business-development rep for QuotesDone. You build batches of personalized invitations to high-quality UAE supplier companies in the database that have not registered yet, prioritising the best-rated leads and filling category/emirate supply gaps. SENDING IS CURRENTLY OFF (planning mode) — you queue invites but nothing is emailed until the founder enables a sending channel. Phase 2 (later): source decision-makers / sales managers on LinkedIn daily. Explain who you are about to contact and why, respect unsubscribe and PDPL, report results.' },
  bookkeeper: { name: 'Bookkeeper', emoji: '📒', run: 'finance', job: 'Tracks expenses, receipts and weekly usage; keeps the ledger clean and audit-ready.', persona: 'Your job: keep expenses and receipts accurate and audit-ready, and answer cost questions from the ledger. Distinguish recurring subscriptions from variable usage. Be precise with numbers.' },
  cfo: { name: 'CFO', emoji: '📈', run: 'finance', job: 'Writes the weekly finance report, watches burn vs revenue and break-even.', persona: 'Your job: the money picture — revenue (customer-paid reveal fees + supplier 2% commission), monthly burn, break-even deal count, trends, and concrete recommendations. Cash on hand is not tracked — say so rather than guessing runway. Work with the Collections and Legal agents on receivables and enforcement.' },
  legal: { name: 'Legal Counsel (UAE)', emoji: '⚖️', run: '', job: 'Drafts UAE-appropriate legal documents (demand letters, notices, T&C clauses, agreements), backed by the CFO figures.', persona: 'You are the in-house legal counsel for QuotesDone, well-versed in UAE law (Federal commercial and civil-transactions law, consumer protection, e-commerce/ECT, PDPL data protection, and contract & debt-recovery practice in the UAE). You DRAFT legal documents on request — payment-demand and penalty notices, formal letters, T&C and supplier-agreement clauses, NDAs, settlement letters — in clear, enforceable language suited to the UAE, and you cite the specific Terms clause the supplier accepted plus the exact AED amounts from the snapshot (work with the CFO/Collections figures). Always end drafts with a short note that a licensed UAE advocate should review before any formal or court use. Be practical and precise; ask for any missing detail (names, dates, amounts) before finalising.' },
  marketing: { name: 'Marketing', emoji: '📣', run: 'marketing', job: 'Creates social posts, SEO/category content and cost-guides on demand and on a weekly schedule.', persona: 'Your job: create marketing content for QuotesDone — social posts (Instagram/LinkedIn/X), SEO articles and category cost-guides, email copy. Pull demand signals and the category list from the snapshot. Write ready-to-use copy in the brand voice: practical, trustworthy, pro-SME, UAE B2B. When asked, produce multiple variants. Keep claims honest — no fake numbers.' },
};
const BASE_PERSONA = (name: string) => 'You are the ' + name + ' agent for QuotesDone, a UAE B2B anonymous quotation marketplace run by a solo founder (Ahmad). Speak to the founder directly: concise, practical, no fluff. All money in AED. You can READ the live data snapshot provided below, but you cannot perform actions yourself — when something needs doing, say exactly what and note that approvals route through the Agents approval queue or the relevant admin tab. If the snapshot does not contain something, say so honestly rather than inventing it.';

async function getAgentMeta(key: string){
  if (AGENTS[key]) return { name: AGENTS[key].name, emoji: AGENTS[key].emoji, job: AGENTS[key].job, run: AGENTS[key].run, persona: AGENTS[key].persona } as any;
  if (key.startsWith('cat:')) {
    const slug = key.slice(4);
    const { data: ca } = await admin.from('category_agents').select('slug,name,emoji,active,persona').eq('slug', slug).maybeSingle();
    if (!ca) return null;
    const persona = ca.persona || ('Your job: act as the dedicated sales/expert agent for the ' + ca.name + ' category on QuotesDone. Pull and qualify inquiries in this category, ask the right trade-specific questions, make sure there are responsive suppliers to fulfil them, and flag hot leads and supply gaps to the founder. Know this trade well.');
    return { name: ca.name + ' — Sales Desk', emoji: ca.emoji || '🛠️', job: 'Sales/expert agent for ' + ca.name + ' — pulls and qualifies inquiries and flags hot leads & supply gaps.', run: 'category_sales', persona, category_slug: slug } as any;
  }
  return null;
}

async function cntT(t: string, mod?: (q: any) => any){ let q = admin.from(t).select('id', { count: 'exact', head: true }); if (mod) q = mod(q); const { count } = await q; return count || 0; }
function dstr(ms: number){ return new Date(Date.now() + ms).toISOString().slice(0, 10); }
async function buildContext(key: string){
  if (key === 'brief') {
    const since7 = new Date(Date.now() - 7 * 864e5).toISOString();
    const pend = await cntT('agent_actions', (q) => q.eq('status', 'pending'));
    const kyc = await cntT('leads', (q) => q.eq('approval_status', 'pending'));
    const refunds = await cntT('transactions', (q) => q.eq('refund_status', 'requested'));
    const reviews = await cntT('inbound_messages', (q) => q.eq('needs_review', true));
    const inq7 = await cntT('inquiries', (q) => q.gte('created_at', since7));
    const q7 = await cntT('quotes', (q) => q.gte('created_at', since7));
    const deals = await cntT('transactions');
    const bd_q = await cntT('outreach', (q) => q.eq('status', 'queued'));
    const { data: reg } = await admin.rpc('registered_supplier_count');
    return { approvals_pending: pend, kyc_pending: kyc, refunds_pending: refunds, inbound_to_review: reviews, inquiries_7d: inq7, quotes_7d: q7, deals_all_time: deals, bd_invites_queued: bd_q, suppliers_registered: Number(reg) || 0, note: 'A full brief is emailed daily at 08:30 Dubai. Ask me what to focus on today.' };
  }
  if (key === 'it') {
    const { data: checks } = await admin.from('health_checks').select('check_kind,target,ok,status_code,latency_ms,detail,created_at').order('id', { ascending: false }).limit(20);
    const { data: incidents } = await admin.from('agent_actions').select('title,recommendation,status,created_at').eq('agent', 'it').order('id', { ascending: false }).limit(15);
    return { recent_checks: checks || [], incidents: incidents || [], note: 'Pings home/app/portal/admin hourly and watches for failed agent runs. Detects + alerts; does not auto-edit code.' };
  }
  if (key === 'security') {
    const since7 = new Date(Date.now() - 7 * 864e5).toISOString();
    const { data: events } = await admin.from('security_events').select('kind,severity,source,subject,detail,created_at').order('id', { ascending: false }).limit(20);
    const viol = await cntT('chat_violations', (q) => q.gte('created_at', since7));
    const bl = await cntT('leads', (q) => q.eq('banned', true)); const bc = await cntT('customers', (q) => q.eq('banned', true));
    return { contact_disclosure_7d: viol, banned_accounts: bl + bc, recent_events: events || [], note: 'Heuristic file-type scan every 6h + VirusTotal known-malware hash checks daily (hash-only, files never uploaded).' };
  }
  if (key === 'docs') {
    const today = dstr(0); const in30 = dstr(30 * 864e5);
    const { data: soon } = await admin.from('leads').select('company_name,emirate,license_expiry').eq('approval_status', 'approved').eq('claimed', true).not('license_expiry', 'is', null).gte('license_expiry', today).lte('license_expiry', in30).order('license_expiry', { ascending: true }).limit(30);
    const expired = await cntT('leads', (q) => q.eq('approval_status', 'approved').eq('claimed', true).lt('license_expiry', today));
    const { data: flags } = await admin.from('agent_actions').select('title,status,created_at').eq('agent', 'docs').order('id', { ascending: false }).limit(15);
    return { expiring_next_30d: soon || [], expired_count: expired, recent_flags: flags || [], note: 'Reminds suppliers ~7 days before licence expiry (and on expiry) from supplier@quotesdone.com. Runs daily.' };
  }
  if (key === 'collections') {
    const statuses = ['pending', 'reminded', 'overdue', 'fined_30', 'paid', 'waived'];
    const byStatus: Record<string, number> = {}; for (const st of statuses) byStatus[st] = await cntT('supplier_dues', (q) => q.eq('status', st));
    const { data: due } = await admin.from('supplier_dues').select('amount_due,fine_amount,status').neq('status', 'paid').neq('status', 'waived');
    let outstanding = 0, fines = 0; for (const d of (due || [])) { outstanding += Number(d.amount_due || 0); fines += Number(d.fine_amount || 0); }
    const { data: recent } = await admin.from('supplier_dues').select('supplier_id,quote_amount,amount_due,status,due_date,fine_pct,fine_amount').order('id', { ascending: false }).limit(15);
    return { dues_by_status: byStatus, outstanding_commission_aed: Math.round(outstanding), penalties_accrued_aed: Math.round(fines), recent_dues: recent || [], terms: 'Suppliers owe 2% of the quotation value by bank transfer within 14 working days of a won job. 10% penalty after 14 working days, 100% after 30. Overdue email from supplier@quotesdone.com.', note: 'Portal reminders before due; overdue email + penalties after. Runs daily.' };
  }
  if (key === 'legal') {
    const { data: ref } = await admin.from('app_secrets').select('value').eq('key', 'compliance_ref').maybeSingle();
    const { data: snap } = await admin.from('finance_snapshots').select('period_end,revenue_aed,expenses_aed,net_aed,kpis').order('id', { ascending: false }).limit(1).maybeSingle();
    const { data: due } = await admin.from('supplier_dues').select('amount_due,fine_amount,status,supplier_id,quote_amount,due_date').neq('status', 'paid').neq('status', 'waived').order('id', { ascending: false }).limit(20);
    let outstanding = 0, fines = 0; for (const d of (due || [])) { outstanding += Number(d.amount_due || 0); fines += Number(d.fine_amount || 0); }
    return { compliance_reference: String(ref?.value || '').slice(0, 4000), latest_finance: snap || null, outstanding_commission_aed: Math.round(outstanding), penalties_accrued_aed: Math.round(fines), overdue_dues: due || [], note: 'Draft UAE-appropriate legal documents on request, backed by these figures. Recommend a licensed UAE advocate review before any formal/court use.' };
  }
  if (key === 'onboarding') {
    const kyc_pending = await cntT('leads', (q) => q.eq('approval_status', 'pending'));
    const { data: recent } = await admin.from('leads').select('company_name,emirate,sector,registration_submitted_at,ai_review_notes,ai_review_flags,license_expiry').eq('approval_status', 'pending').not('registration_submitted_at', 'is', null).order('registration_submitted_at', { ascending: false }).limit(15);
    const { data: pend } = await admin.from('agent_actions').select('title,recommendation,detail').eq('agent', 'onboarding').eq('status', 'pending').limit(25);
    return { kyc_pending, recent_registrations: recent || [], pending_queue: pend || [] };
  }
  if (key === 'followup') {
    const { data: pend } = await admin.from('agent_actions').select('kind,title,recommendation').eq('agent', 'followup').eq('status', 'pending').limit(40);
    const open_inq = await cntT('inquiries', (q) => q.not('status', 'in', '(completed,accepted,closed,cancelled)'));
    const refunds_pending = await cntT('transactions', (q) => q.eq('refund_status', 'requested'));
    const review_pending = await cntT('inbound_messages', (q) => q.eq('needs_review', true));
    return { open_inquiries: open_inq, refunds_pending, inbound_to_review: review_pending, pending_queue: pend || [] };
  }
  if (key === 'bd') {
    const enabled = (await sec('bd_outreach_enabled')) === 'true';
    const cap = Number(await sec('bd_daily_cap')) || 20;
    const statuses = ['queued', 'sent', 'replied', 'registered', 'unsubscribed', 'bounced', 'skipped'];
    const byStatus: Record<string, number> = {}; for (const st of statuses) byStatus[st] = await cntT('outreach', (q) => q.eq('status', st));
    const { data: sample } = await admin.from('outreach').select('company,category,emirate,subject,status,created_at').order('id', { ascending: false }).limit(12);
    const addressable = await cntT('leads', (q) => q.eq('permanently_closed', false).eq('claimed', false).not('email', 'is', null).neq('email', ''));
    return { sending_enabled: enabled, daily_cap: cap, source_mode: 'database (Phase 1). Phase 2 = LinkedIn sales-manager sourcing, later.', addressable_uncontacted_estimate: addressable, outreach_by_status: byStatus, recent_queue: sample || [], note: enabled ? 'Sending is ON within the daily cap.' : 'Sending is OFF — planning mode only; invites queued but NOT emailed until enabled.' };
  }
  if (key === 'marketing') {
    const { data: cats } = await admin.from('seo_categories').select('slug,name').order('sort');
    const since90 = new Date(Date.now() - 90 * 864e5).toISOString();
    const { data: inq } = await admin.from('inquiries').select('category').gte('created_at', since90);
    const demand: Record<string, number> = {}; for (const i of (inq || [])) { const c = i.category || '(uncategorised)'; demand[c] = (demand[c] || 0) + 1; }
    const { data: drafts } = await admin.from('content_drafts').select('channel,category,title,status,created_at').order('id', { ascending: false }).limit(12);
    const supTotal = await cntT('leads', (q) => q.eq('permanently_closed', false));
    return { brand: 'QuotesDone — UAE B2B anonymous quotation marketplace.', categories: (cats || []).map((c) => ({ slug: c.slug, name: c.name })), demand_by_category_90d: demand, total_suppliers: supTotal, recent_drafts: drafts || [] };
  }
  if (key.startsWith('cat:')) {
    const slug = key.slice(4);
    const { data: spec } = await admin.from('seo_categories').select('slug,name,search_term,intro,includes,faqs').eq('slug', slug).maybeSingle();
    const term = String(spec?.search_term || spec?.name || slug);
    const kw = (term.replace(/[^a-zA-Z]+/g, ' ').trim().split(' ')[0] || slug).slice(0, 24);
    let supCount = 0; try { supCount = await cntT('leads', (q) => q.or('categories.ilike.%' + kw + '%,sector.ilike.%' + kw + '%,services.ilike.%' + kw + '%')); } catch (_e) { supCount = 0; }
    const { data: recentInq } = await admin.from('inquiries').select('id,emirate,summary,status,created_at,category').ilike('category', '%' + slug + '%').order('created_at', { ascending: false }).limit(20);
    const { data: pend } = await admin.from('agent_actions').select('title,recommendation,kind').eq('agent', key).eq('status', 'pending').limit(20);
    return { category: spec?.name || slug, spec: { intro: spec?.intro, includes: spec?.includes, faqs: spec?.faqs }, supplier_coverage_estimate: supCount, recent_inquiries: recentInq || [], pending_queue: pend || [] };
  }
  return {};
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const { data: al } = await admin.from('app_secrets').select('value').eq('key', 'admin_emails').maybeSingle();
    const admins = String(al?.value || 'management@quotesdone.com').toLowerCase().split(',').map((s) => s.trim());
    if (!admins.includes(email)) return J({ error: 'forbidden — not an admin' }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || 'overview');
    const since7 = new Date(Date.now() - 7 * 864e5).toISOString();

    if (action === 'overview') {
      const cnt = async (t: string, mod?: (q: any) => any) => { let q = admin.from(t).select('id', { count: 'exact', head: true }); if (mod) q = mod(q); const { count } = await q; return count || 0; };
      const [suppliers, claimed, verified, selfreg, inq, inq7, quotes, quotes7, txAll, review, pending, refunds, customers, agentQ] = await Promise.all([
        cnt('leads', (q) => q.eq('permanently_closed', false)),
        cnt('leads', (q) => q.eq('claimed', true)),
        cnt('leads', (q) => q.eq('verified', true)),
        cnt('leads', (q) => q.eq('source', 'self_registered')),
        cnt('inquiries'),
        cnt('inquiries', (q) => q.gte('created_at', since7)),
        cnt('quotes'),
        cnt('quotes', (q) => q.gte('created_at', since7)),
        cnt('transactions'),
        cnt('inbound_messages', (q) => q.eq('needs_review', true)),
        cnt('leads', (q) => q.eq('approval_status', 'pending')),
        cnt('transactions', (q) => q.eq('refund_status', 'requested')),
        cnt('customers'),
        cnt('agent_actions', (q) => q.eq('status', 'pending')),
      ]);
      const { data: txs } = await admin.from('transactions').select('reveal_fee,app_fee,fee_status,refund_status');
      let revTotal = 0, revRefunded = 0;
      for (const t of txs || []) { const f = Number(t.reveal_fee ?? t.app_fee ?? 0); if (t.fee_status === 'refunded' || t.refund_status === 'approved') revRefunded += f; else revTotal += f; }
      const { data: cfg } = await admin.from('pricing_config').select('supplier_free_count').eq('id', 1).maybeSingle();
      const { data: regCount } = await admin.rpc('registered_supplier_count');
      const freeLeft = Math.max(0, (Number(cfg?.supplier_free_count) || 1000) - (Number(regCount) || 0));
      const success_ratio = inq > 0 ? Math.round((txAll / inq) * 100) : 0;
      return J({ overview: { total_customers: customers, suppliers, suppliers_registered: Number(regCount) || 0, claimed, verified, selfreg, inquiries: inq, inquiries_7d: inq7, quotes, quotes_7d: quotes7, deals: txAll, success_ratio, revenue_total: Math.round(revTotal), revenue_refunded: Math.round(revRefunded), review_queue: review, kyc_pending: pending, pending_approvals: pending, refunds_pending: refunds, free_slots_left: freeLeft, agent_queue: agentQ } });
    }

    if (action === 'agents_overview') {
      const { data: runs } = await admin.from('agent_runs').select('agent,finished_at,status,counts').order('id', { ascending: false }).limit(160);
      const lastByAgent: Record<string, any> = {};
      for (const r of (runs || [])) { if (!lastByAgent[r.agent]) lastByAgent[r.agent] = r; }
      const { data: pend } = await admin.from('agent_actions').select('agent').eq('status', 'pending');
      const pendBy: Record<string, number> = {}; for (const a of (pend || [])) pendBy[a.agent] = (pendBy[a.agent] || 0) + 1;
      const out: any[] = [];
      for (const [key, m] of Object.entries(AGENTS)) { const lr = m.run ? lastByAgent[m.run] : null; out.push({ key, group: 'ops', name: m.name, emoji: m.emoji, job: m.job, last_run: lr?.finished_at || null, last_status: lr?.status || null, last_counts: lr?.counts || null, pending: pendBy[key] || 0 }); }
      const { data: cats } = await admin.from('category_agents').select('slug,name,emoji,active').eq('active', true).order('name');
      const lrc = lastByAgent['category_sales'];
      for (const c of (cats || [])) { const key = 'cat:' + c.slug; out.push({ key, group: 'category', name: c.name, emoji: c.emoji || '🛠️', job: 'Sales / expert agent for ' + c.name, last_run: lrc?.finished_at || null, last_status: lrc?.status || null, last_counts: null, pending: pendBy[key] || 0 }); }
      return J({ agents: out });
    }
    if (action === 'agent_history') {
      const key = String(body.agent || ''); const m0 = await getAgentMeta(key); if (!m0) return J({ error: 'unknown agent' }, 400);
      const { data } = await admin.from('agent_chats').select('role,content,created_at').eq('agent_key', key).order('id', { ascending: false }).limit(30);
      return J({ agent: key, messages: (data || []).reverse() });
    }
    if (action === 'agent_chat') {
      const key = String(body.agent || ''); const msg = String(body.message || '').trim();
      const m = await getAgentMeta(key); if (!m) return J({ error: 'unknown agent' }, 400);
      if (!msg) return J({ error: 'message required' }, 400);
      const { data: hist } = await admin.from('agent_chats').select('role,content').eq('agent_key', key).order('id', { ascending: false }).limit(10);
      const history = (hist || []).reverse().map((h) => ({ role: h.role, content: h.content }));
      let ctx = {}; try { ctx = await buildContext(key); } catch (_e) { ctx = { error: 'snapshot unavailable' }; }
      const sys = BASE_PERSONA(m.name) + '\n\n' + m.persona + '\n\nLIVE DATA SNAPSHOT (read-only, captured just now):\n' + JSON.stringify(ctx).slice(0, 9000);
      const reply = await llm(sys, [...history, { role: 'user', content: msg }], 1500) || 'I could not reach the AI service just now — try again in a moment.';
      await admin.from('agent_chats').insert([{ agent_key: key, role: 'user', content: msg, created_by: email }, { agent_key: key, role: 'assistant', content: reply }]);
      return J({ reply });
    }
    if (action === 'content_drafts') {
      const { data } = await admin.from('content_drafts').select('id,channel,category,title,body,status,created_at').order('id', { ascending: false }).limit(40);
      return J({ drafts: data || [] });
    }
    if (action === 'outreach') {
      const statuses = ['queued', 'sent', 'replied', 'registered', 'unsubscribed', 'bounced', 'skipped'];
      const byStatus: Record<string, number> = {}; for (const st of statuses) { const { count } = await admin.from('outreach').select('id', { count: 'exact', head: true }).eq('status', st); byStatus[st] = count || 0; }
      const { data: rows } = await admin.from('outreach').select('id,company,category,emirate,email,subject,body,status,created_at,sent_at').order('id', { ascending: false }).limit(60);
      const enabled = (await sec('bd_outreach_enabled')) === 'true'; const cap = Number(await sec('bd_daily_cap')) || 20;
      return J({ enabled, cap, by_status: byStatus, rows: rows || [] });
    }
    if (action === 'bd_set') {
      if (body.enabled !== undefined) await admin.from('app_secrets').upsert({ key: 'bd_outreach_enabled', value: body.enabled ? 'true' : 'false' }, { onConflict: 'key' });
      if (body.cap !== undefined) await admin.from('app_secrets').upsert({ key: 'bd_daily_cap', value: String(Math.max(1, Math.min(200, Number(body.cap) || 20))) }, { onConflict: 'key' });
      return J({ ok: true });
    }
    if (action === 'collections') {
      const { data: dues } = await admin.from('supplier_dues').select('id,supplier_id,quote_amount,amount_due,status,due_date,due_date_30,fine_pct,fine_amount,reminders,overdue_emailed_at,created_at').order('id', { ascending: false }).limit(80);
      const sids = [...new Set((dues || []).map((d) => d.supplier_id))];
      const names: Record<string, string> = {}; if (sids.length) { const { data: ls } = await admin.from('leads').select('id,company_name').in('id', sids); for (const l of ls || []) names[String(l.id)] = l.company_name; }
      return J({ dues: (dues || []).map((d) => ({ ...d, supplier: names[String(d.supplier_id)] || ('#' + d.supplier_id) })) });
    }
    if (action === 'mark_due_paid') { const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400); await admin.from('supplier_dues').update({ status: 'paid', paid_at: new Date().toISOString() }).eq('id', id); return J({ ok: true }); }
    if (action === 'chats') {
      const { data: threads } = await admin.from('chat_threads').select('inquiry_id,supplier_id,status,reason,requested_by,category,strikes,opened_at,created_at').order('created_at', { ascending: false }).limit(60);
      const { data: viol } = await admin.from('chat_violations').select('inquiry_id,supplier_id,sender_role,sender_email,matched,created_at').order('id', { ascending: false }).limit(40);
      return J({ threads: threads || [], violations: viol || [] });
    }

    if (action === 'inquiries') {
      const { data: inq } = await admin.from('inquiries').select('id,category,emirate,summary,status,created_at').order('created_at', { ascending: false }).limit(40);
      const ids = (inq || []).map((i) => i.id);
      const mc: Record<string, number> = {}, qc: Record<string, number> = {};
      if (ids.length) { const { data: m } = await admin.from('inquiry_matches').select('inquiry_id').in('inquiry_id', ids); for (const r of m || []) mc[r.inquiry_id] = (mc[r.inquiry_id] || 0) + 1; const { data: q } = await admin.from('quotes').select('inquiry_id').in('inquiry_id', ids); for (const r of q || []) qc[r.inquiry_id] = (qc[r.inquiry_id] || 0) + 1; }
      return J({ inquiries: (inq || []).map((i) => ({ ...i, matches: mc[i.id] || 0, quotes: qc[i.id] || 0 })) });
    }

    if (action === 'revenue') {
      const { data: txs } = await admin.from('transactions').select('id,supplier_id,quote_amount,reveal_fee,app_fee,fee_status,refund_status,refund_deadline,revealed_at').order('revealed_at', { ascending: false }).limit(50);
      const sids = [...new Set((txs || []).map((t) => t.supplier_id))];
      const names: Record<string, string> = {};
      if (sids.length) { const { data: ls } = await admin.from('leads').select('id,company_name').in('id', sids); for (const l of ls || []) names[String(l.id)] = l.company_name; }
      return J({ transactions: (txs || []).map((t) => ({ ...t, fee: Number(t.reveal_fee ?? t.app_fee ?? 0), supplier: names[String(t.supplier_id)] || ('#' + t.supplier_id) })) });
    }

    if (action === 'refunds') {
      const { data } = await admin.from('transactions').select('id,quote_id,supplier_id,quote_amount,reveal_fee,refund_status,refund_deadline,revealed_at').eq('refund_status', 'requested').order('revealed_at', { ascending: false }).limit(50);
      return J({ refunds: data || [] });
    }
    if (action === 'approve_refund' || action === 'reject_refund') {
      const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400);
      const approve = action === 'approve_refund';
      await admin.from('transactions').update({ refund_status: approve ? 'approved' : 'rejected', fee_status: approve ? 'refunded' : 'paid' }).eq('id', id);
      return J({ ok: true });
    }

    if (action === 'suppliers') {
      const { data } = await admin.from('leads').select('id,company_name,sector,emirate,claimed,verified,approval_status,app_rating,app_reviews,rating,reviews,source,email,phone,registration_status,registration_expires_at,portal_updated_at,lifecycle_stage,banned,license_expiry').or('claimed.eq.true,source.eq.self_registered,source.eq.email_inbound').order('portal_updated_at', { ascending: false, nullsFirst: false }).limit(50);
      return J({ suppliers: data || [] });
    }

    if (action === 'review_queue') {
      const { data } = await admin.from('inbound_messages').select('id,from_email,subject,ai_notes,raw,created_at').eq('needs_review', true).order('created_at', { ascending: false }).limit(40);
      return J({ queue: data || [] });
    }

    if (action === 'kyc') {
      const { data } = await admin.from('leads').select('id,company_name,emirate,sector,contact_name,signatory_name,phone,services,products,trade_license_no,license_authority,license_expiry,trn,egr_number,egr_doc_name,egr_doc_path,license_doc_path,bank_name,bank_account_name,bank_iban,approval_status,ai_review_notes,ai_review_flags,registration_status,registration_submitted_at,accepted_terms_at,verified').eq('approval_status', 'pending').order('registration_submitted_at', { ascending: true, nullsFirst: false }).limit(40);
      return J({ kyc: data || [] });
    }

    if (action === 'verify_supplier' || action === 'approve_supplier') {
      const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400);
      const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', id).maybeSingle();
      await admin.from('leads').update({ verified: true, approval_status: 'approved', lifecycle_stage: 'active', portal_updated_at: new Date().toISOString() }).eq('id', id);
      if (lead?.claimed_by) await admin.from('notifications').insert({ type: 'registration_approved', to_email: lead.claimed_by, to_role: 'supplier', lead_id: id, subject: "You're verified on QuotesDone", body: `Good news — ${lead.company_name} has been verified and approved on QuotesDone. You can now receive inquiries and submit quotes. Access your portal: https://quotesdone.com/suppliers/` });
      return J({ ok: true });
    }
    if (action === 'reject_supplier') {
      const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400);
      const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', id).maybeSingle();
      await admin.from('leads').update({ approval_status: 'rejected', verified: false, portal_updated_at: new Date().toISOString() }).eq('id', id);
      if (lead?.claimed_by) await admin.from('notifications').insert({ type: 'registration_rejected', to_email: lead.claimed_by, to_role: 'supplier', lead_id: id, subject: 'QuotesDone registration — more info needed', body: `We reviewed the registration for ${lead.company_name} and need to verify some details before approving. Please reply to this email or update your profile in the portal.` });
      return J({ ok: true });
    }
    if (action === 'unban') {
      const kind = String(body.kind || ''); const id = Number(body.id); if (!id || !['supplier','customer'].includes(kind)) return J({ error: 'kind (supplier|customer) and id required' }, 400);
      if (kind === 'supplier') await admin.from('leads').update({ banned: false, banned_reason: null }).eq('id', id);
      else await admin.from('customers').update({ banned: false, banned_reason: null }).eq('id', id);
      return J({ ok: true });
    }

    if (action === 'resolve_review') {
      const mid = Number(body.message_id); const leadId = Number(body.lead_id);
      if (!mid) return J({ error: 'message_id required' }, 400);
      await admin.from('inbound_messages').update({ needs_review: false, lead_id: leadId || null, ai_notes: 'resolved by admin' }).eq('id', mid);
      return J({ ok: true });
    }

    if (action === 'agent_queue') {
      const { data } = await admin.from('agent_actions').select('id,agent,kind,status,risk,title,recommendation,detail,target_table,target_id,created_at').eq('status', 'pending').order('created_at', { ascending: false }).limit(100);
      const { data: runs } = await admin.from('agent_runs').select('agent,finished_at,status,counts').order('id', { ascending: false }).limit(8);
      return J({ queue: data || [], runs: runs || [] });
    }
    if (action === 'agent_decide') {
      const id = Number(body.id); const decision = String(body.decision || '');
      if (!id || !['approve', 'reject'].includes(decision)) return J({ error: 'id and decision (approve|reject) required' }, 400);
      const { data: a } = await admin.from('agent_actions').select('*').eq('id', id).maybeSingle();
      if (!a || a.status !== 'pending') return J({ error: 'not found or already decided' }, 404);
      let applied = 'noted';
      if (a.kind === 'approve_supplier') {
        const lid = Number(a.target_id);
        const { data: lead } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', lid).maybeSingle();
        if (decision === 'approve') { await admin.from('leads').update({ verified: true, approval_status: 'approved', lifecycle_stage: 'active', portal_updated_at: new Date().toISOString() }).eq('id', lid); if (lead?.claimed_by) await admin.from('notifications').insert({ type: 'registration_approved', to_email: lead.claimed_by, to_role: 'supplier', lead_id: lid, subject: "You're verified on QuotesDone", body: `Good news — ${lead?.company_name} has been verified and approved on QuotesDone.` }); applied = 'supplier approved'; }
        else { await admin.from('leads').update({ approval_status: 'rejected', verified: false, portal_updated_at: new Date().toISOString() }).eq('id', lid); if (lead?.claimed_by) await admin.from('notifications').insert({ type: 'registration_rejected', to_email: lead.claimed_by, to_role: 'supplier', lead_id: lid, subject: 'QuotesDone registration — more info needed', body: `We need to verify some details for ${lead?.company_name} before approving.` }); applied = 'supplier rejected'; }
      } else if (a.kind === 'licence_expiring' || a.kind === 'licence_expired') {
        if (decision === 'approve') { const lid = Number(a.target_id); const { data: lead } = await admin.from('leads').select('claimed_by,company_name').eq('id', lid).maybeSingle(); if (lead?.claimed_by) await admin.from('notifications').insert({ type: 'licence_reminder', to_email: lead.claimed_by, to_role: 'supplier', lead_id: lid, subject: 'Your trade licence on QuotesDone needs renewal', body: `Our records show the trade licence for ${lead?.company_name} is expiring or has expired. Please upload the renewed licence.` }); applied = 'renewal reminder sent'; } else applied = 'dismissed'; }
      else if (a.kind === 'compliance_update') {
        if (decision === 'approve' && a.detail && (a.detail as any).append_note) { const { data: cur } = await admin.from('app_secrets').select('value').eq('key', 'compliance_ref').maybeSingle(); const base = String(cur?.value || ''); await admin.from('app_secrets').upsert({ key: 'compliance_ref', value: base + String((a.detail as any).append_note) }, { onConflict: 'key' }); applied = 'compliance reference updated'; }
        else if (decision === 'approve' && a.detail && (a.detail as any).new_text) { await admin.from('app_secrets').upsert({ key: 'compliance_ref', value: String((a.detail as any).new_text) }, { onConflict: 'key' }); applied = 'compliance reference updated'; }
        else applied = 'dismissed'; }
      else if (a.kind === 'content_review') { applied = decision === 'approve' ? 'acknowledged' : 'dismissed'; }
      else if (a.kind === 'bd_batch') { applied = decision === 'approve' ? 'acknowledged' : 'dismissed'; }
      else if (a.kind === 'incident' || a.kind === 'security_alert' || a.kind === 'licence_expired') { applied = decision === 'approve' ? 'acknowledged' : 'dismissed'; }
      else if (a.kind === 'open_chat') { const tid = String(a.target_id || ''); const ix = tid.lastIndexOf(':'); const iq = tid.slice(0, ix); const sp = Number(tid.slice(ix + 1)); if (decision === 'approve') { await admin.from('chat_threads').update({ status: 'open', opened_at: new Date().toISOString() }).eq('inquiry_id', iq).eq('supplier_id', sp); const { data: tinfo } = await admin.from('chat_threads').select('customer_id').eq('inquiry_id', iq).eq('supplier_id', sp).maybeSingle(); const { data: lead } = await admin.from('leads').select('claimed_by,email,company_name').eq('id', sp).maybeSingle(); let cuEmail: string | null = null; if (tinfo?.customer_id) { const { data: cu } = await admin.from('customers').select('email').eq('id', tinfo.customer_id).maybeSingle(); cuEmail = cu?.email || null; } const warn = 'Reminder: keep everything on-platform. Sharing phone numbers, emails, links or social handles breaks the Terms you accepted and triggers an immediate ban and a AED 10,000 penalty.'; const rows: any[] = []; const sEmail = lead?.claimed_by || lead?.email; if (sEmail) rows.push({ type: 'chat_opened', to_email: sEmail, to_role: 'supplier', inquiry_id: iq, subject: 'A project chat has been opened on QuotesDone', body: 'A direct chat has been opened for an inquiry. ' + warn + ' Log in to your supplier portal to chat.' }); if (cuEmail) rows.push({ type: 'chat_opened', to_email: cuEmail, to_role: 'customer', inquiry_id: iq, subject: 'Your project chat is now open on QuotesDone', body: 'Your direct chat with the supplier is open. ' + warn + ' Log in to the app to chat.' }); if (rows.length) await admin.from('notifications').insert(rows); applied = 'chat opened'; } else { await admin.from('chat_threads').update({ status: 'closed', closed_at: new Date().toISOString() }).eq('inquiry_id', iq).eq('supplier_id', sp); applied = 'chat request declined'; } }
      await admin.from('agent_actions').update({ status: decision === 'approve' ? 'approved' : 'rejected', decided_at: new Date().toISOString(), decided_by: email }).eq('id', id);
      return J({ ok: true, applied });
    }

    if (action === 'crm') {
      const stages = ['lead', 'registered', 'active', 'lapsed'];
      const pipeline: Record<string, number> = {};
      for (const st of stages) { const { count } = await admin.from('leads').select('id', { count: 'exact', head: true }).eq('lifecycle_stage', st); pipeline[st] = count || 0; }
      const { data: sup } = await admin.from('leads').select('id,company_name,emirate,sector,lifecycle_stage,approval_status,portal_updated_at').or('lifecycle_stage.not.is.null,claimed.eq.true').order('portal_updated_at', { ascending: false, nullsFirst: false }).limit(25);
      const { data: custs } = await admin.from('customers').select('id,full_name,email,created_at').order('created_at', { ascending: false }).limit(20);
      const cids = (custs || []).map((c) => c.id);
      const inqCount: Record<string, number> = {};
      if (cids.length) { const { data: inq } = await admin.from('inquiries').select('customer_id').in('customer_id', cids); for (const r of inq || []) inqCount[String(r.customer_id)] = (inqCount[String(r.customer_id)] || 0) + 1; }
      const { count: custTotal } = await admin.from('customers').select('id', { count: 'exact', head: true });
      return J({ pipeline, suppliers: sup || [], customers: (custs || []).map((c) => ({ ...c, inquiries: inqCount[String(c.id)] || 0 })), customers_total: custTotal || 0 });
    }
    if (action === 'agent_activity') {
      const { data: runs } = await admin.from('agent_runs').select('agent,started_at,finished_at,status,counts,note').order('id', { ascending: false }).limit(15);
      const { data: decided } = await admin.from('agent_actions').select('agent,kind,title,status,decided_at,decided_by').in('status', ['approved', 'rejected']).order('decided_at', { ascending: false }).limit(20);
      return J({ runs: runs || [], decided: decided || [] });
    }

    if (action === 'finance') {
      const { data: exps } = await admin.from('expenses').select('*').order('active', { ascending: false }).order('amount', { ascending: false });
      let monthly = 0; const byCat: Record<string, number> = {};
      for (const e of (exps || [])) { if (!e.active) continue; const a = Number(e.amount) * (String(e.currency).toUpperCase() === 'AED' ? 1 : USD_AED); const m = e.cadence === 'monthly' ? a : (e.cadence === 'annual' ? a / 12 : (e.cadence === 'weekly' ? a * 52 / 12 : 0)); monthly += m; if (m) byCat[e.category] = (byCat[e.category] || 0) + m; }
      const since30 = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
      const { data: ents } = await admin.from('expense_entries').select('id,vendor,category,amount,currency,charged_on,note,source,doc_path,doc_name,doc_content_type').gte('charged_on', since30).order('charged_on', { ascending: false }).limit(80);
      let usage30 = 0; const entsOut = [];
      for (const e of (ents || [])) { if (String(e.category) !== 'Subscription') usage30 += Number(e.amount) * (String(e.currency).toUpperCase() === 'AED' ? 1 : USD_AED); let du = null; if (e.doc_path) { const { data } = await admin.storage.from('receipt-files').createSignedUrl(e.doc_path, 3600); du = data?.signedUrl || null; } entsOut.push({ ...e, doc_url: du }); }
      monthly += usage30;
      const { data: tx } = await admin.from('transactions').select('reveal_fee,app_fee,fee_status,refund_status');
      let rec = 0, col = 0, pend = 0, ref = 0; for (const t of (tx || [])) { const f = Number(t.reveal_fee ?? t.app_fee ?? 0); if (t.fee_status === 'refunded' || t.refund_status === 'approved') { ref += f; continue; } rec += f; if (t.fee_status === 'paid') col += f; else pend += f; }
      const { data: dueAll } = await admin.from('supplier_dues').select('amount_due,fine_amount,status').neq('status','paid').neq('status','waived'); let commDue = 0; for (const d of (dueAll||[])) commDue += Number(d.amount_due||0) + Number(d.fine_amount||0);
      const { data: snaps } = await admin.from('finance_snapshots').select('period_end,revenue_aed,expenses_aed,net_aed').order('id', { ascending: false }).limit(8);
      const { data: reps } = await admin.from('finance_reports').select('id,period_start,period_end,summary,html_path,xlsx_path,created_at').order('id', { ascending: false }).limit(8);
      const repsOut = [];
      for (const r of (reps || [])) { let hu = null, xu = null; if (r.html_path) { const { data } = await admin.storage.from('finance-reports').createSignedUrl(r.html_path, 3600); hu = data?.signedUrl || null; } if (r.xlsx_path) { const { data } = await admin.storage.from('finance-reports').createSignedUrl(r.xlsx_path, 3600); xu = data?.signedUrl || null; } repsOut.push({ id: r.id, period: (r.period_start || '') + ' → ' + (r.period_end || ''), summary: String(r.summary || '').slice(0, 600), created_at: r.created_at, html_url: hu, xlsx_url: xu }); }
      return J({ pl: { revenue_recognized: Math.round(rec), fees_collected: Math.round(col), fees_pending: Math.round(pend), refunds: Math.round(ref), commission_outstanding: Math.round(commDue), monthly_burn: Math.round(monthly), usage_30d: Math.round(usage30), expenses_by_cat: byCat }, expenses: exps || [], usage_entries: entsOut, snapshots: snaps || [], reports: repsOut });
    }
    if (action === 'add_expense') {
      const { vendor, category, description, amount, currency, cadence, expense_date } = body as any;
      if (!vendor || !amount) return J({ error: 'vendor and amount required' }, 400);
      await admin.from('expenses').insert({ vendor: String(vendor), category: String(category || 'Other'), description: description ? String(description) : null, amount: Number(amount), currency: String(currency || 'USD').toUpperCase(), cadence: String(cadence || 'monthly'), expense_date: expense_date || null, source: 'manual', confidence: 'confirmed' });
      return J({ ok: true });
    }
    if (action === 'update_expense') {
      const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400);
      const patch: Record<string, unknown> = {}; ['vendor', 'category', 'description', 'amount', 'currency', 'cadence', 'expense_date', 'active', 'note', 'confidence'].forEach((f) => { if ((body as any)[f] !== undefined) patch[f] = (body as any)[f]; }); if (patch.amount !== undefined) patch.amount = Number(patch.amount);
      await admin.from('expenses').update(patch).eq('id', id); return J({ ok: true });
    }
    if (action === 'delete_expense') { const id = Number(body.id); if (!id) return J({ error: 'id required' }, 400); await admin.from('expenses').update({ active: false }).eq('id', id); return J({ ok: true }); }
    if (action === 'log_usage') {
      const { vendor, amount, currency, charged_on, category, note } = body as any;
      if (!vendor || !amount) return J({ error: 'vendor and amount required' }, 400);
      await admin.from('expense_entries').insert({ vendor: String(vendor), category: category ? String(category) : 'Usage', amount: Number(amount), currency: String(currency || 'USD').toUpperCase(), charged_on: charged_on || new Date().toISOString().slice(0, 10), note: note ? String(note) : null, source: 'manual' });
      return J({ ok: true });
    }
    if (action === 'run_finance') { await admin.rpc('run_agent', { p_job: 'finance' }); return J({ ok: true, note: 'Finance run triggered — refresh in ~30s' }); }
    if (action === 'run_agent') { const job = String(body.job || ''); if (!['marketing','category_sales','compliance','onboarding','followup','finance','bd_outreach','brief','it_health','security','docs','collections'].includes(job)) return J({ error: 'unknown job' }, 400); if (job === 'brief') { await admin.rpc('fn_founder_brief'); } else if (job === 'security') { await admin.rpc('fn_security_scan'); } else if (job === 'docs') { await admin.rpc('fn_doc_control'); } else if (job === 'collections') { await admin.rpc('fn_collections'); } else { await admin.rpc('run_agent', { p_job: job }); } return J({ ok: true, note: job + ' triggered — refresh in ~30s' }); }

    return J({ error: 'unknown action' }, 400);
  } catch (e) {
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});

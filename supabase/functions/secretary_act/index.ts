// secretary_act v2 — the Secretary acts on the founder's instructions via a real action toolkit.
// Tool-calling loop (OpenRouter). Low-risk tools run immediately; high-stakes tools pause for a one-line confirm.
// Accepts document attachments (already text-extracted by the caller) and folds them into the founder's message.
// Auth: __secret == inbound_secret (server/testing) OR admin-email JWT.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function whoami(req: Request, body: any): Promise<string | null> {
  if (body.__secret && body.__secret === (await sec('inbound_secret'))) return 'founder';
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return null;
  const { data: { user } } = await admin.auth.getUser(jwt);
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return (user?.email && allow.includes(user.email.toLowerCase())) ? user.email.toLowerCase() : null;
}
async function callFn(name: string, payload: Record<string, unknown>) { try { const sk = await sec('inbound_secret'); const r = await fetch(FN + '/' + name, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: sk, ...payload }) }); return await r.json(); } catch (e) { return { error: String((e as Error)?.message || e) }; } }
const dayAgo = (d: number) => new Date(Date.now() - d * 864e5).toISOString();

// ---------- TOOLKIT ----------
const HIGH = new Set(['issue_refund', 'supplier_decision', 'delete_files', 'post_content']);
const TOOLS = [
  { type: 'function', function: { name: 'get_status', description: 'Business snapshot: what needs attention (pending suppliers, refund requests, stuck queues, 24h activity, revenue, active alerts).', parameters: { type: 'object', properties: {} } } },
  { type: 'function', function: { name: 'team_roster', description: 'The QuotesDone team: the AI staff of specialist agents (finance, legal, marketing, security, IT, onboarding, collections, BD, document control, etc.) plus per-category sales desks, and the human founder. Use for any question about staff/agents/headcount/who handles a topic.', parameters: { type: 'object', properties: {} } } },
  { type: 'function', function: { name: 'lookup', description: 'Find records. entity one of supplier|customer|inquiry|transaction; query is a name/email/id/keyword.', parameters: { type: 'object', properties: { entity: { type: 'string', enum: ['supplier', 'customer', 'inquiry', 'transaction'] }, query: { type: 'string' } }, required: ['entity', 'query'] } } },
  { type: 'function', function: { name: 'run_maintenance', description: 'Fix/refresh operations. target one of: health, smoke, security, it_health, clear_test_queue (cancel stuck test/dead-address emails+SMS), recompute_response.', parameters: { type: 'object', properties: { target: { type: 'string', enum: ['health', 'smoke', 'security', 'it_health', 'clear_test_queue', 'recompute_response'] } }, required: ['target'] } } },
  { type: 'function', function: { name: 'draft_content', description: 'Generate and SAVE a content draft (not published). channel one of email|whatsapp|social|seo.', parameters: { type: 'object', properties: { channel: { type: 'string' }, topic: { type: 'string' }, notes: { type: 'string' } }, required: ['channel', 'topic'] } } },
  { type: 'function', function: { name: 'add_task', description: 'Add a task to the founder task list.', parameters: { type: 'object', properties: { title: { type: 'string' }, detail: { type: 'string' } }, required: ['title'] } } },
  { type: 'function', function: { name: 'send_email', description: 'Queue an email to one or more recipients (goes out via the mailer). to is an array of addresses.', parameters: { type: 'object', properties: { to: { type: 'array', items: { type: 'string' } }, subject: { type: 'string' }, body: { type: 'string' } }, required: ['to', 'subject', 'body'] } } },
  { type: 'function', function: { name: 'post_content', description: 'PUBLISH content to a channel now. channel email|whatsapp|social. Provide text OR draft_id.', parameters: { type: 'object', properties: { channel: { type: 'string' }, text: { type: 'string' }, draft_id: { type: 'string' }, to: { type: 'array', items: { type: 'string' } } }, required: ['channel'] } } },
  { type: 'function', function: { name: 'log_finance', description: 'Record a finance entry the founder gives you or that you read from an attached invoice/receipt/subscription. kind one of expense|income|subscription. amount in AED. For subscription also give next_due (YYYY-MM-DD) and cycle (monthly|annual).', parameters: { type: 'object', properties: { kind: { type: 'string', enum: ['expense', 'income', 'subscription'] }, vendor: { type: 'string' }, description: { type: 'string' }, amount: { type: 'number' }, currency: { type: 'string' }, category: { type: 'string' }, next_due: { type: 'string' }, cycle: { type: 'string' } }, required: ['kind', 'amount'] } } },
  { type: 'function', function: { name: 'issue_refund', description: 'Record a reveal-fee refund for a transaction (fires the 3% supplier non-response charge). Money settlement is done in your processor.', parameters: { type: 'object', properties: { transaction_id: { type: 'string' }, reason: { type: 'string' } }, required: ['transaction_id'] } } },
  { type: 'function', function: { name: 'supplier_decision', description: 'Approve, reject, ban or unban a supplier. action one of approve|reject|ban|unban.', parameters: { type: 'object', properties: { supplier_id: { type: 'string' }, action: { type: 'string', enum: ['approve', 'reject', 'ban', 'unban'] }, reason: { type: 'string' } }, required: ['supplier_id', 'action'] } } },
  { type: 'function', function: { name: 'delete_files', description: 'Delete files from a storage bucket. bucket + paths[] (or a prefix).', parameters: { type: 'object', properties: { bucket: { type: 'string' }, paths: { type: 'array', items: { type: 'string' } }, prefix: { type: 'string' } }, required: ['bucket'] } } },
];

async function cnt(t: string, mod?: (q: any) => any) { let q = admin.from(t).select('id', { count: 'exact', head: true }); if (mod) q = mod(q); const { count } = await q; return count || 0; }
async function tool_get_status() {
  const supBase = (q: any) => q.or('claimed.eq.true,source.eq.self_registered,source.eq.email_inbound');
  const [pending_suppliers, refunds_requested, held_emails, queued_sms, inq24, q24, rev24, open_tasks] = await Promise.all([
    cnt('leads', (q) => supBase(q).in('approval_status', ['pending', 'submitted'])),
    cnt('transactions', (q) => q.eq('refund_status', 'requested')),
    cnt('notifications', (q) => q.eq('channel', 'email').eq('status', 'held')),
    cnt('notifications', (q) => q.eq('channel', 'sms').eq('status', 'queued')),
    cnt('inquiries', (q) => q.gte('created_at', dayAgo(1))),
    cnt('quotes', (q) => q.gte('created_at', dayAgo(1))),
    cnt('transactions', (q) => q.gte('revealed_at', dayAgo(1))),
    cnt('crm_tasks', (q) => q.eq('status', 'open')),
  ]);
  const { data: paid } = await admin.from('transactions').select('reveal_fee').eq('fee_status', 'paid');
  const revenue = Math.round((paid || []).reduce((a, t) => a + (Number(t.reveal_fee) || 0), 0));
  return { pending_suppliers, refunds_requested, stuck_test_emails: held_emails, stuck_test_sms: queued_sms, inquiries_24h: inq24, quotes_24h: q24, reveals_24h: rev24, open_tasks, revenue_collected_aed: revenue };
}
async function tool_lookup(entity: string, query: string) {
  const q = String(query || '').replace(/[%,()*]/g, ' ').trim().slice(0, 80);
  if (entity === 'supplier') { const { data } = await admin.from('leads').select('id,company_name,email,emirate,approval_status,banned,rv_response_rate').or(`company_name.ilike.*${q}*,email.ilike.*${q}*`).limit(5); return data || []; }
  if (entity === 'customer') { const { data } = await admin.from('customers').select('id,full_name,email,phone,banned').or(`full_name.ilike.*${q}*,email.ilike.*${q}*,phone.ilike.*${q}*`).limit(5); return data || []; }
  if (entity === 'inquiry') { let r: any; if (/^[0-9a-f-]{6,}$/i.test(q)) r = await admin.from('inquiries').select('id,category,emirate,summary,status,created_at').eq('id', q).limit(5); else r = await admin.from('inquiries').select('id,category,emirate,summary,status,created_at').or(`summary.ilike.*${q}*,category.ilike.*${q}*`).limit(5); return r.data || []; }
  if (entity === 'transaction') { const { data } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,fee_status,refund_status,revealed_at').eq('id', q).limit(5); return data || []; }
  return [];
}
async function tool_run_maintenance(target: string) {
  if (target === 'health') return await admin.rpc('run_health_check').then((r) => r.data);
  if (target === 'smoke') { await admin.rpc('fn_smoke'); return { ran: 'smoke' }; }
  if (target === 'security') { await admin.rpc('fn_security_scan'); const { data } = await admin.from('agent_runs').select('counts').eq('agent', 'security').order('id', { ascending: false }).limit(1); return (data && data[0]?.counts) || { ran: 'security' }; }
  if (target === 'it_health') return await admin.rpc('run_agent', { p_job: 'it_health' }).then((r) => r.data).catch(() => ({ ran: 'it_health' }));
  if (target === 'recompute_response') { await admin.rpc('qd_recompute_response').catch(() => null); return { ran: 'recompute_response' }; }
  if (target === 'clear_test_queue') {
    const { data, error } = await admin.from('notifications').update({ status: 'cancelled' }).in('status', ['held', 'queued']).or('to_email.ilike.%.test,to_email.ilike.%@quotesdone.test,to_email.is.null').select('id');
    if (error) return { error: error.message };
    return { cancelled: (data || []).length };
  }
  return { error: 'unknown target' };
}
async function llm(sys: string, user: string, max = 700) { const key = await sec('openrouter_api_key'); if (!key) return null; for (const model of ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8', 'openai/gpt-4o']) { try { const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, max_tokens: max, messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] }), signal: AbortSignal.timeout(25000) /* H9 (OS audit) */ }); const j = await r.json(); const c = j?.choices?.[0]?.message?.content; if (c) return c; } catch (_e) {} } return null; }
async function tool_draft_content(channel: string, topic: string, notes: string) {
  let brain = ''; try { const { data } = await admin.rpc('fn_agent_context', { p_agent_key: 'marketing', p_max_chars: 6000 }); brain = data ? String(data) : ''; } catch (_e) {}
  const out = await llm('You write concise, on-brand content for QuotesDone, a UAE B2B anonymous quotation marketplace. Practical, trustworthy, pro-SME. No invented statistics. Follow the brand voice, content pillars, caption/hashtag formula and platform specs in the knowledge below.\n\n' + brain, 'Channel: ' + channel + '\nTopic: ' + topic + (notes ? ('\nNotes: ' + notes) : '') + '\nWrite the ' + channel + ' content now.', 900) || 'Draft unavailable (AI not reachable).';
  const { data } = await admin.from('content_drafts').insert({ channel: String(channel).slice(0, 20), title: String(topic).slice(0, 200), body: out.slice(0, 4000), status: 'draft', source: 'secretary' }).select('id').maybeSingle();
  return { draft_id: data?.id || null, preview: out.slice(0, 500) };
}
async function tool_add_task(title: string, detail: string) { const { data } = await admin.from('crm_tasks').insert({ title: String(title).slice(0, 200), detail: String(detail || '').slice(0, 2000), status: 'open', source: 'secretary' }).select('id').maybeSingle(); return { task_id: data?.id || null }; }
async function tool_send_email(to: string[], subject: string, body: string) { const rows = (to || []).filter(Boolean).map((addr) => ({ type: 'secretary_send', to_email: String(addr).slice(0, 160), to_role: 'external', channel: 'email', subject: String(subject).slice(0, 200), body: String(body).slice(0, 6000) })); if (!rows.length) return { error: 'no recipients' }; await admin.from('notifications').insert(rows); return { queued: rows.length }; }
async function tool_log_finance(a: any) { const r = await callFn('finance_ingest', { action: 'log', entry: { kind: a.kind, vendor: a.vendor || null, description: a.description || null, amount: a.amount, currency: a.currency || 'AED', category: a.category || null, next_due: a.next_due || null, cycle: a.cycle || null, source: 'secretary' } }); return r; }
async function tool_post_content(a: any) {
  let text = a.text || '';
  if (!text && a.draft_id) { const { data } = await admin.from('content_drafts').select('body').eq('id', a.draft_id).maybeSingle(); text = data?.body || ''; }
  if (!text) return { error: 'nothing to post' };
  const channel = String(a.channel || '');
  if (channel === 'email' || channel === 'whatsapp') { const to = Array.isArray(a.to) ? a.to : []; if (!to.length) return { error: 'need recipients for ' + channel }; await tool_send_email(to, a.subject || 'QuotesDone', text); if (a.draft_id) await admin.from('content_drafts').update({ status: 'posted' }).eq('id', a.draft_id); return { posted: channel, recipients: to.length }; }
  return { pending_channel: channel, note: channel + ' is not connected yet (needs its posting token). The content is saved as a draft; it will publish once the ' + channel + ' connector is added.' };
}
async function tool_issue_refund(transaction_id: string, reason: string) { const { data: tx } = await admin.from('transactions').select('id,refund_status').eq('id', transaction_id).maybeSingle(); if (!tx) return { error: 'transaction_not_found' }; await admin.from('transactions').update({ refund_status: 'refunded', refund_note: String(reason || '').slice(0, 500), refund_resolved_at: new Date().toISOString() }).eq('id', transaction_id); const { data: due } = await admin.from('supplier_dues').select('amount_due,status').eq('transaction_id', transaction_id).order('created_at', { ascending: false }).maybeSingle(); return { refunded: transaction_id, supplier_charge: due || null }; }
async function tool_supplier_decision(supplier_id: string, action: string, reason: string) {
  const id = Number(supplier_id); const { data: l } = await admin.from('leads').select('id,company_name,claimed_by').eq('id', id).maybeSingle(); if (!l) return { error: 'supplier_not_found' };
  if (action === 'approve') { await admin.from('leads').update({ approval_status: 'approved', verified: true, lifecycle_stage: 'active', approved_at: new Date().toISOString() }).eq('id', id); if (l.claimed_by) await admin.from('notifications').insert({ type: 'registration_approved', to_email: l.claimed_by, to_role: 'supplier', lead_id: id, channel: 'email', subject: "You're verified on QuotesDone", body: 'Good news — ' + (l.company_name || 'your company') + ' has been approved on QuotesDone. You can now receive inquiries and quote: https://quotesdone.com/suppliers/' }); }
  else if (action === 'reject') { await admin.from('leads').update({ approval_status: 'rejected', verified: false, rejection_reason: String(reason || '').slice(0, 500) }).eq('id', id); }
  else if (action === 'ban') { await admin.from('leads').update({ banned: true, banned_reason: String(reason || 'admin action').slice(0, 300) }).eq('id', id); }
  else if (action === 'unban') { await admin.from('leads').update({ banned: false, banned_reason: null }).eq('id', id); }
  else return { error: 'bad action' };
  return { ok: true, supplier_id: id, action };
}
async function tool_delete_files(bucket: string, paths: string[], prefix: string) { const r = await callFn('asset_delete', prefix ? { bucket, prefix } : { bucket, paths }); return r; }

async function runTool(name: string, a: any) {
  try {
    if (name === 'get_status') return await tool_get_status();
    if (name === 'team_roster') return await tool_team_roster();
    if (name === 'lookup') return await tool_lookup(a.entity, a.query);
    if (name === 'run_maintenance') return await tool_run_maintenance(a.target);
    if (name === 'draft_content') return await tool_draft_content(a.channel, a.topic, a.notes);
    if (name === 'add_task') return await tool_add_task(a.title, a.detail);
    if (name === 'send_email') return await tool_send_email(a.to, a.subject, a.body);
    if (name === 'log_finance') return await tool_log_finance(a);
    if (name === 'post_content') return await tool_post_content(a);
    if (name === 'issue_refund') return await tool_issue_refund(a.transaction_id, a.reason);
    if (name === 'supplier_decision') return await tool_supplier_decision(a.supplier_id, a.action, a.reason);
    if (name === 'delete_files') return await tool_delete_files(a.bucket, a.paths, a.prefix);
    return { error: 'unknown_tool' };
  } catch (e) { return { error: String((e as Error)?.message || e) }; }
}
function isHigh(name: string, a: any) { if (HIGH.has(name)) return true; if (name === 'send_email' && Array.isArray(a?.to) && a.to.length > 3) return true; return false; }
function describe(name: string, a: any) {
  if (name === 'issue_refund') return 'Refund reveal fee for transaction ' + a.transaction_id + ' (this also charges the supplier the 3% non-response fee).';
  if (name === 'supplier_decision') return a.action + ' supplier #' + a.supplier_id + (a.reason ? (' — ' + a.reason) : '');
  if (name === 'delete_files') return 'Delete files from ' + a.bucket + (a.prefix ? (' under "' + a.prefix + '/"') : (' (' + ((a.paths || []).length) + ' file(s))'));
  if (name === 'post_content') return 'Publish to ' + a.channel + (Array.isArray(a.to) ? (' — ' + a.to.length + ' recipient(s)') : '');
  if (name === 'send_email') return 'Send email "' + (a.subject || '') + '" to ' + ((a.to || []).length) + ' recipient(s)';
  return name;
}

const ROLE_AGENTS: { name: string; duty: string }[] = [
  { name: 'Secretary (me)', duty: 'chief of staff — coordinates the team and acts on your instructions' },
  { name: 'CFO', duty: 'weekly finance report, burn vs revenue, break-even' },
  { name: 'Bookkeeper', duty: 'expenses, receipts, ledger' },
  { name: 'Legal Counsel (UAE)', duty: 'drafts UAE-compliant letters, notices, T&C clauses' },
  { name: 'Marketing', duty: 'social posts, SEO/blog, campaigns, ad plans' },
  { name: 'Security Engineer', duty: 'file scanning, contact-leak + intrusion monitoring' },
  { name: 'IT / Uptime', duty: 'hourly site health checks, incident detection' },
  { name: 'Document Controller', duty: 'supplier trade-licence expiry tracking' },
  { name: 'Onboarding Officer', duty: 'new supplier KYC review + approvals' },
  { name: 'Follow-up / SLA', duty: 'chases stalled inquiries, reveals and quotes' },
  { name: 'Collections', duty: '2% supplier commission dues, reminders, penalties' },
  { name: 'BD / Outreach', duty: 'invites new supplier companies (planning mode)' },
  { name: 'Daily Brief', duty: 'emails your 08:30 Dubai morning snapshot' },
];
async function teamRoster() {
  let cats: any[] = [];
  try { const { data } = await admin.from('category_agents').select('name').eq('active', true).order('name'); cats = data || []; } catch (_e) {}
  return { founder: 'Ahmad (human — founder & owner)', role_agents: ROLE_AGENTS, category_sales_desks: { count: cats.length, examples: cats.slice(0, 14).map((c: any) => c.name) }, total_ai_agents: ROLE_AGENTS.length + cats.length };
}
async function tool_team_roster() { return await teamRoster(); }

const SYS = `You are the Secretary — the founder's chief of staff for QuotesDone, a UAE B2B anonymous quotation marketplace. QuotesDone is founded and owned by Ahmad (the founder you report to); day-to-day operations run on an AI STAFF of specialist agents that YOU coordinate. When someone asks about "our team", "staff", "agents", "headcount" or "who handles X", they mean this AI agent team plus the founder — you know it well (see YOUR TEAM below, and call team_roster for detail). You are capable and decisive, not just a reporter: when the founder gives an instruction, USE YOUR TOOLS to actually do it, then report crisply what you did in 1-4 sentences.

Rules:
- Act. Do not merely describe what could be done — call the tools and get it done.
- Chain tools when needed (e.g. look something up, then act on it).
- If the founder attaches a document (invoice, receipt, subscription, contract), READ the attached text, extract the key details, and act on it (e.g. log_finance for an invoice/subscription), then summarise what you recorded.
- For any question about the team, staff, agents, headcount or who owns a topic, use YOUR TEAM below (or call team_roster) — NEVER say we have "no staff".
- High-stakes actions (refunds/money, sending to many people, publishing publicly, deleting data, banning/approving suppliers) will be paused by the system for a one-line confirmation from the founder — that is expected; still call the tool, do not refuse.
- Be concise and practical. Money is in AED. If a channel isn't connected yet, say so plainly.
- Never invent operational data; if a tool returns nothing, say so.`;

async function orChat(messages: any[]) {
  const key = await sec('openrouter_api_key'); if (!key) return { error: 'no ai key' };
  for (const model of ['anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8', 'openai/gpt-4o']) {
    try {
      const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, max_tokens: 1200, temperature: 0.2, tools: TOOLS, messages }), signal: AbortSignal.timeout(30000) /* H9 (OS audit): abort a hung upstream so the founder's console does not hang */ });
      const j = await r.json(); const m = j?.choices?.[0]?.message; if (m) return { message: m };
    } catch (_e) {}
  }
  return { error: 'ai_unreachable' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const actor = await whoami(req, body); if (!actor) return J({ error: 'forbidden' }, 403);

    // ---- CONFIRM PATH ----
    if (body.confirm_token) {
      const { data: p } = await admin.from('agent_pending_actions').select('*').eq('token', body.confirm_token).maybeSingle();
      if (!p || p.status !== 'pending') return J({ error: 'nothing_to_confirm' });
      if (body.decision === 'cancel') { await admin.from('agent_pending_actions').update({ status: 'cancelled' }).eq('token', body.confirm_token); return J({ ok: true, reply: 'Cancelled — I did not do it.' }); }
      const results: any[] = [];
      for (const act of (p.actions || [])) { results.push({ action: describe(act.tool, act.args), result: await runTool(act.tool, act.args) }); }
      await admin.from('agent_pending_actions').update({ status: 'done' }).eq('token', body.confirm_token);
      await admin.from('agent_command_log').insert({ agent: 'secretary', actor, command: '[confirm] ' + (p.summary || ''), did: results });
      return J({ ok: true, reply: 'Done. ' + results.map((r) => r.action).join('; '), results });
    }

    const message = String(body.message || '').trim(); if (!message) return J({ error: 'empty message' });
    const attachments = Array.isArray(body.attachments) ? body.attachments.slice(0, 5) : [];
    const attachBlock = attachments.filter((a: any) => a && a.text).map((a: any) => 'ATTACHED DOCUMENT "' + String(a.name || 'file').slice(0, 120) + '":\n' + String(a.text).slice(0, 12000)).join('\n\n---\n\n');
    const userContent = message + (attachBlock ? ('\n\n' + attachBlock) : '');
    const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
    let brain = ''; try { const { data: bc } = await admin.rpc('fn_agent_context', { p_agent_key: 'secretary', p_max_chars: 8000 }); brain = bc ? String(bc) : ''; } catch (_e) {}
    let teamBlock = ''; try { const roster = await teamRoster(); teamBlock = 'YOUR TEAM (the AI staff you coordinate, plus the founder):\n- Founder: ' + roster.founder + '\n- Role agents (' + roster.role_agents.length + '): ' + roster.role_agents.map((r) => r.name + ' — ' + r.duty).join('; ') + '\n- Category sales desks: ' + roster.category_sales_desks.count + ' live (e.g. ' + roster.category_sales_desks.examples.slice(0, 10).join(', ') + ')\n- Headcount: ' + roster.total_ai_agents + ' AI specialist agents + 1 human founder (you).'; } catch (_e) {}
    const messages: any[] = [{ role: 'system', content: SYS + (teamBlock ? ('\n\n' + teamBlock) : '') + (brain ? ('\n\n' + brain) : '') }, ...history, { role: 'user', content: userContent }];
    const did: any[] = []; const pending: any[] = [];

    for (let step = 0; step < 5; step++) {
      const resp = await orChat(messages); if ((resp as any).error) return J({ error: (resp as any).error }, 502);
      const m = (resp as any).message; messages.push(m);
      const calls = m.tool_calls || [];
      if (!calls.length) {
        await admin.from('agent_command_log').insert({ agent: 'secretary', actor, command: message, did });
        return J({ ok: true, reply: m.content || 'Done.', did });
      }
      for (const c of calls) {
        let args: any = {}; try { args = JSON.parse(c.function.arguments || '{}'); } catch (_e) {}
        if (isHigh(c.function.name, args)) { pending.push({ tool: c.function.name, args }); messages.push({ role: 'tool', tool_call_id: c.id, content: JSON.stringify({ status: 'awaiting_founder_confirmation', note: 'queued; will run once the founder confirms' }) }); }
        else { const out = await runTool(c.function.name, args); did.push({ tool: c.function.name, result: out }); messages.push({ role: 'tool', tool_call_id: c.id, content: JSON.stringify(out).slice(0, 4000) }); }
      }
      if (pending.length) {
        const summary = pending.map((p) => describe(p.tool, p.args)).join(' AND ');
        const { data: tok } = await admin.from('agent_pending_actions').insert({ created_by: actor, summary, actions: pending }).select('token').maybeSingle();
        return J({ ok: true, needs_confirmation: true, confirm_token: tok?.token || null, reply: 'I am about to: ' + summary + '. Confirm?', did });
      }
    }
    await admin.from('agent_command_log').insert({ agent: 'secretary', actor, command: message, did });
    return J({ ok: true, reply: 'Done (reached step limit).', did });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

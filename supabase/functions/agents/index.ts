// agents - scheduled autonomous ops workers. Risky actions queued into agent_actions for approval; safe work auto.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const UA = 'Mozilla/5.0 (compatible; QuotesDoneComplianceBot/1.0; +https://quotesdone.com)';
const CAP = 30 * 1024 * 1024; const USD_AED = 3.6725;
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const ASSET = Deno.env.get('SUPABASE_URL')! + '/storage/v1/object/public/brand';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function callFn(name: string, payload: Record<string, unknown>){ try { const sk = await sec('cred_fn_agents'); const r = await fetch(FN + '/' + name, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: sk, ...payload }) }); return await r.json(); } catch (e) { return { error: String((e as Error)?.message || e) }; } }
function parseDate(v: unknown): Date | null { if (!v) return null; const s = String(v).trim(); let d = new Date(s); if (!isNaN(d.getTime())) return d; const m = s.match(/^(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})$/); if (m) { let yy = Number(m[3]); if (yy < 100) yy += 2000; d = new Date(yy, Number(m[2]) - 1, Number(m[1])); if (!isNaN(d.getTime())) return d; } return null; }
async function queue(row: Record<string, unknown>) { try { await admin.from('agent_actions').insert(row); } catch (_e) {} }
async function sha256(s: string){ const data = new TextEncoder().encode(s); const h = await crypto.subtle.digest('SHA-256', data); return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 40); }
const dayAgo = (d: number) => new Date(Date.now() - d * 864e5).toISOString();
// Background AI helpers on Opus 4.8 first, Sonnet 5 fallback, iterating models individually for resilience.
const llm = makeLlm(SONNET_FIRST, { max: 400 }); // shared OpenRouter client (Sonnet-first ladder + 25s timeout)
async function cnt(t: string, mod?: (q: any) => any){ let q = admin.from(t).select('id', { count: 'exact', head: true }); if (mod) q = mod(q); const { count } = await q; return count || 0; }

async function onboarding() {
  const counts = { reviewed: 0, queued_approval: 0, licence_alerts: 0 };
  const { data: pend } = await admin.from('leads').select('id,company_name,emirate,approval_status,registration_submitted_at,ai_review_flags,ai_review_notes,license_expiry,trade_license_no,trn,accepted_terms_at,lifecycle_stage').eq('approval_status', 'pending').not('registration_submitted_at', 'is', null).order('registration_submitted_at', { ascending: true }).limit(60);
  for (const s of (pend || [])) {
    counts.reviewed++;
    const flags = Array.isArray(s.ai_review_flags) ? s.ai_review_flags : [];
    const exp = parseDate(s.license_expiry);
    const missing: string[] = [];
    if (!s.trade_license_no) missing.push('trade licence number');
    if (!s.accepted_terms_at) missing.push('terms not accepted');
    if (!exp) missing.push('licence expiry unreadable'); else if (exp.getTime() < Date.now()) missing.push('trade licence EXPIRED');
    const clean = flags.length === 0 && missing.length === 0;
    const title = String(s.company_name || ('Supplier #' + s.id)) + (s.emirate ? ' — ' + s.emirate : '');
    await queue({ agent: 'onboarding', kind: 'approve_supplier', status: 'pending', risk: 'high', title, recommendation: clean ? 'approve' : 'review', target_table: 'leads', target_id: String(s.id), detail: { emirate: s.emirate, flags, ai_notes: String(s.ai_review_notes || '').slice(0, 500), missing, licence_expiry: s.license_expiry || null } });
    counts.queued_approval++;
    if (s.lifecycle_stage !== 'registered') await admin.from('leads').update({ lifecycle_stage: 'registered' }).eq('id', s.id);
  }
  const { data: appr } = await admin.from('leads').select('id,company_name,emirate,license_expiry,lifecycle_stage').eq('approval_status', 'approved').not('license_expiry', 'is', null).limit(400);
  for (const s of (appr || [])) {
    const exp = parseDate(s.license_expiry); if (!exp) continue;
    const days = Math.round((exp.getTime() - Date.now()) / 864e5);
    if (days <= 30) { const expired = days < 0; await queue({ agent: 'onboarding', kind: expired ? 'licence_expired' : 'licence_expiring', status: 'pending', risk: expired ? 'high' : 'low', title: String(s.company_name || s.id) + (expired ? ' — licence EXPIRED' : ' — licence expires in ' + days + ' days'), recommendation: expired ? 'suspend / chase renewal' : 'remind supplier', target_table: 'leads', target_id: String(s.id), detail: { licence_expiry: s.license_expiry, days } }); counts.licence_alerts++; }
    if (s.lifecycle_stage !== 'active') await admin.from('leads').update({ lifecycle_stage: 'active' }).eq('id', s.id);
  }
  return counts;
}

async function recentlyNudged(type: string, inquiryId: number | null, supplierId: number | null){ let q = admin.from('notifications').select('id').eq('type', type).gte('created_at', dayAgo(4)).limit(1); if (inquiryId) q = q.eq('inquiry_id', inquiryId); if (supplierId) q = q.eq('lead_id', supplierId); const { data } = await q; return !!(data && data.length); }
const CLOSED = '(completed,accepted,closed,cancelled)';
async function followup(){
  const counts = { reveal_nudges: 0, quote_nudges: 0, sla: 0 };
  const { data: openInq } = await admin.from('inquiries').select('id,customer_id,category,emirate,created_at,status').lt('created_at', dayAgo(2)).not('status', 'in', CLOSED).order('created_at', { ascending: true }).limit(200);
  for (const inq of (openInq || [])) {
    const qn = await cnt('quotes', (q) => q.eq('inquiry_id', inq.id)); if (!qn) continue;
    const tn = await cnt('transactions', (q) => q.eq('inquiry_id', inq.id)); if (tn) continue;
    if (await recentlyNudged('nudge_reveal', inq.id, null)) continue;
    const { data: cust } = await admin.from('customers').select('email,full_name').eq('id', inq.customer_id).maybeSingle(); if (!cust || !cust.email) continue;
    const first = cust.full_name ? ' ' + String(cust.full_name).split(' ')[0] : '';
    await admin.from('notifications').insert({ type: 'nudge_reveal', to_email: cust.email, to_role: 'customer', inquiry_id: inq.id, channel: 'email', subject: 'You have ' + qn + ' quote' + (qn > 1 ? 's' : '') + ' waiting on QuotesDone', body: 'Hi' + first + ', you have ' + qn + ' quote' + (qn > 1 ? 's' : '') + ' ready for your ' + (inq.category || '') + ' request' + (inq.emirate ? ' in ' + inq.emirate : '') + '. Open the app to compare and reveal the supplier you choose: https://quotesdone.com/app/' });
    counts.reveal_nudges++;
  }
  const { data: matches } = await admin.from('inquiry_matches').select('id,inquiry_id,supplier_id,sent_at').lt('sent_at', dayAgo(2)).order('sent_at', { ascending: true }).limit(300);
  for (const m of (matches || [])) {
    if (counts.quote_nudges >= 80) break;
    const { data: inq } = await admin.from('inquiries').select('id,category,emirate,status').eq('id', m.inquiry_id).maybeSingle();
    if (!inq || ['completed', 'accepted', 'closed', 'cancelled'].includes(String(inq.status))) continue;
    const tn = await cnt('transactions', (q) => q.eq('inquiry_id', m.inquiry_id)); if (tn) continue;
    const qn = await cnt('quotes', (q) => q.eq('inquiry_id', m.inquiry_id).eq('supplier_id', m.supplier_id)); if (qn) continue;
    if (await recentlyNudged('nudge_quote', m.inquiry_id, m.supplier_id)) continue;
    const { data: lead } = await admin.from('leads').select('company_name,claimed_by,email,approval_status').eq('id', m.supplier_id).maybeSingle();
    const toA = lead?.claimed_by || lead?.email; if (!toA || lead?.approval_status === 'rejected') continue;
    await admin.from('notifications').insert({ type: 'nudge_quote', to_email: toA, to_role: 'supplier', lead_id: m.supplier_id, inquiry_id: m.inquiry_id, channel: 'email', subject: 'A customer is waiting for your quote', body: 'Hi ' + (lead?.company_name || '') + ', a customer is waiting for your quote on a ' + (inq.category || '') + ' request' + (inq.emirate ? ' in ' + inq.emirate : '') + '. Submit it in your portal: https://quotesdone.com/suppliers/' });
    counts.quote_nudges++;
  }
  const { data: refs } = await admin.from('transactions').select('id,refund_requested_at,reveal_fee').eq('refund_status', 'requested').lt('refund_requested_at', dayAgo(2)).limit(50);
  for (const r of (refs || [])) { const days = Math.round((Date.now() - new Date(r.refund_requested_at).getTime()) / 864e5); await queue({ agent: 'followup', kind: 'sla_refund', status: 'pending', risk: 'low', title: 'Refund request pending ' + days + ' days', recommendation: 'resolve in the Refunds tab', target_table: 'transactions', target_id: String(r.id), detail: { reveal_fee: r.reveal_fee, days } }); counts.sla++; }
  const { data: revq } = await admin.from('inbound_messages').select('id,from_email,subject,created_at').eq('needs_review', true).lt('created_at', dayAgo(3)).limit(50);
  for (const m of (revq || [])) { await queue({ agent: 'followup', kind: 'sla_review', status: 'pending', risk: 'low', title: 'Inbound email awaiting review: ' + String(m.subject || m.from_email || m.id).slice(0, 60), recommendation: 'clear in the Review queue', target_table: 'inbound_messages', target_id: String(m.id), detail: { from: m.from_email } }); counts.sla++; }
  const { data: gaps } = await admin.from('inquiries').select('id,category,emirate,created_at,status').lt('created_at', dayAgo(5)).not('status', 'in', CLOSED).limit(120);
  for (const inq of (gaps || [])) { const mn = await cnt('inquiry_matches', (q) => q.eq('inquiry_id', inq.id)); if (mn) continue; await queue({ agent: 'followup', kind: 'sla_no_supply', status: 'pending', risk: 'low', title: 'No suppliers matched: ' + (inq.category || '') + (inq.emirate ? ' / ' + inq.emirate : ''), recommendation: 'check category coverage / source suppliers', target_table: 'inquiries', target_id: String(inq.id), detail: { category: inq.category, emirate: inq.emirate } }); counts.sla++; }
  return counts;
}

async function marketing(){
  const counts = { drafts: 0 };
  const { data: cats } = await admin.from('seo_categories').select('slug,name').order('sort').limit(24);
  const since90 = new Date(Date.now() - 90 * 864e5).toISOString();
  const { data: inq } = await admin.from('inquiries').select('category').gte('created_at', since90);
  const demand: Record<string, number> = {}; for (const i of (inq || [])) { const c = i.category || ''; if (c) demand[c] = (demand[c] || 0) + 1; }
  const catNames = (cats || []).map((c) => c.name).join(', ');
  const out = await llm('You are the marketing content creator for QuotesDone, a UAE B2B anonymous quotation marketplace (customers post a job, get matched to vetted suppliers, compare anonymised quotes, and pay a small reveal fee to unlock the supplier they choose). Brand voice: practical, trustworthy, pro-SME. Produce a weekly content batch as STRICT JSON ONLY: {"drafts":[{"channel":"social|seo|email","category":"<a category name or empty>","title":"...","body":"..."}]}. Make exactly 5 drafts: 3 short punchy social posts (with 2-3 hashtags) for different categories, 1 SEO cost-guide article (title + a 120-180 word intro) for a high-demand category, and 1 short email tip. Do NOT invent statistics. Reply with JSON only, no preamble.', 'Categories: ' + catNames + '\nRecent demand by category (90d): ' + JSON.stringify(demand), 1900);
  let drafts: any[] = [];
  if (out) { const m = out.match(/\{[\s\S]*\}/); if (m) { try { drafts = JSON.parse(m[0]).drafts || []; } catch (_e) {} } }
  for (const d of drafts.slice(0, 8)) { if (!d || !d.body) continue; await admin.from('content_drafts').insert({ channel: String(d.channel || 'social').slice(0, 20), category: d.category ? String(d.category).slice(0, 80) : null, title: d.title ? String(d.title).slice(0, 200) : null, body: String(d.body).slice(0, 4000), status: 'draft', source: 'marketing_agent' }); counts.drafts++; }
  if (counts.drafts) await queue({ agent: 'marketing', kind: 'content_review', status: 'pending', risk: 'low', title: counts.drafts + ' new marketing drafts ready to review', recommendation: 'open the Marketing agent, review and post the ones you like', target_table: 'content_drafts', target_id: null, detail: { count: counts.drafts } });
  return counts;
}

async function categorySales(){
  const counts = { categories: 0, hot: 0, gaps: 0 };
  const { data: cats } = await admin.from('category_agents').select('slug,name').eq('active', true);
  for (const c of (cats || [])) {
    counts.categories++; const key = 'cat:' + c.slug;
    const { data: inqs } = await admin.from('inquiries').select('id,emirate,summary,status,created_at').ilike('category', '%' + c.slug + '%').gte('created_at', dayAgo(21)).not('status', 'in', CLOSED).order('created_at', { ascending: false }).limit(40);
    for (const inq of (inqs || [])) {
      if (counts.hot + counts.gaps >= 60) break;
      const tn = await cnt('transactions', (q) => q.eq('inquiry_id', inq.id)); if (tn) continue;
      const { data: exists } = await admin.from('agent_actions').select('id').eq('agent', key).eq('target_id', String(inq.id)).eq('status', 'pending').limit(1);
      if (exists && exists.length) continue;
      const qn = await cnt('quotes', (q) => q.eq('inquiry_id', inq.id));
      const mn = await cnt('inquiry_matches', (q) => q.eq('inquiry_id', inq.id));
      if (qn > 0) { await queue({ agent: key, kind: 'hot_lead', status: 'pending', risk: 'low', title: 'Hot lead — ' + c.name + (inq.emirate ? ' / ' + inq.emirate : '') + ': ' + qn + ' quote(s), not revealed', recommendation: 'nudge the customer to reveal', target_table: 'inquiries', target_id: String(inq.id), detail: { category: c.slug, quotes: qn } }); counts.hot++; }
      else if (mn === 0) { await queue({ agent: key, kind: 'supply_gap', status: 'pending', risk: 'low', title: 'Supply gap — ' + c.name + (inq.emirate ? ' / ' + inq.emirate : '') + ': no suppliers matched', recommendation: 'source or activate suppliers in this category', target_table: 'inquiries', target_id: String(inq.id), detail: { category: c.slug } }); counts.gaps++; }
    }
    if (counts.hot + counts.gaps >= 60) break;
  }
  return counts;
}

async function bdOutreach(){
  const counts: Record<string, unknown> = { mode: 'plan', planned: 0, sent: 0, skipped: 0 };
  const enabled = (await sec('bd_outreach_enabled')) === 'true';
  const cap = Math.max(1, Math.min(200, Number(await sec('bd_daily_cap')) || 20));
  if (enabled) {
    counts.mode = 'send';
    const { data: q } = await admin.from('outreach').select('id,lead_id,email,subject,body').eq('status', 'queued').order('id', { ascending: true }).limit(cap);
    for (const o of (q || [])) { if (!o.email) { await admin.from('outreach').update({ status: 'skipped' }).eq('id', o.id); (counts.skipped as number)++; continue; } await admin.from('notifications').insert({ type: 'bd_invite', to_email: o.email, to_role: 'supplier', lead_id: o.lead_id, channel: 'email', subject: o.subject || 'An invitation to join QuotesDone', body: o.body || '' }); await admin.from('outreach').update({ status: 'sent', sent_at: new Date().toISOString() }).eq('id', o.id); (counts.sent as number)++; }
    return counts;
  }
  const queuedPending = await cnt('outreach', (q) => q.eq('status', 'queued'));
  if (queuedPending >= cap * 5) { counts.note = 'queue already has ' + queuedPending + ' planned invites; enable sending to work them off'; return counts; }
  const { data: taken0 } = await admin.from('outreach').select('lead_id');
  const taken = new Set((taken0 || []).map((r) => r.lead_id));
  const tplSub = 'Invitation to join QuotesDone — free supplier listing';
  const tplBody = 'Dear {{COMPANY}},\n\nWe would like to introduce QuotesDone, a UAE marketplace that connects customers with trusted suppliers across every trade and service. Customers post what they need, we match them to suitable suppliers, and each supplier submits a competitive, anonymised quote. The customer compares the quotes and pays a small fee only to unlock the supplier they choose — so every enquiry that reaches you comes from someone ready to buy.\n\nFor suppliers, joining is completely free: no subscription and no commission on the work you win.\n\nHow to register:\n1. Go to quotesdone.com/suppliers and create your account.\n2. Add your trade licence and list your full range of products and services — the more complete your details, the more accurately we can match you to relevant customer requests.\n3. Once approved, you start receiving matched enquiries and can quote directly.\n\nWe would be glad to welcome {{COMPANY}} to the network.';
  const { data: leads } = await admin.from('leads').select('id,company_name,email,categories,sector,emirate,app_rating,rating,reviews').eq('permanently_closed', false).eq('claimed', false).not('email', 'is', null).neq('email', '').order('app_rating', { ascending: false, nullsFirst: false }).order('rating', { ascending: false, nullsFirst: false }).order('reviews', { ascending: false, nullsFirst: false }).limit(cap * 5);
  let made = 0;
  for (const l of (leads || [])) {
    if (made >= cap) break; if (taken.has(l.id) || !l.email) continue;
    const trade = (l.sector || (l.categories ? String(l.categories).split(/[,;]/)[0].trim() : '') || 'your services');
    const link = 'https://quotesdone.com/suppliers';
    const fill = (s: string) => String(s || '').replace(/\{\{COMPANY\}\}/g, l.company_name || 'there').replace(/\{\{TRADE\}\}/g, trade).replace(/\{\{EMIRATE\}\}/g, l.emirate || 'the UAE').replace(/\{\{LINK\}\}/g, link);
    const subject = fill(tplSub).slice(0, 160);
    let bodyTxt = fill(tplBody).slice(0, 2000);
    if (!/quotesdone\.com\/portal/.test(bodyTxt)) bodyTxt += '\n\nRegister at quotesdone.com/portal';
    await admin.from('outreach').insert({ lead_id: l.id, source: 'database', email: l.email, company: l.company_name, category: trade, emirate: l.emirate, channel: 'email', status: 'queued', subject, body: bodyTxt });
    taken.add(l.id); made++; (counts.planned as number)++;
  }
  if ((counts.planned as number) > 0) await queue({ agent: 'bd_outreach', kind: 'bd_batch', status: 'pending', risk: 'low', title: (counts.planned as number) + ' supplier invites drafted and queued (NOT sent)', recommendation: 'review in the BD / Outreach Rep agent; enable sending when ready', target_table: 'outreach', target_id: null, detail: { planned: counts.planned, mode: 'plan' } });
  return counts;
}

async function itHealth(){
  const counts: Record<string, number> = { checks: 0, up: 0, down: 0, alerts: 0 };
  const targets: [string, string][] = [['home', 'https://quotesdone.com/'], ['app', 'https://quotesdone.com/me'], ['portal', 'https://quotesdone.com/portal'], ['admin', 'https://quotesdone.com/os']];
  for (const [name, url] of targets) {
    counts.checks++; const t0 = Date.now(); let ok = false, code = 0, detail = '';
    try { const ctrl = new AbortController(); const tm = setTimeout(() => ctrl.abort(), 15000); const r = await fetch(url, { method: 'GET', redirect: 'follow', signal: ctrl.signal, headers: { 'User-Agent': UA } }); clearTimeout(tm); code = r.status; ok = r.ok; try { await r.body?.cancel(); } catch (_e) {} } catch (e) { detail = String((e as Error)?.message || e); }
    const lat = Date.now() - t0;
    await admin.from('health_checks').insert({ check_kind: 'http', target: name, ok, status_code: code, latency_ms: lat, detail });
    if (ok) counts.up++; else { counts.down++; await queue({ agent: 'it', kind: 'incident', status: 'pending', risk: 'high', title: 'Page DOWN: ' + name + ' (' + (code || detail || 'no response') + ')', recommendation: 'check the Vercel deploy / edge function; page returned non-200', target_table: 'health_checks', target_id: null, detail: { url, code, detail } }); counts.alerts++; }
  }
  const { data: fails } = await admin.from('agent_runs').select('agent,note').eq('status', 'error').gte('started_at', dayAgo(1)).order('id', { ascending: false }).limit(10);
  if (fails && fails.length) { const agents = [...new Set(fails.map((f) => f.agent))]; await admin.from('health_checks').insert({ check_kind: 'agent_runs', target: agents.join(','), ok: false, detail: fails.length + ' failed runs' }); await queue({ agent: 'it', kind: 'incident', status: 'pending', risk: 'medium', title: fails.length + ' agent run(s) failed in last 24h', recommendation: 'review failing jobs: ' + agents.join(', '), target_table: 'agent_runs', target_id: null, detail: { agents } }); counts.alerts++; }
  if (counts.down > 0) { const owner = String(await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim(); await admin.from('notifications').insert({ type: 'it_alert', to_email: owner, to_role: 'admin', channel: 'email', subject: '⚠ QuotesDone IT alert: ' + counts.down + ' page(s) down', body: 'The IT monitor found ' + counts.down + ' page(s) returning errors. Open the IT agent in admin for details.' }); }
  return counts;
}

async function security(){
  const counts: Record<string, number> = { scanned: 0, suspicious: 0, violations7d: 0, banned: 0, events: 0 };
  const buckets = ['quote-files', 'drawing-files', 'supplier-docs', 'receipt-files'];
  const badExt = /\.(exe|bat|cmd|com|scr|msi|ps1|vbs|js|jar|sh|apk|dll|hta|wsf|docm|xlsm|pptm|iso|img|html?|svg)$/i;
  const okExt = /\.(pdf|png|jpe?g|webp|gif|heic|heif|dwg|dxf|docx?|xlsx?|csv|txt)$/i;
  const scan = async (b: string, path: string, meta: any) => {
    counts.scanned++; const sizeB = Number(meta?.size || 0); const mime = String(meta?.mimetype || ''); let sev = ''; let why = '';
    if (/\.[a-z0-9]{2,5}\.(exe|js|scr|bat|html?|svg|hta)$/i.test(path)) { sev = 'high'; why = 'double extension'; }
    else if (badExt.test(path)) { sev = 'high'; why = 'dangerous file type'; }
    else if (!okExt.test(path)) { sev = 'medium'; why = 'unexpected file type'; }
    else if (sizeB > 30 * 1024 * 1024) { sev = 'medium'; why = 'oversized (' + Math.round(sizeB / 1048576) + 'MB)'; }
    else if (sizeB === 0) { sev = 'low'; why = 'empty file'; }
    if (sev) { counts.suspicious++; counts.events++; await admin.from('security_events').insert({ kind: 'suspicious_upload', severity: sev, source: b, subject: path.slice(0, 200), detail: { mime, size: sizeB, why } }); if (sev === 'high') await queue({ agent: 'security', kind: 'security_alert', status: 'pending', risk: 'high', title: 'Suspicious upload (' + why + '): ' + path.slice(0, 80), recommendation: 'inspect/remove the file in storage; do NOT open it directly', target_table: 'security_events', target_id: null, detail: { bucket: b, path, mime, size: sizeB, why } }); }
  };
  for (const b of buckets) {
    try {
      const { data: top } = await admin.storage.from(b).list('', { limit: 80, sortBy: { column: 'created_at', order: 'desc' } });
      for (const f of (top || [])) {
        if (counts.scanned >= 250) break;
        if ((f as any).id && (f as any).metadata) { await scan(b, f.name, (f as any).metadata); }
        else { const { data: sub } = await admin.storage.from(b).list(f.name, { limit: 40, sortBy: { column: 'created_at', order: 'desc' } }); for (const s of (sub || [])) { if (counts.scanned >= 250) break; await scan(b, f.name + '/' + s.name, (s as any).metadata); } }
      }
    } catch (_e) {}
  }
  counts.violations7d = await cnt('chat_violations', (q) => q.gte('created_at', dayAgo(7)));
  const bl = await cnt('leads', (q) => q.eq('banned', true)); const bc = await cnt('customers', (q) => q.eq('banned', true)); counts.banned = bl + bc;
  if (counts.violations7d > 0) { await admin.from('security_events').insert({ kind: 'contact_disclosure', severity: 'medium', source: 'chat', subject: counts.violations7d + ' contact-sharing attempt(s) in 7d', detail: { count: counts.violations7d } }); counts.events++; }
  if (counts.suspicious > 0) { const owner = String(await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim(); await admin.from('notifications').insert({ type: 'security_alert', to_email: owner, to_role: 'admin', channel: 'email', subject: '⚠ QuotesDone security: ' + counts.suspicious + ' suspicious file(s) flagged', body: 'The Security agent flagged ' + counts.suspicious + ' uploaded file(s) during its scan. Open the Security agent in admin for details. Do not open flagged files directly.' }); }
  return counts;
}

function isAsset(url: string){ return /\.(pdf|ashx|aspx|docx?|xlsx?)(\?|$)/i.test(url) || /\/-\/media\//i.test(url) || /\/media\//i.test(url); }
async function assetInfo(url: string){ const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 25000); let ok = false, status = 0; let lastModified: string | null = null, contentLength: string | null = null, etag: string | null = null, total: string | null = null; let err = ''; try { try { const h = await fetch(url, { method: 'HEAD', headers: { 'User-Agent': UA }, redirect: 'follow', signal: ctrl.signal }); status = h.status; ok = h.ok; lastModified = h.headers.get('last-modified'); contentLength = h.headers.get('content-length'); etag = h.headers.get('etag'); } catch (_e) {} try { const g = await fetch(url, { method: 'GET', headers: { 'User-Agent': UA, 'Range': 'bytes=0-0' }, redirect: 'follow', signal: ctrl.signal }); if (g.status === 206 || g.ok) { ok = true; status = g.status; const cr = g.headers.get('content-range'); if (cr) { const m = cr.match(/\/(\d+)\s*$/); if (m) total = m[1]; } if (!etag) etag = g.headers.get('etag'); if (!lastModified) lastModified = g.headers.get('last-modified'); if (!contentLength) contentLength = g.headers.get('content-length'); } else if (!ok) { status = g.status; } try { await g.body?.cancel(); } catch (_e) {} } catch (e) { if (!ok) err = String((e as Error)?.message || e); } clearTimeout(t); return { ok, status, lastModified, contentLength, etag, total, err }; } catch (e) { clearTimeout(t); return { ok: false, status: 0, lastModified: null, contentLength: null, etag: null, total: null, err: String((e as Error)?.message || e) }; } }
function assetSignature(h: any){ const size = h.total || h.contentLength; let lm = h.lastModified; if (lm) { const lmMs = new Date(lm).getTime(); if (isNaN(lmMs) || Math.abs(Date.now() - lmMs) < 6 * 3600 * 1000) lm = null; } const parts = [ h.etag ? ('etag ' + h.etag) : '', size ? ('size ' + size) : '', lm ? ('mod ' + lm) : '' ].filter(Boolean); return 'file: ' + (parts.join(' | ') || 'reachable'); }
async function fetchHtml(url: string){ const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 25000); try { const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'text/html,application/xhtml+xml' }, redirect: 'follow', signal: ctrl.signal }); clearTimeout(t); if (!r.ok) return { ok: false, status: r.status, text: '' }; let body = await r.text(); body = body.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim(); return { ok: true, status: r.status, text: body.slice(0, 8000) }; } catch (e) { clearTimeout(t); return { ok: false, status: 0, text: '', err: String((e as Error)?.message || e) } as any; } }
async function fetchReader(url: string){ const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 28000); try { const r = await fetch('https://r.jina.ai/' + url, { headers: { 'User-Agent': UA, 'Accept': 'text/plain' }, redirect: 'follow', signal: ctrl.signal }); clearTimeout(t); if (!r.ok) return { ok: false, status: r.status, text: '' }; let body = await r.text(); body = body.replace(/\s+/g, ' ').trim(); return { ok: true, status: r.status, text: body.slice(0, 8000) }; } catch (e) { clearTimeout(t); return { ok: false, status: 0, text: '', err: String((e as Error)?.message || e) } as any; } }
async function downloadAsset(url: string){ const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 45000); try { const r = await fetch(url, { headers: { 'User-Agent': UA }, redirect: 'follow', signal: ctrl.signal }); clearTimeout(t); if (!r.ok) return { ok: false, status: r.status }; const ct = r.headers.get('content-type') || 'application/octet-stream'; const buf = new Uint8Array(await r.arrayBuffer()); return { ok: true, status: r.status, bytes: buf, contentType: ct }; } catch (e) { clearTimeout(t); return { ok: false, status: 0, err: String((e as Error)?.message || e) } as any; } }
async function storeDoc(id: number, oldPath: string | null, body: Uint8Array | string, contentType: string, ext: string){ const p = String(id) + '/' + Date.now() + '.' + ext; const payload = typeof body === 'string' ? new Blob([body], { type: contentType }) : body; const { error } = await admin.storage.from('compliance-docs').upload(p, payload, { contentType, upsert: true }); if (error) return null; if (oldPath && oldPath !== p) { try { await admin.storage.from('compliance-docs').remove([oldPath]); } catch (_e) {} } return p; }
async function compliance(){
  const counts = { checked: 0, reachable: 0, unreachable: 0, downloaded: 0, changes_proposed: 0 };
  const { data: srcs } = await admin.from('compliance_sources').select('*').eq('active', true).limit(60);
  if (!srcs || !srcs.length) return counts;
  for (const s of srcs) {
    counts.checked++; const mode = s.fetch_mode || 'direct'; const upd: Record<string, unknown> = { last_checked_at: new Date().toISOString() };
    let reachable = false; let sig = ''; let summary = ''; let textForStore: string | null = null; const asset = mode !== 'reader' && isAsset(s.url);
    if (mode === 'reader') { const f = await fetchReader(s.url); if (f.ok && f.text.length >= 200) { reachable = true; textForStore = f.text; sig = 'text:' + await sha256(f.text); } else upd.note = 'reader unreachable (' + (f.status || (f as any).err || '?') + ')'; }
    else if (asset) { const h = await assetInfo(s.url); if (h.ok) { reachable = true; sig = assetSignature(h); summary = 'The official published document was re-issued by the authority.'; } else upd.note = 'unreachable (' + (h.status || h.err || '?') + ')'; }
    else { const f = await fetchHtml(s.url); if (f.ok && f.text.length >= 200) { reachable = true; textForStore = f.text; sig = 'text:' + await sha256(f.text); } else upd.note = 'unreachable (' + (f.status || (f as any).err || '?') + ')'; }
    if (!reachable) { counts.unreachable++; await admin.from('compliance_sources').update(upd).eq('id', s.id); continue; }
    counts.reachable++; const firstBaseline = !s.last_signature; const diff = sig !== s.last_signature; upd.last_signature = sig; upd.note = 'ok'; let meaningful = false;
    if (!firstBaseline && diff) { if (asset) meaningful = true; else if (textForStore) { const out = await llm('You compare official UAE regulatory page snapshots. Decide if the NEW snapshot reflects a SUBSTANTIVE regulatory change (new edition, circular, effective date, changed requirement) vs cosmetic/nav/news noise. Reply ONLY JSON {"changed":true|false,"summary":"one sentence"}.', 'Authority: ' + s.authority + '\nTopic: ' + s.topic + '\nOLD signature: ' + s.last_signature + '\n\nNEW PAGE TEXT:\n' + textForStore, 300); if (out) { const m = out.match(/\{[\s\S]*\}/); if (m) { try { const pj = JSON.parse(m[0]); meaningful = pj.changed === true; summary = String(pj.summary || ''); } catch (_e) {} } } } }
    const shouldStore = !s.doc_path || diff;
    if (shouldStore) { if (asset) { const dl = await downloadAsset(s.url); if (dl.ok && dl.bytes && dl.bytes.length <= CAP) { const ext = (dl.contentType || '').includes('pdf') || /\.pdf|\.ashx/i.test(s.url) ? 'pdf' : 'bin'; const pth = await storeDoc(s.id, s.doc_path, dl.bytes, dl.contentType, ext); if (pth) { upd.doc_path = pth; upd.doc_bytes = dl.bytes.length; upd.doc_content_type = dl.contentType; upd.doc_downloaded_at = new Date().toISOString(); counts.downloaded++; } } } else if (textForStore) { const pth = await storeDoc(s.id, s.doc_path, textForStore, 'text/plain', 'txt'); if (pth) { upd.doc_path = pth; upd.doc_bytes = textForStore.length; upd.doc_content_type = 'text/plain'; upd.doc_downloaded_at = new Date().toISOString(); counts.downloaded++; } } }
    if (meaningful) { upd.last_changed_at = new Date().toISOString(); upd.last_summary = summary.slice(0, 500); const appendNote = '\n\n[Update ' + new Date().toISOString().slice(0, 10) + ' — ' + s.authority + ', ' + s.topic + '] ' + (summary || 'Governing document appears updated') + ' (source: ' + s.url + '). Verify before quoting.'; await queue({ agent: 'compliance', kind: 'compliance_update', status: 'pending', risk: 'high', title: s.authority + ' — ' + s.topic + ': possible code update', recommendation: 'review & append dated note to compliance reference', target_table: 'compliance_sources', target_id: String(s.id), detail: { authority: s.authority, topic: s.topic, url: s.url, summary, append_note: appendNote } }); counts.changes_proposed++; }
    await admin.from('compliance_sources').update(upd).eq('id', s.id);
  }
  return counts;
}

function money(n: number){ return 'AED ' + Math.round(Number(n) || 0).toLocaleString('en-US'); }
function esc(s: string){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
async function uploadReport(ext: string, body: string, contentType: string){ const p = 'weekly/' + Date.now() + '.' + ext; const { error } = await admin.storage.from('finance-reports').upload(p, new Blob([body], { type: contentType }), { contentType, upsert: true }); return error ? null : p; }
async function bookkeeping(){
  const wkStart = new Date(Date.now() - 7 * 864e5); const iso = wkStart.toISOString(); const wkIso = iso.slice(0, 10); const m30 = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
  const { data: exps } = await admin.from('expenses').select('*').eq('active', true);
  let monthlyAed = 0, weeklyAed = 0; const byCat: Record<string, number> = {}; const byVendor: any[] = [];
  for (const e of (exps || [])) { const amtAed = Number(e.amount) * (String(e.currency).toUpperCase() === 'AED' ? 1 : USD_AED); let m = 0; if (e.cadence === 'monthly') m = amtAed; else if (e.cadence === 'annual') m = amtAed / 12; else if (e.cadence === 'weekly') m = amtAed * 52 / 12; else if (e.cadence === 'one_off') { if (e.expense_date) { const dd = new Date(e.expense_date); if (dd >= wkStart && dd <= new Date()) weeklyAed += amtAed; } byVendor.push([e.vendor, e.category, e.cadence, e.amount + ' ' + e.currency, Math.round(amtAed) + ' AED (one-off)']); continue; } monthlyAed += m; weeklyAed += m * 12 / 52; byCat[e.category] = (byCat[e.category] || 0) + m; byVendor.push([e.vendor, e.category, e.cadence, e.amount + ' ' + e.currency, Math.round(m) + ' AED/mo']); }
  const { data: ent7 } = await admin.from('expense_entries').select('amount,currency').neq('category', 'Subscription').gte('charged_on', wkIso);
  let usage7 = 0; for (const e of (ent7 || [])) usage7 += Number(e.amount) * (String(e.currency).toUpperCase() === 'AED' ? 1 : USD_AED);
  const { data: ent30 } = await admin.from('expense_entries').select('amount,currency,vendor').neq('category', 'Subscription').gte('charged_on', m30);
  let usage30 = 0; const usageByVendor: Record<string, number> = {}; for (const e of (ent30 || [])) { const a = Number(e.amount) * (String(e.currency).toUpperCase() === 'AED' ? 1 : USD_AED); usage30 += a; usageByVendor[e.vendor] = (usageByVendor[e.vendor] || 0) + a; }
  for (const v of Object.keys(usageByVendor)) byVendor.push([v, 'Usage', 'last 30d', '—', Math.round(usageByVendor[v]) + ' AED']);
  weeklyAed += usage7; monthlyAed += usage30;
  const { data: tx } = await admin.from('transactions').select('reveal_fee,app_fee,fee_status,refund_status,revealed_at');
  let recAll = 0, colAll = 0, pendAll = 0, refAll = 0, recWk = 0;
  for (const t of (tx || [])) { const f = Number(t.reveal_fee ?? t.app_fee ?? 0); const refunded = (t.fee_status === 'refunded' || t.refund_status === 'approved'); if (refunded) { refAll += f; continue; } recAll += f; if (t.fee_status === 'paid') colAll += f; else pendAll += f; if (t.revealed_at && new Date(t.revealed_at) >= wkStart) recWk += f; }
  const [inqWk, quoteWk, dealWk, newCust, newSup] = await Promise.all([cnt('inquiries', (q) => q.gte('created_at', iso)), cnt('quotes', (q) => q.gte('created_at', iso)), cnt('transactions', (q) => q.gte('revealed_at', iso)), cnt('customers', (q) => q.gte('created_at', iso)), cnt('leads', (q) => q.gte('registration_submitted_at', iso))]);
  const netWk = recWk - weeklyAed;
  const kpis = { monthly_burn_aed: Math.round(monthlyAed), weekly_burn_aed: Math.round(weeklyAed), usage_7d_aed: Math.round(usage7), usage_30d_aed: Math.round(usage30), usage_by_vendor: usageByVendor, expenses_by_cat: byCat, expense_rows: byVendor, inq_wk: inqWk, quotes_wk: quoteWk, deals_wk: dealWk, new_customers_wk: newCust, new_suppliers_wk: newSup, fees_recognized_all: Math.round(recAll), fees_collected_all: Math.round(colAll), fees_pending_all: Math.round(pendAll), refunds_all: Math.round(refAll) };
  const { data: snap } = await admin.from('finance_snapshots').insert({ period_start: wkIso, period_end: new Date().toISOString().slice(0, 10), revenue_aed: Math.round(recWk), fees_collected_aed: Math.round(colAll), fees_pending_aed: Math.round(pendAll), refunds_aed: Math.round(refAll), supplier_sub_aed: 0, expenses_aed: Math.round(weeklyAed), net_aed: Math.round(netWk), kpis }).select('*').maybeSingle();
  return snap;
}
async function cfo(snap: any){
  const k = snap?.kpis || {};
  const { data: cfoTpl } = await admin.from('templates').select('content').eq('name', 'weekly_finance_report').maybeSingle();
  const themes = cfoTpl?.content ? ('\n\nThe founder wants these themes/emphases reflected in your commentary (do not output their layout literally, just cover them): ' + cfoTpl.content) : '';
  const { data: hist } = await admin.from('finance_snapshots').select('period_end,revenue_aed,expenses_aed,net_aed').order('id', { ascending: false }).limit(8);
  const { data: tx } = await admin.from('transactions').select('reveal_fee').limit(300);
  let avgFee = 0; if (tx && tx.length) avgFee = tx.reduce((a, t) => a + Number(t.reveal_fee || 0), 0) / tx.length;
  const monthlyBurn = k.monthly_burn_aed || 0; const dealsBE = avgFee > 0 ? Math.ceil(monthlyBurn / avgFee) : null;
  const ctx = JSON.stringify({ this_week: { revenue_aed: snap?.revenue_aed, expenses_aed: snap?.expenses_aed, net_aed: snap?.net_aed, kpis: k }, history: hist, avg_reveal_fee_aed: Math.round(avgFee), deals_per_month_to_break_even: dealsBE });
  const raw = await llm('You are the CFO of QuotesDone, a UAE B2B quotation marketplace (revenue = customer-paid reveal fees; solo founder). Write ONLY the CFO commentary as clean plain text for a founder: one short headline sentence, then a few short paragraphs covering this week, the trend, cash & burn (state monthly burn and how many deals/month to break even), the main risks, and exactly three specific recommendations. STRICT FORMAT RULES: plain prose only. Do NOT use markdown. No #, no asterisks, no pipe tables, no bullet symbols, no section labels in brackets. The KPI numbers and tables are rendered separately in the report, so do not re-list them as a table. All money in AED. Cash balance on hand is unknown — say so rather than guessing runway.' + themes, 'Figures (AED):\n' + ctx, 1500) || 'CFO narrative unavailable (AI not reachable this run).';
  const narrative = String(raw).replace(/^#+\s*/gm, '').replace(/\*\*/g, '').replace(/^\s*[-*•]\s+/gm, '').replace(/\|/g, ' ').trim();
  const period = (snap?.period_start || '') + ' → ' + (snap?.period_end || '');
  const paras = narrative.split(/\n{2,}/).map((p) => '<p>' + esc(p).replace(/\n/g, '<br>') + '</p>').join('');
  const neg = (Number(snap?.net_aed) || 0) < 0;
  const catRows = Object.entries(k.expenses_by_cat || {}).map(([c, v]) => '<tr><td>' + esc(c) + '</td><td class="r">' + money(v as number) + '/mo</td></tr>').join('') || '<tr><td colspan="2" style="color:#9ca3af">No recurring categories recorded.</td></tr>';
  const card = (l: string, v: string, n = false) => '<div class="card' + (n ? ' neg' : '') + '"><div class="l">' + l + '</div><div class="v">' + v + '</div></div>';
  const html = '<!doctype html><html><head><meta charset="utf-8"><title>QuotesDone Weekly Finance Report</title><style>'
    + 'body{font:13px/1.65 -apple-system,Segoe UI,Arial,sans-serif;color:#0A0A0A;margin:0;padding:34px 40px}'
    + '.hd{display:flex;align-items:center;justify-content:space-between;border-bottom:3px solid #14B8A6;padding-bottom:14px}'
    + '.hd h1{font-size:20px;margin:0;color:#0C2330}.hd .pd{color:#6b7280;font-size:12px;margin-top:3px}'
    + '.cards{display:flex;gap:10px;margin:20px 0 6px}'
    + '.card{flex:1;border:1px solid #e5e7eb;border-radius:10px;padding:12px 14px}'
    + '.card .l{font-size:10.5px;color:#6b7280;text-transform:uppercase;letter-spacing:.04em}'
    + '.card .v{font-size:20px;font-weight:800;color:#14B8A6;margin-top:5px}.card.neg .v{color:#dc2626}'
    + 'h2{font-size:14px;color:#0C2330;border-bottom:1px solid #e5e7eb;padding-bottom:5px;margin:26px 0 8px}'
    + 'p{margin:0 0 10px}table{width:100%;border-collapse:collapse;font-size:12.5px}'
    + 'th,td{border-bottom:1px solid #eef0f2;padding:7px 6px;text-align:left}th{background:#f8fafc;color:#0C2330}'
    + 'td.r,th.r{text-align:right}.foot{margin-top:28px;color:#9ca3af;font-size:11px;border-top:1px solid #eef0f2;padding-top:10px}'
    + '</style></head><body>'
    + '<div class="hd"><div><h1>QuotesDone — Weekly Finance Report</h1><div class="pd">Period: ' + period + ' · prepared by the CFO agent</div></div><img src="' + ASSET + '/qd_lockup_dark.png" style="height:34px"></div>'
    + '<div class="cards">' + card('Revenue (wk)', money(snap?.revenue_aed)) + card('Costs (wk)', money(snap?.expenses_aed)) + card('Net (wk)', money(snap?.net_aed), neg) + card('Monthly burn', money(k.monthly_burn_aed)) + '</div>'
    + '<h2>CFO commentary</h2>' + (paras || '<p>No commentary.</p>')
    + '<h2>Monthly costs by category</h2><table><tr><th>Category</th><th class="r">Monthly</th></tr>' + catRows + '</table>'
    + '<h2>This week, operationally</h2><table><tr><th>Metric</th><th class="r">Count</th></tr>'
    + '<tr><td>Inquiries</td><td class="r">' + (k.inq_wk || 0) + '</td></tr><tr><td>Quotes</td><td class="r">' + (k.quotes_wk || 0) + '</td></tr><tr><td>Deals (reveals)</td><td class="r">' + (k.deals_wk || 0) + '</td></tr><tr><td>New customers</td><td class="r">' + (k.new_customers_wk || 0) + '</td></tr><tr><td>New suppliers</td><td class="r">' + (k.new_suppliers_wk || 0) + '</td></tr></table>'
    + '<div class="foot">Revenue = customer-paid reveal fees recorded on the platform. Usage costs are summed from logged receipts; subscriptions are counted once via recurring lines. Cash on hand is not tracked. Generated by QuotesDone · quotesdone.com</div>'
    + '</body></html>';
  const stamp = String(snap?.period_end || new Date().toISOString().slice(0,10));
  const pdf = await callFn('make_pdf', { html, name: 'QuotesDone_Finance_' + stamp, folder: 'weekly', bucket: 'finance-reports' });
  const summaryRows: any[][] = [['QuotesDone Weekly Finance Report'], ['Period', period], [], ['KPIs (AED)'], ['Revenue (wk)', snap?.revenue_aed], ['Costs (wk)', snap?.expenses_aed], ['Net (wk)', snap?.net_aed], ['Monthly burn', k.monthly_burn_aed], [], ['Operations (this week)'], ['Inquiries', k.inq_wk], ['Quotes', k.quotes_wk], ['Deals', k.deals_wk], ['New customers', k.new_customers_wk], ['New suppliers', k.new_suppliers_wk], [], ['Fees collected (all-time)', k.fees_collected_all], ['Fees pending (all-time)', k.fees_pending_all], ['Refunds (all-time)', k.refunds_all]];
  const costRows: any[][] = [['Vendor', 'Category', 'Cadence', 'Listed', 'Normalized'], ...((k.expense_rows as any[]) || [])];
  const xlsx = await callFn('make_xlsx', { sheets: [{ name: 'Summary', rows: summaryRows }, { name: 'Costs', rows: costRows }], name: 'QuotesDone_Finance_' + stamp, folder: 'weekly', bucket: 'finance-reports' });
  const htmlPath = await uploadReport('html', html, 'text/html');
  const pdfUrl = (pdf && pdf.url) ? pdf.url : null; const xlsxUrl = (xlsx && xlsx.url) ? xlsx.url : null;
  const { data: rep } = await admin.from('finance_reports').insert({ period_start: snap?.period_start, period_end: snap?.period_end, kind: 'weekly', summary: narrative.slice(0, 1200), kpis: k, html_path: htmlPath, xlsx_path: (xlsx && xlsx.path) || null, pdf_path: (pdf && pdf.path) || null }).select('id').maybeSingle();
  let emailed = false; const al = await sec('admin_emails'); const owner = String(al || 'management@quotesdone.com').split(',')[0].trim();
  if (owner) { const headline = narrative.split(/\n/)[0].slice(0, 220); const links = (pdfUrl ? ('\n\n📄 Full PDF report: ' + pdfUrl) : '') + (xlsxUrl ? ('\n📊 Excel workbook: ' + xlsxUrl) : ''); const body = 'Your weekly finance report is ready (' + period + ').\n\n' + headline + '\n\nThis week: revenue ' + money(snap?.revenue_aed) + ', costs ' + money(snap?.expenses_aed) + ', net ' + money(snap?.net_aed) + ', monthly burn ' + money(k.monthly_burn_aed) + '.' + links + '\n\nThe full breakdown, tables and commentary are in the attached PDF. You can also open the Finance tab in your admin for the archive.'; await admin.from('notifications').insert({ type: 'cfo_report', to_email: owner, to_role: 'admin', channel: 'email', subject: 'QuotesDone weekly finance report — ' + (snap?.period_end || ''), body }); emailed = true; }
  return { report_id: rep?.id || null, emailed, pdf: !!pdfUrl, xlsx: !!xlsxUrl };
}
async function finance(){ const snap = await bookkeeping(); const r = await cfo(snap); return { net_aed: snap?.net_aed, revenue_aed: snap?.revenue_aed, expenses_aed: snap?.expenses_aed, report_id: r.report_id, emailed: r.emailed, pdf: r.pdf, xlsx: r.xlsx }; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'agents');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const job = String(body.job || '');
    const { data: run } = await admin.from('agent_runs').insert({ agent: job }).select('id').maybeSingle();
    let counts: Record<string, unknown> = {}; let status = 'ok'; let note = '';
    try { if (job === 'onboarding') counts = await onboarding(); else if (job === 'compliance') counts = await compliance(); else if (job === 'followup') counts = await followup(); else if (job === 'finance') counts = await finance(); else if (job === 'marketing') counts = await marketing(); else if (job === 'category_sales') counts = await categorySales(); else if (job === 'bd_outreach') counts = await bdOutreach(); else if (job === 'it_health') counts = await itHealth(); else if (job === 'security') counts = await security(); else { status = 'error'; note = 'unknown_job'; } } catch (e) { status = 'error'; note = String((e as Error)?.message || e); }
    if (run?.id) await admin.from('agent_runs').update({ finished_at: new Date().toISOString(), status, counts, note }).eq('id', run.id);
    return J({ ok: status === 'ok', job, counts, note });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

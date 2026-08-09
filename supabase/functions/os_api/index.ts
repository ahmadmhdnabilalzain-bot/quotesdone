// os_api — backend for QuotesDone OS. JWT-gated; owner/admin only (or a read-only x-os-key preview bypass). + audit trail. + secretary console passthrough.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-os-key', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
const esc = (s: string) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' } as any)[c]);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false;
  const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner', 'admin'].includes(String(data || '').toLowerCase())) return true; } catch (_e) { /* ignore */ }
  try { const { data } = await admin.from('app_secrets').select('value').eq('key', 'admin_emails').maybeSingle(); const list = String((data as any)?.value || '').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) { /* ignore */ }
  return false;
}

const WS: Record<string, string> = {
  'ws.exec': 'fn_ws_exec', 'ws.marketplace': 'fn_ws_marketplace', 'ws.customers': 'fn_ws_customers',
  'ws.operations': 'fn_ws_operations', 'ws.ai': 'fn_ws_ai', 'ws.knowledge': 'fn_ws_knowledge',
  'ws.documents': 'fn_ws_documents', 'ws.analytics': 'fn_ws_analytics', 'ws.company': 'fn_ws_company',
  'ws.finance': 'fn_ws_finance', 'ws.agents': 'fn_ws_agents', 'ws.marketing': 'fn_ws_marketing',
  'ws.ea': 'fn_ws_ea', 'ws.reports': 'fn_ws_reports', 'ws.strategy': 'fn_ws_strategy', 'ws.governance': 'fn_ws_governance',
  'ws.fraud': 'fn_ws_fraud', 'ws.refunds': 'fn_ws_refunds', 'ws.intelligence': 'fn_ws_intelligence',
  'ws.exec_home': 'fn_ws_exec_home', 'ws.company_os': 'fn_ws_company_os',
  'ws.notifications': 'fn_ws_notifications', 'ws.live_company': 'fn_ws_live_company',
};
// ---- ACTION CLASSIFICATION (2 Aug 2026, Phase 1 hardening) -------------------------------------
// Every action this function will route, classified, with no default. It feeds two independent
// gates: the preview-key allowlist below, and Observe/Control Mode in the database
// (public.control_mode_action). scripts/checks/os_action_classification.mjs fails the build if a
// dispatched action is missing here, or if this table lists an action that no longer exists.
//
//   read_only    - performs no persistent business write
//   mutating     - requires an open Control Mode session
//   mode_control - Control Mode's own plumbing, which cannot require what it grants
//
// AN ACTION ABSENT FROM THIS TABLE IS REFUSED. Absence is not permission. The first version of this
// gate treated "unregistered" as "read-only", and it was wrong twice on the day it shipped:
// secretary_chat drives an agent that acts and was unregistered, so it was ungated; and `record`
// was registered as mutating although fn_os_record is STABLE, so opening any record would have
// demanded a phone code. Both are correct below.
type ActionClass = 'read_only' | 'mutating' | 'mode_control';
const ACTION_CLASS: Record<string, ActionClass> = {
  control_mode_status: 'mode_control', control_mode_open: 'mode_control',
  control_mode_close: 'mode_control', control_mode_challenge: 'mode_control',

  inbox_send: 'mutating', fraud_resolve: 'mutating', refund_resolve: 'mutating',
  prompt_approve: 'mutating', prompt_rollback: 'mutating', prompt_gate: 'mutating',
  comment_add: 'mutating', review_decide: 'mutating', blog_publish: 'mutating',
  knowledge_dispatch: 'mutating', knowledge_refresh: 'mutating', exam_run: 'mutating',
  exam_revert: 'mutating', secretary_chat: 'mutating',

  ping: 'read_only', dashboard: 'read_only', viz: 'read_only', suppliers_board: 'read_only',
  rfq_board: 'read_only', customers_board: 'read_only', agents_board: 'read_only',
  activity: 'read_only', nav: 'read_only', inbox: 'read_only', search: 'read_only',
  record: 'read_only', files: 'read_only', file: 'read_only', prompt_view: 'read_only',
  memory: 'read_only', drilldown: 'read_only', report_recommend_approve: 'mutating',
  simulate: 'mutating', simulation_approve: 'mutating',
  marketing_studio: 'read_only', knowledge_gaps: 'read_only', exam_summary: 'read_only',
  knowledge_export: 'read_only', extract_doc: 'read_only', report_pdf: 'read_only',
  'ws.suppliers': 'read_only', 'ws.supplier': 'read_only', 'ws.customer': 'read_only',
  'ws.agent': 'read_only', 'ws.rfq': 'read_only', 'ws.exec': 'read_only',
  'ws.marketplace': 'read_only', 'ws.customers': 'read_only', 'ws.operations': 'read_only',
  'ws.ai': 'read_only', 'ws.knowledge': 'read_only', 'ws.documents': 'read_only',
  'ws.analytics': 'read_only', 'ws.company': 'read_only', 'ws.finance': 'read_only',
  'ws.agents': 'read_only', 'ws.marketing': 'read_only', 'ws.ea': 'read_only',
  'ws.reports': 'read_only', 'ws.strategy': 'read_only', 'ws.governance': 'read_only',
  'ws.fraud': 'read_only', 'ws.refunds': 'read_only', 'ws.intelligence': 'read_only',
  'ws.exec_home': 'read_only', 'ws.company_os': 'read_only', 'ws.notifications': 'read_only', 'ws.live_company': 'read_only',
  transcribe: 'read_only',
};

const OSAPI_MUTATIONS = new Set(Object.keys(ACTION_CLASS).filter((a) => ACTION_CLASS[a] === 'mutating'));
// What the x-os-key preview bypass may reach. Narrower than read_only on purpose: two actions read
// before they do anything, but still cost something a static string should not be able to spend.
//   report_pdf   - renders and stores a PDF object in the finance-reports bucket
//   extract_doc  - hands caller-supplied bytes to extract_text, which is a paid OCR call
// Everything else classified read_only is allowed; anything mutating, mode_control or unclassified
// is not, so the bypass cannot reach a handler added later without someone classifying it first.
//   transcribe   - hands caller-supplied audio to the transcribe function, a paid speech-to-text call
const BYPASS_DENY = new Set(['report_pdf', 'extract_doc', 'transcribe']);
const READONLY = new Set(
  Object.keys(ACTION_CLASS).filter((a) => ACTION_CLASS[a] === 'read_only' && !BYPASS_DENY.has(a)),
);

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    const authHeader = req.headers.get('Authorization') || '';
    let email = '';
    // OS BYPASS FIX 28 Jul 2026. os_ops was hardened on 27 Jul; this twin was missed. A single static
    // app_secrets.os_bypass_key in an x-os-key header skipped the entire admin identity check on a
    // function that runs with verify_jwt:false, so anyone holding that string could send from the
    // inbox, resolve a fraud case or a refund, approve or roll back a prompt, publish a blog post,
    // dispatch knowledge, run or revert an exam, comment or decide a review - and the audit row named
    // 'os-preview@quotesdone.com', a fabricated person, so the log read as if a colleague had done it.
    // Nothing reads through this key and no app_secrets row for it exists today, which is the only
    // reason the hole was inert: creating that row alone would have opened it. It is now read-only
    // (see the READONLY gate below) and it is recorded under its own name, never as an email address.
    let viaBypass = false;
    // Hoisted out of the else block below. It used to be read from `u` further down, in
    // control_mode_open, where `u` is out of scope - a ReferenceError caught by the outer try/catch
    // and returned as an opaque 500, which meant Control Mode could never actually be opened through
    // this function even though the database function behind it worked. Found by `deno check`, which
    // now runs in CI for exactly this reason.
    let userId: string | null = null;
    const osKey = req.headers.get('x-os-key') || '';
    if (osKey && osKey === (await sec('os_bypass_key'))) { email = 'os_bypass_key (no human identity)'; viaBypass = true; }
    else {
      const token = authHeader.replace(/^Bearer\s+/i, '').trim();
      if (!token) return J({ error: 'unauthorized' }, 401);
      const { data: u, error: uerr } = await admin.auth.getUser(token);
      email = u?.user?.email || '';
      userId = (u?.user?.id as string) || null;
      if (uerr || !email) return J({ error: 'unauthorized' }, 401);
      if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);
    }

    const body = await req.json().catch(() => ({} as any));
    const action = (body?.action as string) || 'ping';

    // ---- FAIL CLOSED ON AN UNCLASSIFIED ACTION (2 Aug 2026, Phase 1 hardening) -----------------
    // First gate after identity, before anything else looks at the action. An action nobody has
    // classified is an action nobody has thought about, and the asymmetry is the whole argument:
    // refusing a read costs one redeploy, allowing an unreviewed mutation costs an incident. The
    // database gate refuses the same case independently, so both layers have to be forgotten at once
    // for something ungated to run.
    if (!ACTION_CLASS[action]) {
      try {
        await admin.from('os_audit_log').insert({ actor: email, action,
          detail: { refused: 'action_classification_required', via_bypass: viaBypass } });
      } catch (_e) { /* audit must never break the refusal */ }
      return J({ error: 'action_classification_required', action,
        hint: 'This action is not classified. Add it to ACTION_CLASS in os_api and to public.control_mode_action, then redeploy. Until then it is refused.' }, 403);
    }

    // ---- audit trail for os_api mutations (never block) ----
    // A non-read action arriving on the preview key is audited here too, even when it is not one of
    // OSAPI_MUTATIONS: an attempt to mutate with the static key is exactly the event worth having on
    // record, so it is logged first and refused second.
    if (OSAPI_MUTATIONS.has(action) || (viaBypass && !READONLY.has(action))) {
      try {
        const det: any = { ...body }; delete det.action;
        const ent = String(body?.subject_type || (body?.transaction_id ? 'transactions' : '') || (body?.key ? 'prompt' : ''));
        const eid = String(body?.subject_id ?? body?.transaction_id ?? body?.id ?? body?.key ?? '');
        await admin.from('os_audit_log').insert({ actor: email, action, entity: ent || null, entity_id: eid || null, detail: det });
      } catch (_e) { /* audit must never break the operation */ }
    }
    // Deliberately after the audit insert, for the reason given above.
    if (viaBypass && !READONLY.has(action)) return J({ error: 'forbidden', hint: 'the x-os-key preview key is read-only — sign in with an admin account to make changes' }, 403);

    // ---- OBSERVE MODE / CONTROL MODE (2 Aug 2026, Phase 1.4) ----------------------------------
    // The founder's stated architecture is "monitor and issue rare high-level instructions". This
    // function exposes 14 actions that approve suppliers, resolve refunds and fraud, publish public
    // content, change agent prompts and send mail as the company - with, until now, no distinction
    // between looking and acting. One stolen session or one mis-tap on a phone was enough.
    //
    // Observe Mode is not a setting; it is the ABSENCE of a Control Mode session, so it is where you
    // are unless you did something deliberate. Control Mode is short-lived (15 min), needs a fresh
    // phone code that cannot be replayed, and needs a written reason stored beside whatever you then
    // change. Both the grant and every refusal go into control_mode_audit.
    if (action === 'control_mode_status') {
      const { data, error } = await admin.rpc('fn_control_mode_status', { p_actor_email: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, user: email, data });
    }
    // Step one of two. The code is minted here, hashed before it is stored, and sent to the number
    // registered against this admin identity in app_secrets - it is not taken from the request, so a
    // caller cannot nominate the phone their own code goes to. What comes back to the browser is a
    // challenge id, a one-time nonce and the last four digits: never the number, never the code.
    if (action === 'control_mode_challenge') {
      const buf = new Uint32Array(1);
      crypto.getRandomValues(buf);                       // not Math.random - this is a credential
      const code = String(100000 + (buf[0] % 900000));
      const { data: h, error: herr } = await admin.rpc('fn_otp_hash', { p_code: code });
      if (herr) return J({ error: herr.message }, 500);
      const { data, error } = await admin.rpc('fn_control_mode_challenge_start', {
        p_actor_email: email, p_code_hash: String(h || ''),
        p_ip: req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null,
      });
      if (error) return J({ error: error.message }, 500);
      // deno-lint-ignore no-explicit-any
      const r = data as any;
      if (!r?.ok) return J({ error: r?.error || 'challenge_failed', hint: r?.message }, 403);
      let delivered = false; let via = ''; let why = '';
      try {
        const sent = await fetch(`${BASE}/send_whatsapp`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          // 4 Aug 2026: this sent the code as freeform text only. WhatsApp refuses freeform
          // business-initiated messages outside the 24-hour window the recipient opens by messaging
          // us (Twilio 63016), and the Control Mode phone has never messaged this number - so the
          // code has never been deliverable, and `delivered:false` below was the only trace. The
          // approved authentication template is now tried first; the freeform text remains as the
          // in-session fallback and is what still arrives while a template awaits Meta approval.
          body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), to: r.phone,
            templateKey: 'control_mode_code', vars: { '1': code },
            body: `QuotesDone Control Mode code: ${code}\nValid for ${r.minutes} minutes. If you did not ask for this, someone else is signed in to your console.` }),
        });
        // deno-lint-ignore no-explicit-any
        const sr = (await sent.json().catch(() => ({}))) as any;
        delivered = !!sr?.ok; via = String(sr?.via || ''); why = String(sr?.error || '');
      } catch (e) { why = String((e as Error)?.message || 'send_whatsapp unreachable'); }
      return J({ ok: true, user: email, data: {
        challenge_id: r.challenge_id, nonce: r.nonce, phone_tail: r.phone_tail,
        expires_at: r.expires_at, delivered, via, why,
        // "Could not deliver" with no reason is what let this sit unexplained: Twilio 63016 means
        // the freeform code was sent outside WhatsApp's 24-hour window, which is a different
        // problem from a wrong number or a dead credential and needs a different fix.
        message: delivered ? `Code sent to the number ending ${r.phone_tail}${via ? ' (' + via + ')' : ''}.`
                           : `Could not deliver the code to the number ending ${r.phone_tail}.` +
                             (/63016/.test(why)
                               ? ' WhatsApp only accepts a plain-text message within 24 hours of that phone messaging us. Send any WhatsApp message to the QuotesDone number from that handset, then request the code again.'
                               : why ? ` Twilio said: ${why.slice(0, 160)}` : ' Check WhatsApp sending before retrying.'),
      } }, 200);
    }
    // Step two. Challenge id + nonce + code, all three, all bound to this admin identity and to the
    // purpose 'control_mode'. A sign-in code or a customer verification code is not accepted here -
    // that was the whole defect in the first version.
    if (action === 'control_mode_open') {
      const { data, error } = await admin.rpc('fn_control_mode_open', {
        p_actor_email: email, p_reason: String(body?.reason || ''),
        p_challenge_id: String(body?.challenge_id || '') || null,
        p_nonce: String(body?.nonce || ''), p_code: String(body?.code || ''),
        p_user_id: userId,
        p_ip: req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null,
        p_ua: req.headers.get('user-agent') || null,
      });
      if (error) return J({ error: error.message }, 500);
      // deno-lint-ignore no-explicit-any
      const r = data as any;
      return J(r?.ok ? { ok: true, user: email, data: r } : { error: r?.error || 'control_mode_denied', hint: r?.message, attempts_left: r?.attempts_left }, r?.ok ? 200 : 403);
    }
    if (action === 'control_mode_close') {
      const { data, error } = await admin.rpc('fn_control_mode_close', { p_actor_email: email });
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, user: email, data });
    }
    // The gate itself. public.control_mode_action decides; an action it does not know is refused
    // there too, independently of the ACTION_CLASS check above.
    //
    // The failure path matters as much as the success path. This used to swallow any error and
    // continue, which meant a database hiccup silently downgraded every mutation to ungated. Now a
    // failed lookup is only survivable for something this file already knows is read_only; anything
    // mutating is refused until the gate can actually answer.
    try {
      const { data: gate, error: gerr } = await admin.rpc('fn_control_mode_require', { p_actor_email: email, p_action: action });
      if (gerr) throw new Error(gerr.message);
      // deno-lint-ignore no-explicit-any
      const g = gate as any;
      // FAIL CLOSED 3 Aug 2026 (audit 3.3). This was `if (g && g.allowed === false)` - "allow
      // unless told no". A null or absent RPC payload WITH NO ERROR fell straight through to the
      // handler ungated, which is the exact shape this whole work existed to remove. The gate must
      // now say allowed===true out loud. A missing payload is treated identically to a failed
      // lookup below: refused for anything mutating, survivable only for something this file
      // already knows is read_only.
      if (!g || typeof g !== 'object') {
        if (ACTION_CLASS[action] !== 'read_only') {
          return J({ error: 'control_mode_unavailable', mode: 'observe',
                     hint: 'The Control Mode gate returned nothing, so this change is refused. Try again in a moment.' }, 503);
        }
      } else if (g.allowed !== true) {
        return J({ error: g.error || 'control_mode_required', mode: 'observe',
                   hint: g.message || 'This changes something. Open Control Mode with a phone code and a reason first.' }, 403);
      }
    } catch (_e) {
      if (ACTION_CLASS[action] !== 'read_only') {
        return J({ error: 'control_mode_unavailable', mode: 'observe',
                   hint: 'The Control Mode gate could not be checked, so this change is refused. Try again in a moment.' }, 503);
      }
    }

    if (action === 'ping') return J({ ok: true, user: email });
    if (action === 'dashboard') { const { data, error } = await admin.rpc('fn_os_command'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'viz') { const { data, error } = await admin.rpc('fn_os_dashboard_viz'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'suppliers_board') { const { data, error } = await admin.rpc('fn_suppliers_board', { p_search: String(body?.search || ''), p_sector: String(body?.sector || ''), p_limit: Number(body?.limit || 60), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'rfq_board') { const { data, error } = await admin.rpc('fn_rfq_board', { p_search: String(body?.search || ''), p_limit: Number(body?.limit || 80), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'customers_board') { const { data, error } = await admin.rpc('fn_customers_board', { p_search: String(body?.search || ''), p_limit: Number(body?.limit || 80), p_offset: Number(body?.offset || 0) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'agents_board') { const { data, error } = await admin.rpc('fn_agents_board'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'activity') { const { data, error } = await admin.rpc('fn_entity_activity', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'comment_add') { const { data, error } = await admin.rpc('fn_entity_comment_add', { p_entity: String(body?.entity || ''), p_id: String(body?.id || ''), p_author: email, p_body: String(body?.body || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'nav') { const { data, error } = await admin.rpc('fn_os_nav'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'ws.suppliers') { const { data, error } = await admin.rpc('fn_ws_suppliers', { p: body?.params || {} }); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'ws.supplier') { const { data, error } = await admin.rpc('fn_ws_supplier_360', { p_id: Number(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.customer') { const { data, error } = await admin.rpc('fn_ws_customer_360', { p_id: String(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.agent') { const { data, error } = await admin.rpc('fn_ws_agent_ops', { p_agent: String(body?.key) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'ws.rfq') { const { data, error } = await admin.rpc('fn_ws_rfq_360', { p_id: String(body?.id) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'inbox') { const { data, error } = await admin.rpc('fn_inbox_list'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'inbox_send') { const { data, error } = await admin.rpc('fn_inbox_send', { p_id: Number(body?.id), p_body: String(body?.body || ''), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'search') { const { data, error } = await admin.rpc('fn_os_search', { p_q: String(body?.q || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    // The company's memory, asked about a SUBJECT and scoped to a PERIOD — "every decision about
    // Marketing", "why did we reject Supplier X", "when did AI change pricing", "lessons from February".
    // Click a number in a report: why it moved, against what target, and who contributed.
    // Approve a recommendation without leaving the report it came from.
    if (action === 'report_recommend_approve') { const { data, error } = await admin.rpc('fn_report_recommendation_approve', { p_report_id: Number(body?.report_id), p_index: Number(body?.index || 0), p_by: email, p_source: String(body?.source || 'exec_reports') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    // Screen 16 — "What if?". A natural-language scenario goes to fn_what_if, which records the
    // simulation and returns its projection. Mutating: it writes a simulations row.
    if (action === 'simulation_approve') { const { data, error } = await admin.from('agent_actions').insert({ agent: 'strategy_ai', kind: 'simulation_approved', status: 'approved', risk: 'medium', title: String(body?.scenario || 'Simulated action'), recommendation: JSON.stringify(body?.result || {}).slice(0, 4000), target_table: 'simulations', decided_by: email, decided_at: new Date().toISOString() }).select('id').maybeSingle(); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'simulate') { const { data, error } = await admin.rpc('fn_what_if', { p_question: String(body?.question || body?.scenario || ''), p_change: body?.change || {} }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'drilldown') { const { data, error } = await admin.rpc('fn_report_drilldown', { p_metric: String(body?.metric || ''), p_days: Number(body?.days || 30) }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'memory') {
      const { data, error } = await admin.rpc('fn_os_memory', {
        p_q: body?.topic != null ? String(body.topic) : (body?.subject != null ? String(body.subject) : null),
        p_from: body?.from ? String(body.from) : null,
        p_to: body?.to ? String(body.to) : null,
      });
      if (error) return J({ error: error.message }, 500); return J({ ok: true, data });
    }
    if (action === 'record') { const { data, error } = await admin.rpc('fn_os_record', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'secretary_chat') {
      const payload: any = { __secret: await sec('cred_fn_os_api'), actor_email: email };
      for (const k of ['message','history','attachments','confirm_token','decision']) if (body?.[k] !== undefined) payload[k] = body[k];
      const r = await fetch(`${BASE}/secretary_act`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd });
    }
    // The founder speaking to the OS. Same shape as extract_doc: caller-supplied bytes to a paid
    // service, so it is on BYPASS_DENY and a static preview key cannot spend against it.
    if (action === 'transcribe') {
      const r = await fetch(`${BASE}/transcribe`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), b64: String(body?.b64 || ''), mime: String(body?.mime || 'audio/webm') }) });
      const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd });
    }
    if (action === 'extract_doc') {
      const r = await fetch(`${BASE}/extract_text`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), filename: String(body?.filename || 'document'), mime: String(body?.mime || ''), b64: String(body?.b64 || '') }) });
      const jd = await r.json().catch(() => ({})); return J({ ok: true, data: jd });
    }

    if (action === 'fraud_resolve') {
      const { data, error } = await admin.rpc('fn_fraud_resolve', { p_subject_type: String(body?.subject_type || ''), p_subject_id: String(body?.subject_id || ''), p_action: String(body?.op || 'dismiss'), p_by: email });
      if (error) return J({ error: error.message }, 500); return J({ ok: true, data });
    }
    if (action === 'refund_resolve') {
      const fwd = authHeader || ('Bearer ' + (await sec('os_service_jwt')));
      const r = await fetch(`${BASE}/refunds_api`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': fwd }, body: JSON.stringify({ action: 'resolve', transaction_id: body?.transaction_id, decision: String(body?.op || ''), note: body?.note || '' }) });
      const jd = await r.json().catch(() => ({})); if (!r.ok) return J({ error: jd?.error || ('refunds_api ' + r.status) }, 502); return J({ ok: true, data: jd });
    }

    if (action === 'files') { const { data, error } = await admin.rpc('fn_entity_files', { p_entity: String(body?.entity || ''), p_id: String(body?.id || '') }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'file') { const bucket = String(body?.bucket || 'supplier-docs'); const path = String(body?.path || '').replace(/^\/+/, ''); if (!path) return J({ error: 'path_required' }, 400); const { data, error } = await admin.storage.from(bucket).createSignedUrl(path, 300); if (error || !data?.signedUrl) return J({ error: error?.message || 'could_not_sign' }, 500); return J({ ok: true, data: { url: data.signedUrl } }); }
    if (action === 'report_pdf') {
      const id = Number(body?.id); const src = String(body?.src || 'board'); let title = 'Report'; let text = '';
      if (src === 'exec') { const { data } = await admin.from('exec_reports').select('officer,period,summary,findings,recommendations').eq('id', id).maybeSingle(); if (!data) return J({ error: 'not_found' }, 404); title = `${(data as any).officer} — ${(data as any).period}`; text = String((data as any).summary || ''); if ((data as any).findings) text += '\n\nFINDINGS\n' + JSON.stringify((data as any).findings, null, 2); if ((data as any).recommendations) text += '\n\nRECOMMENDATIONS\n' + JSON.stringify((data as any).recommendations, null, 2); }
      else { const { data } = await admin.from('board_reports').select('title,body').eq('id', id).maybeSingle(); if (!data) return J({ error: 'not_found' }, 404); title = String((data as any).title || 'Report'); text = String((data as any).body || ''); }
      let hb = ''; for (const raw of text.split('\n')) { const t = raw.replace(/\s+$/, ''); if (!t) { hb += '<div style="height:6px"></div>'; continue; } if (/^[=\-_]{3,}$/.test(t)) continue; if (t === t.toUpperCase() && /[A-Z]/.test(t) && t.length < 64) hb += `<h3>${esc(t)}</h3>`; else hb += `<p>${esc(t)}</p>`; }
      const html = `<html><head><title>${esc(title)}</title></head><body><h1>${esc(title)}</h1>${hb}</body></html>`;
      const r = await fetch(`${BASE}/make_pdf`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), html, title, name: 'report-' + id, bucket: 'finance-reports', folder: 'reports' }) });
      const jd = await r.json().catch(() => ({})); if (!jd?.url) return J({ error: jd?.error || 'render_failed' }, 500); return J({ ok: true, data: { url: jd.url, path: jd.path } });
    }

    if (action === 'prompt_view') {
      const r = await fetch(`${BASE}/prompt_gate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), action: 'view', key: String(body?.key || ''), version: body?.version }) });
      const jd = await r.json().catch(() => ({})); return J({ ok: true, data: jd });
    }
    if (action === 'prompt_gate') {
      const p = fetch(`${BASE}/prompt_gate`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), action: 'gate', key: String(body?.key || ''), version: body?.version }) });
      try { (globalThis as any).EdgeRuntime?.waitUntil?.(p); } catch (_e) { /* ignore */ }
      return J({ ok: true, data: { queued: true } });
    }
    if (action === 'prompt_approve') { const { data, error } = await admin.rpc('fn_prompt_approve_draft', { p_key: String(body?.key || ''), p_version: Number(body?.version), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'prompt_rollback') { const { data, error } = await admin.rpc('fn_prompt_rollback', { p_key: String(body?.key || ''), p_to_version: Number(body?.to_version), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'marketing_studio') { const { data, error } = await admin.rpc('fn_marketing_studio'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'review_decide') { const { data, error } = await admin.rpc('fn_review_decide', { p_kind: String(body?.kind || ''), p_ref_id: Number(body?.ref_id), p_decision: String(body?.decision || ''), p_comment: String(body?.comment || ''), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'blog_publish') { const { data, error } = await admin.rpc('fn_marketing_blog_publish', { p_id: String(body?.id || ''), p_published: Boolean(body?.published), p_by: email }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }

    if (action === 'knowledge_gaps') { const { data, error } = await admin.rpc('fn_knowledge_gaps'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'knowledge_dispatch') { const { data, error } = await admin.rpc('fn_dispatch_agent_knowledge_gaps'); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'knowledge_refresh') { const r = await fetch(`${BASE}/gen_category_knowledge`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), slug: String(body?.slug || '') }) }); const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd }); }
    if (action === 'exam_summary') { const { data, error } = await admin.rpc('fn_knowledge_exam_summary'); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }
    if (action === 'exam_run') { const r = await fetch(`${BASE}/knowledge_exam`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_api'), agent_key: body?.agent_key || undefined, generate: Number(body?.generate ?? 6), answer: Number(body?.answer ?? 8) }) }); const jd = await r.json().catch(() => ({})); if (!r.ok && jd?.error) return J({ error: jd.error }, 502); return J({ ok: true, data: jd }); }
    if (action === 'exam_revert') { const { data, error } = await admin.rpc('fn_exam_revert', { p_agent_key: body?.agent_key || null }); if (error) return J({ error: error.message }, 500); return J({ ok: true, data }); }
    if (action === 'knowledge_export') {
      const ak = String(body?.agent_key || '').trim();
      let sel = admin.from('agent_knowledge').select('agent_key,topic,content,priority,updated_at').order('agent_key').order('priority', { ascending: false });
      if (ak) sel = sel.in('agent_key', ak.startsWith('cat:') ? [ak] : [ak, 'cat:' + ak]);
      const { data, error } = await sel; if (error) return J({ error: error.message }, 500);
      const rows = (data as any[]) || [];
      const groups: Record<string, any[]> = {}; for (const r of rows) { (groups[r.agent_key] = groups[r.agent_key] || []).push(r); }
      let md = '# QuotesDone — Agent Knowledge Export\n\n' + (ak ? 'Agent: `' + ak + '`\n' : 'All agents\n') + 'Generated: ' + new Date().toISOString() + '\nItems: ' + rows.length + '\n';
      for (const [key, items] of Object.entries(groups)) {
        md += '\n\n---\n\n## ' + key + '  (' + items.length + ' item' + (items.length === 1 ? '' : 's') + ')\n';
        for (const it of items) { md += '\n**' + (it.topic || 'general') + '**' + (String(it.topic || '').startsWith('exam:') ? ' _(exam-verified)_' : '') + '  \n' + String(it.content || '').trim() + '\n'; }
      }
      const filename = 'knowledge-' + (ak ? ak.replace(/[^a-z0-9-]+/gi, '_') : 'all-agents') + '.md';
      return J({ ok: true, data: { filename, markdown: md, count: rows.length } });
    }

    if (WS[action]) { const { data, error } = await admin.rpc(WS[action]); if (error) return J({ error: error.message }, 500); return J({ ok: true, user: email, data }); }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});

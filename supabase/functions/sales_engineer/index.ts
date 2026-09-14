// sales_engineer — the Sales Engineer seat's runtime. The company's third agent, and the first one
// that has a health route.
//
// WHY IT EXISTS. The founder, 9 September 2026: "Sales Engineer and Customer Support report directly
// to the actual new CEO." This seat owns customer intake, document interpretation, technical scope,
// quote readiness, supplier identity and capability verification, supplier-safe RFQ construction,
// matching and dispatch — and keeps ownership until the outcome is VERIFIED.
//
// NO MODEL CALL, ANYWHERE IN HERE, and every action below was chosen so that is not a limitation.
// Measured 9 Sep 2026: all 8 routes in llm_route_health carry open_until = 2126-08-15 under the
// founder's own hold, and fn_kernel_paid_provider_gate denies GLOBALLY while any route is held. So a
// model-dependent runtime would be a dead one today.
//
// That constraint turned out to be clarifying rather than costly. The build prompt is explicit:
// "Use deterministic code for arithmetic, units, schema validation, permissions, budget
// reservations, state transitions and mandatory exclusions." An intake obligation set is exactly
// that — which of a sector's questions remain unresolved is a set difference over a field catalogue,
// not a judgement. The model's judgement belongs in interpreting a drawing and weighing conflicting
// evidence, which is the half that waits for the hold to lift. What is here does not.
//
// WHAT IS DELIBERATELY ABSENT, so nobody mistakes silence for capability: this function does not
// dispatch, does not email, does not write a supplier's verification state, and does not match. Each
// of those needs a capability the estate does not currently have (see `capability` below, which
// reports the honest per-format status the build prompt demands rather than a list of intentions).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { registeredLocale } from '../_shared/registered_locale.ts';
import { portalLink } from '../_shared/site_origins.ts';
import { noExactSpec, offerMessage, apologyMessage, type OfferForText } from '../_shared/line_specs/no_exact_spec.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER. Same rule as ceo_agent, and written this way from
// the first line rather than retrofitted: ceo_agent shipped on 8 Sep reading `body.as` and believing
// it, which let any holder of an in-scope credential present as the CEO. An unrecognised context is
// refused rather than defaulted.
const SEAT_BY_CREDENTIAL: Record<string, 'sales_engineer'> = {
  'fn.sales_engineer': 'sales_engineer',
};

// A PORTAL CALLER IS A THIRD KIND OF CALLER, and it is the one the founder's 9 Sep ruling adds:
// "if its on the home page then the support replies. but if its on the customer or supplier portal
// then its the sales engineer". PortalShell already sends the customer's own session token; this
// resolves it to a customer row and NOTHING WIDER. `customer` may read its own report and ask its
// own questions; it may not name another party. Note customers.id is NOT auth.users.id (measured 9
// Sep: the one real customer's id does not exist in auth.users) — the verified JWT email is the
// join, which is the same identity rule the estate already uses: a phone may confirm, never select.
//
// A FOURTH KIND IS A SERVICE CALLER. customer_api hands this seat the matching decision on the
// create_inquiry path (the founder, 9 Sep: "match capability is the sales engineer task"). It
// presents ITS OWN credential — fn.customer_api — and must not therefore become the seat: the work
// is still performed AS sales_engineer (grant checked, agent_runs row written) but the CALLER is
// recorded as what it is. SERVICE_ACTIONS is the whole of what a service caller may reach, so a
// widened credential scope cannot quietly hand customer_api the grant ledger or the sector
// catalogue as well.
// spec_offer_sweep: resilience_ping's daily pass (founder_instruction #321). The work is sales_engineer's
// (detect, decide); every message goes out through customer_support's door (_shared/deliver.ts).
const SERVICE_ACTIONS = new Set(['match', 'spec_offer_sweep']);

// ── NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321) ─────────────────────────────────
// One pass: (1) inquiries whose quote window closed, or whose invited suppliers all quoted, are
// checked once against quote_compare's technical comparison (eligible quotes only) and an offer opens
// for every mandatory requested value no eligible quote matches while at least one offers another;
// (2) due reminders go out and lapsed offers close with an apology. State and timing: Postgres.
async function customerContact(customerId: string | null) {
  if (!customerId) return null;
  const { data } = await admin.from('customers').select('id,email,phone,wa_optin,locale,is_demo').eq('id', customerId).maybeSingle();
  return data || null;
}
// deno-lint-ignore no-explicit-any
async function tellCustomer(o: any, kind: 'offer' | 'reminder' | 'apology_no_reply', msg: { subject: string; body: string }, lang: 'en' | 'ar', cust: any): Promise<number[]> {
  const base = { type: 'spec_offer_' + kind, kind: 'sales_engineer_spec_offer_' + kind, to_role: 'customer', inquiry_id: o.inquiry_id,
    subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'sales_engineer', sender: 'customer_support' };
  const rows: Record<string, unknown>[] = [];
  if (cust?.email) rows.push({ ...base, channel: 'email', to_email: cust.email, dedupe_key: `spec_offer:${o.id}:${kind}:${o.reminders_sent ?? 0}:email` });
  if (cust?.phone && cust?.wa_optin !== false) rows.push({ ...base, channel: 'whatsapp', to_phone: cust.phone, dedupe_key: `spec_offer:${o.id}:${kind}:${o.reminders_sent ?? 0}:whatsapp` });
  if (!rows.length) return [];
  const { data } = await requestDelivery(admin, rows);
  return (data || []).map((d) => d.notification_id).filter((x): x is number => typeof x === 'number');
}
async function specOfferSweep(limit: number) {
  const out = { checked: 0, offers_opened: 0, offers_sent: 0, reminders: 0, lapsed: 0, errors: [] as string[] };
  const secret = await sec('cred_fn_sales_engineer');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const { data: cands, error: cErr } = await admin.rpc('fn_spec_offer_candidates', { p_limit: limit });
  if (cErr) out.errors.push('candidates: ' + cErr.message);
  for (const c of (cands || []) as Array<{ inquiry_id: string; customer_id: string | null }>) {
    try {
      // The same comparison the customer sees, eligible quotes only. quote_compare runs with verify_jwt,
      // so the service key passes the gateway and __secret decides the caller (the #630 lesson).
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/quote_compare', { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
        body: JSON.stringify({ __secret: secret, inquiry_id: c.inquiry_id, lang: 'en' }), signal: AbortSignal.timeout(45000) });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j) { out.errors.push(`${c.inquiry_id}: quote_compare HTTP ${r.status}`); continue; }
      const offers = j.ok && j.analysis ? noExactSpec(j.analysis.technical_detail) : [];
      const { data: opened, error: oErr } = await admin.rpc('fn_spec_offer_open', { p_inquiry: c.inquiry_id, p_offers: offers });
      if (oErr) { out.errors.push(`${c.inquiry_id}: open ${oErr.message}`); continue; }
      out.checked++; out.offers_opened += (opened || []).length;
      if (!(opened || []).length) continue;
      const cust = await customerContact(c.customer_id);
      const lang = await registeredLocale(admin, { role: 'customer', customerId: c.customer_id });
      const { data: inq } = await admin.from('inquiries').select('rfq_no').eq('id', c.inquiry_id).maybeSingle();
      // deno-lint-ignore no-explicit-any
      for (const o of opened as any[]) {
        if (o.last_sent_at) continue;
        const ids = await tellCustomer(o, 'offer', offerMessage(o as OfferForText, lang, { rfqNo: inq?.rfq_no, portalUrl: portalLink(lang, c.inquiry_id) }), lang, cust);
        await admin.rpc('fn_spec_offer_mark', { p_offer: o.id, p_action: 'sent', p_notification_ids: ids });
        out.offers_sent++;
      }
    } catch (e) { out.errors.push(`${c.inquiry_id}: ${String((e as Error)?.message || e).slice(0, 160)}`); }
  }
  const { data: due, error: dErr } = await admin.rpc('fn_spec_offer_due');
  if (dErr) out.errors.push('due: ' + dErr.message);
  for (const d of (due || []) as Array<{ offer_id: number; action: string; reminder_no: number; final: boolean }>) {
    try {
      const { data: o } = await admin.from('spec_alternative_offer').select('*').eq('id', d.offer_id).maybeSingle();
      if (!o || o.state !== 'open') continue;
      const cust = await customerContact(o.customer_id);
      const lang = await registeredLocale(admin, { role: 'customer', customerId: o.customer_id });
      const { data: inq } = await admin.from('inquiries').select('rfq_no').eq('id', o.inquiry_id).maybeSingle();
      if (d.action === 'remind') {
        const ids = await tellCustomer(o, 'reminder', offerMessage(o as OfferForText, lang, { rfqNo: inq?.rfq_no, portalUrl: portalLink(lang, o.inquiry_id), reminder: d.reminder_no, final: d.final }), lang, cust);
        await admin.rpc('fn_spec_offer_mark', { p_offer: o.id, p_action: 'remind', p_notification_ids: ids });
        out.reminders++;
      } else if (d.action === 'close_no_reply') {
        const ids = await tellCustomer(o, 'apology_no_reply', apologyMessage(o as OfferForText, lang, 'no_reply', { rfqNo: inq?.rfq_no }), lang, cust);
        await admin.rpc('fn_spec_offer_mark', { p_offer: o.id, p_action: 'close_no_reply', p_notification_ids: ids });
        out.lapsed++;
      }
    } catch (e) { out.errors.push(`offer ${d.offer_id}: ${String((e as Error)?.message || e).slice(0, 160)}`); }
  }
  return out;
}
type Caller =
  | { kind: 'sales_engineer' | 'founder' }
  | { kind: 'service'; context: string }
  | { kind: 'customer'; customerId: string; email: string }
  | null;

async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'sales_engineer');
    if (r.ok && SEAT_BY_CREDENTIAL[r.context]) return { kind: 'sales_engineer' };
    if (r.ok) return { kind: 'service', context: r.context };
  }
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!jwt) return null;
  const { data } = await admin.auth.getUser(jwt).catch(() => ({ data: { user: null } } as never));
  const email = String((data as { user?: { email?: string } })?.user?.email || '').toLowerCase();
  if (!email) return null;
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (allow.includes(email)) return { kind: 'founder' };
  const { data: cust } = await admin.from('customers').select('id').ilike('email', email).maybeSingle();
  return cust?.id ? { kind: 'customer', customerId: String(cust.id), email } : null;
}

// EMBEDDING IS FREE AND IS NOT OpenRouter. ai_gateway serves {action:'embed'} at its line 204,
// BEFORE routing and before fn_kernel_paid_provider_gate, from Supabase.ai.Session('gte-small') —
// an in-region 384-dim model with no bill and no route. Those are the same six lines, run here
// rather than across a network hop that would also need a second scoped credential for a local
// model. Verified 9 Sep 2026 by reading ai_gateway/index.ts:54-63.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }
}

// EVERY CALL LEAVES A ROW. fn_agents_board LEFT JOINs agent_runs on agent = agent_key, so a seat
// that never writes one renders with runs24 = 0 — indistinguishable from a seat that is down.
// Neither existing agent does this; measured 9 Sep, agent_runs holds rows for send_outbox and
// login_otp only. Best-effort: attribution must never fail the call it is attributing.
async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'sales_engineer',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

Deno.serve(observe('sales_engineer', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const caller = await whoami(req, body);
    if (!caller) return J({ error: 'unauthorized' }, 401);

    const action = String(body.action || '').trim();
    if (caller.kind === 'service' && !SERVICE_ACTIONS.has(action)) {
      return J({ error: 'forbidden', action, caller: caller.context, allowed: [...SERVICE_ACTIONS] }, 403);
    }

    // ── ASSIST ─────────────────────────────────────────────────────────────────────────────────
    // The portal assistant. PortalShell.tsx called site_assistant — Support's function, and correct
    // on the public homepage but wrong inside the customer portal by the founder's ruling of 9 Sep.
    //
    // NO MODEL, so the answer is RETRIEVED OR ESCALATED. fn_sales_assist reads SEVEN corpora, not
    // one: sales_knowledge (1,136), ops_knowledge (9,139), kb_chunks (2,686,026), agent_knowledge
    // (2,556, of which 1,627 are the live 'cat:' technical body), support_knowledge (408),
    // category_specs (56) and category_quote_specs (141). The first build of this handler searched
    // sales_knowledge alone — 0.042% of what the seat is entitled to — and the founder rejected the
    // refusal that produced on 9 Sep: "there is no reason for him not to know whatsoever."
    //
    // THE FLOORS DID NOT MOVE, because a nearest neighbour is ALWAYS found and an unfiltered vector
    // search answers nonsense as confidently as it answers a real question. A row that HAS an
    // embedding must clear cosine 0.86 (fn_faq_answer's number) AND match the tsvector. A row that
    // has NO embedding — 93.8% of kb_chunks, all of support_knowledge, all 1,627 'cat:' rows —
    // cannot be put to the vector floor at all, so it must clear a stricter lexical-only bar
    // instead. The lexical index is the only instrument in this estate that returns nothing for
    // nothing, which is why it gates both routes.
    //
    // WHEN NOTHING CLEARS, SOMETHING STILL HAPPENS. The refusal string is gone. The routine records
    // the question in sales_knowledge_gap (deduplicated, counted — the acquisition backlog) and
    // opens an org_tasks row owned by sales_engineer, and the asker is given the task number and
    // the owner. Which records were retrieved, how close each was and which were cited are written
    // to sales_decision_log from INSIDE the retrieval routine, so this handler cannot forget to.
    if (action === 'spec_offer_sweep') {
      if (caller.kind !== 'service' && caller.kind !== 'sales_engineer' && caller.kind !== 'founder') return J({ error: 'forbidden' }, 403);
      const res = await specOfferSweep(Math.max(1, Math.min(50, Number(body.limit) || 20)));
      await run('spec_offer_sweep', res.errors.length ? 'error' : 'ok', { checked: res.checked, offers_opened: res.offers_opened, offers_sent: res.offers_sent, reminders: res.reminders, lapsed: res.lapsed, errors: res.errors.length },
        res.errors.length ? res.errors.slice(0, 5).join(' | ') : undefined);
      return J({ ok: true, ...res });
    }

    if (action === 'assist') {
      const message = String(body.message || '').trim();
      if (!message) return J({ error: 'message_required' }, 400);

      const vec = await embed(message);
      const { data, error } = await admin.rpc('fn_sales_assist', {
        p_text: message, p_embedding: vec,
        p_min_similarity: Number(body.min_similarity ?? 0.86),
        p_min_rank: Number(body.min_rank ?? 0.05),
        p_k: Number(body.k ?? 5),
        p_actor: 'sales_engineer',
      });
      if (error) return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);

      const r = data as Record<string, unknown>;
      const recs = (r.records || []) as Array<Record<string, unknown>>;
      // Plain text: the widget renders a string, not markdown. Deterministic assembly of the cited
      // records — no generation step, nothing to hallucinate with. Each passage now names the body
      // it came from, because a cross-corpus answer that does not say whether it is quoting the
      // company's own policy or a trade standard is a worse answer than one that does.
      const reply = r.answered
        ? recs.map((x) =>
            String(x.title || '(untitled)') + '\n' +
            '[' + String(x.corpus) + (x.provenance ? ' · ' + String(x.provenance) : '') + ']\n' +
            String(x.content)).join('\n\n')
        : String(r.handoff || 'I do not have that yet.');

      // 14 SEP 2026. This exchange was never saved: the customer's question and the answer existed
      // only in the widget. The founder: "all conversations need to be saved and the sales agent
      // has access to them at any time". assistant_logs is the store the website assistant already
      // writes; audience 'customer:<id>' is what fn_conversation_party files it under.
      try {
        await admin.from('assistant_logs').insert({
          message, reply, seat: 'sales_engineer', answered: r.answered === true,
          audience: caller.kind === 'customer' ? 'customer:' + caller.customerId : caller.kind,
          path: 'portal', gap_task_id: (r.task_id as number | undefined) ?? null,
        });
      } catch { /* the customer already has the answer; a failed log must not take it back */ }

      await run('assist', 'ok', {
        answered: r.answered === true,
        cited: Array.isArray(r.cited) ? r.cited.length : 0,
        refusal: r.refusal ?? null,
        task_id: r.task_id ?? null,
      });

      return J({
        ok: true,
        seat: 'sales_engineer',
        answered: r.answered === true,
        reply,
        cited: r.cited,
        corpora: r.corpora,
        floor: r.floor,
        refusal: r.refusal ?? null,
        // The fallback is an action now, not a sentence. Surfaced so a caller can show the task.
        task_id: r.task_id ?? null,
        gap_recorded: r.gap_recorded === true,
        // Never claimed, always stated: this seat has no model today.
        basis: 'retrieved across sales_knowledge, ops_knowledge, kb_chunks, agent_knowledge, support_knowledge, category_specs and category_quote_specs under a similarity floor with lexical corroboration (embedded rows) or a stricter lexical-only bar (rows with no embedding); no model was called, so passages are quoted, never fused or restated',
        scope: caller.kind === 'customer' ? { customer_id: caller.customerId } : { caller: caller.kind },
      });
    }

    // ── CONVERSATIONS ──────────────────────────────────────────────────────────────────────────
    // The founder, 14 Sep 2026: "all conversations need to be saved and the sales agent has access
    // to them at any time. just in case we needed them for any reason". Every store - email in and
    // out, WhatsApp, portal chat, clarifications, the website assistant, forms - read whole through
    // fn_conversation_record, with a link to the PDF kept in the backups bucket. A customer caller
    // reads its own record and nobody else's: the party comes from the session, never the body.
    if (action === 'conversations') {
      const contact = caller.kind === 'customer' ? 'customer:' + caller.customerId : String(body.contact || '').trim();
      const { data, error } = await admin.rpc('fn_conversation_record', { p_contact: contact, p_limit: Number(body.limit ?? 200) });
      if (error) return J({ ok: false, error: 'record_failed', detail: error.message }, 503);
      const rec = data as { messages?: Array<Record<string, unknown>> } & Record<string, unknown>;
      for (const m of (rec.messages || []).slice(0, 50)) {
        const pdf = m.pdf as { bucket?: string; path?: string } | null;
        if (pdf?.bucket && pdf.path) {
          const { data: s } = await admin.storage.from(pdf.bucket).createSignedUrl(pdf.path, 3600);
          m.pdf_url = s?.signedUrl ?? null;
        }
      }
      await run('conversations', 'ok', { messages: Array.isArray(rec.messages) ? rec.messages.length : 0 });
      return J({ seat: 'sales_engineer', ...rec });
    }

    // ── REPORT ─────────────────────────────────────────────────────────────────────────────────
    // "he does the comparison reports, he basically fill the reports for suppliers and customers
    // about jobs won / supplier ratings / customer total spend literally everything related to
    // both portals." Every figure carries its basis — true_zero / measured / unknown /
    // derived_not_earned — because three different facts print as the character 0 on this
    // database today and collapsing them would be the misinformation, not the zero.
    //
    // A CUSTOMER CALLER MAY ONLY READ ITSELF. The party is taken from the resolved session, not
    // from the body, so a portal caller cannot widen what it can see by renaming the subject.
    if (action === 'report') {
      let kind = String(body.party_kind || '').trim().toLowerCase();
      let id = String(body.party_id ?? '').trim();
      if (caller.kind === 'customer') { kind = 'customer'; id = caller.customerId; }
      if (!kind || !id) return J({ error: 'party_kind_and_party_id_required' }, 400);

      const { data, error } = await admin.rpc('fn_sales_portal_report', { p_party_kind: kind, p_party_id: id });
      if (error) return J({ ok: false, error: 'report_failed', detail: error.message }, 503);
      await run('report', 'ok', { party_kind: kind });
      return J(data);
    }

    // ── ASK_ACCOUNTANT ─────────────────────────────────────────────────────────────────────────
    // A customer asks about a charge, an invoice or a refund in the portal. The founder, 14 Sep 2026:
    // "the accountant need to be in communication back and forth with the sales agent." The portal
    // voice stays this seat's; the figures are the accountant's. The question is handed over
    // (billing.question), the accountant reads the books and hands the facts back (billing.answer), and
    // they are shown here and delivered by customer_support. No figure is composed in this file.
    if (action === 'ask_accountant') {
      const question = String(body.question || body.message || '').trim().slice(0, 1000);
      if (!question) return J({ error: 'question_required' }, 400);
      const customerId = caller.kind === 'customer' ? caller.customerId : String(body.customer_id || '');
      if (!customerId) return J({ error: 'customer_id_required' }, 400);
      const { data: hid, error: hErr } = await admin.rpc('fn_seat_handoff', {
        p_from: 'sales_engineer', p_to: 'accountant', p_type: 'billing.question', p_subject_table: 'customers',
        p_subject_id: customerId + ':' + crypto.randomUUID(),
        p_payload: { party: 'customer', customer_id: customerId, transaction_id: body.transaction_id || null, question },
      });
      if (hErr) return J({ ok: false, error: 'handoff_failed', detail: hErr.message }, 503);
      const { data: ans } = await admin.from('agent_actions').select('evidence,status')
        .eq('kind', 'handoff').eq('target_id', 'billing.answer:' + String(hid)).maybeSingle();
      await run('ask_accountant', 'ok', { handoff_id: hid, answered: ans?.status === 'done' });
      return J({ ok: true, seat: 'sales_engineer', handoff_id: hid,
        facts: (ans?.evidence as Record<string, unknown> | null)?.facts ?? [], delivered_by: 'customer_support, by email' });
    }

    // Everything below `assist` and `report` is INTERNAL: seat readiness, the grant ledger, the
    // sector catalogue and the format matrix. A portal customer is authenticated but is not staff,
    // and an authenticated caller reaching an operator route is how privilege quietly widens.
    if (caller.kind === 'customer') return J({ error: 'forbidden', action }, 403);

    // ── HANDOFFS ───────────────────────────────────────────────────────────────────────────────
    // What other seats have handed this one and it has not closed (a remediation waiting on a
    // customer's proof, a delivery result not yet back), and the door to close one with evidence.
    if (action === 'handoffs') {
      const { data } = await admin.from('agent_actions').select('id,status,title,detail,evidence,created_at')
        .eq('kind', 'handoff').eq('agent', 'sales_engineer').neq('status', 'done').order('id').limit(100);
      return J({ ok: true, seat: 'sales_engineer', open: data || [] });
    }
    if (action === 'complete_handoff') {
      const { data: h } = await admin.from('agent_actions').select('id,agent').eq('id', Number(body.id)).eq('kind', 'handoff').maybeSingle();
      if (!h || h.agent !== 'sales_engineer') return J({ error: 'not_this_seats_handoff' }, 404);
      const { data, error } = await admin.rpc('fn_seat_handoff_complete', { p_id: Number(body.id), p_evidence: body.evidence ?? {} });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('complete_handoff', 'ok', { handoff_id: Number(body.id) });
      return J(data);
    }

    // ── MATCH ──────────────────────────────────────────────────────────────────────────────────
    // "match capability is the sales engineer task." (founder, 9 September 2026)
    //
    // WHAT THIS REPLACES. customer_api:187 POSTed to functions/v1/route_inquiry inside an
    // `if (useRouter)` try/catch. route_inquiry was deleted in 182308b and is deployed nowhere, so
    // that fetch 404'd, `rj?.ok` was falsy, routerAnswered stayed false and the very next block
    // degraded to match_suppliers_kw — KEYWORD matching — marking routing.fallback = true. No
    // exception, no alert, no stuck row. decision_policy.use_capability_matching is true, so the
    // intent was capability matching and the reality was keywords, silently, on every inquiry.
    //
    // NO MODEL, AND NONE IS WANTED HERE. The gates below are not judgement calls, they are facts
    // about a supplier's declared and confirmed scope, and public.fn_match_capability already
    // applies every one of them as hard SQL BEFORE ranking: supplier-confirmed scope
    // (confirmed_at not null), trade intersection, declared negative scope (excluded_trades),
    // contracted role via taxonomy_role, every taxonomy_trade.authority_required code,
    // project-value band, and emirate coverage. It is not re-implemented here and must not be —
    // a second matcher is a second answer.
    //
    // THE GRANT'S OWN WORDS ARE THE LIMIT. sales.matching carries: "Unknown mandatory evidence is
    // not a pass. No inventing a minimum supplier count and no padding with poor matches." So
    // nothing below ever relaxes the floor to reach a target count, ever widens the trade set to
    // find somebody, and ever returns a supplier the SQL gates refused. A short list is the answer
    // when the market is short.
    if (action === 'match') {
      const { data: mayRaw, error: mayErr } = await admin.rpc('fn_agent_may_act', {
        p_grantee_role_id: 'sales_engineer', p_action_class: 'matching', p_amount_aed: null,
      });
      const may = (mayRaw || {}) as Record<string, unknown>;
      if (mayErr || may.may_act !== true) {
        await run('match', 'refused', {}, String(may.reason || mayErr?.message || 'no grant'));
        return J({ ok: false, error: 'not_permitted', ...may }, 403);
      }

      const inquiryId = String(body.inquiry_id || '').trim();
      let inq: Record<string, unknown> | null = null;
      if (inquiryId) {
        const { data } = await admin.from('inquiries')
          .select('id,summary,raw_input,category,keywords,trades,emirate,scope_type,role_needed,budget,expected_value,boq')
          .eq('id', inquiryId).maybeSingle();
        if (!data) return J({ ok: false, error: 'inquiry_not_found', inquiry_id: inquiryId }, 404);
        inq = data as Record<string, unknown>;
      }

      const arr = (v: unknown): string[] =>
        (Array.isArray(v) ? v : []).map((x) => String(x).trim().toLowerCase()).filter(Boolean);

      // TRADES. The customer's own words resolved through taxonomy_trade.aliases by
      // public.fn_norm_trades — the estate's normaliser, word-START anchored so 'sign' matches
      // "signage" and not "design". Reused, not re-written.
      let trades = arr(body.trades);
      if (!trades.length) trades = arr(inq?.trades);
      const brief = [inq?.summary, inq?.raw_input, inq?.category, arr(inq?.keywords).join(' '), body.text]
        .map((x) => String(x ?? '')).filter(Boolean).join(' ').slice(0, 4000);
      if (!trades.length && brief) {
        const { data: nt } = await admin.rpc('fn_norm_trades', { p_text: brief });
        trades = arr(nt);
      }

      // WHAT THE CUSTOMER NEEDS DONE, not what a supplier would like to sell. taxonomy_role
      // decides which roles can serve each; this only picks the column.
      const need = String(body.need || '').trim() ||
        (String(inq?.scope_type || '').toLowerCase().includes('turnkey')
          ? 'whole_scope'
          : (/supply|material|product/i.test(String(inq?.scope_type || inq?.role_needed || '')) ? 'supplies' : 'executes'));

      // VALUE. Only a number that is actually a number gates the size band; a budget we cannot read
      // stays null, because an unreadable budget parsed as 0 would exclude every supplier with a
      // minimum. "Unknown mandatory evidence is not a pass" cuts the other way too: it is not a
      // fail either — it is unknown, and an unknown value simply does not gate.
      const num = (v: unknown): number | null => {
        const n = Number(String(v ?? '').replace(/[^0-9.]/g, ''));
        return Number.isFinite(n) && n > 0 ? n : null;
      };
      const value = num(body.value) ?? num(inq?.expected_value) ?? num(inq?.budget);
      const emirate = String(body.emirate || inq?.emirate || '').trim() || null;
      const products = arr(body.products);
      const brands = arr(body.brands);
      const projectType = String(body.project_type || inq?.scope_type || '').trim() || null;

      // THE FANOUT CEILING IS READ, NOT COMPILED IN. decision_policy holds match_max_fanout = 5,
      // match_max_fanout_per_trade = 3 and match_relevance_floor = 35 (measured 9 Sep 2026). The
      // keyword fallback this replaces hard-coded p_limit: 8, which CONTRADICTED the ceiling of 5
      // and had done so on every inquiry it ever handled. The configured 5 wins here; 8 was never
      // policy, it was a literal.
      const { data: polRows } = await admin.from('decision_policy').select('key,value')
        .in('key', ['match_max_fanout', 'match_max_fanout_per_trade', 'match_relevance_floor']);
      const pol = Object.fromEntries((polRows || []).map((r: { key: string; value: unknown }) => [r.key, Number(r.value)]));
      const maxFanout = Number.isFinite(pol.match_max_fanout) ? pol.match_max_fanout : 5;
      const perTrade = Number.isFinite(pol.match_max_fanout_per_trade) ? pol.match_max_fanout_per_trade : 3;
      const floor = Number.isFinite(pol.match_relevance_floor) ? pol.match_relevance_floor : 35;

      const policy = { max_fanout: maxFanout, max_fanout_per_trade: perTrade, relevance_floor: floor };
      const askedFor = { trades, need, products, brands, project_type: projectType, value, emirate };

      if (!trades.length) {
        // NOT A FAILURE AND NOT A COVERAGE GAP. Nobody was asked, because there was no question:
        // the brief names no trade this taxonomy recognises. Widening it to "everything" to produce
        // a list would be exactly the padding the grant forbids.
        await run('match', 'ok', { inquiry_id: inquiryId || null, trades: 0, matched: 0, gap: 'no_trade_identified' });
        return J({
          ok: true, seat: 'sales_engineer', inquiry_id: inquiryId || null, asked_for: askedFor, policy,
          candidates: 0, above_floor: 0, matched: [], persisted: 0,
          gap: { reason: 'no_trade_identified',
            note: 'The brief names no trade in taxonomy_trade, so fn_match_capability was not called. This is a brief that needs a question answered, not a supply gap.' },
        });
      }

      // Headroom, then trim. Asking fn_match_capability for exactly 5 would let one over-represented
      // trade fill the list before the per-trade cap could spread it.
      const headroom = Math.min(60, Math.max(maxFanout, trades.length * perTrade * 2));
      const { data: rowsRaw, error: matchErr } = await admin.rpc('fn_match_capability', {
        p_trades: trades, p_need: need, p_products: products, p_brands: brands,
        p_project_type: projectType, p_value: value, p_emirate: emirate, p_limit: headroom,
      });
      if (matchErr) {
        await run('match', 'error', { inquiry_id: inquiryId || null }, matchErr.message);
        return J({ ok: false, error: 'match_failed', detail: matchErr.message }, 503);
      }
      const rows = (rowsRaw || []) as Array<Record<string, unknown>>;

      // THREE DIFFERENT EMPTIES, AND THEY MUST NOT PRINT AS THE SAME 0. `candidates` is what
      // cleared the hard gates; `above_floor` is what then cleared the relevance floor. A gap after
      // the gates is a market fact; a gap after the floor is a policy fact; they call for different
      // work and were previously one number.
      const aboveFloor = rows.filter((r) => Number(r.score) >= floor);

      const usedByTrade = new Map<string, number>();
      const picked: Array<Record<string, unknown>> = [];
      for (const r of aboveFloor) {
        if (picked.length >= maxFanout) break;
        const shared = arr(r.trades).filter((t) => trades.includes(t));
        // Every trade this supplier would be picked FOR is already full. Taking it anyway is the
        // padding the grant names.
        if (shared.length && shared.every((t) => (usedByTrade.get(t) || 0) >= perTrade)) continue;
        for (const t of shared) usedByTrade.set(t, (usedByTrade.get(t) || 0) + 1);
        picked.push(r);
      }

      const matched = picked.map((r) => ({
        supplier_id: Number(r.supplier_id),
        company_name: r.company_name ?? null,
        // The SAME normalisation customer_api already applies: fn_match_capability's weights come
        // from decision_policy and sum to 100 by construction, so 100 is the denominator and the
        // stored similarity is a 0..1 fraction on a declared scale.
        score: Number(r.score),
        similarity: Math.round(Math.min(1, Math.max(0, Number(r.score) / 100)) * 1000) / 1000,
        reason: String(r.why || '').slice(0, 400),
        trades: r.trades, roles: r.roles, product_hits: r.product_hits,
        brand_hit: r.brand_hit, ptype_hit: r.ptype_hit, track: r.track,
      }));

      // THE MATCH RECORD. inquiry_matches carries a UNIQUE (inquiry_id, supplier_id), so this is an
      // upsert and a re-run of the same decision is not a second fanout.
      //
      // MEASURED 9 SEP 2026, AND IT CONTRADICTS THE COMMENT customer_api CARRIES: the two BEFORE
      // INSERT eligibility triggers it describes — a00_unsafe_match_eligibility and
      // gate_incomplete_match — DO NOT EXIST on this database. pg_trigger holds 4 rows for
      // inquiry_matches and every one is an internal referential-integrity trigger; there are 0
      // user triggers, and neither trigger FUNCTION exists in pg_proc either. So nothing between
      // this insert and the table refuses a supplier, and the eligibility that comment relies on is
      // being applied ONLY by fn_match_capability's own fn_is_matchable gate above. That is a real
      // gate and it is enough for this path — but it is one gate, not three, and it is stated here
      // rather than assumed.
      //
      // customer_api passes persist:false: it performs its own write immediately afterwards
      // because it needs the landed/refused split to decide who to email. One writer per path.
      let persisted = 0;
      const wantPersist = body.persist !== false && !!inquiryId;
      if (wantPersist && matched.length) {
        const { data: landed, error: insErr } = await admin.from('inquiry_matches')
          .upsert(matched.map((m) => ({
            inquiry_id: inquiryId, supplier_id: m.supplier_id,
            similarity: m.similarity, match_reason: m.reason,
          })), { onConflict: 'inquiry_id,supplier_id' })
          .select('supplier_id');
        if (insErr) {
          await run('match', 'error', { inquiry_id: inquiryId, matched: matched.length }, insErr.message);
          return J({ ok: false, error: 'match_record_failed', detail: insErr.message, matched }, 503);
        }
        persisted = (landed || []).length;
      }

      // A SUPPLY GAP IS A FINDING, NOT AN ERROR. ok stays true, the customer's intent is not
      // distorted, the project is not silently split, and nothing is escalated to the founder. The
      // recording and recovery path already exists and is NOT duplicated here: customer_api's
      // flagCoverageGap() fires on exactly this condition (zero landed matches) and writes the
      // agent_actions coverage_gap row, the founder_alerts line and the owner notification.
      const gap = matched.length ? null : {
        reason: rows.length === 0 ? 'no_capable_supplier' : 'below_relevance_floor',
        candidates_before_floor: rows.length,
        best_score: rows.length ? Number(rows[0].score) : null,
        relevance_floor: floor,
        note: rows.length === 0
          ? 'No supplier cleared fn_match_capability\'s hard gates for this trade, role, authority, value band and emirate. This is a supply-coverage gap: the demand is real and the marketplace cannot serve it.'
          : 'Suppliers cleared the hard gates but none reached the configured relevance floor. Lowering the floor to produce a list is expressly forbidden by the sales.matching grant.',
        recovery: 'Recorded and pursued by customer_api.flagCoverageGap() on the create_inquiry path (agent_actions coverage_gap + founder_alerts + owner notification). The customer\'s scope is not widened, the project is not split, and no supplier choice is put to the founder.',
      };

      await run('match', 'ok', {
        inquiry_id: inquiryId || null, trades: trades.length, candidates: rows.length,
        above_floor: aboveFloor.length, matched: matched.length, persisted, gap: gap?.reason ?? null,
      });

      return J({
        ok: true, seat: 'sales_engineer', caller: caller.kind,
        inquiry_id: inquiryId || null,
        asked_for: askedFor, policy,
        candidates: rows.length, above_floor: aboveFloor.length,
        matched, persisted, gap,
        grant: { grant: may.grant, limit: may.limit },
        basis: 'public.fn_match_capability — supplier-confirmed scope, trade intersection, declared exclusions, contracted role, mandatory authorities, project-value band and emirate coverage applied as SQL gates before ranking; then decision_policy\'s relevance floor, per-trade cap and fanout ceiling. No model was called and no supplier was added to reach a count.',
      });
    }

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // Readiness measured, not asserted. The audit of 9 Sep found the only honest liveness signal for
    // the CEO seat was an authenticated round-trip returning 200; edge_health_probe exists with 0
    // rows and nothing writes it. This route answers the question directly: is the seat established,
    // what may it do, and what is it waiting on.
    if (action === 'health') {
      const [agent, grants, know, routes] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available').eq('agent_key', 'sales_engineer').maybeSingle(),
        admin.from('ceo_standing_grant').select('grant_key,action_class,active').eq('grantee_role_id', 'sales_engineer'),
        admin.from('sales_knowledge').select('record_id', { count: 'exact', head: true }),
        admin.from('llm_route_health').select('model_id,open_until'),
      ]);

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      // A knowledge table that does not exist yet is a stage of the build, not an error. Say which.
      const knowledgeCount = know.error ? null : (know.count ?? 0);

      await run('health', 'ok', { grants: (grants.data || []).length, knowledge: knowledgeCount });
      return J({
        ok: true,
        seat: 'sales_engineer',
        caller: caller.kind,
        seated: agent.data?.active === true && agent.data?.available === true,
        grants: (grants.data || []).map((g: { grant_key: string; action_class: string; active: boolean }) =>
          ({ grant: g.grant_key, class: g.action_class, active: g.active })),
        knowledge_records: knowledgeCount,
        knowledge_state: know.error ? 'not_ingested' : (knowledgeCount ? 'ingested' : 'empty'),
        // The single most useful thing this route can report, because it is what gates the half of
        // this seat that needs judgement.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held; the founder set this and only he can clear it' }
          : null,
      });
    }

    // ── GRANTS ─────────────────────────────────────────────────────────────────────────────────
    // What may this seat do right now, answered by the database at call time — expiry and active
    // state are evaluated inside fn_agent_may_act, so a revoked grant cannot be used from a cached
    // answer. An uncovered class routes to the CEO and says so; it never routes to the founder.
    if (action === 'grants') {
      const cls = String(body.action_class || '').trim();
      if (cls) {
        const { data, error } = await admin.rpc('fn_agent_may_act', {
          p_grantee_role_id: 'sales_engineer', p_action_class: cls,
          p_amount_aed: body.amount_aed ?? null,
        });
        if (error) return J({ ok: false, refused: error.message }, 400);
        await run('grants', 'ok', { action_class: cls });
        return J({ ok: true, action_class: cls, ...(data as Record<string, unknown>) });
      }
      const { data } = await admin.from('ceo_standing_grant')
        .select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at')
        .eq('grantee_role_id', 'sales_engineer').order('grant_key');
      await run('grants', 'ok', { listed: (data || []).length });
      return J({ ok: true, grants: data || [] });
    }

    // ── OBLIGATIONS ────────────────────────────────────────────────────────────────────────────
    // The intake obligation set for one sector: which questions still resolve a material
    // uncertainty, given what is already known.
    //
    // This is the build prompt's section 6 made deterministic: "Build an inquiry-specific obligation
    // set instead of asking every field in a static category checklist. Each question must resolve a
    // material uncertainty... do not dump an enormous form, repeatedly ask answered questions or
    // require irrelevant information."
    //
    // `answered` is the set of field_keys already resolved by earlier answers or by a document. The
    // difference is the obligation set. No model is consulted to compute a set difference, and one
    // consulted here would make the same question non-reproducible between two identical inquiries.
    if (action === 'obligations') {
      const sector = String(body.sector_id || '').trim();
      if (!sector) return J({ error: 'sector_id_required' }, 400);
      const answered = new Set((Array.isArray(body.answered) ? body.answered : []).map(String));

      const { data, error } = await admin.from('sales_qualification_field')
        .select('field_key,question,answer_type,ask_only_if,criticality,unknown_handling')
        .eq('sector_id', sector).order('field_key');

      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      if (!data?.length) return J({ ok: false, error: 'unknown_sector', sector_id: sector }, 404);

      const open = data.filter((f: { field_key: string }) => !answered.has(f.field_key));
      await run('obligations', 'ok', { sector, total: data.length, open: open.length });
      return J({
        ok: true,
        sector_id: sector,
        total_fields: data.length,
        answered: data.length - open.length,
        obligations: open,
        // Stated rather than implied: this is the sector's catalogue, not a judgement that these are
        // the only things that matter for this particular inquiry.
        basis: 'seed catalogue for this sector; a document or an answer may retire a field, and an unusual scope may add one that is not listed here',
      });
    }

    // ── SECTORS ────────────────────────────────────────────────────────────────────────────────
    if (action === 'sectors') {
      const q = String(body.q || '').trim();
      let query = admin.from('sales_sector').select('sector_id,group_key,title,scope');
      if (q) query = query.or(`title.ilike.%${q}%,scope.ilike.%${q}%,sector_id.ilike.%${q}%`);
      const { data, error } = await query.order('sector_id').limit(Number(body.limit ?? 50));
      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      await run('sectors', 'ok', { q, found: (data || []).length });
      return J({ ok: true, sectors: data || [], count: (data || []).length });
    }

    // ── CAPABILITY ─────────────────────────────────────────────────────────────────────────────
    // The per-format capability status the build prompt requires, section 8: "Implement real
    // parsers/adapters and expose per-format capability status... Never claim full extraction when
    // only a thumbnail or subset worked... Do not advertise unsupported DWG handling as completed."
    //
    // Every entry is MEASURED at call time against the deployed function list, not declared. A format
    // whose handler is not deployed reports unavailable with the reason, so a caller can tell "we
    // cannot read this" from "we read it and found nothing" — which are the same empty result and
    // very different facts.
    if (action === 'capability') {
      const { data: owned } = await admin.from('function_owner').select('function_slug');
      const present = new Set((owned || []).map((r: { function_slug: string }) => r.function_slug));

      // The handler each format needs, and what it can honestly do when it is present. Written from
      // the 9 Sep audit of every deployed document function, not from their names.
      const FORMATS = [
        { format: 'pdf_text_layer', handler: 'extract_text', gives: 'one flat text blob; no pages, no layout, no coordinates' },
        { format: 'pdf_scanned', handler: 'doc_extract', gives: 'OCR fallback — the only one in the estate' },
        { format: 'pdf_licence', handler: 'license_extract', gives: 'model-asserted licence fields; enum-whitelisted' },
        { format: 'pdf_quotation', handler: 'quote_extract', gives: 'quotation line items' },
        { format: 'drawing_to_boq', handler: 'drawing_boq', gives: 'model-read line items from page images; never geometry or scale' },
        { format: 'drawing_redaction', handler: 'drawing_redact', gives: 'pixel overlay on a raster; NOT layers, block attributes, xrefs or embedded thumbnails' },
        { format: 'dwg_dxf', handler: 'cad_convert', gives: 'raster preview only (200 dpi PNG via CloudConvert); no entities, layers or dimensions, ever' },
        { format: 'xlsx', handler: 'supplier_catalog_ingest', gives: 'first sheet only, cached values, hidden rows included, merges ignored' },
      ];

      const matrix = FORMATS.map((f) => ({
        ...f,
        available: present.has(f.handler),
        reason: present.has(f.handler) ? null : `${f.handler} is not deployed`,
      }));

      await run('capability', 'ok', { available: matrix.filter((m) => m.available).length, total: matrix.length });
      return J({
        ok: true,
        formats: matrix,
        available: matrix.filter((m) => m.available).length,
        total: matrix.length,
        // The sentence that must never be softened.
        native_dwg: 'NOT SUPPORTED. CloudConvert is configured and paid for, but it is a rasteriser — entity-level DWG needs a licensed SDK the estate does not have. Any DWG handling is raster preview only.',
      });
    }

    return J({ error: 'unknown_action', action }, 400);
  } catch (e) {
    await run('error', 'error', {}, String((e as Error).message || e));
    return J({ error: String((e as Error).message || e) }, 500);
  }
}));

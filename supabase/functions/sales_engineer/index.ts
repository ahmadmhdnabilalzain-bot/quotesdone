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
import { NOT_LIVE_QUOTE_IN } from '../_shared/quote_live.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { registeredLocale } from '../_shared/registered_locale.ts';
import { portalLink } from '../_shared/site_origins.ts';
import { MATCH_ALL, relevanceFloorApplies } from '../_shared/supplier_capability.ts';
import { serviceKeysOf, serviceVocab } from '../_shared/service_vocabulary.ts';
import { remoteEmbedder } from '../_shared/meaning_embed.ts';
import { noExactSpec, offerMessage, apologyMessage, offerTexts, type OfferForText } from '../_shared/line_specs/no_exact_spec.ts';
import { defaultDeps } from '../_shared/think.ts';
import { arabicTextsFor } from '../_shared/reasoned_governance.ts';
import { reasonedOffers } from '../_shared/reasoned_matching.ts';
import { supplierLabel } from '../_shared/quote_documents.ts';
import { langOf, type QuoteForAnswer } from '../_shared/chat_answers.ts';
import { acceptImages } from '../_shared/chat_images.ts';
import { recallCases, recallTrace } from '../_shared/case_recall.ts';
import { accountKey, clientHistory, fitHistory, openConversation } from '../_shared/chat_history.ts';
import { answerFromBrief } from '../_shared/brief_answer.ts';
import { briefNumbers, companyBrief, figureSource } from '../_shared/company_brief.ts';
import { aiSystem, replyProblems } from '../_shared/ai_reply.ts';
import { guardSupportReply } from '../_shared/support_reply_guard.ts';
import { STATUS, streamReply, wantsStream } from '../_shared/stream_reply.ts';
import { PORTAL_TURN_MS, portalRules, portalFacts, wrappedReply, plainLanguage, customerSafe } from './portal_turn.ts';
import { checkReadability } from '../_shared/readability.ts';
import { tradeSlugsOf, matchEmirate } from '../_shared/match_criteria.ts';

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
  const { data } = await admin.from('customers').select('id,email,locale,is_demo').eq('id', customerId).maybeSingle();
  return data || null;
}
// deno-lint-ignore no-explicit-any
async function tellCustomer(o: any, kind: 'offer' | 'reminder' | 'apology_no_reply', msg: { subject: string; body: string }, lang: 'en' | 'ar', cust: any): Promise<number[]> {
  // SUPPORT ASKS THE CUSTOMER (22 Sep 2026, finding SP-F-08; founder's rule "no exact spec → offer
  // alternatives" — support asks, yes is an accepted spec and no is an apology). The DETECTION is
  // the sales engineer's: it is the seat that compares the requested value with every eligible
  // quote and decides an offer exists. The QUESTION is not. It goes to the customer in the voice
  // the customer already knows, so the template and the requesting seat both name customer_support
  // — they used to read sales_engineer_spec_offer_* / requested_by sales_engineer while the sender
  // was customer_support, which is a message signed by one seat and asked by another. The `type`
  // is unchanged: fn_channel_requester, founder_mail_policy and every reader key on it.
  const base = { type: 'spec_offer_' + kind, kind: 'customer_support_spec_offer_' + kind, to_role: 'customer', inquiry_id: o.inquiry_id,
    subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'customer_support', sender: 'customer_support' };
  const rows: Record<string, unknown>[] = [];
  if (cust?.email) rows.push({ ...base, channel: 'email', to_email: cust.email, dedupe_key: `spec_offer:${o.id}:${kind}:${o.reminders_sent ?? 0}:email` });
  // WhatsApp goes only to the confirmed WhatsApp number (#322): the a03 trigger addresses it by email or records the skip.
  if (cust?.email) rows.push({ ...base, channel: 'whatsapp', to_email: cust.email, dedupe_key: `spec_offer:${o.id}:${kind}:${o.reminders_sent ?? 0}:whatsapp` });
  if (!rows.length) return [];
  const { data } = await requestDelivery(admin, rows);
  return (data || []).map((d) => d.notification_id).filter((x): x is number => typeof x === 'number');
}
async function specOfferSweep(limit: number) {
  const out = { checked: 0, offers_opened: 0, offers_sent: 0, reminders: 0, lapsed: 0, arabic_held: 0, errors: [] as string[], precedent: [] as unknown[], held_for_reasoning: 0 };
  const secret = await sec('cred_fn_sales_engineer');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const { data: cands, error: cErr } = await admin.rpc('fn_spec_offer_candidates', { p_limit: limit });
  if (cErr) out.errors.push('candidates: ' + cErr.message);
  // A FAILED CHECK BACKS OFF (22 Sep 2026). A candidate whose comparison errored was never marked,
  // so fn_spec_offer_candidates handed it back on every ~15-minute resilience tick, forever.
  // fn_spec_offer_failed counts the attempt and sets the next one (15 min, doubling); after the
  // last attempt the inquiry leaves the sweep and sales_engineer is handed it as a finding.
  const failed = async (inquiryId: string, why: string) => {
    out.errors.push(`${inquiryId}: ${why}`);
    try { await admin.rpc('fn_spec_offer_failed', { p_inquiry: inquiryId, p_error: why.slice(0, 300) }); } catch (_e) { /* recorded in errors */ }
  };
  for (const c of (cands || []) as Array<{ inquiry_id: string; customer_id: string | null }>) {
    try {
      // The same technical comparison the customer sees, eligible quotes only. technical_only: the
      // sweep reads technical_detail alone, which quote_compare computes by code — it never needed
      // the paid model comparison it used to trigger for every candidate. quote_compare runs with
      // verify_jwt, so the service key passes the gateway and __secret decides the caller (#630).
      const r = await fetch(Deno.env.get('SUPABASE_URL')! + '/functions/v1/quote_compare', { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
        body: JSON.stringify({ __secret: secret, inquiry_id: c.inquiry_id, lang: 'en', technical_only: true }), signal: AbortSignal.timeout(45000) });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j) { await failed(c.inquiry_id, `quote_compare HTTP ${r.status}`); continue; }
      // AN OFFER ONLY ON A REASONED DIFFERENCE (founder_instruction 886-903; decision point 28). The comparison
      // proposes where no quote is textually the customer's spec; reasoning decides whether each quoted value
      // is GENUINELY different (reasoned_matching.ts reasonedOffers). Held: nothing opens for this inquiry and
      // the customer is told nothing now — the sweep asks again next tick, and nobody is offered on a guess.
      const proposed = j.ok && j.analysis ? noExactSpec(j.analysis.technical_detail) : [];
      const rs = await reasonedOffers(defaultDeps(admin, 'sales_engineer'), proposed, c.inquiry_id);
      if (rs.held) { out.held_for_reasoning++; continue; }
      const offers = rs.offers;
      // HOW DID THE LAST OFFER LIKE THIS END? (23 Sep 2026.) Recalled before the offer opens, per
      // offer, and returned with the sweep so the seat sees "we offered this before and it was declined".
      // ponytail: the first 2 offers per inquiry, sequential gte-small runs inside the sweep's budget.
      for (const sp of offers.slice(0, 2)) {
        const situation = `no exact match for ${sp.label_en} = ${sp.requested} | item: ${sp.item ?? ''}`;
        const m = await recallCases(admin, { seat: 'sales_engineer', path: 'spec_offer', caseKind: 'spec_offer', otherSeats: false,
          situation, embedding: await Promise.race([embed(situation), new Promise<null>((r) => setTimeout(() => r(null), 1500))]) });
        out.precedent.push({ inquiry_id: c.inquiry_id, attr: sp.label_en, ...recallTrace(m), rule: m.rule });
      }
      const { data: opened, error: oErr } = await admin.rpc('fn_spec_offer_open', { p_inquiry: c.inquiry_id, p_offers: offers });
      if (oErr) { await failed(c.inquiry_id, `open ${oErr.message}`); continue; }
      out.checked++; out.offers_opened += (opened || []).length;
      if (!(opened || []).length) continue;
      const cust = await customerContact(c.customer_id);
      const lang = await registeredLocale(admin, { role: 'customer', customerId: c.customer_id });
      const { data: inq } = await admin.from('inquiries').select('rfq_no').eq('id', c.inquiry_id).maybeSingle();
      // deno-lint-ignore no-explicit-any
      for (const o of opened as any[]) {
        if (o.last_sent_at) continue;
        const arTexts = await arabicTextsFor(defaultDeps(admin, 'sales_engineer'), lang, offerTexts(o as OfferForText));
        const msg = offerMessage(o as OfferForText, lang, { rfqNo: inq?.rfq_no, portalUrl: portalLink(lang, c.inquiry_id), arTexts });
        // An Arabic message never goes out with an untranslated line: it is not marked sent, so the next tick
        // retries it — by then the replay has put the reasoned Arabic in the cache (decision point trade_glossary_ar).
        if (msg.untranslated?.length) { out.arabic_held++; continue; }
        await admin.rpc('fn_spec_offer_restart_clock', { p_offer: o.id });   // a late first send gets its full window
        const ids = await tellCustomer(o, 'offer', msg, lang, cust);
        await admin.rpc('fn_spec_offer_mark', { p_offer: o.id, p_action: 'sent', p_notification_ids: ids });
        out.offers_sent++;
      }
    } catch (e) { await failed(c.inquiry_id, String((e as Error)?.message || e).slice(0, 160)); }
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
        const arTexts = await arabicTextsFor(defaultDeps(admin, 'sales_engineer'), lang, offerTexts(o as OfferForText));
        const msg = offerMessage(o as OfferForText, lang, { rfqNo: inq?.rfq_no, portalUrl: portalLink(lang, o.inquiry_id), reminder: d.reminder_no, final: d.final, arTexts });
        if (msg.untranslated?.length) { out.arabic_held++; continue; }   // retried next tick, never sent half-translated
        const ids = await tellCustomer(o, 'reminder', msg, lang, cust);
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

// THE CUSTOMER'S OWN QUOTES, GIVEN TO THE MODEL AS FACTS. Scoped through inquiries to
// the resolved customer; drafts are never a quote the customer can see. The supplier label is the
// compare table's letter (live quotes by ascending price) unless a transactions row proves the
// reveal was paid — the same rule customer_api.letterOf applies, so the chat cannot name a
// supplier the quote PDF would not.
async function answerFromOwnQuotes(customerId: string, message: string, lang: 'en' | 'ar') {
  try {
    const { data: inqs } = await admin.from('inquiries').select('id,rfq_no,category,summary').eq('customer_id', customerId).limit(50);
    const ids = (inqs || []).map((i: { id: string }) => i.id);
    if (!ids.length) return null;
    const [{ data: qs }, { data: tx }] = await Promise.all([
      admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,status,exclusions,scope,conditions,warranty,lead_time,payment_terms,validity,notes,committed_items,created_at')
        .in('inquiry_id', ids).not('status', 'in', NOT_LIVE_QUOTE_IN).order('quote_amount', { ascending: true }).limit(60),
      admin.from('transactions').select('inquiry_id,supplier_id').eq('customer_id', customerId).not('revealed_at', 'is', null),
    ]);
    if (!qs || !qs.length) return null;
    const revealed = new Set((tx || []).map((t: { inquiry_id: string; supplier_id: number }) => t.inquiry_id + ':' + t.supplier_id));
    const revealedIds = [...new Set((qs as Array<{ inquiry_id: string; supplier_id: number }>).filter((q) => revealed.has(q.inquiry_id + ':' + q.supplier_id)).map((q) => q.supplier_id))];
    const names = new Map<number, string>();
    if (revealedIds.length) {
      const { data: leads } = await admin.from('leads').select('id,company_name').in('id', revealedIds);
      for (const l of leads || []) names.set(Number(l.id), String(l.company_name || ''));
    }
    const byInq = new Map<string, { rfq_no: string | null; category: string | null; summary: string | null }>((inqs || []).map((i: any) => [i.id, i]));
    const letterIdx = new Map<string, number>();
    const quotes: QuoteForAnswer[] = (qs as any[]).map((q) => {
      const n = letterIdx.get(q.inquiry_id) ?? 0; letterIdx.set(q.inquiry_id, n + 1);
      const inq = byInq.get(q.inquiry_id);
      const name = revealed.has(q.inquiry_id + ':' + q.supplier_id) ? names.get(Number(q.supplier_id)) : '';
      const items = Array.isArray(q.committed_items)
        ? q.committed_items.map((it: any) => [it?.description ?? it?.item ?? it?.name, it?.spec ?? it?.specification, it?.qty != null ? String(it.qty) + ' ' + String(it?.unit ?? '') : null].filter(Boolean).join(' — ')).join('\n')
        : null;
      return {
        id: String(q.id), rfq_no: inq?.rfq_no ?? null, inquiry_category: inq?.category ?? null, inquiry_summary: inq?.summary ?? null,
        supplier_label: name || (lang === 'ar' ? 'المورّد ' + supplierLabel(n) : 'Supplier ' + supplierLabel(n)),
        amount: q.quote_amount == null ? null : Number(q.quote_amount), status: q.status,
        exclusions: q.exclusions, scope: q.scope, conditions: q.conditions, warranty: q.warranty,
        lead_time: q.lead_time, payment_terms: q.payment_terms, validity: q.validity, notes: q.notes, items,
      };
    });
    // EVERY QUOTE IS GIVEN, AND THE ONE REPLY CALL READS THEM (27 Oct 2026, ruling 1195: knowledge is given to the
    // model, which reasons). Until today a think() DECISION (quoteQuestion: a planning call plus a deciding call,
    // 40-60 s on gpt-6-luna-pro, measured on the 27 Oct replay's sibling calls) ran BEFORE the reply just to pick which
    // quote and field the question was about, and its pick was then turned into a sentence the reply model re-read.
    // Now the quotes are one facts block and the reply model answers from it in the same call. `lang` is unused: the
    // facts are data, the reply is written in the asker's language by the model.
    void lang; void message;
    const shown = quotes.slice(0, 15).map((q) => Object.fromEntries(Object.entries(q).filter(([k, v]) => k !== 'id' && v != null && v !== '')));
    return { facts: JSON.stringify(shown).slice(0, 6000) };
  } catch { return null; }   // a read failure falls through to the corpora rather than failing the turn
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

// The streamed caller's emitter, keyed by its request: the portal reply's checked sentences go out as the model writes them.
const EMITTERS = new WeakMap<Request, (text: string) => void>();
const plain = observe('sales_engineer', async (req) => {
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

    // The customer portal asks for and records the rating of a closed support case here (CSAT 1-5, CES 1-7):
    // the portal is the sales engineer's, so it never calls Support's widget. The asker's questions in 'assist'
    // reach their support case through the assistant_logs row it writes (path 'portal').
    if (action === 'support_rating_due') {
      if (caller?.kind !== 'customer') return J({ error: 'forbidden' }, 403);
      const { data, error } = await admin.rpc('fn_support_rating_due', { p_party_kind: 'customer', p_party_id: caller.customerId });
      return error ? J({ error: 'rating_due_failed' }, 400) : J({ ok: true, due: data || [] });
    }
    if (action === 'support_rating') {
      if (caller?.kind !== 'customer') return J({ error: 'forbidden' }, 403);
      const { data, error } = await admin.rpc('fn_support_portal_rate', {
        p_party_kind: 'customer', p_party_id: caller.customerId, p_case_ref: String(body.case_ref || ''),
        p_csat: body.csat == null ? null : Number(body.csat), p_ces: body.ces == null ? null : Number(body.ces),
        p_comment: body.comment ? String(body.comment).slice(0, 2000) : null });
      return error ? J({ error: 'rating_failed' }, 400) : J(data);
    }

    // THE PORTAL CHAT IS REDRAWN FROM THE DATABASE (ruling 1255): every turn of the customer's one conversation, including
    // what they said on the website widget before signing up (widget_conv, adopted into the account here).
    if (action === 'assist_history') {
      const acct = caller.kind === 'customer' ? accountKey('customer', caller.customerId) : '';
      if (!acct) return J({ turns: [] });
      const c = await openConversation(admin, { account: acct, visitorConv: body.widget_conv, adopt: body.adopt === true });   // the portal sends adopt once, right after sign-in
      return J({ turns: c.turns ?? [], adopted: c.adopted, pending: !!c.pending });
    }
    if (action === 'assist') {
      // ── ONE TURN, ON A CLOCK (customer_support owns the conversation, it_engineer the latency; 27 Oct 2026) ──
      // MEASURED BEFORE (production, ZZ DEMO wardrobe replay 27 Oct 07:41-08:13Z, agent_runs fn:sales_engineer + ai_cost_log):
      // every turn took 58-150 s and turn 7 hit the 150 s edge wall as a 504, so the portal printed its error line. Per
      // turn the old road made 3-5 SERIAL model calls on gpt-6-luna-pro: a planning call (routine_employee_reasoning,
      // 18-31 s, ~22k prompt tokens), the answer (customer_communication, 13-48 s, 35-62k prompt tokens and growing with
      // every turn because the plan's per-step retrieval and the whole transcript rode in one payload), on 4 of 14 turns an
      // independent check plus a corrective rewrite (+40 s), on 8 of 14 a plain-language rewrite (16-35 s), and none of it
      // bounded. supportReply/think was built for deliberate seat decisions, not a chat turn.
      // NOW the turn is answered exactly as the website widget already answers a signed-in customer (rulings 1195/1196,
      // 1219): ONE streamed model call, class customer_portal_assistant (claude-sonnet-5.5, gpt-6-luna-pro behind it; no new
      // model, no routing change), given the company brief, this seat's retrieved records and the customer's own quotes as
      // facts, every sentence checked before it is shown, a failed check rewritten by the model, and the whole ladder inside
      // PORTAL_TURN_MS (portal_turn.ts). The reads before the call run side by side, not one after another.
      const t0 = Date.now(); const T: Record<string, number> = {}; const lap = (k: string) => { T[k] = Date.now() - t0; };
      const deadline = t0 + PORTAL_TURN_MS;
      const message = String(body.message || '').trim();
      if (!message) return J({ error: 'message_required' }, 400);
      const lang = langOf(message, String(body.lang || ''));
      // THE WHOLE CONVERSATION (_shared/chat_history.ts, 18 Oct 2026). PortalShell always sent its history and this
      // handler never read it: every portal turn reached the model alone, so on 14 Oct the founder's 2 m x 1.2 m wardrobe
      // was asked for again one turn later (assistant_logs 3695). Every turn is stored under conv_id, scoped to the
      // caller the session resolved (never the body), and read back whole; the browser's copy only fills the first turn.
      // ruling 1255: ONE conversation per customer (the same key the widget writes when they are signed in), and the
      // visitor chat from before sign-up was adopted into it by assist_history (adopt flag), never here.
      const acct = caller.kind === 'customer' ? accountKey('customer', caller.customerId) : '';
      const pConvo = acct ? openConversation(admin, { account: acct }) : Promise.resolve({ key: '', turns: null, adopted: 0 });
      const rpc = async (f: string, args: Record<string, unknown>) => { const x = await admin.rpc(f, args); return { data: x.data, error: x.error }; };
      const pBrief = companyBrief(rpc, [], '', lang);
      const pKey = sec('cred_fn_sales_engineer');

      // ── A QUESTION ABOUT THE CUSTOMER'S OWN QUOTE IS ANSWERED FROM THAT QUOTE (21 Sep 2026) ──
      // No corpus holds this customer's quote; the quotes table does. Their quotes, scoped in SQL to inquiries.customer_id =
      // the resolved session, are given to the model as facts (portal_turn.portalFacts). The supplier is named only where a
      // transactions row proves the reveal was paid; before that it is the same "Supplier A" letter the compare table prints.
      const pOwn = caller.kind === 'customer' ? answerFromOwnQuotes(caller.customerId, message, lang) : Promise.resolve(null);

      // THE EMBEDDING IS BOUNDED. Measured 21 Sep 2026: fn_sales_assist answers in 0.09 s without a
      // vector; the audit's >2 min portal reply was the in-function gte-small session warming up.
      // A vector adds recall only for rows that ALSO corroborate lexically, so 1.5 s is all it gets;
      // past that the lexical routes answer alone rather than the customer waiting.
      const vec = await Promise.race([embed(message), new Promise<null>((r) => setTimeout(() => r(null), 1500))]);
      lap('embed');
      // PAST CASES BEFORE THE ANSWER (23 Sep 2026): has this seat met this question before, and how did it end? The same
      // vector, so no second embedding. Recorded on the judgement only: a past case's text never enters a customer prompt.
      // fn_sales_assist reads the seat's seven corpora, records what it retrieved, and files the gap when nothing clears.
      const [memory, assisted] = await Promise.all([
        recallCases(admin, { seat: 'sales_engineer', path: 'assist', situation: message, embedding: vec }),
        admin.rpc('fn_sales_assist', {
          p_text: message, p_embedding: vec,
          p_min_similarity: Number(body.min_similarity ?? 0.86),
          p_min_rank: Number(body.min_rank ?? 0.05),
          p_k: Number(body.k ?? 5),
          p_actor: 'sales_engineer',
        }),
      ]);
      const { data, error } = assisted;
      if (error) return J({ ok: false, error: 'retrieval_failed', detail: error.message }, 503);
      const r = data as Record<string, unknown>;
      // NOTHING INTERNAL OR UNVERIFIED REACHES A CUSTOMER (#1567/#1569, the 7 Oct stating rule; independent review of #1640,
      // 27 Oct 2026). fn_sales_assist reads sales_knowledge, ops_knowledge, agent_knowledge, support_knowledge and kb_chunks
      // without the audience and eligibility rules fn_reason_retrieve applies; a record's text would ride in the facts AND
      // make its figures "known" to the figure check. portal_turn.customerSafe drops them here, before the call, and fails
      // closed (a failed lookup withholds that corpus's every record; a corpus with no rule is withheld unless it is named
      // in PASS_THROUGH). The rules and the 27 Oct counts are in portal_turn.ts.
      const all = await customerSafe((r.records || []) as Array<Record<string, unknown>>, async (rule, ids) => {
        const x = await admin.from(rule.table).select(rule.select).in(rule.key, ids);
        return { data: x.data as Record<string, unknown>[] | null, error: x.error };
      });
      const [own, convo, brief, key] = await Promise.all([pOwn, pConvo, pBrief, pKey]);
      lap('reads');
      const ownQuote = own?.facts ?? null;
      const convKey = convo.key; const stored = convo.turns;
      const transcript = stored && stored.length ? stored : clientHistory(body.history).filter((h, i, a) => !(i === a.length - 1 && h.role === 'user' && h.content === message));
      // the facts change per turn, so they ride with the message, after the cached brief, rules and earlier turns
      const facts = portalFacts({ facts: ownQuote ? 'THEIR OWN QUOTES (scoped in SQL to this customer):\n' + ownQuote : '', passages: all });
      const sys = '\n\n' + aiSystem({ seat: 'sales_engineer', channel: 'the signed-in customer portal', audience: 'customer', lang, message, rules: portalRules(), plainText: true }, lang);
      const allowed = figureSource(brief) + '\n' + facts + '\n' + sys;
      const known = briefNumbers(allowed);
      // a photo or drawing the customer sent (ruling 1200): only what chat_images accepts reaches the model
      const images = acceptImages(body.images, new URL(Deno.env.get('SUPABASE_URL')!).host).images;
      const past = fitHistory(transcript.map((t) => ({ role: t.role === 'assistant' ? 'assistant' as const : 'user' as const, content: t.content })), message);
      const emit = EMITTERS.get(req) ?? (() => {});
      const a = key ? await answerFromBrief({
        gateway: Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway', secret: key, fn: 'sales_engineer', agent: 'sales_engineer',
        taskClass: 'customer_portal_assistant', brief, sys, max: images.length ? 1200 : 900, images, deadline,
        input: [...past, { role: 'user', content: (facts ? facts + '\n\n' : '') + 'MESSAGE:\n' + message.slice(0, 4000) }],
        // the same rules aiReply holds every conversation reply to (figures, policy, reply guard, another party's identity),
        // sentence by sentence; a deferral is a whole-answer judgement (aiReply), never one sentence's, so it is not run here
        check: (t: string) => [...guardSupportReply(t, lang).violations.map((v) => 'it breaks the reply rule "' + v + '"'),
          ...replyProblems(t, known, { allowed }).filter((p) => !/defers/.test(p)), ...wrappedReply(t), ...plainLanguage(t, lang)],
      }, emit) : { reply: '', model: null, attempts: ['no gateway credential'], rewrites: 0, streamed: false, error: 'no_model_credential' };
      lap('reply');
      const reply = a.reply.trim();
      try {
        await admin.from('assistant_logs').insert({ message, reply: reply || null, seat: 'sales_engineer', answered: !!reply, ...(convKey ? { conv_id: convKey } : {}),
          audience: caller.kind === 'customer' ? 'customer:' + caller.customerId : caller.kind, path: reply ? 'portal:reasoned' : 'portal',
          gap_task_id: (r.task_id as number | undefined) ?? null });  // the gap fn_sales_assist filed stays linked (review of #1043)
      } catch { /* the customer already has the answer; logging must not change the outcome */ }
      if (reply) {
        // the plain-language score of the reply that went out, for the monthly self-review, as supportReply recorded it
        try {
          const rd = checkReadability(reply, lang);
          await admin.rpc('fn_support_reply_readability_log', { p_channel: 'portal', p_lang: lang, p_path: 'reasoned', p_rewritten: a.rewrites > 0,
            p_score: rd.score, p_tone: rd.tone, p_issues: rd.issues, p_reason: null, p_demo: /^ZZ DEMO/.test(message) });
        } catch { /* the reply matters more than its score */ }
        await run('assist', 'ok', { answered: true, basis: 'reasoned', model: a.model, attempts: a.attempts, ms: T, precedent: recallTrace(memory) });
        return J({ ok: true, seat: 'sales_engineer', answered: true, reply, basis: 'composed by the model from the brief, the retrieved records and their own quotes', model: a.model });
      }
      // NO MODEL ANSWERED INSIDE THE TURN (rulings 1195/1196: code writes no reply text). The question is logged with the gap
      // fn_sales_assist filed; the portal shows its own notice and the conversation stays open.
      await run('assist', 'error', { answered: false, attempts: a.attempts, ms: T, task_id: r.task_id ?? null, precedent: recallTrace(memory) });
      return J({ ok: false, seat: 'sales_engineer', answered: false, error: 'no_answer', attempts: a.attempts, task_id: r.task_id ?? null }, 503);
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

      // ── WHOSE INQUIRY IT IS, AND WHO DECIDES ITS CRITERIA (23 Sep 2026) ────────────────────
      //
      // WHAT WAS MEASURED, because the finding handed over said something else. The hand-over said
      // "a signed-in customer can steer which suppliers receive somebody else's inquiry". A customer
      // CANNOT reach this branch: the cutoff above (`if (caller.kind === 'customer') return 403`)
      // refuses every portal caller before `match` is read. (#866 also noted that no service list
      // existed on the request at all; PR #859 added one on 23 Sep 2026, and it goes through the one
      // criteria source below like every other criterion, so a named inquiry still decides its own.)
      // Nor does any caller in the repository pass criteria: the ONE runtime
      // caller is customer_api.matchAndNotify, which sends `{action:'match', inquiry_id, persist:false}`
      // and nothing else. So the lever was reachable only with the sales_engineer credential, an
      // internal credential, or the founder's admin JWT.
      //
      // IT WAS STILL A REAL DOOR, and it was proved open on production before this change: the same
      // ZZ DEMO gypsum inquiry returned its own gypsum supplier on an honest call, and — with
      // `trades:['painting'], emirate:'Sharjah'` in the body and nothing else changed — returned
      // `asked_for.trades = ['painting']` and 0 matches instead. The body won over the stored row on
      // EVERY criterion, because every one of them was written `body.x || inq.x`. "Only our own
      // functions can reach it" is an argument about today's callers, not a guard.
      //
      // TWO RULES NOW.
      //  1. OWNERSHIP IS ENFORCED BY THE BUILD, NOT BY A BRANCH THAT CANNOT RUN. The obvious fix —
      //     `if (caller.kind === 'customer' && inq.customer_id !== caller.customerId) return 403` —
      //     DOES NOT COMPILE here, and that is the evidence rather than an inconvenience: `deno check`
      //     reports `Property 'customerId' does not exist on type 'never'`, because the cutoff above
      //     has already returned for every customer, so the only kinds that reach this line are
      //     sales_engineer, founder and service. Writing that branch anyway, with a cast to silence
      //     the compiler, would read as protection while asserting nothing — and would carry a
      //     bilingual refusal string no customer could ever be shown. So the invariant is stated as a
      //     type below: if the `match` branch is ever moved above that cutoff, `caller` widens, the
      //     assignment stops compiling and the green build goes red.
      //  2. A NAMED INQUIRY DECIDES ITS OWN CRITERIA. When inquiry_id resolves, the stored row is
      //     the only source and the body contributes nothing but `persist` — which declines a write
      //     and can therefore narrow nobody. The body is read only when NO inquiry is named, and
      //     then there is no third party to steer: that path is an operator exercising the matcher.
      const inquiryId = String(body.inquiry_id || '').trim();
      let inq: Record<string, unknown> | null = null;
      if (inquiryId) {
        const { data } = await admin.from('inquiries')
          // BOTH SIDES KEPT on the merge of 23 Sep 2026: customer_id for #866's ownership invariant,
          // service_keys for this branch's p_services gate.
          .select('id,customer_id,summary,raw_input,category,keywords,trades,emirate,scope_type,role_needed,budget,expected_value,boq,service_keys')
          .eq('id', inquiryId).maybeSingle();
        if (!data) return J({ ok: false, error: 'inquiry_not_found', inquiry_id: inquiryId }, 404);
        inq = data as Record<string, unknown>;
      }

      // THE OWNERSHIP INVARIANT, ENFORCED BY `deno check` (see rule 1 above). No customer caller can
      // reach `match`: the cutoff earlier in this handler returns 403 for `caller.kind === 'customer'`
      // before any action below it is read. This assignment is the only thing standing between that
      // fact and a silent regression — move `match` above the cutoff, or add a customer variant that
      // skips it, and the type widens and the build fails. customer_id is selected above so the
      // ownership comparison is one line away the day a customer-facing caller does reach this path.
      const _onlyOperatorsReachMatch: Exclude<typeof caller, { kind: 'customer' }> = caller;
      void _onlyOperatorsReachMatch;

      const arr = (v: unknown): string[] =>
        (Array.isArray(v) ? v : []).map((x) => String(x).trim().toLowerCase()).filter(Boolean);

      // THE ONE SOURCE OF CRITERIA (see the two rules above). `src` is the stored inquiry whenever
      // one is named, and the body ONLY when none is — mapped onto the stored column names so that
      // nothing below has to ask which it is reading, and so that no criterion can be written as
      // `body.x || inq.x` again without the check noticing.
      const src: Record<string, unknown> = inq ?? {
        trades: body.trades, emirate: body.emirate, scope_type: body.project_type,
        role_needed: body.need, expected_value: body.value, budget: body.value,
        summary: body.text, raw_input: null, category: null, keywords: [],
        // The request's own service list belongs here with every other criterion (merge of #866 and
        // #859, 23 Sep 2026): on a NAMED inquiry `src` is the stored row, so the stored service_keys
        // decide and the request's list is never consulted — a caller cannot narrow somebody else's
        // match to the services it chooses. On an unnamed call there is no third party to steer.
        service_keys: body.services,
      };
      // NO STORED EQUIVALENT, SAID OUT LOUD. `inquiries` carries no products and no brands column —
      // the select above is the whole of what this path reads. On a NAMED inquiry they are therefore
      // EMPTY, which is both what the one runtime caller sends today and the only non-narrowing
      // choice: a product or brand term switches the relevance floor ON (relevanceFloorApplies) and
      // can only REMOVE suppliers, and letting a caller remove suppliers from somebody else's match
      // is the whole finding. They are deliberately NOT derived from `keywords`: that would turn the
      // floor on for every inquiry, which is the exact condition that scored aluminium at 5.0 against
      // a floor of 35 and invited nobody (measured 15 Sep 2026, smoke run 34888342875). On an
      // UNNAMED call there is no third party to steer, so the caller's own terms are used.
      const products = inq ? [] : arr(body.products);
      const brands = inq ? [] : arr(body.brands);

      // TRADES. The customer's own words resolved through taxonomy_trade.aliases by
      // public.fn_norm_trades — the estate's normaliser, word-START anchored so 'sign' matches
      // "signage" and not "design". Reused, not re-written.
      // A single-trade request stores its trade in `category` only (12 Oct 2026, run f4294be8: 9 of 9
      // matched nobody) — tradeSlugsOf tries that slug on its own before the brief is read.
      let trades = tradeSlugsOf(src);
      // STORED TRADES ARE INTAKE SLUGS, THE MATCHER SPEAKS TAXONOMY CODES (14 Sep 2026). 39 of the 56
      // intake slugs are not taxonomy codes ('glass' is 'glazing', 'fitout' is 'interior_fitout' ...),
      // and passing them through made fn_match_capability answer zero for every request in those
      // categories — measured: ['glass'] matched nobody while ['aluminium'] matched both demo
      // suppliers. public.fn_taxonomy_trades_for is the one resolver
      // (scripts/sql/every_intake_trade_resolves_to_the_capability_vocabulary.sql). It is EXACT ONLY
      // (founder, 14 Sep 2026: "either exact match or no match"): a slug resolves to itself and to the
      // same trade's taxonomy code, never to a neighbour. A category nobody is registered for matches
      // nobody, and the no-match path below says so honestly.
      if (trades.length) {
        const { data: codes, error: resErr } = await admin.rpc('fn_taxonomy_trades_for', { p_slugs: trades });
        if (!resErr && Array.isArray(codes)) trades = arr(codes);
      }
      const brief = [src.summary, src.raw_input, src.category, arr(src.keywords).join(' ')]
        .map((x) => String(x ?? '')).filter(Boolean).join(' ').slice(0, 4000);
      if (!trades.length && brief) {
        const { data: nt } = await admin.rpc('fn_norm_trades', { p_text: brief });
        trades = arr(nt);
      }

      // WHAT THE CUSTOMER NEEDS DONE, not what a supplier would like to sell. taxonomy_role
      // decides which roles can serve each; this only picks the column.
      const needAsked = inq ? '' : body.need;
      const need = String(needAsked ?? '').trim() ||
        (String(src.scope_type || '').toLowerCase().includes('turnkey')
          ? 'whole_scope'
          : (/supply|material|product/i.test(String(src.scope_type || src.role_needed || '')) ? 'supplies' : 'executes'));

      // VALUE. Only a number that is actually a number gates the size band; a budget we cannot read
      // stays null, because an unreadable budget parsed as 0 would exclude every supplier with a
      // minimum. "Unknown mandatory evidence is not a pass" cuts the other way too: it is not a
      // fail either — it is unknown, and an unknown value simply does not gate.
      const num = (v: unknown): number | null => {
        const n = Number(String(v ?? '').replace(/[^0-9.]/g, ''));
        return Number.isFinite(n) && n > 0 ? n : null;
      };
      const value = num(src.expected_value) ?? num(src.budget);
      const emirate = matchEmirate(src.emirate);
      const projectType = String(src.scope_type ?? '').trim() || null;

      // THE RELEVANCE FLOOR IS READ, NOT COMPILED IN (decision_policy.match_relevance_floor = 35, measured 9 Sep 2026).
      const { data: polRows } = await admin.from('decision_policy').select('key,value')
        .in('key', ['match_relevance_floor']);
      const pol = Object.fromEntries((polRows || []).map((r: { key: string; value: unknown }) => [r.key, Number(r.value)]));
      // EVERY MATCHED SUPPLIER IS INVITED (founder ruling 24 Sep 2026: ANY number of suppliers may quote; "top 3" is
      // only the comparison report's recommendation). The per-trade cap of 3 and the ceiling of 5 left a 4th capable
      // supplier uninvited (sandbox run 1c94fa6a S07). No count caps the invitation; the SQL gates and the relevance
      // floor decide who is matched. match_max_fanout / _per_trade are no longer read.
      const floor = Number.isFinite(pol.match_relevance_floor) ? pol.match_relevance_floor : 35;

      const policy = { max_fanout: null, max_fanout_per_trade: null, relevance_floor: floor };
      // HAVE WE MATCHED THIS KIND OF JOB BEFORE, AND HOW DID IT END? (23 Sep 2026.) By meaning, within
      // the same trade only (the exact-trade rule), never this inquiry itself. Evidence in the answer;
      // it does not change the SQL gates — a precedent informs the seat, it does not pick suppliers.
      const memory = await recallCases(admin, {
        seat: 'sales_engineer', path: 'match', situation: brief,
        // The same key the case row is written under (trg_case_memory_inquiry: trades[1], else category).
        trade: inq ? (arr(inq.trades)[0] || String(inq.category ?? '') || null) : null,
        exclude: inquiryId ? { table: 'inquiries', id: inquiryId } : null,
        // this worker's own gte-small session, not a second one
        embedding: brief ? await Promise.race([embed(brief), new Promise<null>((r) => setTimeout(() => r(null), 1500))]) : null,
      });
      // BOTH SIDES KEPT on the merge of 23 Sep 2026: `services` is this branch's p_services record,
      // `criteria_from` is #866's.
      const askedFor = { trades, need, products, brands, project_type: projectType, value, emirate, services: [] as string[], services_read: null as string | null };
      // WHERE EVERY FIGURE ABOVE CAME FROM, printed rather than assumed. A reader of a match record
      // should not have to diff the body against the inquiry to know which decided.
      const criteriaFrom = inq ? 'stored_inquiry' : 'request_body_no_inquiry_named';

      if (!trades.length) {
        // NOT A FAILURE AND NOT A COVERAGE GAP. Nobody was asked, because there was no question:
        // the brief names no trade this taxonomy recognises. Widening it to "everything" to produce
        // a list would be exactly the padding the grant forbids.
        await run('match', 'ok', { inquiry_id: inquiryId || null, trades: 0, matched: 0, gap: 'no_trade_identified' });
        return J({
          ok: true, seat: 'sales_engineer', inquiry_id: inquiryId || null, asked_for: askedFor, criteria_from: criteriaFrom, policy, precedent: memory,
          candidates: 0, above_floor: 0, matched: [], persisted: 0,
          gap: { reason: 'no_trade_identified',
            note: 'The brief names no trade in taxonomy_trade, so fn_match_capability was not called. This is a brief that needs a question answered, not a supply gap.' },
        });
      }

      // ── THE SERVICES THE INQUIRY NAMES ────────────────────────────────────────────────────────
      // The founder calls services "our cross matching main source" (15 Sep 2026, instruction
      // 438/439): the supplier's CONFIRMED service list decides who receives a request, exact or
      // none. fn_match_capability has taken p_services since 15 Sep and gates on it — and MEASURED
      // 22 Sep 2026, NO caller passed it: this matcher, customer_api's preview, inquiry_intake's
      // supplier count and public_site all sent 8 arguments, so every request in production was
      // matched at TRADE level and the services a supplier spent its Services tab confirming
      // decided nothing at all.
      //
      // ONE READER, THE SUPPLIER'S OWN. _shared/service_vocabulary.ts serviceKeysOf reads the brief and
      // BOQ with the rule the Services tab reads a supplier's words with: a phrase that IS a service, or
      // one that MEANS it over the stored service vectors (never an alias word inside it: ruling 890,
      // decision point 93, 29 Sep 2026). All or nothing: a text it could not read whole gives NO keys
      // (trade level, nobody dropped), and that "not read" is never stored as "names nothing".
      //
      // STORED, NOT RE-DERIVED. inquiries.service_keys carries what the reader found; null means
      // never derived (an inquiry created before this column), '{}' means derived and the brief
      // names no service in the taxonomy. Both are safe: an empty p_services leaves every
      // candidate through, so a brief the vocabulary does not recognise falls back to trade-level
      // matching and NOBODY is dropped for it. The derivation is stored on first use, which is
      // also how a pre-existing inquiry acquires its keys.
      //
      // NULL AND '{}' ARE DIFFERENT, and only the column itself can tell them apart — `arr` flattens
      // both to an empty list, so the derivation is decided by Array.isArray on the stored value, not
      // by the length. '{}' means a reader already looked and the brief names no service this taxonomy
      // knows; re-deriving it on every match would re-read the vocabulary for nothing.
      let serviceKeys = arr(src.service_keys);
      let servicesRead: string | null = null;
      if (inq && !Array.isArray(inq.service_keys)) {
        const sk = await serviceKeysOf(brief, inq.boq, { services: await serviceVocab(admin), embed: remoteEmbedder(admin, 'sales_engineer') });
        serviceKeys = sk.keys; servicesRead = sk.state;
        // Stored only when the whole text was read; a failed write must not stop the match (the keys
        // are still used for this run). An unread text stays null and is read again on the next match.
        if (sk.complete) await admin.from('inquiries').update({ service_keys: serviceKeys }).eq('id', inquiryId);
      }
      askedFor.services = serviceKeys;
      askedFor.services_read = servicesRead;

      // Every gated candidate, not a top N (fn_match_capability applies `limit greatest(1, p_limit)`).
      const headroom = MATCH_ALL;
      const { data: rowsRaw, error: matchErr } = await admin.rpc('fn_match_capability', {
        p_trades: trades, p_need: need, p_products: products, p_brands: brands,
        p_project_type: projectType, p_value: value, p_emirate: emirate, p_limit: headroom,
        p_services: serviceKeys,
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
      // THE FLOOR GATES ONLY WHAT IT CAN MEASURE (15 Sep 2026). Measured on production:
      // fn_match_capability(['aluminium']) with no products scored two verified, confirmed demo
      // aluminium suppliers at 5.0 (the product term is 0 and size is unknown, 0.5 x 10), and with
      // products ['aluminium windows'] at 45.0. customer_api's create_inquiry match sends no products,
      // so against the floor of 35 every supplier without a track record was dropped and a ready
      // aluminium request invited nobody (smoke run 34888342875: 0/3 matched). The #658 check calls
      // the SQL directly and never met this floor. With no product named there is no relevance to
      // measure; the exact trade already is the relevance test ("either exact match or no match"),
      // so the floor gates only when products were asked for. No count cap applies after it.
      const aboveFloor = relevanceFloorApplies(products) ? rows.filter((r) => Number(r.score) >= floor) : rows;

      const picked = aboveFloor;

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
          ? 'No supplier cleared fn_match_capability\'s hard gates for this trade, role, authority, value band, emirate and availability (a busy or paused supplier is skipped). This is a supply-coverage gap, or every capable supplier is busy: the demand is real and nobody can answer it now. customer_api flags it to the stalled-inquiry rescue (fn_stalled_inquiry_flag).'
          : 'Suppliers cleared the hard gates but none reached the configured relevance floor. Lowering the floor to produce a list is expressly forbidden by the sales.matching grant.',
        recovery: 'Recorded and pursued by customer_api.flagCoverageGap() on the create_inquiry path (agent_actions coverage_gap + founder_alerts + owner notification). The customer\'s scope is not widened, the project is not split, and no supplier choice is put to the founder.',
      };

      await run('match', 'ok', {
        inquiry_id: inquiryId || null, trades: trades.length, candidates: rows.length,
        above_floor: aboveFloor.length, matched: matched.length, persisted, gap: gap?.reason ?? null,
      });

      return J({
        ok: true, seat: 'sales_engineer', caller: caller.kind, precedent: memory,
        inquiry_id: inquiryId || null,
        asked_for: askedFor, criteria_from: criteriaFrom, policy,
        candidates: rows.length, above_floor: aboveFloor.length,
        matched, persisted, gap,
        grant: { grant: may.grant, limit: may.limit },
        basis: 'public.fn_match_capability — supplier-confirmed scope, trade intersection, declared exclusions, contracted role, mandatory authorities, project-value band, emirate coverage and each supplier\'s own availability (busy or paused is skipped) applied as SQL gates before ranking; then decision_policy\'s relevance floor; every supplier left is invited, with no count cap. No model was called and no supplier was added to reach a count.',
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
      // A lookup box over the sector catalogue, not a matching judgement. Characters that are PostgREST filter
      // syntax are dropped so the caller's text cannot add conditions to the or() below.
      const q = String(body.q || '').replace(/[,()*%\\:."]/g, ' ').trim();
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
});

// THE PORTAL ANSWER STREAMS (27 Oct 2026, the same contract as the website widget: _shared/stream_reply.ts). A portal
// `assist` call that sends `Accept: application/x-ndjson` gets a status line at once (so the edge's 150 s idle wall can
// never fire on a turn that is working), then each checked sentence as the model writes it, then `done` with the same
// object the JSON answer carries. Every other action, and any caller without that header, is answered exactly as before.
// One handler answers both, so the observe row and every side effect are identical for either caller.
Deno.serve(async (req) => {
  if (req.method !== 'POST' || !wantsStream(req)) return plain(req);
  const raw = await req.text();
  let b: { action?: unknown; message?: unknown; lang?: unknown } = {};
  try { b = JSON.parse(raw); } catch (_e) { b = {}; }
  const inner = new Request(req.url, { method: 'POST', headers: req.headers, body: raw });
  if (b.action !== 'assist') return plain(inner);
  const lang = langOf(String(b.message || ''), String(b.lang || '').toLowerCase().startsWith('ar') ? 'ar' : 'en');
  return new Response(streamReply(STATUS[lang], (emit) => { EMITTERS.set(inner, emit); return plain(inner).then((r) => r.json()) as Promise<Record<string, unknown>>; }),
    { headers: { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no', ...CORS } });
});

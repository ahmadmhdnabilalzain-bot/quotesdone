// sales_engineer — the no-exact-spec offer pass (founder_instruction #321): customerContact, tellCustomer, specOfferSweep.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { requestDelivery } from '../../_shared/deliver.ts';
import { registeredLocale } from '../../_shared/registered_locale.ts';
import { portalLink } from '../../_shared/site_origins.ts';
import { noExactSpec, offerMessage, apologyMessage, offerTexts, type OfferForText } from '../../_shared/line_specs/no_exact_spec.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { arabicTextsFor } from '../../_shared/reasoned_governance.ts';
import { reasonedOffers } from '../../_shared/reasoned_matching.ts';
import { recallCases, recallTrace } from '../../_shared/case_recall.ts';
import { admin, sec } from '../context.ts';
import { embed } from '../lib/embed.ts';

// ── NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321) ─────────────────────────────────
// One pass: (1) inquiries whose quote window closed, or whose invited suppliers all quoted, are
// checked once against quote_compare's technical comparison (eligible quotes only) and an offer opens
// for every mandatory requested value no eligible quote matches while at least one offers another;
// (2) due reminders go out and lapsed offers close with an apology. State and timing: Postgres.
export async function customerContact(customerId: string | null) {
  if (!customerId) return null;
  const { data } = await admin.from('customers').select('id,email,locale,is_demo').eq('id', customerId).maybeSingle();
  return data || null;
}
// deno-lint-ignore no-explicit-any
export async function tellCustomer(o: any, kind: 'offer' | 'reminder' | 'apology_no_reply', msg: { subject: string; body: string }, lang: 'en' | 'ar', cust: any): Promise<number[]> {
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
export async function specOfferSweep(limit: number) {
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

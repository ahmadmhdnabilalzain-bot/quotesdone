// customer_api — the lifecycle and discovery: activity, trades, discover.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { defaultDeps } from '../../_shared/think.ts';
import { NONE, tradeOfText } from '../../_shared/reasoned_trades.ts';
import { scrubIdentity } from '../../supplier_api/identity_scrub.ts';
import { scoreInMatcherOrder, withoutPartnerWhy } from '../../_shared/partner_match.ts';
import { type ActionCtx, J, admin } from '../context.ts';
import { supplierLabel } from '../lib/inquiry_rules.ts';

export async function discoveryActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, cust } = c;
    // ── §8 / §6: THE RECORDED LIFECYCLE, SERVED TO THE CUSTOMER ────────────────────────────────
    // fn_entity_activity carries the QD_RFQ_TRACE branch — dated milestone / event / quote / match
    // entries — and its only reader was os_api, the staff console. The customer's own portal
    // derived the stage in the browser from quotes.length and anyRevealed: a guess sitting on top
    // of a recorded fact.
    //
    // IDENTITY IS SCRUBBED, NOT TRUSTED. The trace's own text names suppliers — its quote entries
    // read "Quotation AED 250000 from supplier #3251" and its match entries carry route_inquiry's
    // free-text reason, which is generated against a candidate list built as `#<id> — <Company
    // Name>`. Every title and body goes through the same scrubIdentity the quote surface uses,
    // against the company name of every supplier this customer has NOT paid to reveal on this RFQ.
    // Suppliers already revealed are left alone: the customer bought that name.
    if (action === 'activity') {
      const iid = String(body.inquiry_id || '');
      const { data: own } = await admin.from('inquiries').select('id').eq('id', iid).eq('customer_id', cust.id).maybeSingle();
      if (!own) return J({ error: 'Not your inquiry' }, 403);
      const { data: trace, error: te } = await admin.rpc('fn_entity_activity', { p_entity: 'inquiry', p_id: iid });
      if (te) return J({ error: te.message }, 500);
      const { data: qs } = await admin.from('quotes').select('id,supplier_id').eq('inquiry_id', iid);
      const { data: txs } = await admin.from('transactions').select('quote_id').eq('customer_id', cust.id);
      const revealedQuotes = new Set((txs || []).map((t: any) => String(t.quote_id)));
      const hiddenSupIds = [...new Set((qs || []).filter((q: any) => !revealedQuotes.has(String(q.id))).map((q: any) => q.supplier_id))];
      const { data: ms } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', iid);
      for (const m of (ms || [])) if (!hiddenSupIds.includes(m.supplier_id)) hiddenSupIds.push(m.supplier_id);
      const names: string[] = [];
      if (hiddenSupIds.length) { const { data: ls } = await admin.from('leads').select('company_name').in('id', hiddenSupIds); for (const l of ls || []) if (l.company_name) names.push(String(l.company_name)); }
      const hits: string[] = [];
      const clean = (t: unknown) => { let s = t == null ? null : String(t); for (const n of names) s = scrubIdentity(s, n, hits); return s; };
      const entries = (Array.isArray(trace) ? trace : []).map((e: any) => ({
        at: e.at ?? null, kind: e.kind ?? null, actor: e.actor ?? null,
        title: clean(e.title), status: e.status ?? null,
      }));
      return J({ ok: true, inquiry_id: iid, entries, entries_count: entries.length, redacted: hits.length });
    }

    // ── §9 SUPPLIER DISCOVERY, AS ITS OWN ACT ───────────────────────────────────────────────────
    // "Customer does not search. They ask." Both matchers existed and both sat on the DISPATCH
    // path only — discovery happened as a side effect of sending an RFQ, and no customer action
    // invoked it on its own, so the spec's "Found: 47 suppliers / Filtered: UAE, capacity,
    // certification" screen had nothing behind it.
    //
    // NO COMPANY NAMES. fn_match_capability returns company_name and this endpoint drops it: the
    // entire product sells the supplier's identity at reveal, and a free discovery call that
    // listed names would give away the thing being sold. The customer gets the COUNT, the FILTERS
    // that were applied, and a ranked, anonymous shortlist — which is what they need to decide
    // whether the brief is worth sending.
    // The controlled vocabulary the trades box is actually matched against. It is served because
    // the box is free text and fn_match_capability compares with `sc.trades && p_trades` — an exact
    // array overlap on CODES. A customer typing a perfectly ordinary word gets silence otherwise.
    if (action === 'trades') {
      const { data: tr } = await admin.from('taxonomy_trade').select('code,label').eq('active', true).order('sort');
      return J({ ok: true, trades: tr || [] });
    }

    if (action === 'discover') {
      const typed = Array.isArray(body.trades) ? body.trades.map((t: unknown) => String(t).toLowerCase().trim()).filter(Boolean).slice(0, 6) : [];
      if (!typed.length) return J({ error: 'trades_required', message: 'Name at least one trade to search for.' }, 400);
      // ── A WORD THAT IS NOT A CODE MATCHED NOTHING, SILENTLY ──────────────────────────────────
      // MEASURED 13 Aug 2026: typing "marble" into this box returns nothing, and so does the
      // screen's own worked example. taxonomy_trade holds 40 active codes — civil_works, flooring,
      // building_materials, aluminium — and `marble` is not one of them, nor one of the 283
      // aliases. fn_match_capability compares CODES with an exact array overlap, so the query was
      // for a trade that cannot exist and the answer was an empty list with no hint that the word
      // itself was the problem.
      //
      // route_inquiry has resolved customer words through taxonomy_trade.aliases since it was
      // written; discovery never did. Same lexicon, same three steps — code, alias, then label —
      // and whatever still does not resolve is REPORTED rather than searched for and lost.
      //
      // 23 Sep 2026 (founder_instruction 886-903): the alias list and the label substring decided what a typed word
      // MEANT — gone. A word that IS a code (picked from trades_known) is that code; any other word is REASONED
      // among the taxonomy (decision point customer_api.resolve_trade): exactly one trade, or none. Held, the word
      // is reported back as still being confirmed and is not searched; nothing is queued, because the answer is
      // this live search, which the customer runs again.
      const { data: taxo } = await admin.from('taxonomy_trade').select('code,label').eq('active', true);
      const codes = (taxo || []).map((t: { code: string }) => String(t.code));
      const resolved: string[] = []; const unresolved: string[] = []; const confirming: string[] = [];
      for (const w of typed) {
        let c: string | null = codes.find((x: string) => x.toLowerCase() === w) ?? null;
        if (!c) {
          const t = await tradeOfText(defaultDeps(admin, 'customer_api'), {
            surface: 'customer_api.resolve_trade', text: w, audience: 'customer', queueWhenHeld: false,
            options: (taxo || []).map((r: { code: string; label: string }) => ({ slug: String(r.code), label: String(r.label || r.code) })),
          });
          if (t.value === null) { confirming.push(w); continue; }
          c = t.value !== NONE && codes.includes(t.value) ? t.value : null;
        }
        if (c && !resolved.includes(c)) resolved.push(c); else if (!c) unresolved.push(w);
      }
      if (!resolved.length) {
        return J({ ok: true, found: 0, matches: [], anonymous: true,
          filters: { trades: [], emirate: body.emirate ? String(body.emirate).slice(0, 40) : null },
          unresolved, confirming: confirming.length ? confirming : undefined,
          why_empty: { suppliers_holding_trade: 0, confirmed_total: 0, reason: confirming.length && !unresolved.length ? 'trade_being_confirmed' : 'not_a_trade_we_know' },
          trades_known: (taxo || []).map((t: Record<string, unknown>) => ({ code: t.code, label: t.label })),
          note: 'Supplier identities are revealed after a quote is accepted, so discovery returns ranked, anonymous matches.' });
      }
      const trades = resolved;
      const filters = {
        trades,
        emirate: body.emirate ? String(body.emirate).slice(0, 40) : null,
        need: ['executes', 'supplies', 'both'].includes(String(body.need)) ? String(body.need) : 'executes',
        products: Array.isArray(body.products) ? body.products.map((s: unknown) => String(s)).slice(0, 8) : [],
        brands: Array.isArray(body.brands) ? body.brands.map((s: unknown) => String(s)).slice(0, 8) : [],
        project_type: body.project_type ? String(body.project_type).slice(0, 40) : null,
        value: Number.isFinite(Number(body.value)) ? Number(body.value) : null,
        limit: Math.min(24, Math.max(1, Number(body.limit) || 12)),
      };
      // trade-level by design: no brief — `discover` is a free-text TRADES box, so the customer has
      // named trades and not a job, and there is no summary or BOQ to read service keys from. Every
      // matcher that DOES have a brief passes p_services (SP-F-01, 22 Sep 2026), and the check
      // scripts/checks/every_matcher_that_has_a_brief_passes_its_services.test.mjs reads this marker
      // per CALL, so a second matcher added in this file is not exempt by living here.
      const { data: rows, error: me } = await admin.rpc('fn_match_capability', {
        p_trades: filters.trades, p_need: filters.need, p_products: filters.products, p_brands: filters.brands,
        p_project_type: filters.project_type, p_value: filters.value, p_emirate: filters.emirate, p_limit: filters.limit,
      });
      if (me) return J({ error: me.message }, 500);
      const hits2: string[] = [];
      const ranked = scoreInMatcherOrder(rows || []);   // the % ranks as the matcher ranked (services/REPORT.md 3.7)
      const matches = (rows || []).map((r: any, i: number) => ({
        label: 'Supplier ' + supplierLabel(i),
        match_pct: Number.isFinite(ranked[i]) ? Math.round(ranked[i] * (ranked[i] <= 1 ? 100 : 1)) : null,
        trades: r.trades || null, roles: r.roles || null,
        product_hits: r.product_hits ?? 0, brand_hit: !!r.brand_hit, project_type_hit: !!r.ptype_hit,
        track_record: r.track ?? null,
        why: scrubIdentity(withoutPartnerWhy(r.why) || null, r.company_name, hits2),   // the partner fact stays internal (services/REPORT.md 3.7)
      }));
      // ── A ZERO HAS TO NAME ITS OWN REASON ────────────────────────────────────────────────────
      // MEASURED 13 Aug 2026, typing this screen's OWN worked example into it: "Found 0 suppliers —
      // No registered supplier matches that yet." The database holds 20,470 leads and 15,306
      // supplier_capabilities rows, EVERY ONE of them carrying trades. What it does not hold is
      // confirmations: fn_match_capability gates on `sc.confirmed_at is not null`, and exactly ONE
      // row in 15,306 satisfies it. So the matcher can return at most one supplier for any query,
      // and the sentence on screen blamed the wrong thing.
      //
      // That distinction is the whole decision behind the screen. "No supplier matches that" reads
      // as "you need more suppliers" — buy scraping, run outreach. "1,143 suppliers do that trade
      // and none has confirmed their scope" reads as "chase confirmations", which is a different
      // action, cheaper, and the correct one. A count is not an explanation.
      //
      // The GATE IS NOT WEAKENED. Matching an unconfirmed scope would put a customer's RFQ in front
      // of a supplier who never said they do the work — the exact thing confirmed_at exists to
      // prevent. Only the explanation is added.
      let why_empty = null;
      if (!matches.length) {
        const [{ count: holding }, { count: confirmedTotal }] = await Promise.all([
          admin.from('supplier_capabilities').select('supplier_id', { count: 'exact', head: true }).overlaps('trades', filters.trades),
          admin.from('supplier_capabilities').select('supplier_id', { count: 'exact', head: true }).not('confirmed_at', 'is', null),
        ]);
        why_empty = {
          suppliers_holding_trade: holding || 0,
          confirmed_total: confirmedTotal || 0,
          reason: (holding || 0) === 0 ? 'no_supplier_holds_this_trade' : 'held_but_unconfirmed',
        };
      }
      return J({ ok: true, found: matches.length, filters, matches, anonymous: true, why_empty,
        unresolved: unresolved.length ? unresolved : undefined, confirming: confirming.length ? confirming : undefined,
        note: 'Supplier identities are revealed after a quote is accepted, so discovery returns ranked, anonymous matches.' });
    }
}

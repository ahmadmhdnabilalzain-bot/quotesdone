// supplier_portal — market, quote_recommend, document_impact, knowledge_graph, product_match, certifications, tier, scorecard, opportunities, advisor, products, insights.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
import { defaultDeps } from '../../_shared/think.ts';
import { productsAsked } from '../../_shared/reasoned_matching.ts';
import { type ActionCtx, J, loadFailed, admin } from '../context.ts';

export async function marketActions(c: ActionCtx): Promise<Response | undefined> {
  const { b, action, supId } = c;
    if (action === 'market') {
      const { data: mkt, error } = await admin.rpc('fn_supplier_market', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...mkt });
    }

    // ROW #5 §11 — THE AI QUOTE BUILDER. fn_supplier_quote_recommend proposes the price, delivery,
    // warranty, terms, market position and risk for THIS supplier on ONE enquiry, computed from the
    // competing bids on that same enquiry. p_lead_id is the authenticated supplier, never a
    // parameter — a supplier must not be able to ask what someone else should charge, and the
    // routine's `your_index` leg reads that supplier's own pricing history.
    if (action === 'quote_recommend') {
      const inqId = String(b.inquiry_id || '');
      if (!inqId) return J({ error: 'inquiry_id required' }, 400);
      const { data: rec, error } = await admin.rpc('fn_supplier_quote_recommend',
        { p_lead_id: supId, p_inquiry_id: inqId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...rec });
    }

    // ROW #5 §16 §4 — WHAT EACH DOCUMENT IS EARNING, AND WHAT THE MISSING ONE IS COSTING.
    if (action === 'document_impact') {
      const { data: di, error } = await admin.rpc('fn_supplier_document_impact', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...di });
    }

    // ROW #5 §23 — THE KNOWLEDGE GRAPH, READ RATHER THAN REBUILT NIGHTLY AND IGNORED.
    // fn_supplier_knowledge_graph returns CATEGORY structure only: the categories this company is
    // listed in and the adjacent ones its competitors also serve, computed from lead_category's
    // 17,107 rows. Employee, department and goal nodes are QuotesDone's internal org chart and the
    // routine never selects them — a supplier is not an audience for our reporting lines.
    if (action === 'knowledge_graph') {
      const { data: kg, error } = await admin.rpc('fn_supplier_knowledge_graph', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...kg });
    }

    // §10 — RANKED OPPORTUNITIES. "Recommended for you", ordered by fit score and never by date.
    //
    // The ranking itself is fn_supplier_opportunities: it is a query over inquiries, leads and
    // quotes, so it belongs in SQL where the planner can see the indexes, not in a loop here
    // pulling rows across the wire to sort them. What this action must NOT do is re-sort the
    // result — a browser or an edge function reordering a list it already holds is not ranking,
    // and the routine has already ordered by fit_score desc.
    //
    // The reasons ride along with each opportunity: trade, location, capacity fits, and previous
    // similar project — each carrying whether it applied and, when it could not be asked at all,
    // why. With 0 completed jobs the history reason is unanswerable for EVERY supplier, and it
    // says so rather than reading as "you have no relevant experience".
    // §12 (the negotiation assistant) and the 3D network map action were removed 21 Sep 2026 — founder
    // instructions 525/526. fn_supplier_negotiation and fn_supplier_network_map are dropped by
    // scripts/sql/the_last_traces_of_bank_details_negotiations_and_the_network_map_leave.sql.

    if (action === 'product_match') {
      const inquiryId = String(b.inquiry_id || '');
      if (!inquiryId) return J({ error: 'inquiry_id required' }, 400);
      // ONLY AN ENQUIRY THIS SUPPLIER WAS MATCHED TO (IDOR, it_engineer 19 Oct 2026, launch-checklist
      // security pass). p_inquiry_id was taken straight from the body and fn_supplier_product_match
      // reads public.inquiries (summary, raw_input, category) for ANY id, with no membership check —
      // unlike fn_supplier_quote_recommend, which gates on inquiry_matches. A signed-in supplier could
      // probe any inquiry's existence and category, and feed another party's raw_input (which may carry
      // unmasked customer detail) into a platform-billed think() call. Gate it here, the same way
      // supplier_api gates extract_quote/submit_quote through matchedInquiry().
      const { data: mm } = await admin.from('inquiry_matches').select('id').eq('inquiry_id', inquiryId).eq('supplier_id', supId).limit(1);
      if (!mm || !mm.length) return J({ error: 'not_your_inquiry', code: 'not_your_inquiry' }, 403);
      // WHICH OF HIS PRODUCTS THE ENQUIRY ASKS FOR IS REASONED, not counted in shared words (founder_instruction
      // 886-903; decision point 26): the routine hands back the enquiry and his products, think() reads them
      // (reasoned_matching.ts productsAsked), and the routine is asked again with the answer. Held: the list is
      // shown unscored with status 'needs_reasoning' — never a word-count percentage.
      const { data: pm, error } = await admin.rpc('fn_supplier_product_match',
        { p_inquiry_id: inquiryId, p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      // deno-lint-ignore no-explicit-any
      const tr: any = (pm as any)?.to_reason;
      if (!tr?.products?.length || !tr.want) return J({ ok: true, ...pm, to_reason: undefined });
      const asked = await productsAsked(defaultDeps(admin, 'supplier_portal'), { want: String(tr.want), products: tr.products, inquiryId, leadId: Number(supId) });
      if (asked.value == null) return J({ ok: true, ...pm, to_reason: undefined, held: true });
      const { data: pm2, error: e2 } = await admin.rpc('fn_supplier_product_match',
        { p_inquiry_id: inquiryId, p_lead_id: supId, p_asked: asked.value });
      if (e2) return loadFailed(String(action), e2);
      return J({ ok: true, ...pm2 });
    }

    // §16 §24 — every certificate with its validity status and what it gates.
    if (action === 'certifications') {
      const { data: certs, error } = await admin.rpc('fn_supplier_certifications', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...certs });
    }

    // §20 — the QuotesDone supplier tier and the ladder above it.
    if (action === 'tier') {
      const { data: tier, error } = await admin.rpc('fn_supplier_tier', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...tier });
    }

    // THE MONTHLY SCORECARD (29 Sep 2026, sales_engineer, founder_instruction 1013 item 2): last month's response
    // speed, win rate and rating against his trade (an average only over 3+ suppliers), one tip by rule, English
    // only. fn_supplier_scorecard in scripts/sql/a_supplier_sees_its_monthly_scorecard_against_its_trade.sql.
    if (action === 'scorecard') {
      const { data: card, error } = await admin.rpc('fn_supplier_scorecard', { p_lead: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, card });
    }

    if (action === 'opportunities') {
      const { data: opps, error } = await admin.rpc('fn_supplier_opportunities', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...opps });
    }

    if (action === 'advisor') {
      const { data: advice, error } = await admin.rpc('fn_supplier_advisor', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...advice });
    }

    if (action === 'products') {
      const { data: prods, error } = await admin.rpc('fn_supplier_products', {
        p_lead_id: supId,
        p_query: typeof b.q === 'string' && b.q.trim() ? b.q.trim().slice(0, 120) : null,
      });
      if (error) return loadFailed(String(action), error);
      return J({ ok: true, ...prods });
    }

    // WHICH INTELLIGENCE PANELS HAVE ANYTHING TO SAY (14 Sep 2026).
    //
    // The dashboard showed 24 equal tabs; twelve were panels over populations their own routines
    // report as empty (0 quotes and 0 inquiries estate-wide — see the ROW #5 notes above), and on a
    // 375px phone the strip alone was 366px tall. The portal now shows a journey and ONE "Insights"
    // section that lists only the panels answered here as available.
    //
    // Only two of these routines return a top-level `available` at all (grep of
    // scripts/sql/the_portals_come_back.sql, 14 Sep), so the rule is stated rather than assumed: a
    // panel is available when its routine answered without error, did not say `available:false`, and
    // its answer holds at least one non-empty list or positive number within two levels. The
    // routines express an empty population as zeros and empty arrays, never as a failure, so this is
    // the same fact they already report, read the same way for every panel.
    if (action === 'insights') {
      const hasSignal = (v: unknown, depth: number): boolean => {
        if (v == null || typeof v === 'string' || typeof v === 'boolean') return false;
        if (typeof v === 'number') return v > 0;
        if (Array.isArray(v)) return v.length > 0;
        if (depth <= 0) return false;
        return Object.values(v as Record<string, unknown>).some((x) => hasSignal(x, depth - 1));
      };
      const panels: [string, string, Record<string, unknown>][] = [
        ['twin', 'fn_supplier_twin', { p_lead_id: supId }],
        ['market', 'fn_supplier_market', { p_lead_id: supId }],
        ['network', 'fn_supplier_knowledge_graph', { p_lead_id: supId }],
        ['workspaces', 'fn_supplier_workspaces', { p_lead_id: supId }],
        ['recommended', 'fn_supplier_opportunities', { p_lead_id: supId }],
        ['ranking', 'fn_supplier_tier', { p_lead_id: supId }],
        ['certifications', 'fn_supplier_certifications', { p_lead_id: supId }],
        ['products', 'fn_supplier_products', { p_lead_id: supId, p_query: null }],
        ['assistant', 'fn_supplier_advisor', { p_lead_id: supId }],
      ];
      const out = await Promise.all(panels.map(async ([key, fn, args]) => {
        try {
          const { data, error } = await admin.rpc(fn, args);
          if (error) return { key, available: false, basis: 'routine_error' };
          const d = data as Record<string, unknown> | null;
          if (d && typeof d === 'object' && d.available === false) return { key, available: false, basis: String(d.basis || 'routine_reports_unavailable') };
          const ok = hasSignal(d, 2);
          return { key, available: ok, basis: ok ? 'data' : 'empty_population' };
        } catch (_e) { return { key, available: false, basis: 'routine_error' }; }
      }));
      return J({ ok: true, panels: out });
    }
}

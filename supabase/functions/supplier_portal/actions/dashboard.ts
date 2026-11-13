// supplier_portal — dashboard, notifications, overview, twin, workspaces.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
import { revealedBy, workspacesBeforeReveal } from '../before_reveal.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { readSupplierProfile } from '../../_shared/reasoned_suppliers.ts';
import { runtimeWaitUntil } from '../../_shared/async_webhook.ts';
import { buildAlerts, buildDashboard, buildNotifications, supplierCard, type Supplier } from '../overview.ts';
import { type ActionCtx, J, loadFailed, admin } from '../context.ts';

export async function dashboardActions(c: ActionCtx): Promise<Response | undefined> {
  const { sup, action, supId } = c;
    // THE OVERVIEW IN ONE CALL (15 Sep 2026): stats, alerts, eligibility, document impact and the
    // notification counts, every independent read started together. See ./overview.ts for the measurement.
    if (action === 'dashboard') { const r = await buildDashboard(admin, sup as Supplier); return J(r.body, r.status); }
    // The bell's two counts alone: what the portal re-reads after the supplier leaves Messages.
    if (action === 'notifications') return J({ ok: true, notifications: await buildNotifications(admin, supId) });

    if (action === 'overview') {
      const [{ data: stats, error }, { count: activeMatches }, alerts] = await Promise.all([
        admin.rpc('fn_supplier_stats', { p_supplier_id: supId }),
        admin.from('inquiry_matches').select('id', { count:'exact', head:true }).eq('supplier_id', supId),
        buildAlerts(admin, supId),
      ]);
      if (error) return loadFailed(String(action), error);
      return J({ ok:true, supplier: supplierCard(sup as Supplier), stats, active_matches: activeMatches || 0, alerts, alerts_count: alerts.length });
    }

    // ROW #5 §3 §4 §6 §13 — THE SUPPLIER'S OWN DIGITAL TWIN AND HEALTH PANEL.
    //
    // supplier_score holds `reliability` and `response_rate` non-null on 20,464 of 20,464 rows on
    // production, and until this action existed the supplier surface could reach NEITHER. The
    // portal already renders `{s.response_rate != null && <Stat …/>}` — a tile whose guard could
    // never be true, because no endpoint returned the field. This is that missing read path.
    //
    // The whole payload comes from ONE routine, fn_supplier_twin, so the numbers a supplier sees
    // are the numbers the database computed rather than a second derivation that can drift from it.
    if (action === 'twin') {
      // What the capability summary and the supplier's own service words MEAN is reasoned (think(),
      // _shared/reasoned_suppliers.ts; founder_instruction 886-903), once per text, AFTER this response:
      // the page never waits on a model, and under the hold the reading is queued and the twin shows the
      // capabilities from keyed data with capability_reading 'needs_reasoning'.
      runtimeWaitUntil()?.(readSupplierProfile(defaultDeps(admin, 'supplier_portal'), supId).catch((e) => console.error('supplier reading failed:', String(e))));
      const { data: twin, error } = await admin.rpc('fn_supplier_twin', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      // A demo fixture must never be presentable as a live account. fn_supplier_twin sets is_demo
      // from the fence itself (matching_blocked AND a 'demo' tag), so the flag cannot drift from
      // the thing it describes, and the UI can label the row rather than passing it off as real.
      return J({ ok: true, twin });
    }

    // ROW #5 §7 §8 — PRODUCT INTELLIGENCE.
    //
    // supplier_product, supplier_product_variant and supplier_catalog are a complete schema —
    // jsonb attributes, certifications, evidence_refs, catalog versioning by source_hash, variants
    // with price and lead-time policy — that had 0 rows AND 0 readers on production, confirmed by
    // two independent scans against a control. Built and abandoned. This is the read path.
    //
    // `q` searches names, brands, models, categories AND attribute values, so "5000 CFM" finds the
    // unit whose specification says so rather than only matching a title.
    // ROW #5 §15 §4 — THE AI EMPLOYEE. "Why am I losing RFQs?" answered from real columns.
    //
    // The loss BREAKDOWN is empty on purpose while there are 0 quotes estate-wide, and the payload
    // says `basis: 'no_completed_opportunities'` so an empty array is never mistaken for a failed
    // computation. The RECOMMENDATIONS half is real today: every gap is derived from a column the
    // supplier can act on, and impact_rfqs counts live inquiries rather than quoting the spec's
    // illustrative "32 more projects".
    // ROW #5 §19 — THE SUPPLIER NETWORK MAP. Supplier density by emirate from 20,464 real leads;
    // demand, projects and shipments return EMPTY with a stated basis, because there are 0
    // inquiries and no shipments relation at all. A globe speckled with invented demand looks like
    // market intelligence and is nothing.
    // ROW #5 §14 — MARKET INTELLIGENCE. Competitor counts and supply composition are real (20,464
    // leads with sectors and emirates). Demand trend, most-requested and average price are COMPUTED
    // from their populations and fall back to available:false with the empty population named — the
    // availability flag is derived from a count, not hard-coded, so the routine tells the truth on
    // both sides of the day a category starts trading. An arrow reading "HVAC demand up 18%" against
    // zero inquiries would be indistinguishable from real market intelligence on screen, so the
    // percentage stays NULL whenever the prior period is empty rather than being computed from zero.
    // Demo fixtures and live rows are partitioned symmetrically inside the routine, so the demo
    // market cannot move a real supplier's competitor count or market price.
    // ROW #5 §18 — COLLABORATION WORKSPACES, one per customer relationship. Seeded on both projects
    // with one fenced demo relationship (scripts/sql/demo_inquiry_row5.sql) under the founder's
    // standing "create demo for whatever is needed". The cost was stated rather than hidden: each
    // inquiry insert fires fn_emit_event('inquiry','rfq.created'), which injects a synthetic row
    // into row #2's separately-measured event backbone for that row's next run to subtract.
    if (action === 'workspaces') {
      const { data: ws, error } = await admin.rpc('fn_supplier_workspaces', { p_lead_id: supId });
      if (error) return loadFailed(String(action), error);
      // before a reveal: the trade and the emirate, never a customer sentence or file name (./../before_reveal.ts)
      return J({ ok: true, ...workspacesBeforeReveal(ws as Record<string, unknown>, await revealedBy(admin, supId)) });
    }
}

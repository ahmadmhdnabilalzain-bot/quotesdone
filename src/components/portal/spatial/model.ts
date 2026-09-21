// Spec §6 (3D Project Visualization) and §19 (Project Room / Supply Chain Map) — the shapes the
// three endpoints actually serve, and the pure derivations the surfaces share.
//
// EVERY type below is transcribed from a real response. Nothing here is invented:
//   project_api        action:'detail'  -> { project: <public.projects row>, rfqs: [<10 inquiry cols>] }
//   procurement_api    action:'orders'  -> { orders: [...] }  == public.fn_customer_orders(uuid)
//   customer_documents action:'list'    -> { documents: [...] } == shape() in that edge function
//   customer_api       action:'my_inquiries' -> the rows CustomerPortal already holds (quotes[])
// If a field is not here, nothing serves it. Do not add one without adding it there first.
//
// ── WHAT THIS PROJECT'S DATA CAN AND CANNOT SAY ABOUT A BUILDING ────────────────────────────────
// MEASURED on production, 6 Aug 2026:
//   * NO relation carries a storey/level/floor for a procurement package. project_api never reads
//     or writes projects.meta; the only 'floor' in the estate is the `flooring` TRADE CATEGORY in
//     inquiry_intake's keyword table, which is a job type, not a level of a building.
//   * NO relation carries an origin AND a destination on one row (the query the scorer runs
//     returns zero tables), so there is no geographic route to draw and no warehouse hop at all.
// So a per-floor component model does not exist. This module therefore derives geometry from what
// IS real — one block per LINKED RFQ, banded by its own trade category — and calls those bands
// trade packages, never floors. `levelsFromMeta` is the single documented path by which a real
// storey model can arrive; until a project carries one, `source` says so and the surface prints it.
//
// This module imports nothing so ./selfcheck.mjs can exercise it straight off the repo.

export type Lang = 'en' | 'ar';

/** One row of public.projects — what project_api action:'detail' returns in `project`. */
export interface SpatialProject {
  id: string;
  name: string;
  description: string | null;
  status: string;
  target_open_date: string | null;
  budget_total: number | null;
  meta: Record<string, unknown> | null;
  created_at: string;
}

/** Exactly the inquiry columns project_api action:'detail' selects. */
export interface SpatialRfq {
  id: string;
  category: string | null;
  emirate: string | null;
  summary: string | null;
  status: string | null;
  pipeline_stage: string | null;
  budget: number | null;
  expected_value: number | null;
  hired_supplier_id: string | null;
  created_at: string;
}

/** One po_lines row as fn_customer_orders nests it. */
export interface OrderLine {
  line_no: number | null;
  description: string | null;
  qty: number | null;
  unit_price: number | null;
  qty_received: number | null;
}

/**
 * One order as fn_customer_orders builds it. `status` is CHECK-constrained on public.po_orders to
 * exactly: draft | approved | partial | received | billed | closed | cancelled.
 */
export interface CustomerOrder {
  id: number | string;
  po_no: string | null;
  status: string | null;
  order_date: string | null;
  expected_date: string | null;
  currency: string | null;
  subtotal: number | null;
  memo: string | null;
  inquiry_id: string | null;
  quote_id: string | null;
  project_id: string | null;
  approved_at: string | null;
  lines: OrderLine[];
}

/** The subset of customer_documents' shape() this module renders. */
export interface VaultDoc {
  id: number;
  kind: string;
  file_name: string | null;
  created_at: string;
  source: string;
  ref_table: string | null;
  ref_id: string | null;
  supplier: string | null;
  supplier_revealed: boolean;
  expiry_date: string | null;
  covers: string | null;
}

/** A my_inquiries row, narrowed to the two things this module needs from it. */
export interface PortalInquiry {
  id: string;
  quotes?: Array<{ id: string; price?: number | null; supplier?: string | null; supplier_name?: string | null; revealed?: boolean }>;
}

/**
 * The default for the optional `inquiries` prop, declared ONCE at module scope.
 * `inquiries = []` in a parameter list mints a new array on every render, which changes the
 * identity buildModel() is memoised on, which rebuilds the whole three.js scene — a fresh WebGL
 * context, fresh geometry and a visible flicker — on every keystroke anywhere above it.
 */
export const NO_INQUIRIES: PortalInquiry[] = [];

// ── STAGE ───────────────────────────────────────────────────────────────────────────────────────
// The spec names three (Ordered / Quotation / Delivered). A real RFQ spends most of its life before
// the first of them, and calling that state "Quotation" when no quote has arrived would be the
// empty-state lie this portal has already been burned by once. So there are four, and the fourth is
// the honest one: `requested`.
export type PackageStage = 'requested' | 'quotation' | 'ordered' | 'delivered';

/** po_orders.status values that mean the goods are in. Restricted to the CHECK constraint's domain. */
const DELIVERED_ORDER_STATUS = ['received', 'closed', 'billed'];
const DEAD_ORDER_STATUS = ['cancelled'];

/** Sum of a numeric line field, ignoring nulls. */
const sum = (lines: OrderLine[], k: 'qty' | 'qty_received' | 'unit_price'): number =>
  lines.reduce((a, l) => a + (Number(l?.[k]) || 0), 0);

/**
 * Share of an order's ordered quantity that has been received, 0..1, or null when the order carries
 * no quantities at all. NEVER returns 0 for "unknown" — a receipt bar at zero and a receipt bar that
 * cannot be computed are different facts and the surface prints them differently.
 */
export function receivedFraction(order: CustomerOrder): number | null {
  const lines = Array.isArray(order?.lines) ? order.lines : [];
  const ordered = sum(lines, 'qty');
  if (!(ordered > 0)) return null;
  return Math.max(0, Math.min(1, sum(lines, 'qty_received') / ordered));
}

/**
 * The stage of one procurement package, from real fields only.
 *
 *   delivered — an order for this RFQ is received/closed/billed, or its lines are fully received
 *   ordered   — an order exists, or the customer has hired a supplier (this product's "order")
 *   quotation — at least one quote has arrived (from the customer's own my_inquiries row)
 *   requested — everything else, including "sent to suppliers and nobody has answered"
 *
 * Cancelled orders are ignored rather than treated as progress.
 */
export function stageOf(rfq: SpatialRfq, orders: CustomerOrder[], quoteCount: number): PackageStage {
  const mine = (orders || []).filter(
    (o) => o && o.inquiry_id === rfq.id && !DEAD_ORDER_STATUS.includes(String(o.status || '')),
  );
  for (const o of mine) {
    const f = receivedFraction(o);
    if (DELIVERED_ORDER_STATUS.includes(String(o.status || '')) || f === 1) return 'delivered';
  }
  if (mine.length > 0) return 'ordered';
  if (rfq.hired_supplier_id) return 'ordered';
  if (quoteCount > 0) return 'quotation';
  return 'requested';
}

// ── LEVELS ──────────────────────────────────────────────────────────────────────────────────────

export interface SpatialPackage {
  rfqId: string;
  /** The trade. project_api serves `category`; an RFQ with none is grouped as 'unspecified'. */
  category: string;
  stage: PackageStage;
  /** expected_value, else the revealed quote's price, else budget, else null. Never 0-for-unknown. */
  value: number | null;
  summary: string | null;
  emirate: string | null;
  createdAt: string;
  /** The live orders for this RFQ, in the order fn_customer_orders returned them. */
  orders: CustomerOrder[];
}

export interface SpatialLevel {
  key: string;
  label: string;
  packages: SpatialPackage[];
}

export interface SpatialModel {
  /**
   * 'project_meta_levels' — the customer's project carries a real storey model in projects.meta.
   * 'trade_packages'      — it does not, so the bands are trade categories and the surface says so.
   */
  source: 'project_meta_levels' | 'trade_packages';
  levels: SpatialLevel[];
  packageCount: number;
}

/**
 * The ONE documented contract by which real geometry can reach this viewer:
 *
 *   projects.meta.levels = [ "Ground", "L1", ... ]                       (labels only), or
 *   projects.meta.levels = [ { label: "L25", rfqs: ["<inquiry uuid>"] } ]
 *
 * Nothing writes this today — project_api neither selects nor sets `meta`, and production holds
 * zero projects. It is read rather than assumed so that the day a floor plan or BOM import writes
 * it, the viewer shows real storeys with no further change; until then `null` is the honest answer
 * and the caller falls back to trade bands.
 * ponytail: label+rfq-id list only. If real geometry (extents, coordinates, IFC/DXF) ever lands,
 * that is a different reader and a different scene builder — not a wider shape here.
 */
export function levelsFromMeta(meta: Record<string, unknown> | null | undefined): Array<{ label: string; rfqs: string[] }> | null {
  const raw = meta && typeof meta === 'object' ? (meta as Record<string, unknown>).levels : null;
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const out: Array<{ label: string; rfqs: string[] }> = [];
  for (const item of raw) {
    if (typeof item === 'string' && item.trim()) { out.push({ label: item.trim(), rfqs: [] }); continue; }
    if (item && typeof item === 'object') {
      const o = item as Record<string, unknown>;
      const label = typeof o.label === 'string' ? o.label.trim() : '';
      if (!label) continue;
      const rfqs = Array.isArray(o.rfqs) ? o.rfqs.filter((r): r is string => typeof r === 'string') : [];
      out.push({ label, rfqs });
    }
  }
  return out.length ? out : null;
}

const titleCase = (s: string) => s.replace(/(^|[\s_/-])([a-z])/g, (_m, a: string, b: string) => a + b.toUpperCase());

/**
 * The model the scene draws. One block per LINKED RFQ — never a block that stands for nothing.
 *
 * With a real storey model in meta, RFQs land on the level that names them and any RFQ no level
 * claims goes to an explicit "Unassigned" band rather than being silently dropped or silently
 * spread. Without one, the bands are the project's own trade categories, sorted so the same project
 * draws the same building twice running.
 */
export function buildModel(
  project: SpatialProject | null,
  rfqs: SpatialRfq[],
  orders: CustomerOrder[],
  inquiries: PortalInquiry[] = [],
): SpatialModel {
  const quoteCounts = new Map<string, number>();
  // 21 Sep 2026 (customer audit, finding 19): a revealed AED 25,920 quote read "no cost recorded".
  // The quote the customer paid to reveal IS the cost when expected_value is unset.
  const revealedPrice = new Map<string, number>();
  for (const i of inquiries || []) if (i && i.id) {
    quoteCounts.set(i.id, Array.isArray(i.quotes) ? i.quotes.length : 0);
    for (const q of i.quotes || []) if (q && q.revealed && Number(q.price) > 0) revealedPrice.set(i.id, Number(q.price));
  }

  const pkgs: SpatialPackage[] = (rfqs || []).map((r) => ({
    rfqId: r.id,
    category: (r.category || '').trim() || 'unspecified',
    stage: stageOf(r, orders || [], quoteCounts.get(r.id) || 0),
    value: r.expected_value != null ? Number(r.expected_value) : (revealedPrice.get(r.id) ?? (r.budget != null ? Number(r.budget) : null)),
    summary: r.summary,
    emirate: r.emirate,
    createdAt: r.created_at,
    orders: (orders || []).filter((o) => o && o.inquiry_id === r.id),
  }));

  const meta = levelsFromMeta(project?.meta);
  if (meta) {
    const claimed = new Set<string>();
    const levels: SpatialLevel[] = meta.map((l, i) => {
      const on = pkgs.filter((p) => l.rfqs.includes(p.rfqId));
      on.forEach((p) => claimed.add(p.rfqId));
      return { key: `meta:${i}`, label: l.label, packages: on };
    });
    const rest = pkgs.filter((p) => !claimed.has(p.rfqId));
    if (rest.length) levels.push({ key: 'meta:unassigned', label: 'Unassigned', packages: rest });
    return { source: 'project_meta_levels', levels, packageCount: pkgs.length };
  }

  const byCat = new Map<string, SpatialPackage[]>();
  for (const p of pkgs) {
    const arr = byCat.get(p.category);
    if (arr) arr.push(p); else byCat.set(p.category, [p]);
  }
  const levels: SpatialLevel[] = [...byCat.keys()].sort().map((c) => ({
    key: `cat:${c}`,
    label: titleCase(c),
    packages: byCat.get(c) as SpatialPackage[],
  }));
  return { source: 'trade_packages', levels, packageCount: pkgs.length };
}

// ── SUPPLY CHAIN ────────────────────────────────────────────────────────────────────────────────
// The spec draws Supplier Factory -> Warehouse -> Project Site with a live status.
//
// WHAT THE SCHEMA ACTUALLY HOLDS: po_orders links a vendor to a customer, an inquiry, a quote and a
// project, and carries a CHECK-constrained status and an expected_date; po_lines carry qty and
// qty_received. There is no coordinate, no origin, no destination and NO WAREHOUSE ROW ANYWHERE.
// So the chain below has TWO real nodes and one real edge — supplier -> site — and the middle hop
// is reported as having no data rather than drawn as an empty box a customer would read as a fact.
export type ChainStage = 'placed' | 'approved' | 'in_transit' | 'arrived' | 'cancelled';

export interface ChainLeg {
  orderId: string;
  poNo: string | null;
  /** 0..1 position along supplier -> site, derived from the order's own status and receipts. */
  progress: number;
  stage: ChainStage;
  received: number | null;
  expectedDate: string | null;
  orderDate: string | null;
  subtotal: number | null;
  currency: string | null;
  inquiryId: string | null;
  projectId: string | null;
  lineCount: number;
}

/**
 * One leg per order. `progress` is a POSITION derived from real fields, not a guess at where a
 * lorry is: draft 0, approved 0.25, partial interpolates on real received quantity, received/closed
 * /billed 1. A cancelled order keeps its last honest position and is marked, never hidden.
 */
export function chainLegs(orders: CustomerOrder[]): ChainLeg[] {
  return (orders || []).map((o) => {
    const st = String(o.status || 'draft');
    const f = receivedFraction(o);
    let stage: ChainStage = 'placed';
    let progress = 0;
    if (st === 'cancelled') { stage = 'cancelled'; progress = 0; }
    else if (DELIVERED_ORDER_STATUS.includes(st)) { stage = 'arrived'; progress = 1; }
    else if (st === 'partial') { stage = 'in_transit'; progress = 0.35 + 0.6 * (f == null ? 0.5 : f); }
    else if (st === 'approved') { stage = 'approved'; progress = 0.25; }
    return {
      orderId: String(o.id),
      poNo: o.po_no,
      progress: Math.max(0, Math.min(1, progress)),
      stage,
      received: f,
      expectedDate: o.expected_date,
      orderDate: o.order_date,
      subtotal: o.subtotal == null ? null : Number(o.subtotal),
      currency: o.currency,
      inquiryId: o.inquiry_id,
      projectId: o.project_id,
      lineCount: Array.isArray(o.lines) ? o.lines.length : 0,
    };
  });
}

// ── formatting ──────────────────────────────────────────────────────────────────────────────────
export const money = (n: number | null | undefined, currency = 'AED'): string =>
  n == null ? '—' : `${currency || 'AED'} ${Number(n).toLocaleString('en-AE', { maximumFractionDigits: 0 })}`;

export const fmtDate = (d: string | null | undefined, lang: Lang = 'en'): string => {
  if (!d) return '—';
  const t = new Date(d.length === 10 ? `${d}T00:00:00Z` : d).getTime();
  if (!Number.isFinite(t)) return '—';
  return new Date(t).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-AE', {
    year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC',
  });
};

/**
 * Share of the window between a project's creation and its target open date that has passed.
 * Identical rule and identical wording to ../projects/model.ts#elapsedPct on purpose: two surfaces
 * showing the same project must not compute two different timelines. Null when there is no target,
 * so the surface can say that rather than draw a bar out of nothing.
 */
export function elapsedPct(created_at: string, target_open_date: string | null, now: number = Date.now()): number | null {
  if (!target_open_date) return null;
  const start = new Date(created_at).getTime();
  const end = new Date(`${target_open_date}T00:00:00Z`).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
  return Math.max(0, Math.min(100, Math.round(((now - start) / (end - start)) * 100)));
}

/** Documents the vault holds for one RFQ. ref_table/ref_id is how public.documents records ownership. */
export function docsForRfq(docs: VaultDoc[], rfqId: string): VaultDoc[] {
  return (docs || []).filter((d) => d && d.ref_table === 'inquiries' && String(d.ref_id) === String(rfqId));
}

/** The stage palette, shared by the 3D scene and the DOM legend so the two can never disagree. */
export const STAGE_COLOR: Record<PackageStage, string> = {
  requested: '#64748b',
  quotation: '#f59e0b',
  ordered: '#38bdf8',
  delivered: '#22c55e',
};

export const STAGE_LABEL: Record<Lang, Record<PackageStage, string>> = {
  en: { requested: 'Requested', quotation: 'Quotation', ordered: 'Ordered', delivered: 'Delivered' },
  ar: { requested: 'مطلوب', quotation: 'عروض أسعار', ordered: 'تم الطلب', delivered: 'تم التسليم' },
};

export const CHAIN_LABEL: Record<Lang, Record<ChainStage, string>> = {
  en: { placed: 'Placed', approved: 'Approved', in_transit: 'In transit', arrived: 'Arrived on site', cancelled: 'Cancelled' },
  ar: { placed: 'صدر الطلب', approved: 'معتمد', in_transit: 'قيد الشحن', arrived: 'وصل إلى الموقع', cancelled: 'ملغى' },
};

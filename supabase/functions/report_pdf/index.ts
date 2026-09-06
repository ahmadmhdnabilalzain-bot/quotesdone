// report_pdf v1 (6 Sep 2026) — every report is a corporate PDF.
//
// Founder's order: "any report needs to be in PDF format; all finance reports need to be extremely
// organized in corporate PDF format." Until today the 515 rows behind report_registry (board_reports,
// exec_reports, finance_reports) reached the OS as on-screen text and JSON, and nothing anywhere
// produced a PDF of them.
//
// This function is DETERMINISTIC: no model call, no external fetch. It reads one report row, builds a
// document model (cover, table of contents, numbered sections, KPI statements with prior-period
// variance, bar charts drawn as rectangles), renders it with pdf-lib, stores the bytes in the private
// `reports` bucket at <kind>/<period>/<source>_<id>.pdf, records pdf_path / pdf_generated_at on the
// row, and answers with a short-lived signed URL.
//
// Callers: the action invoker (fn_action_invoke_dispatch, queued by the z_report_pdf_enqueue triggers
// the moment a report row is written) and os_api's report_pdf_url action (on demand from the OS).
// Both present a scoped internal credential; there is no JWT path.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'npm:pdf-lib@1.17.1';
import { requireInternal } from '../_shared/internal_auth.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BUCKET = 'reports';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

// ---------------------------------------------------------------------------------------------------
// Document model
// ---------------------------------------------------------------------------------------------------
type Cell = string | number | null | undefined;
type Block =
  | { t: 'h3'; text: string }
  | { t: 'p'; text: string; muted?: boolean }
  | { t: 'li'; text: string }
  | { t: 'table'; head: string[]; rows: Cell[][]; align?: ('l' | 'r')[]; total?: Cell[]; money?: boolean[] }
  | { t: 'chart'; title: string; series: { label: string; value: number }[]; money?: boolean };
type Section = { title: string; blocks: Block[] };
type Doc = { title: string; kind: string; period: string; preparedBy: string; generatedAt: string; summary: string; sections: Section[] };

const MONEY_RE = /aed|cash|burn|revenue|income|expense|amount|balance|arr|fee|spend|cost|net|inflow|outflow|forecast|savings|budget|cac|cpl|collected|outstanding|overdue|clearing|receivable|payable/i;
const isMoneyKey = (k: string) => MONEY_RE.test(k) && !/pct|count|rows|days|hours|months|_n$|score/i.test(k);
const nf2 = new Intl.NumberFormat('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const nf0 = new Intl.NumberFormat('en-AE', { maximumFractionDigits: 2 });
function fmtNum(v: unknown, money = false): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'boolean') return v ? 'Yes' : 'No';
  const n = typeof v === 'number' ? v : (typeof v === 'string' && v.trim() !== '' && !isNaN(Number(v)) ? Number(v) : NaN);
  if (isNaN(n)) return String(v);
  return money ? 'AED ' + nf2.format(n) : nf0.format(n);
}
function numOf(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  return isNaN(n) ? null : n;
}
const titleCase = (s: string) => String(s || '').replace(/[_\-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bAed\b/g, 'AED').replace(/\bPct\b/g, '%').replace(/\bWk\b/g, '(week)').replace(/\bRfq/g, 'RFQ').replace(/\bAi\b/g, 'AI').replace(/\bArr\b/g, 'ARR').replace(/\bKpi/g, 'KPI');

// A KPI statement: one row per scalar key, with the prior period's value and the variance when a prior
// row exists. Nested objects become their own statements (department report: sales, supply, finance...).
function kpiStatements(cur: Record<string, unknown> | null, prior: Record<string, unknown> | null, label = 'Key performance indicators'): Block[] {
  const out: Block[] = [];
  if (!cur || typeof cur !== 'object') return out;
  const scalars: Cell[][] = []; const money: boolean[] = [true, true, true, true];
  const groups: [string, Record<string, unknown>][] = [];
  for (const [k, v] of Object.entries(cur)) {
    if (v && typeof v === 'object' && !Array.isArray(v)) { groups.push([k, v as Record<string, unknown>]); continue; }
    if (Array.isArray(v)) continue;
    const m = isMoneyKey(k); const pv = prior && typeof prior === 'object' ? (prior as Record<string, unknown>)[k] : undefined;
    const a = numOf(v), b = numOf(pv);
    const variance = a !== null && b !== null ? a - b : null;
    scalars.push([titleCase(k), fmtNum(v, m), prior ? fmtNum(pv, m) : undefined, prior ? (variance === null ? '—' : (variance > 0 ? '+' : '') + (m ? nf2.format(variance) : nf0.format(variance))) : undefined]);
  }
  if (scalars.length) {
    const head = prior ? ['Metric', 'Current', 'Prior period', 'Variance'] : ['Metric', 'Value'];
    out.push({ t: 'h3', text: label });
    out.push({ t: 'table', head, rows: scalars.map((r) => r.slice(0, head.length)), align: head.map((_, i) => i === 0 ? 'l' : 'r'), money });
  }
  for (const [g, obj] of groups) out.push(...kpiStatements(obj, prior && typeof prior === 'object' && (prior as Record<string, unknown>)[g] && typeof (prior as Record<string, unknown>)[g] === 'object' ? (prior as Record<string, unknown>)[g] as Record<string, unknown> : null, titleCase(g)));
  return out;
}

// Board report bodies are plain text with UPPERCASE headings, "  Key: value" lines and "- " bullets.
function parseNarrative(body: string): Section[] {
  const sections: Section[] = []; let cur: Section | null = null; let kv: Cell[][] = [];
  const flushKv = () => { if (cur && kv.length) { cur.blocks.push({ t: 'table', head: ['Item', 'Value'], rows: kv, align: ['l', 'r'] }); kv = []; } };
  const lines = String(body || '').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i].replace(/\s+$/, '');
    if (i < 2 && (i === 0 || /^[=\-_]{3,}$/.test(raw))) continue;   // the title line and its underline
    if (!raw.trim()) { flushKv(); continue; }
    if (/^[=\-_]{3,}$/.test(raw)) continue;
    const t = raw.trim();
    const isHeading = t === t.toUpperCase() && /[A-Z]/.test(t) && t.length < 72 && !/^\s/.test(raw) && !/[a-z]/.test(t) && !/\d+\.\d+/.test(t);
    if (isHeading) { flushKv(); cur = { title: titleCase(t.toLowerCase()), blocks: [] }; sections.push(cur); continue; }
    if (!cur) { cur = { title: 'Overview', blocks: [] }; sections.push(cur); }
    const m = raw.match(/^\s{2,}([^:]{1,60}):\s*(.*)$/);
    if (m) { const key = m[1].trim(); const val = m[2].trim(); kv.push([key, isMoneyKey(key) && numOf(val) !== null ? fmtNum(val, true) : (numOf(val) !== null ? fmtNum(val) : (val || '—'))]); continue; }
    flushKv();
    if (/^[-•*]\s+/.test(t)) cur.blocks.push({ t: 'li', text: t.replace(/^[-•*]\s+/, '') });
    else cur.blocks.push({ t: 'p', text: t });
  }
  flushKv();
  return sections;
}

// A time series drawn from the last N reports of the same type: one chart per headline metric.
function trendCharts(history: { period: string; kpis: Record<string, unknown> | null }[], keys: string[]): Block[] {
  const out: Block[] = [];
  if (history.length < 2) return out;
  for (const k of keys) {
    const series = history.map((h) => ({ label: h.period, value: numOf(h.kpis?.[k]) ?? 0 }));
    if (series.every((s) => s.value === 0)) continue;
    out.push({ t: 'chart', title: titleCase(k) + ' — last ' + history.length + ' reports', series, money: isMoneyKey(k) });
  }
  return out;
}

// The statement pack every finance PDF carries, read live from fn_ws_finance (deterministic SQL):
// chart of accounts (cash), monthly cash flow, expense breakdown by account, P&L, run rate & runway.
async function financeStatements(): Promise<Section[]> {
  const { data, error } = await admin.rpc('fn_ws_finance');
  if (error || !data) return [{ title: 'Financial statements', blocks: [{ t: 'p', text: 'fn_ws_finance could not be read: ' + (error?.message || 'no data'), muted: true }] }];
  const f = data as Record<string, any>;
  const out: Section[] = [];
  const rr = f.run_rate || {}; const k = f.ai?.kpis || {};
  out.push({ title: 'Cash, runway and burn', blocks: [
    { t: 'table', head: ['Measure', 'Value'], align: ['l', 'r'], rows: [
      ['Cash position', fmtNum(f.cash?.total ?? k.cash, true)],
      ['Monthly burn (30d expense)', fmtNum(rr.monthly_burn ?? k.monthly_burn, true)],
      ['Revenue (30d)', fmtNum(rr.revenue_30d ?? k.revenue_30d, true)],
      ['Net (30d)', fmtNum(rr.net_30d, true)],
      ['Runway (months)', rr.runway_months == null ? '— (no positive cash to divide)' : fmtNum(rr.runway_months)],
      ['ARR estimate', fmtNum(rr.arr_estimate, true)],
      ['Receivables outstanding', fmtNum(k.ar_outstanding, true)],
      ['Payables outstanding', fmtNum(k.ap_outstanding, true)],
    ] },
    { t: 'p', text: 'Runway is cash divided by monthly burn. It is reported as "—" whenever cash is not positive, because a negative or zero balance has no runway to state.', muted: true },
  ] });
  const accounts: any[] = Array.isArray(f.cash?.accounts) ? f.cash.accounts : [];
  if (accounts.length) out.push({ title: 'Chart of accounts — cash and current assets', blocks: [
    { t: 'table', head: ['Code', 'Account', 'Balance'], align: ['l', 'l', 'r'], rows: accounts.map((a) => [String(a.code ?? ''), String(a.name ?? ''), fmtNum(a.balance, true)]), total: ['', 'Total', fmtNum(accounts.reduce((s, a) => s + (numOf(a.balance) ?? 0), 0), true)] },
  ] });
  const cf: any[] = Array.isArray(f.cashflow) ? f.cashflow : [];
  if (cf.length) out.push({ title: 'Monthly cash flow', blocks: [
    { t: 'table', head: ['Month', 'Inflow', 'Outflow', 'Net'], align: ['l', 'r', 'r', 'r'], rows: cf.map((m) => [String(m.month ?? ''), fmtNum(m.inflow, true), fmtNum(m.outflow, true), fmtNum(m.net, true)]),
      total: ['Total', fmtNum(cf.reduce((s, m) => s + (numOf(m.inflow) ?? 0), 0), true), fmtNum(cf.reduce((s, m) => s + (numOf(m.outflow) ?? 0), 0), true), fmtNum(cf.reduce((s, m) => s + (numOf(m.net) ?? 0), 0), true)] },
    { t: 'chart', title: 'Outflow by month', series: cf.map((m) => ({ label: String(m.month ?? ''), value: numOf(m.outflow) ?? 0 })), money: true },
    { t: 'chart', title: 'Net cash flow by month', series: cf.map((m) => ({ label: String(m.month ?? ''), value: numOf(m.net) ?? 0 })), money: true },
  ] });
  const eb: any[] = Array.isArray(f.expense_breakdown) ? f.expense_breakdown : [];
  if (eb.length) out.push({ title: 'Expense breakdown by account', blocks: [
    { t: 'table', head: ['Code', 'Account', 'Amount'], align: ['l', 'l', 'r'], rows: eb.map((e) => [String(e.code ?? ''), String(e.name ?? ''), fmtNum(e.amount, true)]), total: ['', 'Total expenses', fmtNum(eb.reduce((s, e) => s + (numOf(e.amount) ?? 0), 0), true)] },
    { t: 'chart', title: 'Expenses by account', series: eb.map((e) => ({ label: String(e.name ?? e.code ?? ''), value: numOf(e.amount) ?? 0 })), money: true },
  ] });
  const rb: any[] = Array.isArray(f.revenue_breakdown) ? f.revenue_breakdown : [];
  const pnl = f.pnl || {};
  out.push({ title: 'Profit and loss (all-time)', blocks: [
    { t: 'table', head: ['Line', 'Amount'], align: ['l', 'r'], rows: [
      ...rb.map((r) => ['  Revenue — ' + String(r.name ?? r.code ?? ''), fmtNum(r.amount, true)]),
      ['Revenue', fmtNum(pnl.revenue, true)],
      ['Expenses', fmtNum(pnl.expenses, true)],
      ['Margin %', pnl.margin_pct == null ? '—' : fmtNum(pnl.margin_pct) + '%'],
    ], total: ['Net income', fmtNum(pnl.net_income, true)] },
  ] });
  const budgets: any[] = Array.isArray(f.budgets) ? f.budgets : [];
  if (budgets.length) out.push({ title: 'Budgets', blocks: [{ t: 'table', head: Object.keys(budgets[0]).map(titleCase), rows: budgets.map((b) => Object.entries(b).map(([kk, v]) => fmtNum(v, isMoneyKey(kk)))) }] });
  return out;
}

// ---------------------------------------------------------------------------------------------------
// Row -> Doc
// ---------------------------------------------------------------------------------------------------
type Row = { source: 'board' | 'exec' | 'finance'; id: number; row: Record<string, any> };
const PREPARED: Record<string, string> = { board: 'Reporting & Analytics (reporting_ai)', exec: 'Executive Office', finance: 'Finance Department (finance_ai)' };

async function buildDoc(r: Row): Promise<Doc> {
  const generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
  if (r.source === 'board') {
    const b = r.row; const kind = String(b.report_type || 'report'); const period = String(b.week_start || String(b.created_at || '').slice(0, 10));
    const { data: hist } = await admin.from('board_reports').select('id,week_start,created_at,kpis').eq('report_type', kind).lt('created_at', b.created_at).order('created_at', { ascending: false }).limit(7);
    const prior = (hist && hist[0]?.kpis) || null;
    const sections = parseNarrative(String(b.body || ''));
    const kp = b.kpis && typeof b.kpis === 'object' ? b.kpis : null;
    const stmts = kpiStatements(kp, prior);
    if (stmts.length) sections.push({ title: 'KPI statement' + (prior ? ' with prior-period variance' : ''), blocks: stmts });
    const series = [...(hist || [])].reverse().concat([{ id: b.id, week_start: b.week_start, created_at: b.created_at, kpis: b.kpis }]).map((h: any) => ({ period: String(h.week_start || String(h.created_at).slice(0, 10)), kpis: h.kpis }));
    const keys = kp ? Object.keys(kp).filter((k) => numOf(kp[k]) !== null && !/health/.test(k)).slice(0, 4) : [];
    const charts = trendCharts(series, keys);
    if (charts.length) sections.push({ title: 'Trends across reports', blocks: charts });
    if (kind === 'finance') sections.push(...await financeStatements());
    // The cover summary: the EXECUTIVE SUMMARY paragraph when the body has one, else its first paragraph.
    const summary = (sections.find((s) => /summary/i.test(s.title)) || sections[0])?.blocks.find((x) => x.t === 'p');
    return { title: String(b.title || titleCase(kind) + ' report'), kind, period, preparedBy: kind === 'finance' ? PREPARED.finance : PREPARED.board, generatedAt, summary: summary && summary.t === 'p' ? summary.text : '', sections };
  }
  if (r.source === 'finance') {
    const f = r.row; const kind = 'finance_' + String(f.kind || 'report'); const period = String(f.period_start || String(f.created_at || '').slice(0, 10));
    const { data: prev } = await admin.from('finance_reports').select('id,period_start,kpis').eq('kind', f.kind).lt('created_at', f.created_at).order('created_at', { ascending: false }).limit(1).maybeSingle();
    const kp = (f.kpis && typeof f.kpis === 'object' ? f.kpis : {}) as Record<string, any>;
    const sections: Section[] = [];
    const paras = String(f.summary || '').split(/\n{2,}/).map((s) => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
    sections.push({ title: 'Executive summary', blocks: paras.map((p) => ({ t: 'p', text: p }) as Block) });
    const headline: Cell[][] = [];
    const pk = (prev?.kpis || {}) as Record<string, any>;
    for (const k of ['weekly_burn_aed', 'monthly_burn_aed', 'usage_7d_aed', 'usage_30d_aed', 'fees_collected_all', 'fees_recognized_all', 'fees_pending_all', 'refunds_all', 'inq_wk', 'quotes_wk', 'deals_wk', 'new_customers_wk', 'new_suppliers_wk']) {
      if (!(k in kp)) continue; const m = isMoneyKey(k); const a = numOf(kp[k]), b = numOf(pk[k]);
      headline.push([titleCase(k), fmtNum(kp[k], m), prev ? fmtNum(pk[k], m) : undefined, prev ? (a !== null && b !== null ? (a - b > 0 ? '+' : '') + (m ? nf2.format(a - b) : nf0.format(a - b)) : '—') : undefined]);
    }
    const head = prev ? ['Measure', 'This period', 'Prior period (' + String(prev.period_start || '') + ')', 'Variance'] : ['Measure', 'This period'];
    sections.push({ title: 'Cash and burn statement', blocks: [{ t: 'table', head, rows: headline.map((h) => h.slice(0, head.length)), align: head.map((_, i) => i === 0 ? 'l' : 'r') }] });
    const cat = kp.expenses_by_cat && typeof kp.expenses_by_cat === 'object' ? Object.entries(kp.expenses_by_cat as Record<string, number>) : [];
    if (cat.length) sections.push({ title: 'Recurring expenses by category (AED / month)', blocks: [
      { t: 'table', head: ['Category', 'AED / month'], align: ['l', 'r'], rows: cat.map(([c, v]) => [c, fmtNum(v, true)]), total: ['Total recurring', fmtNum(cat.reduce((s, [, v]) => s + (numOf(v) ?? 0), 0), true)] },
      { t: 'chart', title: 'Recurring expenses by category', series: cat.map(([c, v]) => ({ label: c, value: numOf(v) ?? 0 })), money: true },
    ] });
    const rows: any[] = Array.isArray(kp.expense_rows) ? kp.expense_rows : [];
    if (rows.length) sections.push({ title: 'Expense register', blocks: [{ t: 'table', head: ['Vendor', 'Category', 'Cadence', 'Billed', 'Normalised'], align: ['l', 'l', 'l', 'r', 'r'], rows: rows.map((x) => (Array.isArray(x) ? x : Object.values(x)).slice(0, 5).map((c) => String(c ?? ''))) }] });
    const uv = kp.usage_by_vendor && typeof kp.usage_by_vendor === 'object' ? Object.entries(kp.usage_by_vendor as Record<string, number>) : [];
    if (uv.length) sections.push({ title: 'Usage-billed vendors (last 30 days)', blocks: [{ t: 'table', head: ['Vendor', 'AED (30d)'], align: ['l', 'r'], rows: uv.map(([v, n]) => [v, fmtNum(n, true)]), total: ['Total usage', fmtNum(uv.reduce((s, [, n]) => s + (numOf(n) ?? 0), 0), true)] }] });
    sections.push(...await financeStatements());
    return { title: 'Finance Report — ' + titleCase(String(f.kind || '')) + ' ' + period + (f.period_end ? ' to ' + f.period_end : ''), kind, period, preparedBy: PREPARED.finance, generatedAt, summary: paras[0] || '', sections };
  }
  // exec
  const e = r.row; const kind = 'exec_summary'; const period = String(e.period || String(e.created_at || '').slice(0, 10));
  const { data: prev } = await admin.from('exec_reports').select('id,period,metrics').eq('officer', e.officer).lt('created_at', e.created_at).order('created_at', { ascending: false }).limit(1).maybeSingle();
  const sections: Section[] = [{ title: 'Executive summary', blocks: [{ t: 'p', text: String(e.summary || '—') }] }];
  const m = e.metrics && typeof e.metrics === 'object' ? e.metrics : null;
  const stmts = kpiStatements(m, prev?.metrics || null, 'Metrics');
  if (stmts.length) sections.push({ title: 'Metrics' + (prev ? ' with prior-period variance (' + String(prev.period || '') + ')' : ''), blocks: stmts });
  const findings: any[] = Array.isArray(e.findings) ? e.findings : [];
  if (findings.length) {
    const blocks: Block[] = [];
    for (const f of findings) {
      if (typeof f === 'string') { blocks.push({ t: 'li', text: f }); continue; }
      if (!f || typeof f !== 'object') continue;
      blocks.push({ t: 'h3', text: String(f.item || f.title || f.area || 'Contribution') + (f.owner ? ' — ' + String(f.owner) : '') + (f.health ? ' [' + String(f.health).toUpperCase() + ']' : '') });
      for (const key of ['wins', 'risks', 'ask', 'drivers', 'summary', 'detail', 'note']) if (f[key] && typeof f[key] === 'string') blocks.push({ t: 'p', text: titleCase(key) + ': ' + f[key] });
      if (f.kpis && typeof f.kpis === 'object') blocks.push(...kpiStatements(f.kpis, null, 'KPIs').filter((b) => b.t === 'table'));
      const rest = Object.entries(f).filter(([k, v]) => !['item', 'title', 'area', 'owner', 'health', 'wins', 'risks', 'ask', 'drivers', 'summary', 'detail', 'note', 'kpis', 'target'].includes(k) && (typeof v !== 'object' || v === null));
      if (rest.length) blocks.push({ t: 'table', head: ['Field', 'Value'], align: ['l', 'r'], rows: rest.map(([k, v]) => [titleCase(k), fmtNum(v, isMoneyKey(k))]) });
    }
    sections.push({ title: 'Contributions and findings', blocks });
  }
  const recs: any[] = Array.isArray(e.recommendations) ? e.recommendations : [];
  if (recs.length) {
    const objs = recs.filter((x) => x && typeof x === 'object');
    const blocks: Block[] = [];
    if (objs.length) blocks.push({ t: 'table', head: ['#', 'Recommendation', 'Owner', 'Impact / effort'], align: ['r', 'l', 'l', 'l'], rows: objs.map((x, i) => [String(x.rank ?? i + 1), String(x.title || x.action || x.recommendation || ''), String(x.owner || '—'), [x.impact, x.effort].filter(Boolean).join(' / ') || (x.confidence != null ? 'confidence ' + fmtNum(x.confidence) : '—')]) });
    for (const x of objs) if (x.ask || x.why) blocks.push({ t: 'p', text: String(x.title || x.action || '') + ': ' + [x.ask, x.why].filter(Boolean).join(' — ') });
    for (const x of recs) if (typeof x === 'string') blocks.push({ t: 'li', text: x });
    sections.push({ title: 'Recommendations', blocks });
  }
  const officer = String(e.officer || 'Officer'); const officerLabel = officer.length <= 4 ? officer.toUpperCase() : titleCase(officer);   // ceo -> CEO, competitive -> Competitive
  return { title: officerLabel + ' — Executive Report ' + period, kind, period, preparedBy: PREPARED.exec + ' (' + officer + ')', generatedAt, summary: String(e.summary || ''), sections };
}

// ---------------------------------------------------------------------------------------------------
// Renderer (pdf-lib, standard fonts, WinAnsi)
// ---------------------------------------------------------------------------------------------------
const NAVY = rgb(0.047, 0.137, 0.188), TEAL = rgb(0.078, 0.722, 0.651), INK = rgb(0.08, 0.094, 0.11), MUT = rgb(0.4, 0.44, 0.52), LINE = rgb(0.86, 0.88, 0.9), ZEBRA = rgb(0.965, 0.97, 0.975), WHITE = rgb(1, 1, 1), GOLD = rgb(0.906, 0.71, 0.235);
const PW = 595.28, PH = 841.89, M = 48, HEADER_H = 40, FOOTER_H = 36;
const SUBS: Record<string, string> = { '→': '->', '←': '<-', '…': '...', '✓': 'v', '✔': 'v', '✗': 'x', '⚠': '!', '≥': '>=', '≤': '<=', '≠': '!=', '−': '-', '‑': '-', ' ': ' ', '\t': '  ' };
function clean(s: unknown): string {
  let t = String(s == null ? '' : s);
  for (const [a, b] of Object.entries(SUBS)) t = t.split(a).join(b);
  let o = '';
  for (const ch of t) { const c = ch.codePointAt(0) || 0; o += (c < 0x7f && c >= 0x20) || (c >= 0xa0 && c <= 0xff) || '—–‘’“”•€™'.includes(ch) ? ch : '?'; }
  return o;
}
async function render(doc: Doc): Promise<{ bytes: Uint8Array; pages: number }> {
  const pdf = await PDFDocument.create();
  pdf.setTitle(doc.title); pdf.setAuthor('QuotesDone'); pdf.setSubject(doc.kind + ' ' + doc.period); pdf.setProducer('QuotesDone report_pdf'); pdf.setCreator('QuotesDone OS');
  const F = await pdf.embedFont(StandardFonts.Helvetica), B = await pdf.embedFont(StandardFonts.HelveticaBold);
  const pages: PDFPage[] = []; let page!: PDFPage; let y = 0;
  const w = (s: string, size: number, font: PDFFont = F) => font.widthOfTextAtSize(s, size);
  const wrap = (s: string, size: number, maxW: number, font: PDFFont = F): string[] => {
    const out: string[] = [];
    for (const para of s.split('\n')) {
      let line = '';
      for (const word of para.split(/\s+/)) {
        if (!word) continue;
        const cand = line ? line + ' ' + word : word;
        if (w(cand, size, font) <= maxW) line = cand;
        else { if (line) out.push(line); let ww = word; while (w(ww, size, font) > maxW && ww.length > 1) { let cut = ww.length - 1; while (cut > 1 && w(ww.slice(0, cut), size, font) > maxW) cut--; out.push(ww.slice(0, cut)); ww = ww.slice(cut); } line = ww; }
      }
      out.push(line);
    }
    return out.length ? out : [''];
  };
  const chrome = (p: PDFPage) => {
    p.drawRectangle({ x: 0, y: PH - HEADER_H, width: PW, height: HEADER_H, color: NAVY });
    p.drawText('QUOTESDONE', { x: M, y: PH - 25, size: 12, font: B, color: WHITE });
    p.drawRectangle({ x: M + w('QUOTESDONE', 12, B) + 6, y: PH - 27, width: 3, height: 12, color: TEAL });
    const hl = clean(doc.title); let s = hl; while (w(s, 9) > PW - 2 * M - 120 && s.length > 4) s = s.slice(0, -4) + '...';
    p.drawText(s, { x: PW - M - w(s, 9), y: PH - 24, size: 9, font: F, color: rgb(0.82, 0.87, 0.9) });
    p.drawLine({ start: { x: M, y: FOOTER_H }, end: { x: PW - M, y: FOOTER_H }, thickness: 0.6, color: LINE });
    p.drawText('Confidential — QuotesDone', { x: M, y: FOOTER_H - 14, size: 8, font: F, color: MUT });
    const mid = clean(doc.kind + ' · ' + doc.period + ' · generated ' + doc.generatedAt);
    p.drawText(mid, { x: (PW - w(mid, 8)) / 2, y: FOOTER_H - 14, size: 8, font: F, color: MUT });
  };
  const newPage = () => { page = pdf.addPage([PW, PH]); pages.push(page); chrome(page); y = PH - HEADER_H - 30; return page; };
  const ensure = (h: number) => { if (y - h < FOOTER_H + 12) newPage(); };
  const text = (s: string, size: number, opt: { font?: PDFFont; color?: ReturnType<typeof rgb>; x?: number; maxW?: number; gap?: number } = {}) => {
    const font = opt.font || F, color = opt.color || INK, x = opt.x ?? M, maxW = opt.maxW ?? (PW - M - x);
    for (const ln of wrap(clean(s), size, maxW, font)) { ensure(size * 1.45); page.drawText(ln, { x, y: y - size, size, font, color }); y -= size * 1.45; }
    y -= opt.gap ?? 4;
  };
  const table = (b: Extract<Block, { t: 'table' }>) => {
    const cols = b.head.length; const size = 8.5; const pad = 5; const totalW = PW - 2 * M;
    // Column widths: measure the widest wrapped-free content, cap, then scale to the page.
    const nat = b.head.map((h, i) => Math.max(w(clean(h), size, B), ...b.rows.map((r) => w(clean(String(r[i] ?? '')), size)), b.total ? w(clean(String(b.total[i] ?? '')), size, B) : 0) + 2 * pad);
    const capped = nat.map((n, i) => Math.min(n, i === 0 ? totalW * 0.5 : totalW * 0.4));
    const sum = capped.reduce((a, c) => a + c, 0); const widths = capped.map((c) => c * (totalW / sum));
    const align = b.align || b.head.map((_, i) => i === 0 ? 'l' : 'r');
    const rowH = (cells: Cell[], font: PDFFont) => Math.max(...cells.map((c, i) => wrap(clean(String(c ?? '')), size, widths[i] - 2 * pad, font).length)) * (size * 1.35) + 2 * pad;
    const drawRow = (cells: Cell[], font: PDFFont, fill: ReturnType<typeof rgb> | null, color = INK) => {
      const h = rowH(cells, font); ensure(h);
      if (fill) page.drawRectangle({ x: M, y: y - h, width: totalW, height: h, color: fill });
      let x = M;
      cells.forEach((c, i) => {
        const lines = wrap(clean(String(c ?? '')), size, widths[i] - 2 * pad, font); let ly = y - pad - size;
        for (const ln of lines) { const tx = align[i] === 'r' ? x + widths[i] - pad - w(ln, size, font) : x + pad; page.drawText(ln, { x: tx, y: ly, size, font, color }); ly -= size * 1.35; }
        x += widths[i];
      });
      y -= h;
    };
    const header = () => { drawRow(b.head, B, NAVY, WHITE); };
    header();
    b.rows.forEach((r, i) => { const before = pages.length; const h = rowH(r, F); if (y - h < FOOTER_H + 12) { newPage(); header(); } drawRow(r, F, i % 2 ? ZEBRA : null); if (pages.length !== before) { /* row moved with page */ } });
    if (b.total) { page.drawLine({ start: { x: M, y }, end: { x: PW - M, y }, thickness: 0.8, color: NAVY }); drawRow(b.total, B, rgb(0.93, 0.96, 0.97)); }
    page.drawLine({ start: { x: M, y }, end: { x: PW - M, y }, thickness: 0.5, color: LINE });
    y -= 10;
  };
  const chart = (b: Extract<Block, { t: 'chart' }>) => {
    const series = b.series.slice(0, 24); if (!series.length) return;
    const H = 130, W = PW - 2 * M, labelH = 28; ensure(H + labelH + 30);
    text(b.title, 9.5, { font: B, color: NAVY, gap: 2 });
    const top = y, base = y - H; const vals = series.map((s) => s.value);
    const max = Math.max(0, ...vals), min = Math.min(0, ...vals); const span = (max - min) || 1;
    const zeroY = base + ((0 - min) / span) * H;
    page.drawRectangle({ x: M, y: base, width: W, height: H, borderColor: LINE, borderWidth: 0.5 });
    page.drawLine({ start: { x: M, y: zeroY }, end: { x: M + W, y: zeroY }, thickness: 0.6, color: MUT });
    const slot = W / series.length, bw = Math.min(slot * 0.62, 36);
    series.forEach((s, i) => {
      const h = (Math.abs(s.value) / span) * H; const x = M + i * slot + (slot - bw) / 2;
      page.drawRectangle({ x, y: s.value >= 0 ? zeroY : zeroY - h, width: bw, height: Math.max(h, 0.5), color: s.value >= 0 ? TEAL : GOLD });
      const v = b.money ? nf0.format(Math.round(s.value)) : nf0.format(s.value); const vs = 6.5;
      // A negative bar's label sits just above the zero line, never under the bar where the axis labels live.
      if (w(v, vs) <= slot) page.drawText(v, { x: x + bw / 2 - w(v, vs) / 2, y: s.value >= 0 ? zeroY + h + 3 : zeroY + 3, size: vs, font: F, color: INK });
      let lb = clean(s.label); while (w(lb, 6.5) > slot - 2 && lb.length > 3) lb = lb.slice(0, -2); if (lb !== clean(s.label)) lb = lb.replace(/\.*$/, '') + '.';
      page.drawText(lb, { x: M + i * slot + slot / 2 - w(lb, 6.5) / 2, y: base - 10, size: 6.5, font: F, color: MUT });
    });
    const unit = b.money ? 'AED' : ''; if (unit) page.drawText(unit, { x: M + 4, y: top - 10, size: 7, font: F, color: MUT });
    y = base - labelH;
  };

  // ---- cover ------------------------------------------------------------------------------------
  const cover = pdf.addPage([PW, PH]); pages.push(cover); page = cover;
  cover.drawRectangle({ x: 0, y: PH - 260, width: PW, height: 260, color: NAVY });
  cover.drawText('QUOTESDONE', { x: M, y: PH - 80, size: 26, font: B, color: WHITE });
  cover.drawRectangle({ x: M, y: PH - 92, width: 70, height: 3, color: TEAL });
  cover.drawText('Corporate report', { x: M, y: PH - 116, size: 11, font: F, color: rgb(0.82, 0.87, 0.9) });
  y = PH - 160;
  for (const ln of wrap(clean(doc.title), 22, PW - 2 * M, B)) { cover.drawText(ln, { x: M, y, size: 22, font: B, color: WHITE }); y -= 30; }
  y = PH - 300;
  const meta: [string, string][] = [['Period', doc.period], ['Report kind', titleCase(doc.kind)], ['Generated at', doc.generatedAt], ['Prepared by', doc.preparedBy], ['Classification', 'Confidential — QuotesDone management']];
  for (const [k, v] of meta) { cover.drawText(k.toUpperCase(), { x: M, y, size: 8, font: B, color: MUT }); cover.drawText(clean(v), { x: M + 120, y, size: 10.5, font: F, color: INK }); y -= 20; }
  if (doc.summary) {
    y -= 10; cover.drawRectangle({ x: M, y: y - 4, width: 3, height: 14, color: TEAL }); cover.drawText('SUMMARY', { x: M + 10, y, size: 8, font: B, color: MUT }); y -= 18;
    for (const ln of wrap(clean(doc.summary), 10.5, PW - 2 * M, F).slice(0, 14)) { cover.drawText(ln, { x: M, y, size: 10.5, font: F, color: INK }); y -= 15; }
  }
  cover.drawText('Confidential — QuotesDone', { x: M, y: FOOTER_H - 14, size: 8, font: F, color: MUT });

  // ---- table of contents (reserved page, filled after layout) -------------------------------------
  const wantToc = doc.sections.length >= 3;
  let toc: PDFPage | null = null; if (wantToc) { toc = pdf.addPage([PW, PH]); pages.push(toc); chrome(toc); }
  const starts: { title: string; page: number }[] = [];

  // ---- body -----------------------------------------------------------------------------------------
  newPage();
  doc.sections.forEach((sec, si) => {
    ensure(60);
    starts.push({ title: sec.title, page: pages.length });
    page.drawRectangle({ x: M, y: y - 16, width: 3, height: 16, color: TEAL });
    text((si + 1) + '. ' + sec.title, 14, { font: B, color: NAVY, x: M + 10, gap: 6 });
    if (!sec.blocks.length) text('No content recorded for this section.', 9.5, { color: MUT });
    for (const b of sec.blocks) {
      if (b.t === 'h3') { ensure(30); text(b.text, 10.5, { font: B, color: NAVY, gap: 2 }); }
      else if (b.t === 'p') text(b.text, 9.5, { color: b.muted ? MUT : INK });
      else if (b.t === 'li') { const size = 9.5; const lines = wrap(clean(b.text), size, PW - 2 * M - 14); ensure(size * 1.45 * lines.length); page.drawText('•', { x: M + 2, y: y - size, size, font: F, color: TEAL }); for (const ln of lines) { ensure(size * 1.45); page.drawText(ln, { x: M + 14, y: y - size, size, font: F, color: INK }); y -= size * 1.45; } y -= 2; }
      else if (b.t === 'table') table(b);
      else if (b.t === 'chart') chart(b);
    }
    y -= 8;
  });

  // ---- fill the TOC, then number the pages ----------------------------------------------------------
  if (toc) {
    let ty = PH - HEADER_H - 30;
    toc.drawRectangle({ x: M, y: ty - 16, width: 3, height: 16, color: TEAL });
    toc.drawText('Table of contents', { x: M + 10, y: ty - 14, size: 14, font: B, color: NAVY }); ty -= 40;
    starts.forEach((s, i) => {
      const label = clean((i + 1) + '. ' + s.title); const pn = String(s.page); const lx = M + 4, rx = PW - M - w(pn, 10);
      toc.drawText(label, { x: lx, y: ty, size: 10, font: F, color: INK });
      const dotsW = rx - 8 - (lx + w(label, 10) + 6); if (dotsW > 10) { const n = Math.floor(dotsW / w('.', 10)); toc.drawText('.'.repeat(n), { x: lx + w(label, 10) + 6, y: ty, size: 10, font: F, color: LINE }); }
      toc.drawText(pn, { x: rx, y: ty, size: 10, font: F, color: INK }); ty -= 18;
      if (ty < FOOTER_H + 20) return;
    });
  }
  pages.forEach((p, i) => { const s = 'Page ' + (i + 1) + ' of ' + pages.length; p.drawText(s, { x: PW - M - w(s, 8), y: FOOTER_H - 14, size: 8, font: F, color: MUT }); });
  // useObjectStreams:false keeps page objects readable by a plain parser (the CI check counts them).
  const bytes = await pdf.save({ useObjectStreams: false });
  return { bytes, pages: pages.length };
}

// ---------------------------------------------------------------------------------------------------
// Row resolution and storage
// ---------------------------------------------------------------------------------------------------
const TABLE: Record<Row['source'], string> = { board: 'board_reports', exec: 'exec_reports', finance: 'finance_reports' };
function normSource(s: unknown): Row['source'] | null { const v = String(s || '').toLowerCase(); if (v === 'board' || v === 'narrative') return 'board'; if (v === 'exec' || v === 'exec_reports' || v === 'exec_summary') return 'exec'; if (v === 'finance' || v === 'finance_reports') return 'finance'; return null; }
async function resolve(body: any): Promise<Row | { error: string; status: number }> {
  if (body?.latest_finance) {
    const [{ data: fr }, { data: br }] = await Promise.all([
      admin.from('finance_reports').select('*').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      admin.from('board_reports').select('*').eq('report_type', 'finance').order('created_at', { ascending: false }).limit(1).maybeSingle(),
    ]);
    if (!fr && !br) return { error: 'no finance report exists yet', status: 404 };
    const pickBoard = !!br && (!fr || new Date(br.created_at) > new Date(fr.created_at));
    return pickBoard ? { source: 'board', id: Number(br!.id), row: br! } : { source: 'finance', id: Number(fr!.id), row: fr! };
  }
  let source = normSource(body?.source); let id = Number(body?.id);
  if ((!source || !id) && body?.kind) {
    const q = admin.from('report_registry').select('source,id,period,created_at').eq('report_type', String(body.kind)).order('created_at', { ascending: false });
    const { data } = body.period ? await q.eq('period', String(body.period)).limit(1).maybeSingle() : await q.limit(1).maybeSingle();
    if (!data) return { error: 'no report of kind ' + body.kind + (body.period ? ' for ' + body.period : ''), status: 404 };
    source = normSource(data.source); id = Number(data.id);
  }
  if (!source || !id) {
    // A bare id: report_body's rule — board_reports first, then exec_reports.
    if (id) { for (const s of ['board', 'exec', 'finance'] as Row['source'][]) { const { data } = await admin.from(TABLE[s]).select('*').eq('id', id).maybeSingle(); if (data) return { source: s, id, row: data }; } }
    return { error: 'source_and_id_required', status: 400 };
  }
  const { data, error } = await admin.from(TABLE[source]).select('*').eq('id', id).maybeSingle();
  if (error) return { error: error.message, status: 500 };
  if (!data) return { error: 'not_found', status: 404 };
  return { source, id, row: data };
}
const safe = (s: string) => String(s || '').replace(/[^\w.\-]+/g, '_').slice(0, 40) || 'x';
function pathFor(r: Row, doc: Doc) { return safe(doc.kind) + '/' + safe(doc.period) + '/' + r.source + '_' + r.id + '.pdf'; }
async function sign(path: string, ttl: number) { const { data, error } = await admin.storage.from(BUCKET).createSignedUrl(path, ttl); return error ? null : (data?.signedUrl || null); }

Deno.serve(async (req) => {
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* fall through: no credential, refused below */ }
  const auth = await requireInternal(admin, body?.__secret, 'report_pdf');
  if (!auth.ok) return J({ error: auth.error, message: auth.message }, auth.status);
  try {
    const r = await resolve(body);
    if ('error' in r) return J({ ok: false, error: r.error }, r.status);
    const ttl = Math.min(Math.max(Number(body?.ttl_seconds) || 900, 60), 7 * 24 * 3600);
    // Already rendered and still stored: sign it and stop. Anything else renders.
    if (!body?.force && r.row.pdf_generated_at && r.row.pdf_path) {
      const url = await sign(String(r.row.pdf_path), ttl);
      if (url) return J({ ok: true, rendered: false, source: r.source, id: r.id, bucket: BUCKET, path: r.row.pdf_path, url, expires_in: ttl });
    }
    const doc = await buildDoc(r);
    const { bytes, pages } = await render(doc);
    const path = pathFor(r, doc);
    let up = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: 'application/pdf', upsert: true });
    if (up.error && /bucket not found/i.test(up.error.message)) { await admin.storage.createBucket(BUCKET, { public: false }); up = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: 'application/pdf', upsert: true }); }
    if (up.error) return J({ ok: false, error: 'store_failed', detail: up.error.message }, 500);
    const at = new Date().toISOString();
    const { error: ue } = await admin.from(TABLE[r.source]).update({ pdf_path: path, pdf_generated_at: at }).eq('id', r.id);
    if (ue) return J({ ok: false, error: 'row_update_failed', detail: ue.message, path }, 500);
    const url = await sign(path, ttl);
    return J({ ok: true, rendered: true, source: r.source, id: r.id, kind: doc.kind, period: doc.period, bucket: BUCKET, path, url, pages, bytes: bytes.length, expires_in: ttl });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});

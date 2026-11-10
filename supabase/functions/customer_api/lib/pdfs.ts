// customer_api — the customer's documents: the quotation, the brief and the comparison report, and the
// IO of the held Arabic comparison's finisher.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { NOT_LIVE_QUOTE_IN } from '../../_shared/quote_live.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { quoteDocument, compareDocument, completenessOf, itemsOfRows, clipCell, quoteRef, jobNoOf, arCategory, arEmirate, enCategory, type Item } from '../../_shared/quote_documents.ts';
import { portalLink } from '../../_shared/site_origins.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { MAX_ATTEMPTS as MAX_COMPARE_ATTEMPTS, type CompareFinishIO } from '../compare_arabic.ts';
import { nativeArabic } from '../../_shared/reasoned_governance.ts';
import { readRevealRate, recordRateUnreadable } from '../../_shared/reveal_rate.ts';
import { J, SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { supplierLabel } from './inquiry_rules.ts';

// THE QUOTATION DOCUMENT (14 Sep 2026, agent: ceo). quoteDocument lays it out with no model; the
// Arabic copy translates what the platform knows the meaning of and reproduces the supplier's own
// words as written (see _shared/quote_documents.ts for why). translateQuoteAr — an ai_gateway call
// whose failure under the OpenRouter hold silently shipped English under Arabic headings — is gone.
// The anonymous letter of a quote is its place among the LIVE quotes by ascending price: the rule
// my_inquiries and quote_compare both use. This used to count drafts too, so a draft priced below a
// quote made its PDF say "Supplier C" on a card the customer sees as "Supplier B".
export async function letterOf(q: any): Promise<string> {
  const { data: sibs } = await admin.from('quotes').select('id,quote_amount').eq('inquiry_id', q.inquiry_id).not('status', 'in', NOT_LIVE_QUOTE_IN).order('quote_amount', { ascending: true });
  const idx = (sibs || []).findIndex((s: any) => s.id === q.id); return supplierLabel(idx >= 0 ? idx : 0);
}
// The strings that must not appear on a customer's document before the reveal.
async function supplierIdentities(ids: any[]): Promise<string[]> {
  const uniq = [...new Set((ids || []).filter((x) => x != null).map(String))];
  if (!uniq.length) return [];
  try {
    const { data } = await admin.from('leads').select('company_name,email,phone,whatsapp,website').in('id', uniq);
    return (data || []).flatMap((l: any) => [l.company_name, l.email, l.phone, l.whatsapp, l.website]).filter((v: any) => v && String(v).trim().length >= 3).map(String);
  } catch (_e) { return []; }
}
// 21 Sep 2026 (customer audit, finding 19): after a paid reveal the PDF still said "Supplier A".
// A transactions row for the quote means the customer bought the name; it is printed as the party.
async function revealedPartyName(q: any): Promise<string | null> {
  try {
    const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', String(q.id)).limit(1).maybeSingle();
    if (!tx) return null;
    const { data: l } = await admin.from('leads').select('company_name').eq('id', q.supplier_id).maybeSingle();
    return l?.company_name ? String(l.company_name) : null;
  } catch (_e) { return null; }
}
export async function buildQuotePdf(q: any, inq: any, lang: 'en' | 'ar') {
  const partyName = await revealedPartyName(q);
  const letter = await letterOf(q);
  // The supplier's OWN priced breakdown lives in quote_items; the customer's requested BOQ is only
  // the fallback when the supplier priced a lump sum.
  // Each line carries its own price and technical specification (brand, model, specification, and the
  // spec agent's per-attribute `specs` when that column exists), so the quotation can show them.
  let items: Item[] = [];
  try {
    const { data: qi } = await admin.from('quote_items').select('*').eq('quote_id', String(q.id)).order('line_no', { ascending: true }).limit(60);
    items = itemsOfRows(qi);
  } catch (_e) { items = []; }
  // The completeness checks and the per-line specs are the hold desk's own reading (completenessOf,
  // audit 21 Sep 2026, finding 4) — the same reader that approved the quote, so the page cannot
  // contradict the review. The intake answers are read for the checks only.
  let inqSpec: unknown = null;
  try { const { data: s } = await admin.from('inquiries').select('spec').eq('id', String(q.inquiry_id)).maybeSingle(); inqSpec = s?.spec ?? null; } catch (_e) { /* the checks then apply the trade's standard alone */ }
  const done = completenessOf(q, items, inq?.category ?? null, inqSpec);
  items = done.items;
  if (!items.length && inq?.boq && Array.isArray((inq.boq as any).boq)) items = (inq.boq as any).boq.map((b: any) => ({ desc: String(b.description || ''), qty: b.qty == null ? '' : String(b.qty), unit: String(b.unit || '') })).filter((x: any) => x.desc).slice(0, 40);
  const quoteRow = { ...done.quote, scope: items.length ? q.scope : (q.scope || inq?.summary || '') };
  const maskNames = partyName ? [] : await supplierIdentities([q.supplier_id]);
  // The Arabic of the supplier's own words is reasoned (decision point trade_glossary_ar); a line not yet
  // translated HOLDS the Arabic document — it is never printed half-translated.
  // The fee line prints pricing_config's rate (the one reveal_fee() charges); unread, the PDF is refused, never guessed.
  const rateRead = await readRevealRate(admin);
  if (!rateRead.ok) { await recordRateUnreadable(admin, 'customer_api quotation PDF -> pricing_config', rateRead.error, { quote_id: q.id }); return { j: { ok: false, error: 'reveal_rate_unread' }, ref: quoteRef(inq, letter) }; }
  const revealRate = rateRead.cfg.standard_reveal_rate;
  const doc = await nativeArabic(defaultDeps(admin, 'customer_api'), (arTexts) => quoteDocument({ quote: quoteRow, inquiry: inq, items, letter, lang, partyName, maskNames, requestUrl: portalLink(lang, inq.id, q.id), arTexts, revealRate }), { subject: { quote_id: q.id } });
  if (!doc.doc) return { j: ARABIC_HELD, ref: quoteRef(inq, letter) };
  const { body, ref } = doc.doc;
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...body, __secret: secret }) });
  const j = await r.json();
  return { j, ref };
}
// The anonymised supplier brief as a branded document. Same engine as the quotations
// and the comparison report, so the customer sees exactly what left the building on
// QuotesDone letterhead instead of a browser print-out.
export async function buildBriefPdf(inq: any, lang: string) {
  const ar = lang === 'ar';
  const T = (en: string, arx: string) => (ar ? arx : en);
  const blocks: any[] = [];
  const ref = 'QD-' + jobNoOf(inq) + '-BRIEF';
  // The trade code ('hvac') and the emirate ('Dubai') printed raw on the Arabic brief (audit 21 Sep 2026);
  // they take the same deterministic Arabic the quotation uses. The budget is the customer's own words.
  const trade = (c: unknown) => (ar ? arCategory(c) : null) ?? enCategory(c);
  const kv: any[] = [
    [T('Reference', 'الرقم المرجعي'), ref],
    [T('Category', 'الفئة'), clipCell(trade(inq?.category), 40) || '—'],
    [T('Emirate', 'الإمارة'), clipCell((ar ? arEmirate(inq?.emirate) : null) ?? inq?.emirate, 40) || '—'],
    [T('Budget', 'الميزانية'), clipCell(inq?.budget, 40) || '—'] ];
  if (Array.isArray(inq?.trades) && inq.trades.length) kv.push([T('Trades', 'التخصصات'), clipCell(inq.trades.map(trade).join(ar ? '، ' : ', '), 80)]);
  blocks.push({ t: 'kv', pairs: kv });
  blocks.push({ t: 'h2', text: T('Scope', 'نطاق العمل') });
  blocks.push({ t: 'p', text: String(inq?.summary || '—') });
  const spec = (inq?.spec && typeof inq.spec === 'object' && !Array.isArray(inq.spec)) ? inq.spec : null;
  if (spec) {
    const rows = Object.entries(spec)
      .filter(([k, v]) => k !== 'customer_requirements' && v != null && (typeof v !== 'object' || Array.isArray(v)) && String(v).trim() !== '')
      .map(([k, v]) => [clipCell(String(k).replace(/_/g, ' '), 40), clipCell(Array.isArray(v) ? v.join(', ') : v, 160)]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Specification', 'المواصفات') });
      blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Detail', 'التفاصيل')], rows, widths: [0.32, 0.68] });
    }
  }
  // What the customer asked the sales engineer for (docs/contracts/intake_answers.md), from the derived
  // display rows so the PDF says exactly what the portal says, in the document's language.
  const reqRows = (spec as any)?.customer_requirements?.display?.[ar ? 'ar' : 'en'];
  if (Array.isArray(reqRows) && reqRows.length) {
    blocks.push({ t: 'h2', text: T('What the customer asked for', 'ما طلبه العميل') });
    blocks.push({ t: 'table', head: [T('Item', 'البند'), T('Requested', 'المطلوب')], rows: reqRows.map((r: any) => [clipCell(r?.label, 40), clipCell(r?.value, 160)]), widths: [0.32, 0.68] });
  }
  const boq = (inq?.boq && Array.isArray((inq.boq as any).boq)) ? (inq.boq as any).boq : null;
  if (boq && boq.length) {
    const rows = boq.slice(0, 60)
      .map((b: any, i: number) => [String(i + 1), clipCell(b.description, 150), b.qty == null ? '' : String(b.qty), clipCell(b.unit, 12)])
      .filter((r: any) => r[1]);
    if (rows.length) {
      blocks.push({ t: 'h2', text: T('Bill of quantities', 'جدول الكميات') });
      blocks.push({ t: 'table', head: ['#', T('Description', 'الوصف'), T('Qty', 'الكمية'), T('Unit', 'الوحدة')], rows, widths: [0.07, 0.68, 0.12, 0.13] });
    }
  }
  if (inq?.drawing_file_name) blocks.push({ t: 'note', text: T('A drawing is attached to this request and is shared with matched suppliers: ', 'أُرفق بهذا الطلب مخطط يطّلع عليه المورّدون المطابقون: ') + clipCell(inq.drawing_file_name, 80) });
  blocks.push({ t: 'space', h: 6 });
  blocks.push({ t: 'note', text: T(
    'This is the anonymised brief QuotesDone sends to matched suppliers. The customer name, company and contact details are never included - suppliers quote on the scope alone, and contact details are exchanged only after the customer reveals a quote.',
    'هذا ملخّص الطلب كما ترسله QuotesDone إلى المورّدين المطابقين، دون الإفصاح عن هوية العميل؛ فلا يتضمّن اسمه ولا اسم شركته ولا بيانات التواصل معه. يقدّم المورّدون عروضهم استنادًا إلى نطاق العمل وحده، ولا تُتبادل بيانات التواصل إلا بعد أن يكشف العميل عن العرض الذي يختاره.') });
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    // filed under the request in Dropbox (fn_enqueue_doc_backups: CUSTOMER DOCUMENTS reads agent-docs/brief/<inquiry id>/)
    body: JSON.stringify({ __secret: secret, title: T('Supplier brief', 'ملخّص الطلب للمورّدين'), ref, name: ref, lang: ar ? 'ar' : 'en', blocks, options: { letterhead: true }, folder: 'brief/' + inq.id }) });
  const j = await r.json();
  return { j, ref };
}

// The comparison report: the analysis quote_compare returned, laid out by compareDocument (see
// _shared/quote_documents.ts — the side-by-side table, the roster of every quote, the anonymity
// mask). compare_csv exports the same compareTable rows, so the two can never disagree.
// ONE server-to-server call to quote_compare, shared by compare_pdf and compare_csv.
// Measured 14 Sep 2026 (e2e run 5): the same customer got a deterministic analysis from
// quote_compare with their own JWT and {"error":"comparison_unavailable"} from compare_pdf in both
// languages. quote_compare is deployed with verify_jwt = true and both call sites POSTed with no
// Authorization header, so the gateway refused them with a 401 BEFORE the function ran; the
// gateway's body carries neither `error` nor `note`, which is exactly what fell through to the
// generic label. Same defect sales_engineer's `match` call had (see the routing block above).
// The service key gets past the gateway; __secret (cred_fn_customer_api, scope includes
// quote_compare) is what decides the caller inside.
export async function fetchCompareAnalysis(iid: string, lang: 'en' | 'ar'): Promise<{ analysis?: any; error?: string }> {
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/quote_compare`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${SERVICE}`, apikey: SERVICE },
    body: JSON.stringify({ __secret: secret, inquiry_id: iid, lang }) });
  const jd = await r.json().catch(() => null);
  if (jd?.ok && jd.analysis) return { analysis: jd.analysis };
  return { error: jd?.note || jd?.error || (r.ok ? 'comparison_unavailable' : 'comparison_unavailable_http_' + r.status) };
}

/** An Arabic document with a line not yet translated by reasoning (under the founder's model hold). */
const ARABIC_HELD = { ok: false, held: true, error: 'arabic_held' } as const;
export const heldReply = () => J({ ok: false, held: true, code: 'arabic_held',
  message: 'The Arabic version is being prepared by our sales engineer. We will send it to you by email and WhatsApp as soon as it is ready. The English version is available now.',
  message_ar: 'يُعدّ مهندس المبيعات لدينا النسخة العربية، وسنرسلها إليكم بالبريد الإلكتروني وواتساب فور جاهزيتها. النسخة الإنجليزية متاحة الآن.' }, 202);
// The edge wall is 150 s; one think() batch can run ~47 s (the gateway wall). A batch may START only before
// started + 90 s, so the request always answers (the 202 held reply) instead of a 504.
export const ARABIC_COMPARE_BUDGET_MS = 90_000;
// deadline (epoch ms): past it a missing line is FILED for the replay, never reasoned. compare_pdf passes its start
// + ARABIC_COMPARE_BUDGET_MS; the replay's finisher (compare_arabic.ts) passes Date.now(), so it never calls a model.
// A held Arabic report records its waiter, and the replay sends it to the customer once its lines exist.
export async function buildComparePdf(a: any, inq: any, lang: 'en' | 'ar', deadline: number) {
  const { data: sq } = await admin.from('quotes').select('supplier_id').eq('inquiry_id', inq.id);
  const maskNames = await supplierIdentities((sq || []).map((r: any) => r.supplier_id));
  const portalUrl = portalLink(lang, inq.id);
  const doc = await nativeArabic(defaultDeps(admin, 'customer_api'), (arTexts) => compareDocument({ analysis: a, inquiry: inq, lang, maskNames, portalUrl, linkFor: (qid) => portalLink(lang, inq.id, qid), arTexts }), { subject: { inquiry_id: inq.id }, deadline });
  if (!doc.doc) {
    const { error: wErr } = await admin.rpc('fn_arabic_compare_wait', { p_inquiry: String(inq.id), p_texts: doc.missing });
    if (wErr) console.error('compare_pdf: the Arabic report waiter was not recorded:', wErr.message);
    return { j: ARABIC_HELD, ref: 'QD-' + jobNoOf(inq) + '-CMP' };
  }
  const { body, ref } = doc.doc;
  const secret = await getSecret('cred_fn_customer_api');
  const r = await fetch(`${SUPABASE_URL}/functions/v1/pdf_native`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    // filed under the request in Dropbox (fn_enqueue_doc_backups: CUSTOMER DOCUMENTS reads agent-docs/compare/<inquiry id>/)
    body: JSON.stringify({ ...body, __secret: secret, folder: 'compare/' + inq.id }) });
  const j = await r.json();
  return { j, ref };
}
// The live IO of the held Arabic report's finisher (compare_arabic.ts holds the decisions and their tests).
const COMPARE_INQ_COLS = 'id,rfq_no,customer_id,category,summary,emirate';
export function compareFinishIO(): CompareFinishIO {
  return {
    waiter: async (iid) => { const { data } = await admin.from('arabic_compare_waiter').select('inquiry_id,created_at,attempts').eq('inquiry_id', iid).maybeSingle(); return (data as any) ?? null; },
    inquiry: async (iid) => { const { data } = await admin.from('inquiries').select(COMPARE_INQ_COLS).eq('id', iid).maybeSingle(); return (data as any) ?? null; },
    customer: async (cid) => { const { data } = await admin.from('customers').select('email').eq('id', cid).maybeSingle(); return (data as any) ?? null; },
    render: async (inq) => {
      const got = await fetchCompareAnalysis(inq.id, 'ar');
      if (!got.analysis) return { error: got.error || 'comparison_unavailable' };
      // deadline = now: every line is read from the cache; one still missing is filed, never reasoned here.
      const { j, ref } = await buildComparePdf(got.analysis, inq, 'ar', Date.now());
      if ((j as any)?.held) return { held: true };
      return j?.ok && j.url ? { url: String(j.url), ref } : { error: String(j?.error || j?.detail || 'pdf_failed') };
    },
    deliver: async (rows) => { const { error } = await requestDelivery(admin, rows); return error ? { ok: false, err: error.message } : { ok: true }; },
    done: async (iid) => { await admin.from('arabic_compare_waiter').delete().eq('inquiry_id', iid); },
    tried: async (iid, attempts) => { await admin.from('arabic_compare_waiter').update({ attempts, last_tried_at: new Date().toISOString() }).eq('inquiry_id', iid); },
    tellSalesEngineer: async (iid, last) => {
      await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'arabic_comparison_render_failed', status: 'pending', risk: 'medium',
        title: `The Arabic comparison report could not be sent after ${MAX_COMPARE_ATTEMPTS} tries`, detail: { inquiry_id: iid, last }, target_table: 'inquiries', target_id: iid });
    },
    overdue: async (iid, hours) => {
      const { data: open } = await admin.from('agent_actions').select('id').eq('agent', 'sales_engineer').eq('kind', 'arabic_comparison_overdue').eq('target_id', iid).eq('status', 'pending').limit(1);
      if (open?.length) return;
      await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'arabic_comparison_overdue', status: 'pending', risk: 'medium',
        title: `A customer's Arabic comparison report has waited ${hours} h for its Arabic lines`, detail: { inquiry_id: iid, hours }, target_table: 'inquiries', target_id: iid });
    },
  };
}

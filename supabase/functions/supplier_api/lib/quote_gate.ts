// supplier_api — the gates a quotation passes: the exact-spec checklist, one verdict per quotation, the job
// this supplier was matched to, and the file that is its own.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { defaultDeps } from '../../_shared/think.ts';
import { checkVerdict, type Ctx } from '../../_shared/line_specs/workflow.ts';
import { type Assessment, type Line } from '../../_shared/line_specs/assess.ts';
import type { Attr } from '../../_shared/line_specs/model.ts';
import { checklistAttrs, chooseChecklist, needsChecklist, reasonLineSpecs, type Checklist, type ChecklistRow } from '../../_shared/line_specs/reasoned_specs.ts';
import { admin } from '../context.ts';
import { UUID_RE } from './fields.ts';

// EXACT SPECS FOR A TRADE WITH NO LINE READER (23 Sep 2026). The trade's knowledge pack says what a line
// must state (fn_trade_spec_checklist); think() judges what the supplier's lines already state
// (_shared/line_specs/reasoned_specs.ts). Under the model hold nothing is judged and every required spec
// is asked, so the quote is held until it is stated. A trade with a reader, or no checklist, is unchanged.
// mode 'gate': choose the checklist (reasoned) and judge the lines — once per submission. 'stored': the
// live hold's own checklist, read back for fill-in and approval, no reasoning. The preflight asks 'gate' too (2 Nov 2026):
// its own "one checklist or every checklist together" prediction disagreed with the submission it predicted.
export async function specChecklist(category: string | null, quoteId: string, mode: 'gate' | 'stored' = 'gate'): Promise<{ checklist?: Attr[]; reason?: Ctx['reason'] }> {
  if (!category || !needsChecklist(category)) return {};
  if (mode === 'stored') {
    const { data: h } = await admin.from('quote_spec_hold').select('original_snapshot').eq('quote_id', quoteId)
      .in('state', ['open', 'awaiting_approval']).order('id', { ascending: false }).limit(1).maybeSingle();
    const rows = ((h?.original_snapshot as { checklist?: ChecklistRow[] } | null)?.checklist ?? []) as ChecklistRow[];
    return rows.length ? { checklist: checklistAttrs(rows) } : {};
  }
  const { data, error } = await admin.rpc('fn_trade_spec_checklist', { p_category: category });
  const lists = (!error && Array.isArray(data) ? data : []) as Checklist[];
  if (!lists.length) {
    // Not held on an empty list, and not silently: the missing pack is an IT finding the knowledge work closes.
    try { await admin.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'spec_checklist_missing:' + category, p_title: 'A trade with no line reader has no spec checklist, so its quotes cannot be held for missing specs',
      p_where: 'edge function supplier_api', p_blast: 'customer_facing', p_affected: 1, p_evidence: { category, quote_id: quoteId, error: error?.message ?? null }, p_ruled_out: [], p_undetermined: [], p_raised_by: 'sales_engineer' }); } catch (_e) { /* the gate goes on */ }
    return {};
  }
  const deps = defaultDeps(admin, 'supplier_api');
  const { data: lineRows } = await admin.from('quote_items').select('*').eq('quote_id', quoteId).order('line_no', { ascending: true }).limit(60);
  const picked = await chooseChecklist(deps, { checklists: lists, lines: (lineRows ?? []) as Line[], trade: category, quoteId });
  const checklist = checklistAttrs(picked.rows);
  if (!checklist.length) return {};
  return { checklist, reason: (lines, cl) => reasonLineSpecs(deps, { lines, checklist: cl, trade: category, quoteId }) };
}
// ONE QUOTATION, ONE VERDICT (sales_engineer, 2 Nov 2026): workflow.ts checkVerdict stores the first SETTLED verdict on
// a set of gate inputs (gateInputKey) and compares later ones; a disagreement is an IT finding with both verdicts.
export async function sameVerdict(key: string, a: Assessment, settled: boolean, quoteId: string, phase: 'preflight' | 'submission') {
  try {
    const v = await checkVerdict(async (fn, args) => { const r = await admin.rpc(fn, args); return { data: r.data, error: r.error }; }, key, a, settled);
    if (v.outcome === 'unreadable') console.error('quote gate verdict could not be stored or read back for quote', quoteId);
    if (v.outcome !== 'disagree') return;
    const { first, now } = v;
    await admin.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'quote_gate_disagreement:' + key.slice(0, 16), p_title: 'The quote hold gate gave one quotation two different verdicts',
      p_where: 'edge function supplier_api submit_quote (' + phase + ')', p_blast: 'customer_facing', p_affected: 1,
      p_evidence: { quote_id: quoteId, gate_input_key: key, first, now }, p_ruled_out: [], p_undetermined: ['which reading was not settled'], p_raised_by: 'sales_engineer' });
  } catch (_e) { /* the record never blocks the gate */ }
}

// A SUPPLIER ACTS ONLY ON A JOB IT WAS MATCHED TO (audit 22 Sep 2026, finding SP-N-03).
//
// `inbox` has always been scoped to public.inquiry_matches, and the quotation-review actions reach the job
// only through it — but submit_quote and extract_quote took body.inquiry_id and never asked. Any approved
// supplier could therefore price, and store a quotation file against, any enquiry in the estate whose uuid
// it held; fn_supplier_opportunities handed out those uuids for every open enquiry, its own reason line
// reading "Outside your registered trade". One row in inquiry_matches is the platform's record that this
// enquiry was sent to this company, so that row is the question both doors now ask.
//
// It answers with the id or with null, and the caller returns 404 — not 403. A 403 would confirm that the
// uuid names a real enquiry; a job this supplier was not matched to must not exist for them. It FAILS
// CLOSED: an unreadable inquiry_matches is null, which refuses, rather than an assumed match.
export async function matchedInquiry(supplierId: number, raw: unknown): Promise<string | null> {
  const id = typeof raw === 'string' && UUID_RE.test(raw) ? raw.toLowerCase() : null;
  if (!id) return null;
  const { data, error } = await admin.from('inquiry_matches').select('id').eq('inquiry_id', id).eq('supplier_id', supplierId).limit(1);
  if (error || !data || !data.length) return null;
  return id;
}
// A QUOTATION FILE LIVES UNDER ITS OWN SUPPLIER'S PREFIX (audit 22 Sep 2026, finding SP-N-04). Both doors
// took original_file_path verbatim from the request and wrote it onto the quote row, so a supplier could
// attach ANY object in the quote-files bucket — another supplier's quotation — to its own quote and have
// the platform serve it back.
//
// TWO PREFIXES, BOTH MEASURED, because one would have broken the main door. extract_quote writes
// `quotes/<supplier id>/<inquiry>/…` and the quotation review writes `review/<supplier id>/<inquiry>/…`
// (quote_review_flow.ts line 270) — production on 22 Sep 2026 holds two quotes with an original file and
// BOTH are `review/126512/…`, so a rule naming only `quotes/` would have refused every quotation the
// chat submits. Either prefix, and the supplier id in it must be the caller's. '..' is refused with them
// because a stored path is later signed, not resolved.
export const ownQuoteFile = (p: unknown, supplierId: number): boolean => {
  const s = String(p ?? '');
  return (s.startsWith(`quotes/${supplierId}/`) || s.startsWith(`review/${supplierId}/`)) && !s.includes('..');
};
export const NOT_MY_FILE = { error: 'file_not_yours', code: 'file_not_yours', message: 'That file is not one of yours. Please attach your quotation again.' };

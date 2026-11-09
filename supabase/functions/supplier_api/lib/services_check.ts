// supplier_api — the cross-check of the services the documents state against the services the supplier typed.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { admin } from '../context.ts';

// DOCUMENTS-LEAD + DOUBLE CONFIRMATION 29 Jul 2026 ---------------------------------------------
// Spec: "These documents are the PRIMARY data source. An agent extracts information from them to
// understand what the supplier does", and "the supplier is also given the option to manually write
// the services they provide (for DOUBLE CONFIRMATION against the extracted data)".
//
// Until now process_docs wrote extracted services only when the supplier had typed NOTHING
// (`&& !sup.services`), so the documents were the FALLBACK and the typed text was the source of
// truth - the exact inversion of the spec - and the two were never compared, so no mismatch could
// ever surface.
//
// Now: extracted services ALWAYS win the canonical leads.services field, the supplier's typed text
// is preserved as the DECLARED value, and the two are cross-checked on every extraction and on
// every profile save.
//
// WHERE THE DECLARED TEXT AND THE OUTCOME LIVE, AND WHY agent_actions: one row per check, kind
// 'supplier_services_crosscheck', target_table/target_id = leads/<id>, whole comparison in the
// jsonb `detail` (verdict, overlap, shared terms, extracted list, declared text, note). No
// migration is added and no other feature's column is borrowed: every leads JSONB column already
// has an owner (ai_review_flags was REWRITTEN WHOLESALE by this function's own review helper on every
// save until 22 Sep 2026, and still belongs to that review; machinery / brands_carried /
// client_references / iso_certifications / manufacturer_authorizations belong to capability
// enrichment) and supplier_capabilities is owned end to end by capability_agent, which upserts
// whole rows including review_status. agent_actions is the platform's existing durable, queryable
// review surface, it is where the spec asks conflicts to be raised anyway, and unlike a single
// column it keeps the FULL HISTORY of what the supplier declared versus what the documents said.
// Query it with: select detail->>'verdict', detail->>'declared_services' from agent_actions
// where kind = 'supplier_services_crosscheck'.
//
// A conflict NEVER blocks registration - the founder wants full automation, so we flag and carry on.
const SVC_STOP = new Set(['and','the','for','with','all','our','any','are','you','your','uae','dubai','abu','general','other','service','work','job','provide','providing','provider','company','llc','etc','type','various','including','include','solution']);
const svcStem = (w: string) => (w.length > 4 && w.endsWith('ies')) ? w.slice(0, -3) + 'y' : ((w.length > 3 && w.endsWith('s')) ? w.slice(0, -1) : w);
function svcTerms(v: unknown): string[] {
  return String(v == null ? '' : v).toLowerCase().replace(/[^a-z0-9؀-ۿ]+/g, ' ').split(/\s+/).map(svcStem).filter((w) => w.length > 2 && !SVC_STOP.has(w));
}
// Term overlap rather than string equality: the documents may say "supply and installation of VRF
// air conditioning systems" where the supplier typed "AC installation", and those two agree.
// Containment (shared / smaller set) is used rather than Jaccard so a long extracted list is not
// punished against a short typed line. 60%+ = agreement, some shared terms = partial overlap,
// nothing in common = conflict.
function crossCheckServices(extracted: string[], declared: unknown) {
  const dText = String(declared == null ? '' : declared).trim();
  const eText = extracted.join(', ');
  const eSet = new Set(svcTerms(eText));
  const dSet = new Set(svcTerms(dText));
  const q = (s: string) => '"' + s.slice(0, 300) + '"';
  if (!eSet.size) return { verdict: 'no_extraction', overlap: 0, shared: [] as string[], note: 'Nothing usable was extracted from the documents, so there was nothing to cross-check the supplier text against.' };
  if (!dSet.size) return { verdict: 'not_declared', overlap: 0, shared: [] as string[], note: 'Supplier typed no services of their own, so the document extraction ' + q(eText) + ' stands unconfirmed. Not a conflict.' };
  const shared = [...dSet].filter((w) => eSet.has(w));
  const overlap = shared.length / Math.min(eSet.size, dSet.size);
  const verdict = overlap >= 0.6 ? 'agreement' : (shared.length ? 'partial' : 'conflict');
  const head = verdict === 'agreement' ? 'Documents and supplier agree' : (verdict === 'partial' ? 'Partial overlap' : 'CONFLICT');
  return { verdict, overlap, shared, note: head + ': documents say ' + q(eText) + ', supplier typed ' + q(dText) + ' (' + Math.round(overlap * 100) + '% overlap' + (shared.length ? ', shared: ' + shared.slice(0, 8).join(', ') : ', nothing in common') + '). Documents are the source of truth; the typed text is kept as the declared value.' };
}
// The declared text has to survive the fact that leads.services now holds the EXTRACTED value -
// re-running extraction would otherwise compare the documents against themselves. The most recent
// cross-check row is the durable record of what the supplier actually typed.
export async function priorCrossCheck(supplierId: number) {
  try {
    const { data } = await admin.from('agent_actions').select('detail').eq('kind', 'supplier_services_crosscheck').eq('target_id', String(supplierId)).order('id', { ascending: false }).limit(1).maybeSingle();
    if (!data) return { found: false, declared: null as unknown, extracted: [] as string[] };
    const d = (data.detail || {}) as Record<string, unknown>;
    return { found: true, declared: (d.declared_services ?? null) as unknown, extracted: Array.isArray(d.extracted_services) ? (d.extracted_services as string[]) : [] };
  } catch (_e) { return { found: false, declared: null as unknown, extracted: [] as string[] }; }
}
export async function recordServicesCrossCheck(supplierId: number, companyName: unknown, extracted: string[], declared: unknown) {
  const cc = crossCheckServices(extracted, declared);
  const conflict = cc.verdict === 'conflict';
  try {
    await admin.from('agent_actions').insert({
      agent: 'sales_engineer',
      kind: 'supplier_services_crosscheck',
      status: conflict ? 'needs_review' : 'auto_done',
      risk: conflict ? 'medium' : 'low',
      title: 'Services cross-check (' + cc.verdict + ') — ' + String(companyName || ('supplier #' + supplierId)).slice(0, 120),
      recommendation: conflict ? "The documents and the supplier's own description have nothing in common. Registration was NOT blocked. Open the trade licence / company profile and correct leads.services if the extraction is wrong, or ask the supplier what they actually do." : cc.note,
      detail: { supplier_id: supplierId, verdict: cc.verdict, overlap: Math.round(cc.overlap * 100) / 100, shared_terms: cc.shared.slice(0, 20), extracted_services: extracted, declared_services: declared == null ? null : String(declared).slice(0, 2000), note: cc.note, checked_at: new Date().toISOString(), source: 'supplier_api' },
      target_table: 'leads',
      target_id: String(supplierId),
    });
  } catch (_e) { /* the cross-check is evidence, not a gate - it must never break registration */ }
  return cc;
}

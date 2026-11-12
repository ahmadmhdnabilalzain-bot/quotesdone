// supplier_portal — the documents a supplier can hold, in the order the portal shows them, and the one list builder
// every read and every write answers with.
// Moved here from index.ts on 9 Nov 2026 (sales_engineer: the 791-line index.ts split into modules, a pure move).
import { wrongDocumentOnFile } from '../../_shared/licence_read_state.ts';
import { REQUIRED_DOC_KEYS } from '../../_shared/supplier_registration.ts';
import { type VersionSnapshot } from '../document_actions.ts';
import { verifiedBadges } from '../../_shared/verified_badges.ts';
import { admin, sign } from '../context.ts';

// Every document a supplier can hold, in the order the portal shows them.
//
// Until v4 this map contained ONLY `iso`, which meant save_documents could write an ISO
// certificate and nothing else. The documents tab rendered the trade licence and company
// profile as read-only, and VAT / insurance / manufacturer authorisation had no UI at all.
// The effect was a dead end: fn_supplier_expiries raises "Insurance has expired - upload a
// renewed copy" and routes the supplier to a tab with no insurance field. Worse, an
// established supplier could never replace an expired trade licence, because the only
// licence upload lives in ProfileForm, which renders only while the account still has no
// company. Driving both read and write off one map closes that.
//
// `folder` keeps storage tidy and mirrors what save_profile already writes.
export const DOC_KINDS: Record<string, { pathCol: string; nameCol?: string; expCol: string | null; label: string; folder: string; hint: string }> = {
  license:      { pathCol:'license_doc_path',           nameCol:'license_doc_name', expCol:'license_expiry',            label:'Trade licence',              folder:'licence',   hint:'Required. Your current trade licence from your licensing authority (Economic Department or free-zone authority).' },
  profile:      { pathCol:'company_profile_doc_path',                               expCol:null,                        label:'Company profile',            folder:'profile',   hint:'Required. Your company introduction deck or PDF. Shown to customers after a reveal.' },
  vat:          { pathCol:'vat_doc_path',                                           expCol:null,                        label:'VAT certificate',            folder:'certs',     hint:'Your TRN certificate. Needed before you can invoice with VAT.' },
  insurance:    { pathCol:'insurance_doc_path',                                     expCol:'insurance_expiry',          label:'Insurance',                  folder:'certs',     hint:'Public liability or contractor all-risk cover.' },
  iso:          { pathCol:'iso_doc_path',                                           expCol:'iso_expiry',                label:'ISO certification',          folder:'certs',     hint:'Any ISO certificate you hold. Strengthens your capability score.' },
  manufacturer: { pathCol:'manufacturer_auth_doc_path',                             expCol:'manufacturer_auth_expiry',  label:'Manufacturer authorisation', folder:'certs',     hint:'Authorised-dealer letters from the brands you carry.' },
  // ONE NAME FOR THE EGR (audit 21 Sep 2026, finding 18): the establishment card issued with the
  // trade licence — the profile's "Economic Register (EGR) no." is its number. It was "Establishment
  // card" here, "EGR (Emirates Green Building) certificate" in the portal and "immigration
  // establishment card" in the hint; fn_supplier_certifications and the portal now say the same.
  egr:          { pathCol:'egr_doc_path',               nameCol:'egr_doc_name',     expCol:null,                        label:'Establishment card (EGR)',   folder:'certs',     hint:'Your establishment card (EGR), issued with your trade licence.' },
};
// `iban` (a bank letter) was a document type here until 21 Sep 2026. Money moves both directions through
// Stripe, so the estate never holds a supplier's bank details — founder instruction 527.
export const DOC_ORDER = ['license','profile','catalogs','vat','insurance','iso','manufacturer','egr'];
// The supporting-document subject that can stand in for a fixed kind (fn_supplier_document_home).
export const HOME_KEY: Record<string, string> = { license: 'trade_licence', profile: 'company_profile', insurance: 'insurance', iso: 'iso', manufacturer: 'manufacturer_auth', egr: 'establishment' };
// THE DOCUMENTS LIST — the one builder every read and every write answers with (finding 16), and the
// one home for each subject (finding 17): a certificate a supplier uploaded as a SUPPORTING document
// (ISO 9001 under "Supporting documents") is on file here too, marked source 'supporting', the same
// way fn_supplier_certifications, fn_supplier_document_impact and fn_supplier_twin now see it.
export async function listDocuments(supId: number) {
  // Column list is derived from DOC_KINDS so adding a document type here needs no edit below.
  const cols = new Set<string>(['catalog_doc_paths', 'verified', 'licence_gate_reason', 'licence_read_state']);
  for (const k of Object.values(DOC_KINDS)) { cols.add(k.pathCol); if (k.nameCol) cols.add(k.nameCol); if (k.expCol) cols.add(k.expCol); }
  const [{ data: l }, { data: homeRows }, { data: vers }, expiries, { data: cap }] = await Promise.all([
    admin.from('leads').select([...cols].join(',')).eq('id', supId).maybeSingle(),
    admin.rpc('fn_supplier_document_home', { p_lead_id: supId }),
    // Previous versions (replaced or removed files) per kind, from doc_versions — the supplier
    // sees "2 earlier versions kept" beside a document, and Remove can say what was hidden.
    admin.from('doc_versions').select('entity_id,version,snapshot,created_at')
      .eq('entity_type', 'supplier_document').like('entity_id', `${supId}:%`).order('version', { ascending: false }).limit(200),
    admin.rpc('fn_supplier_expiries', { p_supplier_id: supId }),
    // Which profile / catalogue is still being read after its upload answered (supplier_docs_later.ts): the tab says
    // so and asks again until the read has finished (19 Oct 2026, sales_engineer).
    admin.from('supplier_capabilities').select('source_docs').eq('supplier_id', supId).maybeSingle(),
  ]);
  const reading = (((cap?.source_docs as { docs?: { path: string; status: string }[] } | null)?.docs) || []).filter((d) => d.status === 'reading').map((d) => d.path);
  const row = (l || {}) as Record<string, unknown>;
  const home = new Map<string, { path: string | null; name: string | null; source: string | null }>();
  for (const h of ((homeRows || []) as { key: string; path: string | null; name: string | null; source: string | null }[])) home.set(h.key, h);

  const cats: string[] = Array.isArray(row.catalog_doc_paths) ? (row.catalog_doc_paths as string[]) : [];
  const catalogues: { path: string; name: string; url: string | null }[] = [];
  for (const p of cats.slice(0, 20)) {
    catalogues.push({ path: p, name: String(p).split('/').pop() || 'Catalogue', url: await sign('supplier-docs', p) });
  }

  const today = new Date(); today.setHours(0, 0, 0, 0);
  const docs: Record<string, unknown>[] = [];
  for (const key of DOC_ORDER) {
    if (key === 'catalogs') {
      docs.push({ key:'catalogs', label:'Catalogues', hint_code:'doc_hint_catalogs', hint:'Product or project catalogues. Upload as many as you like - new files are added, never replaced.',
        path: cats.length ? 'catalogs' : null, expiry:null, url:null, name:null, required:false,
        count: cats.length, urls: catalogues.map((c) => c.url).filter(Boolean), items: catalogues,
        status: cats.length ? 'on_file' : 'missing' });
      continue;
    }
    const k = DOC_KINDS[key]; if (!k) continue;
    const own = (row[k.pathCol] as string) || null;
    const stand = !own && HOME_KEY[key] ? home.get(HOME_KEY[key]) : undefined;
    const path = own || (stand && stand.path) || null;
    const source = own ? 'leads' : (stand && stand.path ? 'supporting' : null);
    const expiry = own && k.expCol ? ((row[k.expCol] as string) || null) : null;
    // Filename falls back to the stored path's tail so the supplier always sees which file is on record.
    const name = (own && k.nameCol ? (row[k.nameCol] as string) : null) || (stand && stand.path ? stand.name : null) || (path ? String(path).split('/').pop() : null) || null;
    let status = 'missing';
    if (path) {
      status = 'on_file';
      // A trade licence whose expiry nobody could read is on file but NOT read: say so on its card, not "On file" (2 Nov 2026, ledger 1467).
      if (key === 'license' && own && !expiry) status = 'unread';
      if (expiry) {
        const d = Math.round((new Date(expiry).getTime() - today.getTime()) / 864e5);
        status = d < 0 ? 'expired' : d <= 30 ? 'expiring' : 'valid';
      }
    }
    // a file in the licence slot that the model is sure is not a licence: the card says which file it is (founder ruling 1668)
    const wrong = key === 'license' && own && status === 'unread' ? await wrongDocumentOnFile(admin, supId, row as { licence_read_state?: unknown; license_doc_path?: unknown }) : null;
    docs.push({ key, label: k.label, hint: k.hint, path, name, expiry, has_expiry: !!k.expCol, source, ...(wrong ? { wrong_document: wrong.kind, wrong_document_message: wrong.message } : {}),
      // The mandatory six (_shared/supplier_registration.ts): licence AND company profile. This
      // said `key === 'license'` while the same tab's heading listed three required documents.
      required: REQUIRED_DOC_KEYS.includes(key), hint_code: 'doc_hint_' + key, status, url: await sign('supplier-docs', path) });
  }

  const required = docs.filter((d) => d.required);
  const complete = docs.filter((d) => d.status !== 'missing').length;
  for (const d of docs) {
    const mine = ((vers || []) as { entity_id: string; snapshot: VersionSnapshot; created_at: string }[]).filter((v) => v.entity_id === `${supId}:${d.key}`);
    d.versions = mine.length;
    d.last_version = mine[0] ? { event: mine[0].snapshot?.event, name: mine[0].snapshot?.name, at: mine[0].created_at } : null;
  }
  // The two verified badges and what earns each (English only: suppliers read English).
  return { ok:true, documents: docs, expiries: expiries.data || [], reading, badges: verifiedBadges(row as Parameters<typeof verifiedBadges>[0]),
    summary: { total: docs.length, on_file: complete, missing: docs.length - complete,
      required_missing: required.filter((d) => d.status === 'missing').length,
      attention: docs.filter((d) => d.status === 'expired' || d.status === 'expiring').length } };
}

// SUPPLIER PROFILE SCORE (T3, 4 Oct 2026, sales_engineer).
// One number out of 100 for how complete and current a supplier's profile is, and the ranked list of
// what to fix, each item naming the portal tab that fixes it. Deterministic: it reads only the
// supplier's own `supplier_api me` row and the dashboard's eligibility payload, both already loaded.
// Suppliers read English only, so every label here is English.
// Guard: scripts/checks/supplier_profile_score.test.mjs
export type ScoreItem = { key: string; label: string; points: number; done: boolean; tab: 'documents' | 'services' | 'profile' };

const filled = (v: unknown) => (Array.isArray(v) ? v.length > 0 : String(v ?? '').trim().length > 0);

export function profileScore(me: any, eligibility: any, today: string = new Date().toISOString().slice(0, 10)) {
  const m = me || {};
  const scopeOpen = ((eligibility && eligibility.blocking) || []).some((b: any) => b && b.code === 'scope_unconfirmed');
  const licOnFile = filled(m.license_doc_path) || filled(m.trade_license_no);
  const items: ScoreItem[] = [
    { key: 'licence', label: 'Upload your trade licence', points: 20, done: licOnFile, tab: 'documents' },
    { key: 'licence_current', label: 'Keep your trade licence in force (on file with an expiry date that has not passed)', points: 15, done: licOnFile && filled(m.license_expiry) && String(m.license_expiry).slice(0, 10) >= today, tab: 'documents' },
    { key: 'company_profile', label: 'Upload your company profile (PDF)', points: 15, done: filled(m.company_profile_doc_path), tab: 'documents' },
    // 12 Nov 2026 (browser walk H9/M12): the one step left after Submit has one name everywhere, "Confirm your services".
    { key: 'scope', label: 'Confirm your services', points: 15, done: !!eligibility && !scopeOpen, tab: 'services' },
    { key: 'description', label: 'Write a company description of at least 80 characters', points: 10, done: String(m.description ?? '').trim().length >= 80, tab: 'profile' },
    { key: 'offer', label: 'List the products or services you supply', points: 10, done: filled(m.products) || filled(m.services), tab: 'profile' },
    { key: 'catalogue', label: 'Upload a product catalogue', points: 5, done: filled(m.catalog_doc_paths), tab: 'documents' },
    // Walk of 12 Nov 2026, S4: this read leads.certifications, which nothing in the portal writes, so it could never be done. The
    // Documents tab stores the ISO certificate (leads.iso_doc_path, sent by `me`); that is what completes it now.
    { key: 'certifications', label: 'Upload your ISO certificate, if you hold one', points: 5, done: filled(m.iso_doc_path) || filled(m.certifications), tab: 'documents' },
    // Where he works is set on Services (walk of 12 Nov 2026, B1): `me` answers service_emirates as the matcher's one list.
    { key: 'emirates', label: 'Choose where you work', points: 5, done: filled(m.service_emirates), tab: 'services' },
  ];
  const score = items.reduce((s, i) => s + (i.done ? i.points : 0), 0);
  // Ranked by what each fix is worth; ties keep the order above.
  const todo = items.filter((i) => !i.done).sort((a, b) => b.points - a.points);
  return { score, items, todo };
}

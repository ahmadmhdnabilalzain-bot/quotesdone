// WHERE HE WORKS IS ONE LIST (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, blocker B1).
//
// What was wrong. Two screens asked one question and stored it in two columns: Services "Where you work" wrote
// supplier_capabilities.coverage_emirates (capabilityConfirm) and Profile "Emirates you serve" wrote leads.service_emirates
// (save_profile). Neither wrote the other, and the live matcher (fn_match_capability, and fn_sales_engineer_supply_gap the same
// way) limits a supplier to the UNION of both. So unticking Sharjah in one place did nothing while the other still held it,
// and the two screens showed different lists. Measured on production 12 Nov 2026: 2 of the 3 claimed suppliers had lists
// that disagree (both non-empty; in both the profile list is the wider), so the union matched them wider than one screen said.
//
// The rule, in this one file:
//   * what he SEES, on every screen, is the union the matcher uses (emirateList of both columns), so nothing he is shown
//     differs from what reaches him;
//   * every save of it writes BOTH columns as the same set (capabilityConfirm and save_profile call whereHeWorksWrite), so
//     the union is exactly the one list, and removing an emirate removes it for matching;
//   * the home emirate (leads.emirate: eligibility, the tie-break, the founder's registration mail) follows the list as
//     save_profile always did: the first chosen emirate, when none is on file or the one on file is no longer chosen.
// The list holds the seven emirate names only (an empty list is UAE-wide, as the matcher reads it). Directory imports left
// addresses in these columns (8 entries, measured 12 Nov 2026); a supplier's own save replaces them with what he ticked.
// No SQL: the matcher's union of two equal sets is the set. Guard: _shared/where_he_works.test.ts.

export const UAE_EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'] as const;
const byLower = new Map(UAE_EMIRATES.map((e) => [e.toLowerCase().replace(/\s+/g, ' '), e as string]));

/** The emirates named in any of the lists, by their one English name, each once, in the fixed order. Anything else is dropped. */
export function emirateList(...lists: unknown[]): string[] {
  const on = new Set<string>();
  for (const l of lists) {
    if (!Array.isArray(l)) continue;
    for (const v of l) { const e = byLower.get(String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ')); if (e) on.add(e); }
  }
  return UAE_EMIRATES.filter((e) => on.has(e));
}

/** The home emirate to write with this list, or undefined to leave the one on file. */
export function homeEmirateFor(list: string[], onFile: unknown): string | undefined {
  const first = list[0];
  if (!first) return undefined;
  const cur = typeof onFile === 'string' ? onFile : '';
  return !cur || !list.includes(cur) ? first : undefined;
}

/** The leads columns a save of the list writes: the list, and the home emirate when it must follow. */
export function leadColumnsFor(list: string[], homeOnFile: unknown): Record<string, unknown> {
  const home = homeEmirateFor(list, homeOnFile);
  return home ? { service_emirates: list, emirate: home } : { service_emirates: list };
}

// deno-lint-ignore no-explicit-any
type Db = any;

/** Writes the one list to the side the caller has not already written. `capability` updates an existing capability row only:
 *  a supplier with none has nothing the matcher reads there, and creating one here would make him a capability he never confirmed.
 *  Returns the error message, or null. */
export async function whereHeWorksWrite(admin: Db, supplierId: number, list: string[], side: 'lead' | 'capability'): Promise<string | null> {
  if (side === 'capability') {
    const { error } = await admin.from('supplier_capabilities').update({ coverage_emirates: list }).eq('supplier_id', supplierId);
    return error ? String(error.message || error) : null;
  }
  const { data: lead, error: rErr } = await admin.from('leads').select('emirate').eq('id', supplierId).maybeSingle();
  if (rErr) return String(rErr.message || rErr);
  const { error } = await admin.from('leads').update(leadColumnsFor(list, lead?.emirate)).eq('id', supplierId);
  return error ? String(error.message || error) : null;
}

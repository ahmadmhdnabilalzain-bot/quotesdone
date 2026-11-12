// A LICENCE THAT PRINTS ITS COMPANY NAME IN ARABIC ONLY IS PUT TO A PERSON, NEVER BACK TO THE SUPPLIER (12 Nov 2026, sales_engineer, built
// by it_engineer; founder ruling 1672 and the review of #1987, S7). The company is named by its trade licence, and leads.licence_legal_name
// is the ENGLISH legal name (licence_extract.ts SYS_LICENSE; an Arabic name is never put there, review of #1711). A licence that prints
// only an Arabic name therefore left the company unnamed and the gate held it "licence_unreadable", and the held-registration mails asked
// him for "a clearer copy": a clearer copy of the same Arabic licence cannot help. Now, as the held-for-a-person route of #1985 does
// (licence_read_state.ts holdLicenceForPerson): the row is held as ours ('ours_failed', and the re-read sweep is not let ask the model
// again: licence_read_tries at its ceiling of 8), one needs_review row and a ceo task now, and the hand-over's once-mark so the daily
// decider does not open a second task. He is told, truthfully, that a person will confirm the name, and Submit is not stopped. The
// Arabic name the model read is shown back to him as the company (it IS the legal name; code never transliterates it). Its own kind
// ('licence_name_for_person'), so the form never shows it as a wrong document.
// Prevented by: supplier_api/an_arabic_only_licence_goes_to_a_person.test.ts.

/** What he is told at the licence step. English, as every supplier message is (ruling 1008). */
export const ARABIC_ONLY_NOTE = 'Your trade licence prints your company name in Arabic only. A person at QuotesDone will confirm your company name from it; you do not need to do anything, and you can submit your registration.';

/** The Arabic legal name the model read when it read no English one; null otherwise (an English name is the reading as before). */
export function arabicOnlyName(merged: { legal_name_en?: unknown } | null | undefined, doc: { legal_name_ar?: unknown } | null | undefined): string | null {
  if (String(merged?.legal_name_en ?? '').trim()) return null;
  const ar = String(doc?.legal_name_ar ?? '').trim().slice(0, 200);
  return /\p{Script=Arabic}{2}/u.test(ar) ? ar : null;
}

/** The row's state for such a licence: held as ours, never re-read by the sweep. */
export const ARABIC_ONLY_ROW = { licence_read_state: 'ours_failed', licence_read_tries: 8 } as const;

/** The review row, the ceo task and the once-mark, once per file. Never fails the caller. */
export async function holdArabicOnlyNameForPerson(
  // deno-lint-ignore no-explicit-any
  admin: any, supplierId: unknown, where: string, path: unknown, arabicName: string, read: Record<string, unknown>,
): Promise<void> {
  try {
    const { data: seen } = await admin.from('agent_actions').select('id').eq('kind', 'licence_name_for_person').eq('target_id', String(supplierId)).eq('detail->>path', String(path ?? '')).limit(1);
    if (Array.isArray(seen) && seen.length) return;
  } catch (_e) { /* a courtesy check */ }
  const readLine = Object.entries(read).filter(([, v]) => String(v ?? '').trim()).map(([k, v]) => `${k} ${v}`).join(', ') || 'nothing else';
  try {
    await admin.from('agent_actions').insert({
      agent: 'sales_engineer', kind: 'licence_name_for_person', status: 'needs_review', risk: 'medium',
      title: `Name a company whose trade licence prints its name in Arabic only — supplier #${supplierId}`.slice(0, 200),
      recommendation: `The model read the licence (${readLine}) and its company name only in Arabic: ${arabicName}. The company is named by its licence's legal name, and the registration waits for it. Open the file, write the company's legal name as the licence prints it in leads.licence_legal_name (the English name if the licence or another official record gives one; otherwise decide with the founder), set licence_read_state 'read'; the gate then names the company and goes on. He was told a person will confirm his company name and was asked for nothing.`,
      detail: { supplier_id: supplierId, where, path: path ?? null, legal_name_ar: arabicName, read, message: ARABIC_ONLY_NOTE, at: new Date().toISOString() },
      target_table: 'leads', target_id: String(supplierId),
    });
    await admin.rpc('fn_ceo_task_open', { p_title: `Name a supplier from an Arabic-only trade licence: supplier #${supplierId}`,
      p_detail: `Supplier ${supplierId} attached a trade licence (${String(path ?? '')}) whose company name is printed in Arabic only: ${arabicName}. Write its legal name in leads.licence_legal_name and set licence_read_state 'read'; the registration then goes on. He was told a person will confirm the name.` });
    await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'held_registration_for_ceo', status: 'auto_done', risk: 'low',
      title: `Held registration put to the ceo seat — supplier #${supplierId}`.slice(0, 200), recommendation: 'No action required here. The ceo task decides it.',
      detail: { supplier_id: supplierId, clock: `licence_being_read:${String(path ?? '')}`, why: 'the licence prints the company name in Arabic only' }, target_table: 'leads', target_id: String(supplierId) });
  } catch (e) { console.error(JSON.stringify({ at: `${where}.arabic_only_name`, supplier: supplierId, error: String(e) })); }
}

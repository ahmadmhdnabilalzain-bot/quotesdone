// WHAT THE SERVICES TAB MAY SHOW OF THE DOCUMENTS IT READ, AND WHAT A REFRESH MAY NOT TAKE AWAY (review of #1796, 2 Nov 2026).
// Pure functions, no React, so scripts/checks/the_services_tab_never_says_found_no_service_of_a_file_it_did_not_read.test.mjs can fail them.
// Node strips the types on import, so nothing here imports an alias.

// ENGLISH ONLY TO A SUPPLIER (ruling 1008). A profile read off a picture may be Arabic; the trade it names is shown by its English name, and
// the Arabic line that proved it stays stored and is not repeated on this screen.
export const ARABIC_SCRIPT = /[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]/;
export const isEnglishLine = (line: unknown): boolean => { const s = String(line ?? '').trim(); return !!s && !ARABIC_SCRIPT.test(s); };
export const englishLines = (lines: readonly unknown[]): string[] => lines.map((l) => String(l ?? '').trim()).filter(isEnglishLine);

// A RELOAD BECAUSE THE PROFILE FINISHED READING keeps what the supplier has done since the tab opened (ticks, removed trades, the roles it
// chose, the text it typed). Only the checklist and the documents are new. A reload for any other reason (after a save, a retry) takes the
// server's values, as it always has.
export const reloadSet = (cur: ReadonlySet<string>, fresh: Iterable<string>, keep: boolean): Set<string> => new Set(keep ? cur : fresh);
export const reloadRoles = (cur: readonly string[], fresh: readonly string[], keep: boolean): string[] => (keep && cur.length ? [...cur] : [...fresh]);
export const reloadText = (cur: string, fresh: string, keep: boolean): string => (keep && cur.trim() ? cur : fresh);

// ONE PLAIN-ENGLISH LINE PER DOCUMENT, FROM ITS REAL STATE. The fallback list used to print the raw status ("needs_ocr", "unreadable",
// "refused") and "read, no service matched" for a document whose reading service was down or whose trades were held.
export type DocStateLike = { status?: string; choice?: string; reason?: string; source?: string; trades?: readonly unknown[]; vision_held?: readonly unknown[] };
export function docStateLine(d: DocStateLike): string {
  if ((d.trades || []).length) return 'read; the services it names are listed above';
  switch (d.status) {
    case 'reading': return 'still being read';
    case 'needs_ocr': return /^The (picture|scanned PDF) /.test(d.reason || '') ? String(d.reason) : 'a scan or photo with no printed text that we could read';
    case 'unreadable': return 'the file is damaged and could not be opened';
    case 'refused': return 'not accepted by our file check, so it was not read';
    case 'needs_cad_conversion': return 'a drawing file that has to be converted before it can be read';
    case 'read':
      if (d.choice === 'unavailable') return 'could not be read just now because our reading service was not available; please upload it again later';
      if (d.choice === 'held') return 'read, but we could not settle on a service from it';
      if ((d.vision_held || []).length) return 'read from a picture; the services found are waiting for our sales engineer to check';
      return 'read, no service matched';
    default: return 'not read yet';
  }
}

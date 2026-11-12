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
// WHAT SCREEN 1 TICKS WHEN THE LIST ARRIVES, THE SAME LIVE AS ON A RELOAD (12 Nov 2026, review of #1975, item 2). Only what is his is
// ticked: `his` is the proposals he already confirmed (services_state `stated` = among his confirmed services; empty before his first
// Confirm, founder 862) and his own screen-1 ticks kept in this browser for the same reading (qd-svc-step). Nothing else is ever
// ticked for him. A reload draws exactly `his`. A live arrival keeps everything he did meanwhile and adds `his` only for rows that
// were not on his screen before (a row he saw and unticked stays unticked). The live arrival was the wrong one: it ignored `his`,
// so a proposal he had already confirmed came back unticked live and ticked after a reload.
export const arrivedTicks = (cur: ReadonlySet<string>, shownBefore: ReadonlySet<string>, his: Iterable<string>, keep: boolean): Set<string> => {
  if (!keep) return new Set(his);
  const out = new Set(cur);
  for (const k of his) if (!shownBefore.has(k)) out.add(k);
  return out;
};
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
      // Review of 12 Nov 2026: he was told to upload again under "still reading" about a hold on OUR side. The licence step's wording.
      if (d.choice === 'unavailable') return 'read; our document reader has not finished understanding it yet. That is on our side, not yours: we read it again automatically, and you can carry on';
      if (d.choice === 'held') return 'read, but we could not settle on a service from it';
      if ((d.vision_held || []).length) return 'read from a picture; the services found are waiting for our sales engineer to check';
      return 'read, no service matched';
    default: return 'not read yet';
  }
}

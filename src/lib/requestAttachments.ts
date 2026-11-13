// What the request composer (src/components/me/NewRequest.tsx) sends as `drawing` to customer_api
// create_inquiry, when the customer attaches more than one file.
//
// MEASURED 22 SEP 2026 (production walk, customer portal, en-1440 and ar-390): a BOQ sheet was read
// (3 lines), then a drawing PDF was attached and the BOQ card showed the drawing's 1 line — the sheet's
// 3 lines were gone. The composer held ONE attachment and each upload replaced it. create_inquiry takes
// one `drawing` object: one BOQ (drawing.boq), any number of verified redacted pages
// (drawing_redacted_paths, checked server-side against the customer's own redaction runs) and one
// original file path. So the files are merged here, not replaced:
//   * the BOQ: a BOQ the customer attached (brief_source 'boq') is never displaced by a drawing's own
//     reading; otherwise the newest reading wins;
//   * the redacted pages: every file's verified pages are kept, in order, without repeats (24 max, the
//     server's own cap); a HELD file adds none and takes none away;
//   * share_redacted=false only when nothing at all is left to share.
// Prevented by: src/lib/requestAttachments.test.mjs.
type Boq = { boq?: unknown[] } & Record<string, unknown>;
export type Attachment = {
  drawing_file_path: string | null;
  drawing_file_name: string | null;
  drawing_redacted_paths: string[] | null;
  boq: Boq | null;
  brief_source: string;
  held?: boolean;
  held_name?: string | null;
  share_redacted?: boolean;
  files?: string[];
};

const hasLines = (b: Boq | null | undefined) => !!(b && Array.isArray(b.boq) && b.boq.length);

export function mergeAttachment(prev: Attachment | null, next: Attachment): Attachment {
  const files = [...new Set([...(prev?.files || (prev?.drawing_file_name ? [prev.drawing_file_name] : [])), ...(next.drawing_file_name ? [next.drawing_file_name] : [])])];
  if (!prev) return { ...next, ...(next.held ? { held_name: next.drawing_file_name } : {}), files };
  // The customer's own redaction boxes re-run a held file: its new result replaces its hold.
  const prevHeldName = prev.held ? (prev.held_name ?? prev.drawing_file_name) : null;
  const prevHeld = !!prevHeldName && prevHeldName !== next.drawing_file_name;
  // A customer's existing quotation (13 Nov 2026) is his own item list too: a later drawing's reading never displaces it.
  const own = (s: string) => s === 'boq' || s === 'quotation';
  const prevIsBoq = own(prev.brief_source) && hasLines(prev.boq);
  const nextIsBoq = own(next.brief_source) && hasLines(next.boq);
  const boq = nextIsBoq || (!prevIsBoq && hasLines(next.boq)) ? next.boq : prev.boq;
  const paths = [...new Set([...(prev.drawing_redacted_paths || []), ...(next.drawing_redacted_paths || [])])].slice(0, 24);
  const held = prevHeld || !!next.held;
  return {
    drawing_file_path: next.drawing_file_path || prev.drawing_file_path,
    drawing_file_name: next.drawing_file_name || prev.drawing_file_name,
    drawing_redacted_paths: paths.length ? paths : null,
    boq,
    brief_source: boq === next.boq ? next.brief_source : prev.brief_source,
    ...(held ? { held: true, held_name: next.held ? next.drawing_file_name : prevHeldName } : {}),
    ...(held && !paths.length ? { share_redacted: false } : {}),
    files,
  };
}

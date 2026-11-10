// A CUSTOMER'S DRAWING PATH IS ONE OF THEIR OWN UPLOADS (it_engineer, security checklist audit 10 Nov 2026, M1).
//
// create_inquiry took drawing.drawing_file_path from the request body and wrote it onto the inquiry. my_inquiries
// then signs that path back to the customer (lib/storage.ts signedDrawing, a 1-hour URL into the private
// drawing-files bucket), and it is the "original" a revealed supplier is told exists. So a customer who learned
// another customer's path could have the platform sign that file back to them, or attach it to their own request.
// Every legitimate path is written by storeOriginal (lib/drawings.ts) as drawings/<customer id>/<ts>_<name>, with
// the caller's own customers.id, so anything else in the body is a tampered or broken request.
// Prevented by ./drawing_path.test.ts.
const MAX_PATH = 512;

/** The path when it is under this customer's own drawings/ prefix; null when none was given. */
export function ownDrawingPath(custId: string | number, raw: unknown): { ok: true; path: string | null } | { ok: false } {
  if (!raw) return { ok: true, path: null };   // the same "none given" create_inquiry always read from a falsy value
  const p = String(raw);
  const prefix = `drawings/${String(custId)}/`;
  if (!String(custId) || p.length > MAX_PATH || !p.startsWith(prefix) || p.length === prefix.length) return { ok: false };
  // No step out of the prefix and no second root: storage keys are flat strings, but a "..", a backslash or a
  // control character has no place in a name storeOriginal wrote (safeFilename keeps [\w.-]).
  if (p.includes('..') || p.includes('\\') || p.includes('//') || /[\u0000-\u001f]/.test(p)) return { ok: false };
  return { ok: true, path: p };
}

// licence_second_read — WHO "ONE OF OUR TEAM" IS WHEN NO PERSON PRESSES A BUTTON (13 Nov 2026, sales_engineer; founder ruling 1681:
// "the reader has to confirm ... I'm expecting the artificial intelligence to do that"). A file the first reader is not sure of
// (licence_extract.ts licenceJudgementOf outcome iii: a non-licence kind at 'medium', or any non-licence kind with both an
// authority and an expiry read) is read ONCE more, the same file, by the other model family, asked one direct question
// (licence_extract.ts SYS_LICENSE_SECOND_READ). Its answer decides (secondReadOutcome):
//   a trade licence, sure      -> its reading is the reading: stored and gated as any licence (fn_licence_authority_class still refuses
//                                 a chamber, a municipality office, GDRFA or the FTA as a licensing authority);
//   another document, sure     -> named as the wrong document, nothing stored;
//   unsure, or no answer       -> held, and a person is asked (licence_read_state.ts holdLicenceForPerson), as before the ruling.
// A file the first reader called a licence, or named at 'high', is never read twice: only a held reading reaches askSecond.
// Prevented by: _shared/the_reader_decides_what_is_a_trade_licence.test.ts.
import { secondReadOutcome, UNREADABLE_LICENCE, type HeldForPerson, type WrongDocument } from './licence_extract.ts';

type Doc = ReturnType<typeof UNREADABLE_LICENCE>;
export type SecondRead = { asked: boolean; model: string | null; outcome: 'licence' | 'wrong_document' | 'held_for_person' | null };

/** The final doc for one licence-slot answer. `askSecond` is called only for a held reading, once; `settle` turns a raw answer into the
 *  doc the caller stores (normaliseLicence plus license_extract's own proofs). */
export async function decideWithSecondRead<S extends { doc: Doc }>(
  first: S, firstModel: string | null,
  askSecond: (firstModel: string) => Promise<{ ai: Record<string, unknown>; model: string | null } | null>,
  settle: (raw: Record<string, unknown>) => Promise<S>,
): Promise<{ s: S; second: SecondRead }> {
  const held = first.doc.held_for_person as HeldForPerson | null;
  if (!held) return { s: first, second: { asked: false, model: null, outcome: null } };
  // without the first answer's model the other family cannot be named: a person is asked, as before
  if (!firstModel) return { s: { ...first, doc: { ...first.doc, held_for_person: { ...held, second_read: { model: null, kind: 'not_asked', confidence: '', why: 'the first answer named no model' } } } }, second: { asked: false, model: null, outcome: 'held_for_person' } };
  let got: { ai: Record<string, unknown>; model: string | null } | null = null;
  try { got = await askSecond(firstModel); } catch (_e) { got = null; }
  const j = secondReadOutcome(held, got?.ai ?? null, got?.model ?? null);
  const second: SecondRead = { asked: true, model: got?.model ?? null, outcome: j.outcome };
  if (j.outcome === 'licence') return { s: await settle(got!.ai), second };
  if (j.outcome === 'wrong_document') return { s: { ...first, doc: { ...UNREADABLE_LICENCE(), wrong_document: j.wrong as WrongDocument } }, second };
  return { s: { ...first, doc: { ...first.doc, held_for_person: j.held } }, second };
}

/** SHA-256 of the file in the licence slot (hex), so the same file refused twice for one supplier is known (recordWrongDocument). */
// deno-lint-ignore no-explicit-any
export async function licenceFileSha(body: { images?: any[]; file_b64?: string }): Promise<string | null> {
  const first = Array.isArray(body.images) && body.images.length ? (body.images[0]?.b64 ?? body.images[0]?.data ?? body.images[0]) : body.file_b64;
  if (typeof first !== 'string' || !first) return null;
  try {
    // a plain loop, not Uint8Array.from with a callback: 1,106 ms of CPU for a 12 MB file, measured 18 Nov 2026 (review of #2054)
    const bin = atob(first.replace(/^data:[^;]+;base64,/, ''));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    return [...d].map((b) => b.toString(16).padStart(2, '0')).join('');
  } catch (_e) { return null; }
}

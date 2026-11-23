// inquiry_intake/drawing_open_lines.ts — THE DRAWING'S OPEN LINES (14 Sep 2026): the one Yes / Adjust / Not sure question
// about the BOQ lines we did not read, offered beside Send, and the CAD ask for a photo of a drawing. Appends to the reply
// (`out`) when it asks; hands back the check and its flags for the brief, and the question card. Moved verbatim from
// handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines).
// deno-lint-ignore-file no-explicit-any
import { confirmQuestion, openLines, readConfirmAnswer, type BoqCheck } from '../_shared/boq_open_lines.ts';

type NextQuestion = { key: string | null; text: string; options: string[] | null; suggested?: string | null } | null;

export function drawingOpenLines(c: { drawingBoq: any; prevBrief: any; text: string; status: string; ar: boolean; out: any; nextQuestion: NextQuestion }) {
  const { drawingBoq, prevBrief, text, status, ar, out } = c;
  let { nextQuestion } = c;
  // ── THE DRAWING'S OPEN LINES (14 Sep 2026) ─────────────────────────────────────────────────────
  // A drawing's BOQ line we did not READ (a device count, a loop size, a cable length) is shown to
  // the customer as OUR count — numbered on the marked-up copy the portal draws — and ONE question
  // is asked: Yes / Adjust / Not sure (_shared/boq_open_lines.ts). The customer is never asked to
  // count (founder, relayed: "what if the customer didnt count or too lazy to count"). The question
  // does not hold the request: it is offered beside Send, and whatever is true when the customer
  // presses Send — confirmed, adjusted, not sure, or unanswered — is what create_inquiry records on
  // the inquiry and applies to the lines. "We don't assume stuff": an unanswered line goes out
  // marked "estimated from drawing, supplier to verify take-off", never as a settled quantity.
  const nowIso = new Date().toISOString();
  const openBoq = openLines(drawingBoq && Array.isArray(drawingBoq.boq) ? drawingBoq.boq : []);
  let boqCheck: BoqCheck | null = (prevBrief.boq_check && typeof prevBrief.boq_check === 'object') ? prevBrief.boq_check : null;
  let boqAsked = prevBrief.boq_asked === true;
  if (openBoq.length) {
    if (boqCheck && boqCheck.status === 'asked' && boqAsked && text) {
      const r = readConfirmAnswer(boqCheck.lines, text);
      boqCheck = { ...boqCheck, status: r.status, answered_at: nowIso, answer: text.slice(0, 300), adjustments: r.adjustments };
    }
    if (!boqCheck) boqCheck = { status: 'asked', asked_at: nowIso, answered_at: null, lines: openBoq };
    if (boqCheck.status === 'asked' && status === 'ready') {
      const q = confirmQuestion(boqCheck.lines, ar ? 'ar' : 'en');
      nextQuestion = { key: q.key, text: q.text, options: q.options };
      out.assistant_message = `${out.assistant_message || ''} ${q.text}`.trim();
      boqAsked = true;
    }
  }
  // A photo or scan of a drawing: the CAD or PDF it came from counts every device exactly (a CAD
  // block count), so ask for it once — never as a condition.
  const imageOnly = !!drawingBoq && Array.isArray(drawingBoq.kinds) && drawingBoq.kinds.every((k: unknown) => k === 'image') && openBoq.length > 0;
  let cadAsked = prevBrief.cad_asked === true;
  if (imageOnly && !cadAsked) {
    out.assistant_message = `${out.assistant_message || ''} ${ar ? 'إن كان لديك ملف CAD (بصيغة DWG أو DXF) أو ملف PDF الأصلي لهذا المخطط فأرفقه، لنحصي منه كل جهاز بدقة.' : 'If you have the CAD file (DWG or DXF) or the original PDF of this drawing, attach it and we will count every device from it exactly.'}`.trim();
    cadAsked = true;
  }
  return { boqCheck, boqAsked, cadAsked, nextQuestion };
}

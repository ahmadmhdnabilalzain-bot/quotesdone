// boq_open_lines — a BOQ line whose quantity we did not READ goes back to the customer as OUR count
// to confirm, never as a question asking them to count, and never silently. No model.
//
// THE RULES (founder, 14 Sep 2026, relayed): intake "we don't assume stuff"; then "what if the
// customer didnt count or too lazy to count" — so the customer is NEVER asked to count:
//   1. Every uncertain line is shown with our own count (or "we could not count these") on a
//      marked-up copy of their drawing, and ONE question is asked: Yes / Adjust / Not sure.
//   2. Yes            -> the count stands as customer-confirmed.
//      Adjust         -> the numbers they type replace ours, line by line, as customer-stated.
//      Not sure, or no answer by the time the request is sent (the window) -> the request still
//      goes out, and each open line says "estimated from drawing, supplier to verify take-off".
//   3. Whatever happens is recorded on the inquiry (spec.boq_check), so the outcome is a fact
//      anyone can read, not an assumption buried in a quantity.
//
// WHAT COUNTS AS OPEN. qty null, or qty_status 'to_confirm' / 'estimated' (a count our code made
// but could not cross-check). A quantity PRINTED on the document (qty_status absent or 'read') is
// not re-asked: that is the customer's own document speaking.

// check_confirmed: our count agreed with the second, independent reading (drawing_boq/confirm.ts).
export type QtyStatus = 'read' | 'to_confirm' | 'estimated' | 'check_confirmed' | 'customer_confirmed' | 'customer_stated' | 'estimated_supplier_to_verify';
export type Line = {
  section?: string; item?: string; description: string; qty: number | null; unit: string; basis?: string;
  confidence?: string; qty_status?: QtyStatus; estimate?: number | null; type?: string;
};
export type OpenLine = { key: string; description: string; unit: string; estimate: number | null; type?: string };
export type BoqCheck = {
  status: 'asked' | 'confirmed' | 'adjusted' | 'not_sure' | 'unanswered';
  asked_at?: string; answered_at?: string | null; answer?: string | null;
  lines: OpenLine[]; adjustments?: Record<string, number>;
};

const slug = (s: string) => String(s || '').toLowerCase().replace(/[^a-z0-9؀-ۿ]+/g, '_').replace(/^_|_$/g, '').slice(0, 40);
export const lineKey = (l: { description: string; type?: string }) => 'boq_' + (l.type || slug(l.description));

export function isOpen(l: Line): boolean {
  return l.qty == null || l.qty_status === 'to_confirm' || l.qty_status === 'estimated';
}

export function openLines(boq: Line[] | null | undefined): OpenLine[] {
  const out: OpenLine[] = []; const seen = new Set<string>();
  for (const l of Array.isArray(boq) ? boq : []) {
    if (!l || !isOpen(l)) continue;
    const key = lineKey(l);
    if (seen.has(key)) continue; seen.add(key);
    const est = l.qty_status === 'to_confirm' || l.qty_status === 'estimated' ? (l.estimate ?? l.qty ?? null) : (l.estimate ?? null);
    out.push({ key, description: l.description, unit: l.unit, estimate: est == null ? null : Number(est), ...(l.type ? { type: l.type } : {}) });
  }
  return out;
}

const OPTIONS_EN = ['Yes, that is right', 'Adjust', 'Not sure'];
const OPTIONS_AR = ['نعم، هذا صحيح', 'تعديل', 'لست متأكداً'];

/** The ONE question. Our count per line; lines we could not count are named, not asked. */
export function confirmQuestion(open: OpenLine[], lang: 'en' | 'ar'): { key: 'boq_check'; text: string; options: string[] } {
  const counted = open.filter((o) => o.estimate != null);
  const uncounted = open.filter((o) => o.estimate == null);
  if (lang === 'ar') {
    const a = counted.map((o) => `${o.estimate} × ${o.description}`).join('، ');
    const b = uncounted.map((o) => o.description).join('، ');
    const text = (a ? `عددنا من مخططك (مرقّمة على النسخة المؤشّرة): ${a}.` : '')
      + (b ? ` لم نتمكن من عدّ: ${b} — سيتحقق الموردون من الكميات.` : '')
      + ' هل هذا صحيح؟';
    return { key: 'boq_check', text: text.trim(), options: OPTIONS_AR };
  }
  const a = counted.map((o) => `${o.estimate} × ${o.description}`).join(', ');
  const b = uncounted.map((o) => o.description).join(', ');
  const text = (a ? `Here is what we counted on your drawing (numbered on the marked-up copy): ${a}.` : '')
    + (b ? ` We could not count: ${b} — suppliers will verify those quantities.` : '')
    + ' Is that right?';
  return { key: 'boq_check', text: text.trim(), options: OPTIONS_EN };
}

// \b is an ASCII word boundary and never fires after an Arabic letter, so Arabic has its own pattern.
const YES = /^\s*(?:(?:y|yes|yeah|yep|correct|right|ok|okay|confirm(?:ed)?|that is right)\b|نعم|صحيح|أكيد|اكيد|تمام)/i;
const NOT_SURE = /\b(not sure|don'?t know|no idea|unsure|skip|later)\b|لست متأكد|غير متأكد|لا أعرف|لا اعرف|ما أعرف/i;

/**
 * Read the customer's reply to the ONE question. Adjustments are "<number> <what>" or
 * "<what> <number>" pairs matched to the open line whose words they name. A reply we cannot tie to
 * a line is kept as the customer's own words (answer) and the lines stay estimated — never guessed.
 */
export function readConfirmAnswer(open: OpenLine[], reply: string): { status: BoqCheck['status']; adjustments: Record<string, number> } {
  const t = String(reply || '').trim();
  if (!t) return { status: 'asked', adjustments: {} };
  const adjustments: Record<string, number> = {};
  const words = (s: string) => s.toLowerCase().replace(/[^a-z؀-ۿ ]+/g, ' ').split(/\s+/).filter((w) => w.length > 2 && !['with', 'and', 'the'].includes(w));
  const parts = t.split(/[,;\n،]+|\band\b|\bو\b/i);
  for (const p of parts) {
    const n = p.match(/(\d+)/);
    if (!n) continue;
    const pw = words(p);
    let best: OpenLine | null = null; let bestN = 0;
    for (const o of open) {
      const ow = words(o.description);
      const hit = ow.filter((w) => pw.some((x) => x.startsWith(w.slice(0, 5)) || w.startsWith(x.slice(0, 5)))).length;
      // A combined device ("smoke detector c/w sounder") must be named in full to take the number.
      if (hit > bestN || (hit === bestN && best && ow.length < words(best.description).length)) { best = o; bestN = hit; }
    }
    if (best && bestN > 0) adjustments[best.key] = Number(n[1]);
  }
  if (Object.keys(adjustments).length) return { status: 'adjusted', adjustments };
  if (NOT_SURE.test(t)) return { status: 'not_sure', adjustments };
  if (YES.test(t)) return { status: 'confirmed', adjustments };
  return { status: 'not_sure', adjustments };
}

const VERIFY_EN = 'estimated from drawing, supplier to verify take-off';

/** Apply the outcome to the BOQ the suppliers receive. Nothing is left silently assumed. */
export function settleLines(boq: Line[], check: BoqCheck | null | undefined): Line[] {
  const status = check?.status || 'unanswered';
  const adj = check?.adjustments || {};
  return (Array.isArray(boq) ? boq : []).map((l) => {
    if (!isOpen(l)) return l;
    const key = lineKey(l);
    const est = l.estimate ?? l.qty ?? null;
    if (key in adj) return { ...l, qty: adj[key], qty_status: 'customer_stated' as const, basis: `${l.basis ? l.basis + '; ' : ''}quantity stated by the customer` };
    if (status === 'confirmed' && est != null) return { ...l, qty: est, qty_status: 'customer_confirmed' as const, basis: `${l.basis ? l.basis + '; ' : ''}our count, confirmed by the customer` };
    return { ...l, qty: est, qty_status: 'estimated_supplier_to_verify' as const, basis: `${l.basis ? l.basis + '; ' : ''}${VERIFY_EN}` };
  });
}

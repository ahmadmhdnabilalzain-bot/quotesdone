// markup — the marked-up copy of the customer's drawing: every symbol our counter found, circled
// and numbered per type, drawn by code from the counter's boxes (symbol_count.ts). Pure: returns an
// SVG the portal lays over the image, and the fixture test composites onto the PNG to look at.
//
// WHY (founder, 14 Sep 2026, relayed: "what if the customer didnt count or too lazy to count"). The
// customer is never asked to count. They are shown OUR count, where each number sits on their own
// drawing, and asked one question: is that right? A number with no picture behind it is a claim;
// a numbered circle on their drawing is something they can check in seconds.

export type Rect = { x: number; y: number; w: number; h: number };
export type Mark = { type: string; box: Rect };

// One colour per type, chosen to stay distinct from each other and from red fire-alarm ink.
const PALETTE = ['#0057d9', '#008a3c', '#b35900', '#7a1fa2', '#00838f', '#c2185b', '#5d4037', '#455a64'];
const esc = (s: string) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

export function markupSvg(width: number, height: number, marks: Mark[], labels: Record<string, string> = {}): string {
  const types = [...new Set(marks.map((m) => m.type))];
  const colour = (t: string) => PALETTE[types.indexOf(t) % PALETTE.length];
  const perType: Record<string, number> = {};
  const r0 = Math.max(6, Math.round(Math.min(width, height) / 160));
  const fs = Math.max(8, Math.round(r0 * 1.1));
  const shapes = marks.map((m) => {
    const n = (perType[m.type] = (perType[m.type] || 0) + 1);
    const cx = m.box.x + m.box.w / 2, cy = m.box.y + m.box.h / 2, r = Math.max(r0, Math.max(m.box.w, m.box.h) * 0.8);
    const c = colour(m.type);
    return `<circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${r.toFixed(1)}" fill="none" stroke="${c}" stroke-width="${Math.max(1.5, r0 / 4).toFixed(1)}"/>`
      + `<text x="${(cx + r).toFixed(1)}" y="${(cy - r).toFixed(1)}" font-family="Arial,sans-serif" font-size="${fs}" font-weight="700" fill="${c}" stroke="#fff" stroke-width="2.5" paint-order="stroke">${n}</text>`;
  }).join('');
  const key = types.map((t, i) => `<text x="${fs}" y="${fs * 1.6 * (i + 1)}" font-family="Arial,sans-serif" font-size="${fs * 1.2}" font-weight="700" fill="${colour(t)}" stroke="#fff" stroke-width="3" paint-order="stroke">${esc(labels[t] || t)}: ${perType[t] || 0}</text>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${shapes}${key}</svg>`;
}

/** Per-type totals of a set of marks, for the question text beside the picture. */
export function markTotals(marks: Mark[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const m of marks) out[m.type] = (out[m.type] || 0) + 1;
  return out;
}

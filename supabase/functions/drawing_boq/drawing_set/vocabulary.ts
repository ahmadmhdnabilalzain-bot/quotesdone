import type { TextRun } from '../../_shared/pdf_text_positions.ts';
import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import type { Box } from '../../_shared/anonymise.ts';
import type { Sheet, SheetKind, Status } from './types.ts';

// ── vocabulary ─────────────────────────────────────────────────────────────────────────────────
// Equipment: one unit per id. Names are the fallback when the drawing's own abbreviation table does
// not define the type.
export const EQUIPMENT: Record<string, string> = {
  RTU: 'Rooftop unit', DOAS: 'Dedicated outdoor air unit', AHU: 'Air handling unit', AH: 'Air handling unit', FCU: 'Fan coil unit',
  EF: 'Exhaust fan', SF: 'Supply fan', RF: 'Return fan', TF: 'Transfer fan', CU: 'Condensing unit', ACCU: 'Air-cooled condensing unit',
  AC: 'Split air conditioning unit (indoor)', HP: 'Heat pump', ERV: 'Energy recovery ventilator', HRV: 'Heat recovery ventilator',
  MAU: 'Make-up air unit', UH: 'Unit heater', GUH: 'Gas unit heater', CUH: 'Cabinet unit heater', IRH: 'Infrared radiant tube heater',
  EWH: 'Electric wall heater', EUH: 'Electric unit heater', EBB: 'Electric baseboard heater', VAV: 'VAV terminal unit', FPB: 'Fan powered box',
  B: 'Boiler', CH: 'Chiller', CT: 'Cooling tower', P: 'Pump', WH: 'Water heater', DWH: 'Domestic water heater', HX: 'Heat exchanger',
  ET: 'Expansion tank', AS: 'Air separator', HUM: 'Humidifier', DH: 'Dehumidifier', FD_DAMPER: 'Fire damper',
};
// Plumbing fixtures and devices: counted per occurrence. A tag like FD-2 is a TYPE, not a unit.
export const FIXTURE: Record<string, string> = {
  'WC/L': 'Combination water closet and lavatory', WC: 'Water closet', L: 'Lavatory', LAV: 'Lavatory', UR: 'Urinal', U: 'Urinal',
  S: 'Sink', SK: 'Sink', MS: 'Mop sink', MB: 'Mop basin', SH: 'Shower', FD: 'Floor drain', FS: 'Floor sink', HB: 'Hose bibb',
  WHY: 'Wall hydrant', EWC: 'Electric water cooler / drinking fountain', DF: 'Drinking fountain', FCO: 'Floor cleanout', CO: 'Cleanout',
  WCO: 'Wall cleanout', RD: 'Roof drain', OD: 'Overflow drain', TP: 'Trap primer', IW: 'Ice maker box', WB: 'Washer box', ES: 'Eyewash station',
  EW: 'Emergency eyewash', SS_SHOWER: 'Safety shower',
  // Electrical, fire-alarm and door symbols tagged on a plan (28 Sep 2026: the drawing benchmark read 0
  // of the lighting/power sheet because these were missing). Counted per occurrence, like a fixture.
  LT: 'Light fitting', LF: 'Light fitting', EL: 'Emergency light fitting', DS: 'Double socket outlet', SSO: 'Single socket outlet',
  SW: 'Light switch', SD: 'Smoke detector', HD: 'Heat detector', MCP: 'Manual call point', D: 'Door', DR: 'Door',
  // 19 Oct 2026 drawing bench: windows tagged W1.. and sockets tagged SKT were read as nothing.
  W: 'Window', WN: 'Window', SKT: 'Socket outlet',
};
// Section of a counted fixture line; a type not listed is a plumbing fixture (the table's original scope).
export const SECTION_OF: Record<string, string> = {
  LT: 'Electrical devices', LF: 'Electrical devices', EL: 'Electrical devices', DS: 'Electrical devices', SSO: 'Electrical devices', SW: 'Electrical devices',
  SD: 'Fire alarm devices', HD: 'Fire alarm devices', MCP: 'Fire alarm devices', D: 'Doors', DR: 'Doors', W: 'Windows', WN: 'Windows', SKT: 'Electrical devices',
};
// Types written with no number are rare and specific; anything else needs a number to be a tag.
export const NO_NUMBER_OK = new Set(['EWC', 'FCO', 'DF', 'WCO', 'CO', 'SD', 'HD', 'MCP', 'SKT']);
export const SHEET_NO = /^[A-Z]{1,2}-?\d{1,2}\.\d{1,2}[A-Z]?$/;
export const PREFIX = /^\((E|R|N|D|ER|EX)\)\s*/;
export const statusOf = (p: string | undefined): Status => p === 'E' || p === 'EX' ? 'existing' : p === 'R' || p === 'ER' ? 'relocate' : p === 'D' ? 'demolish' : 'new';

export const size = (r: TextRun) => r.vertical ? r.w : r.h;
export const cx = (r: TextRun) => r.x + r.w / 2;
export const cy = (r: TextRun) => r.y + r.h / 2;
export const inBox = (r: TextRun, b: Box | null) => !!b && cx(r) >= b.x && cx(r) <= b.x + b.w && cy(r) >= b.y && cy(r) <= b.y + b.h;
export const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

/** "EF-8", "(R)EWC", "WC/L-1", "RTU1-4-H" -> {type, tag, status} or null. */
export function parseTag(text: string): { type: string; tag: string; status: Status; kind: 'equipment' | 'fixture' | 'terminal' } | null {
  const t = text.trim().toUpperCase();
  const pm = PREFIX.exec(t); const body = pm ? t.slice(pm[0].length) : t; const status = statusOf(pm?.[1]);
  // VAV terminal named after its air handler: RTU1-4, RTU1-4-H (H = with reheat).
  let m = /^([A-Z]{2,4})(\d{1,2})-(\d{1,2})(-H)?$/.exec(body);
  if (m && EQUIPMENT[m[1]]) return { type: 'VAV', tag: `${m[1]}${m[2]}-${m[3]}${m[4] || ''}`, status, kind: 'terminal' };
  m = /^([A-Z]{1,4}(?:\/[A-Z]{1,3})?)(?:-?(\d{1,3}[A-Z]?))?$/.exec(body);
  if (!m) return null;
  const [, type, num] = m;
  if (FIXTURE[type] && (num || NO_NUMBER_OK.has(type))) return { type, tag: num ? `${type}-${num}` : type, status, kind: 'fixture' };
  if (EQUIPMENT[type] && num) return { type, tag: `${type}-${num}`, status, kind: 'equipment' };
  return null;
}

/** A sheet's number, title, scale and kind. `index` is the drawing index read off the cover sheet. */
export function sheetOf(p: PdfPage, pi: number, strip: Box | null, index: Map<string, string>): Sheet {
  const nums = p.runs.filter((r) => SHEET_NO.test(r.text.trim())).sort((a, b) => size(b) - size(a));
  const number = nums[0]?.text.trim() || `page ${pi + 1}`;
  const views = p.runs.filter((r) => !r.vertical && !inBox(r, strip) && r.h >= 0.012 && /[A-Z]{3,}/.test(r.text) && !/NOTES?:?$/.test(r.text.trim()))
    .sort((a, b) => b.h - a.h || a.y - b.y);
  const title = index.get(number) || views.map((r) => r.text.trim()).find((t) => /PLAN|SCHEDULE|DETAIL|DIAGRAM|SECTION|ELEVATION|LEGEND|SPECIFICATION/.test(t)) || views[0]?.text.trim() || '';
  const all = p.runs.map((r) => r.text).join(' ');
  const sc = /SCALE\s*:?\s*((?:\d+\/)?\d+"\s*=\s*\d+'\s*-?\s*\d*"?|1\s*[:\/]\s*\d{1,4})/i.exec(all);
  let scale = sc ? sc[1].replace(/\s+/g, ' ').trim() : '';
  if (!scale) { const i = p.runs.findIndex((r) => /^SCALE:?$/i.test(r.text.trim())); if (i >= 0) { const r0 = p.runs[i]; const nx = p.runs.filter((o) => Math.abs(cy(o) - cy(r0)) < r0.h && o.x > r0.x && o.x < r0.x + 0.06).sort((a, b) => a.x - b.x)[0]; if (nx) scale = nx.text.trim(); } }
  const T = title.toUpperCase();
  const kind: SheetKind = /DEMO/.test(T) ? 'demolition_plan' : /SCHEDULE/.test(T) ? 'schedule' : /PLAN/.test(T) ? 'plan' : 'other';
  return { page: pi + 1, number, title, scale, kind };
}

/** Drawing index on any sheet: a sheet-number run with a title run to its right on the same line. */
export function drawingIndex(pages: PdfPage[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const p of pages) for (const r of p.runs) {
    if (r.vertical || !SHEET_NO.test(r.text.trim())) continue;
    const right = p.runs.filter((o) => !o.vertical && o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.6 && o.x > r.x + r.w && o.x < r.x + r.w + 0.03 && /[A-Z]{3,}/.test(o.text))
      .sort((a, b) => a.x - b.x)[0];
    if (right && !out.has(r.text.trim())) out.set(r.text.trim(), right.text.trim());
  }
  return out;
}

/** Abbreviation table ("RTU  ROOFTOP UNIT"): the drawing's own names for its tag types. */
export function abbreviations(pages: PdfPage[]): Map<string, string> {
  const out = new Map<string, string>();
  for (const p of pages) for (const r of p.runs) {
    const k = r.text.trim().replace(/\s*\([A-Z]+\)$/, '');
    if (r.vertical || !/^[A-Z]{1,5}$/.test(k) || !(EQUIPMENT[k] || FIXTURE[k])) continue;
    const right = p.runs.filter((o) => !o.vertical && o !== r && Math.abs(cy(o) - cy(r)) < r.h * 0.5 && o.x > r.x + r.w && o.x < r.x + r.w + 0.03 && /^[A-Z][A-Z ,\-\/]{4,}$/.test(o.text.trim()))
      .sort((a, b) => a.x - b.x)[0];
    if (right && !out.has(k)) out.set(k, right.text.trim());
  }
  return out;
}

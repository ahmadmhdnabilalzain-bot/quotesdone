import type { PdfPage } from '../../_shared/pdf_text_positions.ts';
import { titleStrip, type Box } from '../../_shared/anonymise.ts';
import { feet, measureDucts, measurePipes, metres, scaleLabels, tooDense, type Measured } from '../drawing_lengths.ts';
import { abbreviations, clip, drawingIndex, EQUIPMENT, FIXTURE, inBox, parseTag, SECTION_OF, sheetOf, size, statusOf } from './vocabulary.ts';
import { keyedNotes, tagsOnSheet, unreadTagLike } from './tags.ts';
import { scheduleRows } from './schedules.ts';
import type { Consumed, ScheduleTable, Sheet, Status, TakeoffLine } from './types.ts';
import { planRoles, sheetWords, type SheetWords } from './enlarged.ts';
import { LENGTH_MAY_INCLUDE_ENLARGED, LENGTH_MAY_INCLUDE_ENLARGED_AR } from '../length_notes.ts';

// A keyed note is scope when it tells someone to do or supply something; "EXISTING … TO REMAIN" is not.
const SCOPE_NOTE = /\b(PROVIDE|INSTALL|REMOVE|DEMO(?:LISH)?|RELOCATE|REPLACE|CONNECT|ROUTE|FURNISH|EXTEND|CAP|NEW|TERMINATION|LOUVER|DAMPER|VALVE|MAN\s+BARS?|GOOSENECK|SOLENOID|FLUSH\s+VALVE)\b/;
const NOT_SCOPE = /\bTO REMAIN\b|\bCONTINUED\b|\bFIELD VERIFY\b(?!.*\bPROVIDE\b)/;

/** Sizes of duct and pipe printed on the drawing, grouped. Lengths are not printed: qty stays null. */
function sizesOn(p: PdfPage, strip: Box | null, consumed: Consumed) {
  const duct = new Map<string, number>(); const pipe = new Map<string, { n: number; status: Status }>(); const louver = new Map<string, number>();
  for (const r of p.runs) {
    if (inBox(r, strip) || consumed.has(r)) continue;
    const t = r.text.trim().toUpperCase();
    let m = /^(\d{1,2})\s*X\s*(\d{1,2})\s+LOUVER$/.exec(t);
    if (m) { const k = `${m[1]}x${m[2]}`; louver.set(k, (louver.get(k) || 0) + 1); continue; }
    m = /^(\d{1,2})\s*"?\s*X\s*(\d{1,2})"?(\s*\(1"\s*LNR\))?(?:\s+(?:UP|DN|DOWN))?$/.exec(t);
    if (m) { const k = `${m[1]}x${m[2]}${m[3] ? ' (1" liner)' : ''}`; duct.set(k, (duct.get(k) || 0) + 1); continue; }
    m = /^(\d{1,2})\s*"\s*Ø$/.exec(t);
    if (m) { const k = `${m[1]}" round`; duct.set(k, (duct.get(k) || 0) + 1); continue; }
    m = /^(?:\((E|R|N|D)\))?\s*(\d+(?:\s?\d\/\d)?|\d\/\d)"\s*(SS|SAN|V|VENT|W|CW|HW|HWR|TW|G|GAS|ST|RD|CD)$/.exec(t);
    if (m) { const st = statusOf(m[1]); const k = `${m[2]}" ${m[3]}|${st}`; const g = pipe.get(k) || { n: 0, status: st }; g.n++; pipe.set(k, g); }
  }
  return { duct, pipe, louver };
}

// Arabic names of the systems, for the measured length lines (22 Sep 2026; every user-facing string EN + AR).
const SERVICE_AR: Record<string, string> = { SS: 'صرف صحي', V: 'تهوية الصرف', CW: 'مياه باردة', HW: 'مياه ساخنة', HWR: 'راجع المياه الساخنة', G: 'غاز', ST: 'تصريف أمطار', CD: 'تصريف التكثيف', REF: 'تبريد', CHW: 'مياه مبردة', HHW: 'مياه تدفئة', CA: 'هواء مضغوط' };
const SERVICE: Record<string, string> = { SS: 'sanitary sewer (waste)', SAN: 'sanitary sewer (waste)', V: 'vent', VENT: 'vent', W: 'waste', CW: 'domestic cold water', HW: 'domestic hot water', HWR: 'hot water return', TW: 'tempered water', G: 'gas', GAS: 'gas', ST: 'storm', RD: 'roof drain leader', CD: 'condensate drain' };

/** The whole set. `schedules` are OCR tables from the portal: they enrich lines and never make one 'read'. */
export function takeoff(pages: PdfPage[], schedules: ScheduleTable[] = []) {
  const index = drawingIndex(pages);
  const abbr = abbreviations(pages);
  const strips = pages.map((p) => titleStrip(p));
  const sheets = pages.map((p, i) => sheetOf(p, i, strips[i], index));
  const lines: TakeoffLine[] = [];
  const nameOf = (type: string) => {
    const a = abbr.get(type);
    const base = EQUIPMENT[type] || FIXTURE[type] || type;
    return a ? a.charAt(0) + a.slice(1).toLowerCase() : base;
  };
  const sched = scheduleRows(schedules);
  const airLetters = [...sched.keys()].filter((k) => /^[A-Z]$/.test(k));

  // ── equipment & terminals: distinct ids across the set; fixtures: per sheet, max over plans ──
  const ids = new Map<string, { type: string; status: Status; sheets: Set<string>; demoOnly: boolean }>();
  const fixtures = new Map<string, { type: string; status: Status; perSheet: Map<string, number>; demo: boolean }>();
  const diffusers = new Map<string, { n: number; necks: Map<string, number>; cfm: number; cfmKnown: number; sheets: Set<string>; inferred: boolean }>();
  const notes: { sheet: Sheet; n: number; text: string; bubbles: number; outlined: boolean }[] = [];
  const measured: { sheet: Sheet; m: Measured }[] = []; const dense: string[] = [];
  const sizes: { sheet: Sheet; duct: Map<string, number>; pipe: Map<string, { n: number; status: Status }>; louver: Map<string, number> }[] = [];
  const coverage = { tags_read: 0, tag_like_unread: 0 };
  pages.forEach((p, i) => {
    const sh = sheets[i];
    // Only PLANS are counted. A cover sheet's legend and abbreviation table ("CO2 CARBON DIOXIDE", a
    // legend "A") and a detail sheet's callouts are not items: measured 21 Sep 2026, counting every
    // sheet added a phantom CO-2 and a 13th type-A diffuser from the mechanical cover sheet.
    if (sh.kind !== 'plan' && sh.kind !== 'demolition_plan') {
      // A sheet that is not a plan by its title is not counted, so a tag on it is not read either: "GROUND FLOOR AC
      // LAYOUT" (no PLAN in the title) carrying FCU-1..12 beside a PLAN sheet with EF-1, EF-2 read 2 of 14 (independent
      // review, 27 Oct 2026). Its tagged runs count as unread, so the set goes to the model. A schedule is not a plan
      // by design (its rows are read in schedule_tables). Legend and abbreviation samples are left out by unreadTagLike.
      if (sh.kind === 'other') coverage.tag_like_unread += unreadTagLike(p, strips[i], new Set());
      sizes.push({ sheet: sh, duct: new Map(), pipe: new Map(), louver: new Map() }); return;
    }
    const { hits, diffusers: dfs, consumed } = tagsOnSheet(p, i, strips[i], airLetters);
    const demoSheet = sh.kind === 'demolition_plan';
    coverage.tags_read += hits.length; coverage.tag_like_unread += unreadTagLike(p, strips[i], consumed);
    for (const h of hits) {
      const k = parseTag(h.tag)!;
      if (k.kind === 'fixture') {
        const status: Status = demoSheet && h.status === 'new' ? 'demolish' : h.status;
        const key = `${h.tag}|${status}`;
        const f = fixtures.get(key) || { type: h.type, status, perSheet: new Map(), demo: demoSheet };
        f.perSheet.set(sh.number, (f.perSheet.get(sh.number) || 0) + 1); fixtures.set(key, f);
      } else {
        const e = ids.get(h.tag) || { type: h.type, status: h.status, sheets: new Set(), demoOnly: true };
        e.sheets.add(sh.number); if (!demoSheet) e.demoOnly = false; if (h.status !== 'new') e.status = h.status; ids.set(h.tag, e);
      }
    }
    for (const d of dfs) {
      const g = diffusers.get(d.letter) || { n: 0, necks: new Map(), cfm: 0, cfmKnown: 0, sheets: new Set(), inferred: false };
      if (d.inferred) g.inferred = true;
      g.n++; if (d.neck) g.necks.set(d.neck, (g.necks.get(d.neck) || 0) + 1); if (/^\d+$/.test(d.cfm)) { g.cfm += Number(d.cfm); g.cfmKnown++; } g.sheets.add(sh.number); diffusers.set(d.letter, g);
    }
    for (const n of keyedNotes(p, strips[i], consumed)) notes.push({ sheet: sh, ...n });
    sizes.push({ sheet: sh, ...sizesOn(p, strips[i], consumed) });
    // Lengths from the CAD layers, new-work plans only (a demolition plan's runs are removals).
    if (!demoSheet && p.layers) {
      if (tooDense(p, strips[i])) { dense.push(sh.number); return; }
      const sc = scaleLabels(p, strips[i]);
      for (const m of [...measurePipes(p, strips[i], sc), ...measureDucts(p, strips[i], sc)]) measured.push({ sheet: sh, m });
    }
  });

  const specFor = (tag: string) => sched.get(tag.toUpperCase());
  for (const [tag, e] of [...ids.entries()].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))) {
    const status: Status = e.demoOnly ? 'demolish' : e.status;
    if (status === 'existing') continue;                                       // existing to remain is not scope
    const spec = specFor(tag);
    const what = e.type === 'VAV' ? (tag.endsWith('-H') ? 'VAV terminal unit with electric reheat' : 'VAV terminal unit') : nameOf(e.type);
    lines.push({
      section: status === 'demolish' ? 'Demolition' : e.type === 'VAV' ? 'HVAC terminal units' : 'Equipment', type: `tag:${tag}`, status,
      item: `${tag} ${what}`, description: `${tag} — ${what}${spec ? ` — ${spec}` : ''}${status === 'relocate' ? ' (relocate)' : ''}`,
      qty: 1, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: [...e.sheets],
      basis: `tag ${tag} printed on ${[...e.sheets].join(', ')}; one unit per tag id${spec ? '; make/model from the schedule read by OCR — to confirm' : ''}`,
    });
  }
  // A VAV tag and its "-H" twin are the same box drawn with its reheat coil: keep one line per box.
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i]; if (!l.type.endsWith('-H')) continue;
    const base = lines.find((o) => o.type === l.type.slice(0, -2));
    if (base) { base.description = base.description.replace('VAV terminal unit', 'VAV terminal unit with electric reheat'); base.item = base.item.replace('VAV terminal unit', 'VAV terminal unit with electric reheat'); base.basis += `; reheat tag ${l.type.slice(4)} beside it`; lines.splice(i, 1); }
  }
  for (const [key, f] of [...fixtures.entries()].sort()) {
    if (f.status === 'existing') continue;                                     // (E) existing to remain is not scope
    const tag = key.split('|')[0];
    const per = [...f.perSheet.entries()];
    const qty = Math.max(...per.map(([, n]) => n));
    const spec = specFor(tag.replace(/^\((E|R|N|D)\)/, ''));
    const verb = f.status === 'demolish' ? 'remove' : f.status === 'relocate' ? 'relocate / reuse' : '';
    lines.push({
      section: f.status === 'demolish' ? 'Demolition' : SECTION_OF[f.type] || 'Plumbing fixtures', type: `tag:${tag}:${f.status}`, status: f.status,
      item: `${tag} ${nameOf(f.type)}`, description: `${tag} — ${nameOf(f.type)}${spec ? ` — ${spec}` : ''}${verb ? ` (${verb})` : ''}`,
      qty, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: per.map(([s]) => s),
      basis: `tag ${tag} drawn ${per.map(([s, n]) => `${n}x on ${s}`).join(', ')}; the same fixture appears on each system's plan, so the count is the largest on one sheet, not the sum`,
    });
  }
  for (const [letter, g] of [...diffusers.entries()].sort()) {
    const spec = specFor(letter);
    const necks = [...g.necks.entries()].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${n}x ${k}`).join(', ');
    lines.push({
      section: 'Air devices', type: `air_device:${letter}`, status: 'new',
      item: `Air device type ${letter}`, description: `Air device type ${letter}${spec ? ` — ${spec}` : ''}${necks ? ` (necks ${necks})` : ''}`,
      ...(g.inferred && !spec ? { qty: g.n, estimate: g.n, qty_status: 'to_confirm' as const, confidence: 'low' as const } : { qty: g.n, qty_status: 'read' as const, confidence: 'medium' as const }),
      unit: 'nos', sheets: [...g.sheets],
      basis: g.inferred && !spec
        ? `${g.n} "${letter}" tag(s) on ${[...g.sheets].join(', ')} drawn like the other air-device tags; "${letter}" continues the A.. series and no schedule row confirms it — to confirm`
        : `each "${letter}" tag counted on ${[...g.sheets].join(', ')}; ${g.cfmKnown ? `${g.cfm} cfm total over ${g.cfmKnown} devices` : 'airflow not stated'}`,
    });
  }
  // Louvers: size + word on the plan; read.
  const louv = new Map<string, number>();
  for (const s of sizes) for (const [k, n] of s.louver) louv.set(k, Math.max(louv.get(k) || 0, n));
  for (const [k, n] of louv) lines.push({ section: 'Equipment', type: `louver:${k}`, status: 'new', item: `Louver ${k}`, description: `Louver ${k} in`, qty: n, unit: 'nos', qty_status: 'read', confidence: 'medium', sheets: sizes.filter((s) => s.louver.has(k)).map((s) => s.sheet.number), basis: `"${k} LOUVER" printed on the plan` });
  // Keyed notes that are scope: our bubble count, to confirm.
  // A note no bubble points at is a general note, not a counted item. The same demolition drawn on the
  // waste plan AND the water plan ("DEMO AND REMOVE EXISTING LAV" on P-1.00 and P-2.00, measured
  // 21 Sep 2026) is one lavatory removed, so notes with the same first sentence merge at the larger count.
  const byItem = new Map<string, TakeoffLine>();
  for (const n of notes) {
    if (!n.bubbles || !SCOPE_NOTE.test(n.text) || NOT_SCOPE.test(n.text)) continue;
    const demo = n.sheet.kind === 'demolition_plan' || /^\s*(DEMO|REMOVE)\b/.test(n.text);
    const first = n.text.split(/(?<=\.)\s+/)[0];
    const key = (demo ? 'demo|' : 'note|') + first.toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();
    const prev = byItem.get(key);
    // Only the SAME note on ANOTHER sheet merges. Measured 22 Sep 2026: on M1.0 notes 7 and 8 share their
    // first sentence ("4"Ø RADIANT TUBE HEATER AIR VENT.") but one ends at a sidewall and one at a roof
    // gooseneck, and notes 1 and 2 are two intakes for two fans; merging them lost an item each.
    if (prev && !prev.sheets.includes(n.sheet.number)) {
      prev.sheets.push(n.sheet.number);
      prev.basis += `; also keyed note ${n.n} on ${n.sheet.number} (${n.bubbles} bubble(s))`;
      if (n.bubbles > (prev.qty || 0)) { prev.qty = n.bubbles; if (prev.qty_status === 'to_confirm') prev.estimate = n.bubbles; }
      continue;
    }
    const line: TakeoffLine = {
      section: demo ? 'Demolition' : 'Keyed notes', type: `note:${n.sheet.number}:${n.n}`, status: demo ? 'demolish' : 'new',
      item: clip(first, 120), description: clip(n.text, 240),
      // An outlined bubble is printed on the drawing, so its count is read, one location per bubble.
      ...(n.outlined
        ? { qty: n.bubbles, unit: 'nos', qty_status: 'read' as const, confidence: 'medium' as const, basis: `keyed note ${n.n} on ${n.sheet.number}; ${n.bubbles} bubble(s) numbered ${n.n} drawn on the sheet, one per location` }
        : { qty: n.bubbles, estimate: n.bubbles, unit: 'nos', qty_status: 'to_confirm' as const, confidence: 'low' as const, basis: `keyed note ${n.n} on ${n.sheet.number}; ${n.bubbles} bubble(s) numbered ${n.n} counted on the sheet — our count, to confirm` }),
      sheets: [n.sheet.number],
    };
    byItem.set(key, line); lines.push(line);
  }
  // Duct and pipe: sizes read, lengths to be measured at the sheet's scale.
  const ductAll = new Map<string, { n: number; sheets: Set<string>; scale: string }>();
  const pipeAll = new Map<string, { n: number; sheets: Set<string>; scale: string; status: Status }>();
  for (const s of sizes) {
    for (const [k, n] of s.duct) { const g = ductAll.get(k) || { n: 0, sheets: new Set(), scale: s.sheet.scale }; g.n += n; g.sheets.add(s.sheet.number); ductAll.set(k, g); }
    for (const [k, v] of s.pipe) { const g = pipeAll.get(k) || { n: 0, sheets: new Set(), scale: s.sheet.scale, status: v.status }; g.n += v.n; g.sheets.add(s.sheet.number); pipeAll.set(k, g); }
  }
  // Lengths measured from the CAD layers replace the "to be measured" lines for what they cover.
  const measuredDuct = measured.some((x) => x.m.kind === 'duct');
  // Each physical run once (enlarged.ts): read what every sheet says of itself and of the others, only when something was measured.
  const words = new Map<number, SheetWords>();
  if (measured.length) pages.forEach((p, i) => words.set(i + 1, sheetWords(p, strips[i], { number: sheets[i].number, title: sheetOf(p, i, strips[i], new Map()).title })));
  const lengthLines = lengthLinesOf(measured, words);
  const agg = new Set(lengthLines.map((l) => l.type));
  lines.push(...lengthLines);
  if (ductAll.size && !measuredDuct) {
    const ks = [...ductAll.keys()].sort((a, b) => a.localeCompare(b, 'en', { numeric: true }));
    const rect = ks.filter((k) => /x/.test(k)), round = ks.filter((k) => /round/.test(k));
    const sc = [...new Set([...ductAll.values()].map((g) => g.scale).filter(Boolean))].join(', ');
    const sh = [...new Set([...ductAll.values()].flatMap((g) => [...g.sheets]))].join(', ');
    if (rect.length) lines.push({ section: 'Ductwork', type: 'duct:rectangular', status: 'new', item: 'Rectangular ductwork', description: `Rectangular ductwork, sizes ${rect.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured from the plan at ${sc || 'the printed scale'}` });
    if (round.length) lines.push({ section: 'Ductwork', type: 'duct:round', status: 'new', item: 'Round ductwork', description: `Round ductwork, sizes ${round.join(', ')}`, qty: null, unit: 'm', confidence: 'low', sheets: sh.split(', '), basis: `sizes printed on ${sh}; lengths are not printed — to be measured at ${sc || 'the printed scale'}` });
  }
  for (const [k, g] of [...pipeAll.entries()].sort()) {
    if (g.status !== 'new' || agg.has('pipe:' + k.split('|')[0])) continue;     // existing pipe is not scope; a measured size has its line
    const [sz, svc] = k.split('|')[0].split(' ');
    lines.push({ section: 'Piping', type: `pipe:${k.split('|')[0]}`, status: 'new', item: `${sz} ${SERVICE[svc] || svc} pipe`, description: `${sz} ${SERVICE[svc] || svc} piping, new`, qty: null, unit: 'm', confidence: 'low', sheets: [...g.sheets], basis: `"${k.split('|')[0]}" labelled ${g.n}x on ${[...g.sheets].join(', ')}; length is not printed — to be measured at ${g.scale || 'the printed scale'}` });
  }
  // Schedule rows that no plan tag matched: OCR-only, so the quantity is ours to confirm.
  const tagged = new Set(lines.map((l) => l.type.replace(/^tag:|^air_device:/, '').split(':')[0].toUpperCase()));
  for (const [tag, spec] of sched) {
    if (tagged.has(tag)) continue;
    const t = parseTag(tag); if (!t && !/^[A-Z]$/.test(tag)) continue;
    lines.push({ section: 'From the schedule (not found on a plan)', type: `sched:${tag}`, status: 'new', item: `${tag} ${t ? nameOf(t.type) : 'air device'}`, description: `${tag} — ${spec}`, qty: 1, estimate: 1, unit: 'nos', qty_status: 'to_confirm', confidence: 'low', sheets: [], basis: 'row of a schedule read by OCR; no plan tag carries it — quantity and model to confirm' });
  }
  return { sheets, lines, strips, dense, coverage };
}

/** Measured runs -> BOQ lines, one per system and size across the set. */
/** The measured runs as BOQ lines, one per size, each physical run once: `words` (enlarged.ts sheetWords, by page) lets an
 *  enlarged plan of an area already measured drop out of the sum, and flags a line that may still include one. */
export function lengthLinesOf(measured: { sheet: Sheet; m: Measured }[], words: Map<number, SheetWords> = new Map()): TakeoffLine[] {
  const out: TakeoffLine[] = [];
  const roles = planRoles(measured, words);
  const agg = new Map<string, { m: Measured; sheets: Set<string>; realIn: number; single: number; notes: Set<string>; flag: boolean }>();
  for (const { sheet, m } of measured) {
    const k = `${m.kind}:${m.key}`;
    const role = roles.get(sheet.page);
    const g = agg.get(k) || { m, sheets: new Set<string>(), realIn: 0, single: 0, notes: new Set<string>(), flag: false };
    if (role?.why) g.notes.add(role.why);
    if (role?.flag) g.flag = true;
    agg.set(k, g);
    if (role && !role.counted) continue;                                         // an enlargement of an area already summed
    g.realIn += m.realIn; g.single += m.single || 0; g.sheets.add(sheet.number);
  }
  for (const [k, g] of [...agg.entries()].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))) {
    const m = g.m, sh = [...g.sheets], qty = metres(g.realIn);
    if (qty < 0.3) continue;                                                    // under a foot: a fitting edge, not a run
    const layers = [...m.layers].join(', ');
    const where = `measured along layer ${layers} on ${sh.join(', ')} at ${m.scale}: ${feet(g.realIn)} ft (${qty} m) in plan; risers and drops are not in plan and are not included`;
    if (m.kind === 'pipe') {
      const [sz, svc] = m.labelled ? m.key.split(' ') : ['', m.svc];
      const what = `${sz ? sz + ' ' : ''}${SERVICE[svc] || svc} pipe`;
      out.push(once({ section: 'Piping', section_ar: 'الأنابيب', type: `pipe:${m.key}`, status: 'new', item: what, description: `${what}, new${m.labelled ? '' : ' (size not labelled on the plan)'}`,
        description_ar: `أنابيب ${SERVICE_AR[svc] || svc}${sz ? ' مقاس ' + sz : ''}، جديدة${m.labelled ? '' : ' (المقاس غير مكتوب على المخطط)'}`,
        qty, unit: 'm', ...(m.labelled ? { qty_status: 'read' as const, confidence: 'medium' as const } : { estimate: qty, qty_status: 'to_confirm' as const, confidence: 'low' as const }), sheets: sh, basis: where }, g));
    } else {
      // A duct stretch is 'read' when both walls are drawn and the gap matches a printed size; a
      // single-line run takes its size from the nearest label, so that length is ours to confirm.
      const sure = m.labelled && g.single === 0;
      const what = m.labelled ? (/round/.test(m.key) ? `Round ductwork ${m.key.replace(' round', ' dia')}` : `Rectangular ductwork ${m.key}`) : `Ductwork, ${m.key}`;
      const whatAr = m.labelled ? (/round/.test(m.key) ? `مجاري هواء دائرية قطر ${m.key.replace(' round', '')}` : `مجاري هواء مستطيلة ${m.key.replace(' (1" liner)', ' (بطانة 1 إنش)')}`) : `مجاري هواء، ${m.key.replace(' wide (size not labelled)', ' عرض (المقاس غير مكتوب)').replace('single-line duct (size not labelled)', 'خط مفرد (المقاس غير مكتوب)')}`;
      out.push(once({ section: 'Ductwork', section_ar: 'مجاري الهواء', type: `duct:${m.key}`, status: 'new', item: what, description: what, description_ar: whatAr, qty, unit: 'm',
        ...(sure ? { qty_status: 'read' as const, confidence: 'medium' as const } : { estimate: qty, qty_status: 'to_confirm' as const, confidence: 'low' as const }), sheets: sh,
        basis: `${where}${g.single ? `; ${feet(g.single)} ft of it is drawn single-line and sized from the nearest label — to confirm` : ''}${m.labelled ? '' : '; no printed size matches this width — to confirm'}` }, g));
    }
  }
  return out;
}


/** A length line with what the enlarged-plan reading found (enlarged.ts): a sheet not counted again is named in the basis;
 *  a line that may still include an enlarged plan says so in its description, EN and AR, and is open (to confirm). */
function once(l: TakeoffLine, g: { notes: Set<string>; flag: boolean }): TakeoffLine {
  if (!g.notes.size) return l;
  const basis = `${l.basis}; ${[...g.notes].join('; ')}`;
  if (!g.flag) return { ...l, basis };
  return { ...l, basis, description: `${l.description} — ${LENGTH_MAY_INCLUDE_ENLARGED}`, ...(l.description_ar ? { description_ar: `${l.description_ar} — ${LENGTH_MAY_INCLUDE_ENLARGED_AR}` } : {}),
    estimate: l.qty, qty_status: 'to_confirm', confidence: 'low' };
}

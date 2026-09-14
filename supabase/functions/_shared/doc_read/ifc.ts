// ifc — element counts and model-stated quantities read off an IFC STEP file, with no BIM kernel (14 Sep 2026).
//
// WHY. IFC is the open BIM exchange format (ISO 16739, carried as ISO 10303-21 STEP text). Consultants
// in the UAE hand over Revit/ArchiCAD models as IFC. A model already states how many doors of each type
// sit on each storey and, when exported with base quantities, each wall's NetSideArea and each slab's
// NetVolume. Reading those statements is plain text parsing; before this reader an .ifc was stored unread.
//
// WHAT IT READS. The DATA section, tokenised in full: strings ('' escapes, \X2\..\X0\ UTF-16, \X\hh,
// \S\ encodings decoded), nested lists, $, *, .ENUM., typed values, comments, multi-line instances.
// Then: building elements counted per class, per type (IfcRelDefinesByType -> type Name, else the
// element's ObjectType) and per storey (IfcRelContainedInSpatialStructure, following IfcRelAggregates
// up to the storey for nested parts and spaces). IfcElementQuantity sets linked by
// IfcRelDefinesByProperties give IfcQuantityLength/Area/Volume/Count/Weight values (attribute 3),
// converted through IfcUnitAssignment (SI prefixes and conversion-based units) to m, sqm, m3, kg, nos,
// summed per storey / class / type / quantity name. Confidence 'medium': the model states them.
//
// WHAT IT NEVER DOES. It does not evaluate geometry. A model exported without base quantities yields
// counts but no areas or volumes, and the notes say so. It does not read property sets' prices or
// costs (IfcCostItem is not an element). Identity is NOT scrubbed here; the caller does that.
import { capText, empty, LIMITS, ok, refuse, type Qty, type ReadContext, type ReadResult } from './types.ts';

/** 2,000,000 instances is a large hospital model; past it the reader stops and says so. */
export const IFC_MAX_ENTITIES = 2_000_000;

export type StepValue = string | number | null | { r: number } | { e: string } | { t: string; v: StepValue } | StepValue[];
type Inst = { t: string; a: StepValue[] };

// Element classes counted (upper-case STEP name -> display name). Spatial and relationship
// instances are not elements; openings are voids, not built work.
const ELEMENTS = Object.fromEntries([
  'IfcWall', 'IfcWallStandardCase', 'IfcWallElementedCase', 'IfcCurtainWall', 'IfcSlab', 'IfcSlabStandardCase',
  'IfcSlabElementedCase', 'IfcRoof', 'IfcDoor', 'IfcDoorStandardCase', 'IfcWindow', 'IfcWindowStandardCase',
  'IfcColumn', 'IfcColumnStandardCase', 'IfcBeam', 'IfcBeamStandardCase', 'IfcMember', 'IfcMemberStandardCase',
  'IfcPlate', 'IfcPlateStandardCase', 'IfcStair', 'IfcStairFlight', 'IfcRamp', 'IfcRampFlight', 'IfcRailing',
  'IfcCovering', 'IfcFooting', 'IfcPile', 'IfcChimney', 'IfcShadingDevice', 'IfcBuildingElementProxy',
  'IfcBuildingElementPart', 'IfcElementAssembly', 'IfcSpace', 'IfcFurnishingElement', 'IfcFurniture',
  'IfcSystemFurnitureElement', 'IfcPipeSegment', 'IfcPipeFitting', 'IfcDuctSegment', 'IfcDuctFitting',
  'IfcCableSegment', 'IfcCableCarrierSegment', 'IfcCableCarrierFitting', 'IfcFlowSegment', 'IfcFlowFitting',
  'IfcFlowTerminal', 'IfcFlowController', 'IfcFlowMovingDevice', 'IfcEnergyConversionDevice', 'IfcAirTerminal',
  'IfcSanitaryTerminal', 'IfcLightFixture', 'IfcLamp', 'IfcOutlet', 'IfcSwitchingDevice', 'IfcValve', 'IfcPump',
  'IfcFan', 'IfcBoiler', 'IfcChiller', 'IfcUnitaryEquipment', 'IfcFireSuppressionTerminal', 'IfcTransportElement',
  'IfcReinforcingBar', 'IfcReinforcingMesh', 'IfcTendon', 'IfcDiscreteAccessory', 'IfcMechanicalFastener',
].map((n) => [n.toUpperCase(), n]));

const PREFIX: Record<string, number> = {
  EXA: 1e18, PETA: 1e15, TERA: 1e12, GIGA: 1e9, MEGA: 1e6, KILO: 1e3, HECTO: 1e2, DECA: 1e1,
  DECI: 1e-1, CENTI: 1e-2, MILLI: 1e-3, MICRO: 1e-6, NANO: 1e-9, PICO: 1e-12,
};

/** STEP string escapes (ISO 10303-21 §6.4.3). */
export function decodeStepString(s: string): string {
  return s
    .replace(/\\X2\\((?:[0-9A-Fa-f]{4})*)\\X0\\/g, (_m, h: string) => String.fromCharCode(...(h.match(/.{4}/g) ?? []).map((x) => parseInt(x, 16))))
    .replace(/\\X4\\((?:[0-9A-Fa-f]{8})*)\\X0\\/g, (_m, h: string) => String.fromCodePoint(...(h.match(/.{8}/g) ?? []).map((x) => parseInt(x, 16))))
    .replace(/\\X\\([0-9A-Fa-f]{2})/g, (_m, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\S\\(.)/g, (_m, c: string) => String.fromCharCode(c.charCodeAt(0) + 128))
    .replace(/\\P[A-I]\\/g, '')
    .replace(/\\\\/g, '\\');
}

/** Tokenise DATA-section instances. Malformed instances are skipped to the next ';' and counted. */
export function parseStepData(src: string, maxEntities = IFC_MAX_ENTITIES): { insts: Map<number, Inst>; bad: number; capped: boolean } {
  const insts = new Map<number, Inst>();
  const start = src.search(/\bDATA\s*;/);
  let i = start < 0 ? src.length : src.indexOf(';', start) + 1;
  const n = src.length;
  let bad = 0, capped = false;
  const ws = () => {
    for (;;) {
      while (i < n && /\s/.test(src[i])) i++;
      if (src.startsWith('/*', i)) { const e = src.indexOf('*/', i + 2); i = e < 0 ? n : e + 2; } else return;
    }
  };
  const fail = (): never => { throw new Error('step_syntax'); };
  const value = (): StepValue => {
    ws();
    const c = src[i];
    if (c === "'") {
      let s = ''; i++;
      for (;;) {
        const q = src.indexOf("'", i);
        if (q < 0) fail();
        s += src.slice(i, q); i = q + 1;
        if (src[i] === "'") { s += "'"; i++; } else break;
      }
      return decodeStepString(s);
    }
    if (c === '(') {
      i++; const out: StepValue[] = []; ws();
      if (src[i] === ')') { i++; return out; }
      for (;;) { out.push(value()); ws(); if (src[i] === ',') { i++; continue; } if (src[i] === ')') { i++; return out; } fail(); }
    }
    if (c === '#') { const m = /^#(\d+)/.exec(src.slice(i, i + 24)) ?? fail(); i += m[0].length; return { r: +m[1] }; }
    if (c === '$' || c === '*') { i++; return null; }
    if (c === '.') { const e = src.indexOf('.', i + 1); if (e < 0) fail(); const v = src.slice(i + 1, e); i = e + 1; return { e: v }; }
    if (c === '"') { const e = src.indexOf('"', i + 1); if (e < 0) fail(); const v = src.slice(i + 1, e); i = e + 1; return v; } // binary
    const num = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(src.slice(i, i + 64));
    if (num) { i += num[0].length; return parseFloat(num[0]); }
    const kw = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i, i + 128));
    if (kw) { i += kw[0].length; ws(); if (src[i] !== '(') fail(); i++; const v = value(); ws(); if (src[i] !== ')') fail(); i++; return { t: kw[0].toUpperCase(), v }; }
    return fail();
  };
  while (i < n) {
    ws();
    if (i >= n || src.startsWith('ENDSEC', i)) break;
    const at = i;
    try {
      const m = /^#(\d+)\s*=\s*/.exec(src.slice(i, i + 40)) ?? fail();
      i += m[0].length;
      if (src[i] === '(') { value(); ws(); if (src[i] !== ';') fail(); i++; continue; } // complex instance: not an element we count
      const kw = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i, i + 128)) ?? fail();
      i += kw[0].length; ws();
      if (src[i] !== '(') fail();
      const a = value() as StepValue[]; ws();
      if (src[i] !== ';') fail();
      i++;
      if (insts.size >= maxEntities) { capped = true; break; }
      insts.set(+m[1], { t: kw[0].toUpperCase(), a });
    } catch {
      bad++;
      const e = src.indexOf(';', at + 1);
      i = e < 0 ? n : e + 1;
    }
  }
  return { insts, bad, capped };
}

const SEP = '\u0001'; // key separator: a control character cannot occur in a storey, class or type name
const ref = (v: StepValue | undefined) => (v && typeof v === 'object' && 'r' in v ? v.r : null);
const refs = (v: StepValue | undefined) => (Array.isArray(v) ? v.map(ref).filter((x): x is number => x != null) : []);
const str = (v: StepValue | undefined) => (typeof v === 'string' ? v : '');
const enm = (v: StepValue | undefined) => (v && typeof v === 'object' && 'e' in v ? v.e : '');
const numOf = (v: StepValue | undefined): number | null =>
  typeof v === 'number' ? v : v && typeof v === 'object' && 't' in v ? numOf(v.v) : null;

export async function readIfc(bytes: Uint8Array, _ctx: ReadContext, maxEntities = IFC_MAX_ENTITIES): Promise<ReadResult> {
  const src = new TextDecoder('utf-8').decode(bytes);
  if (!/ISO-10303-21\s*;/.test(src.slice(0, 1024))) return refuse('ifc_unreadable', 'Not an ISO-10303-21 STEP file (missing header).');
  if (!/\bDATA\s*;/.test(src)) return refuse('ifc_unreadable', 'STEP file has no DATA section.');
  const schema = /FILE_SCHEMA\s*\(\s*\(\s*'([^']*)'/i.exec(src.slice(0, 8192))?.[1] ?? 'unknown';
  const { insts, bad, capped } = parseStepData(src, maxEntities);
  if (!insts.size) return refuse('ifc_unreadable', `No readable instances in the DATA section (${bad} malformed).`);

  // Units: unit type -> factor to m / sqm / m3 / kg.
  const siFactor = (id: number | null): number | null => {
    const u = id != null ? insts.get(id) : undefined;
    if (!u) return null;
    if (u.t === 'IFCSIUNIT') {
      const p = PREFIX[enm(u.a[2])] ?? 1, name = enm(u.a[3]);
      if (name === 'METRE') return p;
      if (name === 'SQUARE_METRE') return p * p;
      if (name === 'CUBIC_METRE') return p * p * p;
      if (name === 'GRAM') return p / 1000;
      return p;
    }
    if (u.t === 'IFCCONVERSIONBASEDUNIT' || u.t === 'IFCCONVERSIONBASEDUNITWITHOFFSET') {
      const mw = insts.get(ref(u.a[3]) ?? -1);
      const v = mw ? numOf(mw.a[0]) : null, base = mw ? siFactor(ref(mw.a[1])) : null;
      return v != null && base != null ? v * base : null;
    }
    return null;
  };
  const unitFor: Record<string, number> = { LENGTHUNIT: 1, AREAUNIT: 1, VOLUMEUNIT: 1, MASSUNIT: 1 };
  const unitNote: string[] = [];
  for (const [, x] of insts) {
    if (x.t !== 'IFCUNITASSIGNMENT') continue;
    for (const id of refs(x.a[0])) {
      const u = insts.get(id), type = u ? enm(u.a[1]) : '';
      const f = siFactor(id);
      if (type in unitFor && f != null) { unitFor[type] = f; unitNote.push(`${type.replace('UNIT', '').toLowerCase()} x${+f.toPrecision(6)}`); }
    }
    break;
  }

  const names: Record<number, string> = {}; // element id -> class display
  for (const [id, x] of insts) if (ELEMENTS[x.t]) names[id] = ELEMENTS[x.t];

  const typeOf = new Map<number, string>(), storeyOf = new Map<number, number>(), parent = new Map<number, number>();
  const qsets: [number[], number][] = [];
  const text: string[] = [], used = { n: 0 };
  const addText = (s: string) => { const t = s.trim(); if (t) capText(text, t + '\n', used); };
  const storeys = new Map<number, string>();
  for (const [id, x] of insts) {
    switch (x.t) {
      case 'IFCPROJECT': addText(str(x.a[2])); addText(str(x.a[5])); break;
      case 'IFCBUILDINGSTOREY': storeys.set(id, str(x.a[2]) || str(x.a[7]) || `storey #${id}`); break;
      case 'IFCRELDEFINESBYTYPE': {
        const t = insts.get(ref(x.a[5]) ?? -1), nm = t ? str(t.a[2]) : '';
        if (nm) for (const o of refs(x.a[4])) typeOf.set(o, nm);
        break;
      }
      case 'IFCRELCONTAINEDINSPATIALSTRUCTURE': { const s = ref(x.a[5]); if (s != null) for (const o of refs(x.a[4])) storeyOf.set(o, s); break; }
      case 'IFCRELAGGREGATES': case 'IFCRELNESTS': { const p = ref(x.a[4]); if (p != null) for (const o of refs(x.a[5])) parent.set(o, p); break; }
      case 'IFCRELDEFINESBYPROPERTIES': { const d = ref(x.a[5]); if (d != null && insts.get(d)?.t === 'IFCELEMENTQUANTITY') qsets.push([refs(x.a[4]), d]); break; }
    }
  }
  for (const s of storeys.values()) addText(s);
  const storeyName = (id: number): string => {
    for (let cur: number | undefined = id, hop = 0; cur != null && hop < 8; cur = parent.get(cur), hop++) {
      if (storeys.has(cur)) return storeys.get(cur)!;
      const s = storeyOf.get(cur);
      if (s != null) return storeys.get(s) ?? '(no storey)';
    }
    return '(no storey)';
  };
  const typeName = (id: number) => typeOf.get(id) || str(insts.get(id)!.a[4]) || '(untyped)';

  // Counts.
  type Agg = { v: number; n: number };
  const counts = new Map<string, Agg>(), sums = new Map<string, Agg & { unit: string }>();
  for (const k of Object.keys(names)) {
    const id = +k, key = [storeyName(id), names[id], typeName(id)].join(SEP);
    const a = counts.get(key) ?? { v: 0, n: 0 }; a.v++; counts.set(key, a);
  }
  const typeNames = new Set<string>();
  for (const k of counts.keys()) typeNames.add(k.split(SEP)[2]);
  for (const t of typeNames) if (t !== '(untyped)') addText(t);
  for (const [, x] of insts) if (x.t === 'IFCSPACE') { addText(str(x.a[2])); addText(str(x.a[7])); }

  // Quantities: one value per element per quantity name (exporters often repeat a name in two sets).
  const QK: Record<string, [string, string]> = {
    IFCQUANTITYLENGTH: ['LENGTHUNIT', 'm'], IFCQUANTITYAREA: ['AREAUNIT', 'sqm'], IFCQUANTITYVOLUME: ['VOLUMEUNIT', 'm3'],
    IFCQUANTITYWEIGHT: ['MASSUNIT', 'kg'], IFCQUANTITYCOUNT: ['', 'nos'],
  };
  const seen = new Set<string>();
  for (const [objs, qs] of qsets) {
    const set = insts.get(qs)!;
    for (const obj of objs) {
      if (!names[obj]) continue;
      for (const qid of refs(set.a[5])) {
        const qi = insts.get(qid), kind = qi && QK[qi.t];
        if (!qi || !kind) continue;
        const qname = str(qi.a[0]), raw = numOf(qi.a[3]);
        if (!qname || raw == null || seen.has(`${obj}${SEP}${qname}`)) continue;
        seen.add(`${obj}${SEP}${qname}`);
        const own = siFactor(ref(qi.a[2]));
        const f = own ?? (kind[0] ? unitFor[kind[0]] : 1);
        const key = [storeyName(obj), names[obj], typeName(obj), qname].join(SEP);
        const a = sums.get(key) ?? { v: 0, n: 0, unit: kind[1] }; a.v += raw * f; a.n++; sums.set(key, a);
      }
    }
  }

  const quantities: Qty[] = [];
  const sorted = <T,>(m: Map<string, T>) => [...m].sort((a, b) => a[0].localeCompare(b[0]));
  for (const [k, a] of sorted(counts)) {
    const [st, cls, ty] = k.split(SEP);
    quantities.push({ section: st, description: `${cls} · ${ty}`, qty: a.v, unit: 'nos', basis: `${a.v} ${cls} instances in the model`, confidence: 'medium' });
  }
  for (const [k, a] of sorted(sums)) {
    const [st, cls, ty, qn] = k.split(SEP);
    quantities.push({ section: st, description: `${cls} · ${ty} · ${qn}`, qty: +a.v.toFixed(3), unit: a.unit, basis: `IfcElementQuantity ${qn} summed over ${a.n} elements`, confidence: 'medium' });
  }

  const notes: string[] = [`IFC schema ${schema}; ${insts.size} instances read${unitNote.length ? `; units ${unitNote.join(', ')}` : ''}.`];
  if (quantities.length > LIMITS.maxQuantities) {
    notes.push(`${quantities.length} quantities found; the first ${LIMITS.maxQuantities} are kept.`);
    quantities.length = LIMITS.maxQuantities;
  }
  if (!Object.keys(names).length) notes.push('The model contains no building elements this reader counts.');
  else if (!sums.size) notes.push('The model states no IfcElementQuantity (exported without base quantities): element counts only; areas and volumes would need its geometry measured.');
  if (bad) notes.push(`${bad} malformed instances were skipped.`);
  if (capped) notes.push(`The model has more than ${maxEntities} instances; reading stopped there, so counts are partial.`);
  return ok({ ...empty('ifc', notes), text: text.join('').trimEnd(), quantities });
}

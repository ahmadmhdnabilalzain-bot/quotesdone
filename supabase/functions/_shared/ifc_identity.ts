// ifc_identity — what an IFC model says about its own job and its authors (23 Sep 2026, sales_engineer).
// Read by drawing_identity_gate so none of it reaches a supplier's BOQ. See that file for what was
// measured. An IFC names its parties in fixed places (ISO 16739):
//   HEADER FILE_NAME        author list and organisation list (arguments 3 and 4)
//   IfcProject / IfcSite / IfcBuilding   Name, Description, LongName (the job as the consultant named it)
//   IfcPerson, IfcOrganization, IfcActorRole, IfcPostalAddress, IfcTelecomAddress (every string: names,
//   ids, address lines, phones, e-mails, web addresses)
// A storey or a type is NOT a source of terms (its name is usually "Level 1" / "Basic Wall 200mm"), but it
// IS scanned by the gate, so a storey named after the project is caught by the project's own terms.
import { parseStepData, decodeStepString, type StepValue } from './doc_read/ifc.ts';

const PARTY = new Set(['IFCPERSON', 'IFCORGANIZATION', 'IFCACTORROLE', 'IFCPOSTALADDRESS', 'IFCTELECOMADDRESS', 'IFCPERSONANDORGANIZATION']);
const PLACE = new Set(['IFCPROJECT', 'IFCSITE', 'IFCBUILDING']);
// Words an IfcSite / IfcBuilding is routinely called by exporters; never a seed.
const GENERIC = /^(?:default|site|building|project|my\s+project|unnamed|project\s+name|level\s*\d*|\$|n\/?a)$/i;

const strings = (v: StepValue | undefined, out: string[]): string[] => {
  if (typeof v === 'string') out.push(v);
  else if (Array.isArray(v)) v.forEach((x) => strings(x, out));
  else if (v && typeof v === 'object' && 't' in v) strings((v as { v: StepValue }).v, out);
  return out;
};

/** Every identity term an IFC (STEP text) states. Non-IFC input returns []. */
export function ifcIdentityTerms(src: string): string[] {
  const s = String(src || '');
  if (!/ISO-10303-21\s*;/.test(s.slice(0, 1024))) return [];
  const out = new Set<string>();
  const add = (v: string) => { const t = v.replace(/\s+/g, ' ').trim(); if (t.length >= 3 && !GENERIC.test(t)) out.add(t); };
  // FILE_NAME(name, time_stamp, (author...), (organization...), preprocessor, originating_system, authorization)
  const fn = /FILE_NAME\s*\(([\s\S]*?)\)\s*;/i.exec(s.slice(0, 16384))?.[1] ?? '';
  const groups = fn.match(/\(([^()]*)\)/g) ?? [];
  for (const g of groups.slice(0, 2)) for (const m of g.matchAll(/'((?:[^']|'')*)'/g)) add(decodeStepString(m[1].replace(/''/g, "'")));
  const auth = [...fn.matchAll(/'((?:[^']|'')*)'/g)].pop()?.[1];
  if (auth) add(decodeStepString(auth.replace(/''/g, "'")));
  const { insts } = parseStepData(s);
  for (const [, x] of insts) {
    if (PARTY.has(x.t)) strings(x.a, []).forEach(add);
    else if (PLACE.has(x.t)) {
      // Name (2), Description (3), LongName (5 for IfcProject, 7 for IfcSite / IfcBuilding)
      for (const i of x.t === 'IFCPROJECT' ? [2, 3, 5] : [2, 3, 7]) strings(x.a[i], []).forEach(add);
    }
  }
  return [...out];
}

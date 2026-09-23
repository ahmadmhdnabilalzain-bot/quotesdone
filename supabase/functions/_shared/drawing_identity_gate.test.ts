// drawing_identity_gate — synthetic ZZ DEMO drawings only (never a customer file). Each test is the case
// the gate exists for. Measured: with the re-read removed (every line kept, rest not scanned) tests 2 and 3 fail;
// with the IFC terms removed test 4 fails. Test 1 is a regression: the DXF reader already cuts the contact
// text out of its lines, so the gate must not cost a quantity there.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from './doc_read/index.ts';
import { boqFromExtracted } from '../drawing_boq/boq_from_document.ts';
import { IFC_FIXTURE_TEXT } from './doc_read/ifc.fixtures.ts';
import { dxfFrom, dxfSection } from './doc_read/cad.fixtures.ts';
import { consultantDxf } from './cad_identity.test.ts';
import { drawingIdentityTerms, gateDrawingBoq, labelTerms, residualIdentity } from './drawing_identity_gate.ts';
import { ifcIdentityTerms } from './ifc_identity.ts';
import { dxfTextOf } from './cad_identity.ts';

const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const PARTY = ['ORBIT', 'HARBOUR', 'KEYSTONE', 'zz.drafter', 'REEM', '000 0012', '0000012', 'orbit.example', 'ZZ-L-4471', 'ZZ-4471'];
const leaks = (v: unknown) => { const t = JSON.stringify(v ?? '').toUpperCase(); return PARTY.filter((x) => t.includes(x.toUpperCase())); };

async function served(bytes: Uint8Array, name: string, mime: string, raw: string) {
  const r: any = await readDocument(bytes, name, mime);
  assert(r.ok, JSON.stringify(r));
  const boq = boqFromExtracted(r, '');
  return { r, g: gateDrawingBoq(boq, drawingIdentityTerms(r.kind, raw, r.dxf_text), r.dxf_text !== undefined) };
}

Deno.test('1. DXF (regression): through the gate every quantity survives and no party is served', async () => {
  const base = new TextDecoder().decode(consultantDxf()).replace(/0\r?\nEOF\s*$/, '');
  const extra = new TextDecoder().decode(dxfFrom([...dxfSection('ENTITIES', [
    [0, 'MTEXT'], [8, 'M-ANNO'], [10, 0], [20, -1100], [40, 100], [1, 'CONTACT +971 50 000 0012 zz@orbit.example.invalid TRADE LICENCE NO: ZZ-L-4471'],
  ]), [0, 'EOF']]));
  // Two ENTITIES sections read as one drawing by the DXF reader; the second carries only the contact MTEXT.
  const bytes = new TextEncoder().encode(base + extra);
  const { g } = await served(bytes, 'plan.dxf', 'image/vnd.dxf', '');
  assert(g.boq, 'the take-off is not withheld for one dirty note');
  assertEquals(leaks(g.boq), [], 'identity reached the supplier-facing take-off');
  const q = (re: RegExp) => ((g.boq as any).boq as any[]).filter((l) => re.test(l.description)).map((l) => l.qty);
  assertEquals(q(/FCU/), [24]);
  assertEquals(q(/EXHAUST FANS/), [6]);
  assertEquals(residualIdentity(g.boq, []), []);
});

Deno.test('2. the re-read catches what redaction missed: a term glued inside a word withholds the take-off', () => {
  const boq = { summary: 'Sheet set issued by ZZORBITENG', boq: [{ section: 'A', description: 'Wall', qty: 3, unit: 'm', basis: 'x' }], missing_info: [] };
  const g = gateDrawingBoq(boq, ['ZZ ORBIT']);
  assertEquals(g.boq, null, 'identity left outside the lines must withhold the whole take-off');
  assert(!g.clean && g.found.some((f) => /ORBIT/i.test(f)), JSON.stringify(g.found));
});

Deno.test('3. a line that still names a party after redaction is dropped, and the customer is told', () => {
  const boq = { boq: [
    { section: 'A', description: 'Supply ducting to ZZORBITENG detail', qty: 5, unit: 'm', basis: 'x' },
    { section: 'A', description: 'Supply diffusers', qty: 12, unit: 'nos', basis: 'y' },
  ], missing_info: [] };
  const g = gateDrawingBoq(boq, ['ZZ ORBIT']) as any;
  assertEquals(g.dropped_lines, 1);
  assertEquals(g.boq.boq.map((l: any) => l.qty), [12]);
  assert(/withheld/.test(g.boq.missing_info.at(-1)));
});

const ifcWithParties = () => IFC_FIXTURE_TEXT
  .replace("FILE_NAME('zz-demo.ifc','2026-09-14T00:00:00',('ZZ DEMO'),('ZZ DEMO')", "FILE_NAME('zz-demo.ifc','2026-09-14T00:00:00',('ZZ Reem Kassab'),('ZZ Keystone Architects')")
  .replace("'ZZ DEMO Villa',$,$,'ZZ DEMO Villa, Architect''s issue'", "'ZZ HARBOUR TOWER',$,$,'ZZ HARBOUR TOWER for ZZ Orbit Holdings'")
  .replace("'Level 1'", "'ZZ HARBOUR TOWER L1'")
  .replace('#10=IFCUNITASSIGNMENT', "#900=IFCPERSON($,'Kassab','ZZ Reem',$,$,$,$,(#902));\n#901=IFCORGANIZATION($,'ZZ Orbit Consulting',$,$,(#902));\n#902=IFCTELECOMADDRESS(.OFFICE.,$,$,('+971 50 000 0012'),$,$,('zz@orbit.example.invalid'),$,$);\n#10=IFCUNITASSIGNMENT");

Deno.test('4. IFC: project, storey, person, organisation, phone and e-mail stay out; the quantities stay in', async () => {
  const src = ifcWithParties();
  const terms = ifcIdentityTerms(src);
  for (const t of ['ZZ HARBOUR TOWER', 'ZZ Orbit Consulting', 'Kassab', '+971 50 000 0012', 'zz@orbit.example.invalid', 'ZZ Keystone Architects']) assert(terms.includes(t), `term missing: ${t} in ${JSON.stringify(terms)}`);
  const { g } = await served(new TextEncoder().encode(src), 'model.ifc', 'application/x-step', src);
  assert(g.boq, JSON.stringify(g));
  assertEquals(leaks(g.boq), [], 'identity reached the supplier-facing take-off');
  const walls = ((g.boq as any).boq as any[]).filter((l) => /Length/.test(l.description)).map((l) => l.qty);
  assertEquals(walls, [9]);
});

Deno.test('5. IFC without the gate WOULD have leaked the storey name (the case this file fixes)', async () => {
  const src = ifcWithParties();
  const r: any = await readDocument(new TextEncoder().encode(src), 'model.ifc', 'application/x-step');
  assert(JSON.stringify(boqFromExtracted(r, '')).includes('HARBOUR'));
});

Deno.test('6. label values from a PDF text layer become terms; plain content does not', () => {
  assertEquals(labelTerms('GROUND FLOOR PLAN\nClient: ZZ Orbit Holdings\nScale 1:100\nالمالك: زد زد ريم'), ['ZZ Orbit Holdings', 'زد زد ريم']);
  assertEquals(dxfTextOf(''), '');
});

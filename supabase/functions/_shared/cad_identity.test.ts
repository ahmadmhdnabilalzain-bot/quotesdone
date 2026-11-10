// cad_identity.test.ts — a CAD file's take-off reaches a supplier with none of the file's own names.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/cad_identity.test.ts
//
// Replays the measurement of 22 Sep 2026 (header of cad_identity.ts) through the production chain:
// doc_read (the DXF reader) -> boqFromExtracted (drawing_boq 'document' mode) -> cadSupplierBoq
// (customer_api) -> create_inquiry's redactBoq -> the supplier inbox's inboxBoq. Before the fix the
// consultant fixture served six identity strings and the repo's own title-block fixture served one.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from './doc_read/index.ts';
import { boqFromExtracted } from '../drawing_boq/boq_from_document.ts';
import { redactBoq, seedTerms } from './anonymise.ts';
import { inboxBoq } from '../supplier_api/identity_scrub.ts';
import { dxfFrom, dxfSection, dxfTitleBlockFixture } from './doc_read/cad.fixtures.ts';
import { cadIdentityTerms, cadSupplierBoq, dxfTextOf, neutralCadName, neutraliseCadLines } from './cad_identity.ts';

// The customer is NOT the consultant: the title block names the firm that drew it and the project.
const CUSTOMER = { name: 'ZZ DEMO Rashid Kareem', email: 'rashid@example.invalid', phone: '+971500000017' };
const seeds = seedTerms({ name: CUSTOMER.name, email: CUSTOMER.email, phone: CUSTOMER.phone, extra: ['drawing.dxf'] });
const line = (layer: string, x1: number, y1: number, x2: number, y2: number): [number, string | number][] =>
  [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const ins = (b: string, x: number): [number, string | number][] => [[0, 'INSERT'], [8, 'M-EQPM'], [2, b], [10, x], [20, 0], [30, 0]];
export function consultantDxf(): Uint8Array {
  return dxfFrom([
    ...dxfSection('HEADER', [[9, '$ACADVER'], [1, 'AC1027'], [9, '$PROJECTNAME'], [1, 'ZZ HARBOUR TOWER'], [9, '$LASTSAVEDBY'], [1, 'zz.drafter'], [9, '$INSUNITS'], [70, 4]]),
    ...dxfSection('BLOCKS', [[0, 'BLOCK'], [8, '0'], [2, 'KEYSTONE_TITLEBLOCK_A1'], [70, 0], [10, 0], [20, 0], [30, 0],
      [0, 'TEXT'], [8, '0'], [10, 0], [20, 0], [40, 100], [1, 'ZZ ORBIT CONSULTING ENGINEERS'], [0, 'ENDBLK']]),
    ...dxfSection('ENTITIES', [
      ...line('ZZORBIT-M-DUCT', 0, 0, 12000, 0), ...line('ZZORBIT-M-DUCT', 0, 500, 12000, 500),
      ...ins('SMOKE_DET', 100), ...ins('SMOKE_DET', 200), ...ins('ORBITENG_LOGO', 0),
      [0, 'INSERT'], [8, 'TITLE'], [2, 'KEYSTONE_TITLEBLOCK_A1'], [66, 1], [10, 0], [20, 0],
      [0, 'ATTRIB'], [8, 'TITLE'], [10, 0], [20, -600], [40, 100], [1, 'ZZ HARBOUR TOWER'], [2, 'PROJ_NAME'],
      [0, 'ATTRIB'], [8, 'TITLE'], [10, 0], [20, -800], [40, 100], [1, 'ZZ-M-101'], [2, 'DWG_NO'],
      [0, 'SEQEND'], [8, 'TITLE'],
      [0, 'TEXT'], [8, 'A-ANNO'], [10, 0], [20, -700], [40, 100], [1, 'ZZ HARBOUR TOWER - 24 NOS FCU'],
      [0, 'MTEXT'], [8, 'M-ANNO'], [10, 0], [20, -900], [40, 100], [1, 'SUPPLY 12 NOS DIFFUSERS AS PER ZZ ORBIT CONSULTING ENGINEERS SPEC\\P6 NOS EXHAUST FANS'],
    ]),
    [0, 'EOF'],
  ]);
}
const IDENTITY = ['ORBIT', 'HARBOUR', 'KEYSTONE', 'ORBITENG', 'ZZORBIT', 'zz.drafter', 'MANSOORI'];
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));

async function served(bytes: Uint8Array, scrub: boolean) {
  const r = await readDocument(bytes, 'drawing.dxf', 'image/vnd.dxf');
  let boq: any = boqFromExtracted(r as any, '');
  if (scrub) boq = cadSupplierBoq(boq, dxfTextOf(b64(bytes)));   // customer_api, after drawing_boq answers
  const gate = redactBoq(boq, seeds);                               // create_inquiry
  const inbox = inboxBoq(gate.held ? null : gate.boq, CUSTOMER.name, seeds, []);   // supplier_api inbox
  return { gate, inbox, text: JSON.stringify(inbox.boq ?? '').toUpperCase() };
}
const leaks = (text: string) => IDENTITY.filter((x) => text.includes(x.toUpperCase()));
const qty = (b: any, re: RegExp) => (b?.boq || []).filter((l: any) => re.test(String(l.description))).map((l: any) => l.qty);

Deno.test('the consultant title block: no name reaches the supplier, every quantity does', async () => {
  const { inbox, text } = await served(consultantDxf(), true);
  assertEquals(inbox.withheld, false);
  assertEquals(leaks(text), [], 'identity served to the supplier');
  const b = inbox.boq as any;
  assertEquals(qty(b, /FCU/), [24]);
  assertEquals(qty(b, /DIFFUSERS/), [12]);
  assertEquals(qty(b, /EXHAUST FANS/), [6]);
  // 10 Nov 2026 (drawing_boq/linear_services.ts): the two walls of one duct, 12 m long and 500 apart, are ONE 12 m duct
  // along its centreline, no longer 24 m of "linework on layer M-DUCT"; its layer name is still served neutralised.
  assertEquals(qty(b, /^Duct 500 mm wide \(size not labelled\)$/), [12]);
  assert(!b.boq.some((l: any) => /linework on layer M-DUCT/.test(l.description)), 'the duct layer is not listed again as raw linework');
  assert(b.boq.some((l: any) => /smoke/i.test(l.description) && l.qty === 2), 'the smoke detectors stay counted');
  assert(!b.boq.some((l: any) => /LOGO|TITLE/i.test(JSON.stringify(l))), 'a logo or title-block insert is not a priced line');
});

Deno.test('the inbox gate alone (a DWG, or a BOQ stored before the fix) still hides every layer and block name', async () => {
  const { text } = await served(consultantDxf(), false);
  for (const n of ['ORBITENG', 'KEYSTONE', 'ZZORBIT']) assert(!text.includes(n), n + ' served');
});

Deno.test('the repo title-block fixture: the layer named after the client is not served', async () => {
  const { text } = await served(dxfTitleBlockFixture(), true);
  assertEquals(leaks(text), []);
});

Deno.test('the terms the file states about itself', () => {
  const t = cadIdentityTerms(new TextDecoder().decode(consultantDxf()));
  // A drawing number with a project code is a term; a bare sheet number (M-101) or a view title is content.
  for (const want of ['ZZ HARBOUR TOWER', 'zz.drafter', 'ZZ ORBIT CONSULTING ENGINEERS', 'ZZ-M-101']) assert(t.includes(want), want + ' not found in ' + JSON.stringify(t));
  const content = cadIdentityTerms(new TextDecoder().decode(dxfFrom([...dxfSection('ENTITIES', [
    [0, 'TEXT'], [8, 'TITLE'], [1, 'M-101'], [0, 'TEXT'], [8, 'TITLE'], [1, 'MECHANICAL FLOOR PLAN'], [0, 'TEXT'], [8, 'TITLE'], [1, 'SCALE 1:100'], [0, 'TEXT'], [8, 'TITLE'], [1, '22/09/2026']]), [0, 'EOF']])));
  assertEquals(content, []);
  assertEquals(cadIdentityTerms('%PDF-1.4 not a dxf'), []);
});

Deno.test('names keep only CAD vocabulary; other shapes are untouched', () => {
  assertEquals(neutralCadName('ZZORBIT-M-DUCT'), 'M-DUCT');
  assertEquals(neutralCadName('AL MANSOORI VILLA'), 'AL-VILLA');
  assertEquals(neutralCadName('D-900'), 'D-900');
  assertEquals(neutralCadName('ACMEHOLDINGS'), 'unnamed');
  const sheet = [{ section: 'Masonry', description: 'block ACME wall 200 mm', qty: 40, unit: 'sqm', basis: 'row 3' }];
  assertEquals(neutraliseCadLines(sheet), sheet);
});

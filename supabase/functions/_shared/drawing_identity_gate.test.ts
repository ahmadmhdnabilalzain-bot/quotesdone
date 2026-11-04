// drawing_identity_gate — synthetic ZZ DEMO drawings only (never a customer file). Each test is the case
// the gate exists for. Measured: with the re-read removed (every line kept, rest not scanned) tests 2 and 3 fail; Test 1 is a regression: the DXF reader already cuts the contact
// text out of its lines, so the gate must not cost a quantity there.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from './doc_read/index.ts';
import { boqFromExtracted } from '../drawing_boq/boq_from_document.ts';
import { dxfFrom, dxfSection } from './doc_read/cad.fixtures.ts';
import { consultantDxf } from './cad_identity.test.ts';
import { drawingIdentityTerms, gateDrawingBoq, labelTerms, residualIdentity } from './drawing_identity_gate.ts';
import { dxfTextOf } from './cad_identity.ts';

const PARTY = ['ORBIT', 'HARBOUR', 'KEYSTONE', 'zz.drafter', 'REEM', '000 0012', '0000012', 'orbit.example', 'ZZ-L-4471', 'ZZ-4471'];
const leaks = (v: unknown) => { const t = JSON.stringify(v ?? '').toUpperCase(); return PARTY.filter((x) => t.includes(x.toUpperCase())); };

async function served(bytes: Uint8Array, name: string, mime: string) {
  const r: any = await readDocument(bytes, name, mime);
  assert(r.ok, JSON.stringify(r));
  const boq = boqFromExtracted(r, '');
  return { r, g: gateDrawingBoq(boq, drawingIdentityTerms(r.text, r.dxf_text), r.dxf_text !== undefined) };
}

Deno.test('1. DXF (regression): through the gate every quantity survives and no party is served', async () => {
  const base = new TextDecoder().decode(consultantDxf()).replace(/0\r?\nEOF\s*$/, '');
  const extra = new TextDecoder().decode(dxfFrom([...dxfSection('ENTITIES', [
    [0, 'MTEXT'], [8, 'M-ANNO'], [10, 0], [20, -1100], [40, 100], [1, 'CONTACT +971 50 000 0012 zz@orbit.example.invalid TRADE LICENCE NO: ZZ-L-4471'],
  ]), [0, 'EOF']]));
  // Two ENTITIES sections read as one drawing by the DXF reader; the second carries only the contact MTEXT.
  const bytes = new TextEncoder().encode(base + extra);
  const { g } = await served(bytes, 'plan.dxf', 'image/vnd.dxf');
  assert(g.boq, 'the take-off is not withheld for one dirty note');
  assertEquals(leaks(g.boq), [], 'identity reached the supplier-facing take-off');
  const q = (re: RegExp) => ((g.boq as any).boq as any[]).filter((l) => re.test(l.description)).map((l) => l.qty);
  assertEquals(q(/FCU/), [24]);
  assertEquals(q(/EXHAUST FANS/), [6]);
  assertEquals(residualIdentity(g.boq, []), []);
});

Deno.test('2. the re-read catches what redaction missed: a term glued inside a word withholds the take-off', () => {
  // 3 Nov 2026: 'Sheet set issued by ZZORBITENG' is now REDACTED (identity_text PERSON_LABELLED takes the name after
  // 'issued by'), so it no longer reaches the re-read; the glued term below has no label and still does.
  const boq = { summary: 'Sheet set ZZORBITENG rev 3', boq: [{ section: 'A', description: 'Wall', qty: 3, unit: 'm', basis: 'x' }], missing_info: [] };
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

Deno.test('6. label values from a PDF text layer become terms; plain content does not', () => {
  assertEquals(labelTerms('GROUND FLOOR PLAN\nClient: ZZ Orbit Holdings\nScale 1:100\nالمالك: زد زد ريم'), ['ZZ Orbit Holdings', 'زد زد ريم']);
  assertEquals(dxfTextOf(''), '');
});

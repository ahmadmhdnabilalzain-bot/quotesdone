// deno test supabase/functions/drawing_boq/cad_blocks_devices.test.ts
// The VECTOR counter: a CAD file counts its own symbols. doc_read/cad.ts counts INSERTs per block name;
// boqFromExtracted maps a block that names a device (legend_vocabulary.ts) to that device's line, with
// the file's exact count, qty_status 'read' — so the customer is not asked to confirm it.
import { assertEquals } from 'jsr:@std/assert@1';
import { readDxf } from '../_shared/doc_read/cad.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { DEVICE_TYPES, vocabFrom } from './legend_vocabulary.ts';

// Which block names which device is REASONED (decision point drawing_boq.vocabulary): here, the reasoning's answer.
const VOCAB = vocabFrom({ 'device:smoke_detector': { value: 'SMOKE_DETECTOR', evidence: 'SMOKE_DETECTOR' }, 'device:manual_call_point': { value: 'MANUAL_CALL_POINT', evidence: 'MANUAL_CALL_POINT' },
  'device:fire_alarm_control_panel': { value: 'FIRE_ALARM_CONTROL_PANEL', evidence: 'FIRE_ALARM_CONTROL_PANEL' } });
void DEVICE_TYPES;

const insert = (name: string, x: number) => `0\nINSERT\n8\nFA\n2\n${name}\n10\n${x}\n20\n0\n30\n0\n`;
const DXF = [
  '0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n',
  '0\nSECTION\n2\nENTITIES\n',
  ...[1, 2, 3].map((i) => insert('SMOKE_DETECTOR', i)),
  ...[1, 2].map((i) => insert('MANUAL_CALL_POINT', 10 + i)),
  insert('FIRE_ALARM_CONTROL_PANEL', 50),
  insert('DOOR-900', 60),
  '0\nENDSEC\n0\nEOF\n',
].join('');

Deno.test('CAD block counts become exact device lines', async () => {
  const r = await readDxf(new TextEncoder().encode(DXF), { filename: 'fa.dxf', depth: 0, readChild: () => Promise.reject(new Error('none')) } as never);
  assertEquals(r.ok, true);
  const out = boqFromExtracted((r as { ok: true } & Parameters<typeof boqFromExtracted>[0]), '', '', {}, VOCAB);
  const dev = (out.boq as { type?: string; qty: number | null; qty_status?: string }[]).filter((b) => b.type);
  assertEquals(dev.map((b) => [b.type, b.qty, b.qty_status]).sort(), [
    ['fire_alarm_control_panel', 1, 'read'], ['manual_call_point', 2, 'read'], ['smoke_detector', 3, 'read'],
  ]);
  // A block that is not a device stays a plain "block" line.
  assertEquals(out.boq.some((b) => /DOOR-900/.test(b.description)), true);
});

Deno.test('held: with no reasoned vocabulary no block is taken for a device — each stays its own line, counted', async () => {
  const r = await readDxf(new TextEncoder().encode(DXF), { filename: 'fa.dxf', depth: 0, readChild: () => Promise.reject(new Error('none')) } as never);
  const out = boqFromExtracted((r as { ok: true } & Parameters<typeof boqFromExtracted>[0]));
  assertEquals((out.boq as { type?: string }[]).filter((b) => b.type).length, 0);
  assertEquals(out.boq.some((b) => /SMOKE_DETECTOR/.test(b.description) && b.qty === 3), true);
});

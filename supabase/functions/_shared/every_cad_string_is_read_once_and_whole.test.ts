// EVERY CAD STRING IS READ WHOLE, ONCE, AND THE FILE IS PROVED ONE VALUE AT A TIME (second review of the anonymity fix,
// 13 Nov 2026, sales_engineer). Measured by the reviewer on this branch at a58c2fc45:
//   * the model never saw past character 200 of a string ("... SITE CONTACT MR" and the name after it), and a bare plot
//     number ("6512") was never sent at all;
//   * a bad line number in the model's answer, and a file of more than MAX_STRINGS strings, had no test (both must HOLD);
//   * every file whose logo BLOCK the model marked was held ("count of block ZZDEMO_CORAL_LOGO ... missing");
//   * the verifier joined the file's strings with "\n", and held 4 of 20 ordinary CAD files as a firm or an address
//     spread over two neighbouring strings;
//   * a layer spelt in two cases became two different names;
//   * mode 'cad' and mode 'file' each read the same strings (two paid readings), with an answer ceiling that truncates.
// Offline: the model is a stub.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/every_cad_string_is_read_once_and_whole.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { MAX_STRINGS, PIECE, READ_PAGE, cadStrings, cadStringsInContext, readCadStrings, readItems, readVerdict, stringsPrompt } from './drawing_string_reading.ts';
import { redactCadFile, verifyCadRedaction } from './cad_file_redact.ts';
import { dxfFrom } from './doc_read/cad.fixtures.ts';
import { seedTerms } from './anonymise.ts';

type P = [number, string | number][];
const line = (x1: number, y1: number, x2: number, y2: number, layer = 'POOL'): P => [[0, 'LINE'], [8, layer], [10, x1], [20, y1], [30, 0], [11, x2], [21, y2], [31, 0]];
const text = (layer: string, x: number, y: number, h: number, s: string): P => [[0, 'TEXT'], [8, layer], [10, x], [20, y], [30, 0], [40, h], [1, s]];
const LONG = 'GENERAL NOTES: ALL POOL WORKS TO COMPLY WITH DUBAI MUNICIPALITY POOL REGULATIONS, CONTRACTOR TO VERIFY ALL DIMENSIONS ON SITE BEFORE FABRICATION, ALL MATERIALS TO BE APPROVED SAMPLES. SITE CONTACT MR ZZ DEMO KAREEM AT THE GATE, NEXT TO THE SUPERMARKET';
const tables: P = [
  [0, 'SECTION'], [2, 'TABLES'],
  [0, 'TABLE'], [2, 'LAYER'], [0, 'LAYER'], [2, 'A-OWNER-ZZDEMO'], [70, 0], [62, 7], [6, 'CONTINUOUS'], [0, 'LAYER'], [2, 'POOL'], [70, 0], [62, 7], [6, 'CONTINUOUS'], [0, 'ENDTAB'],
  [0, 'ENDSEC'],
  [0, 'SECTION'], [2, 'BLOCKS'], [0, 'BLOCK'], [8, '0'], [2, 'ZZDEMO_CORAL_LOGO'], [70, 0], [10, 0], [20, 0], [30, 0], [3, 'ZZDEMO_CORAL_LOGO'], ...line(0, 0, 100, 100, '0'), [0, 'ENDBLK'], [0, 'ENDSEC'],
];
const ents: P = [
  ...line(0, 0, 10000, 0), ...line(10000, 0, 10000, 5000), ...line(10000, 5000, 0, 5000), ...line(0, 5000, 0, 0),
  ...text('POOL', 500, 2500, 180, 'SHALLOW END FFL -1.20'), ...text('POOL', 8200, 2500, 180, 'DEEP END FFL -1.80'),
  ...line(20000, 0, 20100, 100, 'a-owner-zzdemo'),                     // the same layer, spelt in lower case
  [0, 'INSERT'], [8, 'POOL'], [2, 'ZZDEMO_CORAL_LOGO'], [10, 15000], [20, 0], [30, 0],
  ...text('POOL', 12000, 3000, 200, 'PLOT NO.'), ...text('POOL', 13000, 3000, 200, '6512'), ...text('POOL', 12000, 2600, 200, 'TOTAL 1200'),
  [0, 'MTEXT'], [8, 'NOTES'], [10, 0], [20, -2000], [30, 0], [40, 150], [1, LONG],
];
const dxfBytes = dxfFrom([...tables, [0, 'SECTION'], [2, 'ENTITIES'], ...ents, [0, 'ENDSEC'], [0, 'EOF']]);
const dxf = new TextDecoder().decode(dxfBytes);
const seeds = seedTerms({ name: 'ZZ Demo Agent', email: 'agent.zz@example.invalid', phone: '+971500000043', extra: ['POOL-101.dxf'] });

/** A FAITHFUL reader: marks a line that names the owner, the firm or the site, and a plot number by the label beside it. */
function faithfulModel(log: string[] = []) {
  return async (_sys: string, user: string) => {
    log.push(user);
    const ids: number[] = [];
    for (const l of user.split('\n')) {
      const m = l.match(/^(\d+): (.*)$/);
      if (!m) continue;
      if (/KAREEM|ZZDEMO|ZZ DEMO|ALBARSHA|AL BARSHA/i.test(m[2]) || /beside it: "PLOT NO\./.test(m[2])) ids.push(Number(m[1]));
    }
    return JSON.stringify({ identity: ids });
  };
}

Deno.test('a long string is read in overlapping pieces to its END, and a name in the last piece removes the whole string', async () => {
  const items = readItems([LONG]);
  assert(items.length >= 2 && items.every((x) => x.text.length <= PIECE), JSON.stringify(items.map((x) => x.text.length)));
  assertMatch(stringsPrompt(items), /KAREEM/, 'the name after character 200 reaches the model');
  assertMatch(stringsPrompt(items), /\[piece 2 of \d\]/);
  // A name lying across a cut is whole in one piece (the pieces overlap by 40 characters).
  const cut = 'X'.repeat(PIECE - 6) + ' ZZ DEMO KAREEM ' + 'Y'.repeat(100);
  assert(readItems([cut]).some((x) => x.text.includes('ZZ DEMO KAREEM')));
  const rd = await readCadStrings(dxf, faithfulModel());
  assert(rd && [...rd.identity].some((s) => s.includes('KAREEM') && s.length > PIECE), 'the whole note is marked');
});

Deno.test('a bare number of 3+ digits goes to the model WITH the strings beside it; a dimension\'s own number does not', async () => {
  const { strings, context } = cadStringsInContext(dxf);
  assert(strings.includes('6512') && strings.includes('TOTAL 1200'));
  assertEquals(context.get('6512'), '"PLOT NO." / "TOTAL 1200"');
  assertMatch(stringsPrompt(readItems(strings, context)), /: 6512 {3}\[a number; beside it: "PLOT NO\." \/ "TOTAL 1200"\]/);
  const dim = dxfFrom([[0, 'SECTION'], [2, 'ENTITIES'], [0, 'DIMENSION'], [8, 'DIM'], [1, '4200'], [10, 0], [20, 0], [30, 0], [0, 'TEXT'], [8, 'T'], [1, '12'], [10, 0], [20, 0], [30, 0], [0, 'ENDSEC'], [0, 'EOF']]);
  const ds = cadStrings(new TextDecoder().decode(dim));
  assert(!ds.includes('4200') && !ds.includes('12'), `a dimension value and a 2-digit number name nobody: ${ds}`);
  const rd = await readCadStrings(dxf, faithfulModel());
  assert(rd?.identity.has('6512'), 'the plot number is marked and removed');
});

Deno.test('the gate rules HOLD: a bad line number, no answer, and a file of more than MAX_STRINGS strings are no reading', async () => {
  const strings = ['KITCHEN', 'ZZ DEMO OWNER'];
  assertEquals(readVerdict(strings, JSON.stringify({ identity: [1] })), new Set(['ZZ DEMO OWNER']));
  for (const bad of [[2], [-1], [0.5], ['x'], [1, 7]]) assertEquals(readVerdict(strings, JSON.stringify({ identity: bad })), null, `answer ${JSON.stringify(bad)} must hold`);
  assertEquals(readVerdict(strings, '{"identity": "1"}'), null);
  assertEquals(await readCadStrings(dxf, async () => JSON.stringify({ identity: [9999] })), null, 'an index past the page holds the file');
  assertEquals(await readCadStrings(dxf, async () => null), null);
  const many: P = [[0, 'SECTION'], [2, 'ENTITIES']];
  for (let i = 0; i <= MAX_STRINGS; i++) many.push(...text('T', i, 0, 1, `ROOM ${i} A`));
  many.push([0, 'ENDSEC'], [0, 'EOF']);
  let asked = 0;
  const big = await readCadStrings(new TextDecoder().decode(dxfFrom(many)), async () => { asked++; return JSON.stringify({ identity: [] }); });
  assertEquals(big, null, `more than ${MAX_STRINGS} strings is never read as "no identity"`);
  assertEquals(asked, 0);
});

Deno.test('the reading is paged under the answer ceiling, costed, paid from the budget, and bound to the file by its SHA-256', async () => {
  const many: P = [[0, 'SECTION'], [2, 'ENTITIES']];
  for (let i = 0; i < 2 * READ_PAGE + 10; i++) many.push(...text('T', i, 0, 1, `ROOM ${i} A`));
  many.push(...text('T', 0, 1, 1, 'ZZ DEMO OWNER'), [0, 'ENDSEC'], [0, 'EOF']);
  const t = new TextDecoder().decode(dxfFrom(many));
  const log: string[] = [];
  const rd = await readCadStrings(t, faithfulModel(log));
  assert(rd);
  assertEquals(rd!.calls, 3);
  assertEquals(log.length, 3);
  assert(log.every((u) => u.split('\n').filter((l) => /^\d+: /.test(l)).length <= READ_PAGE));
  assert(rd!.identity.has('ZZ DEMO OWNER'), 'a line on the last page is mapped back to its string');
  assert(rd!.usd > 0 && /^[0-9a-f]{64}$/.test(rd!.sha));
  let left = rd!.usd - 1e-6;
  assertEquals(await readCadStrings(t, faithfulModel(), { left: () => left, spend: (u) => { left -= u; } }), null, 'a reading the budget cannot pay for holds');
});

Deno.test('READ ONCE: mode cad hands its reading to mode file, which takes it only for the same file (index.ts, lib/drawings.ts, wa_inbound)', () => {
  const edge = Deno.readTextFileSync(new URL('../drawing_redact/index.ts', import.meta.url));
  assertMatch(edge, /const handedOn = reading \? \{ strings_reading: \{ sha: reading\.sha, identity: \[\.\.\.reading\.identity\] \} \} : \{\};/);
  assertMatch(edge, /given\.sha === await dxfSha\(src\.dxf\)\) identity = new Set\(/);
  const api = Deno.readTextFileSync(new URL('../customer_api/lib/drawings.ts', import.meta.url));
  assertMatch(api, /redactFile\(\{ \.\.\.o, stringsReading: rj\?\.strings_reading \?\? null \}\)/);
  const wa = Deno.readTextFileSync(new URL('../wa_inbound/customer_files.ts', import.meta.url));
  assertMatch(wa, /mode === 'file' && reading \? \{ strings_reading: reading \}/);
});

Deno.test('a marked BLOCK name is renamed and the file is still released: the verifier counts through both renames', async () => {
  const identity = new Set(['ZZDEMO_CORAL_LOGO']);
  const r = await redactCadFile(dxfBytes, seeds, { identity });
  assert(r.ok, JSON.stringify(r));
  if (!r.ok) return;
  assert(!r.dxf.includes('ZZDEMO_CORAL_LOGO'));
  const v = await verifyCadRedaction(r.before_dxf, r.dxf, seeds, r, [], r.removed);
  assert(!v.problems.some((p) => /count of block/.test(p)), v.problems.join('; '));
  assertEquals(v.counts.after[r.blocks.get('ZZDEMO_CORAL_LOGO')!], 1);
});

Deno.test('a layer spelt in two cases is ONE name in the released file', async () => {
  const r = await redactCadFile(dxfBytes, seeds, { identity: new Set(['A-OWNER-ZZDEMO']) });
  assert(r.ok);
  if (!r.ok) return;
  const entityLayers = new Set([...r.dxf.matchAll(/\n {2}8\n([^\n]+)/g)].map((m) => m[1].trim()));
  const tableLayers = [...r.dxf.matchAll(/\n {2}0\nLAYER\n {2}2\n([^\n]+)/g)].map((m) => m[1].trim());
  const lineLayer = r.dxf.match(/\nLINE\n {2}8\n([^\n]+)\n 10\n20000/)?.[1].trim();
  assertEquals(lineLayer, tableLayers[0], 'the lower-case entity layer and the upper-case record became the same name');
  assert(![...entityLayers, ...tableLayers].some((l) => /ZZDEMO/i.test(l)));
});

Deno.test('the verifier reads the released strings ONE AT A TIME: two ordinary neighbours are not a firm or an address', async () => {
  // Round 3 (13 Nov 2026) added the two neighbour pairs that HELD the reviewer's ordinary sheets o06 and o12 when the
  // strings were joined: "ISOLATOR 32A" + "ALL WORKS IN THE VILLA ..." read as pattern:firm_en, "2C x 6 mm2" +
  // "STREET LIGHT" as pattern:street_address. Neither string is identity alone.
  const ord: P = [[0, 'SECTION'], [2, 'ENTITIES'], ...line(0, 0, 1000, 0),
    ...text('N', 0, 0, 100, 'FIRE ALARM PANEL FACP-1'), ...text('N', 0, 200, 100, 'ALL WORKS IN THE VILLA SHALL FOLLOW DCD'),
    ...text('N', 0, 250, 100, 'ISOLATOR 32A'), ...text('N', 0, 260, 100, 'ALL WORKS IN THE VILLA SHALL FOLLOW DCD.'),
    ...text('N', 0, 300, 100, '2C x 6 mm2'), ...text('N', 0, 350, 100, 'STREET LIGHT'),
    ...text('N', 0, 400, 100, 'ROOF LEVEL +12.60'), ...text('N', 0, 600, 100, '4200'), [0, 'ENDSEC'], [0, 'EOF']];
  const b = dxfFrom(ord);
  const r = await redactCadFile(b, seeds, { identity: new Set() });
  assert(r.ok, JSON.stringify(r));
  if (!r.ok) return;
  const v = await verifyCadRedaction(r.before_dxf, r.dxf, seeds, r, [], r.removed);
  assert(v.ok, v.problems.join('; '));
  for (const s of ['ISOLATOR 32A', '2C x 6 mm2', 'STREET LIGHT', 'ALL WORKS IN THE VILLA SHALL FOLLOW DCD']) assert(r.dxf.includes('\n' + s), `${s} is kept`);
  // ...while one string that IS a firm still holds.
  const bad = await verifyCadRedaction(r.before_dxf, r.dxf.replace('ROOF LEVEL +12.60', 'ZZ DEMO CORAL CONSULTANTS LLC'), seeds, r, [], r.removed);
  assert(!bad.ok);
  // A removed bare number is looked for as a whole value, not inside a coordinate.
  const num = await verifyCadRedaction(r.before_dxf, r.dxf, seeds, r, [], ['1000']);
  assert(num.ok, 'the digits of a coordinate are not the removed plot number: ' + num.problems.join('; '));
});

// Round 3 (13 Nov 2026): the CAD worker recorded a job's model spend only on the run it published, so each of its
// 'gate' and 'read_strings' calls saw the set's whole budget again. It now sends what the job has spent so far.
Deno.test('the CAD worker\'s calls of one job are counted in the set\'s budget before its run is written', () => {
  const edge = Deno.readTextFileSync(new URL('../drawing_redact/index.ts', import.meta.url));
  const branch = (mode: string) => { const a = edge.indexOf(`if (body.mode === '${mode}')`); return edge.slice(a, edge.indexOf('\n    }\n', a)); };
  for (const m of ['gate', 'read_strings']) assertMatch(branch(m), /await budgetInFlight\(body\.source_path, body\.spent_usd\)/, `mode ${m}`);
  assertMatch(edge, /b\.spend\(Math\.max\(0, Number\(spentUsd\) \|\| 0\)\)/);
  const worker = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  assertEquals([...worker.matchAll(/spent_usd: spent\.get\(job\.id\) \?\? 0/g)].length, 2, 'both worker calls send the job\'s spend');
});

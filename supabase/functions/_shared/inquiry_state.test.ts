// The shared inquiry state's code half (inquiry_state.ts): the 100-message cap, "I don't know" in every dialect, the
// register label, and what may never be asked again. No network.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/inquiry_state.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { arabicRegister, blockedKeys, capRule, capStage, carriedTurns, CONVERGE_AT, dialectOf, intakeKey, MESSAGE_CAP, mergeState, portalKey,
  readState, saysDontKnow, stateSummary, statusOfStage, SUMMARISE_AT, whatsappKey } from './inquiry_state.ts';

Deno.test('the cap: converge from 80, summarise from 95, hand off at 100, never send 101', () => {
  assertEquals([CONVERGE_AT, SUMMARISE_AT, MESSAGE_CAP], [80, 95, 100]);
  assertEquals(capStage(2), 'normal');
  assertEquals(capStage(79), 'normal');
  assertEquals(capStage(80), 'converge');
  assertEquals(capStage(94), 'converge');
  assertEquals(capStage(95), 'summarise');
  assertEquals(capStage(99), 'summarise');
  assertEquals(capStage(100), 'handoff');
  assertEquals(capStage(101), 'over');
  assertEquals(capStage(240), 'over');
  assertEquals(['normal', 'converge', 'summarise', 'handoff', 'over'].map((s) => statusOfStage(s as never)), ['open', 'converging', 'summarising', 'handed_off', 'handed_off']);
  assertEquals(capRule('normal', 10), '');
  assert(/only for the required details still missing/.test(capRule('converge', 80)));
  assert(/summary/.test(capRule('summarise', 96)) && /confirm/.test(capRule('summarise', 96)));
  assert(/sales engineer now has their whole request/.test(capRule('handoff', 100)) && /Ask nothing/.test(capRule('handoff', 100)));
});

Deno.test("I don't know: English, MSA, Egyptian, Levantine, Gulf and Arabizi", () => {
  const yes = ["I'm not sure", 'no idea', 'dont know yet', 'لا أعرف', 'لست متأكداً', 'مش عارف', 'مش عارفة والله', 'معرفش', 'ما بعرف', 'مابعرف شو بدي',
    'مدري', 'ما أدري', 'مو متأكد', 'مب متأكد', 'ماني متأكد', 'mesh 3aref', 'msh 3arfa', 'ma3rafsh', 'ma ba3ref', 'mba3ref', 'madri'];
  for (const t of yes) assert(saysDontKnow(t), t);
  const no = ['I know exactly: 2.4 x 1.2 m', 'أعرف المقاس: مترين', 'بعرف المقاس', 'عارف المقاس', 'the madrid office', 'mesh panels please'];
  for (const t of no) assert(!saysDontKnow(t), t);
});

Deno.test('the register label: Egyptian, Lebanese and Gulf openings from the audit, Arabizi, English', () => {
  assertEquals(dialectOf(['عندي بارتشن خشب MDF صغير، عايز اكسيه بديكور PVC ولا استيكر، تنصحني بايه؟'])?.dialect, 'egyptian');
  assertEquals(dialectOf(['عندي قاطع MDF زغير، عم فكّر لبّسو ألواح PVC أو ستيكر، شو بتنصحني؟'])?.dialect, 'levantine');
  assertEquals(dialectOf(['عندي قاطع خشب MDF صغير ابي البسه بديكور PVC او ستيكر، شو الأفضل الحين؟'])?.dialect, 'gulf');
  assertEquals(dialectOf(['أرغب في تكسية قاطع من خشب MDF بألواح PVC'])?.dialect, 'msa');
  const az = dialectOf(['3ayez a8ayar el ballat fel 7ammam, mesh 3aref el ma2as']);
  assertEquals([az?.script, az?.dialect], ['arabizi', 'egyptian']);
  assertEquals(dialectOf(['I have a small MDF partition, 2.4 x 1.2 m, 2mm film, 3rd floor'])?.dialect, 'english');
  assertEquals(dialectOf([]), null);
  assert(/Egyptian Arabic/.test(arabicRegister('egyptian')) && /never slang/.test(arabicRegister('egyptian')));
  assert(/formal Gulf Arabic when they write Modern Standard Arabic/.test(arabicRegister('msa')));
  assert(/formal Gulf Arabic when they write Modern Standard Arabic/.test(arabicRegister(null)));
});

Deno.test('a held spec and a does-not-know are never asked again; the summary names the message each came from', () => {
  const st = { specs: { size: { value: '2.4 x 1.2 m', first_turn: 2 }, budget: { value: 'about 3,000 AED', first_turn: 2, changed_from: '2,000 AED' } },
    unknown: { material: { turn: 5, said: 'mesh 3aref' } }, message_count: 30 };
  assertEquals([...blockedKeys(st)].sort(), ['budget', 'material', 'size']);
  const s = stateSummary(st);
  assert(/size: "2.4 x 1.2 m" \(message 2\)/.test(s), s);
  assert(/they changed this; earlier "2,000 AED"/.test(s), s);
  assert(/DO NOT KNOW.*material/.test(s), s);
  assertEquals(stateSummary({ specs: {}, unknown: {}, message_count: 0 }), '');
  assertEquals(blockedKeys(null).size, 0);
});

Deno.test('the keys, the carried turns, and the database calls answer null instead of throwing', async () => {
  assertEquals(intakeKey('x'), 'intake:x');
  assertEquals(portalKey('a-c-1', 6), 'a-c-1#6');
  assertEquals(whatsappKey('whatsapp:+971500000000'), 'wa:+971500000000');
  const t = carriedTurns([{ role: 'user', content: 'old job' }, { role: 'assistant', content: 'done' }, { role: 'user', content: 'I need a partition clad' }, { role: 'assistant', content: '' }], 2);
  assertEquals(t, [{ role: 'user', text: 'I need a partition clad', carried: 'portal' }]);
  const broken = { rpc: () => { throw new Error('no such function'); }, from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: { message: 'relation does not exist' } }) }) }) }) };
  assertEquals(await mergeState(broken, 'k', 'request_chat', { turn: 1 }), null);
  assertEquals(await readState(broken, 'k'), null);
});

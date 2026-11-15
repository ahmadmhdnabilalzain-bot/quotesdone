// drawing_text_policy — which words of a drawing may reach a supplier, and when a word is the customer's name.
// deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/drawing_text_policy.test.ts
//
// Second review of #967 (25 Sep 2026). Its probe fuzzy.ts measured the seed matcher both ways: spellings of the
// same Arabic name it missed ("RASHEED KARIM" for "Rashid Kareem"), and drawing words it withheld as if they were a
// name ("ORBITAL" for "Orbit", "KITCHEN" and "SWITCHED SPUR" for "Kitchens Plus", "CEILING HEIGHT" for "Marina
// Heights"). Every probe is a case here. Offline; the names are synthetic.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { fold, isDrawingContent, isVocabularyContent, namesParty, seedHit } from './drawing_text_policy.ts';
import { seedTerms } from './anonymise.ts';
import { ID_TEXT } from './drawing_identity_text.ts';

Deno.test('a name in the spellings a drawing, an OCR and a customer use is the same name', () => {
  const tries: [Record<string, string>, string[]][] = [
    [{ name: 'Rashid Kareem' }, ['RASHEED KARIM', 'RASHED', 'KARIM', 'KAREM', 'KHAREEM', 'RSHID', 'R4SHID', 'RASH1D KAREEM', 'RASHEED', 'KAREEM', 'RASHIDKAREM', 'K A R E E M', 'QAREEM']],
    [{ name: 'Mohammed Al Mansoori', company: 'Emaar Properties' }, ['MOHAMED', 'MUHAMMAD', 'MOHAMMAD', 'MANSOURI', 'AL MANSURI', 'EMAR', 'EMAAR', 'EMMAR']],
    [{ name: 'Fatima Hassan', company: 'Nakheel' }, ['FATIMAH', 'FATMA', 'HASAN', 'HASSAN', 'NAKHIL', 'NAKHEAL']],
  ];
  for (const [src, probes] of tries) {
    const s = seedTerms(src);
    assertEquals(probes.filter((p) => !seedHit(p, s)), [], `missed for ${JSON.stringify(src)}`);
  }
  assertEquals(fold('RASHEED KARIM'), fold('Rashid Kareem'));
});

Deno.test('drawing words are not a name: whole tokens only, and never a seed word that is a trade word', () => {
  const content = `OFFICE 101|MEETING ROOM 102|CORRIDOR|MASTER BEDROOM|KITCHEN|MAJLIS|MAID ROOM|TOILET|BALCONY|STAIRCASE|RECEPTION|STORAGE|LAUNDRY|DRESSING|SMOKE DETECTOR|DOUBLE SOCKET OUTLET|SWITCHED SPUR|EMERGENCY LIGHT|DISTRIBUTION BOARD|FAN COIL UNIT|SUPPLY AIR DIFFUSER|RETURN AIR GRILLE|FIRE ALARM PANEL|MANUAL CALL POINT|HEAT DETECTOR|SPRINKLER HEAD|DOWNLIGHT|LIGHTING LAYOUT|POWER LAYOUT|GROUND FLOOR PLAN|FIRST FLOOR|ROOF PLAN|CEILING HEIGHT 3000|MASHRABIYA SCREEN|PRAYER ROOM|GUEST BEDROOM|FAMILY LIVING|SERVICE CORRIDOR|MECHANICAL ROOM|ELECTRICAL ROOM|GARAGE|DRIVER ROOM|STORE ROOM|CABINET|WARDROBE|MARBLE FLOORING|GYPSUM CEILING|CONCRETE SLAB|RETAINING WALL|STAIRCASE SECTION|HANDRAIL|MANHOLE|CHAMBER|MAINTENANCE|MANSARD ROOF|KITCHENS|TWO KITCHENS|MONITOR|CHARGER|RADIATOR|ACCESSORIES|CASHIER|ORBITAL|MANIFOLD|MANSION|FATIGUE|KARAOKE|SHAREDSPACE|CHAIR|EMERGENCY`.split('|');
  const customers: Record<string, string>[] = [
    { name: 'Rashid Kareem' }, { name: 'Mohammed Al Mansoori', company: 'Emaar Properties' }, { name: 'Fatima Hassan', company: 'Nakheel' },
    { name: 'Kareem Consulting', company: 'Orbit Design Studio' }, { name: 'Sara Ali', project: 'Palm Residence', company: 'Marina Heights Developers' },
    { name: 'Omar', company: 'Kitchens Plus' },
  ];
  for (const src of customers) {
    const s = seedTerms(src);
    assertEquals(content.filter((c) => seedHit(c, s)), [], `drawing words read as ${JSON.stringify(src)}`);
  }
  // The whole phrase is still the party.
  assert(seedHit('KITCHENS PLUS', seedTerms({ name: 'Omar', company: 'Kitchens Plus' })));
  assert(seedHit('MARINA HEIGHTS', seedTerms({ company: 'Marina Heights Developers' })));
});

Deno.test('the scan route\'s vocabulary gate (isVocabularyContent, OCR with no model): a short word passes only from the closed list; anything unknown, foreign or disguised is withheld', () => {
  for (const t of ['DAR', 'WSP', 'ARUP', 'ZZ', 'ORB', 'OR BI T', '<> BY DAR', 'ZZ ORBIT', 'NORTH GATE LLC', '0RB1T', 'ORB\u00cdT', 'K', 'K A R E E M', 'VILLA 12 JUMEIRAH', 'al@', 'kx.ae', 'T 050']) {
    assert(!isVocabularyContent(t), `"${t}" passed as drawing content`);
  }
  for (const t of ['OFFICE 101', 'SD - SMOKE DETECTOR', 'DB-01', '63A TPN', '12 WAYS', '2x13A', 'L1', 'FFL +0.150', 'SPLIT AC 2.5 TR', 'DATA OUTLET CAT6', 'CABLE SIZE 4C x 16 SQMM XLPE/SWA', 'REFER TO MEP SPECIFICATION', 'CONTRACTOR TO VERIFY ON SITE', 'EXISTING WALL TO BE DEMOLISHED', 'POWDER ROOM', 'SWIMMING POOL', 'VANITY', 'SHOWER', '<>', '600x600', 'OFFICE 1@1']) {
    assert(isVocabularyContent(t), `"${t}" was withheld`);
  }
  assert(!namesParty('CONTRACTOR TO VERIFY ON SITE') && namesParty('CONTRACTOR: ZZ OMEGA CONTRACTING') && namesParty('ZZORBITENGINEERING'));
});

// 13 Nov 2026 (design change C, review item 10): the code floor withholds only what it can PROVE is a party or a place.
Deno.test('the code floor (isDrawingContent): what code can prove is withheld; a word it merely does not know is not', () => {
  for (const t of ['ZZ ORBIT ENGINEERING', 'NORTH GATE LLC', 'DM LIC 123456', '050 123 4567', 'al@', 'kx.ae', 'VILLA 12 JUMEIRAH', 'PLOT NO 345', 'OWNER: MR X', 'DRAWN BY A. DEMO', 'K A R E E M', 'E 492 310.25 N 2 778 104.60', 'V-15']) {
    assert(!isDrawingContent(t), `"${t}" passed the floor`);
  }
  for (const t of ['BS 7671', 'IEC 61439', 'LOAD SCHEDULE', 'TOTAL CONNECTED LOAD 45.6 KW', 'FLAT ROOF', 'TOWER CRANE', 'STREET LIGHT', 'PLOT BOUNDARY', 'PAINT JOTUN FENOMASTIC', 'N', 'UNIT 1200 W', 'TOWER B', 'BUILDING A', 'CLIENT', '0 1 2 3 4 5 m']) {
    assert(isDrawingContent(t), `"${t}" was withheld by the floor`);
  }
});

Deno.test('the phone forms the review drew are contacts', () => {
  for (const t of ['(04) 123-4567', '04.123.4567', '0 5 0 1 2 3 4 5 6 7', '050 1234 567', '050 123 4567', '04 123 4567']) assert(ID_TEXT.test(t), t);
  for (const t of ['6000', '+0.150', '1:100', '600x600', '3000 4500', '12345']) assert(!ID_TEXT.test(t), `${t} read as a phone`);
});

// identity_text.test.ts — every leak the planted-identity run measured on 3 Nov 2026 (scripts/e2e/
// identity_never_leaks_before_reveal.mjs, seed 20261103), replayed through the scrubbers that let it through, AND the
// independent review of #1838's MUST-KEEP probes: the ordinary BOQ, quotation and Q&A wording the first version of
// the shared list destroyed (some of it at save, so permanently). Both halves must hold.
// deno test --no-lock supabase/functions/_shared/identity_text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { identityShapesIn, knownNameRe, scrubIdentityText } from './identity_text.ts';
import { scrubIdentity as supplierScrub } from '../supplier_api/identity_scrub.ts';
import { scrubIdentity as boqScrub } from '../drawing_boq/boq_from_text.ts';
import { maskContacts, quoteDocument } from './quote_documents.ts';
import { stripContact } from '../messages_api/strip_contact.ts';
import { residualScan } from './anonymise.ts';
import * as F from './quote_documents.fixture.ts';

const NAME = 'ZZ Crescent Green AM9 Engineering Consultants LLC';
// The printed forms that reached the other side, each with the substring that must be gone.
const LEAKED: [string, string][] = [
  ['Cheque in favour of ZZ Crescent Green AM9 Engineering Consultants LLC.', 'Crescent Green AM9'],
  ['Transfer to IBAN AE09 0580 0009 6788 6290 627.', '6788'],
  ['IBAN: AE280040006055553370809', '0060555'],
  ['P. O. Box 59508', '59508'], ['PO BOX: 14446', '14446'], ['POB 21759', '21759'], ['ص.ب ٥٦١٤٣', '٥٦١٤٣'],
  ['Trade licence TL 273158', '273158'], ['T.L. No. 273158', '273158'], ['CN-9744610', '9744610'], ['D.E.D. Licence 780159', '780159'],
  // The header's own measured leak was the SIX-digit "CN-974461" (second review of #1838, 3 Nov 2026): restored.
  ['CN-974461', '974461'], ['Licence CN 1234567', '1234567'], ['CN1234567', '1234567'],
  ['Hotline (050) 000 0076', '0076'], ['Mob 971500000064', '0064'], ['+٩٧١ ٥٠ ٠٠٠ ٠٠٦١', '٠٠٦١'], ['٠٤ ٠٠٠ ٠٠٥٥', '٠٠٥٥'], ['(04) 000 0044', '0044'],
  ['Mob: 05 0000 0012', '0012'], ['04-0000012', '0000012'], ['0500000098', '0098'], ['+971 4 000 0017', '0017'],
  ['Showroom: Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai.', 'IU8 Tower'],
  ['Al Katheeb Al Akhdar Trading standard conditions apply.', 'Katheeb'],
  ['شركة النخلة الملكي للديكور ذ.م.م', 'النخلة'], ['شركة الواحة الأخضر للخدمات الفنية ذ.م.م', 'الواحة'],
  ['Prepared by: ZZ Omar Qasimi, Sales Engineer', 'Qasimi'], ['Thanks, ZZ Rashid Ketbi - quotes', 'Ketbi'], ['Site visits arranged by ZZ Majid Nuaimi.', 'Nuaimi'],
  ['المسؤول: زد زد عمر المزروعي.', 'المزروعي'],
  // ── second independent review of #1838 (3 Nov 2026): leaks the loosened list REOPENED, each measured passing ──
  // 1. a sign-off with no comma
  ['Best Regards\nAhmed Khan\nSales Manager', 'Khan'], ['Best Regards Ahmed Khan', 'Khan'], ['Kind regards Ahmed Khan, Sales Manager', 'Khan'],
  ['Thanks & Regards\nAHMED KHAN', 'KHAN'], ['Regards,\nAhmed Khan\nSales Manager', 'Khan'],
  // 2. name shapes: hyphenated, all-caps, lowercase particles
  ['Prepared by: Ahmed Al-Mansoori', 'Mansoori'], ['Prepared by: AHMED KHAN', 'KHAN'], ['Contact: Eng. Ahmed al Mansoori', 'Mansoori'],
  ['Mr. Ahmed bin Rashid', 'Rashid'], ['Prepared by: Ahmed Khan Sales Engineer', 'Khan'],
  // 4. Arabic legal names: a legal form is identity on its own; a proper noun after شركة / مؤسسة
  ['شركة النور ٢٠٠٠ للمقاولات ذ.م.م', 'النور'], ['النور للمقاولات ذ.م.م', 'النور'], ['شركة النور الذهبية', 'النور'], ['مؤسسة النور', 'النور'],
  ['وشركة النور للمقاولات', 'النور'],
  // 5. the country code in brackets
  ['Tel (+971) 50 123 4567', '4567'], ['Tel (+971) 4 123 4567', '4567'],
  // 6. all-caps Latin firms; 7. other mobile layouts
  ['AL NOOR TRADING', 'NOOR'], ['AL NOOR CONTRACTING CO.', 'NOOR'],
  ['050 12 34 567', '567'], ['050/1234567', '1234567'], ['0 5 0 1 2 3 4 5 6 7', '4 5 6 7'],
  // PRE-EXISTING GAPS closed here
  ['Lic. No. 1234567', '1234567'], ['Lic No: 654321', '654321'], ['رخصة تجارية رقم ١٢٣٤٥٦', '١٢٣٤٥٦'], ['السجل التجاري 765432', '765432'],
  ['Visit alnoor.store', 'alnoor'], ['Visit alnoor.shop today', 'alnoor'], ['Follow instagram.com/alnoortrading', 'alnoortrading'],
  ['Mail ahmed @ gmail . com', 'ahmed'], ['Mail ahmed[at]gmail[dot]com', 'ahmed'], ['Mail ahmed(at)gmail(dot)com', 'ahmed'],
  ['IBAN AE07-0331-2345-6789-0123-456', '6789'],
  ['Building 5, Al Quoz, Dubai', 'Al Quoz'], ['Villa 23, Street 14, Jumeirah 1, Dubai', 'Jumeirah'], ['مكتب ١٢، برج الخليج، دبي', 'برج الخليج'], ['Post Box 12345', '12345'],
  ['المهندس أحمد المنصوري', 'المنصوري'], ['م. أحمد المنصوري', 'المنصوري'], ['مع التحية، أحمد المنصوري', 'المنصوري'],
  ['Al Noor & Sons Trading LLC', 'Noor'], ['Saif bin Darwish Contracting', 'Saif'],
  // ── adversarial re-review of these fixes (3 Nov 2026), every row reproduced by execution ──
  // C1 a phone followed by another group; C7 other layouts and other countries
  ['Call +971 50 123 4567 9am to 6pm', '4567'], ['Call 050 123 4567 9am to 6pm', '4567'], ['Mob: 050 123 4567 24/7', '4567'],
  ['Tel 04 345 6789 050 123 4567', '6789'], ['Tel 04 345 6789 050 123 4567', '123 4567'],
  ['Call 050–123–4567', '4567'], ['٠٥٠–١٢٣–٤٥٦٧', '٤٥٦٧'], ['Call 050  123  4567', '4567'], ['Toll free 800 66667', '66667'], ['Call 600 522222', '522222'],
  ['Mob 00966501234567', '501234567'], ['Mob +966 50 123 4567', '4567'], ['Mob +91 98765 43210', '43210'],
  // C2 long names; C3 apostrophe and camel-case; C4 labels and sign-offs
  ['Best regards,\nMohammed Abdul Rahman Al Hashimi', 'Hashimi'], ['المهندس محمد عبد الله أحمد المنصوري', 'المنصوري'],
  ["Prepared by: John D'Souza", 'Souza'], ['Prepared by: Ian McDonald', 'McDonald'], ['Prepared by: Mohammed DSouza', 'DSouza'],
  ['Rgds, Ahmed Khan', 'Khan'], ['Br,\nAhmed Khan', 'Khan'], ['Cheers, Ahmed Khan', 'Khan'], ['Thanks\nAhmed Khan', 'Khan'], ['Thank you,\nAhmed Khan', 'Khan'],
  ['Name: Ahmed Khan', 'Khan'], ['My name is Ahmed Khan from the sales team', 'Khan'], ['Contact Mr Ahmed Khan for site visit', 'Khan'], ['Eng Ahmed Khan will attend', 'Khan'],
  ['Sales Engineer - Ahmed Khan', 'Khan'], ['Engr. Mohd. Irfan Khan', 'Khan'], ['Regards, Sales Manager Ahmed Khan', 'Khan'],
  ['السيد/ أحمد المنصوري', 'المنصوري'], ['م/ أحمد المنصوري', 'المنصوري'], ['المهندس/ أحمد المنصوري', 'المنصوري'], ['الاسم: أحمد المنصوري', 'المنصوري'],
  ['تحياتي، أحمد المنصوري', 'المنصوري'], ['شكرا، أحمد المنصوري', 'المنصوري'], ['مدير المبيعات: أحمد المنصوري', 'المنصوري'], ['اسمي أحمد المنصوري', 'المنصوري'],
  // C5 Latin firm forms
  ['Gulf Pipes FZC', 'Gulf Pipes'], ['Gulf Pipes W.L.L.', 'Gulf Pipes'], ['Gulf Pipes DMCC', 'Gulf Pipes'], ['Gulf Pipes PJSC', 'Gulf Pipes'],
  ['Al Noor Est.', 'Noor'], ['Al Noor Est', 'Noor'], ['Al Noor Group', 'Noor'], ['Al Noor Technical Works', 'Noor'], ['Al Noor Electromechanical Works', 'Noor'],
  ['Al Noor General Maintenance', 'Noor'], ['Al Noor Trdg. LLC', 'Noor'], ['Al Noor Cont. Co. LLC', 'Noor'], ['M/s. Al Noor Bldg. Cont. Co.', 'Noor'],
  ['al noor trading llc', 'noor'], ['Al Noor trading LLC', 'Noor'],
  // C6 Arabic firms
  ['مؤسسة نور الهدى', 'نور الهدى'], ['النور للمقاولات العامة', 'النور'], ['أحمد المنصوري للمقاولات', 'المنصوري'], ['مكتب النور للاستشارات الهندسية', 'النور'],
  ['مصنع النور للألمنيوم', 'النور'], ['النور للمقاولات LLC', 'النور'],
  // C8 mail, web and social
  ['ahmed at gmail dot com', 'gmail'], ['ahmed AT gmail DOT com', 'gmail'], ['Visit alnoor . ae', 'alnoor'], ['Visit alnoor dot ae', 'alnoor'], ['Visit alnoor.dev', 'alnoor'],
  ['Visit alnoor.build', 'alnoor'], ['Visit alnoor.contractors', 'alnoor'], ['Visit alnoor.me', 'alnoor'], ['Visit alnoor.in', 'alnoor'], ['Instagram: @alnoor_trading', 'alnoor_trading'],
  ['Find us on facebook /alnoortrading', 'alnoortrading'], ['IG alnoor.trading', 'alnoor'],
  // C9 bank; C10 P.O. Box, licence, address
  ['Acc No. 1012345678901', '1012345678901'], ['رقم الحساب: 1012345678901', '1012345678901'], ['IBAN: AE٠٧٠٣٣١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦', '٥٦٧٨٩'],
  ['P.O. Box No. 12345', '12345'], ['P.B. 12345', '12345'], ['PB 12345 Dubai', '12345'], ['Box 12345, Dubai', '12345'], ['صندوق البريد 12345', '12345'], ['ص.ب. رقم 12345', '12345'],
  ['TL 273158', '273158'], ['TL-273158', '273158'], ['DED 1234567', '1234567'], ['رخصة رقم 123456', '123456'], ['ترخيص رقم 123456', '123456'], ['CN 12345678', '12345678'],
  ['Shop # 5, Al Quoz, Dubai', 'Al Quoz'], ['Office 12 - Al Garhoud - Dubai', 'Garhoud'], ['مكتب رقم ١٢ - بناية النور - الشارقة', 'بناية النور'],
  // the reviewer's own input set, re-run after the fixes above
  ['Please ask for Ahmed Khan at reception', 'Khan'], ['Ahmed Khan | Sales Manager | +971 50 123 4567', 'Khan'], ['info@alnoor.construction', 'alnoor'],
  ['Plot 597-123, DIP, Dubai', '597'],
  // the final 480-trial run on these fixes: 1 of 180 Q&A messages kept a bracketed address with a long ending
  ['email info [at] zzcrescentbluegd8.example.invalid', 'zzcrescentbluegd8'], ['ahmed (at) alnoor (dot) construction', 'alnoor'],
  // ── the anonymity audit of 13 Nov 2026 (REPORT_A L1/L4, REPORT_C L2): every one passed every scrubber ──
  ['Villa 15, Al Barsha 2, Dubai', 'Barsha'], ['Villa 15, Al Barsha 2, Dubai', 'Villa 15'], ['Site is Villa 15 Al Barsha 2', 'Barsha'], ['Site is Villa 15 Al Barsha 2', '15'],
  ['The house is in Al Barsha 2 near Mall of the Emirates', 'Mall of'], ['The house is in Al Barsha 2 near Mall of the Emirates', 'Barsha'],
  ['الفيلا في البرشاء 2 قرب مول الإمارات، فيلا رقم 15', 'البرشاء'], ['الفيلا في البرشاء 2 قرب مول الإمارات، فيلا رقم 15', '15'], ['الفيلا في البرشاء 2 قرب مول الإمارات، فيلا رقم 15', 'مول'],
  ['Plot No. 373-4512 in Al Barsha South', '4512'], ['Makani 12345 67890', '67890'], ['Makani number: 1234567890', '1234567890'], ['Makani 3061295475', '3061295475'],
  ['Apartment 1204, Marina Gate 2 tower, Dubai Marina', '1204'], ['Apartment 1204, Marina Gate 2 tower, Dubai Marina', 'Marina'], ['Location 25.1123, 55.2001', '25.1123'],
  ['what3words ///filled.count.soap', 'filled.count'], ['visit our showroom in Al Quoz', 'Quoz'], ['from our Al Quoz warehouse', 'Quoz'], ['Emirates NBD, Al Quoz branch', 'Quoz'],
  ['Emirates NBD, Al Quoz branch', 'NBD'], ['Payment by transfer to Mashreq', 'Mashreq'], ['Interior painting in Al Nahda, Sharjah', 'Nahda'], ['Villa in Khalifa City A', 'Khalifa'],
  ['near Sheikh Zayed Road opposite Lulu Hypermarket', 'Zayed'], ['call zero five five, zero zero zero, zero four nine nine', 'zero four nine'],
  ['zero five zero one two three four five six seven', 'zero five zero'], ['my number is 055 000 then 0499', '0499'], ['call 050 123 / then 4567', '4567'],
  ['رقمي صفر خمسة خمسة صفر صفر صفر صفر أربعة تسعة تسعة', 'تسعة'], ['mail omar.haddad @ zz-mail.example.invalid', 'haddad'], ['write to omarhaddad at gmail dot com', 'omarhaddad'],
  ['Contact Rashid Khan for details', 'Rashid'], ['Regards, Rashid', 'Rashid'], ['Consultant is Eng. Rami Khoury', 'Khoury'], ['ask for Rashid at the gate', 'Rashid'],
  ['Quotation No. FT-Q-2026-0457', 'FT-Q'], ['Ref FT/Q/2026/0457 attached', 'FT/Q'], ['Sales Manager. Signed and stamped', 'stamped'], ['Sales Manager. Signed and stamped', 'Sales Manager'],
  ['[company stamp: FALCON TRADING LLC - DUBAI]', 'stamp'],
];
/** What a residual scan must flag on the RAW text (a drawing page holding these is held, never shared). */
const residualOf = (s: string) => residualScan(s, ['zz demo']);
Deno.test('every leaked shape is gone through each scrubber that let it through, and a residual scan flags the raw text', () => {
  const bad: string[] = [];
  for (const [text, gone] of LEAKED) {
    const outs = { supplier_api: supplierScrub(text, NAME, []) ?? '', drawing_boq: boqScrub(text), quote_documents: maskContacts(text, [NAME]), messages_api: stripContact(text, [NAME]) };
    for (const [who, out] of Object.entries(outs)) if (out.includes(gone)) bad.push(`${who} kept "${gone}" of ${JSON.stringify(text)}: ${JSON.stringify(out)}`);
    if (!residualOf(text).length) bad.push(`residualScan found nothing in ${JSON.stringify(text)}`);
  }
  assertEquals(bad, []);
});
Deno.test('a known name is matched whole, with its suffix, and next to Arabic; fragments only with a digit, only when asked', () => {
  const re = knownNameRe(NAME)!;
  for (const s of ['ZZ Crescent Green AM9 Engineering Consultants LLC', 'zz crescent green am9 engineering consultants', 'شركة ZZ Crescent Green AM9 Engineering Consultants للتجارة']) { re.lastIndex = 0; assert(re.test(s), s); }
  re.lastIndex = 0; assert(!re.test('the Crescent Green AM9 series'), 'no fragment unless asked');
  const fr = knownNameRe(NAME, { fragments: true })!; assert(fr.test('the Crescent Green AM9 series'), 'a fragment carrying a digit');
  const ar = knownNameRe('شركة النور للتجارة')!; assert(ar.test('من شركة النور للتجارة'));
  // "Consultants" no longer loses its "Co": the old pattern matched none of these.
  assertEquals(supplierScrub(`payable to ${NAME} only`, NAME, []), 'payable to [removed] only');
});
Deno.test('a residual Arabic-Indic or bracketed phone, an IBAN, a P.O. Box or a licence holds a drawing page', () => {
  for (const s of ['٠٤ ٠٠٠ ٠٠١٤', '(04) 000 0019', 'T.L. No. 614867', 'IBAN AE09 0580 0009 6788 6290 627', 'ص.ب ٥٦١٤٣']) assert(residualScan(s, ['zz demo']).length > 0, s);
});

// ── MUST-KEEP (independent review of #1838, scratchpad probes probe.ts / probe_main.ts / probe_cmp.ts / probe_reveal.ts)
const KEEP = ['Supply and install 2 TR ducted split unit 6 nos 4200.00 25200.00', 'GI ductwork with insulation 85 sqm 180.00', 'Copper piping 1/2" + 7/8" insulated 60 lm',
  '14 days from PO.', '50% advance, 50% on completion.', 'Thanks for the opportunity to quote.', 'Cooling Tower CT-1 1 nos', 'Main Building ground floor', 'Validity: 30 days',
  'Qty 0.50 Rate 1250.00', 'AED 9,971,500.00', 'FCU-1 to FCU-6, 2 TR each', 'بلاط بورسلين 600x600 الكمية 120 متر مربع', 'Room 0450 x 1200', 'Unit 6, 2 TR', 'Contact the Majlis ceiling height 3.2 m',
  'Toughened glass to BS EN 12150-1, 10 mm clear', 'ASTM C1036 float glass 6 mm', 'Fire rated to DIN 4102 B1', 'Cables to BS 6724 LSZH 4C x 16 sqmm',
  'Inverter model TL-12000 1 nos', 'Product code CN-123456 ceiling tile', 'Ref TL 273158 luminaire', 'Dimmer DED 45000 series',
  'Bosch part no 0 986 452 041', 'UPVC pipe dia 050 075 110 160 mm', 'Valves DN 025 032 040 050 065 080',
  '01 25 450.00 11250.00', '03 120 4500 54000', 'Item 02 6 nos 1250.00 7500.00', 'Rev 02 dated 05.11.2026 10:30',
  'Dated 01.12.2026 1200 hrs', 'Price AED 971,500.00', 'Total 0 971 500 000', '050 mm thick insulation',
  'Project Manager Full Time On Site', 'Attention: Please note prices exclude VAT', 'Approved by MEP Consultants prior to install', 'Section 4 General Contracting works',
  'Project Duration Est. 6 Weeks', 'Mr. Client to provide power', 'From: Ground Floor To Roof',
  'مكتب خشبي مقاس ١٢٠×٦٠ سم عدد ١٠', 'تشطيب مكتب الإدارة بالكامل', 'خرسانة جاهزة من مصنع معتمد C40', 'يتم الاستلام من قبل المهندس المشرف على المشروع',
  'المسؤول عن التركيب المقاول الرئيسي', 'شركة التأمين تتحمل التكاليف',
  'Contact: Site Office for access', 'Regards, Supply Chain Team',
  // ── second independent review of #1838 (3 Nov 2026): trade text the loosened list still ate ──
  'Acoustic Consultants approval required', 'Third Party Consultants to witness testing', 'Fire Alarm Engineering Consultants approval',
  'Kitchen Interiors package 1 lot', 'Section 5: Hotel Lobby Interiors', 'Permit issued by Dubai Municipality', 'NOC issued by Abu Dhabi Municipality',
  'Signed by Both Parties before mobilisation', 'Submitted by Tenderer Before Closing Date', 'Contact: Dubai Electricity Authority for connection',
  'BMS software licence 12500.00', 'Annual licence 15000 per year', 'عن طريق شركة معتمدة للصيانة', 'بواسطة شركة متخصصة للعزل المائي',
  // and the guards the fixes above must not break
  'Thanks for the opportunity', 'Our trading terms apply', 'General trading terms apply', 'With regards to the delivery schedule',
  'Best Regards, Supply Chain Team', 'Kind regards, QS Team', 'Prepared by: MEP CONSULTANTS', 'Attention: ALL WORKS TO BE TESTED',
  'Dated 05.06.2026 1200 hrs', 'الشركة المصنعة تقدم الضمان', 'الشركة الموردة مسؤولة عن التركيب', 'المهندس المقيم في الموقع', 'مع الشكر للتعاون',
  'طول الأنبوب ١٠ م. حسب المخطط', 'Model CN 1234567 driver', 'Item code CN-1234567 panel',
  // ── adversarial re-review (3 Nov 2026): trade text the fixes above destroyed, every row reproduced by execution ──
  // D1 Title-Case scope ending in a firm word
  'Site Establishment and Mobilisation 1 LS', 'Mobilisation & Site Establishment 1 lot', 'Includes 12 Months Free Technical Services',
  'Annual Maintenance Contract Technical Services', 'Testing & Commissioning Technical Services', 'Scope: Waterproofing Contracting for roof',
  'Villa Renovation Contracting works', 'Swimming Pool Contracting Package', 'Interior Fit-Out Contracting 1 LS', 'Gypsum Partition Contracting 120 sqm',
  'Kitchen Equipment Trading terms apply',
  // D2 roles and scope after a label
  'Prepared by Quantity Surveyor', 'Signed by Authorised Signatory', 'Thanks, Will Confirm Tomorrow', 'From: Existing Manhole MH-3 To MH-7',
  'Contact: Mall Security For Permits', 'اعتماد المهندس قبل التنفيذ', 'موافقة المهندس قبل البدء بالأعمال', 'توفير المهندس طوال فترة المشروع', 'مع التحية والتقدير لكم',
  // D3 dates and DN lists with a slash; D4 prices after @; D5 a sentence with no space after its full stop
  'Dated 05/03/2026 09:00', 'Site visit on 05/02/2026 10 am', 'Valves DN 050/065/080 2 nos each',
  'Supply 10 nos @ 450. Total 4500', 'Rate @ 120. VAT extra', 'Rebar 12 mm 5.2 ton @ 3200. VAT 5%', 'We can meet @ site. Send the drawings first',
  'Price valid for 30 days.Site visit required before start', 'after approval.Shop drawings', '2 weeks.Store at site', '2 years.App based controls',
  'in mm.Pro rata payment', '2 coats.Group A colours',
  // D6 product codes by their label; D8 licence words with no number; D9 a generic firm noun
  'Catalogue No. CN-123456 ceiling tile', 'SKU: CN-123456 downlight', 'Article CN-1234567 LED driver', 'Product CN-123456 panel',
  'License: Included', 'Software License: Perpetual', 'Vehicle registration: required before site access', 'تجديد الرخصة التجارية 2026',
  'يتم الفحص بواسطة شركة المصاعد', 'التنسيق مع شركة الغاز قبل التركيب', 'شركة الحراسة مسؤولة عن الموقع', 'تنظيف نهائي من قبل شركة التنظيف',
  'شركة البناء تتحمل المسؤولية', 'تقديم شهادة من شركة واحدة للضمان', 'تقديم شهادة من شركة فحص للمعدات',
  // and the guards the fixes for the re-review must not break
  'Duct 800 600 1200 mm', 'WhatsApp group for site updates', 'مجموعة المضخات ٢ عدد', 'Qty 6 @AED50', 'Thanks\nPlease find attached', 'Box 12 nos',
  'تم تسليم المخطط للمقاولات العامة', 'مكتب الموقع للمهندس المشرف',
  // the reviewer's own input set, re-run after the fixes above
  'Inspection 05-04-2026 14 30 hrs', 'Price excludes VAT.Info on request', 'Marble Trading Co. not included', 'ص ب 100 لتر',
  // ── the anonymity fix round of 13 Nov 2026: what the new place, phone-word, name, bank and document-number rules must
  // leave alone (the brief's over-redaction list, and the trade words beside each new rule) ──
  'Marina blue emulsion 2 coats', 'Jumeirah collection wallpaper 10 rolls', 'Dubai Municipality approved', 'Sharjah-made concrete blocks', 'DEWA connection by others',
  '3-bedroom villa', '2 villas', 'villa has two floors', 'Unit 6, 2 TR', 'plot area 500 m2', 'Villa 4 bedrooms', 'Office 1 nos', 'Steel Tower 2 nos', 'Access Road paving 200 m2',
  'next to DB-01', 'near the main door', 'JVC TV 55 inch', 'DIP switch 8 way', 'Supply Of Steel For Tower', 'Level 3 slab', 'SHALLOW END FFL -1.20',
  'two coats then one coat of sealer', 'Qty 50, 120, 4500', 'Ref CT-1 cooling tower', 'FAB shop drawings by contractor', 'CBD tiles 600x600',
  'Call Centre support 24/7', 'Contact Details on request', 'Regards, Team', 'call Monday morning', 'Coordinate with Main Contractor', 'Made in Germany',
  '5 years warranty on workmanship', 'Warranty 10 years by manufacturer', 'مع الشكر للتعاون', 'Interior painting in Dubai'];
/**
 * REDUCED, NOT KEPT (13 Nov 2026, founder ledger 1683: "Dubai in general is okay … Al Barsha and Villa 15 need to be
 * hidden"). These four were MUST-KEEP rows of #1838, written when only firm names and contacts were identity; a community,
 * a district or a unit number below the emirate is identity now, so each crosses as its emirate and nothing else.
 */
const REDUCED: [string, string][] = [
  ['Delivery from Jebel Ali Industrial Area 2 warehouse', 'Delivery from Dubai warehouse'],
  ['All works on behalf of Main Contractor Dubai Hills', 'All works on behalf of Main Contractor Dubai'],
  ['Unit 12, Block B, Dubai', 'Dubai'],
  ['تجديد مكتب في دبي مارينا مساحة ٢٠٠ متر مربع', 'تجديد مكتب في دبي مساحة ٢٠٠ متر مربع'],
];
Deno.test('REDUCED: a place below the emirate crosses as its emirate (ruling 1683), through the shared list', () => {
  for (const [s, want] of REDUCED) assertEquals(scrubIdentityText(s, '[X]'), want, s);
});
// stripContact writes Arabic-Indic digits as Latin ones before it reads numbers; that is the same figure, not damage.
const latin = (s: string) => s.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660)).replace(/\s+/g, ' ').trim();
const kept = (s: string, out: string) => latin(out) === latin(s);
Deno.test('MUST-KEEP: ordinary BOQ, quotation and Arabic wording is untouched by the shared list, by every scrubber and by the residual scan', () => {
  const bad: string[] = [];
  for (const s of KEEP) {
    const outs = { shared: scrubIdentityText(s, '[X]'), supplier_api: supplierScrub(s, null, []) ?? '', drawing_boq: boqScrub(s), quote_documents: maskContacts(s, [], 'en'), messages_api: stripContact(s, []) };
    for (const [who, out] of Object.entries(outs)) if (!kept(s, out)) bad.push(`${who}: "${s}" -> "${out}"`);
    // The residual's shared-list half never holds a page for trade wording (its older GENERIC_ID half is unchanged here).
    const shapes = identityShapesIn(s);
    if (shapes.length) bad.push(`residual shared-list half: "${s}" -> ${shapes.join(',')}`);
  }
  assertEquals(bad, []);
});
Deno.test("MUST-KEEP: a trade-named firm's own trade wording survives its own name scrub (saved permanently)", () => {
  const NAMES: [string, string][] = [
    ['Dubai Building Materials Trading LLC', 'All building materials supplied by contractor; building materials list attached'],
    ['Al Ain Ready Mix Concrete LLC', 'Ready mix concrete C40 pump placed 120 cum'],
    ['Al Safa Fire Safety Equipment LLC', 'Fire safety equipment as per civil defence; fire safety signage'],
    ['Modern Aluminium & Glass Works LLC', 'Aluminium, glass partitions 40 sqm; aluminium glass doors'],
    ['Gulf Steel Works LLC', 'Steel works to structural drawings; gulf steel sections'],
    ['Star Interior Decoration LLC', 'Interior decoration package; star rating'],
    ['Green Building Solutions LLC', 'Green building certification support'],
    ['Cool Air Conditioning Contracting LLC', 'Air conditioning works 2 TR ducted split; air conditioning maintenance'],
    ['Premium Joinery Works', 'premium joinery finish to all doors'],
  ];
  // Adversarial re-review D7: a one-word core that is a trade word stripped the supplier's own scope.
  NAMES.push(['Insulation Trading LLC', 'GI ductwork with insulation 85 sqm'], ['Steel Trading LLC', 'Supply of steel rebar']);
  for (const [n, s] of NAMES) assertEquals(supplierScrub(s, n, []), s, n);
  // ...while a name joined by "&" is still taken whole (C5): "Al Noor & Sons" was missed by the `[\s.,_-]*` separator.
  for (const out of [supplierScrub('Cheque payable to Al Noor & Sons only', 'Al Noor & Sons Trading LLC', []) ?? '', maskContacts('Cheque payable to Al Noor & Sons only', ['Al Noor & Sons Trading LLC'], 'en')]) assert(!out.includes('Noor'), out);
  // Across suppliers in the comparison: another supplier's name never strips this one's scope.
  const names = ['Cool Air Conditioning Contracting LLC', 'Al Waha Fire Safety Systems LLC', 'Blue Ocean Building Materials Trading'];
  for (const s of ['Supplier B: supply and install air conditioning units, 6 nos ducted split', 'Fire safety systems to civil defence approval', 'Building materials by others']) assertEquals(maskContacts(s, names, 'en'), s);
});
// Adversarial re-review R1 / R2: a pattern that backtracks exponentially kills the edge function on its CPU cap. The
// dotted BOQ line took 37.9 s through drawing_boq and residualScan (identity_contacts WEB_HOST); 20 KB with no "@" ~1 s.
Deno.test('no shape backtracks: dotted runs and long tokens scrub in well under a second', () => {
  const inputs = ['SUPPLY.AND.FIX.ALL.FLOOR.TILES.AS.PER.THE.DRAWING.AND.SPEC.WITH.ALL.ITEMS.FOR 25 sqm', 'abc.'.repeat(20), 'a'.repeat(20000), 'a.'.repeat(10000), '0-'.repeat(10000),
    'Al '.repeat(3000) + 'Trading', 'شركة '.repeat(3000), 'Regards '.repeat(3000)];
  const runs: [string, (s: string) => unknown][] = [['drawing_boq', boqScrub], ['residualScan', residualOf], ['supplier_api', (s) => supplierScrub(s, NAME, [])],
    ['quote_documents', (s) => maskContacts(s, [NAME])], ['messages_api', (s) => stripContact(s, [NAME])]];
  for (const s of inputs) for (const [who, f] of runs) {
    const t0 = performance.now(); f(s); const ms = performance.now() - t0;
    assert(ms < 1000, `${who}: ${ms.toFixed(0)} ms for ${JSON.stringify(s.slice(0, 40))}…`);
  }
});
Deno.test('MUST-KEEP: a project name is removed only whole from a Q&A answer, its ordinary words stay', () => {
  assertEquals(stripContact('The kitchen cabinets are 3.2 m long; villa has two floors; renovation starts in January.', ['Ahmed Khan'], ['Villa Kitchen Renovation']),
    'The kitchen cabinets are 3.2 m long; villa has two floors; renovation starts in January.');
  assertEquals(stripContact('Yes the office fit out includes the pantry; fit out works at night only.', ['Sara Ali'], ['Marina Office Fit Out']), 'Yes the office fit out includes the pantry; fit out works at night only.');
  assert(!stripContact('Site is ZZ Dune Heights Villa 2, see you there', ['ZZ DEMO Omar Ketbi'], ['ZZ Dune Heights Villa 2']).includes('Dune Heights'));
});
Deno.test('MUST-KEEP: a REVEALED quotation names its supplier on the party chip (EN and AR)', () => {
  const q0 = F.QUOTES[0] as unknown as { items: never[] };
  for (const name of ['Al Waha Al Thahabi Trading LLC', 'Gulf Cool Air Conditioning Contracting LLC', 'Bright Star Technical Services LLC', 'شركة النخلة الملكية للديكور ذ.م.م']) {
    for (const lang of ['en', 'ar'] as const) {
      const { body } = F.reasoned((arTexts) => ({ ...quoteDocument({ quote: q0 as never, inquiry: F.INQUIRY as never, items: q0.items ?? [], letter: 'A', lang, partyName: name, maskNames: [], arTexts }) }));
      // deno-lint-ignore no-explicit-any
      const party = ((body as any).blocks as any[]).find((b) => b.t === 'party');
      assertEquals(party?.chip, name, `${lang} ${name}`);
    }
  }
});

// ── the anonymity audit of 13 Nov 2026 (REPORT_A L4, REPORT_C L1/L3/L4): known names in their other forms ──
Deno.test('a known name in the other script, without its demo prefix, without its trade words, as initials and as a house brand', () => {
  const gone = (out: string, needle: string, what: string) => assert(!out.toLowerCase().includes(needle.toLowerCase()), `${what}: ${out}`);
  // the customer's name in Arabic when stored in Latin, and the reverse (every door: the e-mail scrub and the answer scrub)
  gone(supplierScrub('أنا عمر حداد وأحتاج إلى تبليط ثلاثة حمامات.', 'ZZ DEMO Omar Haddad', []) ?? '', 'حداد', 'Arabic of a Latin name');
  gone(stripContact('أنا عمر حداد وأحتاج إلى تبليط', ['ZZ DEMO Omar Haddad']), 'حداد', 'Arabic of a Latin name (answer)');
  gone(supplierScrub('Hi, I am Omar Haddad from Dubai', 'عمر حداد', []) ?? '', 'Haddad', 'Latin of an Arabic name');
  gone(supplierScrub('فالكون للدهانات - الدفع بشيك', 'Falcon Trading LLC', []) ?? '', 'فالكون', 'an Arabic firm with no legal form');
  // a demo account's name is tested like a real one (REPORT_C L3)
  gone(supplierScrub('Falcon premium paint, 2 coats', 'ZZ DEMO Falcon Trading LLC', []) ?? '', 'Falcon', 'demo prefix');
  // the supplier's own short name once the trade word is dropped (REPORT_C L1)
  for (const [n, t, needle] of [['Desert Brush Painting LLC', 'balance on completion - Desert Brush team', 'Desert Brush'], ['Gulf Shield Waterproofing LLC', 'Gulf Shield warranty 10 years', 'Gulf Shield'],
    ['Emirates Steel Fabrication LLC', 'Emirates Steel workshop warranty', 'Emirates Steel'], ['Al Noor Building Materials Trading LLC', 'Delivered by Al Noor trucks', 'Al Noor'],
    ['ZZ DEMO Desert Brush Painting LLC', 'We are Desert Brush, since 2012', 'Desert Brush']] as const) gone(supplierScrub(t, n, []) ?? '', needle, n);
  // initials before a code or a team, and a house brand on the name's root
  gone(supplierScrub('Ref FT-SD-04 by FT team', 'Falcon Trading LLC', []) ?? '', 'FT', 'initials');
  gone(supplierScrub('Falcolux premium emulsion', 'Falcon Trading LLC', []) ?? '', 'Falcolux', 'house brand');
  // ...and what each of those must leave: "10 ft", a lower-case trade phrase, another word
  assertEquals(supplierScrub('Ceiling height 10 FT, 2 FT x 4 FT tiles', 'Falcon Trading LLC', []), 'Ceiling height 10 FT, 2 FT x 4 FT tiles');
  assertEquals(supplierScrub('Steel works to structural drawings; gulf steel sections', 'Gulf Steel Works LLC', []), 'Steel works to structural drawings; gulf steel sections');
  assertEquals(supplierScrub('Emirates NBD is not our bank; supply to United Arab Emirates standards', 'Emirates Steel Fabrication LLC', []), '[removed] is not our bank; supply to United Arab Emirates standards');
});
Deno.test('the warranty a supplier gave survives the removal of his name (REPORT_C L4: "5 years warranty by Falcon Trading LLC" was saved as "5 █")', () => {
  for (const out of [supplierScrub('5 years warranty by Falcon Trading LLC on workmanship', 'Falcon Trading LLC', []) ?? '', scrubIdentityText('5 years warranty by Falcon Trading LLC on workmanship', '[X]'),
    maskContacts('5 years warranty by Falcon Trading LLC on workmanship', ['Falcon Trading LLC'], 'en'), stripContact('5 years warranty by Falcon Trading LLC on workmanship', ['Falcon Trading LLC'])]) {
    assert(out.startsWith('5 years warranty by '), out); assert(!out.includes('Falcon'), out); assert(out.endsWith('on workmanship'), out);
  }
  // a stranger's firm in the same shape (no known name): the shared list alone keeps the period
  assertEquals(scrubIdentityText('5 years warranty by Gulf Pipes LLC', '[X]'), '5 years warranty by [X]');
});

// lead_sourcing.ts — the deterministic parts that decide whether a sourced company becomes a lead.
//   deno test --allow-net=0 supabase/functions/marketing/lead_sourcing.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { acceptContact, businessEmail, emirateOf, extractContacts, isComplete, linkedinPerson, matchTrade, normalisePhone, type Prospect, SKIP_HOSTS, sourceLeads } from './lead_sourcing.ts';

const ALU = { code: 'aluminium', label: 'Aluminium & cladding', aliases: ['aluminium', 'aluminum', 'cladding', 'curtain wall'] };

Deno.test('exact trade or none: a neighbour category never maps', () => {
  assertEquals(matchTrade(ALU, { title: 'Gulf Facade LLC', category: 'Aluminium supplier' }), 'aluminium');
  assertEquals(matchTrade(ALU, { title: 'Emirates Curtain Wall Co', category: 'Contractor' }), 'aluminium');
  assertEquals(matchTrade(ALU, { title: 'Star Glass', category: 'Glass shop' }), null);
  assertEquals(matchTrade(ALU, { title: 'Steel Traders', category: 'Steel supplier' }), null);
});

Deno.test('UAE phones: E.164, and mobile told from landline', () => {
  assertEquals(normalisePhone('050 123 4567'), { e164: '+971501234567', kind: 'mobile' });
  assertEquals(normalisePhone('+971 4 331 2345'), { e164: '+97143312345', kind: 'landline' });
  assertEquals(normalisePhone('12345'), null);
  assertEquals(normalisePhone('+44 20 7946 0958'), null);   // not a UAE number
});

Deno.test('business email: free-mail, image names and other domains refused', () => {
  assert(businessEmail('sales@acme.ae', 'acme.ae'));
  assert(!businessEmail('acme@gmail.com', 'acme.ae'));
  assert(!businessEmail('logo@2x.png', 'acme.ae'));
  assert(!businessEmail('info@other.com', 'acme.ae'));
});

Deno.test('emirate only when the address names it', () => {
  assertEquals(emirateOf('Al Quoz 3 - Dubai - United Arab Emirates'), 'Dubai');
  assertEquals(emirateOf('Industrial Area 13 - Sharjah'), 'Sharjah');
  assertEquals(emirateOf('Riyadh, Saudi Arabia'), null);
});

Deno.test('contacts: email, mobile and a named person with a title', () => {
  const html = `<p>Call <a href="tel:+971501234567">050 123 4567</a> or 04 123 4567</p>
    <a href="mailto:sales@acme.ae">sales@acme.ae</a> <img src="logo@2x.png">
    <div><h3>Rashid Al Mansoori</h3><p>Managing Director</p></div>`;
  const c = extractContacts(html, 'acme.ae');
  assertEquals(c.emails, ['sales@acme.ae']);
  assert(c.phones.some((p) => p.e164 === '+971501234567' && p.kind === 'mobile'));
  assertEquals(c.person, { name: 'Rashid Al Mansoori', title: 'Managing Director' });
  assertEquals(extractContacts('<h2>Our Team</h2><p>Manager</p>', 'acme.ae').person, null);
  // the two false people of the 12 Oct pilot
  assertEquals(extractContacts('<p>John Doe</p><p>CEO</p>', 'acme.ae').person, null);
  assertEquals(extractContacts('<p>On Special</p><p>Partner</p>', 'acme.ae').person, null);
});

Deno.test('LinkedIn and other platforms are never crawled', () => {
  for (const h of ['linkedin.com', 'ae.linkedin.com', 'facebook.com', 'instagram.com', 'yellowpages-uae.com']) assert(SKIP_HOSTS.test(h), h);
  assert(!SKIP_HOSTS.test('acme.ae'));
});

Deno.test('complete means all eight fields and an MX-checked email', () => {
  const p: Prospect = { company_name: 'Acme', trade_code: 'aluminium', emirate: 'Dubai', website: 'https://acme.ae', domain: 'acme.ae',
    phone_e164: '+971501234567', phone_kind: 'mobile', email: 'sales@acme.ae', email_status: 'mx_ok', contact_name: 'Rashid Al Mansoori',
    contact_title: 'Managing Director', place_id: '1', query: 'q', field_sources: {} };
  assert(isComplete(p));
  assert(!isComplete({ ...p, email_status: 'mx_nxdomain' }));
  assert(!isComplete({ ...p, trade_code: null }));
});

Deno.test('sourcing: LinkedIn website is dropped, untraded places are not crawled, credits counted', async () => {
  const r = await sourceLeads({ serperKey: 'x', trades: [ALU], emirate: 'Dubai', pagesPerQuery: 1, maxSites: 0, deadlineMs: 5000,
    fetchSerper: (_path) => Promise.resolve({ credits: 3, places: [
      { title: 'Acme Aluminium', category: 'Aluminium supplier', address: 'Dubai', website: 'https://www.linkedin.com/company/acme', phoneNumber: '04 331 2345', cid: '1' },
      { title: 'Star Glass', category: 'Glass shop', address: 'Dubai', website: 'https://star.ae', cid: '2' },
    ] }) });
  assertEquals(r.serper_credits, 3);
  assertEquals(r.prospects[0].website, null);
  assertEquals(r.prospects[0].field_sources.phone_e164?.startsWith('serper:places'), true);
  assertEquals(r.prospects[1].trade_code, null);
  assertEquals(r.sites_crawled, 0);
});

Deno.test('the model is held to the page: a name not in the text is refused', () => {
  const pages = [{ url: 'https://acme.ae/about', text: 'Founded by Rashid Al Mansoori, our Managing Director.' }];
  assertEquals(acceptContact('{"name":"Rashid Al Mansoori","title":"Managing Director","real":true,"url":"https://acme.ae/about"}', pages),
    { name: 'Rashid Al Mansoori', title: 'Managing Director', url: 'https://acme.ae/about' });
  assertEquals(acceptContact('{"name":"Invented Person","title":"CEO","real":true,"url":"https://acme.ae/about"}', pages), null);
  assertEquals(acceptContact('{"name":"Rashid Al Mansoori","title":"Managing Director","real":false}', pages), null);
  assertEquals(acceptContact('not json', pages), null);
});

Deno.test('LinkedIn result titles: the person only when the company and a title word match', () => {
  assertEquals(linkedinPerson('Pir Arkam - Founder & CEO - Proto21 3D Printing LLC | LinkedIn', 'Proto21 3D Printing LLC'),
    { name: 'Pir Arkam', title: 'Founder & CEO' });
  assertEquals(linkedinPerson('Jane Smith - Sales Manager - Other Company | LinkedIn', 'Proto21 3D Printing LLC'), null);
  assertEquals(linkedinPerson('Proto21 3D Printing LLC | LinkedIn', 'Proto21 3D Printing LLC'), null);
  assertEquals(linkedinPerson('Pir Arkam - Founder & CEO at Proto21 3D Printing | LinkedIn', 'Proto21 3D Printing LLC'), { name: 'Pir Arkam', title: 'Founder & CEO' });
});

Deno.test('LinkedIn titles as Google returned them in the 12 Oct pilot (RTL marks, "@", "...")', () => {
  assertEquals(linkedinPerson('‏Ajil AR‏ - ‏Key account Manager @ Abradant International', 'Abradant International'),
    { name: 'Ajil AR', title: 'Key account Manager' });
  assertEquals(linkedinPerson('MD Jamsher Alam‏ - ‏Founder & CEO @Orbit3D | 3D Design', 'Orbit3D Printing Co. LLC'),
    { name: 'MD Jamsher Alam', title: 'Founder & CEO' });
  assertEquals(linkedinPerson('Rizwana Razak - ACCOUNTANT | SAP FICO | ZOHO BOOKS', 'Right Way Accounting & Auditing'), null);
  assertEquals(linkedinPerson('Shibu Mathew - Administrator at AL YOUSUF GENERAL ...', 'AL YOUSUF GENERAL TRADING LLC'), null);   // not a title we accept
});
Deno.test('a non-Latin honorific is dropped from a LinkedIn name', () => { assertEquals(linkedinPerson('HANKUK LEE 님 - Chief Executive Officer - Layerlab', 'Layerlab 3D Printing'), { name: 'HANKUK LEE', title: 'Chief Executive Officer' }); });

Deno.test('spend caps: no Serper call past the credit cap, no model call past the USD cap', async () => {
  let calls = 0;
  const none = await sourceLeads({ serperKey: 'x', trades: [ALU], emirate: 'Dubai', pagesPerQuery: 3, maxSites: 0, deadlineMs: 5000,
    maxSerperCredits: 0, fetchSerper: () => { calls++; return Promise.resolve({ credits: 1, places: [] }); } });
  assertEquals([calls, none.queries], [0, 0]);
  const one = await sourceLeads({ serperKey: 'x', trades: [ALU, ALU], emirate: 'Dubai', pagesPerQuery: 3, maxSites: 0, deadlineMs: 5000,
    maxSerperCredits: 2, fetchSerper: () => { calls++; return Promise.resolve({ credits: 2, places: Array(10).fill({ title: 'x', cid: String(Math.random()) }) }); } });
  assertEquals(one.queries, 1);   // the first call spent the cap; nothing after it
});

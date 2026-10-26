// gaeb fixtures — a small GAEB DA XML 3.2 BoQ whose items are known by construction.
// Imported by gaeb.test.ts and by the before/after audit; pure, no I/O.
//
// gaebFixture(): X83 bid request. Category 01 Earthworks: 01.0010 Excavation 120.5 m3, 01.0020
// Backfilling 80 m3. Category 02 Tiling (Arabic label): 02.0010 porcelain tiles 250.75 m2 with Arabic
// outline text. gaebX84Fixture(): the same BoQ as an X84 bid carrying unit prices, item totals and a
// BoQ total. The price values are distinctive (313.13, 7777.77, 99999.99 ...) so a test can prove
// none of them reaches the reader's output.
export const GAEB_PRICES = ['313.13', '37732.17', '424.24', '33939.20', '515.15', '129173.86', '99999.99'];

function build(dp: '83' | '84'): string {
  const priced = dp === '84';
  const pr = (up: string, it: string) => (priced ? `<UP>${up}</UP><IT>${it}</IT>` : '');
  const item = (rno: string, qty: string, qu: string, txt: string, up: string, it: string) =>
    `<Item RNoPart="${rno}"><Qty>${qty}</Qty><QU>${qu}</QU>${pr(up, it)}<Description><CompleteText>` +
    `<DetailTxt><Text><p><span>${txt} — full specification.</span></p></Text></DetailTxt>` +
    `<OutlineText><OutlTxt><TextOutlTxt><p><span>${txt}</span></p></TextOutlTxt></OutlTxt></OutlineText>` +
    `</CompleteText></Description></Item>`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA${dp}/3.2">
<GAEBInfo><Version>3.2</Version><ProgSystem>ZZ DEMO</ProgSystem></GAEBInfo>
<PrjInfo><NamePrj>ZZ DEMO Villa</NamePrj></PrjInfo>
<Award><DP>${dp}</DP><BoQ><BoQInfo><Name>ZZ-DEMO-01</Name><LblTx>ZZ DEMO Villa fit-out</LblTx>${priced ? '<Totals><Total>99999.99</Total></Totals>' : ''}</BoQInfo>
<BoQBody>
<BoQCtgy RNoPart="01"><LblTx><p><span>Earthworks</span></p></LblTx><BoQBody><Itemlist>
${item('0010', '120.500', 'm3', 'Excavation for footings', '313.13', '37732.17')}
${item('0020', '80.000', 'm3', 'Backfilling in layers', '424.24', '33939.20')}
</Itemlist></BoQBody></BoQCtgy>
<BoQCtgy RNoPart="02"><LblTx><p><span>أعمال البلاط / Tiling</span></p></LblTx><BoQBody><Itemlist>
${item('0010', '250.750', 'm2', 'Porcelain floor tiles 600x600 بلاط أرضيات بورسلين', '515.15', '129173.86')}
</Itemlist></BoQBody></BoQCtgy>
</BoQBody></BoQ></Award>
</GAEB>
`;
}

export const gaebFixture = (): Uint8Array => new TextEncoder().encode(build('83'));
export const gaebX84Fixture = (): Uint8Array => new TextEncoder().encode(build('84'));

// A JSON RESPONSE WITH NO CORS HEADERS: the one definition (it_engineer, 10 Nov 2026).
//
// Measured 10 Nov 2026: this exact arrow, `J(o, s = 200)` -> `new Response(JSON.stringify(o), { status: s, headers:
// { 'Content-Type': 'application/json' } })`, was written out in 18 edge functions (TD-04 in
// docs/engineering/tech-debt.md, which counted 65 copies of a JSON helper across every variant). Those 18 now import it
// from here. The other variants are NOT this function and were left where they are: 22 more spread the function's own
// `CORS` constant into the headers, and those constants differ from function to function, so merging them would change
// which origins each function answers. docs/engineering/duplicated-helpers.md lists every variant.
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

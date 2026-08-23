import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_section8_security_probes.mjs';
let s = readFileSync(f, 'utf8');

// A SCAN WITH NOTHING TO FIND IS NOT A REFUSAL.
//
// P3-supplier-surface-body reads three supplier-facing bodies and looks for two known customer
// identities. Its own observed text has always said what it is bounded by — "0 inquiries exist, so
// this proves the surfaces carry no identity and the direct table is unreachable, NOT that a
// populated payload is masked" — and it nevertheless recorded REFUSED_AS_REQUIRED, so
// PD-PRIV-004 read as refused on evidence that says it cannot support that. A zero-population pass
// is the one thing this whole harness exists to refuse.
//
// The verdict now depends on whether there was anything to find. Where the supplier-facing surface
// has no inquiry behind it at all, the probe reports NOT_DISCRIMINATED — a verdict the table's own
// CHECK already allows — and the deliverable carries that instead of a green it did not earn.
// Nothing about the assertion is weakened: a leak still reports NOT_REFUSED whatever the population.
const OLD = `    record('P3-supplier-surface-body', 'supplier reads raw customer identity from a supplier surface',
      hits.length === 0 ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',`;
const NEW = `    // Is there an identity to find at all? An inquiry is what carries one onto a supplier surface,
    // and creating one is forbidden while the automation hold stands, so this is measured rather
    // than assumed.
    const pop = (await sql(\`select (select count(*) from public.inquiries)       as inquiries,
                                   (select count(*) from public.inquiry_matches) as matches\`))[0];
    const anythingToFind = Number(pop.inquiries) > 0 && Number(pop.matches) > 0;

    record('P3-supplier-surface-body', 'supplier reads raw customer identity from a supplier surface',
      hits.length > 0 ? 'NOT_REFUSED' : (anythingToFind ? 'REFUSED_AS_REQUIRED' : 'NOT_DISCRIMINATED'),`;
if (!s.includes(OLD)) throw new Error('P3 verdict anchor not found');
s = s.split(OLD).join(NEW);

// and the observed text states the population it was decided on
const OLDT = `Bodies scanned for the two known customer identities: \${hits.length === 0 ? 'no identity value appeared in any body' : 'LEAKED ' + hits.join(', ')}. BOUNDED: 0 inquiries exist, so this proves the surfaces carry no identity and the direct table is unreachable, NOT that a populated payload is masked\`, inbox.status);`;
const NEWT = `Bodies scanned for the two known customer identities: \${hits.length === 0 ? 'no identity value appeared in any body' : 'LEAKED ' + hits.join(', ')}. POPULATION: \${pop.inquiries} inquiry/inquiries and \${pop.matches} match(es) exist, so this \${anythingToFind ? 'discriminates a masked payload from a leaked one' : 'proves the surfaces carry no identity and the direct table is unreachable, and CANNOT show that a populated payload is masked — an inquiry is what puts an identity on a supplier surface and creating one is forbidden while the automation hold stands'}\`, inbox.status);`;
if (!s.includes(OLDT)) throw new Error('P3 text anchor not found');
s = s.split(OLDT).join(NEWT);

writeFileSync(f, s);
console.log('patched');

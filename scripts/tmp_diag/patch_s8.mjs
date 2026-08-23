import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_section8_security_probes.mjs';
let s = readFileSync(f, 'utf8');

// ---- 1. GIVE EACH SUPPLIER A DOCUMENT, OR THE CROSS-TENANT PROBE PROVES NOTHING ----------------
const OLD_FIX = `           ('ZZ DEMO — section 8 probe supplier B', \${lit(EMAIL.supB)}, true, \${lit(EMAIL.supB)}, false, 'pending', 'zz_phase_d_section8', 'supplier');\`);`;
const NEW_FIX = `           ('ZZ DEMO — section 8 probe supplier B', \${lit(EMAIL.supB)}, true, \${lit(EMAIL.supB)}, false, 'pending', 'zz_phase_d_section8', 'supplier');\`);

  // PD-AUTH-002 (23 Aug 2026). THE PROBE THAT COULD NOT DISCRIMINATE.
  //
  // P2-document-scope compared supplier A's documents response with the same call naming supplier
  // B's id and found the two byte-identical. Both fixtures held ZERO documents, so an identical
  // pair was the only possible answer and it answered nothing: a scope that leaked and a scope that
  // held would both return the same empty body. That is why the defect was recorded
  // NOT_DISCRIMINATED rather than REFUSED.
  //
  // Each supplier now carries ONE document of its own, with a path that names the supplier it
  // belongs to, so A's body must contain A's path and must NOT contain B's. supplier_portal derives
  // every document path from the leads row resolved through claimed_by on the JWT, so the paths are
  // set on the leads rows the cleanup already deletes; no storage object is created, nothing is
  // uploaded, and no new table is written.
  await sql(\`
    update public.leads set license_doc_path = 'zz-phase-d-section8/supplier-a/licence-A.pdf'
     where claimed_by = \${lit(EMAIL.supA)};
    update public.leads set license_doc_path = 'zz-phase-d-section8/supplier-b/licence-B.pdf'
     where claimed_by = \${lit(EMAIL.supB)};\`);`;
if (!s.includes(OLD_FIX)) throw new Error('fixture anchor not found');
s = s.split(OLD_FIX).join(NEW_FIX);

// ---- 2. THE ASSERTION NOW HAS TWO SIDES ---------------------------------------------------------
const OLD_P2 = `    const docsA = await fn('supplier_portal', tok.supA, { action: 'documents' });
    const docsCross = await fn('supplier_portal', tok.supA, { action: 'documents', id: ids.supB, leads_id: ids.supB, supplier_id: ids.supB });
    const same = docsA.text === docsCross.text;
    const mentionsB = docsCross.text.includes('probe supplier B') || docsCross.text.includes(EMAIL.supB);
    record('P2-document-scope', "supplier A reads supplier B's documents",
      same && !mentionsB ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      \`supplier_portal documents as A -> \${docsA.status}; the same call naming B's id -> \${docsCross.status} and the two bodies are \${same ? 'IDENTICAL' : 'DIFFERENT'}; B's identity \${mentionsB ? 'APPEARS' : 'does not appear'} in the cross-tenant response\`, docsCross.status);`;
const NEW_P2 = `    const docsA = await fn('supplier_portal', tok.supA, { action: 'documents' });
    const docsCross = await fn('supplier_portal', tok.supA, { action: 'documents', id: ids.supB, leads_id: ids.supB, supplier_id: ids.supB });
    const same = docsA.text === docsCross.text;
    const mentionsB = docsCross.text.includes('probe supplier B') || docsCross.text.includes(EMAIL.supB);

    // THE POSITIVE HALF, without which the negative half is vacuous: A's own document must be in
    // A's own body. If it is not, an empty response would score as a refusal.
    const A_PATH = 'zz-phase-d-section8/supplier-a/licence-A.pdf';
    const B_PATH = 'zz-phase-d-section8/supplier-b/licence-B.pdf';
    const ownVisible = docsA.text.includes(A_PATH);
    const bLeaked = docsA.text.includes(B_PATH) || docsCross.text.includes(B_PATH);

    // AND THE DIRECT REQUEST. supplier_portal accepts no caller-supplied path, so naming B's file
    // explicitly is the sharpest form of the question the defect asks.
    const byPath = await fn('supplier_portal', tok.supA, { action: 'documents', path: B_PATH, doc_path: B_PATH });
    const byPathLeaked = byPath.text.includes(B_PATH);

    record('P2-document-scope', "supplier A reads supplier B's documents",
      ownVisible && !bLeaked && !byPathLeaked && same && !mentionsB ? 'REFUSED_AS_REQUIRED' : 'NOT_REFUSED',
      \`each supplier holds ONE document of its own. supplier_portal documents as A -> \${docsA.status} and \${ownVisible ? 'DOES' : 'DOES NOT'} carry A's own path; the same call naming B's id -> \${docsCross.status}, bodies \${same ? 'IDENTICAL' : 'DIFFERENT'}; naming B's path directly -> \${byPath.status}. B's path \${bLeaked || byPathLeaked ? 'LEAKED' : 'appears in none of the three responses'} and B's identity \${mentionsB ? 'APPEARS' : 'does not appear'}. The caller-supplied id and path are both discarded: every path is derived from the leads row claimed_by resolves on the JWT\`, docsCross.status);`;
if (!s.includes(OLD_P2)) throw new Error('P2 anchor not found');
s = s.split(OLD_P2).join(NEW_P2);

writeFileSync(f, s);
console.log('patched');

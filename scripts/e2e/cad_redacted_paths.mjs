// What a CAD drawing (DXF, binary DXF or DWG) records for suppliers since #1056 (29 Sep 2026): ONE drawn preview
// page (drawing_redact mode 'cad', `<prefix>_p0.jpg`) and, when its own verifier proved it, the anonymised drawing
// FILE beside it (mode 'file', `<prefix>_drawing.dxf`) - never instead of the preview, never anything else.
// The journeys asserted "exactly one path" until 18 Oct 2026 and failed on every correct run (2 paths). Works on
// stored paths and on the signed URLs the supplier inbox serves (the path, then a ?token query).
// Assigned: it_engineer. Prevented by: scripts/checks/a_cad_drawing_reaches_a_supplier_drawn_without_its_identity.test.mjs
export function cadRedactionShape(paths) {
  const list = (Array.isArray(paths) ? paths : []).map((p) => String(p).split('?')[0]);
  const previews = list.filter((p) => /_p0\.jpg$/.test(p)).length;
  const files = list.filter((p) => /_drawing\.dxf$/.test(p)).length;
  return { previews, files, ok: previews === 1 && files <= 1 && previews + files === list.length, detail: `${previews} preview page(s), ${files} anonymised file(s), ${list.length} path(s)` };
}

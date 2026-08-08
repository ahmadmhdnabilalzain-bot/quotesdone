// Generate public/models/supplier-warehouse.gltf — a valid glTF 2.0 asset, authored here rather
// than downloaded, so the repo owns every byte of it and nobody has to wonder about its licence.
//
// ── WHY A GENERATED MODEL AND NOT A REAL ONE ────────────────────────────────────────────────────
// §23 asks that the supplier surface load a 3D model through the GLTF pipeline. The pipeline is the
// requirement; the artwork is not. A generated warehouse shell proves the loader, the asset path,
// the buffer encoding and the material — and it is honest about being a primitive rather than
// pretending to be a scanned facility. A real modelled asset is still worth having and is recorded
// as outstanding; this is not a substitute for one, it is the pipeline it will arrive through.
//
// ── THE GEOMETRY IS DRIVEN BY A REAL DIMENSION ──────────────────────────────────────────────────
// The shell's footprint is 1x1 in model space and the surface scales it by the supplier's own
// warehouse_area, so the box a supplier sees is the size of the warehouse they told us about. A
// model whose proportions mean nothing would be decoration; this one carries one real fact.
//
//   node scripts/gen_warehouse_gltf.mjs
import { mkdirSync, writeFileSync } from 'node:fs';

// A warehouse shell: a unit box with a pitched roof. Positions only — glTF says a client must
// compute flat normals when NORMAL is absent, which is the correct look for an untextured shell.
const H = 0.6;          // wall height
const R = 1.0;          // ridge height
const v = [
  // floor (y=0)
  [-0.5, 0, -0.5], [0.5, 0, -0.5], [0.5, 0, 0.5], [-0.5, 0, 0.5],
  // eaves (y=H)
  [-0.5, H, -0.5], [0.5, H, -0.5], [0.5, H, 0.5], [-0.5, H, 0.5],
  // ridge line (y=R), running along z
  [0, R, -0.5], [0, R, 0.5],
];
const tri = [
  // walls
  0, 1, 5, 0, 5, 4,
  1, 2, 6, 1, 6, 5,
  2, 3, 7, 2, 7, 6,
  3, 0, 4, 3, 4, 7,
  // gable ends
  4, 5, 8, 7, 9, 6,
  // roof slopes
  4, 8, 9, 4, 9, 7,
  5, 6, 9, 5, 9, 8,
  // floor
  0, 3, 2, 0, 2, 1,
];

// One interleaved-free buffer: indices (uint16) then positions (float32), each view 4-byte aligned.
const idx = new Uint16Array(tri);
const idxBytes = Buffer.from(idx.buffer);
const pad = (idxBytes.length % 4) === 0 ? 0 : 4 - (idxBytes.length % 4);
const pos = new Float32Array(v.flat());
const buf = Buffer.concat([idxBytes, Buffer.alloc(pad), Buffer.from(pos.buffer)]);

const min = [0, 1, 2].map((i) => Math.min(...v.map((p) => p[i])));
const max = [0, 1, 2].map((i) => Math.max(...v.map((p) => p[i])));

const gltf = {
  asset: { version: '2.0', generator: 'QuotesDone scripts/gen_warehouse_gltf.mjs (row #5 §23)' },
  scene: 0,
  scenes: [{ nodes: [0], name: 'SupplierWarehouse' }],
  nodes: [{ mesh: 0, name: 'WarehouseShell' }],
  meshes: [{
    name: 'WarehouseShell',
    primitives: [{ attributes: { POSITION: 1 }, indices: 0, material: 0 }],
  }],
  materials: [{
    name: 'Shell',
    pbrMetallicRoughness: {
      baseColorFactor: [0.42, 0.55, 0.68, 1],
      metallicFactor: 0.1,
      roughnessFactor: 0.85,
    },
    doubleSided: true,
  }],
  accessors: [
    { bufferView: 0, componentType: 5123, count: idx.length, type: 'SCALAR' },
    { bufferView: 1, componentType: 5126, count: v.length, type: 'VEC3', min, max },
  ],
  bufferViews: [
    { buffer: 0, byteOffset: 0, byteLength: idxBytes.length, target: 34963 },
    { buffer: 0, byteOffset: idxBytes.length + pad, byteLength: pos.byteLength, target: 34962 },
  ],
  buffers: [{ byteLength: buf.length, uri: 'data:application/octet-stream;base64,' + buf.toString('base64') }],
};

mkdirSync('public/models', { recursive: true });
writeFileSync('public/models/supplier-warehouse.gltf', JSON.stringify(gltf, null, 2));

// Assert what a loader will assert, here, where the failure is readable — rather than as a blank
// canvas in a browser. Every index must address a real vertex and every triangle must be complete.
const bad = tri.filter((i) => i < 0 || i >= v.length);
if (bad.length) throw new Error('index out of range: ' + bad.join(','));
if (tri.length % 3 !== 0) throw new Error('index count is not a whole number of triangles');
console.log(`public/models/supplier-warehouse.gltf  ${v.length} vertices, ${tri.length / 3} triangles, ${buf.length} buffer bytes`);

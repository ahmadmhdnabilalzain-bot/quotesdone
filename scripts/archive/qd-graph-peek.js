const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..');
const g = JSON.parse(fs.readFileSync(path.join(ROOT, 'graphify-out', 'graph.json'), 'utf8'));
for (const key of Object.keys(g)) {
  const v = g[key];
  const shape = Array.isArray(v) ? `array[${v.length}]`
    : (v && typeof v === 'object') ? `object{${Object.keys(v).slice(0, 12).join(',')}}`
    : JSON.stringify(v).slice(0, 100);
  console.log(key, '=', shape);
}
if (Array.isArray(g.nodes) && g.nodes.length) {
  console.log('\nSAMPLE NODE:', JSON.stringify(g.nodes[0]).slice(0, 500));
}
if (Array.isArray(g.edges) && g.edges.length) {
  console.log('\nSAMPLE EDGE:', JSON.stringify(g.edges[0]).slice(0, 300));
}

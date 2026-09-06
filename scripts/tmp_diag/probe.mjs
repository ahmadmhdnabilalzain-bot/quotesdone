// Run a plpgsql DO block that ends in `raise exception 'MARK<<...>>'` and print what it carried.
// The raise is what rolls the transaction back, so a probe leaves nothing behind.
import { q } from './q.mjs';
import { readFileSync } from 'node:fs';

export async function probe(body, marker = 'PROBE') {
  try {
    await q(body);
    return '(no marker — the block did not raise)';
  } catch (e) {
    const m = String(e.message);
    const a = m.indexOf(marker + '<<');
    if (a >= 0) return m.slice(a + marker.length + 2, m.indexOf('>>', a));
    return 'ERROR: ' + m.slice(0, 3000);
  }
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop())) {
  const body = readFileSync(process.argv[2] || 0, 'utf8');
  console.log(await probe(body, process.argv[3] || 'PROBE'));
}

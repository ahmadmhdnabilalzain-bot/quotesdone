// Summarise scripts/tmp_diag/reason_census.txt by refusal class. The census file carries literal
// backslash-n sequences (the transport is JSON source), so both forms are normalised here.
import { readFileSync } from 'node:fs';
const raw = readFileSync(process.argv[2] || 'scripts/tmp_diag/reason_census.txt', 'utf8')
  .replace(/\\n/g, '\n').replace(/\\"/g, '"');
const blocks = raw.split(/^--- /m);
const reasons = [];
for (const b of blocks.slice(1)) {
  const lines = b.split('\n').filter(l => !l.startsWith('CONTEXT:') && l.trim() !== '"}' && l.trim() !== '');
  const head = lines[0] || ''; const m = head.match(/^(W\d\d-S\d\d) (\S+) ?(\S*)/); if (!m) continue;
  reasons.push({ step: m[1], outcome: m[2], code: m[3] || '', reason: lines.slice(1).join(' ').replace(/\s+/g, ' ').trim() });
}
const byCode = {};
for (const r of reasons) (byCode[r.code] ||= []).push(r);
const full = process.argv.includes('--full');
for (const [code, rs] of Object.entries(byCode).sort((a, b) => b[1].length - a[1].length)) {
  console.log(`\n===== ${code} (${rs.length})`);
  const sig = {};
  for (const r of rs) {
    const s = r.reason.replace(/[0-9a-f]{8}-[0-9a-f-]{27}/g, '<uuid>').replace(/\b\d{2,}\b/g, '<n>').slice(0, full ? 1200 : 300);
    (sig[s] ||= []).push(r.step);
  }
  for (const [s, steps] of Object.entries(sig)) console.log(`  [${steps.length}] ${steps.join(' ')}\n      ${s}`);
}

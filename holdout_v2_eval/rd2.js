const fs = require('fs');
const s = fs.readFileSync('supabase/functions/supplier_api/index.ts', 'utf8');
const i = s.indexOf('async function setRegistration');
console.log('=== setRegistration ===');
console.log(s.slice(i, i + 1700));
const j = s.indexOf('registration_status');
console.log('\n=== occurrences of registration_status / fee_due ===');
for (const m of s.matchAll(/registration_(status|fee_due)/g)) {
  const a = Math.max(0, m.index - 160);
  console.log('...' + s.slice(a, m.index + 90).replace(/\s+/g, ' ') + '\n');
}

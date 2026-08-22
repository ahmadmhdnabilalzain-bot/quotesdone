import { readFileSync, writeFileSync } from 'node:fs';
const p = 'docs/phase-d/PHASE_D_BUILDER_CLOSURE.md';
let s = readFileSync(p, 'utf8');

// remove the mangled block written by a shell heredoc that ate every backtick
const start = s.indexOf('**The rule body, quoted, so the next session does not have to re-derive it.**');
const end = s.indexOf('### Still open after this session, itemised');
if (start < 0 || end < 0 || end < start) { console.error('anchors missing'); process.exit(1); }

const block = [
  '**The rule body, quoted, so the next session does not have to re-derive it.** `fn_phase_d_rule_check`,',
  'BR-012:',
  '',
  '```sql',
  'select count(*) into v_n from public.phase_d_object_record o',
  " where o.object_id = 'supplier_safe_package' and o.state = 'approved' and o.superseded_by is null",
  "   and (o.business_key = v_txt or 'supplier_safe_package:' || o.business_key = v_txt);",
  '```',
  '',
  "`v_txt` is `p_context->>'safe_package_ref'`. So that context key must carry the OBJECT-STORE key, in",
  'either the bare or the `<object>:`-prefixed form — and the factory contributes the relation row id.',
  'BR-026 and BR-035 have the same shape against `customer_terms_acceptance` and the',
  '`IMMUTABLE_REVISION` family. BR-013 and BR-015 do not: their refusals name `public.inquiries` and',
  '`public.leads`, and they want the relation key they already get.',
  '',
  'Three routes were considered and none is a one-liner, which is why this is a named increment rather',
  'than a guess:',
  '',
  '- **(a) contribute the object-store key for those four refs only.** Correct today, and a per-key',
  '  list that goes stale the moment a rule changes which store it reads.',
  '- **(b) key `phase_d_object_record` by the relation row id.** One shape everywhere — and it',
  '  destroys the replay determinism the md5-derived key exists for, because a relation id is new on',
  '  every drive and a replay would then create a second record instead of colliding with itself.',
  '- **(c) give the object record an alias column carrying the relation id and widen the lookups.**',
  '  General, and it edits rule bodies, which is the one thing that must not be done casually.',
  '',
  'The choice belongs to whoever has the budget to prove it by execution rather than by argument.',
  '',
].join('\n');

s = s.slice(0, start) + block + s.slice(end);
writeFileSync(p, s);
console.log('rewrote the block cleanly');

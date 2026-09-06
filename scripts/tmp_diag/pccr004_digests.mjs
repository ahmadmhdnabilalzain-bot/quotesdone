// Computes the digests PCCR-004's amendment table must state. Reads only; writes nothing.
import { sql } from '../phase_b/lib/db.mjs';
import { createHash } from 'node:crypto';
const sha = s => createHash('sha256').update(s, 'utf8').digest('hex');

const [{ prosrc, fd }] = await sql(
  `select p.prosrc, encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') fd
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_kernel_cancel'`);
const [{ digest: frozen }] = await sql(
  `select digest from public.phase_c_frozen_subject where subject = 'canonical_cancellation_service'`);

console.log('frozen digest recorded   ', frozen);
console.log('live functiondef sha256  ', fd, fd === frozen ? '(MATCHES — undrifted)' : '(DRIFTED)');

// The proposed body, spliced exactly as scripts/tmp_diag/gen_j02.mjs splices it. It is built here
// so its digest can be STATED in the change request; it is not written and not applied.
const MARK = '  -- ---- (a) the command ';
const at = prosrc.indexOf(MARK);
if (at < 0) throw new Error('the (a) anchor is not in the live body; regenerate the amendment');
const src = await import('node:fs').then(m => m.readFileSync('scripts/tmp_diag/gen_j02.mjs', 'utf8'));
console.log('gen_j02.mjs sha256       ', sha(src));
console.log('live prosrc length       ', prosrc.length, 'characters');
console.log('anchor (a) at            ', at);

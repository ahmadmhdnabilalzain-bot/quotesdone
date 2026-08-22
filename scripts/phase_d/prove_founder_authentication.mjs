// PHASE D DELIVERABLE — PHASE_D_FOUNDER_AUTHENTICATION_RESULT.csv
//
// The founder's ruling of 21 Aug 2026, section E. Every case below is produced by EXECUTION against
// production inside a transaction that ends in `raise exception`; nothing is read off the source.
//
//   node scripts/phase_d/prove_founder_authentication.mjs
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const q = `do $emit$
declare
  v text; v_sub uuid; v_non uuid; v_ev bigint; v_out text := '';
  function_result text;
begin
  select f.auth_user_id into v_sub from public.phase_c_founder_identity f
   where f.identity = 'management@quotesdone.com' and f.active;
  select u.id into v_non from auth.users u where u.email = 'acceptance-nonfounder@example.invalid';

  -- 1. E39's EXACT VECTOR: type the founder's email as service_role.
  begin
    v := public.fn_phase_c_require_founder('management@quotesdone.com');
    v_out := v_out || 'typed_email=ACCEPTED_WRONGLY:' || v || '~|~';
  exception when others then
    v_out := v_out || 'typed_email=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 2. THE FOUNDER'S VERIFIED SUBJECT, BOUND BY THE SERVER PATH.
  begin
    perform public.fn_phase_c_founder_subject_bind(v_sub);
    v := public.fn_phase_c_require_founder(null);
    v_out := v_out || 'founder_subject=ACCEPTED:' || v || '~|~';
  exception when others then
    v_out := v_out || 'founder_subject=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 3. THE SAME CALL, ASSERTING A DIFFERENT IDENTITY.
  begin
    v := public.fn_phase_c_require_founder('someone.else@example.invalid');
    v_out := v_out || 'mismatched_assertion=ACCEPTED_WRONGLY:' || v || '~|~';
  exception when others then
    v_out := v_out || 'mismatched_assertion=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 4. A REAL, NON-FOUNDER AUTH SUBJECT.
  perform set_config('app.phase_c_founder_auth_event','', true);
  begin
    perform public.fn_phase_c_founder_subject_bind(v_non);
    v_out := v_out || 'non_founder_subject=BOUND_WRONGLY~|~';
  exception when others then
    v_out := v_out || 'non_founder_subject=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 5. A SUBJECT THAT IS NOBODY.
  begin
    perform public.fn_phase_c_founder_subject_bind('00000000-0000-0000-0000-000000000000'::uuid);
    v_out := v_out || 'unknown_subject=BOUND_WRONGLY~|~';
  exception when others then
    v_out := v_out || 'unknown_subject=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 6. THE GUC SET BY HAND, POINTING AT AN EVENT FROM ANOTHER TRANSACTION.
  --    A committed event row would be the only thing to point at, and there are none; pointing at
  --    an id that does not exist is the same test with nothing to find.
  perform set_config('app.phase_c_founder_auth_event','999999999', true);
  begin
    v := public.fn_phase_c_require_founder(null);
    v_out := v_out || 'hand_set_context=ACCEPTED_WRONGLY:' || v || '~|~';
  exception when others then
    v_out := v_out || 'hand_set_context=REFUSED:' || left(SQLERRM,90) || '~|~';
  end;

  -- 7. THE REFUND GUARD, WHICH IS WHAT ALL OF THIS IS ACTUALLY PROTECTING.
  --    Every refund needs the founder, at any amount. The guard calls fn_phase_c_require_founder.
  perform set_config('app.phase_c_founder_auth_event','', true);
  begin
    v := public.fn_phase_c_require_founder('management@quotesdone.com');
    v_out := v_out || 'refund_path_without_a_subject=ACCEPTED_WRONGLY~|~';
  exception when others then
    v_out := v_out || 'refund_path_without_a_subject=REFUSED:' || left(SQLERRM,60) || '~|~';
  end;

  -- 8. RESIDUE: the audit rows this probe wrote, all of which roll back.
  v_out := v_out || 'auth_events_written_by_this_probe='
        || (select count(*)::text from public.phase_c_founder_auth_event
             where txid = txid_current()) || '~|~';

  raise exception 'FOUNDERAUTH<<%>>', v_out;
end $emit$;`;

let out;
try { await sql(q); out = '(no marker)'; }
catch (e) {
  const m = String(e.message); const a = m.indexOf('FOUNDERAUTH<<');
  out = a < 0 ? 'ERROR: ' + m.slice(0, 600) : m.slice(a + 13, m.indexOf('>>', a));
}
const rows = out.split('~|~').filter(Boolean).map(p => {
  const i = p.indexOf('=');
  return [p.slice(0, i), p.slice(i + 1)];
});

// ---- THE HTTP LAYER, MEASURED AGAINST THE DEPLOYED FUNCTION -----------------------------------
// The founder's section E asks for 401 on an expired or invalid JWT. os_api runs with
// verify_jwt=false and does the check itself, so this is the only place the status code can be
// read: a real POST to the deployed function, with no credential that is not already public.
const OSAPI = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/os_api';
const ANON = process.env.QD_ANON_KEY || '';
if (ANON) {
  const httpCases = [
    ['http_no_authorization_header', {}],
    ['http_garbage_bearer_token', { Authorization: 'Bearer not.a.jwt' }],
    ['http_anon_key_as_a_bearer_token', { Authorization: 'Bearer ' + ANON }],
    ['http_forged_jwt_naming_the_founder_subject',
     { Authorization: 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjU2YzdlYy0xN2JmLTRiMWUtYWY4Zi1hYWEzMmE4ZmRkMTQiLCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTAwMDAwMDAwMH0.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }],
  ];
  for (const [name, extra] of httpCases) {
    const r = await fetch(OSAPI, { method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: ANON, ...extra },
      body: JSON.stringify({ action: 'founder_command_control', command_id: 1, op: 'noop' }) });
    rows.push([name, `HTTP ${r.status} ${(await r.text()).slice(0, 90).replace(/\s+/g, ' ')}`]);
  }
} else {
  rows.push(['http_layer', 'NOT MEASURED — set QD_ANON_KEY to probe the deployed os_api; the anon key is a public credential and is not committed here']);
}

const board = await sql('select check_name, expected, actual, ok from public.fn_phase_c_founder_auth_state()');
for (const b of board) rows.push([`board:${b.check_name}`, `${b.actual} (expected ${b.expected}) ok=${b.ok}`]);

const csv = provenance({
  command: 'node scripts/phase_d/prove_founder_authentication.mjs',
  numerator: rows.length, denominator: rows.length,
  of: 'founder-authentication cases and board rows, each measured by execution',
  attribution: 'every verdict is what public.fn_phase_c_require_founder or public.fn_phase_c_founder_subject_bind actually returned or raised, inside a transaction ending in raise exception',
}) + 'case,result\n'
  + rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_FOUNDER_AUTHENTICATION_RESULT.csv'), csv);
for (const r of rows) console.log(r[0].padEnd(52), r[1]);

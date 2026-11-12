// Finding H1 (9 Nov 2026): a supplier could replace a verified mobile and keep the verified flag.
// Prevented by this file: the rule itself, and that save_profile applies it.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/supplier_api/phone_change.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { phoneChanged, phoneWrite } from './lib/phone_change.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('a different number is a change; formatting alone is not', () => {
  assertEquals(phoneChanged('+971 50 123 4567', '+971501234567'), false);
  assertEquals(phoneChanged('+971-50-123-4567', '971501234567'), false);
  assertEquals(phoneChanged('+971501234567', '+971559999999'), true);
  assertEquals(phoneChanged(null, '+971501234567'), true);
  assertEquals(phoneChanged('+971501234567', ''), true);
  assertEquals(phoneChanged('+971501234567', undefined), false, 'no phone in the request is no change');
});

Deno.test('save_profile keeps a verified number, and clears the flag only over an unverified one', () => {
  const src = functionSource('supplier_api');
  const start = src.indexOf("if (action === 'save_profile')");
  assert(start >= 0, 'save_profile handler not found');
  const body = src.slice(start, start + 4000);
  assert(/select\('[^']*\bphone\b[^']*\bowner_phone_verified\b[^']*'\)/.test(body.slice(0, 600)), 'save_profile must read the phone on file and whether it is verified');
  assert(/phoneWrite\(sup\.phone,\s*sup\.owner_phone_verified,\s*upd\.phone\)/.test(body), 'save_profile must decide with phoneWrite(sup.phone, sup.owner_phone_verified, upd.phone)');
  assert(/phoneDecision === 'kept'\) delete upd\.phone/.test(body), 'a verified number must not be replaced by an unverified one');
  assert(/phoneDecision === 'unverified'\) upd\.owner_phone_verified = false/.test(body), 'a changed number over an unverified one must be written unverified');
});

// WALK OF 12 NOV 2026, B2: Profile said "Changes saved." while save_profile had turned his verified mobile into an unverified one.
// Known-bad control: on origin/main the handler wrote the new phone with owner_phone_verified = false, and the next test fails.
Deno.test('a different number over a verified one: the verified number stays in force until its code is typed', () => {
  assertEquals(phoneWrite('+971501234567', true, '+971559999999'), 'kept');
  assertEquals(phoneWrite('+971501234567', false, '+971559999999'), 'unverified');
  assertEquals(phoneWrite(null, false, '+971559999999'), 'unverified');
  assertEquals(phoneWrite('+971 50 123 4567', true, '+971501234567'), 'unchanged', 'formatting alone is no change');
  assertEquals(phoneWrite('+971501234567', true, undefined), 'unchanged');
});

Deno.test('save_profile itself: an approved supplier who types a new number keeps his verified one, and is told so', async () => {
  const lead: Record<string, unknown> = { id: 9, company_name: 'ZZ DEMO Mobile Kept LLC', claimed_by: 'zz-demo-mobile@example.invalid', approval_status: 'approved',
    registration_submitted_at: '2026-11-01T00:00:00Z', phone: '+971500000011', owner_phone_verified: true, emirate: 'Dubai' };
  const from = (table: string) => {
    let upd: Record<string, unknown> | null = null;
    const b: Record<string, unknown> = {};
    const self = () => b;
    const out = () => ({ data: table === 'leads' ? lead : null, error: null });
    Object.assign(b, { select: self, eq: self, order: self, limit: self,
      update: (v: Record<string, unknown>) => { upd = v; return b; },
      maybeSingle: () => Promise.resolve(out()),
      then: (res: (v: unknown) => void) => { if (upd && table === 'leads') Object.assign(lead, upd); return Promise.resolve({ data: [], error: null }).then(res); } });
    return b;
  };
  const rpc = () => Promise.resolve({ data: { ok: true, approval_status: 'approved', missing: [], reason: null, licence_expired: false }, error: null });
  Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
  const ctx = await import('./context.ts');
  Object.assign(ctx.admin, { from, rpc });   // the handler's own client, pointed at the stub
  const { profileActions } = await import('./actions/profile.ts');
  const res = await profileActions({ req: new Request('http://127.0.0.1/', { method: 'POST' }), email: 'zz-demo-mobile@example.invalid', action: 'save_profile',
    body: { action: 'save_profile', phone: '+971559999999', contact_name: 'ZZ DEMO Contact' } } as never);
  const j = await res!.json();
  assertEquals([res!.status, j.ok, j.phone_kept], [200, true, true], JSON.stringify(j));
  assertEquals([lead.phone, lead.owner_phone_verified, lead.contact_name], ['+971500000011', true, 'ZZ DEMO Contact'], 'the verified number was replaced or un-verified');
});

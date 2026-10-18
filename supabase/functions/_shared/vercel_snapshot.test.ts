// deno test supabase/functions/_shared/vercel_snapshot.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { envCoverage, snapshot } from './vercel_snapshot.ts';

Deno.test('the snapshot keeps names, targets and settings, and never a value', () => {
  const s = snapshot({ name: 'p', framework: 'nextjs', buildCommand: null, crons: { definitions: [{ path: '/api/x', schedule: '*/15 * * * *' }] }, link: { type: 'github', repo: 'r', productionBranch: 'main' } },
    { domains: [{ name: 'b.ae', verified: true }, { name: 'a.ae', verified: false, redirect: 'b.ae' }] },
    { envs: [{ key: 'SUPABASE_SECRET_KEY', target: ['production', 'preview'], type: 'encrypted', value: 'SECRET-VALUE', decrypted: true }] }, '2026-10-12T00:00:00Z');
  assertEquals(JSON.stringify(s).includes('SECRET-VALUE'), false);
  assertEquals(s.env, [{ key: 'SUPABASE_SECRET_KEY', targets: ['preview', 'production'], type: 'encrypted' }]);
  assertEquals(s.domains.map((d) => d.name), ['a.ae', 'b.ae']);
  assertEquals(s.project, { name: 'p', framework: 'nextjs', buildCommand: null, git: { type: 'github', repo: 'r', productionBranch: 'main' } });
});

Deno.test('a needed var Vercel lacks, and a var with no recoverable source, are named', () => {
  const c = envCoverage(['CRON_SECRET', 'NEXT_PUBLIC_SUPABASE_URL', 'MY_TOKEN'],
    [{ key: 'NEXT_PUBLIC_SUPABASE_URL', targets: ['production'], type: 'plain' }, { key: 'POSTGRES_URL', targets: ['production'], type: 'encrypted' }, { key: 'MY_TOKEN', targets: ['production'], type: 'encrypted' }],
    ['my_token']);
  assertEquals(c.missing_in_vercel, ['CRON_SECRET']);
  assertEquals(c.no_recoverable_source, ['CRON_SECRET']);
  assertEquals(c.sources.find((s) => s.key === 'MY_TOKEN')?.source, 'app_secrets.my_token');
  assertEquals(c.sources.find((s) => s.key === 'POSTGRES_URL')?.source, 'Supabase project (the Vercel-Supabase integration re-syncs it)');
});

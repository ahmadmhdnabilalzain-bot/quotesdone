// The whole runtime source of send_whatsapp as text, for the tests that assert a property of it (index.ts first).
// index.ts is the handler; the helpers live beside it (split out 9 Nov 2026), and a test that read index.ts alone
// would read the router and assert on nothing.
export function functionSource(): string {
  const dir = new URL('./', import.meta.url);
  const names = [...Deno.readDirSync(dir)].filter((e) => e.isFile && e.name.endsWith('.ts') && !/\.test\.ts$/.test(e.name) && !e.name.startsWith('test_') && e.name !== 'index.ts').map((e) => e.name).sort();
  return ['index.ts', ...names].map((n) => Deno.readTextFileSync(new URL(n, dir))).join('\n');
}

// The export hop's CPU: the native-regex escape must equal the v1 per-character escape byte for byte,
// round-trip exactly, leave no firewall-trigger character, and a hop must end at the byte budget with a
// clean resume point. Pure, no network. No production data: every fixture below is invented.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { exportSlot, HOP_BYTES, type Deps, type Slot, wafSafeJson } from './table_export_core.ts';

// v1 of wafSafeJson, verbatim (backup v9, #686). The reference the new one must match.
const RISKY_V1 = /[<>&'"\/\\.;|`$(){}%=*+\-#:!?@\[\],~^]/;
function wafSafeJsonV1(value: unknown): string {
  const s = JSON.stringify(value);
  let out = '';
  let inStr = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (!inStr) { out += c; if (c === '"') inStr = true; continue; }
    if (c === '\\') {
      const n = s[i + 1];
      if (n === 'u') { out += s.slice(i, i + 6); i += 5; continue; }
      out += n === '"' ? '\\u0022' : n === '\\' ? '\\u005c' : n === '/' ? '\\u002f' : '\\' + n;
      i++; continue;
    }
    if (c === '"') { out += c; inStr = false; continue; }
    out += RISKY_V1.test(c) ? '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0') : c;
  }
  return out;
}

const C = String.fromCharCode;
const controls = Array.from({ length: 32 }, (_, i) => C(i)).join('') + C(0x7f) + C(0x2028) + C(0x2029);
const owasp = "' UNION SELECT username, password FROM users-- ; <script>alert(1)</script> <img src=x onerror=alert(1)> " +
  "../../etc/passwd ${jndi:ldap://x/a} `id` | /bin/sh; cmd.exe /c dir & echo %PATH% <?php system($_GET['c']); ?> " +
  "1' OR '1'='1 /*! comment */ LEN(password)>5 WAITFOR DELAY '0:0:5' -- " + "\\x00 \\\\ \\\" \\/";
const arabic = 'مرحبا بكم في كوتس دن — عرض سعر رقم ٣٤٥، الكمية: ١٢٠ متر مربع (ألمنيوم 6063-T5).';
const emoji = '🙂👍🏽🇦🇪 family: 👨‍👩‍👧 ' + C(0xd83d) + ' lone-high ' + C(0xdc00) + ' lone-low';
const pageRow = (i: number) => ({                       // the shape of a kb_chunks export row (invented text)
  id: 185284 + i, source_kind: i % 3 ? 'guide' : 'standard', source_id: `wstg-4.2-${i}`, category: 'it',
  title: `OWASP WSTG 4.2 - ${i}. By inferring the length of the string using the LEN function`,
  content: owasp + ' ' + 'Testing for SQL injection: ' + 'abc'.repeat(i % 50) + (i % 7 === 0 ? arabic : '') + (i % 11 === 0 ? emoji : ''),
  citation: 'https://owasp.org/www-project-web-security-testing-guide/v42/?q=a&b=c#frag',
  effective_date: i % 5 ? '2020-12-03' : null, created_at: '2026-07-01T10:00:00.123456+00:00', category_norm: 'it',
});
const corpus: unknown[] = [
  [], {}, '', 'plain', 0, -1.5e-7, 1e21, true, false, null, [null, [[], {}]],
  owasp, arabic, emoji, controls, '"', '\\', '\\"', '"\\', '\\u0041', '\\\\u0041', '/', '</script>',
  { [owasp]: owasp, 'a"b': 'c\\d', '': '', [arabic]: [emoji, controls] },
  Array.from({ length: 40 }, (_, i) => pageRow(i)),
  { long: 'x'.repeat(3_000_000) },                                  // a very long plain string
  { long: ('<a href="/x?y=1&z=2">' + arabic + '\\"' + controls).repeat(20_000) }, // a very long risky one
  { deep: JSON.parse('['.repeat(200) + '"<deep>"' + ']'.repeat(200)) },
];

Deno.test('(a) the native-regex escape equals v1 byte for byte on every corpus item', () => {
  for (const [i, v] of corpus.entries()) {
    const a = wafSafeJsonV1(v), b = wafSafeJson(v);
    assert(a === b, `item ${i} differs (lengths ${a.length} vs ${b.length})`);
  }
});

Deno.test('(b) JSON.parse round-trips every corpus item exactly', () => {
  for (const [i, v] of corpus.entries()) {
    assertEquals(JSON.stringify(JSON.parse(wafSafeJson(v))), JSON.stringify(v), `item ${i}`);
  }
});

Deno.test('(c) no firewall-trigger character survives inside a string', () => {
  const page = Array.from({ length: 200 }, (_, i) => pageRow(i));
  const s = wafSafeJson(page);
  for (const bad of ['<', '>', "'", '../', '/etc', '${', '`', '|', '--', ';', '(', ')', '&', '%', '$', 'jndi:', '/*', '?>']) {
    assert(!s.includes(bad), 'still contains ' + JSON.stringify(bad));
  }
  // outside strings only JSON structure remains; the escaped text still parses to the original
  assertEquals(JSON.parse(s), page);
});

Deno.test('(d) a hop ends at the 12 MB budget and the next hop continues with no gap and no duplicate', async () => {
  const PAGES = 7, PAGE_TEXT = 'a'.repeat(4_300_000);                  // ~4.3 MB escaped, like a kb_chunks page
  const stored: string[] = [];
  const deps: Deps = {
    now: () => 0,
    clear: async () => {},
    readPage: async (slot) => {
      const start = Number(slot.after ?? 0);
      return { rows: [{ id: start + 1, t: PAGE_TEXT }], done: start + 1 >= PAGES, last: start + 1 };
    },
    upload: async (path) => { stored.push(path); },
  };
  const slot: Slot = { t: 'kb_chunks', after: null, page: 0, rows: 0, since: null };
  const hops: number[] = [];
  for (let hop = 0; hop < 10; hop++) {
    const budget = { spent: 0, max: HOP_BYTES };
    const before = stored.length;
    const finished = await exportSlot('2026-09-15', slot, 1, deps, () => {}, budget);
    hops.push(stored.length - before);
    assert(budget.spent < HOP_BYTES + 4_400_000, 'a hop overshot the budget by more than one page');
    if (finished) break;
    assert(budget.spent >= HOP_BYTES, 'a hop stopped before the budget without finishing');
  }
  assertEquals(hops, [3, 3, 1]);                                    // 3 x ~4.3 MB crosses 12 MB
  assertEquals(stored, Array.from({ length: PAGES }, (_, i) => `2026-09-15/kb_chunks/page_${String(i).padStart(4, '0')}.json`));
  assertEquals(slot.page, PAGES);
  assertEquals(slot.rows, PAGES);
});

Deno.test('(e) escaping a realistic 4 MB page stays well inside the CPU budget', () => {
  const rows: unknown[] = [];
  for (let bytes = 0; bytes < 4_000_000;) { const r = pageRow(rows.length); rows.push(r); bytes += JSON.stringify(r).length + 1; }
  wafSafeJson(rows);                                                 // warm up the regex compiler
  const t0 = performance.now();
  const out = wafSafeJson(rows);
  const ms = performance.now() - t0;
  const t1 = performance.now();
  wafSafeJsonV1(rows);
  const v1 = performance.now() - t1;
  console.log(`4 MB page: native-regex ${ms.toFixed(0)} ms, v1 ${v1.toFixed(0)} ms, ${out.length} bytes out`);
  // The hop carries ~3 such pages; production measured 60-126 ms per real page. 1,000 ms per page is a
  // loose ceiling so a slow CI runner does not flake, and still fails if escaping regresses to v1-like
  // cost on a slow machine or to anything quadratic.
  assert(ms < 1000, `escaping a 4 MB page took ${ms.toFixed(0)} ms`);
});

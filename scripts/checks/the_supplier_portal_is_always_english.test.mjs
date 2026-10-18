// THE SUPPLIER PORTAL IS ALWAYS ENGLISH (12 Oct 2026, it_engineer; founder ruling 1008, 28 Sep 2026).
//
// Suppliers are always English. The supplier portal still had an EN/عربي toggle in its header, an
// interface-language select in Settings, followed an /ar/portal URL into Arabic and adopted leads.locale
// after sign-in; save_settings stored 'ar' when asked. This fails if any of that returns. The customer
// portal keeps its Arabic toggle and is asserted untouched here so the fix cannot be "remove both".
//   node --test scripts/checks/the_supplier_portal_is_always_english.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (f) => readFileSync(new URL('../../' + f, import.meta.url), 'utf8');
const portal = read('src/components/portal/SupplierPortal.tsx');
const settings = read('src/components/portal/supplier/SupplierSettings.tsx');
const api = read('supabase/functions/supplier_api/index.ts');

test('the supplier portal renders English and offers no language toggle', () => {
  assert.match(portal, /const lang: string = 'en';/, 'lang must be the constant English');
  assert.doesNotMatch(portal, /useState\(['"](en|ar)['"]\)/, 'lang must not be state that can become Arabic');
  assert.doesNotMatch(portal, /setLang|adoptLocale|urlLocale\(/, 'nothing may move the supplier portal to the URL or account language');
  assert.doesNotMatch(portal, />\{?[^<{}]*'عربي'|>عربي</, 'no عربي toggle in the supplier portal');
  assert.doesNotMatch(portal, /save_settings', locale/, 'the portal must not save a supplier language');
});

test('supplier settings has no interface-language control and sends no locale', () => {
  assert.doesNotMatch(settings, /qd-set-lang|<option value="ar"/, 'no language select');
  assert.doesNotMatch(settings, /save_settings', locale/, 'save must not send a locale');
  assert.doesNotMatch(settings, /onLang/, 'no language callback');
});

test('supplier_api save_settings stores English whatever locale arrives', () => {
  const at = api.indexOf("if (action === 'save_settings')");
  assert.ok(at > 0, 'save_settings action not found');
  const body = api.slice(at, at + 1500);
  assert.match(body, /upd\.locale = SUPPLIER_LOCALE;/, "save_settings must store SUPPLIER_LOCALE ('en')");
  assert.doesNotMatch(body, /upd\.locale = loc\b/, 'save_settings must not store the requested locale');
  assert.match(read('supabase/functions/_shared/registered_locale.ts'), /export const SUPPLIER_LOCALE: Locale = 'en';/);
});

test('the customer portal keeps its Arabic toggle', () => {
  const shell = read('src/components/me/PortalShell.tsx') + read('src/components/me/CustomerPortal.tsx');
  assert.match(shell, /عربي/, 'the customer portal must still offer عربي');
});

// node --test src/components/portal/supplier/workspaceHelp.test.mjs
// Walk of 12 Nov 2026, S13 (sales_engineer, built by it_engineer): the approved workspace had no help, contact or Supplier Agreement
// link, and "Home" is hidden under 640 px. This fails if the help line leaves the workspace, loses one of its links, or shows a contact
// the company does not publish.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const help = readFileSync(new URL('./WorkspaceHelp.tsx', import.meta.url), 'utf8');
const portal = readFileSync(new URL('../SupplierPortal.tsx', import.meta.url), 'utf8');
const contact = readFileSync(new URL('../../ContactInner.tsx', import.meta.url), 'utf8');
const rr = readFileSync(new URL('./registrationReceived.ts', import.meta.url), 'utf8');

test('the workspace closes on help, contact, the Supplier Agreement, privacy and home', () => {
  const app = portal.slice(portal.indexOf("{phase === 'app' && (claiming"), portal.indexOf('</main>'));
  assert.match(app, /<WorkspaceHelp \/>/, 'the help line is not in the signed-in workspace');
  for (const href of ["'mailto:' + SUPPORT_EMAIL", '"/contact"', '"/supplier-agreement"', '"/privacy"', '"/"']) assert.ok(help.includes('href={' + href + '}') || help.includes('href=' + href), href);
  assert.doesNotMatch(help, /hidden sm:|sm:hidden/, 'a link is hidden on a phone');
  assert.match(help, /className=\{link\}/); assert.match(help, /const link = 'inline-flex min-h-11/);
});

test('the address is the one the company publishes, and no WhatsApp number is invented', () => {
  const addr = /export const SUPPORT_EMAIL = '([^']+)'/.exec(rr)[1];
  assert.ok(contact.includes(addr), 'the Contact page does not publish ' + addr);
  assert.doesNotMatch(help, /wa\.me|\+971|whatsapp\.com/i);
});

// A NEW OPTION ONLY WHILE NOTHING IS REVEALED (#1563 review). The portal hides "Add another option" once the
// customer has revealed this supplier, but the server must refuse it too: a revealed quotation is the
// customer's paid decision, and an option added after it would be a price they never compared.
export function newOptionRefusal(newOption: unknown, revealedQuotes: number): { status: number; body: Record<string, unknown> } | null {
  if (newOption !== true || !(revealedQuotes > 0)) return null;
  return { status: 409, body: { error: 'The customer has already revealed your quotation for this job, so another option cannot be added.', code: 'option_after_reveal' } };
}

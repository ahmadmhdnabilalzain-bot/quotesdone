// Names itself in the 410 body: a caller learns which surface is gone, and deploy parity gains the
// distinctive literal it needs to report this function verified instead of UNVERIFIED. The old body
// was the four characters "gone", from which no signature can be derived.
Deno.serve(() => new Response(JSON.stringify({
  error: 'disabled',
  fn: 'src_io',
  retired: 'src_io was retired: it served repository source over HTTP, which is not something a production project should expose.',
}), { status: 410, headers: { 'Content-Type': 'application/json' } }));

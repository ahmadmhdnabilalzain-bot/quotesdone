// Does storage hold this object? (sales_engineer, 14 Sep 2026.)
// An upload is reported to the customer or supplier as done, and its path is written to their record,
// only once storage answers that the object is there. A path that names nothing is how 3 seed
// catalogue/profile rows ended up 'abandoned: source object ... is not in storage': the backup cannot
// copy what was never stored.
// deno-lint-ignore no-explicit-any
export async function storedAt(admin: any, bucket: string, path: string): Promise<boolean> {
  const i = path.lastIndexOf('/');
  const dir = i < 0 ? '' : path.slice(0, i), name = path.slice(i + 1);
  if (!name) return false;
  const { data, error } = await admin.storage.from(bucket).list(dir, { search: name, limit: 100 });
  if (error) throw new Error(`storage list ${bucket}/${dir}: ${error.message}`);
  return (data || []).some((o: { name: string }) => o.name === name);
}

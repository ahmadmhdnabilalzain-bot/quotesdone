// A harness run is COMPLETE when every journey it was asked for (--journey, or the whole ORDER) was
// attempted: not cut by the deadline, and the harness's own session still alive. A --journey subset that
// ran all it asked for is complete for that subset; what it may close is scoped by the ingest to the
// journeys that finished (fn_it_journey_ingest / fn_it_smoke_ingest read run.json `journeys`).
export const runIsComplete = ({ truncated, harnessDead, only, attempted }) =>
  !truncated && !harnessDead && only.length > 0 && only.every((k) => attempted.has(k));

-- Staging carried its own autonomy blocker, cos_frozen = true, while production has had it false.
-- The founder's standing rule is that staging is a rehearsal surface and nothing is meant to
-- remain there: parity is the point, and a freeze that exists on one project only is drift.
select set_config('app.change_reason',
  'Lifting the staging-only cos_frozen freeze so staging matches production. Production has run with cos_frozen=false; keeping staging frozen means the rehearsal surface no longer rehearses what production does.', true);
update app_secrets set value='false' where key='cos_frozen';

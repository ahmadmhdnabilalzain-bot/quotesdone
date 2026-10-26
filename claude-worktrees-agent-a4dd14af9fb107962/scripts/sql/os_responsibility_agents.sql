-- Two acting agents belonged to no operating system. Both are capabilities an OS mandate already
-- claims, so they are registered as responsibilities rather than guessed at by name matching.
insert into public.os_responsibility (responsibility, os_key, note) values
  ('ai_trainer', 'technology',
   'Technology OS mandate: "Owns infrastructure, application, AI runtime, model routing, security and deployment." Training and promoting prompts is operating the AI runtime.'),
  ('supplier_risk_monitor', 'marketplace',
   'Marketplace OS mandate: "Owns supplier acquisition, onboarding, verification, category coverage..."; it already owns the responsibilities "suppliers" and "supplier_performance".')
on conflict (responsibility) do update set os_key = excluded.os_key, note = excluded.note;

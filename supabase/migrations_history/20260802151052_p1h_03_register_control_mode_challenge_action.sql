-- control_mode_challenge is the new first step of opening Control Mode. It is mode_control for the
-- same reason control_mode_open is: requiring Control Mode to request a Control Mode code would make
-- Control Mode unopenable. It is safe outside the gate because it takes no input that selects a
-- destination - the phone comes from the identity registration, not the request - and it is rate
-- limited to five per hour per identity.
alter table public.control_mode_action drop constraint if exists control_mode_action_mode_control_pinned;
alter table public.control_mode_action
  add constraint control_mode_action_mode_control_pinned
  check (classification <> 'mode_control'
         or action in ('control_mode_status','control_mode_open','control_mode_close','control_mode_challenge'));

insert into public.control_mode_action (action, classification, risk, description) values
  ('control_mode_challenge','mode_control','high',
   'Mints a Control Mode code and sends it to the registered admin phone. Rate limited; never accepts a phone from the request.')
on conflict (action) do update
  set classification = excluded.classification, risk = excluded.risk, description = excluded.description;

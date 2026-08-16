-- Phase C correction 7b — registering the clarify operation in BOTH gates.
--
-- An action in os_api's ACTION_CLASS but not in public.control_mode_action once made read-only
-- screens demand a phone code. The two gates are kept in step here, in the same migration as the
-- code that dispatches it.
--
-- founder_gated, not read_only: answering a clarification can CREATE the tasks the original
-- instruction could not safely produce, so it writes, it is audited, and the preview key cannot
-- reach it. The pinning CHECK is widened by exactly one name.
alter table public.control_mode_action drop constraint if exists control_mode_action_founder_gated_pinned;
alter table public.control_mode_action add constraint control_mode_action_founder_gated_pinned
  check (classification <> 'founder_gated'
         or action in ('founder_command','founder_command_control','founder_command_clarify'));

-- requires_control is a GENERATED column: it is derived from the classification, which is exactly
-- the design that stops the two halves of the gate disagreeing. Only the classification is written.
insert into public.control_mode_action (action, classification, description)
values ('founder_command_clarify', 'founder_gated',
        'The founder answers a clarification in the same command thread. It can create the tasks the '
        'original instruction could not safely produce, so it writes and is audited.')
on conflict (action) do update set classification = excluded.classification,
                                   description = excluded.description;

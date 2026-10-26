"select jsonb_agg(to_jsonb(p)) r from public.it_playbook p where failure_class in ('heartbeat_step','unreviewed_revision','whatsapp_template');"  

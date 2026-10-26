"select string_agg(column_name,',') c from information_schema.columns where table_name='agent_runs';"  

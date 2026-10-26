select key from app_secrets where key like 'cred_%' and (key like '%marketing%' or key like '%resilience%');

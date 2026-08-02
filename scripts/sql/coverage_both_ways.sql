-- Every applied migration in the P2-C1 window, with its recorded statement count
-- and the SHA-256 of its exact bytes, so the repository can be checked in both
-- directions: production -> repository and repository -> production.
select version || '|' || name || '|' || array_length(statements, 1)::text || '|'
       || encode(extensions.digest(array_to_string(statements, E';\n') || ';', 'sha256'), 'hex')
       || '|' || length(array_to_string(statements, E';\n') || ';')::text as row
  from supabase_migrations.schema_migrations
 where version >= '20260802165328' and version <= '20260802183212'
 order by version;

select 'agent_knowledge' t, id::text, md5(content) m, substr(content, greatest(1, position('CARD PROCESSING FEE' in content)-260), 420) ctx from agent_knowledge where id=279
union all
select 'kb_chunks', id::text, md5(content), substr(content, greatest(1, position('CARD PROCESSING FEE' in content)-260), 420) from kb_chunks where id=177872;

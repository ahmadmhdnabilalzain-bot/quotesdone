select ic.context from internal_credential ic where ic.active and 'marketing_channels' = any(ic.scope);

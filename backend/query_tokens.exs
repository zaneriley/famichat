# Check user_tokens table structure
cols = Famichat.Repo.query!("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'user_tokens' ORDER BY ordinal_position")
Enum.each(cols.rows, fn [col, type] -> IO.puts("  #{col}: #{type}") end)

# Check user_devices
dcols = Famichat.Repo.query!("SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'user_devices' ORDER BY ordinal_position")
IO.puts("user_devices columns:")
Enum.each(dcols.rows, fn [col, type] -> IO.puts("  #{col}: #{type}") end)

# Get recent tokens - look for invite tokens
tokens = Famichat.Repo.query!("SELECT context, encode(token, 'hex') as token, sent_to, inserted_at FROM user_tokens WHERE context LIKE '%invite%' ORDER BY inserted_at DESC LIMIT 5")
IO.inspect(tokens.rows, label: "InviteTokens")

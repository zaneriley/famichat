# Check user_tokens table structure fully
cols =
  Famichat.Repo.query!(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'user_tokens' ORDER BY ordinal_position"
  )

IO.puts("user_tokens columns:")
Enum.each(cols.rows, fn [col, type] -> IO.puts("  #{col}: #{type}") end)

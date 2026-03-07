# Find the actual invite table name
tables =
  Famichat.Repo.query!(
    "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"
  )

IO.inspect(Enum.map(tables.rows, fn [t] -> t end), label: "Tables")

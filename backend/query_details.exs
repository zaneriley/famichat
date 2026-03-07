results = Famichat.Repo.query!("SELECT id::text, username FROM users LIMIT 10")

Enum.each(results.rows, fn [id, username] ->
  IO.puts("User: #{username} id=#{id}")
end)

fam = Famichat.Repo.query!("SELECT id::text, name FROM families LIMIT 10")

Enum.each(fam.rows, fn [id, name] ->
  IO.puts("Family: #{name} id=#{id}")
end)

inv_cols =
  Famichat.Repo.query!(
    "SELECT column_name FROM information_schema.columns WHERE table_name = 'user_invites'"
  )

IO.inspect(Enum.map(inv_cols.rows, fn [c] -> c end), label: "InviteColumns")

sess_cols =
  Famichat.Repo.query!(
    "SELECT column_name FROM information_schema.columns WHERE table_name = 'user_sessions'"
  )

IO.inspect(Enum.map(sess_cols.rows, fn [c] -> c end), label: "SessionColumns")

users_cols =
  Famichat.Repo.query!(
    "SELECT column_name FROM information_schema.columns WHERE table_name = 'users'"
  )

IO.inspect(Enum.map(users_cols.rows, fn [c] -> c end), label: "UsersColumns")

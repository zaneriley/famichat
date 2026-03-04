results = Famichat.Repo.query!("SELECT id, username FROM users LIMIT 10")
IO.inspect(results.rows, label: "Users")

fam = Famichat.Repo.query!("SELECT id, name FROM families LIMIT 10")
IO.inspect(fam.rows, label: "Families")

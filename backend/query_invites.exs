# Check for invite tokens
tokens =
  Famichat.Repo.query!(
    "SELECT id::text, user_id::text, context, payload, expires_at, used_at, inserted_at FROM user_tokens WHERE context LIKE '%invite%' ORDER BY inserted_at DESC LIMIT 10"
  )

IO.puts("Invite tokens:")

Enum.each(tokens.rows, fn [id, user_id, context, payload, exp, used, ins] ->
  IO.puts(
    "  id=#{id} user=#{user_id} ctx=#{context} payload=#{inspect(payload)} exp=#{exp} used=#{used} ins=#{ins}"
  )
end)

# Also check fresh tokens that could be invites
all_tokens = Famichat.Repo.query!("SELECT DISTINCT context FROM user_tokens")
IO.inspect(Enum.map(all_tokens.rows, fn [c] -> c end), label: "AllContexts")

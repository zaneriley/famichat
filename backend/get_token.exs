# Get the admin user (zane) and issue an invite programmatically
admin_user_id = "2076cf69-ee68-4a99-afa3-cd6d6fa82aeb"
family_id = "208bb331-e940-458d-bdb6-57114753bda1"

# Issue invite using the Onboarding module
result =
  Famichat.Auth.Onboarding.issue_invite(admin_user_id, nil, %{
    household_id: family_id,
    role: "member"
  })

case result do
  {:ok, tokens} ->
    IO.puts("INVITE_TOKEN=#{tokens.invite}")
    IO.puts("QR_TOKEN=#{tokens.qr}")
    IO.puts("ADMIN_CODE=#{tokens.admin_code}")

  {:error, reason} ->
    IO.inspect(reason, label: "Error")
end

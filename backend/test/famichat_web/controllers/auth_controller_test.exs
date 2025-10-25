defmodule FamichatWeb.AuthControllerTest do
  use FamichatWeb.ConnCase, async: true

  alias Famichat.Repo
  alias Famichat.Auth.Sessions
  alias Famichat.ChatFixtures
  alias Famichat.Accounts.{User, UserDevice}

  @json "application/json"

  setup do
    family = ChatFixtures.family_fixture()

    admin =
      ChatFixtures.user_fixture(%{
        household_id: family.id,
        role: :admin,
        username: "admin_user"
      })

    ChatFixtures.membership_fixture(admin, family, :admin)

    {:ok, admin_session} =
      Sessions.start_session(
        admin,
        %{id: Ecto.UUID.generate(), user_agent: "test-agent", ip: "127.0.0.1"},
        remember: true
      )

    %{family: family, admin: admin, admin_session: admin_session}
  end

  test "invite → pair → register → passkey login flow",
       %{
         conn: conn,
         family: family,
         admin: _admin,
         admin_session: admin_session
       } do
    conn =
      conn
      |> put_req_header("content-type", @json)
      |> auth(admin_session.access_token)

    # Issue invite
    invite_conn =
      conn
      |> post(~p"/api/v1/auth/invites", %{
        household_id: family.id,
        role: "member",
        email: "newuser@example.test"
      })

    response = json_response(invite_conn, 202)

    invite_token = response["invite_token"]
    qr_token = response["qr_token"]
    admin_code = response["admin_code"]
    assert invite_token
    assert qr_token
    assert admin_code
    encoded = invite_conn |> get_resp_header("x-test-token") |> List.first()
    refute is_nil(encoded)
    decoded = Jason.decode!(encoded)
    assert decoded["invite"]
    assert decoded["qr"]
    assert decoded["admin_code"]

    # Redeem pairing via QR
    pair_payload =
      conn
      |> post(~p"/api/v1/auth/pairings/redeem", %{token: qr_token})
      |> json_response(200)

    assert pair_payload["invite_token"] == invite_token
    assert pair_payload["payload"]["household_id"] == family.id

    # Redeem pairing via admin code
    conn
    |> post(~p"/api/v1/auth/pairings/redeem", %{token: admin_code})
    |> json_response(200)

    # Accept invite to fetch payload + registration token
    accept_conn =
      conn
      |> post(~p"/api/v1/auth/invites/accept", %{token: invite_token})

    accept_payload = json_response(accept_conn, 200)

    registration_token = accept_payload["registration_token"]
    assert is_binary(registration_token)

    header_registration_token =
      accept_conn
      |> get_resp_header("x-test-token")
      |> List.first()
      |> case do
        nil -> nil
        encoded -> Jason.decode!(encoded)["registration_token"]
      end

    assert header_registration_token in [nil, registration_token]

    conn
    |> post(~p"/api/v1/auth/invites/accept", %{token: invite_token})
    |> json_response(410)

    # Complete invite by registering the user
    register_payload =
      conn
      |> put_req_header("authorization", "Bearer #{registration_token}")
      |> post(~p"/api/v1/auth/invites/complete", %{
        username: "new_member"
      })
      |> json_response(201)

    user_id = register_payload["user_id"]
    assert user_id
    register_token = register_payload["passkey_register_token"]
    assert register_token

    created_user = Repo.get!(User, user_id)

    assert created_user.email |> to_string() |> String.downcase() ==
             "newuser@example.test"

    # Request passkey registration challenge
    challenge_payload =
      conn
      |> post(~p"/api/v1/auth/passkeys/register/challenge", %{
        register_token: register_token
      })
      |> json_response(200)

    challenge = challenge_payload["challenge"]
    challenge_handle = challenge_payload["challenge_handle"]
    refute Map.has_key?(challenge_payload, "user")
    refute Map.has_key?(challenge_payload, "challenge_token")
    assert challenge_handle

    public_key_opts = challenge_payload["public_key_options"]
    assert public_key_opts
    assert public_key_opts["challenge"] == challenge

    credential_id = Base.encode64("credential-123")
    public_key = Base.encode64("public-key-123")

    # Register passkey
    conn
    |> post(~p"/api/v1/auth/passkeys/register", %{
      credential_id: credential_id,
      public_key: public_key,
      challenge: challenge,
      challenge_handle: challenge_handle,
      sign_count: 0
    })
    |> json_response(201)

    # Request passkey assertion challenge via username
    assert_payload =
      conn
      |> post(~p"/api/v1/auth/passkeys/assert/challenge", %{
        username: "new_member"
      })
      |> json_response(200)

    assert_challenge = assert_payload["challenge"]
    assert_handle = assert_payload["challenge_handle"]
    refute Map.has_key?(assert_payload, "user")
    refute Map.has_key?(assert_payload, "challenge_token")
    assert assert_handle

    assert_public_key = assert_payload["public_key_options"]
    assert assert_public_key
    assert assert_public_key["challenge"] == assert_challenge

    device_id = Ecto.UUID.generate()

    # Assert passkey + start session
    session_payload =
      conn
      |> post(~p"/api/v1/auth/passkeys/assert", %{
        credential_id: credential_id,
        challenge: assert_challenge,
        challenge_handle: assert_handle,
        sign_count: 1,
        device_id: device_id,
        trust_device: true
      })
      |> json_response(201)

    access_token = session_payload["access_token"]
    refresh_token = session_payload["refresh_token"]
    assert access_token
    assert refresh_token
    assert session_payload["device_id"] == device_id

    # Refresh session
    refreshed =
      conn
      |> post(~p"/api/v1/auth/sessions/refresh", %{
        device_id: device_id,
        refresh_token: refresh_token
      })
      |> json_response(200)

    assert refreshed["refresh_token"] != refresh_token

    # Revoke device
    conn
    |> auth(session_payload["access_token"])
    |> delete(~p"/api/v1/auth/devices/#{device_id}")
    |> response(204)

    # Refreshing again should fail
    conn
    |> post(~p"/api/v1/auth/sessions/refresh", %{
      device_id: device_id,
      refresh_token: refresh_token
    })
    |> json_response(401)

    assert Repo.get_by(UserDevice, device_id: device_id).revoked_at
  end

  test "magic link and otp flows", %{conn: conn, admin: admin} do
    conn = put_req_header(conn, "content-type", @json)

    existing_user =
      ChatFixtures.user_fixture(%{
        email: "magic@example.test",
        username: "magic_user"
      })

    # Magic link issuance/redeem
    magic_conn =
      conn
      |> post(~p"/api/v1/auth/magic_link", %{email: "magic@example.test"})

    magic_response = json_response(magic_conn, 202)
    assert magic_response["status"] == "accepted"

    token =
      magic_conn
      |> get_resp_header("x-test-token")
      |> List.first()

    refute is_nil(token)

    conn
    |> post(~p"/api/v1/auth/magic_link/redeem", %{token: token})
    |> json_response(200)

    user = Repo.get!(User, existing_user.id)
    assert %DateTime{} = user.enrollment_required_since

    diff =
      DateTime.diff(DateTime.utc_now(), user.enrollment_required_since, :second)

    assert_in_delta(diff, 0, 5)

    conn
    |> post(~p"/api/v1/auth/magic_link/redeem", %{token: token})
    |> json_response(410)

    # OTP issuance/verify (user must exist)
    otp_conn =
      conn
      |> post(~p"/api/v1/auth/otp/request", %{email: admin.email})

    otp_response = json_response(otp_conn, 202)
    assert otp_response["status"] == "accepted"

    otp_token =
      otp_conn
      |> get_resp_header("x-test-token")
      |> List.first()

    refute is_nil(otp_token)

    conn
    |> post(~p"/api/v1/auth/otp/verify", %{email: admin.email, code: otp_token})
    |> json_response(200)
  end

  defp auth(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end

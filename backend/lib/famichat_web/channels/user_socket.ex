defmodule FamichatWeb.UserSocket do
  use Phoenix.Socket
  require Logger

  # Update channel pattern to support conversation-type-aware topic formats
  # Format: message:<type>:<id> where type is one of: self, direct, group, family
  channel "message:*", FamichatWeb.MessageChannel

  @salt "user_auth"

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case verify_token_and_connect(token, socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} = error -> error
    end
  end

  def connect(_params, _socket, _connect_info) do
    {:error, %{reason: "invalid_token"}}
  end

  defp verify_token_and_connect(token, socket) do
    case Phoenix.Token.verify(FamichatWeb.Endpoint, @salt, token,
           max_age: 86_400
         ) do
      {:ok, user_id} ->
        Logger.debug("User connected with user_id: #{user_id}")
        {:ok, assign(socket, :user_id, user_id)}

      {:error, reason} ->
        Logger.error("User connection failed due to invalid token: #{reason}")
        {:error, %{reason: "invalid_token"}}
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     FamichatWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end

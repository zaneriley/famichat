defmodule Mix.Tasks.Famichat.RunbookSeed do
  @moduledoc """
  Emits deterministic seed data for the canonical messaging runbook.

  The task creates/reuses:
  - one family
  - one sender user
  - one receiver user
  - one direct conversation between sender/receiver
  - one access token per user

  Output is JSON so it can be consumed directly by scripts and LLM tooling.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Famichat,
      Famichat.Chat,
      Famichat.Auth.Households,
      Famichat.Auth.Identity,
      Famichat.Auth.Sessions
    ],
    exports: []

  use Mix.Task

  require Logger

  alias Famichat.Auth.{Households, Identity, Sessions}
  alias Famichat.Chat.{ConversationService, Family}
  alias Famichat.Repo

  @shortdoc "Prints canonical runbook seed JSON (users/tokens/topic)"

  @default_family_name "Runbook Family"
  @default_sender_username "runbook_sender"
  @default_receiver_username "runbook_receiver"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    ensure_allowed_environment!()

    opts = parse_opts(args)
    previous_level = Logger.level()
    Logger.configure(level: :info)

    try do
      case seed(opts) do
        {:ok, payload} ->
          IO.puts(Jason.encode!(payload, pretty: true))

        {:error, reason} ->
          Mix.raise("runbook seed failed: #{inspect(reason)}")
      end
    after
      Logger.configure(level: previous_level)
    end
  end

  defp parse_opts(args) do
    normalized_args = Enum.map(args, &normalize_switch_arg/1)

    {opts, argv, invalid} =
      OptionParser.parse(normalized_args,
        strict: [
          family_name: :string,
          sender_username: :string,
          receiver_username: :string
        ]
      )

    ensure_no_invalid_options!(invalid)
    ensure_no_positional_args!(argv)

    family_name = fetch_non_empty_opt!(opts, :family_name, @default_family_name)

    sender_username =
      fetch_non_empty_opt!(opts, :sender_username, @default_sender_username)

    receiver_username =
      fetch_non_empty_opt!(
        opts,
        :receiver_username,
        @default_receiver_username
      )

    if sender_username == receiver_username do
      Mix.raise("sender_username and receiver_username must differ")
    end

    %{
      family_name: family_name,
      sender_username: sender_username,
      receiver_username: receiver_username
    }
  end

  defp normalize_switch_arg("--" <> switch) do
    case String.split(switch, "=", parts: 2) do
      [name, value] ->
        "--" <> String.replace(name, "_", "-") <> "=" <> value

      [name] ->
        "--" <> String.replace(name, "_", "-")
    end
  end

  defp normalize_switch_arg(arg), do: arg

  defp ensure_no_invalid_options!([]), do: :ok

  defp ensure_no_invalid_options!(invalid) do
    invalid_list =
      invalid
      |> Enum.map_join(", ", &format_invalid_option/1)

    Mix.raise("unrecognized options: #{invalid_list}")
  end

  defp ensure_no_positional_args!([]), do: :ok

  defp ensure_no_positional_args!(argv) do
    Mix.raise("unexpected positional arguments: #{Enum.join(argv, " ")}")
  end

  defp fetch_non_empty_opt!(opts, key, default) do
    value =
      opts
      |> Keyword.get(key, default)
      |> String.trim()

    if value == "" do
      Mix.raise("#{key} must be a non-empty string")
    end

    value
  end

  defp format_invalid_option({option, _value}) when is_binary(option),
    do: option

  defp format_invalid_option({option, _value}), do: inspect(option)
  defp format_invalid_option(option) when is_binary(option), do: option
  defp format_invalid_option(option), do: inspect(option)

  defp ensure_allowed_environment! do
    env = Application.get_env(:famichat, :environment)

    if env not in [:dev, :test] do
      Mix.raise(
        "mix famichat.runbook_seed is restricted to dev/test (current: #{inspect(env)})"
      )
    end
  end

  defp seed(%{
         family_name: family_name,
         sender_username: sender_username,
         receiver_username: receiver_username
       }) do
    Repo.transaction(fn ->
      with {:ok, family} <- ensure_family(family_name),
           {:ok, sender} <- ensure_member(sender_username, family.id, :admin),
           {:ok, receiver} <-
             ensure_member(receiver_username, family.id, :member),
           {:ok, conversation} <-
             ConversationService.create_direct_conversation(
               sender.id,
               receiver.id
             ),
           {:ok, sender_session} <- start_session(sender, "sender"),
           {:ok, receiver_session} <- start_session(receiver, "receiver") do
        %{
          environment: to_string(Application.get_env(:famichat, :environment)),
          generated_at:
            DateTime.utc_now(:second)
            |> DateTime.to_iso8601(),
          family: %{
            id: family.id,
            name: family.name
          },
          sender: %{
            id: sender.id,
            username: sender.username,
            access_token: sender_session.access_token,
            device_id: sender_session.device_id
          },
          receiver: %{
            id: receiver.id,
            username: receiver.username,
            access_token: receiver_session.access_token,
            device_id: receiver_session.device_id
          },
          conversation: %{
            type: "direct",
            id: conversation.id,
            topic: "message:direct:#{conversation.id}"
          },
          broadcast: %{
            endpoint: "/api/v1/conversations/:id/messages",
            payload_template: %{
              body: "runbook hello"
            }
          }
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, payload} -> {:ok, payload}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_family(name) do
    case Repo.get_by(Family, name: name) do
      %Family{} = family ->
        {:ok, family}

      nil ->
        %Family{}
        |> Family.changeset(%{name: name})
        |> Repo.insert()
    end
  end

  defp ensure_member(username, family_id, role) do
    email = "#{username}@example.test"

    with {:ok, user} <-
           Identity.ensure_user(%{username: username, email: email}),
         {:ok, _membership} <-
           Households.upsert_membership(user.id, family_id, role) do
      {:ok, user}
    end
  end

  defp start_session(user, label) do
    Sessions.start_session(
      user,
      %{
        id: "runbook-#{label}-#{System.unique_integer([:positive])}",
        user_agent: "famichat.runbook_seed",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end
end

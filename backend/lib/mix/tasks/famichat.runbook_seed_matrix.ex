defmodule Mix.Tasks.Famichat.RunbookSeedMatrix do
  @moduledoc """
  Emits deterministic seed data for live messaging QA matrix probes.

  The task creates/reuses:
  - one primary family
  - sender/receiver/third users in the primary family
  - one outsider family + outsider user
  - one sender self conversation
  - one receiver self conversation
  - one direct conversation (sender <-> receiver)
  - one group conversation (sender + receiver + third)
  - one family conversation
  - access tokens for matrix actors, including a second sender device session

  Output is JSON so runbook commands and agents can run black-box probes
  against real HTTP/WS surfaces.
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

  import Ecto.Query

  alias Famichat.Auth.{Households, Identity, Sessions}

  alias Famichat.Chat.{
    Conversation,
    ConversationParticipant,
    ConversationService,
    Family,
    Self
  }

  alias Famichat.Repo

  @shortdoc "Prints runbook matrix seed JSON (actors/tokens/conversations/topics)"

  @default_family_name "Runbook Family"
  @default_outsider_family_name "Runbook Outsider Family"
  @default_sender_username "runbook_sender"
  @default_receiver_username "runbook_receiver"
  @default_third_username "runbook_member"
  @default_outsider_username "runbook_outsider"
  @default_group_name "Runbook Group"

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
          Mix.raise("runbook matrix seed failed: #{inspect(reason)}")
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
          outsider_family_name: :string,
          sender_username: :string,
          receiver_username: :string,
          third_username: :string,
          outsider_username: :string,
          group_name: :string
        ]
      )

    ensure_no_invalid_options!(invalid)
    ensure_no_positional_args!(argv)

    family_name = fetch_non_empty_opt!(opts, :family_name, @default_family_name)

    outsider_family_name =
      fetch_non_empty_opt!(
        opts,
        :outsider_family_name,
        @default_outsider_family_name
      )

    sender_username =
      fetch_non_empty_opt!(opts, :sender_username, @default_sender_username)

    receiver_username =
      fetch_non_empty_opt!(opts, :receiver_username, @default_receiver_username)

    third_username =
      fetch_non_empty_opt!(opts, :third_username, @default_third_username)

    outsider_username =
      fetch_non_empty_opt!(opts, :outsider_username, @default_outsider_username)

    group_name = fetch_non_empty_opt!(opts, :group_name, @default_group_name)

    usernames = [
      sender_username,
      receiver_username,
      third_username,
      outsider_username
    ]

    if length(Enum.uniq(usernames)) != length(usernames) do
      Mix.raise("sender/receiver/third/outsider usernames must all differ")
    end

    %{
      family_name: family_name,
      outsider_family_name: outsider_family_name,
      sender_username: sender_username,
      receiver_username: receiver_username,
      third_username: third_username,
      outsider_username: outsider_username,
      group_name: group_name
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
      |> Enum.map(&format_invalid_option/1)
      |> Enum.join(", ")

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
        "mix famichat.runbook_seed_matrix is restricted to dev/test (current: #{inspect(env)})"
      )
    end
  end

  defp seed(opts) do
    Repo.transaction(fn ->
      with {:ok, family} <- ensure_family(opts.family_name),
           {:ok, sender} <-
             ensure_member(opts.sender_username, family.id, :admin),
           {:ok, receiver} <-
             ensure_member(opts.receiver_username, family.id, :member),
           {:ok, third} <-
             ensure_member(opts.third_username, family.id, :member),
           {:ok, outsider_family} <- ensure_family(opts.outsider_family_name),
           {:ok, outsider} <-
             ensure_member(opts.outsider_username, outsider_family.id, :member),
           {:ok, sender_self} <- Self.get_or_create(sender.id),
           {:ok, receiver_self} <- Self.get_or_create(receiver.id),
           {:ok, direct} <-
             ConversationService.create_direct_conversation(
               sender.id,
               receiver.id
             ),
           {:ok, group} <-
             ensure_group_conversation(
               sender.id,
               family.id,
               [sender.id, receiver.id, third.id],
               opts.group_name
             ),
           {:ok, family_conversation} <- ensure_family_conversation(family.id),
           {:ok, sender_session_primary} <-
             start_session(sender, "sender-primary"),
           {:ok, sender_session_secondary} <-
             start_session(sender, "sender-secondary"),
           {:ok, receiver_session} <- start_session(receiver, "receiver"),
           {:ok, third_session} <- start_session(third, "third"),
           {:ok, outsider_session} <- start_session(outsider, "outsider") do
        now =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        %{
          environment: to_string(Application.get_env(:famichat, :environment)),
          generated_at: now,
          families: %{
            primary: %{id: family.id, name: family.name},
            outsider: %{id: outsider_family.id, name: outsider_family.name}
          },
          actors: %{
            a_tab1: actor_payload(sender, sender_session_primary, "A-tab1"),
            a_tab2: actor_payload(sender, sender_session_primary, "A-tab2"),
            a_dev2: actor_payload(sender, sender_session_secondary, "A-dev2"),
            b: actor_payload(receiver, receiver_session, "B"),
            c: actor_payload(third, third_session, "C"),
            outsider: actor_payload(outsider, outsider_session, "O")
          },
          conversations: %{
            self_sender: %{
              type: "self",
              id: sender_self.id,
              topic: "message:self:#{sender.id}"
            },
            self_receiver: %{
              type: "self",
              id: receiver_self.id,
              topic: "message:self:#{receiver.id}"
            },
            direct: conversation_payload(:direct, direct.id),
            group: conversation_payload(:group, group.id),
            family: conversation_payload(:family, family_conversation.id)
          },
          endpoints: %{
            broadcast: "/api/v1/conversations/:id/messages",
            message_history: "/api/v1/conversations/:id/messages",
            websocket: "/socket/websocket?vsn=2.0.0"
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

  defp ensure_group_conversation(
         creator_id,
         family_id,
         participant_ids,
         group_name
       ) do
    existing_query =
      from c in Conversation,
        where: c.family_id == ^family_id and c.conversation_type == :group,
        where: fragment("?->>'name' = ?", c.metadata, ^group_name),
        order_by: [asc: c.inserted_at],
        limit: 1

    case Repo.one(existing_query) do
      %Conversation{} = conversation ->
        with :ok <- ensure_group_participants(conversation.id, participant_ids) do
          {:ok, Repo.preload(conversation, :explicit_users)}
        end

      nil ->
        with {:ok, conversation} <-
               ConversationService.create_group_conversation(
                 creator_id,
                 family_id,
                 group_name,
                 %{}
               ),
             :ok <- ensure_group_participants(conversation.id, participant_ids) do
          {:ok, Repo.preload(conversation, :explicit_users)}
        end
    end
  end

  defp ensure_group_participants(conversation_id, participant_ids) do
    participant_ids
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn user_id, :ok ->
      case Repo.get_by(ConversationParticipant,
             conversation_id: conversation_id,
             user_id: user_id
           ) do
        %ConversationParticipant{} ->
          {:cont, :ok}

        nil ->
          changeset =
            ConversationParticipant.changeset(%ConversationParticipant{}, %{
              conversation_id: conversation_id,
              user_id: user_id
            })

          case Repo.insert(changeset) do
            {:ok, _participant} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_family_conversation(family_id) do
    query =
      from c in Conversation,
        where: c.family_id == ^family_id and c.conversation_type == :family,
        order_by: [asc: c.inserted_at],
        limit: 1

    case Repo.one(query) do
      %Conversation{} = conversation ->
        {:ok, conversation}

      nil ->
        %Conversation{}
        |> Conversation.create_changeset(%{
          family_id: family_id,
          conversation_type: :family,
          metadata: %{"name" => "Family"}
        })
        |> Repo.insert()
    end
  end

  defp start_session(user, label) do
    Sessions.start_session(
      user,
      %{
        id: "runbook-#{label}-#{Ecto.UUID.generate()}",
        user_agent: "famichat.runbook_seed_matrix",
        ip: "127.0.0.1"
      },
      remember_device?: true
    )
  end

  defp actor_payload(user, session, label) do
    %{
      label: label,
      id: user.id,
      username: user.username,
      access_token: session.access_token,
      device_id: session.device_id
    }
  end

  defp conversation_payload(type, conversation_id) do
    type_string = Atom.to_string(type)

    %{
      type: type_string,
      id: conversation_id,
      topic: "message:#{type_string}:#{conversation_id}"
    }
  end
end

# /srv/famichat/backend/lib/famichat/application.ex

```ex
defmodule Famichat.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Can't be a child process for some reason.
    Application.start(:yamerl)

    children = [
      FamichatWeb.Telemetry,
      Famichat.Repo,
      {DNSCluster,
       query: Application.get_env(:famichat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Famichat.PubSub},
      {Finch, name: Famichat.Finch},
      FamichatWeb.Endpoint,
      Famichat.Cache
    ]

    opts = [strategy: :one_for_one, name: Famichat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamichatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

# /srv/famichat/backend/lib/famichat/cache.ex

```ex
defmodule Famichat.Cache do
  @moduledoc """
  Wrapper for caching operations.

  This module provides a unified interface for cache operations, supporting
  bypassing and disabling of the cache. It uses Cachex as the underlying
  cache implementation when enabled.

  The cache can be configured using the `:famichat, :cache` application
  environment variable. Set `[disabled: true]` to disable the cache.
  """

  require Logger
  @cache_name :content_cache

  @doc """
  Returns the child specification for the cache.

  This function is used by supervisors to start the cache process.
  """
  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    cache_opts = Application.get_env(:famichat, :cache, [])

    if disabled?() do
      %{id: __MODULE__, start: {__MODULE__, :start_link_disabled, []}}
    else
      %{
        id: __MODULE__,
        start: {Cachex, :start_link, [@cache_name, cache_opts]}
      }
    end
  end

  @doc """
  Retrieves a value from the cache.

  Returns `{:error, :invalid_key}` if the key is nil, `:cache_bypassed` if
  bypassed, `:cache_disabled` if the cache is disabled, or the cached value.
  """
  @spec get(any(), Keyword.t()) ::
          any() | :cache_bypassed | :cache_disabled | {:error, :invalid_key}
  def get(key, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        result = Cachex.get(@cache_name, key)

        Logger.debug(
          "Cache.get called with key: #{inspect(key)}, result: #{inspect(result)}"
        )

        result
    end
  end

  def put(key, value, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        do_put(key, value, opts)
    end
  end

  defp do_put(key, value, opts) do
    ttl = Keyword.get(opts, :ttl)
    result = put_with_ttl(@cache_name, key, value, ttl)
    result
  end

  defp put_with_ttl(cache, key, value, nil), do: Cachex.put(cache, key, value)

  defp put_with_ttl(cache, key, value, ttl),
    do: Cachex.put(cache, key, value, ttl: ttl)

  @doc """
  Deletes a value from the cache.

  Returns `{:error, :invalid_key}` if the key is nil, `:cache_bypassed` if
  bypassed, `:cache_disabled` if the cache is disabled, or the result of
  Cachex.del.
  """
  @spec delete(any(), Keyword.t()) ::
          any() | :cache_bypassed | :cache_disabled | {:error, :invalid_key}
  def delete(key, opts \\ []) do
    cond do
      is_nil(key) ->
        {:error, :invalid_key}

      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        Cachex.del(@cache_name, key)
    end
  end

  @doc """
  Checks if a key exists in the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.exists?.
  """
  @spec exists?(any(), Keyword.t()) ::
          boolean() | :cache_bypassed | :cache_disabled
  def exists?(key, opts \\ []) do
    cond do
      should_bypass?(opts) ->
        :cache_bypassed

      disabled?() ->
        :cache_disabled

      true ->
        case Cachex.exists?(@cache_name, key) do
          {:ok, exists} -> exists
          _ -> false
        end
    end
  end

  @doc """
  Gets the TTL for a key in the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.ttl.
  """
  @spec ttl(any(), Keyword.t()) :: integer() | :cache_bypassed | :cache_disabled
  def ttl(key, opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.ttl(@cache_name, key)
    end
  end

  @doc """
  Clears all entries from the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.clear.
  """
  @spec clear(Keyword.t()) :: :ok | :cache_bypassed | :cache_disabled
  def clear(opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.clear(@cache_name)
    end
  end

  @doc """
  Busts (deletes) a specific key from the cache.

  Returns `:cache_bypassed` if bypassed, `:cache_disabled` if the cache is
  disabled, or the result of Cachex.del.
  """
  @spec bust(any(), Keyword.t()) :: :ok | :cache_bypassed | :cache_disabled
  def bust(key, opts \\ []) do
    cond do
      should_bypass?(opts) -> :cache_bypassed
      disabled?() -> :cache_disabled
      true -> Cachex.del(@cache_name, key)
    end
  end

  @doc """
  Starts a disabled cache using an Agent.

  This is used when the cache is configured to be disabled.
  """
  @spec start_link_disabled() :: Agent.on_start()
  def start_link_disabled do
    Agent.start_link(fn -> %{} end, name: @cache_name)
  end

  @doc """
  Checks if the cache is disabled based on application configuration.
  """
  @spec disabled?() :: boolean()
  def disabled? do
    Application.get_env(:famichat, :cache, [])[:disabled] == true
  end

  @spec should_bypass?(Keyword.t()) :: boolean()
  defp should_bypass?(opts) do
    Keyword.get(opts, :bypass_cache, false)
  end
end
```

# /srv/famichat/backend/lib/famichat/mailer.ex

```ex
defmodule Famichat.Mailer do
  @moduledoc """
  This module defines Swoosh for your application.
  """

  use Swoosh.Mailer, otp_app: :famichat
end
```

# /srv/famichat/backend/lib/famichat/release.ex

```ex
defmodule Famichat.Release do
  @moduledoc """
  This module defines functions that you can run with releases.
  """

  @app :famichat
  alias Famichat.Content
  alias Famichat.Content.FileManagement.Reader
  alias Famichat.Content.Remote.GitRepoSyncer
  require Logger

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Pulls the latest changes from the configured repository.
  """
  def pull_repository do
    repo_url = Application.get_env(:famichat, :content_repo_url)
    local_path = Application.get_env(:famichat, :content_base_path)

    IO.puts("Debug: repo_url = #{inspect(repo_url)}")
    IO.puts("Debug: local_path = #{inspect(local_path)}")

    cond do
      is_nil(repo_url) ->
        raise "Missing configuration for content_repo_url. Ensure CONTENT_REPO_URL environment variable is set."

      is_nil(local_path) ->
        raise "Missing configuration for content_base_path. Check your config files."

      not is_binary(repo_url) ->
        raise "Invalid configuration for content_repo_url: #{inspect(repo_url)}. It should be a string."

      not is_binary(local_path) ->
        raise "Invalid configuration for content_base_path: #{inspect(local_path)}. It should be a string."

      true ->
        do_pull_repository(repo_url, local_path)
    end
  end

  defp do_pull_repository(repo_url, local_path) do
    case GitRepoSyncer.sync_repo(repo_url, local_path) do
      {:ok, _} ->
        Logger.info("Successfully pulled latest changes from the repository.")

      {:error, reason} ->
        Logger.error("Failed to pull repository: #{reason}")
        raise "Failed to pull repository: #{reason}"
    end
  end

  @doc """
  Reads all existing markdown files and updates the database.
  """
  def read_existing_content do
    with :ok <- load_app(),
         {:ok, content_base_path} <- get_content_base_path(),
         {:ok, files} <- list_files(content_base_path) do
      files
      |> Enum.filter(&markdown?/1)
      |> Enum.each(&process_file(Path.join(content_base_path, &1)))
    else
      {:error, reason} ->
        Logger.error("Failed to read existing content: #{inspect(reason)}")
    end
  end

  defp get_content_base_path do
    case Application.get_env(:famichat, :content_base_path) do
      nil ->
        {:error,
         "Missing configuration for content_base_path. Check your config files."}

      path when is_binary(path) ->
        {:ok, path}

      invalid ->
        {:error,
         "Invalid configuration for content_base_path: #{inspect(invalid)}"}
    end
  end

  defp list_files(path) do
    case File.ls(path) do
      {:ok, files} ->
        {:ok, files}

      {:error, reason} ->
        {:error, "Failed to list files in #{path}: #{inspect(reason)}"}
    end
  end

  defp markdown?(file_name) do
    String.ends_with?(file_name, ".md")
  end

  defp process_file(file_path) do
    case Reader.read_markdown_file(file_path) do
      {:ok, content_type, attrs} ->
        case Content.upsert_from_file(content_type, attrs) do
          {:ok, _content} ->
            Logger.info("Successfully upserted content from file: #{file_path}")

          {:error, reason} ->
            Logger.error(
              "Error upserting content from file #{file_path}: #{inspect(reason)}"
            )
        end

      {:error, reason} ->
        Logger.error("Error processing file #{file_path}: #{inspect(reason)}")
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

# /srv/famichat/backend/lib/famichat/chat/user.ex

```ex
defmodule Famichat.Chat.User do
  @moduledoc """
  Schema and changeset for the `User` model.

  Represents a user in the Famichat application.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: Ecto.UUID.t(),
    username: String.t(),
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :username, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t() # Changed t() to __MODULE__.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> unique_constraint(:username)
  end
end
```

# /srv/famichat/backend/lib/famichat/chat/message.ex

```ex
defmodule Famichat.Chat.Message do
  @moduledoc """
  Schema and changeset for the `Message` model.

  Represents a message in a Famichat conversation. Handles different
  message types and validations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type message_type :: :text | :voice | :video | :image | :file | :poke | :reaction | :gif
  @type status :: :sent | :delivered | :read

  @type t :: %__MODULE__{
    id: Ecto.UUID.t(),
    message_type: message_type(),
    content: String.t() | nil,
    media_url: String.t() | nil,
    metadata: map() | nil,
    status: status(),
    sender_id: Ecto.UUID.t(),
    conversation_id: Ecto.UUID.t(),
    sender: Famichat.Chat.User.t() | nil,
    conversation: Famichat.Chat.Conversation.t() | nil,
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @primary_key {:id, :binary_id, autogenerate: true} # Explicit primary key type if needed - defaults to UUID
  schema "messages" do
    field :message_type, Ecto.Enum, values: [:text, :voice, :video, :image, :file, :poke, :reaction, :gif], default: :text # Enum for message types
    field :content, :string # For text messages, maybe captions for media in future
    field :media_url, :string # URL for media (voice, video, image, file) - nullable for text messages
    field :metadata, :map # For message-specific metadata (e.g., voice memo duration, reaction type)
    field :status, Ecto.Enum, values: [:sent, :delivered, :read], default: :sent # Message delivery status

    belongs_to :sender, Famichat.Chat.User, foreign_key: :sender_id # Sender of the message
    belongs_to :conversation, Famichat.Chat.Conversation, foreign_key: :conversation_id # Conversation message belongs to

    timestamps()
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t() # Changed t() to __MODULE__.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message_type, :content, :media_url, :metadata, :status, :sender_id, :conversation_id])
    |> validate_required([:message_type, :sender_id, :conversation_id])
    |> validate_inclusion(:message_type, [:text, :voice, :video, :image, :file, :poke, :reaction, :gif])
    |> validate_required([:content], where: [message_type: :text]) # Ensure content is present for text messages
    |> validate_length(:content, min: 1, where: [message_type: :text]) # Ensure content is not empty for text messages
  end
end
```

# /srv/famichat/backend/lib/famichat/chat/message_service.ex

```ex
defmodule Famichat.Chat.MessageService do
  @moduledoc """
  Provides the core message sending functionality for Famichat.

  This service module encapsulates the logic for sending messages,
  handling validations, and interacting with the database to persist messages.
  """
  alias Famichat.Repo
  alias Famichat.Chat
  alias Famichat.Chat.Message

  @doc """
  Sends a text message.

  Receives sender_id, conversation_id, and message content,
  creates a new message, and inserts it into the database.

  ## Returns
  - `{:ok, message}` on successful message creation, where `message` is the inserted `Famichat.Chat.Message` struct.
  - `{:error, changeset}` on validation errors, where `changeset` is an `Ecto.Changeset` struct containing error information.
  """
  @spec send_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: {:ok, Message.t()} | {:error, Ecto.Changeset.t()}
  def send_message(sender_id, conversation_id, content) do
    message_params = %{
      sender_id: sender_id,
      conversation_id: conversation_id,
      content: content,
      message_type: :text # For Level 1, we only send text messages
    }

    %Message{}
    |> Message.changeset(message_params)
    |> Repo.insert()
  end
end
```

# /srv/famichat/backend/lib/famichat/chat/conversation.ex

```ex
defmodule Famichat.Chat.Conversation do
  @moduledoc """
  Schema and changeset for the `Conversation` model.

  Represents a conversation between users in Famichat.  Supports
  different conversation types (direct, group, self) and user associations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
    id: Ecto.UUID.t(),
    conversation_type: :direct | :group | :self,
    metadata: map(),
    messages: [Famichat.Chat.Message.t()] | nil,
    users: [Famichat.Chat.User.t()] | nil,
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "conversations" do
    field :conversation_type, Ecto.Enum, values: [:direct, :group, :self], default: :direct  # Enum for conversation types
    field :metadata, :map # For future metadata (e.g., group chat name, etc.)

    has_many :messages, Famichat.Chat.Message, foreign_key: :conversation_id
    many_to_many :users, Famichat.Chat.User, join_through: "conversation_users" # Explicit many-to-many for users

    timestamps()
  end

  @doc false
  @spec changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t() # Changed t() to __MODULE__.t()
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:conversation_type, :metadata])
    |> validate_required([:conversation_type]) # conversation_type will always be set, but good to have
    |> cast_assoc(:users, with: &user_changeset/2) # Ensure users association is handled correctly if needed in changeset
  end

  @doc false
  @spec user_changeset(Chat.User.t(), map()) :: Ecto.Changeset.t()
  defp user_changeset(user, attrs) do #Dummy user changeset, adapt if needed for associations
    user
    |> Famichat.Chat.User.changeset(attrs) # assuming User has its own changeset
  end
end
```

# /srv/famichat/backend/lib/famichat/logger_formatter.ex

```ex
defmodule Famichat.LoggerFormatter do
  @moduledoc """
  A custom logger formatter for the Famichat application.

  This formatter is responsible for formatting log messages in a specific format that is consistent with the application's logging requirements.
  """

  @doc """
  Formats a log message.

  The formatter takes the following arguments:
    - level: The log level of the message (e.g., :debug, :info, :warn, :error)
    - message: The log message to be formatted
    - timestamp: The timestamp of the log message
    - metadata: Additional metadata associated with the log message

  The formatter returns a formatted log message as a string.
  """
  def format(level, message, timestamp, metadata) do
    [
      format_timestamp(timestamp),
      format_level(level),
      format_module(metadata),
      format_message(message),
      format_metadata_inline(metadata),
      "\n"
    ]
    |> IO.ANSI.format()
  end

  defp format_timestamp(
         {{_year, _month, _day}, {hour, minute, second, millisecond}}
       ) do
    formatted_time =
      :io_lib.format("~2..0B:~2..0B:~2..0B.~3..0B", [
        hour,
        minute,
        second,
        millisecond
      ])

    [:cyan, "#{formatted_time} "]
  end

  defp format_level(level) do
    color =
      case level do
        :debug -> :green
        :info -> :blue
        :warn -> :yellow
        :warning -> :yellow
        :error -> :red
        _ -> :normal
      end

    [color, "[#{String.upcase(to_string(level))}] "]
  end

  defp format_module(metadata) do
    case Keyword.get(metadata, :module) do
      nil -> ""
      module -> [:magenta, "[#{inspect(module)}]\n"]
    end
  end

  defp format_message(message) do
    [:bright, "  #{message}\n"]
  end

  defp format_metadata_inline(metadata) do
    function = format_function(metadata)
    line = Keyword.get(metadata, :line, "")
    request_id = Keyword.get(metadata, :request_id, "")

    [
      :faint,
      "  #{function}",
      (line != "" && ", Line #{line}") || "",
      (request_id != "" && ", Request: #{request_id}") || ""
    ]
  end

  defp format_function(metadata) do
    case Keyword.get(metadata, :function) do
      [name, "/", arity] -> "#{name}/#{arity}"
      other -> inspect(other)
    end
  end
end
```

# /srv/famichat/backend/lib/famichat/chat.ex

```ex
defmodule Famichat.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias Famichat.Repo

  alias Famichat.Chat.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
```

# /srv/famichat/backend/lib/famichat/repo.ex

```ex
defmodule Famichat.Repo do
  use Ecto.Repo,
    otp_app: :famichat,
    adapter: Ecto.Adapters.Postgres
end
```

# /srv/famichat/flutter/famichat/pubspec.yaml

```yaml
name: famichat
description: A minimal Flutter project to test connectivity with the Famichat Phoenix backend.
publish_to: "none"

environment:
  sdk: ">=2.17.0 <3.0.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - "config/app_settings.json"```

# /srv/famichat/flutter/famichat/analysis_options.yaml

```yaml
# This file configures the analyzer, which statically analyzes Dart code to
# check for errors, warnings, and lints.
#
# The issues identified by the analyzer are surfaced in the UI of Dart-enabled
# IDEs (https://dart.dev/tools#ides-and-editors). The analyzer can also be
# invoked from the command line by running `flutter analyze`.

# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
include: package:flutter_lints/flutter.yaml

linter:
  # The lint rules applied to this project can be customized in the
  # section below to disable rules from the `package:flutter_lints/flutter.yaml`
  # included above or to enable additional rules. A list of all available lints
  # and their documentation is published at https://dart.dev/lints.
  #
  # Instead of disabling a lint rule for the entire project in the
  # section below, it can also be suppressed for a single line of code
  # or a specific dart file by using the `// ignore: name_of_lint` and
  # `// ignore_for_file: name_of_lint` syntax on the line or in the file
  # producing the lint.
  rules:
    # avoid_print: false  # Uncomment to disable the `avoid_print` rule
    # prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule

# Additional information about this file can be found at
# https://dart.dev/guides/language/analysis-options
```

# /srv/famichat/flutter/famichat/lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FamichatApp());
}

class FamichatApp extends StatefulWidget {
  const FamichatApp({super.key});

  @override
  State<FamichatApp> createState() => _FamichatAppState();
}

class _FamichatAppState extends State<FamichatApp> {
  String appTitle = 'Loading...';
  String apiUrl = 'http://127.0.0.1:4000/api/placeholder';

  @override
  void initState() {
    super.initState();
    _printAssetManifest();
    _loadConfig();
  }

  Future<void> _printAssetManifest() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      print('AssetManifest.json contents:\n$manifestContent');
    } catch (e) {
      print('Error loading AssetManifest.json: $e');
    }
  }

  Future<void> _loadConfig() async {
    final jsonString = await rootBundle.loadString('config/app_settings.json');
    final config = json.decode(jsonString);

    setState(() {
      appTitle = config['appTitle'] as String? ?? 'Famichat';
      apiUrl = config['apiUrl'] as String? ?? 'http://127.0.0.1:8001/api/v1/hello';
      print('API URL loaded from config: $apiUrl');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HelloScreen(apiUrl: apiUrl, title: appTitle),
    );
  }
}

class HelloScreen extends StatefulWidget {
  final String apiUrl;
  final String title;

  const HelloScreen({super.key, required this.apiUrl, required this.title});

  @override
  State<HelloScreen> createState() => _HelloScreenState();
}

class _HelloScreenState extends State<HelloScreen> {
  String message = 'Loading...';

  @override
  void initState() {
    super.initState();
    fetchGreeting();
  }

  Future<void> fetchGreeting() async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8001/api/v1/hello'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        setState(() {
          message = jsonResponse['message'] ?? 'No message received';
        });
      } else {
        setState(() {
          message = 'Error: ${response.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      print('Network error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        message = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchGreeting,
          ),
        ],
      ),
      body: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
} ```

# /srv/famichat/project-docs/done.md

```md
Level 1: Foundation - Basic Direct Message Sending (Text Only)

    "Done" Definition:
        Schema: Conversation and Message schemas are set up (as we've discussed). Migrations are run and database is updated.
        Service Modules:
            Famichat.Chat.MessageService module is created.
            MessageService includes a function send_message(sender_id, conversation_id, content) that:
                Creates a new Message record in the database of message_type: :text.
                Returns {:ok, message} on success, or {:error, changeset} on validation failure.
            Basic changeset validation in Message schema for sender_id, conversation_id, and content (for :text type).
        Testing:
            Unit tests for MessageService.send_message:
                Test successful message creation.
                Test validation errors (e.g., missing sender_id, conversation_id, empty content).
        Scope: Focus only on sending text messages in direct conversations. Assume conversations and users exist (seed data or manual setup). No message retrieval yet, no conversation listing, no self-messages, no statuses beyond initial creation.

Level 2: Message Retrieval - Get Messages in a Conversation

    "Done" Definition (Builds on Level 1):
        Service Modules:
            MessageService module is updated to include get_conversation_messages(conversation_id) function.
            get_conversation_messages function:
                Retrieves all messages for a given conversation_id from the database, ordered by inserted_at (or timestamp if you add one).
                Returns {:ok, messages} on success, or {:error, :not_found} if the conversation doesn't exist (optional error handling for MVP, could also just return empty list if no messages found).
        Testing:
            Unit tests for MessageService.get_conversation_messages:
                Test successful retrieval of messages for a conversation.
                Test case with no messages in a conversation (should return empty list or :ok, []).
                (Optional for MVP Level 2) Test case where conversation doesn't exist (return :error, :not_found or handle gracefully).
        Scope: Focus on retrieving messages for existing direct conversations. Still text messages only. No conversation creation, no listing, no self-messages.

Level 3: Conversation Creation - Start Direct Conversations

    "Done" Definition (Builds on Level 2):
        Service Modules:
            Famichat.Chat.ConversationService module is created.
            ConversationService includes a function create_direct_conversation(user1_id, user2_id):
                Creates a new Conversation record in the database of conversation_type: :direct.
                Associates user1_id and user2_id with this new conversation using the conversation_users join table.
                Handles cases where a direct conversation already exists between these two users (either return the existing one or prevent creation and return error - decide desired behavior). For MVP, let's say we return the existing conversation if one exists between the same user pair (order doesn't matter, user A & B is same as user B & A).
                Returns {:ok, conversation} on success, or {:error, changeset} or {:error, :already_exists} on failure.
        Testing:
            Unit tests for ConversationService.create_direct_conversation:
                Test successful creation of a new direct conversation between two users.
                Test case where a conversation already exists between the same two users (should return the existing conversation).
                Test validation errors (if any for conversation creation itself at this stage - maybe for future metadata).
        Scope: Focus on creating direct conversations. Message sending and retrieval from Level 1 & 2 should still work. No conversation listing, no self-messages.

Level 4: List User Conversations - Get User's Direct Conversations

    "Done" Definition (Builds on Level 3):
        Service Modules:
            ConversationService module is updated to include list_user_conversations(user_id):
                Retrieves all direct conversations that a given user_id is a participant in (using the conversation_users join table).
                Returns {:ok, conversations}. Could return an empty list if the user has no conversations yet.
        Testing:
            Unit tests for ConversationService.list_user_conversations:
                Test successful retrieval of a list of direct conversations for a user.
                Test case where a user has no direct conversations (should return empty list).
                Test that it only returns direct conversations and not other types (if we introduce other types later).
        Scope: Focus on listing direct conversations for a user. All previous levels' functionality should remain working. No self-messages yet.

Level 5: Self-Messages - Basic Support

    "Done" Definition (Builds on Level 4):
        Service Modules:
            MessageService is extended to handle conversation_type: :self. send_message should now work for self-conversations too.
            ConversationService is extended to include create_self_conversation(user_id):
                Creates a Conversation of conversation_type: :self associated with a single user_id. We need to decide how self-conversations are modeled - maybe a direct conversation with the same user ID as both participants? Or a special type? Let's go with a special type conversation_type: :self for clarity.
                list_user_conversations might need to be updated to optionally include self-conversations or have a separate list_user_self_conversations function if we want to distinguish them in the UI later. For now, let's have list_user_conversations return only direct conversations and have a separate list_user_self_conversations.
        Testing:
            Unit tests for MessageService.send_message extended to test with conversation_type: :self.
            Unit tests for ConversationService.create_self_conversation.
            Unit tests for ConversationService.list_user_self_conversations.
        Scope: Adding basic self-message functionality. Direct messages and listing from previous levels remain. No message statuses beyond creation yet.

Level 6: Basic Message Status - "Sent" Status

    "Done" Definition (Builds on Level 5):
        Schema: Message schema already has status field. Ensure it defaults to :sent.
        Service Modules:
            MessageService.send_message should, by default, create messages with status: :sent. No explicit changes needed in function logic likely, just verify in testing.
        Testing:
            Unit tests for MessageService.send_message to verify that created messages have status: :sent.
        Scope: Implementing the "sent" message status. All previous levels' functionality remains. No "delivered" or "read" statuses yet.

Level 7: Refinement, Testing, and Documentation - MVP Backend Complete

    "Done" Definition (Builds on Level 6):
        Code Review: Review all code in Famichat.Chat context for clarity, maintainability, and adherence to best practices.
        Error Handling: Ensure proper error handling and logging in service modules.
        Validation: Double-check all input validation in changesets and service functions.
        Comprehensive Testing: Write integration tests (if feasible at this backend-only stage, maybe unit tests that test interactions between services) to ensure all levels work together as expected. Ensure good test coverage for all service functions.
        Documentation: Add basic documentation to service modules and functions (using @doc in Elixir).
        MVP Backend Functionality Complete: Levels 1-7 represent the core backend chat functionality for the MVP (Direct Messages, Self-Messages, Text messages, basic listing, "sent" status).```


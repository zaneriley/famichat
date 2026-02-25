defmodule Famichat.Chat.MessageRateLimiter do
  @moduledoc false

  use GenServer

  @table :chat_send_rate_limiter
  @cleanup_interval_ms :timer.seconds(30)

  @default_windows [
    %{bucket: :msg_device_burst, key: [:device_id], limit: 20, interval: 10},
    %{
      bucket: :msg_device_sustained,
      key: [:device_id],
      limit: 120,
      interval: 60
    }
  ]

  @type window :: %{
          bucket: atom(),
          key: [atom()],
          limit: pos_integer(),
          interval: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec check(map(), Ecto.UUID.t()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  def check(message_params, device_id)
      when is_map(message_params) and is_binary(device_id) do
    sender_id =
      Map.get(message_params, :sender_id) ||
        Map.get(message_params, "sender_id")

    conversation_id =
      Map.get(message_params, :conversation_id) ||
        Map.get(message_params, "conversation_id")

    subject = %{
      sender_id: sender_id,
      conversation_id: conversation_id,
      device_id: device_id
    }

    if valid_subject?(subject) do
      ensure_table!()
      do_check(subject)
    else
      :ok
    end
  end

  def check(_message_params, _device_id), do: :ok

  @doc false
  @spec window_limit(atom()) :: pos_integer() | nil
  def window_limit(bucket) when is_atom(bucket) do
    configured_windows()
    |> Enum.find_value(fn %{bucket: configured_bucket, limit: limit} ->
      if configured_bucket == bucket, do: limit
    end)
  end

  @doc false
  @spec reset_for_test() :: :ok
  def reset_for_test do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete_all_objects(@table)
        :ok
    end
  end

  @impl true
  def init(_opts) do
    ensure_table!()
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_windows()
    schedule_cleanup()
    {:noreply, state}
  end

  defp do_check(subject) do
    Enum.reduce_while(configured_windows(), :ok, fn window, :ok ->
      case check_window(window, subject) do
        :ok ->
          {:cont, :ok}

        {:error, {:rate_limited, _retry_in}} = error ->
          {:halt, error}
      end
    end)
  end

  @spec check_window(window(), map()) ::
          :ok | {:error, {:rate_limited, pos_integer()}}
  defp check_window(window, subject) do
    case :ets.whereis(@table) do
      :undefined ->
        ensure_table!()

        case :ets.whereis(@table) do
          :undefined -> :ok
          _ -> do_check_window(window, subject)
        end

      _ ->
        do_check_window(window, subject)
    end
  end

  defp do_check_window(window, subject) do
    now = System.system_time(:second)
    window_start = now - rem(now, window.interval)
    expires_at = window_start + window.interval
    subject_key = build_subject_key(window.key, subject)
    counter_key = {window.bucket, subject_key, window_start}

    count =
      :ets.update_counter(
        @table,
        counter_key,
        {2, 1},
        {counter_key, 0, expires_at}
      )

    if count <= window.limit do
      :ok
    else
      retry_in = max(1, expires_at - now)

      :telemetry.execute(
        [:famichat, :rate_limiter, :throttled],
        %{count: 1},
        %{bucket: window.bucket}
      )

      {:error, {:rate_limited, retry_in}}
    end
  end

  @spec build_subject_key([atom()], map()) :: term()
  defp build_subject_key(key_fields, subject) do
    values =
      Enum.map(key_fields, fn key_field ->
        Map.fetch!(subject, key_field)
      end)

    case values do
      [single] -> single
      _ -> List.to_tuple(values)
    end
  end

  defp valid_subject?(%{
         sender_id: sender_id,
         device_id: device_id,
         conversation_id: conversation_id
       }) do
    is_binary(sender_id) and is_binary(device_id) and
      is_binary(conversation_id)
  end

  @spec configured_windows() :: [window()]
  defp configured_windows do
    case Application.get_env(:famichat, __MODULE__) do
      nil ->
        @default_windows

      config when is_list(config) ->
        config
        |> Keyword.get(:windows, @default_windows)
        |> normalize_windows()

      config when is_map(config) ->
        config
        |> Map.get(:windows, Map.get(config, "windows", @default_windows))
        |> normalize_windows()

      _ ->
        @default_windows
    end
  end

  @spec normalize_windows(term()) :: [window()]
  defp normalize_windows(windows) when is_list(windows) do
    windows
    |> Enum.map(&normalize_window/1)
    |> Enum.filter(& &1)
  end

  defp normalize_windows(_), do: @default_windows

  @spec normalize_window(term()) :: window() | nil
  defp normalize_window(window) when is_map(window) do
    bucket = Map.get(window, :bucket) || Map.get(window, "bucket")
    key = Map.get(window, :key) || Map.get(window, "key")
    limit = Map.get(window, :limit) || Map.get(window, "limit")
    interval = Map.get(window, :interval) || Map.get(window, "interval")

    if is_atom(bucket) and is_list(key) and key != [] and
         is_integer(limit) and limit > 0 and
         is_integer(interval) and interval > 0 do
      %{bucket: bucket, key: key, limit: limit, interval: interval}
    else
      nil
    end
  end

  defp normalize_window(_), do: nil

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defp cleanup_expired_windows do
    now = System.system_time(:second)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}
    ])

    :ok
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end

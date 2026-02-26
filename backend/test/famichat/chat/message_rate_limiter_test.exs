defmodule Famichat.Chat.MessageRateLimiterTest do
  use ExUnit.Case, async: false

  alias Famichat.Chat.MessageRateLimiter

  setup do
    original_config = Application.get_env(:famichat, MessageRateLimiter)
    MessageRateLimiter.reset_for_test()

    on_exit(fn ->
      MessageRateLimiter.reset_for_test()

      if is_nil(original_config) do
        Application.delete_env(:famichat, MessageRateLimiter)
      else
        Application.put_env(:famichat, MessageRateLimiter, original_config)
      end
    end)

    :ok
  end

  test "exposes configured user sustained window" do
    assert MessageRateLimiter.window_limit(:msg_user_sustained) == 180
  end

  test "fails closed when limiter subject is invalid" do
    assert {:error, {:rate_limited, retry_in}} =
             MessageRateLimiter.check(%{}, "device-1")

    assert retry_in > 0

    assert {:error, {:rate_limited, retry_in}} =
             MessageRateLimiter.check(%{"sender_id" => "", "conversation_id" => "c1"}, "device-1")

    assert retry_in > 0
    assert {:error, {:rate_limited, _retry_in}} = MessageRateLimiter.check(:not_a_map, "device-1")
  end

  test "applies sustained limits across devices for the same sender" do
    Application.put_env(:famichat, MessageRateLimiter,
      windows: [
        %{bucket: :msg_device_burst, key: [:device_id], limit: 100, interval: 60},
        %{bucket: :msg_device_sustained, key: [:device_id], limit: 100, interval: 60},
        %{bucket: :msg_user_sustained, key: [:sender_id], limit: 3, interval: 60}
      ]
    )

    params = %{"sender_id" => "user-1", "conversation_id" => "conversation-1"}

    assert :ok = MessageRateLimiter.check(params, "device-a")
    assert :ok = MessageRateLimiter.check(params, "device-b")
    assert :ok = MessageRateLimiter.check(params, "device-c")

    assert {:error, {:rate_limited, retry_in}} =
             MessageRateLimiter.check(params, "device-d")

    assert retry_in > 0
  end
end

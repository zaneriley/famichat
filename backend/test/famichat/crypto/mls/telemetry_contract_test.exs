defmodule Famichat.Crypto.MLS.TelemetryContractTest do
  use ExUnit.Case, async: false

  alias Famichat.Crypto.MLS
  alias Famichat.TestSupport.MLS.FakeAdapter

  @telemetry_timeout 2_000

  setup do
    previous_adapter = Application.get_env(:famichat, :mls_adapter)
    Application.put_env(:famichat, :mls_adapter, FakeAdapter)

    parent = self()
    ref = make_ref()

    handler_name =
      "mls-telemetry-contract-#{System.unique_integer([:positive])}"

    operations = [
      :create_application_message,
      :process_incoming,
      :mls_commit,
      :mls_update,
      :mls_add,
      :mls_remove
    ]

    events =
      Enum.flat_map(operations, fn operation ->
        [
          [:famichat, :crypto, :mls, operation, :start],
          [:famichat, :crypto, :mls, operation, :stop]
        ]
      end)

    :ok =
      :telemetry.attach_many(
        handler_name,
        events,
        fn event_name, _measurements, metadata, _config ->
          send(parent, {:telemetry_event, ref, event_name, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(handler_name)
      restore_env(:mls_adapter, previous_adapter)
    end)

    {:ok, ref: ref}
  end

  test "emits telemetry spans for core MLS message and lifecycle operations",
       %{ref: ref} do
    assert {:ok, _} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "hello"
             })

    assert {:ok, _} =
             MLS.process_incoming(%{
               group_id: "group-1",
               ciphertext: "ciphertext:hello"
             })

    assert {:ok, _} = MLS.mls_commit(%{group_id: "group-1"})
    assert {:ok, _} = MLS.mls_update(%{group_id: "group-1"})
    assert {:ok, _} = MLS.mls_add(%{group_id: "group-1"})

    assert {:ok, _} =
             MLS.mls_remove(%{group_id: "group-1", remove_target: "recipient"})

    assert_stop_event(ref, :create_application_message, :ok)
    assert_stop_event(ref, :process_incoming, :ok)
    assert_stop_event(ref, :mls_commit, :ok)
    assert_stop_event(ref, :mls_update, :ok)
    assert_stop_event(ref, :mls_add, :ok)
    assert_stop_event(ref, :mls_remove, :ok)
  end

  test "encryption failures expose error code without leaking sensitive fields",
       %{ref: ref} do
    assert {:error, :crypto_failure, details} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "hello",
               force_error: :crypto_failure,
               error_details: %{
                 plaintext: "sensitive",
                 ciphertext: "sensitive",
                 key_material: "sensitive"
               }
             })

    refute Map.has_key?(details, :plaintext)
    refute Map.has_key?(details, :ciphertext)
    refute Map.has_key?(details, :key_material)

    assert_receive {:telemetry_event, ^ref,
                    [
                      :famichat,
                      :crypto,
                      :mls,
                      :create_application_message,
                      :stop
                    ], metadata},
                   @telemetry_timeout

    assert metadata[:result] == :error
    assert metadata[:error_code] == :crypto_failure
    refute Map.has_key?(metadata, :plaintext)
    refute Map.has_key?(metadata, :ciphertext)
    refute Map.has_key?(metadata, :key_material)
  end

  test "nested sensitive fields are redacted from error details and telemetry",
       %{ref: ref} do
    assert {:error, :crypto_failure, details} =
             MLS.create_application_message(%{
               group_id: "group-1",
               body: "hello",
               force_error: :crypto_failure,
               error_details: %{
                 reason: "nested-leak-check",
                 nested: %{
                   plaintext: "secret",
                   allowed: "ok",
                   deep: %{"ciphertext" => "secret-2", "safe" => "ok-2"}
                 },
                 events: [
                   %{key_material: "never"},
                   %{"private_key" => "never", "note" => "keep"}
                 ]
               }
             })

    assert details[:reason] == "nested-leak-check"
    assert details[:nested][:allowed] == "ok"
    assert details[:nested][:deep]["safe"] == "ok-2"
    assert Enum.at(details[:events], 1)["note"] == "keep"

    refute Map.has_key?(details[:nested], :plaintext)
    refute Map.has_key?(details[:nested][:deep], "ciphertext")
    refute Map.has_key?(Enum.at(details[:events], 0), :key_material)
    refute Map.has_key?(Enum.at(details[:events], 1), "private_key")

    assert_receive {:telemetry_event, ^ref,
                    [
                      :famichat,
                      :crypto,
                      :mls,
                      :create_application_message,
                      :stop
                    ], metadata},
                   @telemetry_timeout

    assert metadata[:result] == :error
    assert metadata[:error_code] == :crypto_failure
    refute Map.has_key?(metadata, :nested)
    refute Map.has_key?(metadata, :events)
  end

  defp assert_stop_event(ref, operation, expected_result) do
    assert_receive {:telemetry_event, ^ref,
                    [:famichat, :crypto, :mls, ^operation, :stop], metadata},
                   @telemetry_timeout

    assert metadata[:result] == expected_result
  end

  defp restore_env(key, nil), do: Application.delete_env(:famichat, key)
  defp restore_env(key, value), do: Application.put_env(:famichat, key, value)
end

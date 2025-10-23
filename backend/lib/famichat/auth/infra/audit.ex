defmodule Famichat.Auth.Infra.Audit do
  @moduledoc """
  Placeholder audit logger for authentication flows.
  """

  @typedoc "Audit event metadata."
  @type record :: %{
          event: String.t(),
          actor_id: Ecto.UUID.t() | nil,
          subject_id: Ecto.UUID.t() | nil,
          family_id: Ecto.UUID.t() | nil,
          context: map()
        }

  @doc """
  Placeholder audit recorder.
  """
  @spec record(String.t(), keyword()) :: :ok
  def record(_event, _opts \\ []) do
    :ok
  end
end
